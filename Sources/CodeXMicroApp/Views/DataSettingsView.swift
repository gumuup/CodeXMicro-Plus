import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @ObservedObject private var manager = AppDataManager.shared
    @State private var selectedDirectory = AppDataManager.shared.dataDirectoryURL
    @State private var cleanupReport: CleanupReport?
    @State private var notice: DataNotice?

    var body: some View {
        Form {
            Section("数据保存路径") {
                HStack(spacing: 10) {
                    Image(systemName: selectedDirectory == manager.dataDirectoryURL
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill")
                        .foregroundStyle(selectedDirectory == manager.dataDirectoryURL ? .green : .orange)
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(selectedDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择存储路径") {
                        if let url = DataPanelPresenter.chooseDirectory(startingAt: selectedDirectory) {
                            selectedDirectory = url
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        guard DataPanelPresenter.confirm(
                            title: "从所选路径恢复数据？",
                            message: "所选路径中的设置和自定义素材将成为当前数据。恢复后请重新启动应用。",
                            destructiveButton: "恢复数据"
                        ) else { return }
                        perform("已从所选路径恢复数据，请重新启动 CodeXMicro++。") {
                            try manager.adoptData(at: selectedDirectory)
                        }
                    } label: {
                        Label("从路径中还原数据", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedDirectory == manager.dataDirectoryURL)

                    Button {
                        guard DataPanelPresenter.confirm(
                            title: "用当前数据覆盖所选路径？",
                            message: "所选路径中已有的 CodeXMicro++ 设置和自定义素材将被替换。",
                            destructiveButton: "覆盖并切换"
                        ) else { return }
                        perform("已保存当前数据并切换数据路径。") {
                            try manager.overwriteData(at: selectedDirectory)
                        }
                    } label: {
                        Label("当前数据覆盖路径数据", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedDirectory == manager.dataDirectoryURL)
                }
            }

            Section("数据备份与恢复") {
                Text("备份文件包含应用设置、快捷键、轮盘配置和自定义图标，不包含 ~/.codex 中的 Codex 客户端数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        guard let destination = DataPanelPresenter.chooseBackupDestination() else { return }
                        perform("数据备份已创建：\(destination.lastPathComponent)") {
                            try manager.createBackup(at: destination)
                        }
                    } label: {
                        Label("备份", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        guard let archive = DataPanelPresenter.chooseBackupArchive() else { return }
                        guard DataPanelPresenter.confirm(
                            title: "恢复此备份？",
                            message: "当前设置和自定义素材将被备份内容替换。恢复后请重新启动应用。",
                            destructiveButton: "恢复"
                        ) else { return }
                        perform("备份恢复完成，请重新启动 CodeXMicro++。") {
                            try manager.restoreBackup(from: archive)
                        }
                    } label: {
                        Label("恢复", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section("数据库修复") {
                dataActionRow(
                    title: "检查数据状态",
                    detail: "检测设置文件、快捷键与自定义素材引用是否完整",
                    icon: "checkmark.circle.fill",
                    color: .blue,
                    button: "检查"
                ) {
                    performReport { try manager.checkIntegrity().summary }
                }

                dataActionRow(
                    title: "修复数据存储",
                    detail: "移除无法读取的设置项，并根据当前有效数据重建存储",
                    icon: "wrench.and.screwdriver.fill",
                    color: .orange,
                    button: "修复"
                ) {
                    guard DataPanelPresenter.confirm(
                        title: "修复数据存储？",
                        message: "无法读取的设置项会被移除；建议先创建备份。",
                        destructiveButton: "修复"
                    ) else { return }
                    performReport { try manager.repairDataStore().summary }
                }

                dataActionRow(
                    title: "重建数据存储",
                    detail: "清空应用设置和自定义素材，并在下次启动时恢复默认值",
                    icon: "arrow.clockwise.circle.fill",
                    color: .red,
                    button: "重建"
                ) {
                    guard DataPanelPresenter.confirm(
                        title: "确定重建全部应用数据？",
                        message: "此操作不可撤销。所有 CodeXMicro++ 设置、快捷键、轮盘配置和自定义图标都会被清除。",
                        destructiveButton: "清空并重建"
                    ) else { return }
                    perform("数据已重建，请重新启动 CodeXMicro++。") {
                        try manager.rebuildDataStore()
                    }
                }

                Label("重建操作不可撤销，请确保已经创建备份。不会修改 ~/.codex 或 Codex 客户端数据库。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("数据清理") {
                Text(cleanupReport?.summary ?? "检查并清理未被任何轮盘配置引用的自定义素材。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        performReport {
                            let report = try manager.inspectRedundantData()
                            cleanupReport = report
                            return report.summary
                        }
                    } label: {
                        Label("检查冗余数据", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        guard let cleanupReport, cleanupReport.fileCount > 0 else { return }
                        guard DataPanelPresenter.confirm(
                            title: "清理冗余数据？",
                            message: "将删除 \(cleanupReport.fileCount) 个未使用的自定义素材，此操作不可撤销。",
                            destructiveButton: "清理"
                        ) else { return }
                        performReport {
                            let report = try manager.cleanRedundantData()
                            self.cleanupReport = CleanupReport(fileCount: 0, byteCount: 0)
                            return "已清理 \(report.fileCount) 个文件。"
                        }
                    } label: {
                        Label("清理冗余数据", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(cleanupReport?.fileCount ?? 0 == 0)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedDirectory = manager.dataDirectoryURL
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.isError ? "操作失败" : "数据管理"),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    @ViewBuilder
    private func dataActionRow(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action)
        }
    }

    private func perform(_ successMessage: String, operation: () throws -> Void) {
        do {
            try operation()
            selectedDirectory = manager.dataDirectoryURL
            cleanupReport = nil
            notice = DataNotice(message: successMessage, isError: false)
        } catch {
            notice = DataNotice(message: error.localizedDescription, isError: true)
        }
    }

    private func performReport(operation: () throws -> String) {
        do {
            notice = DataNotice(message: try operation(), isError: false)
        } catch {
            notice = DataNotice(message: error.localizedDescription, isError: true)
        }
    }
}

private struct DataNotice: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@MainActor
private enum DataPanelPresenter {
    static func chooseDirectory(startingAt url: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 CodeXMicro++ 数据保存路径"
        panel.prompt = "选择"
        panel.directoryURL = url
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseBackupDestination() -> URL? {
        let panel = NSSavePanel()
        panel.title = "备份 CodeXMicro++ 数据"
        panel.prompt = "备份"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "CodeXMicro-Backup-\(backupDateString).zip"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseBackupArchive() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 CodeXMicro++ 备份"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.zip]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func confirm(title: String, message: String, destructiveButton: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: destructiveButton)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static var backupDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
