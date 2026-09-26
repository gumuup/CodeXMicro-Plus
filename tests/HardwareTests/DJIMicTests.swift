import Foundation
import Testing
@testable import CodeXMicroApp

@Test func djiClickGesturesDoNotEmitShorterActions() {
    for (count, expected) in [(1, "single"), (2, "double"), (3, "triple")] {
        var detector = DJIMicGestureRecognizer()
        var results: [String] = []
        for index in 0..<count {
            let time = Double(index) * 0.15
            #expect(detector.edge(down: true, time: time) == nil)
            #expect(detector.edge(down: true, time: time + 0.01) == nil)
            if let result = detector.edge(down: false, time: time + 0.05) { results.append(result) }
        }
        if let result = detector.flush(time: 1) { results.append(result) }
        #expect(results == [expected])
        #expect(detector.flush(time: 2) == nil)
    }
}

@Test func djiHoldRequiresRealDurationAndResetCancelsPendingGesture() {
    var detector = DJIMicGestureRecognizer()
    #expect(detector.edge(down: false, time: 0) == nil)
    _ = detector.edge(down: true, time: 1)
    #expect(detector.flush(time: 2) == nil)
    #expect(detector.edge(down: false, time: 2) == "long")
    #expect(detector.flush(time: 3) == nil)
    _ = detector.edge(down: true, time: 4)
    _ = detector.edge(down: false, time: 4.1)
    detector.reset()
    #expect(detector.flush(time: 5) == nil)
}

@MainActor @Test func djiPresetsPersistIndependentlyAndAudioIsUSB() throws {
    let name = "DJIMicTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    #expect(RemoteProfiles.djiButtons.map(\.id) == [
        "link.single", "link.double", "link.long", "power.double", "power.long"
    ])
    #expect(!SupportedRemoteID.djiMicMini2.hasRemoteAudio)
    #expect(DJIMicMini2Adapter.accepts(page: 12, usage: 0xE9))
    #expect(DJIMicMini2Adapter.accepts(page: 12, usage: 0xEA))
    #expect(!DJIMicMini2Adapter.accepts(page: 1, usage: 0xE9))
    #expect(!DJIMicMini2Adapter.accepts(page: 12, usage: 0x30)) // Never infer power.
    for button in RemoteProfiles.djiButtons {
        store.setMapping(.init(action: .pasteText(button.id)), remote: .djiMicMini2, button: button.id)
    }
    store.selectPreset(at: 1, for: .djiMicMini2)
    #expect(store.mapping(.djiMicMini2, "link.single") == nil)
    store.setMapping(.init(action: .pasteText("second")), remote: .djiMicMini2, button: "link.single")
    store.selectPreset(at: 0, for: .djiMicMini2)
    let restored = RemoteMappingStore(defaults: defaults)
    for button in RemoteProfiles.djiButtons {
        #expect(restored.mapping(.djiMicMini2, button.id)?.action == .pasteText(button.id))
    }
    #expect(restored.mapping(.x6, "link.single") == nil)
}

@MainActor @Test func djiNativeLabelsDoNotCreateMacActions() {
    let name = "DJINativeTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    for button in RemoteProfiles.djiButtons {
        #expect(store.mapping(.djiMicMini2, button.id) == nil)
        #expect(store.targetTitle(for: button, remote: .djiMicMini2) == RemoteProfiles.djiNativeTitle(for: button.id))
        #expect(button.defaultTarget == .disabled)
    }
    #expect(RemoteProfiles.djiNativeTitle(for: "power.double") == "开启／关闭降噪")
    #expect(RemoteProfiles.djiNativeTitle(for: "power.single") == "原生未定义")
}

@MainActor @Test func djiNativeOnlyRowsIgnoreSavedCustomActions() {
    let name = "DJIReadOnlyTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    store.setEnabled(true, for: .djiMicMini2)
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    #expect(RemoteProfiles.djiButtons.filter(\.remappable).map(\.id) == ["link.single"])
    for button in RemoteProfiles.djiButtons {
        store.setMapping(.init(action: .pasteText(button.id)), remote: .djiMicMini2, button: button.id)
        if !button.remappable {
            #expect(store.targetTitle(for: button, remote: .djiMicMini2) == RemoteProfiles.djiNativeTitle(for: button.id))
        }
        store.post(button: button, remote: .djiMicMini2, isDown: true)
        store.post(button: button, remote: .djiMicMini2, isDown: false)
    }
    #expect(actions == [.pasteText("link.single")])
}

/// Opt-in physical check: no recording, routing, or system input changes.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMICRO_DJI_AUDIO_TEST"] == "1"))
func djiTwoPhysicalInputsDeliverAudio() async throws {
    let devices = SystemAudioDevices.devices().filter {
        $0.inputChannels > 0 && $0.name.hasPrefix("DJI Mic Mini 2-")
    }
    #expect(devices.count == 2)
    #expect(Set(devices.map(\.uid)).count == devices.count)
    let levels = AudioInputLevels()
    let captures = devices.map { device in
        AudioDeviceCapture(uid: device.uid, destinations: [], levels: levels) { message in
            print("DJI capture diagnostic: \(message)")
        }
    }
    captures.forEach { $0.start() }
    defer { captures.forEach { $0.stop() } }
    try await Task.sleep(for: .seconds(3))
    let snapshot = levels.snapshot()
    for device in devices {
        let level = try #require(snapshot[device.uid], "No audio callback from \(device.name)")
        #expect(level.isFinite)
        print("DJI input verified: \(device.name), channels=\(device.inputChannels), RMS=\(level)")
    }
}
