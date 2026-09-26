import Foundation
import Testing
@testable import CodeXMicroApp

@Test func weChatShortcutWaitsForAudioAndDoesNotRepeatOnStreamRestart() {
    var session = X6VoiceInputSession()
    func next(sampleCount: Int) -> Bool { session.audioArrived(sampleCount: sampleCount) }
    #expect(!next(sampleCount: 160))
    session.begin()
    let earlyRelease = session.keyReleased()
    #expect(!earlyRelease)
    #expect(!next(sampleCount: 0))
    #expect(next(sampleCount: 160))
    #expect(!next(sampleCount: 160))
    // Firmware may stop/reopen a stream while the physical session remains open.
    #expect(!next(sampleCount: 160))
    session.end()
    #expect(!next(sampleCount: 160))
    session.begin(); session.end() // Cancel before opening is confirmed.
    #expect(!next(sampleCount: 160))
    session.begin()
    #expect(!next(sampleCount: 160)) // Audio before release must not start WeChat.
    let released = session.keyReleased()
    #expect(released)
    let duplicateRelease = session.keyReleased()
    #expect(!duplicateRelease)
}

@MainActor @Test func weChatVoicePreferencePreservesMappingsAndEmitsControlI() throws {
    let suite = "test.wechat." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let old = RemoteHardwareConfiguration(enabled: [.x6], mappings: ["x6.k75": .init(action: .pasteText("keep"))])
    defaults.set(try JSONEncoder().encode(old), forKey: RemoteMappingStore.preferenceKey)
    let store = RemoteMappingStore(defaults: defaults)
    #expect(!store.x6WeChatVoiceEnabled)
    store.setX6WeChatVoice(true)
    #expect(store.isEnabled(.x6))
    #expect(store.configuration.remoteMicrophone.contains(.x6))
    #expect(store.configuration.mappings == old.mappings)
    #expect(RemoteMappingStore(defaults: defaults).x6WeChatVoiceEnabled)
    var events: [(KeyboardShortcutBinding, Bool)] = []
    store.keyEventSink = { events.append(($0, $1)) }
    store.startWeChatVoice()
    #expect(events.count == 2)
    #expect(events[0].0.keyCode == 34 && events[0].0.modifiers == .control)
    #expect(events[0].1 && !events[1].1)
}
