// Adapted from VincentKingHsu/vRemoter (MIT); see ThirdParty/vRemoter/LICENSE.
import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import OSLog

private struct HIDCallbackDeviceX6HIDBridge: @unchecked Sendable {
    // Only used synchronously inside callbacks on CFRunLoopGetMain().
    let value: IOHIDDevice
}
private func x6DeviceMatched(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let bridge = Unmanaged<X6HIDBridge>.fromOpaque(context).takeUnretainedValue()
    let wrapped = HIDCallbackDeviceX6HIDBridge(value: device)
    MainActor.assumeIsolated { bridge.deviceDidMatch(result: result, device: wrapped.value) }
}
private func x6DeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let bridge = Unmanaged<X6HIDBridge>.fromOpaque(context).takeUnretainedValue()
    let wrapped = HIDCallbackDeviceX6HIDBridge(value: device)
    MainActor.assumeIsolated { bridge.deviceDidRemove(wrapped.value) }
}
private func x6InputReport(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
    guard let context, result == kIOReturnSuccess, reportLength > 0 else { return }
    let bridge = Unmanaged<X6HIDBridge>.fromOpaque(context).takeUnretainedValue()
    let data = Data(bytes: report, count: reportLength)
    MainActor.assumeIsolated { bridge.handleReport(reportID: reportID, data: data) }
}

