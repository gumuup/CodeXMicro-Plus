import Foundation
import Testing
@testable import CodeXMicroApp

@MainActor @Test func hardwarePresetsMigrateAndRemainIsolatedAcrossRestarts() throws {
    let name = "HardwarePresetTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let old = RemoteHardwareConfiguration(enabled: [.x6], remoteMicrophone: [.x6], mappings: ["x6.voice": .init(action: .pasteText("original")), "chromecast.voice": .init(action: .pasteText("cast"))])
    defaults.set(try JSONEncoder().encode(old), forKey: RemoteMappingStore.preferenceKey)
    let store = RemoteMappingStore(defaults: defaults)
    #expect(store.selectedPreset(for: .x6) == 0)
    store.selectPreset(at: 1, for: .x6)
    #expect(store.mapping(.x6, "voice") == nil)
    #expect(store.mapping(.chromecast, "voice")?.action == .pasteText("cast"))
    store.setMapping(.init(action: .pasteText("second"), releaseAction: .pasteText("release")), remote: .x6, button: "voice")
    let restored = RemoteMappingStore(defaults: defaults)
    #expect(restored.selectedPreset(for: .x6) == 1)
    #expect(restored.mapping(.x6, "voice")?.releaseAction == .pasteText("release"))
    restored.selectPreset(at: 0, for: .x6)
    #expect(restored.mapping(.x6, "voice")?.action == .pasteText("original"))
    restored.setMapping(nil, remote: .x6, button: "voice")
    restored.selectPreset(at: 1, for: .x6)
    #expect(restored.mapping(.x6, "voice")?.action == .pasteText("second"))
    #expect(restored.configuration.enabled == [.x6])
    #expect(restored.configuration.remoteMicrophone == [.x6])
    restored.selectPreset(at: 99, for: .x6)
    #expect(restored.selectedPreset(for: .x6) == 1)
}

@MainActor @Test func hardwarePresetSwitchEndsLearningAndReleasesHeldShortcut() {
    let name = "HardwarePresetTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    let binding = KeyboardShortcutBinding(keyCode: 0, modifiers: [], keyLabel: "A")
    store.setEnabled(true, for: .mxMaster3s)
    store.setMapping(.init(action: .keyboardShortcut(binding), holdShortcut: true), remote: .mxMaster3s, button: "mx00C3")
    var edges: [Bool] = []
    store.keyEventSink = { _, down in edges.append(down) }
    let button = RemoteProfiles.mxButtons.first { $0.id == "mx00C3" }!
    store.post(button: button, remote: .mxMaster3s, isDown: true)
    store.learn(.mxMaster3s)
    store.selectPreset(at: 1, for: .mxMaster3s)
    #expect(edges == [true, false])
    #expect(store.learning == nil)
    #expect(store.mapping(.mxMaster3s, "mx00C3") == nil)
}
