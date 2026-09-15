import AppKit
import SwiftUI

struct HardwareSettingsView: View {
    @ObservedObject var store: CodexStore
    @ObservedObject private var hardware = RemoteMappingStore.shared
    @State private var remote: SupportedRemoteID = .chromecast
    @State private var selectedButton: RemoteButtonDefinition?
    @State private var audioDevice = RemoteAudioOutput.loopbackDevice()?.1
    @State private var confirmReset = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            deviceList
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    remoteIllustration
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(remote.title).font(.headline)
                                Text("点击按键自定义操作").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("启用映射", isOn: Binding(get: { hardware.isEnabled(remote) }, set: { hardware.setEnabled($0, for: remote) }))
                                .toggleStyle(.switch).controlSize(.small).fixedSize()
                        }
                        HStack {
                            Text(hardware.lastInput).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button(hardware.learning == remote ? "取消监听" : "监听设备") {
                                if hardware.learning == remote { hardware.cancelLearning() } else { hardware.learn(remote) }
                            }.controlSize(.small).disabled(!hardware.isEnabled(remote))
                        }
                        if let status = hardware.inputStatus[remote] { Text(status).font(.caption).foregroundStyle(.secondary) }
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(RemoteProfiles.buttons(for: remote)) { button in
                                    HStack(spacing: 8) {
                                        Label(button.title, systemImage: button.symbol).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                        if button.remappable {
                                            Button { selectedButton = button } label: {
                                                HStack {
                                                    Text(hardware.targetTitle(for: button, remote: remote)).lineLimit(1)
                                                    Spacer(minLength: 3)
                                                    Image(systemName: "chevron.right").font(.caption2)
                                                }.frame(width: 142)
                                            }.buttonStyle(.borderless).help("自定义：\(button.title)")
                                        } else { Text("设备内部功能").font(.caption).foregroundStyle(.secondary) }
                                    }.padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        HStack {
                            Text("关闭映射时保留系统行为").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复默认") { confirmReset = true }.buttonStyle(.borderless).font(.caption)
                        }
                    }
                }.padding(16).frame(maxHeight: .infinity)
                PresetCombinationPicker(selectedIndex: hardware.selectedPreset(for: remote)) { index in
                    hardware.selectPreset(at: index, for: remote)
                }.padding(.horizontal, 16).padding(.bottom, 12)
                Divider()
                if remote != .mxMaster3s {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("使用遥控器麦克风", isOn: Binding(get: { hardware.configuration.remoteMicrophone.contains(remote) }, set: { hardware.setRemoteMicrophone($0, for: remote) }))
                        .toggleStyle(.switch).controlSize(.small)
                    Text("语音键支持任意应用的快捷键或快捷指令，可分别配置按下和松开动作。权限统一在“通用 → 系统权限”管理。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(audioDevice.map { "音频通道：\($0)" } ?? "未检测到虚拟音频设备，可在音频页配置输入与输出。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("重新检测") { audioDevice = RemoteAudioOutput.loopbackDevice()?.1 }.controlSize(.small)
                    }
                    if let status = hardware.status[remote] { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未自定义项显示原生功能名称；Options+ 等驱动可能改变实际行为。支持按下／松开动作与滚轮方向；普通按键需匹配到此鼠标的输入事件。")
                        Text("主键监听时请将指针移出本应用窗口。Logi Options+ 或 Mouser 同时接管时可能冲突。")
                        if let status = hardware.status[remote] { Text(status) }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        }.padding(16)
        .sheet(item: $selectedButton) { button in RemoteButtonEditor(store: store, remote: remote, button: button) }
        .confirmationDialog("恢复 \(remote.title) 当前预设的默认映射？", isPresented: $confirmReset) {
            Button("恢复默认映射") {
                for button in RemoteProfiles.buttons(for: remote) where button.remappable {
                    hardware.setMapping(nil, remote: remote, button: button.id)
                }
            }
        } message: { Text("将清除此型号当前预设的自定义按键配置，其他预设保留。") }
        .onChange(of: hardware.learnedButton) { _, id in
            if let id { selectedButton = RemoteProfiles.buttons(for: remote).first { $0.id == id } }
        }
        .onDisappear { hardware.cancelLearning() }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支持的设备").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(SupportedRemoteID.allCases) { item in
                Button {
                    hardware.cancelLearning(); remote = item
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Circle().fill(hardware.connected.contains(item) ? .green : .gray).frame(width: 6, height: 6)
                            Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        }
                        HStack {
                            Text(item.signature).font(.caption2.monospaced())
                            Spacer()
                            Text(hardware.connected.contains(item) ? "已连接" : "未连接").font(.caption2)
                        }.foregroundStyle(.secondary)
                        if hardware.connected.contains(item) { batteryLabel(item) }
                    }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                        .background(remote == item ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(remote == item ? Color.accentColor.opacity(0.5) : .clear))
                }.buttonStyle(.plain)
            }
            Spacer()
            Label("设置跟随型号保存", systemImage: "checkmark.shield.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(width: 205).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
    }
    private func batteryLabel(_ device: SupportedRemoteID) -> some View {
        HStack(spacing: 5) {
            if hardware.connected.contains(device), let battery = hardware.battery[device] {
                Image(systemName: battery.charging ? "battery.100percent.bolt" : battery.percent <= 20 ? "battery.25percent" : "battery.75percent")
                Text("\(battery.percent)%\(battery.charging ? " · 充电中" : "")")
            } else { Image(systemName: "battery.0percent"); Text(hardware.connected.contains(device) ? "电量未知" : "未连接") }
        }.font(.caption.monospacedDigit()).foregroundStyle(hardware.battery[device].map { $0.percent <= 20 ? Color.orange : Color.green } ?? Color.secondary)
    }
    private var remoteIllustration: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            if let url = Bundle.main.url(forResource: remote == .mxMaster3s ? "mx-master-3s" : remote == .chromecast ? "chromecast-voice-remote" : "x6-remote", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 105, height: 285)
                    .accessibilityLabel(remote.title)
            }
            batteryLabel(remote)
            Text("\(RemoteProfiles.buttons(for: remote).filter { $0.remappable }.count) 个可映射按键").font(.caption).foregroundStyle(.secondary)
            if remote == .x6 { Text("鼠标模式由设备内部处理").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Spacer(minLength: 8)
        }.frame(width: 128)
    }
}

