import AVFoundation
import Combine
import Foundation
import CoreAudio

enum AudioDiagnosticSignal {
    static func buffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        let signal = samples(start: 0, count: 48_000)
        signal.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: source.count)
        }
        return buffer
    }
    static func samples(start: Int, count: Int) -> [Float] {
        (start..<(start + count)).map { index in
            let envelope = min(1, Double(index) / 960) * min(1, Double(max(0, 48_000 - index)) / 960)
            return Float(sin(Double(index) * 2 * .pi * 440 / 48_000) * 0.08 * envelope)
        }
    }
}

/// Schedule the whole tone before playback. UI scheduling never feeds the render thread.
@MainActor final class AudioDiagnosticPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    init(device: SystemAudioDevice, completion: @escaping @Sendable () -> Void) throws {
        guard let unit = engine.outputNode.audioUnit else {
            throw AudioSettingsError.message("输出不可用：\(device.name)")
        }
        var id = device.id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw AudioSettingsError.message("无法打开输出：\(device.name)（\(status)）") }
        let buffer = AudioDiagnosticSignal.buffer()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
        engine.prepare()
        try engine.start()
        player.play()
    }
    func stop() { player.stop(); engine.stop() }
}

@MainActor final class AudioDiagnostics: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var level: Float = 0
    @Published private(set) var result = "输入测试不录音、不回放；输出测试播放 1 秒低电平提示音。"
    private var task: Task<Void, Never>?
    private var capture: AudioDeviceCapture?
    private var output: AudioDiagnosticPlayer?
    private var generation = 0

    func stop() {
        generation += 1; task?.cancel(); task = nil
        capture?.stop(); capture = nil; output?.stop(); output = nil
        running = false; level = 0
    }
    func testInput(_ device: SystemAudioDevice) {
        stop(); running = true
        let token = generation
        result = "正在测试：\(device.name)，请说话（5 秒）…"
        task = Task {
            let permission = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed = permission == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : permission == .authorized
            guard generation == token, !Task.isCancelled else { return }
            guard allowed else { stop(); result = "未获得麦克风权限，请检查系统隐私设置。"; return }
            let meters = AudioInputLevels()
            let capture = AudioDeviceCapture(uid: device.uid, destinations: [], levels: meters) { [weak self] error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.stop(); self.result = error
                }
            }
            self.capture = capture; capture.start()
            var peak: Float = 0
            for _ in 0..<50 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard generation == token else { return }
                level = meters.snapshot()[device.uid] ?? 0
                peak = max(peak, level)
            }
            let received = meters.snapshot()[device.uid] != nil
            stop()
            result = "\(device.name)：" + (peak > 0.0001
                ? "检测到声音，最高电平 \(AudioMeterScale.label(peak))（尚不代表输入法已收到）。"
                : received ? "收到音频数据，但未检测到有效声音；请检查麦克风静音、蓝牙收音及说话距离。"
                : "未收到音频数据；请检查连接、权限或设备占用。")
        }
    }
    func testOutput(_ device: SystemAudioDevice) {
        stop(); running = true
        let token = generation
        result = "正在向 \(device.name) 播放测试音…"
        task = Task {
            do {
                output = try AudioDiagnosticPlayer(device: device) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stop()
                        self.result = "\(device.name)：测试音播放完成。" + (device.isLoopback ? "虚拟设备不会直接出声，请在接收应用检查电平。" : "应听到连续、平稳的提示音；实际听感请确认。")
                    }
                }
                // Only a watchdog; it does not supply or time the audio samples.
                try await Task.sleep(for: .seconds(5))
                guard generation == token else { return }
                stop()
                result = "输出测试超时，请检查设备连接。"
            } catch {
                guard generation == token else { return }
                stop(); result = "输出测试失败：\(error.localizedDescription)"
            }
        }
    }
}
