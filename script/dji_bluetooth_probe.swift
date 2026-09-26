// Diagnostic only: no pairing, device commands, audio capture, or key injection.
// Build: swiftc script/dji_bluetooth_probe.swift -o .build/dji-bluetooth-probe
import Foundation
import CoreBluetooth
import IOBluetooth

func report(_ message: String) {
    print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
    fflush(stdout)
}

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var seen = Set<UUID>()
    var target: CBPeripheral?
    let listening = CommandLine.arguments.contains("--listen")
    var notificationCount = 0
    func start() {
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard device.name?.localizedCaseInsensitiveContains("DJI") == true else { continue }
            report("CLASSIC name=\(device.name ?? "?") connected=\(device.isConnected())")
            for service in device.services as? [IOBluetoothSDPServiceRecord] ?? [] {
                report("SDP \(service.getServiceName() ?? "unnamed") attributes=\(service.attributes ?? [:])")
            }
        }
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        report("BLE state=\(central.state.rawValue) (5=poweredOn, 3=unauthorized)")
        guard central.state == .poweredOn else { return }
        // Do not connect or subscribe: first establish whether DJI advertises BLE.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        report("SCAN started; only DJI-named advertisements are logged")
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.localizedCaseInsensitiveContains("DJI"), seen.insert(peripheral.identifier).inserted else { return }
        report("BLE DJI name=\(name) id=\(peripheral.identifier) advertisement=\(advertisementData)")
        if listening, name == "DJI Mic Mini 2-E7DCC2", target == nil {
            target = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        report("BLE connected; discovering services")
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        report("CONNECT failed: \(String(describing: error))")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        report("DISCONNECTED \(String(describing: error))")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        report("SERVICES error=\(String(describing: error))")
        for service in peripheral.services ?? [] {
            report("SERVICE \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        report("CHARACTERISTICS service=\(service.uuid) error=\(String(describing: error))")
        for characteristic in service.characteristics ?? [] {
            report("CHAR \(characteristic.uuid) properties=\(characteristic.properties.rawValue)")
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                // Standard notification subscription only; never write vendor commands.
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        report("SUBSCRIBE \(characteristic.uuid) active=\(characteristic.isNotifying) error=\(String(describing: error))")
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        notificationCount += 1
        guard notificationCount <= 2000 else { return } // Bounded diagnostic output.
        let hex = (characteristic.value ?? Data()).prefix(128).map { String(format: "%02x", $0) }.joined(separator: " ")
        report("NOTIFY \(characteristic.uuid) bytes=\(characteristic.value?.count ?? 0) hex=\(hex) error=\(String(describing: error))")
    }
}
let probe = Probe()
probe.start()
RunLoop.main.run(until: Date().addingTimeInterval(probe.listening ? 300 : 25))
probe.central.stopScan()
if let target = probe.target { probe.central.cancelPeripheralConnection(target) }
report("DONE DJI-named BLE devices=\(probe.seen.count); absence does not exclude hidden/private Bluetooth services")
