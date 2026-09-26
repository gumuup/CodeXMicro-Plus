import Foundation
import IOKit.hid

// Confined to one worker thread, including the callback's run loop. Never seizes
// the keyboard interface; the matching dictionary selects only its raw HID port.
final class NUT65Connection {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private final class ReportBuffer {
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        deinit { pointer.deallocate() }
    }
    private let storage = ReportBuffer()
    private var buffer: UnsafeMutablePointer<UInt8> { storage.pointer }
    private var replies: [[UInt8]] = []
    private let reportSize: Int
    let locationID: Int

    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: NUT65Protocol.vendorID,
            kIOHIDProductIDKey: NUT65Protocol.productID,
            kIOHIDPrimaryUsagePageKey: 0xff60,
            kIOHIDPrimaryUsageKey: 0x61
        ] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard devices.count == 1, let found = devices.first else {
            throw NUT65Error.message(devices.isEmpty ? "未找到 NUT65 有线接口，请切到有线模式并连接 USB 数据线。" : "检测到多把 NUT65，请只连接需要修改的一把。")
        }
        guard (IOHIDDeviceGetProperty(found, kIOHIDTransportKey as CFString) as? String) == "USB" else {
            throw NUT65Error.message("请使用 USB 有线连接进行改键。")
        }
        device = found
        locationID = (IOHIDDeviceGetProperty(found, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
        reportSize = (IOHIDDeviceGetProperty(found, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        guard reportSize == 32 || reportSize == 64 else {
            throw NUT65Error.message("不支持的 HID 报告长度：\(reportSize)")
        }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, 0)
            throw NUT65Error.message("无法打开 NUT65（\(result)），请关闭占用键盘的网页驱动后重试。")
        }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, bytes, count in
            guard result == kIOReturnSuccess, let context, count > 0, count <= 64 else { return }
            let connection = Unmanaged<NUT65Connection>.fromOpaque(context).takeUnretainedValue()
            connection.replies.append(Array(UnsafeBufferPointer(start: bytes, count: count)))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, 0)
    }

    func exchange(_ command: [UInt8], minimum: Int, echoCount: Int) throws -> [UInt8] {
        replies.removeAll()
        let packet = try NUT65Protocol.packet(command, size: reportSize)
        let sent = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, packet.count)
        }
        guard sent == kIOReturnSuccess else { throw NUT65Error.message("USB 发送失败（\(sent)），请检查有线连接。") }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            while !replies.isEmpty {
                let reply = replies.removeFirst()
                if reply.count >= minimum, reply.prefix(echoCount).elementsEqual(command.prefix(echoCount)) { return reply }
            }
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
        }
        throw NUT65Error.message("键盘响应超时或不匹配，请关闭网页驱动并重新读取。若刚执行写入，请先读取确认实际状态。")
    }

    func readSnapshot() throws -> NUT65Snapshot {
        let protocolReply = try exchange([1], minimum: 3, echoCount: 1)
        let version = Int(protocolReply[1]) << 8 | Int(protocolReply[2])
        guard version == 12 else { throw NUT65Error.message("当前协议版本 \(version) 尚未验证，已停止改键。") }
        let layerCount = Int(try exchange([17], minimum: 2, echoCount: 1)[1])
        guard (1...16).contains(layerCount) else { throw NUT65Error.message("键盘层数异常：\(layerCount)") }
        var layers: [[UInt16]] = []
        for layer in 0..<layerCount {
            var bytes: [UInt8] = []
            for position in stride(from: 0, to: NUT65Protocol.keysPerLayer * 2, by: 28) {
                let length = min(28, NUT65Protocol.keysPerLayer * 2 - position)
                let offset = layer * NUT65Protocol.keysPerLayer * 2 + position
                let reply = try exchange([18, UInt8(offset >> 8), UInt8(offset & 255), UInt8(length)], minimum: length + 4, echoCount: 4)
                bytes += reply[4..<(4 + length)]
            }
            layers.append(try NUT65Protocol.decode(bytes))
        }
        let snapshot = NUT65Snapshot(capturedAt: Date(), vendorID: NUT65Protocol.vendorID,
                                     productID: NUT65Protocol.productID, locationID: locationID, version: version, layers: layers)
        try snapshot.validate()
        return snapshot
    }

    func readKey(layer: Int, row: Int, column: Int) throws -> UInt16 {
        let command = try NUT65Protocol.keyCommand(layer: layer, row: row, column: column)
        let reply = try exchange(command, minimum: 6, echoCount: 4)
        return UInt16(reply[4]) << 8 | UInt16(reply[5])
    }

    func writeKey(_ code: UInt16, layer: Int, row: Int, column: Int) throws {
        let command = try NUT65Protocol.keyCommand(write: code, layer: layer, row: row, column: column)
        _ = try exchange(command, minimum: 6, echoCount: 6)
        guard try readKey(layer: layer, row: row, column: column) == code else {
            throw NUT65Error.message("写入后的回读结果不同，请重新读取；写入前的备份已保留。")
        }
    }
}
