import Foundation
import Combine

@MainActor
final class NUT65Store: ObservableObject {
    @Published private(set) var snapshot: NUT65Snapshot?
    @Published private(set) var busy = false
    @Published private(set) var status = "连接 USB 数据线后，读取键盘映射。"
    @Published private(set) var failed = false
    @Published private(set) var lastBackup: URL?
    @Published private(set) var undo: Change?
    private let queue = DispatchQueue(label: "com.gumu.codexmicro.nut65", qos: .userInitiated)

    struct Change: Sendable {
        let layer: Int
        let key: NUT65Key
        let before: UInt16
        let after: UInt16
    }
    struct Result: Sendable {
        let snapshot: NUT65Snapshot
        let backup: URL?
    }
    nonisolated static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexMicro/NUT65/Backups", isDirectory: true)
    }

    func read() {
        guard !busy else { return }
        run(message: "正在读取全部映射层…", operation: {
            let connection = try NUT65Connection()
            return Result(snapshot: try connection.readSnapshot(), backup: nil)
        }) { result in
            self.status = "已读取 \(result.snapshot.layers.count) 层映射 · 协议 \(result.snapshot.version)"
            self.undo = nil
        }
    }

    func save(code: UInt16, layer: Int, key: NUT65Key, restoring: Bool = false) {
        guard !busy, let expected = snapshot, expected.layers.indices.contains(layer),
              NUT65Layout.keys.contains(where: { $0.id == key.id }) else { return }
        let old = expected.layers[layer][key.id]
        guard old != code else { return }
        run(message: "正在备份、写入并回读核验…", operation: {
            let connection = try NUT65Connection()
            let fresh = try connection.readSnapshot()
            guard fresh.locationID == expected.locationID, fresh.layers == expected.layers else {
                throw NUT65Error.message("设备或映射已变化，请重新读取后再修改。")
            }
            let directory = Self.backupDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let backup = directory.appendingPathComponent("NUT65-\(UUID().uuidString).json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(fresh).write(to: backup, options: .atomic)
            // No retries after a failed write: its outcome may be ambiguous.
            try connection.writeKey(code, layer: layer, row: key.row, column: key.column)
            let verified = try connection.readSnapshot()
            var wanted = fresh.layers; wanted[layer][key.id] = code
            guard verified.layers == wanted else {
                throw NUT65Error.message("写入后检测到其他映射变化，请重新读取。备份已保存在 NUT65/Backups。")
            }
            return Result(snapshot: verified, backup: backup)
        }) { _ in
            self.undo = restoring ? nil : Change(layer: layer, key: key, before: old, after: code)
            self.status = "已写入层 \(layer) · \(key.label) → \(NUT65Keycodes.title(code))，存储回读一致。请在实测区按实体键验证；编辑层不会切换键盘模式。"
        }
    }

    func undoLastChange() {
        guard let change = undo else { return }
        save(code: change.before, layer: change.layer, key: change.key, restoring: true)
    }

    private func run(message: String, operation: @escaping @Sendable () throws -> Result,
                     success: @escaping @MainActor (Result) -> Void) {
        busy = true; failed = false; status = message
        queue.async {
            do {
                let result = try operation()
                Task { @MainActor in
                    self.snapshot = result.snapshot; self.busy = false
                    if let backup = result.backup { self.lastBackup = backup }
                    success(result)
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    self.busy = false; self.failed = true; self.status = message
                    self.snapshot = nil; self.undo = nil
                }
            }
        }
    }
}
