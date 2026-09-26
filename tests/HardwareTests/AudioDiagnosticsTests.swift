import Testing
import AVFoundation
import CoreAudio
@testable import CodeXMicroApp

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMICRO_TONE_SPEAKER_TEST"] == "1"))
func diagnosticSpeakerPlaybackCompletes() async throws {
    let device = try #require(SystemAudioDevices.devices().first {
        $0.transport == kAudioDeviceTransportTypeBuiltIn && $0.outputChannels > 0
    })
    let diagnostics = AudioDiagnostics()
    defer { diagnostics.stop() }
    diagnostics.testOutput(device)
    for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(100))
        if !diagnostics.running { break }
    }
    #expect(!diagnostics.running)
    #expect(diagnostics.result.contains("测试音播放完成"))
    print("Physical output completion: \(diagnostics.result)")
}

@MainActor @Test func diagnosticFullBufferRendersWithoutRefillGaps() throws {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let tone = AudioDiagnosticSignal.buffer()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: tone.format)
    try engine.enableManualRenderingMode(.offline, format: tone.format, maximumFrameCount: 512)
    player.scheduleBuffer(tone)
    try engine.start(); player.play()
    defer { player.stop(); engine.stop() }
    let output = AVAudioPCMBuffer(pcmFormat: tone.format, frameCapacity: 512)!
    var samples: [Float] = []
    for _ in 0..<94 {
        #expect(try engine.renderOffline(512, to: output) == .success)
        samples.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
    let reference = AudioDiagnosticSignal.samples(start: 0, count: 48_000)
    let error = zip(samples.prefix(48_000), reference).map { abs($0 - $1) }.max()!
    #expect(error < 0.00001)
    let jump = zip(samples.dropFirst(), samples).map { abs($0 - $1) }.max()!
    #expect(jump < 0.005)
    print("Scheduled tone: 48000 frames, max sample error=\(error), max adjacent step=\(jump)")
}

@Test func diagnosticToneIsBoundedFiniteAndFades() {
    let samples = AudioDiagnosticSignal.samples(start: 0, count: 48_000)
    #expect(samples.count == 48_000)
    #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.08001 })
    #expect(samples[0] == 0)
    #expect(abs(samples.last!) < 0.001)
    #expect(samples.contains { abs($0) > 0.07 })
}

/// Models a 512-frame render arriving after the current 480-frame refill.
/// This diagnostic documents an underrun risk; it is not a speaker recording.
@Test func diagnosticSmallRefillCanIntroduceDiscontinuity() {
    var ring = AudioSampleRing()
    let packet = AudioDiagnosticSignal.samples(start: 4800, count: 480)
    ring.append(packet)
    let rendered = (0..<512).map { _ in ring.pop() }
    #expect(rendered.suffix(32).allSatisfy { $0 == 0 })
    let jump = abs(rendered[479] - rendered[480])
    #expect(jump > 0.04)
    print("Tone refill diagnostic: 480 supplied / 512 requested; 32 zero-filled frames; discontinuity=\(jump)")
}
