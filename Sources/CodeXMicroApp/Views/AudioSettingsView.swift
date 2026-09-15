import SwiftUI
import CoreAudio

struct AudioSettingsView: View {
    @ObservedObject var store: CodexStore
    @ObservedObject private var audio = AudioSettingsStore.shared
    @ObservedObject private var hardware = RemoteMappingStore.shared

    var body: some View {
        VStack(spacing: 0) {
            AudioQuickPanel(audio: audio).padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
        Form {
            Section("系统声音") {
                HStack {
                    Text("与 macOS 声音设置同步").font(.headline)
                    Spacer()
                    Button("打开系统声音设置") { audio.openSystemSound() }
                    Button("刷新") { audio.refresh() }
                }
                Picker("音频输入", selection: Binding(get: { audio.defaultInput }, set: { audio.setDefault($0, input: true) })) {
                    if !audio.inputs.contains(where: { $0.id == audio.defaultInput }) { Text("无输入设备").tag(audio.defaultInput) }
                    ForEach(audio.inputs) { device in Text("\(device.name) · \(device.kind)").tag(device.id) }
                }
                if let device = audio.inputs.first(where: { $0.id == audio.defaultInput }) {
                    systemControls(device, input: true)
                    HStack {
                        Text("输入电平").frame(width: 70, alignment: .leading)
                        ProgressView(value: Double(min(1, max(0, audio.inputLevels[device.uid] ?? 0))))
                        Button(audio.isMonitoringInput ? "停止测试" : "测试麦克风") { Task { await audio.toggleInputMonitor() } }
                            .disabled(audio.isRunning || audio.isStarting)
                    }
                }
                Picker("音频输出", selection: Binding(get: { audio.defaultOutput }, set: { audio.setDefault($0, input: false) })) {
                    if !audio.outputDevices.contains(where: { $0.id == audio.defaultOutput }) { Text("无输出设备").tag(audio.defaultOutput) }
                    ForEach(audio.outputDevices) { device in Text("\(device.name) · \(device.kind)").tag(device.id) }
                }
                if let device = audio.outputDevices.first(where: { $0.id == audio.defaultOutput }) { systemControls(device, input: false) }
                Text("自动识别内置麦克风、DJI 等 USB 麦克风、蓝牙和虚拟音频设备。在这里切换会同步更改 macOS 默认设备；应用内单独指定的音频设备仍由该应用控制。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("声音效果") {
                Toggle("机械按键声音", isOn: $store.keySoundEnabled)
                Picker("播放声音效果的设备", selection: Binding(get: { audio.effectsOutput }, set: { audio.setEffectsOutput($0) })) {
                    if !audio.outputDevices.contains(where: { $0.id == audio.effectsOutput }) { Text("无输出设备").tag(audio.effectsOutput) }
                    ForEach(audio.outputDevices) { Text($0.name).tag($0.id) }
                }
                Text("机械按键声音与“通用”中的开关保持一致；声音效果设备与 macOS 同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = audio.message {
                Section { Label(message, systemImage: "info.circle").foregroundStyle(.orange).font(.callout) }
            }
            Section("多设备混合") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(audio.isRunning ? "正在混音" : audio.isStarting ? "正在启动…" : "混音已停止", systemImage: audio.isRunning ? "waveform" : "waveform.slash")
                            .foregroundStyle(audio.isRunning ? .green : .secondary)
                        Text("\(audio.configuration.inputs.count) 路输入 → \(audio.configuration.outputs.count) 路输出")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if audio.isRunning || audio.isStarting { Button("停止混音") { audio.stopMix() } }
                    else { Button("启动混音") { Task { await audio.startMix() } }.buttonStyle(.borderedProminent) }
                }
                Toggle("监听自己的声音", isOn: Binding(get: { audio.isLocalMonitoring }, set: { audio.setLocalMonitoring($0) }))
                Text("默认不向耳机或扬声器播放麦克风。需要返听时开启“监听自己的声音”；虚拟音频输出仍可供语音软件使用。停止混音、切换系统输入或重启应用后，监听自动关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("参与混合的输入") {
                HStack {
                    Text("快速配置").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("内置麦克风 + 已连接遥控器") { audio.prepareVoiceMix() }
                        .disabled(audio.isRunning || audio.isStarting)
                }
                ForEach(audio.inputs) { device in
                    mixRow(uid: device.uid, title: device.name, detail: device.kind, input: true)
                }
                ForEach(SupportedRemoteID.allCases.filter { $0 != .mxMaster3s }) { remote in
                    let uid = AudioMixConfiguration.remoteUID(remote)
                    if hardware.connected.contains(remote) || audio.configuration.inputs[uid] != nil {
                        mixRow(uid: uid, title: "\(remote.title) 麦克风", detail: hardware.connected.contains(remote) ? "需在硬件页启用遥控器麦克风" : "未连接", input: true)
                    }
                }
                ForEach(missingInputs, id: \.self) { uid in missingRow(uid, input: true) }
                if audio.inputs.isEmpty { Text("未检测到系统音频输入设备").foregroundStyle(.secondary) }
            }
            Section("混合输出到") {
                ForEach(audio.outputDevices) { device in mixRow(uid: device.uid, title: device.name, detail: device.kind, input: false) }
                ForEach(missingOutputs, id: \.self) { uid in missingRow(uid, input: false) }
                Text("耳机或扬声器需开启“监听自己的声音”才播放混音。供语音软件使用时，请输出到 vRemoteDr / BlackHole，并在语音软件中选择同名输入设备。扬声器靠近麦克风可能产生回声。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("这里混合的是所选麦克风／输入设备。其他应用的播放声音，需先通过虚拟音频设备接入。多路输出的延迟取决于各设备，蓝牙和有线设备可能不同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { audio.start(); audio.refresh() }
        .onDisappear { audio.stopInputMonitor() }
        }
    }
    private var missingInputs: [String] {
        audio.configuration.inputs.keys.filter { uid in !uid.hasPrefix("remote:") && !audio.inputs.contains(where: { $0.uid == uid }) }.sorted()
    }
    private var missingOutputs: [String] {
        audio.configuration.outputs.keys.filter { uid in !audio.outputDevices.contains(where: { $0.uid == uid }) }.sorted()
    }
    @ViewBuilder private func systemControls(_ device: SystemAudioDevice, input: Bool) -> some View {
        if let volume = SystemAudioDevices.volume(device, input: input) {
            HStack {
                Text(input ? "输入音量" : "输出音量").frame(width: 70, alignment: .leading)
                Slider(value: Binding(get: { Double(volume) }, set: { audio.setVolume(Float($0), device: device, input: input) }), in: 0...1)
                    .disabled(SystemAudioDevices.controlElements(device, selector: kAudioDevicePropertyVolumeScalar, input: input, writable: true).isEmpty)
                Text("\(Int(volume * 100))%").monospacedDigit().frame(width: 40)
            }
        } else { Text("该设备的音量由硬件或其驱动控制").font(.caption).foregroundStyle(.secondary) }
        if let muted = SystemAudioDevices.muted(device, input: input), !SystemAudioDevices.controlElements(device, selector: kAudioDevicePropertyMute, input: input, writable: true).isEmpty {
            Toggle(input ? "输入静音" : "输出静音", isOn: Binding(get: { muted }, set: { audio.setMuted($0, device: device, input: input) }))
        }
    }
    private func missingRow(_ uid: String, input: Bool) -> some View {
        HStack {
            Label("已断开的设备：\(uid)", systemImage: "cable.connector.slash").font(.caption).lineLimit(1)
            Spacer()
            Button("移除") { audio.select(uid, input: input, enabled: false) }
        }
    }
    private func mixRow(uid: String, title: String, detail: String, input: Bool) -> some View {
        let channel = (input ? audio.configuration.inputs : audio.configuration.outputs)[uid]
        let level = (input ? audio.inputLevels : audio.outputLevels)[uid] ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(get: { channel != nil }, set: { audio.select(uid, input: input, enabled: $0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.checkbox)
                Spacer()
                if input {
                    Toggle("隐藏卡片", isOn: Binding(get: { audio.hiddenCardUIDs.contains(uid) }, set: { audio.setCardHidden($0, uid: uid) }))
                        .toggleStyle(.checkbox).font(.caption).help("仅隐藏上方卡片，不改变混音和系统输入")
                        .accessibilityLabel("隐藏卡片：\(title)")
                }
                if channel != nil {
                    ProgressView(value: Double(min(1, max(0, level)))).frame(width: 100)
                    Text(AudioMeterScale.label(level))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48)
                }
            }
            if let channel {
                HStack {
                    Text(input ? "增益" : "音量").font(.caption)
                    Slider(value: Binding(get: { Double(channel.gain) }, set: { value in
                        var updated = channel; updated.gain = Float(value); audio.update(updated, uid: uid, input: input)
                    }), in: 0...2)
                    Text("\(Int(channel.gain * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
                    Toggle("静音", isOn: Binding(get: { channel.muted }, set: { value in
                        var updated = channel; updated.muted = value; audio.update(updated, uid: uid, input: input)
                    })).toggleStyle(.button)
                    if input {
                        Toggle("独奏", isOn: Binding(get: { channel.solo }, set: { value in
                            var updated = channel; updated.solo = value; audio.update(updated, uid: uid, input: input)
                        })).toggleStyle(.button)
                    }
                }
            }
        }.padding(.vertical, 3)
    }
}
