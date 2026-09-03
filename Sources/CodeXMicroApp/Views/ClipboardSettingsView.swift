import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var store: CodexStore
    @ObservedObject var history: ClipboardHistoryStore
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Section("剪贴板历史") {
                Toggle("启用剪贴板历史", isOn: $history.isEnabled)

                Picker("保留历史", selection: $history.retentionDays) {
                    ForEach(ClipboardHistoryStore.retentionOptions, id: \.self) { days in
                        Text(retentionLabel(days)).tag(days)
                    }
                }

                HStack {
                    Text("已保存 \(history.items.count) 项")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空历史", role: .destructive) { confirmsClear = true }
                        .disabled(history.items.isEmpty)
                }
            }

            Section("快速呼出") {
                HStack {
                    Label("侧栏快捷键", systemImage: "keyboard")
                    Spacer()
                    Button {
                        if store.shortcutRecordingTarget == .clipboardHistory {
                            store.cancelShortcutRecording()
                        } else {
                            store.beginShortcutRecording(for: .clipboardHistory)
                        }
                    } label: {
                        Text(
                            store.shortcutRecordingTarget == .clipboardHistory
                                ? "请按键…"
                                : store.shortcut(for: .clipboardHistory)?.displayName ?? "设置…"
                        )
                        .frame(minWidth: 86)
                    }
                    Button {
                        store.restoreDefaultShortcut(for: .clipboardHistory)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        store.shortcut(for: .clipboardHistory)
                            == ShortcutDefaults.bindings[.clipboardHistory]
                    )
                    .help("恢复默认快捷键 ⌃V")
                }

                if let issue = store.shortcutRegistrationIssue(for: .clipboardHistory) {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("按下快捷键后，侧栏会出现在当前屏幕右侧；选择一项即可粘贴回原应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("隐私") {
                Text("文字和图片历史仅保存在这台 Mac 的 Application Support 目录，不会上传。关闭此功能后将停止捕捉，已有历史不会自动删除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("确定清空全部剪贴板历史？", isPresented: $confirmsClear) {
            Button("清空历史", role: .destructive) { history.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func retentionLabel(_ days: Int) -> String {
        switch days {
        case 1: "1 天"
        case 7: "1 周"
        case 30: "1 个月"
        case 180: "6 个月"
        case 365: "1 年"
        default: "永久"
        }
    }
}
