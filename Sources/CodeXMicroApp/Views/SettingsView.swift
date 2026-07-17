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

                Section("系统权限") {
                    HStack {
                        Label(
                            store.automation.isAccessibilityTrusted ? "辅助功能已授权" : "需要辅助功能权限",
                            systemImage: store.automation.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(store.automation.isAccessibilityTrusted ? .green : .orange)
                        Spacer()
                        Button("打开授权提示") { store.requestAccessibility() }
                    }
                    Text("权限只用于向本机 Codex 桌面端发送你主动点击的快捷键，不上传任务或按键数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "slider.horizontal.3") }

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
        .frame(width: 520, height: 340)
    }
}