/// Read-only protocol probe for the Shenzhen Xingwei X6 BLE remote.
///
/// The device exposes normal keyboard/consumer/mouse collections plus a
/// vendor-defined 255-byte input report (ID 0x5A). We initially observe it
/// non-exclusively so ordinary buttons keep working while we identify the
/// voice-button usage and audio encoding.
@MainActor
final class X6HIDBridge {
    static let vendorID = 0x1D5A
    static let productID = 0xC081
    static let voiceDataReportID: UInt32 = 0x5A
    var onError: ((String) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onConsumerUsageChanged: ((UInt16) -> Void)?
    var onNativeSearchEdge: (() -> Void)?
    /// Physical Search-down. Used only to pre-arm the remote audio route.
    var onPhysicalVoiceDown: (() -> Void)?
    /// Semantic events; each physical gesture produces exactly one path.
    var onShortPress: (() -> Void)?
    var onLongPressBegan: (() -> Void)?
    var onLongPressEnded: (() -> Void)?

    private var exclusive = false
    private lazy var compatibility = X6CompatibilityFilter(store: store)
    private var manager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var connectionTimer: Timer?
    private var wantsRunning = false
    var onInputStatus: ((String) -> Void)?
    private var lastConsumerUsage: UInt16 = 0
    private var voiceGestureActive = false
    private var longVoiceKeyActive = false
    private var longPressConfirmed = false
    private var longPressConfirmWorkItem: DispatchWorkItem?
    private var deferredVoiceRelease: DispatchWorkItem?
    private var voiceReportCount = 0
    private var voiceByteCount = 0
    private let store: RemoteMappingStore
    private var remappingEnabled: Bool
    init(store: RemoteMappingStore = .shared) {
        self.store = store
        self.remappingEnabled = store.isEnabled(.x6)
    }
    private var mappedKeyboardUsages = Set<UInt8>()
    private var passthroughKeyboardUsages = Set<UInt8>()
    private var lastKeyboardModifiers: UInt8 = 0
    private var lastSystemUsage: UInt8 = 0
    private var lastMouseButtons: UInt8 = 0

    func setRemappingEnabled(_ enabled: Bool) {
        guard remappingEnabled != enabled else { return }
        remappingEnabled = enabled
        start()
    }

    func start() {
        stop()
        wantsRunning = true
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileConnection() }
        }
        openManager()
    }

    private func openManager(attemptSeize: Bool = true) {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: Self.vendorID,
                kIOHIDProductIDKey: Self.productID,
            ] as CFDictionary
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            x6DeviceMatched,
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            x6DeviceRemoved,
            context
        )
        IOHIDManagerRegisterInputReportCallback(
            manager,
            x6InputReport,
            context
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        // X6 exposes keyboard, consumer and mouse collections. Opening the
        // manager with seize applies the remapping boundary to every matching
        // collection instead of leaving a system-facing interface live.
        let openOptions = remappingEnabled && attemptSeize
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(manager, openOptions)
        exclusive = result == kIOReturnSuccess && remappingEnabled && attemptSeize
        if attemptSeize && (result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted) {
            // A failed seize can leave the manager's device clients/callbacks
            // unusable. Recreate and register everything before shared open.
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
            openManager(attemptSeize: false)
            return
        }
        if !attemptSeize && remappingEnabled {
            compatibility.keyCodes = { [weak self] in
                guard let self else { return [] }
                var codes = Set(RemoteProfiles.x6Buttons.compactMap { button -> UInt16? in
                    guard self.store.mapping(.x6, button.id) != nil || self.store.learning == .x6 || self.store.editing else { return nil }
                    if let media = X6CompatibilityFilter.mediaCode(button.id) { return media }
                    guard button.id.hasPrefix("k"), let usage = UInt8(button.id.dropFirst(), radix: 16) else { return nil }
                    return X6KeyboardPassthrough.keyCode(for: usage)
                })
                // The voice source is Consumer Search, not the user-selected
                // shortcut. Suppress its native launch action during mapping.
                codes.formUnion(X6CompatibilityFilter.voiceSearchCodes)
                return codes
            }
            if remappingEnabled, !compatibility.start() { onInputStatus?("兼容监听需要辅助功能权限，请到通用检查") }
        }
        guard result == kIOReturnSuccess else {
            Logger(subsystem: "com.gumu.codexmicro.virtual", category: "X6Connection").error("Open failed: \(result)")
            onInputStatus?("按键通道打开失败（\(result)），正在重试")
            onError?("无法接管遥控器，请检查输入监控权限或退出其他遥控器软件（\(result)）")
            print(
                "[X6] HID manager open failed: 0x" +
                String(UInt32(bitPattern: result), radix: 16)
            )
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(manager, 0)
            return
        }
        self.manager = manager
        // Devices already present at launch need an explicit snapshot as well as hotplug callbacks.
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { deviceDidMatch(result: kIOReturnSuccess, device: device) }
        }
        if activeDevice == nil { onInputStatus?("等待 X6 按键通道连接") }
    }

    func stop() {
        wantsRunning = false
        compatibility.stop()
        connectionTimer?.invalidate(); connectionTimer = nil
        store.releaseAll(for: .x6)
        deferredVoiceRelease?.cancel()
        deferredVoiceRelease = nil
        longPressConfirmWorkItem?.cancel()
        longPressConfirmWorkItem = nil
        if voiceGestureActive {
            let wasLong = longPressConfirmed
            voiceGestureActive = false
            longVoiceKeyActive = false
            longPressConfirmed = false
            if wasLong {
                onLongPressEnded?()
            }
        }
        activeDevice = nil
        mappedKeyboardUsages.removeAll()
        for usage in passthroughKeyboardUsages {
            X6KeyboardPassthrough.post(usage: usage, modifiers: 0, isDown: false)
        }
        X6KeyboardPassthrough.postModifierChanges(from: lastKeyboardModifiers, to: 0)
        if lastMouseButtons != 0 { passthroughMouse(Data([0, 0, 0, 0])) }
        passthroughKeyboardUsages.removeAll()
        lastKeyboardModifiers = 0
        lastSystemUsage = 0
        lastMouseButtons = 0
        onConnectionChanged?(false)
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    fileprivate func deviceDidMatch(
        result: IOReturn,
        device: IOHIDDevice
    ) {
        guard wantsRunning else { return }
        guard result == kIOReturnSuccess else {
            onInputStatus?("按键通道暂不可用（\(result)），正在重试")
            return
        }
        guard activeDevice == nil else { return }
        // IOHIDManagerOpen already opened every current and future matching
        // HID collection with the requested access mode.
        activeDevice = device
        voiceReportCount = 0
        voiceByteCount = 0
        lastConsumerUsage = 0
        onConnectionChanged?(true)
        onInputStatus?(remappingEnabled ? (exclusive ? "按键通道已连接 · 映射已启用" : "按键通道已连接 · 兼容监听") : "按键通道已连接 · 系统模式")
        print(
            "[X6] connected VID=0x1d5a PID=0xc081 " +
            "manufacturer=shenzhen_xingwei " +
            "mode=\(remappingEnabled ? "remap" : "observe")"
        )
    }

    fileprivate func deviceDidRemove(_ device: IOHIDDevice) {
        guard let activeDevice, CFEqual(activeDevice, device) else { return }
        store.releaseAll(for: .x6)
        self.activeDevice = nil
        lastConsumerUsage = 0
        onConnectionChanged?(false)
        print("[X6] disconnected")
    }

    private func reconcileConnection() {
        guard wantsRunning else { return }
        if let manager {
            let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
            if let activeDevice, !devices.contains(where: { CFEqual($0, activeDevice) }) { deviceDidRemove(activeDevice) }
            if activeDevice != nil { return }
            // Reopen after permission changes, Bluetooth reconnects, or failed hotplug opens.
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0); self.manager = nil
        }
        openManager()
    }

    func handleReport(reportID: UInt32, data: Data) {
        // On macOS the manager callback includes the report ID as byte zero
        // for this device, even though it is also supplied separately.
        let payload: Data
        let payloadSizes: [UInt32: Int] = [1: 8, 2: 2, 3: 1, 4: 4]
        if data.first == UInt8(truncatingIfNeeded: reportID), payloadSizes[reportID].map({ data.count == $0 + 1 }) ?? true {
            payload = Data(data.dropFirst())
        } else {
            payload = data
        }

        switch reportID {
        case 0x01:
            logSmallReport(name: "keyboard", reportID: reportID, data: payload)
            if remappingEnabled { handleKeyboardMapping(payload) }
            handleKeyboardReport(payload)
        case 0x02:
            if remappingEnabled { handleConsumerMapping(payload) }
            handleConsumerReport(payload)
        case 0x03:
            logSmallReport(name: "system", reportID: reportID, data: payload)
            if remappingEnabled { handleSystemMapping(payload) }
        case 0x04:
            if remappingEnabled, exclusive, !store.editing, store.learning == nil { passthroughMouse(payload) }
        case Self.voiceDataReportID:
            handleVoiceData(payload)
        default:
            logSmallReport(name: "unknown", reportID: reportID, data: payload)
        }
    }

    private func handleKeyboardMapping(_ data: Data) {
        guard data.count >= 2 else { return }
        let modifiers = data[data.startIndex]
        if exclusive { X6KeyboardPassthrough.postModifierChanges(from: lastKeyboardModifiers, to: modifiers) }
        lastKeyboardModifiers = modifiers

        let usages = Set(data.dropFirst(2).filter { $0 != 0 })
        let releasedMapped = mappedKeyboardUsages.subtracting(usages)
        let releasedPassthrough = passthroughKeyboardUsages.subtracting(usages)
        let pressed = usages.subtracting(
            mappedKeyboardUsages.union(passthroughKeyboardUsages)
        )

        for usage in releasedMapped {
            apply(buttonID: String(format: "k%02X", usage), isDown: false)
        }
        for usage in releasedPassthrough {
            X6KeyboardPassthrough.post(
                usage: usage,
                modifiers: modifiers,
                isDown: false
            )
        }
        for usage in pressed {
            let id = String(format: "k%02X", usage)
            if RemoteProfiles.x6Buttons.contains(where: { $0.id == id }) {
                mappedKeyboardUsages.insert(usage)
                apply(buttonID: id, isDown: true)
            } else if exclusive, usage != 0xAA, !store.editing, store.learning == nil {
                passthroughKeyboardUsages.insert(usage)
                X6KeyboardPassthrough.post(
                    usage: usage,
                    modifiers: modifiers,
                    isDown: true
                )
            }
        }
        mappedKeyboardUsages.formIntersection(usages)
        passthroughKeyboardUsages.formIntersection(usages)
    }

    private func handleConsumerMapping(_ data: Data) {
        guard data.count >= 2 else { return }
        let usage = UInt16(data[data.startIndex])
            | UInt16(data[data.index(after: data.startIndex)]) << 8
        let previous = lastConsumerUsage
        guard usage != previous else { return }
        if previous != 0 {
            apply(buttonID: "c" + String(format: "%X", previous), isDown: false)
        }
        if usage != 0, usage != 0x0221 {
            apply(buttonID: "c" + String(format: "%X", usage), isDown: true)
        }
    }

    private func handleSystemMapping(_ data: Data) {
        guard let usage = data.first, usage != lastSystemUsage else { return }
        if lastSystemUsage != 0 {
            apply(
                buttonID: String(format: "s%02X", lastSystemUsage),
                isDown: false
            )
        }
        lastSystemUsage = usage
        if usage != 0 {
            apply(buttonID: String(format: "s%02X", usage), isDown: true)
        }
    }

    private func apply(buttonID: String, isDown: Bool) {
        guard let button = RemoteProfiles.x6Buttons.first(
            where: { $0.id == buttonID }
        ) else { return }
        if !exclusive {
            guard store.mapping(.x6, buttonID) != nil || store.learning == .x6 || store.editing else { return }
            if buttonID.hasPrefix("k"), let usage = UInt8(buttonID.dropFirst(), radix: 16), let code = X6KeyboardPassthrough.keyCode(for: usage) {
                compatibility.record(code, down: isDown)
            } else if let code = X6CompatibilityFilter.mediaCode(buttonID) { compatibility.record(code, down: isDown) }
        }
        store.post(button: button, remote: .x6, isDown: isDown)
        print(
            "[X6-MAP] \(button.title) " +
            "\(isDown ? "DOWN" : "UP") -> " +
            store.targetTitle(for: button, remote: .x6)
        )
    }

    private func passthroughMouse(_ data: Data) {
        guard data.count >= 4 else { return }
        let buttons = data[data.startIndex]
        let dx = CGFloat(Int(Int8(bitPattern: data[data.index(data.startIndex, offsetBy: 1)])))
        let dy = CGFloat(Int(Int8(bitPattern: data[data.index(data.startIndex, offsetBy: 2)])))
        let wheel = Int32(Int(Int8(bitPattern: data[data.index(data.startIndex, offsetBy: 3)])))
        let location = CGEvent(source: nil)?.location ?? .zero
        let next = CGPoint(x: location.x + dx, y: location.y + dy)

        let leftDown = buttons & 0x01 != 0
        let rightDown = buttons & 0x02 != 0
        let lastLeftDown = lastMouseButtons & 0x01 != 0
        let lastRightDown = lastMouseButtons & 0x02 != 0
        let type: CGEventType
        let button: CGMouseButton
        if leftDown != lastLeftDown {
            type = leftDown ? .leftMouseDown : .leftMouseUp
            button = .left
        } else if rightDown != lastRightDown {
            type = rightDown ? .rightMouseDown : .rightMouseUp
            button = .right
        } else if leftDown {
            type = .leftMouseDragged
            button = .left
        } else if rightDown {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: next,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
        lastMouseButtons = buttons

        if wheel != 0 {
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: wheel,
                wheel2: 0,
                wheel3: 0
            )?.post(tap: .cghidEventTap)
        }
    }

    private func handleConsumerReport(_ data: Data) {
        guard data.count >= 2 else { return }
        let usage = UInt16(data[data.startIndex])
            | UInt16(data[data.index(after: data.startIndex)]) << 8
        guard usage != lastConsumerUsage else { return }
        if !exclusive, remappingEnabled {
            if usage == 0x0221 { compatibility.recordVoiceSearch(down: true) }
            if lastConsumerUsage == 0x0221 { compatibility.recordVoiceSearch(down: false) }
        }
        lastConsumerUsage = usage
        print(
            String(
                format: "[X6] consumer usage=0x%04X edge=%@ raw=%@",
                usage,
                usage == 0 ? "up" : "down",
                hex(data)
            )
        )
        onConsumerUsageChanged?(usage)
        if usage == 0x0221 {
            onNativeSearchEdge?()
            beginVoiceGestureIfNeeded(source: "consumer-search")
        } else if usage == 0, voiceGestureActive, !longVoiceKeyActive {
            onNativeSearchEdge?()
            // X6 releases Consumer Search just before it transitions to the
            // hold-only keyboard usage 0xAA. Delay briefly so a short press
            // ends here while a long press can cancel this release.
            scheduleDeferredVoiceRelease()
        }
    }

    private func handleKeyboardReport(_ data: Data) {
        guard data.count >= 2 else { return }
        let keys = Set(data.dropFirst(2).filter { $0 != 0 })
        let voiceHeld = keys.contains(0xAA)
        guard voiceHeld != longVoiceKeyActive else { return }
        longVoiceKeyActive = voiceHeld

        if voiceHeld {
            deferredVoiceRelease?.cancel()
            deferredVoiceRelease = nil
            beginVoiceGestureIfNeeded(source: "keyboard-0xAA")
            // Some X6 firmware emits the 0xAA keyboard usage for both a tap
            // and a hold. Do not classify it as long immediately; confirm
            // that it remains asserted for the same 280ms window used by the
            // normal HID gesture classifier.
            longPressConfirmed = false
            longPressConfirmWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      self.voiceGestureActive,
                      self.longVoiceKeyActive
                else { return }
                self.longPressConfirmed = true
                self.longPressConfirmWorkItem = nil
                self.onLongPressBegan?()
                print("[X6] physical voice HOLD confirmed")
            }
            longPressConfirmWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        } else if voiceGestureActive {
            longPressConfirmWorkItem?.cancel()
            longPressConfirmWorkItem = nil
            if longPressConfirmed {
                finishLongGesture(source: "keyboard-0xAA")
            } else {
                finishShortGesture(source: "keyboard-0xAA")
            }
        }
    }

    private func beginVoiceGestureIfNeeded(source: String) {
        guard !voiceGestureActive else { return }
        deferredVoiceRelease?.cancel()
        deferredVoiceRelease = nil
        voiceGestureActive = true
        print("[X6] voice DOWN source=\(source)")
        onPhysicalVoiceDown?()
    }

    private func scheduleDeferredVoiceRelease() {
        deferredVoiceRelease?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.longVoiceKeyActive else { return }
            self.deferredVoiceRelease = nil
            self.finishShortGesture(source: "consumer-search")
        }
        deferredVoiceRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func finishShortGesture(source: String) {
        deferredVoiceRelease?.cancel()
        deferredVoiceRelease = nil
        guard voiceGestureActive else { return }
        voiceGestureActive = false
        longVoiceKeyActive = false
        longPressConfirmed = false
        longPressConfirmWorkItem?.cancel()
        longPressConfirmWorkItem = nil
        print("[X6] voice UP source=\(source)")
        onShortPress?()
    }

    private func finishLongGesture(source: String) {
        deferredVoiceRelease?.cancel()
        deferredVoiceRelease = nil
        guard voiceGestureActive else { return }
        voiceGestureActive = false
        longVoiceKeyActive = false
        longPressConfirmed = false
        longPressConfirmWorkItem?.cancel()
        longPressConfirmWorkItem = nil
        print("[X6] voice LONG UP source=\(source)")
        onLongPressEnded?()
    }

    private func handleVoiceData(_ data: Data) {
        // Raw input payloads are deliberately not logged.
    }

    private func logSmallReport(
        name: String,
        reportID: UInt32,
        data: Data
    ) {
        // Raw input payloads are deliberately not logged.
    }

    private func hex<S: Sequence>(_ bytes: S) -> String
    where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

