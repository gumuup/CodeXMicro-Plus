// HID++ framing, control discovery and battery decoding adapted from
// TomBadash/Mouser core/hid_gesture.py (MIT). See ThirdParty/Mouser.
import Foundation

struct PeripheralBattery: Equatable, Sendable {
    let percent: Int
    let charging: Bool
    init?(percent: Int, charging: Bool = false) {
        guard (0...100).contains(percent) else { return nil }
        self.percent = percent; self.charging = charging
    }
}

enum MXMasterProtocol {
    static let softwareID: UInt8 = 0x0A
    static let productIDs: Set<Int> = [0xB034, 0xB043]
    static let receiverPID = 0xC548
    static let controlNames: [UInt16: (String, String)] = [
        0x50: ("左键", "computermouse"), 0x51: ("右键", "computermouse"),
        0x52: ("中键 / 滚轮按下", "circle.inset.filled"),
        0x53: ("后退键", "chevron.backward"), 0x56: ("前进键", "chevron.forward"),
        0xC3: ("拇指手势键", "hand.point.up.left"), 0xC4: ("顶部模式键", "arrow.triangle.2.circlepath")
    ]
    static func id(_ cid: UInt16) -> String { String(format: "mx%04X", cid) }
    static func request(device: UInt8, feature: UInt8, function: UInt8, params: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11; bytes[1] = device; bytes[2] = feature; bytes[3] = (function << 4) | softwareID
        for (i, value) in params.prefix(16).enumerated() { bytes[i + 4] = value }
        return bytes
    }
    struct Report: Equatable {
        let device: UInt8; let feature: UInt8; let function: UInt8; let software: UInt8; let params: [UInt8]
    }
    static func parse(_ bytes: [UInt8], reportID: UInt32) -> Report? {
        guard reportID == 0x10 || reportID == 0x11 else { return nil }
        let offset = bytes.first == UInt8(reportID) ? 1 : 0
        guard bytes.count >= offset + 3 else { return nil }
        let function = bytes[offset + 2]
        return Report(device: bytes[offset], feature: bytes[offset+1], function: function >> 4, software: function & 15, params: Array(bytes.dropFirst(offset+3)))
    }
    static func battery(_ params: [UInt8]) -> PeripheralBattery? {
        guard let level = params.first else { return nil }
        return PeripheralBattery(percent: Int(level), charging: params.count > 2 && (1...4).contains(params[2]))
    }
    static func pressed(_ params: [UInt8]) -> Set<UInt16> {
        var values = Set<UInt16>()
        for i in stride(from: 0, to: params.count - params.count % 2, by: 2) {
            let cid = UInt16(params[i]) << 8 | UInt16(params[i+1])
            if cid == 0 { break }; values.insert(cid)
        }
        return values
    }
    struct Control: Equatable {
        let cid: UInt16
        let divertable: Bool
        static func parse(_ params: [UInt8]) -> Control? {
            guard params.count >= 9 else { return nil }
            return Control(cid: UInt16(params[0]) << 8 | UInt16(params[1]), divertable: params[4] & 0x20 != 0)
        }
    }
}

/// A hardware edge is consumed once and expires quickly; unrelated pointer input passes through.
struct MXPhysicalEventMatcher {
    private var events: [(String, Bool, Double)] = []
    mutating func record(id: String, down: Bool, time: Double) {
        events.append((id, down, time))
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }
    mutating func consume(id: String, down: Bool, time: Double) -> Bool {
        events.removeAll { time - $0.2 > 0.06 }
        guard let index = events.lastIndex(where: { $0.0 == id && $0.1 == down && abs(time - $0.2) < 0.06 }) else { return false }
        events.remove(at: index); return true
    }
}
