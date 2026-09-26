import Foundation
import Testing
@testable import CodeXMicroApp

@Test func djiBatteryTransientFailureKeepsIdentityTimestampAndExpires() {
    let now = Date(timeIntervalSince1970: 1000)
    let fresh = DJIBluetoothDevice.retainingRecentBattery([
        .init(id: "AA:BB", name: "DJI A", batteryPercent: 80),
        .init(id: "CC:DD", name: "DJI B", batteryPercent: 60)
    ], previous: [], now: now)
    let missing: [DJIBluetoothDevice] = [.init(id: "aa-bb", name: "DJI A", batteryPercent: nil)]
    let cached = DJIBluetoothDevice.retainingRecentBattery(missing, previous: fresh, now: now.addingTimeInterval(30))
    #expect(cached.count == 1) // Disconnected B is removed, never copied to A.
    #expect(cached[0].batteryPercent == 80)
    #expect(cached[0].batteryIsCached)
    #expect(cached[0].batteryReadAt == now)
    let expired = DJIBluetoothDevice.retainingRecentBattery(missing, previous: cached, now: now.addingTimeInterval(601))
    #expect(expired[0].batteryPercent == nil)
    let changed = DJIBluetoothDevice.retainingRecentBattery([
        .init(id: "AA:BB", name: "DJI A", batteryPercent: 0)
    ], previous: cached, now: now.addingTimeInterval(60))
    #expect(changed[0].batteryPercent == 0) // Explicit system-reported zero is valid.
    #expect(!changed[0].batteryIsCached)
    #expect(DJIBluetoothDevice.retainingRecentBattery([], previous: cached, now: now).isEmpty)
}

@Test func djiBluetoothKeepsTwoIdentitiesAndMissingBatteryUnknown() throws {
    #expect(DJIBluetoothDevice.normalizedAddress("4C-43-F6-DF-F8-86") == DJIBluetoothDevice.normalizedAddress("4c:43:f6:df:f8:86"))
    let data = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"DJI Mic Mini 2-A":{"device_address":"AA","device_batteryLevelMain":"75%"}},{"DJI Mic Mini 2-B":{"device_address":"BB"}},{"Other":{"device_address":"CC","device_batteryLevelMain":"50%"}}],"device_not_connected":[{"DJI Mic Mini 2-C":{"device_address":"DD"}}]}]}"#.utf8)
    let devices = try DJIBluetoothDevice.parse(data)
    #expect(devices.count == 2)
    #expect(devices.map(\.id) == ["AA", "BB"])
    #expect(devices[0].batteryPercent == 75)
    #expect(devices[1].batteryPercent == nil)
}

@Test func djiBluetoothRejectsInvalidPercentAndDropsDisconnectedDevices() throws {
    for value in ["101%", "-1%", "unknown"] {
        let object: [String: Any] = ["SPBluetoothDataType": [["device_connected": [["DJI Mic Mini 2-A": ["device_address": "AA", "device_batteryLevelMain": value]]]]]]
        #expect(try DJIBluetoothDevice.parse(JSONSerialization.data(withJSONObject: object)).first?.batteryPercent == nil)
    }
    #expect(try DJIBluetoothDevice.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
}
