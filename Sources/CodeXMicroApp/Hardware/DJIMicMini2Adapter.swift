import AppKit
import Combine
import IOKit.hid

/// Native adaptation of the Consumer HID trigger documented by
/// Johnixr/dji-mic-dictation (MIT). See ThirdParty/DJIMic/NOTICE.md.
struct DJIMicGestureRecognizer {
    static let clickWindow: TimeInterval = 0.35
    static let holdTime: TimeInterval = 0.8
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?
    private var clicks = 0

    mutating func reset() { self = Self() }
    mutating func edge(down: Bool, time: TimeInterval) -> String? {
        if down {
            guard pressedAt == nil else { return nil } // HID repeats are not clicks.
            pressedAt = time
            return nil
        }
        guard let start = pressedAt else { return nil }
        pressedAt = nil
        if time - start >= Self.holdTime { reset(); return "long" }
        clicks += 1; releasedAt = time
        if clicks == 3 { reset(); return "triple" }
        return nil
    }
    mutating func flush(time: TimeInterval) -> String? {
        guard pressedAt == nil, let end = releasedAt,
              time - end >= Self.clickWindow else { return nil }
        let result = clicks == 2 ? "double" : "single"
        reset(); return result
    }
}

private func djiInput(context: UnsafeMutableRawPointer?, result: IOReturn,
                      sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    guard let context, result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let raw = IOHIDValueGetIntegerValue(value)
    let bridge = Unmanaged<DJIMicMini2Adapter>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { bridge.receive(page: page, usage: usage, down: raw != 0) }
}

@MainActor
final class DJIMicMini2Adapter {
    static let vendorID = 0x2CA3
    static let productID = 0x4011
    static func accepts(page: UInt32, usage: UInt32) -> Bool {
        page == 0x0C && (usage == 0xE9 || usage == 0xEA)
    }
    private let store: RemoteMappingStore
    private var manager: IOHIDManager?
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var recognizer = DJIMicGestureRecognizer()
    private var activeUsages: Set<UInt32> = []
    private var openedEnabled: Bool?
    private var deviceIDs: Set<UInt64> = []
    private var captured = false
    private var lastDeviceScan: TimeInterval = -.infinity

    init(store: RemoteMappingStore = .shared) { self.store = store }

    func start() {
        guard timer == nil else { return }
        store.$configuration.sink { [weak self] _ in self?.cancelGesture() }.store(in: &subscriptions)
        store.$editing.sink { [weak self] _ in self?.cancelGesture() }.store(in: &subscriptions)
        store.$learning.sink { [weak self] _ in self?.cancelGesture() }.store(in: &subscriptions)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func open(enabled: Bool) {
        close(); openedEnabled = enabled
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        // Seize only the Consumer Control collection, never USB audio or the
        // vendor-specific settings interface. No global volume interception.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID,
            kIOHIDDeviceUsagePageKey: 0x0C, kIOHIDDeviceUsageKey: 1
        ] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, djiInput, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, enabled ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
            store.status[.djiMicMini2] = "无法打开 DJI 按键接口（\(result)）；请检查输入监控权限及其他映射软件。关闭再启用映射可重试。"
            return
        }
        self.manager = manager; captured = enabled
    }

    private func tick() {
        let enabled = store.isEnabled(.djiMicMini2)
        if openedEnabled != enabled { open(enabled: enabled) }
        guard let manager else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastDeviceScan >= 0.5 {
        lastDeviceScan = now
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let ids = Set(devices.map { device -> UInt64 in
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
            return id
        })
        if ids != deviceIDs {
            cancelGesture(); deviceIDs = ids
            if ids.isEmpty { store.connected.remove(.djiMicMini2) }
            else { store.connected.insert(.djiMicMini2) }
        }
        let status = ids.isEmpty ? "未检测到 USB 按键接口；请通过 USB-C 接收器连接 Mac。"
            : "USB 按键接口已连接 · \(captured ? "映射已启用" : "保留系统行为")；发射器在线状态尚未读取。"
        if store.status[.djiMicMini2] != status { store.status[.djiMicMini2] = status }
        }
        guard captured, enabled, !store.editing, store.learning == nil else { return }
        if let gesture = recognizer.flush(time: ProcessInfo.processInfo.systemUptime) { dispatch(gesture) }
    }

    func receive(page: UInt32, usage: UInt32, down: Bool) {
        guard Self.accepts(page: page, usage: usage) else { return }
        store.inputStatus[.djiMicMini2] = String(format: "连接键 USB 事件：0x%02X · %@", usage, down ? "按下" : "松开")
        guard captured, store.isEnabled(.djiMicMini2), !store.editing else { return }
        if store.learning == .djiMicMini2 {
            if down { store.learnedButton = "link.single"; store.cancelLearning() }
            return
        }
        guard store.learning == nil else { cancelGesture(); return }
        // The two volume usages are NOT evidence of two physical buttons or TX identities.
        let wasDown = !activeUsages.isEmpty
        if down { activeUsages.insert(usage) } else { activeUsages.remove(usage) }
        let isDown = !activeUsages.isEmpty
        guard wasDown != isDown else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let pending = recognizer.flush(time: now) { dispatch(pending) }
        if let gesture = recognizer.edge(down: isDown, time: now) { dispatch(gesture) }
    }

    private func dispatch(_ gesture: String) {
        guard let button = RemoteProfiles.djiButtons.first(where: { $0.id == "link." + gesture }) else { return }
        store.post(button: button, remote: .djiMicMini2, isDown: true)
        store.post(button: button, remote: .djiMicMini2, isDown: false)
    }
    private func cancelGesture() { recognizer.reset(); activeUsages.removeAll() }
    private func close() {
        cancelGesture(); captured = false; deviceIDs = []
        lastDeviceScan = -.infinity
        store.connected.remove(.djiMicMini2)
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
    }
    func stop() {
        timer?.invalidate(); timer = nil; subscriptions.removeAll()
        close(); openedEnabled = nil
    }
}
