// Read-only DJI USB HID diagnostic. No report writes, key injection or audio capture.
// Disable the application's DJI mapping before running, then restore it afterward.
// swiftc script/dji_usb_probe.swift -o .build/dji-usb-probe
import Foundation
import IOKit.hid

func log(_ text: String) {
    print("\(ISO8601DateFormatter().string(from: Date())) \(text)")
    fflush(stdout)
}
var count = 0
func valueCallback(_ context: UnsafeMutableRawPointer?, _ result: IOReturn,
                   _ sender: UnsafeMutableRawPointer?, _ value: IOHIDValue) {
    guard count < 2000 else { return }
    count += 1
    let element = IOHIDValueGetElement(value)
    log(String(format: "VALUE result=%d page=0x%04X usage=0x%04X value=%ld",
               result, IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element), IOHIDValueGetIntegerValue(value)))
}
func reportCallback(_ context: UnsafeMutableRawPointer?, _ result: IOReturn,
                    _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType,
                    _ reportID: UInt32, _ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
    guard count < 2000 else { return }
    count += 1
    let hex = UnsafeBufferPointer(start: report, count: min(length, 128)).map { String(format: "%02x", $0) }.joined(separator: " ")
    log("REPORT result=\(result) id=\(reportID) length=\(length) hex=\(hex)")
}
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
// All HID collections on this exact receiver, not only known volume usages.
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x2CA3, kIOHIDProductIDKey: 0x4011] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, valueCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, 0)
log("OPEN result=\(result) (0=success), nonexclusive; application mapping must be off")
guard result == kIOReturnSuccess else { exit(1) }
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
var buffers: [UnsafeMutablePointer<UInt8>] = []
log("DEVICES count=\(devices.count)")
for device in devices {
    let size = max(64, min(65536, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 4096))
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    buffers.append(buffer)
    IOHIDDeviceRegisterInputReportCallback(device, buffer, size, reportCallback, nil)
    let elements = (IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement]) ?? []
    for element in elements {
        log(String(format: "ELEMENT type=%u page=0x%04X usage=0x%04X reportID=%u", IOHIDElementGetType(element).rawValue, IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element), IOHIDElementGetReportID(element)))
    }
}
if !devices.isEmpty {
    log("READY timeout=300s")
    RunLoop.main.run(until: Date().addingTimeInterval(300))
}
IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerClose(manager, 0)
buffers.forEach { $0.deallocate() }
log("DONE callbacks=\(count)")
