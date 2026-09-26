import AppKit
import SwiftUI

struct HardwareSettingsView: View {
    @ObservedObject var store: CodexStore
    @ObservedObject private var hardware = RemoteMappingStore.shared
    @ObservedObject private var audio = AudioSettingsStore.shared
    @ObservedObject private var djiBluetooth = DJIBluetoothMonitor.shared
    @State private var remote: SupportedRemoteID = .chromecast
    @State private var selectedButton: RemoteButtonDefinition?
    @State private var audioDevice = RemoteAudioOutput.loopbackDevice()?.1
    @State private var confirmReset = false
    @State private var showingNUT65 = false
    @AppStorage("hardware.deviceOrder") private var savedDeviceOrder = "mxMaster3s,djiMicMini2,nut65,chromecast,x6"
    @State private var draggedDevice: String?
    @State private var dragOffset: CGFloat = 0
    @State private var dragStartCenter: CGFloat = 0
    @State private var deviceFrames: [String: CGRect] = [:]
    @StateObject private var nut65 = NUT65Store()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            deviceList
            if showingNUT65 {
                NUT65SettingsView(keyboard: nut65)
            } else {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    remoteIllustration
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(remote.title).font(.headline)
                                Text(remote == .djiMicMini2 ? "仅连接键单击可自定义，其余为原生功能" : "点击按键自定义操作").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(remote == .djiMicMini2 && !hardware.connected.contains(remote) ? "映射待连接" : "启用映射", isOn: Binding(get: { hardware.isEnabled(remote) }, set: { hardware.setEnabled($0, for: remote) }))
                                .toggleStyle(.switch).controlSize(.small).fixedSize()
                        }
                        HStack {
                            Text(remote == .djiMicMini2 ? (hardware.inputStatus[remote] ?? "尚未收到 DJI 按键事件") : hardware.lastInput).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button(hardware.learning == remote ? "取消监听" : "监听设备") {
                                if hardware.learning == remote { hardware.cancelLearning() } else { hardware.learn(remote) }
                            }.controlSize(.small).disabled(!hardware.isEnabled(remote) || (remote == .djiMicMini2 && !hardware.connected.contains(remote)))
                        }
                        if remote == .djiMicMini2 && !hardware.connected.contains(remote) {
                            Label("配置已保存，尚未生效：当前未启用接收器模式。蓝牙直连暂不支持按键映射。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("请先将接收器用 USB 接口连接 Mac（麦克风孔不支持）")
                                Text("1. **麦克风和接收器都开机**，放在彼此附近。")
                                Text("2. 长按**麦克风上的连接键 2 秒**，直到指示灯蓝绿交替闪烁。")
                                Text("3. 长按**接收器上的连接键 2 秒**，直到接收器的发射器状态灯快速闪绿。")
                                Text("4. 等待双方状态灯变为**绿灯常亮**，表示配对成功。")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        if let status = hardware.inputStatus[remote] { Text(status).font(.caption).foregroundStyle(.secondary) }
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(RemoteProfiles.buttons(for: remote)) { button in
                                    mappingRow(button)
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
                if remote == .djiMicMini2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("连接键单击：需通过 USB 接收器上报按键事件，支持自定义 Mac 操作。")
                        Text("连接键双击、长按及电源键双击、长按仅显示原生功能，不支持自定义，由麦克风固件执行。")
                        Text("原生功能由各支麦的固件执行；上方默认名称仅作备注，不代表 Mac 已支持。连接键单击录像限兼容 DJI 设备／快门 App。")
                        Text("映射触发的是 Mac 操作，不会控制两支麦。当前为型号共用预设，USB 事件尚未区分发射器；蓝牙音频连接不等于按键连接。")
                        Text(djiAudioSummary)
                        if let status = hardware.status[remote] { Text(status) }
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else if remote.hasRemoteAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("使用遥控器麦克风", isOn: Binding(get: { hardware.configuration.remoteMicrophone.contains(remote) }, set: { hardware.setRemoteMicrophone($0, for: remote) }))
                    if remote == .x6 {
                        Toggle("语音键联动微信输入法（⌃I）", isOn: Binding(
                            get: { hardware.x6WeChatVoiceEnabled }, set: { hardware.setX6WeChatVoice($0) }))
                    }
                    Text(voiceHelp)
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
            }
        }.padding(16)
        .onAppear { djiBluetooth.start() }
        .sheet(item: $selectedButton) { button in RemoteButtonEditor(store: store, remote: remote, button: button) }
        .confirmationDialog("恢复 \(remote.title) 当前预设的默认映射？", isPresented: $confirmReset) {
            Button("恢复默认映射") {
                for button in RemoteProfiles.buttons(for: remote) where button.remappable {
                    hardware.setMapping(nil, remote: remote, button: button.id)
                }
            }
        } message: { Text("将清除此型号当前预设的自定义按键配置，其他预设保留。") }
        .onChange(of: hardware.learnedButton) { _, id in
            if let id, !(remote == .x6 && id == "voice") { selectedButton = RemoteProfiles.buttons(for: remote).first { $0.id == id } }
        }
        .onDisappear { hardware.cancelLearning() }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支持的设备").font(.caption.bold()).foregroundStyle(.secondary)
            Text("拖动卡片调整顺序").font(.caption2).foregroundStyle(.secondary)
            ForEach(deviceOrder, id: \.self) { id in
                VStack(spacing: 0) {
                    if id == "nut65" { nut65Card }
                    else if let item = SupportedRemoteID(rawValue: id) { remoteCard(item) }
                }
                .contentShape(Rectangle())
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HardwareDeviceFrames.self,
                                           value: [id: proxy.frame(in: .named("hardware-device-list"))])
                })
                .offset(y: draggedDevice == id ? dragOffset : 0)
                .zIndex(draggedDevice == id ? 1 : 0)
                .shadow(color: .black.opacity(draggedDevice == id ? 0.12 : 0), radius: 6)
                .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("hardware-device-list"))
                    .onChanged { value in
                        if draggedDevice != id { dragStartCenter = deviceFrames[id]?.midY ?? value.startLocation.y }
                        draggedDevice = id
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let order = deviceOrder
                        if let from = order.firstIndex(of: id) {
                            let center = dragStartCenter + value.translation.height
                            let others = order.filter { $0 != id }
                            let to = others.filter { (deviceFrames[$0]?.midY ?? .infinity) < center }.count
                            var updated = order
                            updated.remove(at: from)
                            updated.insert(id, at: to)
                            withAnimation(.easeInOut(duration: 0.18)) {
                                savedDeviceOrder = updated.joined(separator: ",")
                                draggedDevice = nil; dragOffset = 0
                            }
                        } else { draggedDevice = nil; dragOffset = 0 }
                    })
            }
            Spacer()
            Label("设置跟随型号保存", systemImage: "checkmark.shield.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }.coordinateSpace(name: "hardware-device-list")
            .onPreferenceChange(HardwareDeviceFrames.self) { deviceFrames = $0 }
            .padding(14).frame(width: 205).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
    }
    private var deviceOrder: [String] {
        let defaults = ["mxMaster3s", "djiMicMini2", "nut65", "chromecast", "x6"]
        var order: [String] = []
        for id in savedDeviceOrder.split(separator: ",").map(String.init) + defaults
            where defaults.contains(id) && !order.contains(id) {
            order.append(id)
        }
        return order
    }

    private var nut65Card: some View {
Button {
                hardware.cancelLearning(); showingNUT65 = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("NUT65 键盘", systemImage: "keyboard").font(.system(size: 12, weight: .semibold))
                    Text("USB 有线 · 板载改键").font(.caption2).foregroundStyle(.secondary)
                }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(showingNUT65 ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(showingNUT65 ? Color.accentColor.opacity(0.5) : .clear))
            }.buttonStyle(.plain)
    }

    private func remoteCard(_ item: SupportedRemoteID) -> some View {
Button {
                    hardware.cancelLearning(); showingNUT65 = false; remote = item
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Circle().fill(hardware.connected.contains(item) || (item == .djiMicMini2 && !djiBluetooth.devices.isEmpty && djiBluetooth.error == nil) ? .green : .gray).frame(width: 6, height: 6)
                            Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        }
                        HStack {
                            Text(item == .djiMicMini2 ? "蓝牙 / USB" : item.signature).font(.caption2.monospaced())
                            Spacer()
                            Text(item == .djiMicMini2 ? djiConnectionTitle : (hardware.connected.contains(item) ? "已连接" : "未连接")).font(.caption2)
                        }.foregroundStyle(.secondary)
                        if hardware.connected.contains(item) { batteryLabel(item) }
                        if item == .djiMicMini2 {
                            ForEach(djiBluetooth.devices) { device in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.caption2).fixedSize(horizontal: false, vertical: true)
                                    Label((djiBluetooth.error == nil ? "蓝牙已连接 · " : "上次连接 · ") + (device.batteryPercent.map { "\($0)%\(device.batteryIsCached ? "（上次）" : "")" } ?? "电量待更新"),
                                          systemImage: device.batteryPercent == nil ? "battery.0percent" : "battery.100percent")
                                        .font(.caption2).foregroundStyle(device.batteryPercent != nil && djiBluetooth.error == nil ? Color.green : Color.secondary)
                                }.help("\(device.id)；\(device.batteryReadAt.map { "电量读取于 " + $0.formatted(date: .omitted, time: .standard) } ?? "尚无有效电量")。临时缺失保留最近值最多 10 分钟；不代表实时电量。")
                            }
                            if let error = djiBluetooth.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                        }
                    }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                        .background(!showingNUT65 && remote == item ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(!showingNUT65 && remote == item ? Color.accentColor.opacity(0.5) : .clear))
                }.buttonStyle(.plain)
    }

    private var voiceHelp: String {
        remote == .x6
            ? (hardware.x6WeChatVoiceEnabled
                ? "按一下开麦并启动微信语音，松手持续收音；再按关闭麦克风。微信可按任意键结束。微信麦克风请选择 vRemoteDr 2ch。"
                : "按一下持续开麦，再按一下关闭；松开不关麦。开启微信联动后自动发送 Control+I。")
            : "语音键支持任意应用的快捷键或快捷指令，可分别配置按下和松开动作。权限统一在“通用 → 系统权限”管理。"
    }
    private var djiAudioSummary: String {
        let names = audio.inputs.filter { $0.name.localizedCaseInsensitiveContains("DJI Mic Mini 2") }.map(\.name)
        return names.isEmpty
            ? "音频：请在“音频”页选择 DJI 蓝牙麦或 USB 接收器 Wireless Mic Rx。"
            : "可用音频输入（\(names.count) 支）：\(names.joined(separator: "、"))。在“音频”页分别选择；不会自动同时收音。"
    }
    private var djiConnectionTitle: String {
        if djiBluetooth.error != nil { return "蓝牙状态待刷新" }
        if !djiBluetooth.devices.isEmpty { return "蓝牙已连接 · \(djiBluetooth.devices.count) 支" }
        if hardware.connected.contains(.djiMicMini2) { return "USB 已连接" }
        return djiBluetooth.refreshing ? "正在检测" : "未连接"
    }
    private func mappingRow(_ button: RemoteButtonDefinition) -> some View {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(button.title, systemImage: button.symbol).font(.callout)
                                            if remote == .djiMicMini2, button.id == "link.single" {
                                                Text("仅该键支持映射，且需连接接收器").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if button.remappable {
                                            Button { if !(remote == .x6 && button.voiceControlled) { selectedButton = button } } label: {
                                                HStack {
                                                    Text(hardware.targetTitle(for: button, remote: remote)).lineLimit(remote == .djiMicMini2 ? 2 : 1)
                                                    Spacer(minLength: 3)
                                                    Image(systemName: "chevron.right").font(.caption2)
                                                }.frame(width: 142)
                                            }.buttonStyle(.borderless).help("自定义：\(button.title)")
                                        } else {
                                            Text(remote == .djiMicMini2 ? RemoteProfiles.djiNativeTitle(for: button.id) : "设备内部功能")
                                                .font(.caption).foregroundStyle(.secondary)
                                                .frame(width: 142, alignment: .leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }.padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    }
    private func batteryLabel(_ device: SupportedRemoteID) -> some View {
        HStack(spacing: 5) {
            if hardware.connected.contains(device), let battery = hardware.battery[device] {
                Image(systemName: battery.charging ? "battery.100percent.bolt" : battery.percent <= 20 ? "battery.25percent" : "battery.75percent")
                Text("\(battery.percent)%\(battery.charging ? " · 充电中" : "")")
                    .help(hardware.batteryUpdatedAt[device].map { "最近读取：" + $0.formatted(date: .omitted, time: .standard) + "；设备休眠或重连时保留最近读数。" } ?? "最近一次成功读取的电量")
            } else { Image(systemName: "battery.0percent"); Text(hardware.connected.contains(device) ? "电量未知" : "未连接") }
        }.font(.caption.monospacedDigit()).foregroundStyle(hardware.battery[device].map { $0.percent <= 20 ? Color.orange : Color.green } ?? Color.secondary)
    }
    private var remoteIllustration: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            if remote == .djiMicMini2 {
                if let url = Bundle.main.url(forResource: "dji-mic-mini-2", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 128, height: 128)
                        .accessibilityLabel("DJI Mic Mini 2 产品图")
                }
                Text("DJI\nMic Mini 2").font(.headline).multilineTextAlignment(.center)
                Label("USB-C 接收器", systemImage: "cable.connector").font(.caption)
            } else if let url = Bundle.main.url(forResource: remote == .mxMaster3s ? "mx-master-3s" : remote == .chromecast ? "chromecast-voice-remote" : "x6-remote", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 105, height: 285)
                    .accessibilityLabel(remote.title)
            }
            if remote != .djiMicMini2 { batteryLabel(remote) }
            Text(remote == .djiMicMini2 ? "2 枚按键 · 1 项支持映射" : "\(RemoteProfiles.buttons(for: remote).filter { $0.remappable }.count) 个可映射按键").font(.caption).foregroundStyle(.secondary)
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
    @State private var nativeDefault: Bool
    @State private var releaseSelected = false
    @State private var itemID = UUID()

    init(store: CodexStore, remote: SupportedRemoteID, button: RemoteButtonDefinition) {
        self.store = store; self.remote = remote; self.button = button
        _draft = State(initialValue: RemoteMappingStore.shared.mapping(remote, button.id) ?? RemoteButtonMapping(action: .unconfigured))
        _nativeDefault = State(initialValue: RemoteMappingStore.shared.mapping(remote, button.id) == nil)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(remote.title) · \(button.title)", systemImage: button.symbol).font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { hardware.setMapping(nativeDefault ? nil : draft, remote: remote, button: button.id); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            if remote == .djiMicMini2 {
                Text(button.id.hasPrefix("power.") ? "此预设可以保存；电源键尚无已确认的 USB 事件，当前不会执行。" : "手势识别后执行一次。设备固件可能拦截双击／长按，需实机验证。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            } else {
            Picker("触发时机", selection: $releaseSelected) {
                Text("按下时").tag(false); Text("松开时").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal)
            if !releaseSelected, case .keyboardShortcut = draft.action {
                Toggle("按住目标键，松开遥控器时释放", isOn: $draft.holdShortcut).padding(.horizontal).padding(.top, 8)
            }
            }
            RadialMenuItemEditor(
                item: RadialMenuItem(id: itemID, title: button.title, systemImage: button.symbol, action: releaseSelected ? draft.releaseAction : draft.action),
                shortcutRegistrationFailed: false,
                onShortcutRecordingChanged: { _ in },
                canMoveUp: false, canMoveDown: false,
                onChange: { item in
                    if releaseSelected { draft.releaseAction = item.action } else { draft.action = item.action }
                }, onMove: { _ in }, onDelete: {}, hardwareMode: true, hardwareNativeDefault: $nativeDefault
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

private struct HardwareDeviceFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
