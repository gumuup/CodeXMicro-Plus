import SwiftUI

struct ShortcutSettingsView: View {
    @ObservedObject var store: CodexStore

    var body: some View {
        Form {
            if let recordingTarget = store.shortcutRecordingTarget {
                Section("正在录入") {
                    HStack(spacing: 12) {
                        Label(
                            store.feedbackMessage ?? "为 \(recordingTarget.title) 录入一个物理按键或组合",
                            systemImage: "keyboard.badge.ellipsis"
                        )
                        Spacer()
                        Button("取消") { store.cancelShortcutRecording() }
                    }
                    Text("轻点任意单个物理键即可映射，包括 Home、字母、空格、Esc，以及左 / 右 Shift 等修饰键。按住修饰键再按其他键，则录入组合快捷键。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let feedbackMessage = store.feedbackMessage {
                Section {
                    Label(feedbackMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("物理按键映射状态") {
                HStack(alignment: .center, spacing: 12) {
                    Label(listeningStatusTitle, systemImage: listeningStatusIcon)
                        .foregroundStyle(listeningStatusColor)
                    Spacer()
                    if store.hasDirectKeyBindings && !store.automation.isAccessibilityTrusted {
                        Button("开启辅助功能权限") { store.requestAccessibility() }
                    } else if store.hasDirectKeyBindings && !store.isDirectKeyMonitoringActive {
                        Button("重新启动监听") { store.retryShortcutMonitoring() }
                    }
                }

                Text("映射仅保存在本机；键盘事件只在内存中与已绑定键码比较，未命中内容不记录、不上传。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("录入方式（自动识别）") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("单个物理键 · 一级完整接管", systemImage: "1.circle.fill")
                        .font(.headline)
                    Text("可映射键盘上的任意单键。一级映射会拦截该键的按下、长按和抬起，并覆盖所有使用该键的组合；原本输入或修饰功能不再传给其他应用。语音键按住开始、松开结束。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("带修饰键 · 独占组合快捷键", systemImage: "command")
                        .font(.headline)
                    Text("按住 ⌃⌥⇧⌘ 后再按其他键，会录入独占组合快捷键。若组合已被其他程序独占，则拒绝新设置并保留原绑定。若只想映射 Shift 本身，请单独轻点再松开 Shift。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("自定义按键") {
                ForEach(ShortcutTarget.allCases, id: \.self) { target in
                    ShortcutBindingRow(store: store, target: target)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var listeningStatusTitle: String {
        guard store.hasDirectKeyBindings else { return "尚未配置物理按键映射" }
        guard store.automation.isAccessibilityTrusted else { return "物理按键映射等待授权" }
        if !store.isDirectKeyMonitoringActive { return "物理按键映射未启动" }
        return "物理按键映射已就绪"
    }

    private var listeningStatusIcon: String {
        guard store.hasDirectKeyBindings else { return "pause.circle" }
        guard store.automation.isAccessibilityTrusted else { return "exclamationmark.shield.fill" }
        return store.isDirectKeyMonitoringActive ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }

    private var listeningStatusColor: Color {
        guard store.hasDirectKeyBindings else { return .secondary }
        guard store.automation.isAccessibilityTrusted else { return .orange }
        return store.isDirectKeyMonitoringActive ? .green : .red
    }
}

private struct ShortcutBindingRow: View {
    @ObservedObject var store: CodexStore
    let target: ShortcutTarget

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                if let binding {
                    Text(binding.activationMode.label)
                        .font(.caption)
                        .foregroundStyle(binding.activationMode == .directKey ? Color.indigo : Color.secondary)
                }
                if let issue = store.shortcutRegistrationIssue(for: target) {
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button {
                if store.shortcutRecordingTarget == target {
                    store.cancelShortcutRecording()
                } else {
                    store.beginShortcutRecording(for: target)
                }
            } label: {
                Text(store.shortcutRecordingTarget == target ? "请按键…" : binding?.displayName ?? "设置…")
                    .frame(minWidth: 86)
            }

            if binding != nil {
                Button(role: .destructive) {
                    store.clearShortcut(for: target)
                } label: {
                    Image(systemName: "delete.left")
                }
                .buttonStyle(.borderless)
                .help("清除 \(target.title) 的按键映射")
                .accessibilityLabel("清除 \(target.title) 的按键映射")
            }
        }
    }

    private var binding: KeyboardShortcutBinding? {
        store.shortcut(for: target)
    }
}
