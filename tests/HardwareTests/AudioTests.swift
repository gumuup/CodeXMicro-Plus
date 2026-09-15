import CoreAudio
import Foundation
import Testing
@testable import CodeXMicroApp

@Test func audioRingBoundsLatencyAndSanitizesSamples() {
    var ring = AudioSampleRing(capacity: 3)
    ring.append([1, 2, 3, 4])
    #expect(ring.count == 3)
    #expect(ring.pop() == 2)
    #expect(ring.pop() == 3)
    #expect(ring.pop() == 4)
    #expect(ring.pop() == 0)
    ring.append([Float.nan, Float.infinity])
    #expect(ring.pop() == 0)
    #expect(ring.pop() == 0)
}

private func rendered(_ state: AudioMixRenderState, frames: Int) -> [Float] {
    var result = [Float](repeating: 0, count: frames)
    result.withUnsafeMutableBytes { bytes in
        var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
        state.render(frames: frames, buffers: &buffers)
    }
    return result
}

@Test func mixActuallySumsSourcesAndHonorsMuteSolo() {
    let channels = ["mac": AudioMixChannel(gain: 0.5), "usb": AudioMixChannel(gain: 1)]
    let mix = AudioMixRenderState(inputs: channels, output: AudioMixChannel())
    mix.push([0.4, 0.6], source: "mac"); mix.push([0.1, 0.2], source: "usb")
    let values = rendered(mix, frames: 2)
    #expect(abs(values[0] - 0.3) < 0.00001)
    #expect(abs(values[1] - 0.5) < 0.00001)
    mix.configure(inputs: ["mac": AudioMixChannel(solo: true), "usb": AudioMixChannel()], output: AudioMixChannel())
    mix.push([0.3], source: "mac"); mix.push([0.8], source: "usb")
    #expect(rendered(mix, frames: 1) == [0.3])
    mix.configure(inputs: ["mac": AudioMixChannel(muted: true), "usb": AudioMixChannel()], output: AudioMixChannel())
    mix.push([0.4], source: "mac"); mix.push([0.2], source: "usb")
    #expect(rendered(mix, frames: 1) == [0.2])
    #expect(rendered(mix, frames: 1) == [0]) // Muted/solo-excluded audio was drained.
}

@Test func outputsHaveIndependentGainMuteAndClipping() {
    let a = AudioMixRenderState(inputs: ["mic": AudioMixChannel()], output: AudioMixChannel(gain: 2))
    let b = AudioMixRenderState(inputs: ["mic": AudioMixChannel()], output: AudioMixChannel(muted: true))
    a.push([0.8, -0.8], source: "mic"); b.push([0.8, -0.8], source: "mic")
    #expect(rendered(a, frames: 2) == [1, -1])
    #expect(rendered(b, frames: 2) == [0, 0])
}

@Test func streamingResamplerPreservesPacketBoundaries() {
    let input = (0..<1000).map { Float(sin(Double($0) / 30)) }
    var whole = AudioStreamingResampler(); var split = AudioStreamingResampler()
    let expected = whole.convert(input, from: 44_100)
    var actual: [Float] = []
    for index in stride(from: 0, to: input.count, by: 100) { actual += split.convert(Array(input[index..<min(index + 100, input.count)]), from: 44_100) }
    #expect(expected.count == actual.count)
    #expect(zip(expected, actual).allSatisfy { abs($0 - $1) < 0.0001 })
    #expect(split.convert([0.1, 0.2], from: 48_000) == [0.1, 0.2])
}

@Test func routingRejectsLoopbackAndMissingDevicesButAllowsDuplexHardware() {
    let config = AudioMixConfiguration(inputs: ["usb": AudioMixChannel()], outputs: ["usb": AudioMixChannel()])
    #expect(config.validationError(availableInputs: ["usb"], availableOutputs: ["usb"]) == nil)
    #expect(config.validationError(availableInputs: ["usb"], availableOutputs: ["usb"], feedbackSensitiveUIDs: ["usb"]) != nil)
    #expect(config.validationError(availableInputs: [], availableOutputs: ["usb"]) != nil)
    #expect(AudioMixConfiguration().validationError(availableInputs: [], availableOutputs: []) != nil)
}

