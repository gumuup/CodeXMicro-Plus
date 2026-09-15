import Foundation
import CoreGraphics
import Testing
@testable import CodeXMicroApp

@MainActor
private func isolatedStore() -> RemoteMappingStore {
    RemoteMappingStore(defaults: UserDefaults(suiteName: "hardware-tests." + UUID().uuidString)!)
}

@MainActor @Test func customVoiceAndModelIsolation() {
    let store = isolatedStore()
    store.setEnabled(true, for: .x6)
    store.setEnabled(true, for: .chromecast)
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    store.setMapping(RemoteButtonMapping(action: .shortcut(name: "我的语音输入"), releaseAction: .shortcut(name: "结束输入")), remote: .x6, button: "voice")
    store.voice(.x6, down: true)
    store.voice(.x6, down: true)
    store.voice(.chromecast, down: true)
    store.voice(.chromecast, down: false)
    store.voice(.x6, down: false)
    #expect(actions == [.shortcut(name: "我的语音输入"), .shortcut(name: "结束输入")])
}

@MainActor @Test func heldKeyReleasedOnDisableAndEdit() {
    let store = isolatedStore()
    let binding = KeyboardShortcutBinding(keyCode: 58, modifiers: [], keyLabel: "左 Option")
    var edges: [Bool] = []
    store.keyEventSink = { _, down in edges.append(down) }
    store.setMapping(RemoteButtonMapping(action: .keyboardShortcut(binding), holdShortcut: true), remote: .x6, button: "voice")
    store.setEnabled(true, for: .x6)
    store.voice(.x6, down: true)
    store.setEnabled(false, for: .x6)
    store.voice(.x6, down: false)
    #expect(edges == [true, false])
    store.setEnabled(true, for: .x6)
    store.voice(.x6, down: true)
    store.setMapping(nil, remote: .x6, button: "voice")
    #expect(edges == [true, false, true, false])
}

@MainActor @Test func learningAndEditingDoNotExecute() {
    let store = isolatedStore()
    store.setEnabled(true, for: .x6)
    var count = 0
    store.onAction = { _ in count += 1 }
    store.setMapping(RemoteButtonMapping(action: .pasteText("test")), remote: .x6, button: "voice")
    store.learn(.x6); store.voice(.x6, down: true); store.voice(.x6, down: false)
    #expect(store.learnedButton == "voice")
    #expect(count == 0)
    store.editing = true; store.voice(.x6, down: true); store.voice(.x6, down: false)
    #expect(count == 0)
}

@MainActor @Test func chromecastReportEdges() {
    let store = isolatedStore()
    store.setEnabled(true, for: .chromecast)
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    store.setMapping(RemoteButtonMapping(action: .pasteText("up"), releaseAction: .pasteText("release")), remote: .chromecast, button: "03")
    let bridge = ChromecastRemoteHIDBridge(store: store)
    bridge.handleReport(reportID: 1, data: Data([1, 3]))
    bridge.handleReport(reportID: 1, data: Data([1, 3]))
    bridge.handleReport(reportID: 1, data: Data([1, 0]))
    bridge.handleReport(reportID: 1, data: Data())
    #expect(actions == [.pasteText("up"), .pasteText("release")])
}

@MainActor @Test func x6KeyboardAndConsumerReports() {
    let store = isolatedStore()
    store.setEnabled(true, for: .x6)
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    store.setMapping(RemoteButtonMapping(action: .pasteText("up"), releaseAction: .pasteText("up-end")), remote: .x6, button: "k52")
    store.setMapping(RemoteButtonMapping(action: .pasteText("back")), remote: .x6, button: "c224")
    let bridge = X6HIDBridge(store: store)
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0x52, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 2, data: Data([2, 0x24, 2]))
    bridge.handleReport(reportID: 2, data: Data([2, 0, 0]))
    #expect(actions == [.pasteText("up"), .pasteText("up-end"), .pasteText("back")])
}

@MainActor @Test func settingsRoundTrip() throws {
    let config = RemoteHardwareConfiguration(enabled: [.x6], remoteMicrophone: [.x6], mappings: ["x6.voice": RemoteButtonMapping(action: .shortcut(name: "语音输入"))])
    let restored = try JSONDecoder().decode(RemoteHardwareConfiguration.self, from: JSONEncoder().encode(config))
    #expect(restored.enabled == [.x6])
    #expect(restored.mappings["x6.voice"]?.action == .shortcut(name: "语音输入"))
    #expect(restored.remoteMicrophone == [.x6])
}

