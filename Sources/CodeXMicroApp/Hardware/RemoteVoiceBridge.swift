import CoreBluetooth
import Foundation

/// ATVV transport adapted from vRemoter. No provider-specific key or recording
/// files: decoded audio and gesture edges are delivered to the hardware service.
@MainActor
final class RemoteVoiceBridge: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let service = CBUUID(string: ATVVProtocol.serviceUUID)
    private static let command = CBUUID(string: ATVVProtocol.txUUID)
    private static let audio = CBUUID(string: ATVVProtocol.rxUUID)
    private static let control = CBUUID(string: ATVVProtocol.controlUUID)
    let remote: SupportedRemoteID
    var onBattery: ((PeripheralBattery?) -> Void)?
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    var onVoice: ((Bool) -> Void)?
    var onSamples: (([Int16], Int) -> Void)?
    var onStatus: ((String) -> Void)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var protocolHandler = ATVVProtocol()
    private var active = false
    private var streaming = false
    private var microphoneRequested = false
    private var continuousRestarts = 0
    private var openRetries = 0
    private var openRetry: Task<Void, Never>?
    private var didResetSession = false
    func toggleMicrophone() {
        if microphoneRequested { closeMicrophone(); onStatus?("麦克风已关闭") }
        else { continuousRestarts = 0; openRetries = 0; openMicrophone() }
    }
    private var streamID: UInt8 = 0
    private var keepAlive: Timer?
    private var reconnect: Task<Void, Never>?
    private var sessionTimeout: Task<Void, Never>?
    private var notificationCount = 0
    private var lastSearch = Date.distantPast
    private var batteryCharacteristic: CBCharacteristic?
    private var batteryTimer: Timer?

    init(remote: SupportedRemoteID) { self.remote = remote; super.init() }
    func start() {
        guard !active else { return }; active = true
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                if let peripheral = self.peripheral, peripheral.state == .connected {
                    if let characteristic = self.batteryCharacteristic { peripheral.readValue(for: characteristic) }
                    else { peripheral.discoverServices([Self.batteryService]) }
                } else if self.peripheral == nil, self.central?.state == .poweredOn { self.discover() }
            }
        }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central.state == .poweredOn { discover() }
    }
    func stop() {
        active = false; reconnect?.cancel(); sessionTimeout?.cancel()
        batteryTimer?.invalidate(); batteryTimer = nil; batteryCharacteristic = nil
        closeMicrophone(); central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; command = nil; keepAlive?.invalidate(); keepAlive = nil
    }
    func openMicrophone() {
        guard active else { return }
        do {
            protocolHandler.prepareForAudioStream(); try write(protocolHandler.micOpenCommand())
            microphoneRequested = true
            onStatus?("正在开启麦克风…")
            sessionTimeout?.cancel()
            sessionTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.microphoneRequested, !self.streaming else { return }
                self.closeMicrophone(); self.onStatus?("开麦未获设备确认，请再按语音键重试")
            }
        }
        catch { microphoneRequested = false; onStatus?(error.localizedDescription) }
    }
    func closeMicrophone() {
        openRetry?.cancel(); openRetry = nil
        microphoneRequested = false
        if let data = try? protocolHandler.micCloseCommand(streamID: streamID) { try? write(data) }
        finishStream()
    }
    private func finishStream() {
        let wasStreaming = streaming
        streaming = false; protocolHandler.endAudioStream()
        keepAlive?.invalidate(); keepAlive = nil; sessionTimeout?.cancel()
        if wasStreaming { onVoice?(false) }
    }
    private func matches(_ p: CBPeripheral) -> Bool {
        let name = (p.name ?? "").lowercased()
        return remote == .x6 ? name.contains("x6") : name.contains("chromecast")
    }
    private func discover() {
        guard active else { return }
        if let p = central.retrieveConnectedPeripherals(withServices: [Self.service, Self.batteryService]).first(where: matches) { connect(p) }
        else { central.scanForPeripherals(withServices: [Self.service]); onStatus?("等待蓝牙语音连接") }
    }
    private func connect(_ p: CBPeripheral) {
        peripheral = p; p.delegate = self; central.stopScan(); central.connect(p)
        reconnect?.cancel()
        reconnect = Task { [weak self, weak p] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let p, p.state != .connected else { return }
            self.central.cancelPeripheralConnection(p)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { discover() }
        else { microphoneRequested = false; finishStream(); onStatus?(central.state == .unauthorized ? "请允许蓝牙权限" : "蓝牙未开启") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if active, self.peripheral == nil, matches(peripheral) { connect(peripheral) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        didResetSession = false
        reconnect?.cancel(); notificationCount = 0
        protocolHandler = ATVVProtocol(); peripheral.discoverServices([Self.service, Self.batteryService])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { disconnected() }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { disconnected() }
    private func disconnected() {
        openRetry?.cancel(); openRetry = nil
        microphoneRequested = false
        batteryCharacteristic = nil
        finishStream(); peripheral = nil; command = nil; onStatus?("语音蓝牙已断开")
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }; self?.discover()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { onStatus?(error.localizedDescription); return }
        for service in peripheral.services ?? [] {
            if service.uuid == Self.service { peripheral.discoverCharacteristics([Self.command, Self.audio, Self.control], for: service) }
            else if service.uuid == Self.batteryService { peripheral.discoverCharacteristics([Self.batteryLevel], for: service) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { onStatus?(error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.batteryLevel:
                batteryCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
            case Self.command: command = characteristic
            case Self.audio, Self.control: peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { onStatus?(error.localizedDescription); return }
        guard characteristic.uuid != Self.batteryLevel, characteristic.isNotifying else { return }
        notificationCount += 1
        if notificationCount == 2 { try? write(protocolHandler.getCapabilitiesCommand) }
    }
    private func write(_ data: Data) throws {
        guard let peripheral, let command, peripheral.state == .connected else { throw BridgeError.protocolFailure("语音通道尚未就绪") }
        peripheral.writeValue(data, for: command, type: command.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { microphoneRequested = false; onStatus?(error.localizedDescription); finishStream() }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == Self.batteryLevel {
            onBattery?(data.first.flatMap { PeripheralBattery(percent: Int($0)) }); return
        }
        if characteristic.uuid == Self.audio {
            if streaming, let frame = protocolHandler.decodeAudio(data) { onSamples?(frame.samples, protocolHandler.codec?.sampleRate ?? 16000) }
            return
        }
        guard characteristic.uuid == Self.control || characteristic.uuid == Self.command else { return }
        switch protocolHandler.parseControl(data) {
        case let .capabilities(caps):
            do {
                try protocolHandler.acceptCapabilities(caps)
                if remote == .x6, !didResetSession, !microphoneRequested {
                    try write(protocolHandler.micCloseCommand(streamID: 0))
                    didResetSession = true
                }
                onStatus?("蓝牙语音已就绪")
            }
            catch { onStatus?(error.localizedDescription) }
        case .startSearch:
            guard Date().timeIntervalSince(lastSearch) > 0.4 else { return }
            lastSearch = Date()
            // X6 HID owns the toggle. Its BLE Search notification must not
            // reopen the microphone immediately after the second press.
            if remote != .x6, !streaming { openMicrophone() }
        case let .audioStart(_, codec, sid):
            streamID = sid
            if remote == .x6, !microphoneRequested { closeMicrophone(); return }
            let wasStreaming = streaming
            streamID = sid; streaming = true; protocolHandler.beginAudioStream(codec: codec)
            if !wasStreaming { onVoice?(true) }
            if remote == .x6 { onStatus?("麦克风已开启 · 再按语音键关闭") }
            keepAlive?.invalidate()
            keepAlive = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.streaming, let data = try? self.protocolHandler.keepAliveCommand(streamID: self.streamID) else { return }
                    try? self.write(data)
                }
            }
            sessionTimeout?.cancel()
            if remote != .x6 { sessionTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }; self?.closeMicrophone()
            } }
        case .audioStop:
            finishStream()
            if remote == .x6, microphoneRequested {
                // Some firmware stops its initial voice session on release.
                // Reopen without requiring another physical key press, bounded
                // to avoid an endless command loop on incompatible firmware.
                if continuousRestarts < 2 {
                    continuousRestarts += 1; openMicrophone()
                } else {
                    microphoneRequested = false
                    onStatus?("设备结束了持续收音，请重新按语音键开启")
                }
            }
        case let .audioSync(codec, sequence, predictor, stepIndex):
            protocolHandler.applyAudioSync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: stepIndex)
        case let .micOpenError(code):
            finishStream()
            if remote == .x6, microphoneRequested, openRetries < 2 {
                openRetries += 1
                onStatus?("设备暂未接受开麦，正在重试（\(code)）")
                openRetry?.cancel()
                openRetry = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self, self.microphoneRequested, !self.streaming else { return }
                    self.openMicrophone()
                }
            } else {
                microphoneRequested = false; onStatus?("遥控器开麦失败：\(code)")
            }
        case .unknown: break
        }
    }
}
