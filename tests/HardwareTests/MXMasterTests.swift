import Foundation
import Testing
@testable import CodeXMicroApp

@Test func mxReportsRespectDeviceFeatureAndSoftwareFields() {
    let bytes = MXMasterProtocol.request(device: 3, feature: 7, function: 3, params: [0, 0xC3, 3, 0, 0])
    #expect(bytes.count == 20)
    #expect(Array(bytes.prefix(7)) == [0x11, 3, 7, 0x3A, 0, 0xC3, 3])
    let parsed = MXMasterProtocol.parse(bytes, reportID: 0x11)
    #expect(parsed?.device == 3)
    #expect(parsed?.feature == 7)
    #expect(parsed?.function == 3)
    #expect(parsed?.software == 10)
    #expect(MXMasterProtocol.parse(Array(bytes.dropFirst()), reportID: 0x11) == parsed)
    #expect(MXMasterProtocol.parse([0x11], reportID: 0x11) == nil)
    #expect(MXMasterProtocol.parse(bytes, reportID: 1) == nil)
}
@Test func mxFirmwareControlsAndPressSetsAreBounded() {
    #expect(MXMasterProtocol.Control.parse([0, 0xC3, 0, 0, 0x20, 0, 0, 0, 1])?.divertable == true)
    #expect(MXMasterProtocol.Control.parse([0, 0x50, 0, 0, 0, 0, 0, 0, 0])?.divertable == false)
    #expect(MXMasterProtocol.Control.parse([0, 0x50]) == nil)
    #expect(MXMasterProtocol.pressed([0, 0xC3, 0, 0x52, 0, 0, 0, 0x56]) == [0xC3, 0x52])
    #expect(MXMasterProtocol.pressed([0]) == [])
}
@Test func batteryNeverInventsOrClampsInvalidPercentage() {
    #expect(MXMasterProtocol.battery([50, 0, 1]) == PeripheralBattery(percent: 50, charging: true))
    #expect(MXMasterProtocol.battery([0, 0, 0])?.percent == 0)
    #expect(MXMasterProtocol.battery([100, 0, 3])?.charging == true)
    #expect(MXMasterProtocol.battery([255, 0, 0]) == nil)
    #expect(MXMasterProtocol.battery([]) == nil)
}
@Test func mouseMatchingRejectsUnrelatedStaleAndDuplicateEdges() {
    var matcher = MXPhysicalEventMatcher()
    matcher.record(id: "mx0050", down: true, time: 1)
    let result1 = !matcher.consume(id: "mx0051", down: true, time: 1.01)
    #expect(result1)
    let result2 = !matcher.consume(id: "mx0050", down: false, time: 1.01)
    #expect(result2)
    let result3 = matcher.consume(id: "mx0050", down: true, time: 1.01)
    #expect(result3)
    let result4 = !matcher.consume(id: "mx0050", down: true, time: 1.01)
    #expect(result4)
    matcher.record(id: "mx0050", down: true, time: 2)
    let result5 = !matcher.consume(id: "mx0050", down: true, time: 2.2)
    #expect(result5)
}