@Test func audioProtocolResetsAndRejectsMalformedPackets() throws {
    let handler = ATVVProtocol()
    try handler.acceptCapabilities(ATVVCapabilities(version: .v10, codecs: 2, interactionModel: 0, frameSize: 120))
    #expect(handler.decodeAudio(Data()) == nil)
    handler.beginAudioStream(codec: .adpcm16k)
    let packet = Data([0x12, 0x34, 0xAB, 0xCD, 0x56, 0x78])
    let first = handler.decodeAudio(packet)
    _ = handler.decodeAudio(Data(repeating: 0x77, count: 24))
    handler.endAudioStream(); handler.beginAudioStream(codec: .adpcm16k)
    let second = handler.decodeAudio(packet)
    #expect(first?.samples == second?.samples)
    #expect(handler.parseControl(Data()) == .unknown(Data()))
}

@MainActor @Test func x6UnprefixedControlModifierDoesNotLoseMappedKey() {
    let suite = "X6PacketTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RemoteMappingStore(defaults: defaults)
    store.setEnabled(true, for: .x6)
    store.setMapping(.init(action: .pasteText("up"), releaseAction: .pasteText("released")), remote: .x6, button: "k52")
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    let bridge = X6HIDBridge(store: store)
    // An eight-byte unprefixed report starts with modifier 0x01, not report ID 0x01.
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0x52, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 1, data: Data([0, 0, 0, 0, 0, 0, 0, 0]))
    #expect(actions == [.pasteText("up"), .pasteText("released")])
}

@MainActor @Test func x6PGPlusAndVoiceDispatchConfiguredActions() throws {
    let name = "X6ActionTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    store.setEnabled(true, for: .x6)
    let app = RadialMenuAction.application(path: "/System/Applications/App Store.app")
    let shortcut = RadialMenuAction.keyboardShortcut(.init(keyCode: 34, modifiers: .control, keyLabel: "I"))
    store.setMapping(.init(action: app), remote: .x6, button: "k4B")
    store.setMapping(.init(action: shortcut), remote: .x6, button: "voice")
    var actions: [RadialMenuAction] = []
    store.onAction = { actions.append($0) }
    let bridge = X6HIDBridge(store: store)
    bridge.onPhysicalVoiceDown = { store.voice(.x6, down: true) }
    bridge.onShortPress = { store.voice(.x6, down: false) }
    bridge.onLongPressEnded = { store.voice(.x6, down: false) }
    // Packet lengths and usages confirmed on the connected X6.
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0x4B, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 2, data: Data([2, 0x21, 2]))
    bridge.handleReport(reportID: 2, data: Data([2, 0, 0]))
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0xAA, 0, 0, 0, 0, 0]))
    bridge.handleReport(reportID: 1, data: Data([1, 0, 0, 0, 0, 0, 0, 0, 0]))
    #expect(actions == [app, shortcut])
    bridge.stop()
}

@MainActor @Test func x6VoiceSuppressesOnlyMatchingNativeSearchEdges() {
    let name = "X6SearchTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = RemoteMappingStore(defaults: defaults)
    let filter = X6CompatibilityFilter(store: store)
    let now = ProcessInfo.processInfo.systemUptime
    filter.recordVoiceSearch(down: true)
    #expect(!filter.consumePhysicalEdge(0x100, down: true, received: now))
    #expect(!filter.consumePhysicalEdge(0xB1, down: false, received: now))
    #expect(filter.consumePhysicalEdge(0xB1, down: true, received: now))
    #expect(!filter.consumePhysicalEdge(0xB1, down: true, received: now))
    filter.recordVoiceSearch(down: false)
    #expect(filter.consumePhysicalEdge(0xB1, down: false, received: now))
    #expect(!filter.consumePhysicalEdge(0x10D, down: true, received: now + 1))
    store.setEnabled(true, for: .x6)
    filter.keyCodes = { X6CompatibilityFilter.voiceSearchCodes }
    let customEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0xB1, keyDown: true)!
    customEvent.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
    #expect(!filter.handle(.keyDown, customEvent))
}
