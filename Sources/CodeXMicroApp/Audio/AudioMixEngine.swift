import AVFoundation
import CoreAudio
import CoreMedia

/// Every mutable field is guarded by lock; the audio render callback only reads
/// bounded FIFOs and writes the supplied buffers, without dispatching UI work.
final class AudioMixRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: AudioSampleRing]
    private var inputs: [String: AudioMixChannel]
    private var output: AudioMixChannel
    private var peak: Float = 0
    private var playbackEnabled = true
    func setPlaybackEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard playbackEnabled != enabled else { return }
        playbackEnabled = enabled
        queues = inputs.mapValues { _ in AudioSampleRing() }
        peak = 0
    }
    init(inputs: [String: AudioMixChannel], output: AudioMixChannel) {
        self.inputs = inputs; self.output = output
        queues = inputs.mapValues { _ in AudioSampleRing() }
    }
    func configure(inputs: [String: AudioMixChannel], output: AudioMixChannel) {
        lock.lock(); defer { lock.unlock() }
        self.inputs = inputs; self.output = output
    }
    func push(_ samples: [Float], source: String) {
        lock.lock(); defer { lock.unlock() }
        queues[source]?.append(samples)
    }
    func render(frames: Int, buffers: UnsafeMutablePointer<AudioBufferList>) {
        lock.lock(); defer { lock.unlock() }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        for buffer in list {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let soloActive = inputs.values.contains { $0.solo }
        for (uid, channel) in inputs {
            guard var queue = queues[uid] else { continue }
            let gain: Float = channel.muted || (soloActive && !channel.solo) ? 0 : channel.gain
            for index in 0..<frames {
                let sample = queue.pop() * gain
                for buffer in list {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let channels = Int(buffer.mNumberChannels)
                    for channelIndex in 0..<channels where (index * channels + channelIndex + 1) * MemoryLayout<Float>.size <= buffer.mDataByteSize {
                        data[index * channels + channelIndex] += sample
                    }
                }
            }
            queues[uid] = queue
        }
        peak = 0
        for buffer in list {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for index in 0..<min(frames * Int(buffer.mNumberChannels), Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                let sample = output.muted || !playbackEnabled ? 0 : max(-1, min(1, data[index] * output.gain))
                data[index] = sample; peak = max(peak, abs(sample))
            }
        }
    }
    func level() -> Float { lock.lock(); defer { lock.unlock() }; return peak }
}

final class AudioInputLevels: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: (Float, Date)] = [:]
    func record(_ samples: [Float], uid: String) {
        let rms = samples.isEmpty ? 0 : sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
        lock.lock(); values[uid] = (rms, Date()); lock.unlock()
    }
    func snapshot() -> [String: Float] {
        lock.lock(); defer { lock.unlock() }
        return values.mapValues { Date().timeIntervalSince($0.1) < 0.4 ? $0.0 : 0 }
    }
}

/// Session lifecycle, resampler and delegate callbacks all run on one serial queue.
final class AudioDeviceCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue: DispatchQueue
    private var resampler = AudioStreamingResampler()
    private let uid: String
    private let destinations: [AudioMixRenderState]
    private let levels: AudioInputLevels
    private let onError: @Sendable (String) -> Void
    init(uid: String, destinations: [AudioMixRenderState], levels: AudioInputLevels, onError: @escaping @Sendable (String) -> Void) {
        self.uid = uid; self.destinations = destinations; self.levels = levels; self.onError = onError
        queue = DispatchQueue(label: "com.gumu.codexmicro.audio.capture." + uid, qos: .userInteractive)
    }
    func start() {
        queue.async { [self] in
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            guard let device = devices.first(where: { $0.uniqueID == uid }) else { onError("音频输入设备不可采集或已断开：\(uid)"); return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureAudioDataOutput()
                output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1]
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddInput(input), session.canAddOutput(output) else { throw AudioSettingsError.message("无法打开输入：\(device.localizedName)") }
                session.beginConfiguration(); session.addInput(input); session.addOutput(output); session.commitConfiguration()
                session.startRunning()
                if !session.isRunning { onError("输入设备启动失败：\(device.localizedName)") }
            } catch { onError(error.localizedDescription) }
        }
    }
    func stop() {
        queue.async { [self] in
            session.stopRunning()
            for output in session.outputs { (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil) }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM, stream.mBitsPerChannel == 32,
              stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let size = CMBlockBufferGetDataLength(block)
        guard size > 0, size.isMultiple(of: MemoryLayout<Float>.size) else { return }
        var samples = [Float](repeating: 0, count: size / MemoryLayout<Float>.size)
        let result = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
        guard result == kCMBlockBufferNoErr else { return }
        let channels = max(1, Int(stream.mChannelsPerFrame))
        if channels > 1 {
            samples = stride(from: 0, to: samples.count - channels + 1, by: channels).map { start in
                samples[start..<(start + channels)].reduce(0, +) / Float(channels)
            }
        }
        levels.record(samples, uid: uid)
        let normalized = resampler.convert(samples, from: stream.mSampleRate)
        for destination in destinations { destination.push(normalized, source: uid) }
    }
}

@MainActor
final class AudioMixOutput {
    let state: AudioMixRenderState
    private let engine: AVAudioEngine
    init(device: SystemAudioDevice, inputs: [String: AudioMixChannel], output: AudioMixChannel, playbackEnabled: Bool = true) throws {
        state = AudioMixRenderState(inputs: inputs, output: output)
        state.setPlaybackEnabled(playbackEnabled)
        engine = AVAudioEngine()
        guard let audioUnit = engine.outputNode.audioUnit else { throw AudioSettingsError.message("输出不可用：\(device.name)") }
        var deviceID = device.id
        let result = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else { throw AudioSettingsError.message("无法打开输出 \(device.name)（\(result)）") }
        let state = self.state
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        // The audio thread must not inherit this initializer's MainActor isolation.
        let source = AVAudioSourceNode(format: format) { @Sendable _, _, frames, buffers in
            state.render(frames: Int(frames), buffers: buffers); return noErr
        }
        engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
    }
    private var recoveryAttempts = 0
    private var lastRecovery = Date.distantPast
    func recoverAfterDeviceChange() throws {
        if Date().timeIntervalSince(lastRecovery) > 5 { recoveryAttempts = 0 }
        guard recoveryAttempts < 3 else { throw AudioSettingsError.message("设备反复切换音频格式，请检查蓝牙连接。") }
        recoveryAttempts += 1; lastRecovery = Date()
        try engine.start()
    }
    var isRunning: Bool { engine.isRunning }
    func stop() { state.setPlaybackEnabled(false); engine.stop() }
}
