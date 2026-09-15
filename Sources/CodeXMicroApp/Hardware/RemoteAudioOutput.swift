import AVFoundation
import CoreAudio

/// Sends decoded remote PCM to an installed loopback device, never speakers.
/// The user's speech application selects that device as its microphone input.
@MainActor
final class RemoteAudioOutput {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var sampleRate = 0
    private var pendingBuffers = 0
    private var generation = 0
    static func loopbackDevice() -> (AudioDeviceID, String)? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        for device in devices {
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &nameSize, &name) == noErr else { continue }
            guard let name else { continue }
            let value = name.takeUnretainedValue() as String
            if value == "vRemoteDr 2ch" || value == "BlackHole 2ch" { return (device, value) }
        }
        return nil
    }
    func feed(_ samples: [Int16], rate: Int) throws {
        guard !samples.isEmpty else { return }
        if engine == nil || sampleRate != rate { try start(rate: rate) }
        guard pendingBuffers < 80, let player,
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() { channel[i] = max(-1, min(1, Float(sample) / 32768 * 10)) }
        pendingBuffers += 1
        let currentGeneration = generation
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
            }
        }
    }
    private func start(rate: Int) throws {
        stop()
        guard let (device, _) = Self.loopbackDevice() else { throw BridgeError.protocolFailure("未安装虚拟音频设备；请安装 BlackHole 2ch，或使用已有的 vRemoteDr 2ch") }
        let engine = AVAudioEngine()
        guard let unit = engine.outputNode.audioUnit else { throw BridgeError.protocolFailure("音频输出不可用") }
        var deviceID = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw BridgeError.protocolFailure("无法连接虚拟音频设备：\(status)") }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1))
        try engine.start(); player.play()
        self.engine = engine; self.player = player; sampleRate = rate
    }
    func stop() { generation += 1; player?.stop(); engine?.stop(); engine = nil; player = nil; pendingBuffers = 0 }
}
