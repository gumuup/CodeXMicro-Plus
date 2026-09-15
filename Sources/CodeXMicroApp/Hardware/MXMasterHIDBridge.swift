// Native Swift adaptation of Mouser's HID++ discovery/diversion lifecycle.
import AppKit
import Combine
import IOKit.hid

private final class MXReportBuffer: @unchecked Sendable {
    let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    deinit { pointer.deallocate() }
}
private final class MXOutgoingReport {
    let bytes: UnsafeMutablePointer<UInt8>
    init(_ data: [UInt8]) { bytes = .allocate(capacity: data.count); bytes.initialize(from: data, count: data.count) }
    deinit { bytes.deallocate() }
}
private func mxSent(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
    if let context { Unmanaged<MXOutgoingReport>.fromOpaque(context).release() }
}
private func mxReport(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
    guard let context, result == kIOReturnSuccess, reportLength > 0 else { return }
    let session = Unmanaged<MXHIDSession>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    MainActor.assumeIsolated { session.receive(bytes, reportID: reportID) }
}

@MainActor
private final class MXHIDSession {
    let device: IOHIDDevice
    var index: UInt8 = 0xFF
    var onReport: ((MXMasterProtocol.Report) -> Void)?
    private let storage = MXReportBuffer()
    private var buffer: UnsafeMutablePointer<UInt8> { storage.pointer }
    private var pending: (UInt8, UInt8, CheckedContinuation<[UInt8]?, Never>)?
    private var timeout: Task<Void, Never>?
    private var opened = false
    init(device: IOHIDDevice) { self.device = device }
    func open() -> Bool {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        opened = true
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, mxReport, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return true
    }
    func close() {
        guard opened else { return }; opened = false
        timeout?.cancel(); pending?.2.resume(returning: nil); pending = nil
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    func send(_ feature: UInt8, _ function: UInt8, _ params: [UInt8]) -> Bool {
        guard opened else { return false }
        let bytes = MXMasterProtocol.request(device: index, feature: feature, function: function, params: params)
        let outgoing = MXOutgoingReport(bytes)
        let context = Unmanaged.passRetained(outgoing).toOpaque()
        let result = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 0x11, outgoing.bytes, bytes.count, 0.5, mxSent, context)
        if result != kIOReturnSuccess { Unmanaged<MXOutgoingReport>.fromOpaque(context).release() }
        return result == kIOReturnSuccess
    }
    func restore(_ feature: UInt8, cid: UInt16) {
        guard opened else { return }
        let bytes = MXMasterProtocol.request(device: index, feature: feature, function: 3, params: [UInt8(cid >> 8), UInt8(cid & 255), 2, 0, 0])
        // Bounded synchronous teardown: finish the restore write before closing its handle.
        _ = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 0x11, $0.baseAddress!, $0.count, 0.2, nil, nil)
        }
    }
    func request(_ feature: UInt8, _ function: UInt8, _ params: [UInt8] = []) async -> [UInt8]? {
        guard opened, pending == nil, !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            pending = (feature, function, continuation)
            guard send(feature, function, params) else { pending = nil; continuation.resume(returning: nil); return }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let request = self.pending else { return }
                self.pending = nil; request.2.resume(returning: nil)
            }
        }
    }
    func feature(_ id: UInt16) async -> UInt8? {
        guard let result = await request(0, 0, [UInt8(id >> 8), UInt8(id & 255), 0]), let index = result.first, index != 0 else { return nil }
        return index
    }
    func receive(_ bytes: [UInt8], reportID: UInt32) {
        guard let report = MXMasterProtocol.parse(bytes, reportID: reportID), report.device == index else { return }
        if let pending, report.software == MXMasterProtocol.softwareID,
           report.feature == pending.0, [pending.1, (pending.1 + 1) & 15].contains(report.function) {
            self.pending = nil; timeout?.cancel(); pending.2.resume(returning: report.params); return
        }
        if let pending, report.feature == 0xFF, report.params.count >= 2,
           report.function == pending.0 >> 4, report.software == pending.0 & 15,
           report.params[0] == (pending.1 << 4 | MXMasterProtocol.softwareID) {
            self.pending = nil; timeout?.cancel(); pending.2.resume(returning: nil); return
        }
        if report.software == 0 { onReport?(report) }
    }
}

