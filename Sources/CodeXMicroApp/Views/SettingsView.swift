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
        .frame(width: 580, height: 520)
    }
}
