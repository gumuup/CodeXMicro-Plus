import Foundation

// Wire format verified against the manufacturer's web driver, 2026-09-26.
// https://weikavnut65.hsgaming.cn/_next/static/chunks/app/page-598c77f1069eba35.js
// Only keymap commands are implemented; no reset, bootloader, or firmware commands.
enum NUT65Protocol {
    static let vendorID = 13357
    static let productID = 58650
    static let rows = 6
    static let columns = 15
    static let keysPerLayer = rows * columns

    static func packet(_ command: [UInt8], size: Int = 64) throws -> [UInt8] {
        guard !command.isEmpty, command.count <= size, size == 32 || size == 64 else {
            throw NUT65Error.message("无效的键盘指令长度")
        }
        return command + Array(repeating: 0, count: size - command.count)
    }
    static func keyCommand(write code: UInt16? = nil, layer: Int, row: Int, column: Int) throws -> [UInt8] {
        guard (0..<16).contains(layer), (0..<rows).contains(row), (0..<columns).contains(column) else {
            throw NUT65Error.message("按键位置或层超出范围")
        }
        var bytes: [UInt8] = [code == nil ? 4 : 5, UInt8(layer), UInt8(row), UInt8(column)]
        if let code { bytes += [UInt8(code >> 8), UInt8(code & 255)] }
        return bytes
    }
    static func decode(_ bytes: [UInt8]) throws -> [UInt16] {
        guard bytes.count.isMultiple(of: 2) else { throw NUT65Error.message("键盘返回的映射数据不完整") }
        return stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
    }
}

enum NUT65Error: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}

struct NUT65Snapshot: Codable, Sendable {
    let capturedAt: Date
    let vendorID: Int
    let productID: Int
    let locationID: Int
    let version: Int
    var layers: [[UInt16]]

    func validate() throws {
        guard vendorID == NUT65Protocol.vendorID, productID == NUT65Protocol.productID,
              version == 12, (1...16).contains(layers.count),
              layers.allSatisfy({ $0.count == NUT65Protocol.keysPerLayer }) else {
            throw NUT65Error.message("键盘协议或映射尺寸不受支持")
        }
    }
}
