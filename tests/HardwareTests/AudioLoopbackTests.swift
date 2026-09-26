import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import CodeXMicroApp

private final class LoopbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    func fail(_ message: String) { lock.lock(); failure = message; lock.unlock() }
    func error() -> String? { lock.lock(); defer { lock.unlock() }; return failure }

}

/// Opt-in: sends a synthetic signal ONLY to a virtual device, then reads it back.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMICRO_LOOPBACK_TEST"] == "1"))
func virtualMixSignalReturnsThroughDriverAndOutputMuteWorks() async throws {
    let microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
    print("Loopback test microphone authorization: \(microphoneAuthorization.rawValue)")
    try #require(microphoneAuthorization == .authorized, "The test runner needs macOS microphone permission to read the virtual driver")
    let device = try #require(SystemAudioDevices.devices().first { $0.name == "vRemoteDr 2ch" && $0.inputChannels > 0 })
    let levels = AudioInputLevels()
    let probe = LoopbackProbe()
    let capture = AudioDeviceCapture(uid: device.uid, destinations: [], levels: levels, onError: { probe.fail($0) })
    capture.start()
    defer { capture.stop() }
    let writer = try AudioMixOutput(device: device, inputs: ["test": .init(gain: 0.5)], output: .init())
    defer { writer.stop() }
    let signal = (0..<480).map { Float(sin(Double($0) * 2 * .pi * 1000 / 48000)) * 0.2 }
    var audible: Float = 0
    for _ in 0..<200 {
        writer.state.push(signal, source: "test")
        try await Task.sleep(for: .milliseconds(10))
        audible = levels.snapshot()[device.uid] ?? 0
        if audible > 0.01 { break }
    }
    #expect(probe.error() == nil)
    #expect(audible > 0.01 && audible < 0.15)
    writer.state.configure(inputs: ["test": .init()], output: .init(muted: true))
    var muted: Float = -1
    for _ in 0..<200 {
        writer.state.push(signal, source: "test")
        try await Task.sleep(for: .milliseconds(10))
        muted = levels.snapshot()[device.uid] ?? -1
        if muted >= 0 && muted < 0.001 { break }
    }
    #expect(probe.error() == nil)
    #expect(muted >= 0 && muted < 0.001)
    print("Virtual driver round trip: signal RMS=\(audible), muted RMS=\(muted)")
}