@Test func mixSettingsPreserveUIDsAndChannelControls() throws {
    let config = AudioMixConfiguration(inputs: ["BuiltInMicrophoneDevice": AudioMixChannel(gain: 0.7, muted: false, solo: true)], outputs: ["virtual:1": AudioMixChannel(gain: 0.8, muted: true)])
    #expect(try JSONDecoder().decode(AudioMixConfiguration.self, from: JSONEncoder().encode(config)) == config)
}

@Test func systemAudioInventoryIsReadableWithoutChangingRoutes() {
    let devices = SystemAudioDevices.devices()
    #expect(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty && $0.id != 0 })
    #expect(Set(devices.map(\.id)).count == devices.count)
    print("Audio inventory: " + devices.map { "\($0.name) [in:\($0.inputChannels), out:\($0.outputChannels)]" }.joined(separator: ", "))
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMICRO_AUDIO_IO_SMOKE"] == "1"))
func virtualOutputGraphOpensWithoutCapturingOrPlayingContent() throws {
    let devices = SystemAudioDevices.devices()
    let device = try #require(devices.first { $0.outputChannels > 0 && ($0.name == "vRemoteDr 2ch" || $0.name == "BlackHole 2ch") })
    let output = try AudioMixOutput(device: device, inputs: [:], output: AudioMixChannel())
    defer { output.stop() }
    #expect(output.isRunning)
    print("Silent output graph opened: " + device.name)
}

@Test func visualAudioMetersUseDecibelsAndBoundInvalidValues() {
    #expect(AudioMeterScale.segments(0) == 0)
    #expect(AudioMeterScale.segments(.nan) == 0)
    #expect(AudioMeterScale.segments(0.01) == 4)
    #expect(AudioMeterScale.segments(0.1) == 8)
    #expect(AudioMeterScale.segments(1) == 12)
    #expect(AudioMeterScale.segments(10) == 12)
    #expect(AudioMeterScale.label(0) == "−∞ dB")
    #expect(AudioMeterScale.label(0.01) == "−40 dB")
}

@Test func localMonitoringGateSilencesAudioAndDropsStaleSpeech() {
    let state = AudioMixRenderState(inputs: ["usb": AudioMixChannel()], output: AudioMixChannel())
    state.setPlaybackEnabled(false)
    state.push([0.7, 0.7], source: "usb")
    #expect(rendered(state, frames: 2) == [0, 0])
    state.push([0.8], source: "usb")
    state.setPlaybackEnabled(true)
    #expect(rendered(state, frames: 1) == [0])
    state.push([0.5], source: "usb")
    #expect(rendered(state, frames: 1) == [0.5])
    state.setPlaybackEnabled(false)
    state.push([0.9], source: "usb")
    #expect(rendered(state, frames: 1) == [0])
    #expect(state.level() == 0)
}

@Test func headphonesAndAggregatesRequireExplicitMonitoring() {
    func device(_ name: String, _ transport: UInt32) -> SystemAudioDevice {
        .init(id: 1, uid: name, name: name, inputChannels: 1, outputChannels: 2, transport: transport)
    }
    #expect(!device("Earpods", kAudioDeviceTransportTypeUSB).isVirtualMixDestination)
    #expect(!device("外置耳机", kAudioDeviceTransportTypeBuiltIn).isVirtualMixDestination)
    #expect(!device("Multi Output", kAudioDeviceTransportTypeAggregate).isVirtualMixDestination)
    #expect(device("vRemoteDr 2ch", kAudioDeviceTransportTypeUSB).isVirtualMixDestination)
    #expect(device("BlackHole 2ch", kAudioDeviceTransportTypeVirtual).isVirtualMixDestination)
}

@Test func disconnectedDevicesDoNotBlockAvailableMixOrLosePreferences() {
    let saved = AudioMixConfiguration(inputs: ["mac": .init(), "earpods": .init(solo: true), "remote:x6": .init()], outputs: ["speaker": .init()])
    let current = saved.availableSubset(inputs: ["mac", "remote:x6"], outputs: ["speaker"])
    #expect(current.inputs.count == 2)
    #expect(current.inputs["earpods"] == nil)
    #expect(current.validationError(availableInputs: ["mac", "remote:x6"], availableOutputs: ["speaker"]) == nil)
    #expect(saved.inputs["earpods"]?.solo == true)
    #expect(saved.availableSubset(inputs: [], outputs: ["speaker"]).validationError(availableInputs: [], availableOutputs: ["speaker"]) != nil)
    #expect(saved.availableSubset(inputs: ["mac", "earpods", "remote:x6"], outputs: ["speaker"]) == saved)
}
