import Foundation
import IOKit.hid

/// Read-only fallback for peripherals exposing their battery through macOS HID.
@MainActor
final class HardwareBatteryMonitor {
    private var manager: IOHIDManager?
    private var timer: Timer?
    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: 0x18D1, kIOHIDProductIDKey: 0x9450],
            [kIOHIDVendorIDKey: 0x1D5A, kIOHIDProductIDKey: 0xC081]
        ] as CFArray)
        IOHIDManagerOpen(manager, 0); self.manager = manager
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }
    private func refresh() {
        guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for device in devices {
            let vendor = MXMasterHIDBridge.number(device, kIOHIDVendorIDKey)
            let remote: SupportedRemoteID = vendor == 0x18D1 ? .chromecast : .x6
            guard RemoteMappingStore.shared.connected.contains(remote) else { continue }
            if let value = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? NSNumber {
                let charging = (IOHIDDeviceGetProperty(device, "BatteryIsCharging" as CFString) as? NSNumber)?.boolValue ?? false
                RemoteMappingStore.shared.battery[remote] = PeripheralBattery(percent: value.intValue, charging: charging)
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; if let manager { IOHIDManagerClose(manager, 0) }; manager = nil }
}