@MainActor
final class MXMasterHIDBridge {
    private var manager: IOHIDManager?
    private var worker: Task<Void, Never>?
    private var session: MXHIDSession?
    private var controls: [MXMasterProtocol.Control] = []
    private var feature: UInt8?
    private var batteryFeature: UInt8?
    private var unifiedBattery = false
    private var diverted: Set<UInt16> = []
    private var pressed: Set<UInt16> = []
    private var lastBattery = Date.distantPast
    private let store = RemoteMappingStore.shared
    let standard = MXStandardMouseBridge()

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, 0); self.manager = manager
        standard.start()
        worker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private func devices() -> [IOHIDDevice] {
        guard let manager, let values = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(values)
    }
    static func number(_ device: IOHIDDevice, _ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
    private func tick() async {
        standard.ensureTap()
        let devices = devices()
        if let session, !devices.contains(where: { CFEqual($0, session.device) }) { disconnect() }
        if session == nil {
            for device in devices {
                let pid = Self.number(device, kIOHIDProductIDKey)
                let outputSize = Self.number(device, kIOHIDMaxOutputReportSizeKey)
                guard (MXMasterProtocol.productIDs.contains(pid) || pid == MXMasterProtocol.receiverPID), outputSize >= 20 else { continue }
                let candidate = MXHIDSession(device: device)
                guard candidate.open() else { continue }
                for slot: UInt8 in pid == MXMasterProtocol.receiverPID ? Array(1...6) : [0xFF] {
                    guard !Task.isCancelled else { candidate.close(); return }
                    candidate.index = slot
                    guard let controlFeature = await candidate.feature(0x1B04) else { continue }
                    if pid == MXMasterProtocol.receiverPID {
                        guard let nameFeature = await candidate.feature(5), let length = await candidate.request(nameFeature, 0)?.first else { continue }
                        var name = [UInt8]()
                        while name.count < min(Int(length), 80) {
                            guard let chunk = await candidate.request(nameFeature, 1, [UInt8(name.count)]), !chunk.isEmpty else { break }
                            name += chunk.prefix(Int(length) - name.count)
                        }
                        guard String(bytes: name, encoding: .utf8)?.localizedCaseInsensitiveContains("MX Master 3S") == true else { continue }
                    }
                    session = candidate; feature = controlFeature
                    candidate.onReport = { [weak self] in self?.receive($0) }
                    if let count = await candidate.request(controlFeature, 0)?.first {
                        for i in 0..<min(count, 32) {
                            if let params = await candidate.request(controlFeature, 1, [i]), let control = MXMasterProtocol.Control.parse(params) { controls.append(control) }
                        }
                    }
                    guard !Task.isCancelled else { candidate.close(); return }
                    batteryFeature = await candidate.feature(0x1004); unifiedBattery = batteryFeature != nil
                    if batteryFeature == nil { batteryFeature = await candidate.feature(0x1000) }
                    guard !Task.isCancelled else { candidate.close(); return }
                    store.connected.insert(.mxMaster3s)
                    store.status[.mxMaster3s] = "已连接 · \(pid == MXMasterProtocol.receiverPID ? "Logi Bolt" : "蓝牙")"
                    lastBattery = .distantPast
                    break
                }
                if session == nil { candidate.close() } else { break }
            }
        }
        guard let session, let feature, !Task.isCancelled else { return }
        let active = store.isEnabled(.mxMaster3s) && !store.editing
        let learning = store.learning == .mxMaster3s
        let desired = Set(controls.filter { $0.divertable && active && (learning || store.mapping(.mxMaster3s, MXMasterProtocol.id($0.cid)) != nil) }.map(\.cid))
        // Only divert controls the firmware advertises and the user has configured.
        for cid in diverted.subtracting(desired) {
            guard !Task.isCancelled else { return }
            if await session.request(feature, 3, [UInt8(cid >> 8), UInt8(cid & 255), 2, 0, 0]) != nil { diverted.remove(cid); release(cid) }
        }
        for cid in desired.subtracting(diverted) {
            guard !Task.isCancelled else { return }
            if await session.request(feature, 3, [UInt8(cid >> 8), UInt8(cid & 255), 3, 0, 0]) != nil { diverted.insert(cid) }
            else { store.status[.mxMaster3s] = "部分按键接管失败，请检查是否有其他鼠标映射软件占用。" }
        }
        standard.diverted = diverted
        if Date().timeIntervalSince(lastBattery) > 30, let batteryFeature {
            if let params = await session.request(batteryFeature, unifiedBattery ? 1 : 0), let battery = MXMasterProtocol.battery(params) {
                store.battery[.mxMaster3s] = battery
            } else { store.battery[.mxMaster3s] = nil }
            guard !Task.isCancelled else { return }
            // Firmware may clear temporary diversion after sleep; verify and restore on the next tick.
            for cid in diverted {
                if let state = await session.request(feature, 2, [UInt8(cid >> 8), UInt8(cid & 255)]), state.count >= 3, state[2] & 1 == 0 {
                    diverted.remove(cid); release(cid)
                }
            }
            lastBattery = Date()
        }
    }
    private func receive(_ report: MXMasterProtocol.Report) {
        if report.feature == batteryFeature, report.function == 0 {
            store.battery[.mxMaster3s] = MXMasterProtocol.battery(report.params); return
        }
        guard report.feature == feature, report.function == 0 else { return }
        let now = MXMasterProtocol.pressed(report.params).intersection(diverted)
        for cid in pressed.subtracting(now) { release(cid) }
        for cid in now.subtracting(pressed) {
            if let button = RemoteProfiles.mxButtons.first(where: { $0.id == MXMasterProtocol.id(cid) }) {
                store.post(button: button, remote: .mxMaster3s, isDown: true)
            }
        }
        pressed = now
    }
    private func release(_ cid: UInt16) {
        if let button = RemoteProfiles.mxButtons.first(where: { $0.id == MXMasterProtocol.id(cid) }) { store.post(button: button, remote: .mxMaster3s, isDown: false) }
        pressed.remove(cid)
    }
    private func disconnect() {
        if let session, let feature {
            for cid in diverted { session.restore(feature, cid: cid) }
        }
        store.releaseAll(for: .mxMaster3s)
        session?.close(); session = nil; controls = []; diverted = []; pressed = []; feature = nil; batteryFeature = nil
        standard.diverted = []; store.connected.remove(.mxMaster3s); store.battery[.mxMaster3s] = nil
        store.status[.mxMaster3s] = "未连接；请通过蓝牙或 Logi Bolt 连接 MX Master 3S。"
    }
    func stop() {
        worker?.cancel(); worker = nil; disconnect(); standard.stop()
        if let manager { IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue); IOHIDManagerClose(manager, 0) }
        manager = nil
    }
}
