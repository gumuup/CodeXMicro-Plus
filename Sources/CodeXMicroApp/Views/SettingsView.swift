import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CodexStore

    var body: some View {
        TabView {
            Form {
                Section("触感") {
                    Picker("触觉强度", selection: $store.hapticStrength) {
                        ForEach(HapticStrength.allCases) { strength in
                            Text(strength.label).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("机械按键声音", isOn: $store.keySoundEnabled)
                    Text("macOS 只能驱动 Force Touch 触控板的系统触觉，无法让 MacBook 键盘本体逐键震动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("悬浮位置") {
                    Picker("悬浮位置", selection: $store.panelPosition) {
                        ForEach(PanelPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel("悬浮位置")

                    Text(store.panelPosition.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Label("切换快捷键", systemImage: "keyboard")
                        Spacer()
                        Button {
                            if store.shortcutRecordingTarget == .togglePanelPosition {
                                store.cancelShortcutRecording()
                            } else {
                                store.beginShortcutRecording(for: .togglePanelPosition)
                            }
                        } label: {
                            Text(
                                store.shortcutRecordingTarget == .togglePanelPosition
                                    ? "请按键…"
                                    : store.shortcut(for: .togglePanelPosition)?.displayName ?? "设置…"
                            )
                            .frame(minWidth: 86)
                        }

                        Button {
                            store.restoreDefaultShortcut(for: .togglePanelPosition)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            store.shortcut(for: .togglePanelPosition)
                                == ShortcutDefaults.bindings[.togglePanelPosition]
                        )
                        .help("恢复默认快捷键 ⌃P")
                        .accessibilityLabel("恢复悬浮位置默认快捷键")
                    }
                }

                Section("系统权限") {
                    HStack {
                        Label(
                            store.automation.isAccessibilityTrusted ? "辅助功能已授权" : "需要辅助功能权限",
                            systemImage: store.automation.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(store.automation.isAccessibilityTrusted ? .green : .orange)
                        Spacer()
                        if !store.automation.isAccessibilityTrusted {
                            Button("开启辅助功能权限") { store.requestAccessibility() }
                        }
                    }
                    Text("权限用于接管你主动映射的物理按键，并向本机 Codex 发送操作；不保存或上传其他按键数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "slider.horizontal.3") }

            QuickLaunchSettingsView(store: store)
                .tabItem { Label("快速启动", systemImage: "bolt.fill") }

            RadialMenuSettingsView(store: store)
                .tabItem { Label("轮盘", systemImage: "circle.hexagongrid.fill") }

            ShortcutSettingsView(store: store)
                .tabItem { Label("自定义按键", systemImage: "keyboard") }

            VStack(alignment: .leading, spacing: 12) {
                Label("CodeXMicro++", systemImage: "keyboard")
                    .font(.title2.bold())
                Text("CodeXMicro++ 是基于 OpenAI × Work Louder Codex Micro 设计语言的虚拟 macOS 控制面板。非 OpenAI 或 Work Louder 官方产品。")
                Text("Agent 状态只从 ~/.codex 的本地数据库与 rollout 文件读取。")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(minWidth: 780, idealWidth: 780, minHeight: 680, idealHeight: 680)
        .background(SettingsWindowConfigurator())
    }
}

private struct QuickLaunchSettingsView: View {
    @ObservedObject var store: CodexStore
    private let target = ShortcutTarget.quickLaunch

    var body: some View {
        Form {
            Section("快捷键设置") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置全局快捷键快速显示或隐藏悬浮面板")
                        Text("点击右侧按键进入监听，然后直接按下希望使用的真实组合键。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        if isRecording {
                            store.cancelShortcutRecording()
                        } else {
                            store.beginShortcutRecording(for: target)
                        }
                    } label: {
                        Text(isRecording ? "请按键…" : binding?.displayName ?? "设置…")
                            .frame(minWidth: 108)
                    }
                    .controlSize(.large)
                }

                HStack {
                    Spacer()
                    Button("恢复默认") {
                        store.restoreDefaultShortcut(for: target)
                    }
                    .disabled(binding == ShortcutDefaults.bindings[target])
                }

                if isRecording {
                    Label(
                        store.feedbackMessage ?? "请按下新的快速启动组合键",
                        systemImage: "keyboard.badge.ellipsis"
                    )
                    .foregroundStyle(.blue)
                }
            }

            Section("热键状态") {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("重新检查") {
                        store.retryShortcutMonitoring(for: target)
                    }
                }
                .padding(.vertical, 6)

                Text("重新检查会再次读取 macOS 系统快捷键并重新注册该组合。快捷键仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("使用说明") {
                Label("默认快捷键为 Option + Space（⌥Space）", systemImage: "keyboard")
                Label("与 macOS 系统快捷键重合时仍会保存，并在热键状态中标红提醒。", systemImage: "exclamationmark.triangle")
                Label("与本应用其他功能重复时会拒绝保存。", systemImage: "xmark.shield")
                Label("若系统快捷键发生变化，请在热键状态中重新检查。", systemImage: "checkmark.shield")
            }
        }
        .formStyle(.grouped)
    }

    private var binding: KeyboardShortcutBinding? {
        store.shortcut(for: target)
    }

    private var isRecording: Bool {
        store.shortcutRecordingTarget == target
    }

    private var statusTitle: String {
        guard binding != nil else { return "尚未设置快速启动热键" }
        if let issue = store.shortcutRegistrationIssue(for: target) { return issue }
        return store.isShortcutActive(target) ? "热键正常" : "热键监听未启动"
    }

    private var statusDetail: String {
        guard let binding else { return "设置一个组合键后即可使用快速启动。" }
        if store.shortcutRegistrationIssue(for: target) != nil {
            return "该组合键未被接管，请修改快捷键或重新检查。"
        }
        return store.isShortcutActive(target)
            ? "\(binding.displayName) 已启用，可在任意应用中显示或隐藏悬浮面板。"
            : "\(binding.displayName) 已保存，请重新启动监听。"
    }

    private var statusIcon: String {
        guard binding != nil else { return "pause.circle.fill" }
        guard store.shortcutRegistrationIssue(for: target) == nil else {
            return "exclamationmark.triangle.fill"
        }
        return store.isShortcutActive(target) ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        guard binding != nil else { return .secondary }
        guard store.shortcutRegistrationIssue(for: target) == nil else { return .red }
        return store.isShortcutActive(target) ? .green : .red
    }
}
