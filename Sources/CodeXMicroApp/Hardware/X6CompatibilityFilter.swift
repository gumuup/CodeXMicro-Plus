import AppKit

private struct X6EventBox: @unchecked Sendable { let event: CGEvent }
private func x6CompatibilityTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let filter = Unmanaged<X6CompatibilityFilter>.fromOpaque(context).takeUnretainedValue()
    let box = X6EventBox(event: event)
    let suppress = MainActor.assumeIsolated { filter.handle(type, box.event) }
    return suppress ? nil : Unmanaged.passUnretained(event)
}

/// Defer only configured source keys briefly, allowing HID reports to identify
/// their physical source even when the Quartz callback arrives first.
@MainActor
final class X6CompatibilityFilter {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var edges: [(UInt16, Bool, TimeInterval)] = []
    private let store: RemoteMappingStore
    private static let passthroughMarker: Int64 = 0x5836434F4D50
    var keyCodes: () -> Set<UInt16> = { [] }
    init(store: RemoteMappingStore) { self.store = store }
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << 14)
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: x6CompatibilityTap, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap; source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true); return true
    }
    static func mediaCode(_ buttonID: String) -> UInt16? {
        ["cE9": 0x100, "cEA": 0x101, "cE2": 0x107][buttonID]
    }
    // AC Search is translated to 0xB1 by macOS (also observed by upstream
    // vRemoter). Some versions deliver the Launch Panel media event instead.
    static let voiceSearchCodes: Set<UInt16> = [0xB1, 0x10D]
    func recordVoiceSearch(down: Bool) {
        for code in Self.voiceSearchCodes { record(code, down: down) }
    }
    func record(_ code: UInt16, down: Bool) {
        edges.append((code, down, ProcessInfo.processInfo.systemUptime))
        edges.removeAll { ProcessInfo.processInfo.systemUptime - $0.2 > 0.2 }
    }
    func consumePhysicalEdge(_ code: UInt16, down: Bool, received: TimeInterval) -> Bool {
        guard let index = edges.firstIndex(where: { $0.0 == code && $0.1 == down && abs($0.2 - received) < 0.1 }) else { return false }
        edges.remove(at: index)
        return true
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != ShortcutEventMarker.codexAutomation, marker != Self.passthroughMarker,
              store.isEnabled(.x6), let copy = event.copy() else { return false }
        let code: UInt16
        let down: Bool
        if type.rawValue == 14 {
            guard let native = NSEvent(cgEvent: event), native.subtype.rawValue == 8 else { return false }
            code = UInt16(truncatingIfNeeded: native.data1 >> 16) + 0x100
            down = (native.data1 >> 8) & 255 == 0xA
        } else {
            code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            down = type == .keyDown
        }
        guard keyCodes().contains(code) else { return false }
        let received = ProcessInfo.processInfo.systemUptime
        let box = X6EventBox(event: copy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            if self?.consumePhysicalEdge(code, down: down, received: received) == true { return }
            box.event.setIntegerValueField(.eventSourceUserData, value: Self.passthroughMarker)
            box.event.post(tap: .cghidEventTap)
        }
        return true
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; edges = []
    }
}
