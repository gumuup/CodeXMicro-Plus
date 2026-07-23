import Foundation
import IOKit.hid
import OSLog

struct HIDButtonEvent: Sendable {
    let identifier: HIDButtonIdentifier
    let phase: ShortcutKeyPhase
}

private let hidButtonInputCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    guard HIDButtonIdentifier.supportsRawElement(
        usagePage: usagePage,
        usage: usage,
        isRelative: IOHIDElementIsRelative(element),
        logicalMinimum: IOHIDElementGetLogicalMin(element),
        logicalMaximum: IOHIDElementGetLogicalMax(element)
    ) else { return }

    let device = IOHIDElementGetDevice(element)
    let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
    let deviceUsagePage = (
        IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber
    )?.uint32Value ?? 0
    let deviceUsage = (
        IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber
    )?.uint32Value ?? 0
    let rawValue = IOHIDValueGetIntegerValue(value)
    let isDirectional = HIDButtonMonitor.isDirectional(
        element: element,
        usagePage: usagePage
    )
    let isDialOrWheel = usagePage == UInt32(kHIDPage_GenericDesktop)
        && (usage == UInt32(kHIDUsage_GD_Dial) || usage == UInt32(kHIDUsage_GD_Wheel))
    // Absolute axes need value-range semantics rather than shortcut pulses.
    // Ignore those instead of treating their current position as a press.
    guard !isDialOrWheel || isDirectional else { return }
    guard !isDirectional || rawValue != 0 else { return }

    let identifier = HIDButtonIdentifier(
        vendorID: vendorID,
        productID: productID,
        usagePage: usagePage,
        usage: usage,
        direction: isDirectional ? (rawValue > 0 ? 1 : -1) : 0,
        deviceUsagePage: deviceUsagePage,
        deviceUsage: deviceUsage,
        deviceName: deviceName
    )
    let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        if isDirectional {
            // Relative dials and wheels do not send a matching zero/up value.
            // Convert every bounded step into a complete shortcut pulse.
            let stepCount = Int(min(max(rawValue.magnitude, 1), 16))
            for _ in 0..<stepCount {
                monitor.receive(HIDButtonEvent(identifier: identifier, phase: .down))
                monitor.receive(HIDButtonEvent(identifier: identifier, phase: .up))
            }
        } else {
            monitor.receive(HIDButtonEvent(
                identifier: identifier,
                phase: rawValue == 0 ? .up : .down
            ))
        }
    }
}

@MainActor
final class HIDButtonMonitor {
    static let shared = HIDButtonMonitor()

    private static let logger = Logger(
        subsystem: "com.gumu.codexmicro.virtual",
        category: "hid-shortcuts"
    )

    private let manager: IOHIDManager
    private var observers: [UUID: (HIDButtonEvent) -> Void] = [:]
    private(set) var isAvailable = false

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let genericDesktopUsages: [Int] = [
            Int(kHIDUsage_GD_Mouse),
            Int(kHIDUsage_GD_Joystick),
            Int(kHIDUsage_GD_GamePad),
            Int(kHIDUsage_GD_Keyboard),
            0x07, // Keypad application collection
            Int(kHIDUsage_GD_MultiAxisController),
        ]
        var matches = genericDesktopUsages.map { usage in
            [
                kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey: usage,
            ] as [String: Any]
        }
        matches.append([
            kIOHIDDeviceUsagePageKey: Int(kHIDPage_Consumer),
            kIOHIDDeviceUsageKey: Int(kHIDUsage_Csmr_ConsumerControl),
        ])
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            hidButtonInputCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isAvailable = result == kIOReturnSuccess
        if isAvailable {
            Self.logger.info("Raw HID composite-control monitor installed")
        } else {
            Self.logger.error("Could not open raw HID monitor: \(result)")
        }
    }

    @discardableResult
    func addObserver(_ observer: @escaping (HIDButtonEvent) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID?) {
        guard let token else { return }
        observers.removeValue(forKey: token)
    }

    fileprivate func receive(_ event: HIDButtonEvent) {
        let callbacks = Array(observers.values)
        for observer in callbacks { observer(event) }
    }

    nonisolated fileprivate static func isDirectional(
        element: IOHIDElement,
        usagePage: UInt32
    ) -> Bool {
        guard usagePage != UInt32(kHIDPage_Button) else { return false }
        return IOHIDElementIsRelative(element)
    }
}