private struct RemoteButtonEditor: View {
    @ObservedObject var store: CodexStore
    let remote: SupportedRemoteID
    let button: RemoteButtonDefinition
    @ObservedObject private var hardware = RemoteMappingStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RemoteButtonMapping
    @State private var releaseSelected = false
    @State private var itemID = UUID()

    init(store: CodexStore, remote: SupportedRemoteID, button: RemoteButtonDefinition) {
        self.store = store; self.remote = remote; self.button = button
        _draft = State(initialValue: RemoteMappingStore.shared.mapping(remote, button.id) ?? RemoteButtonMapping(action: .unconfigured))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(remote.title) · \(button.title)", systemImage: button.symbol).font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { hardware.setMapping(draft, remote: remote, button: button.id); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Picker("触发时机", selection: $releaseSelected) {
                Text("按下时").tag(false); Text("松开时").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal)
            if !releaseSelected, case .keyboardShortcut = draft.action {
                Toggle("按住目标键，松开遥控器时释放", isOn: $draft.holdShortcut).padding(.horizontal).padding(.top, 8)
            }
            RadialMenuItemEditor(
                item: RadialMenuItem(id: itemID, title: button.title, systemImage: button.symbol, action: releaseSelected ? draft.releaseAction : draft.action),
                shortcutRegistrationFailed: false,
                onShortcutRecordingChanged: { _ in },
                canMoveUp: false, canMoveDown: false,
                onChange: { item in
                    if releaseSelected { draft.releaseAction = item.action } else { draft.action = item.action }
                }, onMove: { _ in }, onDelete: {}, hardwareMode: true
            ).id(releaseSelected)
            HStack {
                Button("恢复此键默认功能") { hardware.setMapping(nil, remote: remote, button: button.id); dismiss() }
                Spacer()
                Text("“未设置”表示不执行操作").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.frame(width: 610, height: 540)
        .onAppear {
            hardware.releaseAll(for: remote); hardware.editing = true
            store.cancelShortcutRecording(); store.setHardwareEditing(true)
        }
        .onDisappear { hardware.editing = false; store.setHardwareEditing(false) }
    }
}