@MainActor
private enum X6KeyboardPassthrough {
    private static let modifierKeyCodes: [(mask: UInt8, keyCode: CGKeyCode)] = [
        (0x01, 0x3B), (0x02, 0x38), (0x04, 0x3A), (0x08, 0x37),
        (0x10, 0x3E), (0x20, 0x3C), (0x40, 0x3D), (0x80, 0x36),
    ]

    static func keyCode(for usage: UInt8) -> CGKeyCode? { keyCodes[usage] }

    private static let keyCodes: [UInt8: CGKeyCode] = [
        0x04: 0x00, 0x05: 0x0B, 0x06: 0x08, 0x07: 0x02,
        0x08: 0x0E, 0x09: 0x03, 0x0A: 0x05, 0x0B: 0x04,
        0x0C: 0x22, 0x0D: 0x26, 0x0E: 0x28, 0x0F: 0x25,
        0x10: 0x2E, 0x11: 0x2D, 0x12: 0x1F, 0x13: 0x23,
        0x14: 0x0C, 0x15: 0x0F, 0x16: 0x01, 0x17: 0x11,
        0x18: 0x20, 0x19: 0x09, 0x1A: 0x0D, 0x1B: 0x07,
        0x1C: 0x10, 0x1D: 0x06,
        0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15,
        0x22: 0x17, 0x23: 0x16, 0x24: 0x1A, 0x25: 0x1C,
        0x26: 0x19, 0x27: 0x1D,
        0x28: 0x24, 0x29: 0x35, 0x2A: 0x33, 0x2B: 0x30,
        0x2C: 0x31, 0x2D: 0x1B, 0x2E: 0x18, 0x2F: 0x21,
        0x30: 0x1E, 0x31: 0x2A, 0x33: 0x29, 0x34: 0x27,
        0x35: 0x32, 0x36: 0x2B, 0x37: 0x2F, 0x38: 0x2C,
        0x39: 0x39,
        0x3A: 0x7A, 0x3B: 0x78, 0x3C: 0x63, 0x3D: 0x76,
        0x3E: 0x60, 0x3F: 0x61, 0x40: 0x62, 0x41: 0x64,
        0x42: 0x65, 0x43: 0x6D, 0x44: 0x67, 0x45: 0x6F,
        0x4A: 0x73, 0x4B: 0x74, 0x4D: 0x77, 0x4E: 0x79,
        0x4F: 0x7C, 0x50: 0x7B, 0x51: 0x7D, 0x52: 0x7E,
        0x54: 0x4B, 0x55: 0x43, 0x56: 0x4E, 0x57: 0x45,
        0x58: 0x4C, 0x59: 0x53, 0x5A: 0x54, 0x5B: 0x55,
        0x5C: 0x56, 0x5D: 0x57, 0x5E: 0x58, 0x5F: 0x59,
        0x60: 0x5B, 0x61: 0x5C, 0x62: 0x52, 0x63: 0x41,
    ]

    static func postModifierChanges(from old: UInt8, to new: UInt8) {
        for entry in modifierKeyCodes where (old & entry.mask) != (new & entry.mask) {
            let isDown = new & entry.mask != 0
            guard let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                virtualKey: entry.keyCode,
                keyDown: isDown
            ) else { continue }
            event.flags = flags(from: new)
            event.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
            event.post(tap: .cghidEventTap)
        }
    }

    static func post(usage: UInt8, modifiers: UInt8, isDown: Bool) {
        guard let keyCode = keyCodes[usage],
              let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                virtualKey: keyCode,
                keyDown: isDown
              )
        else {
            if isDown {
                print(String(format: "[X6-MAP] unmapped keyboard usage=0x%02X", usage))
            }
            return
        }
        event.flags = flags(from: modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        event.post(tap: .cghidEventTap)
    }

    private static func flags(from modifiers: UInt8) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers & 0x11 != 0 { result.insert(.maskControl) }
        if modifiers & 0x22 != 0 { result.insert(.maskShift) }
        if modifiers & 0x44 != 0 { result.insert(.maskAlternate) }
        if modifiers & 0x88 != 0 { result.insert(.maskCommand) }
        return result
    }
}
