// Native macOS button/scroll handling inspired by Mouser core/mouse_hook_macos.py.
// Unlike a global mouse remap, interception requires a matching MX HID value.
import AppKit
import IOKit.hid

private func mxValue(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    guard let context, result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    let device = IOHIDElementGetDevice(element)
    let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
    guard MXMasterProtocol.productIDs.contains(pid) || name.localizedCaseInsensitiveContains("MX Master 3S") else { return }
    let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element), raw = IOHIDValueGetIntegerValue(value)
    let time = IOHIDValueGetTimeStamp(value)
    let bridge = Unmanaged<MXStandardMouseBridge>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { bridge.record(page: page, usage: usage, value: raw, timestamp: time) }
}
private struct MXEventBox: @unchecked Sendable { let event: CGEvent }
private func mxEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let bridge = Unmanaged<MXStandardMouseBridge>.fromOpaque(context).takeUnretainedValue()
    let box = MXEventBox(event: event)
    let suppress = MainActor.assumeIsolated { bridge.handle(type: type, event: box.event) }
    return suppress ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class MXStandardMouseBridge {
    var diverted: Set<UInt16> = []
    private var manager: IOHIDManager?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var matcher = MXPhysicalEventMatcher()
    private var consumed: Set<String> = []
    private var lastScroll: [String: Double] = [:]
    private let store = RemoteMappingStore.shared
    private var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info); return info
    }()
    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, mxValue, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, 0); self.manager = manager
        ensureTap()
    }
    func ensureTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: mxEvent, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func record(page: UInt32, usage: UInt32, value: Int, timestamp: UInt64) {
        var id: String?
        if page == 9 {
            let cid: UInt16? = [1: 0x50, 2: 0x51, 3: 0x52, 4: 0x53, 5: 0x56][usage]
            if let cid, !diverted.contains(cid) { id = MXMasterProtocol.id(cid) }
        } else if value != 0, page == 1, usage == 0x38 { id = value > 0 ? "mxScrollUp" : "mxScrollDown" }
        else if value != 0, page == 0x0C, usage == 0x238 { id = value > 0 ? "mxScrollRight" : "mxScrollLeft" }
        guard let id else { return }
        let seconds = Double(timestamp) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        matcher.record(id: id, down: value != 0, time: seconds)
    }
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != ShortcutEventMarker.codexAutomation,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(ProcessInfo.processInfo.processIdentifier) else { return false }
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type)
        let scrolling = type == .scrollWheel
        let id: String
        if scrolling {
            let y = event.getIntegerValueField(.scrollWheelEventDeltaAxis1), x = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            guard x != 0 || y != 0 else { return false }
            id = abs(x) > abs(y) ? (x > 0 ? "mxScrollLeft" : "mxScrollRight") : (y > 0 ? "mxScrollUp" : "mxScrollDown")
        } else {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard let cid: UInt16 = [0: 0x50, 1: 0x51, 2: 0x52, 3: 0x53, 4: 0x56][button], !diverted.contains(cid) else { return false }
            id = MXMasterProtocol.id(cid)
        }
        let time = Double(event.timestamp) / 1_000_000_000
        // Match one physical event, never an unrelated mouse or trackpad event.
        guard matcher.consume(id: id, down: down, time: time) else { return false }
        guard let button = RemoteProfiles.mxButtons.first(where: { $0.id == id }) else { return false }
        if !down, consumed.remove(id) != nil { store.post(button: button, remote: .mxMaster3s, isDown: false); return true }
        guard store.isEnabled(.mxMaster3s), !store.editing else { return false }
        // Keep this app's settings operable even when left/right click are remapped.
        if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }) { return false }
        guard store.learning == .mxMaster3s || store.mapping(.mxMaster3s, id) != nil else { return false }
        if scrolling {
            if time - (lastScroll[id] ?? 0) > 0.12 {
                lastScroll[id] = time; store.post(button: button, remote: .mxMaster3s, isDown: true); store.post(button: button, remote: .mxMaster3s, isDown: false)
            }
        } else if down { consumed.insert(id); store.post(button: button, remote: .mxMaster3s, isDown: true) }
        return true
    }
    func stop() {
        store.releaseAll(for: .mxMaster3s); consumed = []; matcher = MXPhysicalEventMatcher()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        if let manager { IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue); IOHIDManagerClose(manager, 0) }; manager = nil
    }
}
