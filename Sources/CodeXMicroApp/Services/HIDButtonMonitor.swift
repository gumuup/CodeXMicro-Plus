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
    guard IOHIDElementGetUsagePage(element) == kHIDPage_Button else { return }
    let usage = IOHIDElementGetUsage(element)
    guard usage > 0 else { return }
    let device = IOHIDElementGetDevice(element)
    let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
    let event = HIDButtonEvent(
        identifier: HIDButtonIdentifier(
            vendorID: vendorID,
            productID: productID,
            usage: usage,
            deviceName: deviceName
        ),
        phase: IOHIDValueGetIntegerValue(value) == 0 ? .up : .down
    )
    let monitor = Unmanaged<HIDButtonMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.receive(event)
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
        let mouseMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [mouseMatch] as CFArray)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            hidButtonInputCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isAvailable = result == kIOReturnSuccess
        if isAvailable {
            Self.logger.info("Raw HID mouse-button monitor installed")
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
}
