import CoreAudio
import SwiftUI

struct AudioQuickPanel: View {
    @ObservedObject var audio: AudioSettingsStore
    @ObservedObject private var hardware = RemoteMappingStore.shared
    @State private var page = 0
    private let pageSize = 2

    private struct Source: Identifiable {
        let id: String
        let title: String
        let detail: String
        let deviceID: AudioDeviceID?
    }
    private var sources: [Source] {
        var values = audio.inputs.sorted {
            if $0.isLoopback != $1.isLoopback { return !$0.isLoopback }
            if ($0.transport == kAudioDeviceTransportTypeBuiltIn) != ($1.transport == kAudioDeviceTransportTypeBuiltIn) { return $0.transport == kAudioDeviceTransportTypeBuiltIn }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.map { Source(id: $0.uid, title: $0.name, detail: $0.kind, deviceID: $0.id) }
        for remote in SupportedRemoteID.allCases where remote != .mxMaster3s && hardware.connected.contains(remote) {
            values.append(Source(id: AudioMixConfiguration.remoteUID(remote), title: remote.title, detail: "遥控器麦克风", deviceID: nil))
        }
        return values.filter { !audio.hiddenCardUIDs.contains($0.id) }
    }
    private var pageCount: Int { max(1, (sources.count + pageSize - 1) / pageSize) }
    private var visibleSources: [Source] { Array(sources.dropFirst(min(page, pageCount - 1) * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("音频控制台", systemImage: "waveform").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(audio.isRunning ? Color.green : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    Text(audio.isRunning ? "混音中" : audio.isStarting ? "正在启动" : "未启动").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if pageCount > 1 {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0).help("上一组输入")
                    Text("\(min(page, pageCount - 1) + 1) / \(pageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button { page = min(pageCount - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pageCount - 1).help("下一组输入")
                }
                Button(audio.isRunning || audio.isStarting ? "停止混音" : "启动混音") {
                    if audio.isRunning || audio.isStarting { audio.stopMix() } else { audio.requestStartMix() }
                }.buttonStyle(.borderedProminent).controlSize(.small)
            }.buttonStyle(.borderless)
            HStack(alignment: .top, spacing: 12) {
                if visibleSources.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mic.slash").font(.title2).foregroundStyle(.secondary)
                        Text("没有显示的输入卡片").font(.callout)
                        Text("可在下方设备列表取消“隐藏卡片”").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 210).background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(visibleSources) { source in inputCard(source).frame(maxWidth: .infinity) }
                outputCard.frame(width: 230)
            }
            if let message = audio.message {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .onChange(of: sources.map(\.id)) { _, _ in page = min(page, pageCount - 1) }
    }
    private var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    private func inputCard(_ source: Source) -> some View {
        let channel = audio.configuration.inputs[source.id]
        let level = audio.inputLevels[source.id] ?? 0
        let otherSolo = audio.configuration.inputs.values.contains { $0.solo } && channel?.solo != true
        let mixStatus = channel == nil ? "未参与混音" : channel?.muted == true ? "已静音" : otherSolo ? "其他通道独奏" : audio.isRunning ? (level > 0.0001 ? "正在收音" : "等待声音") : "等待启动"
        let remote = SupportedRemoteID.allCases.first { AudioMixConfiguration.remoteUID($0) == source.id }
        let status = remote.flatMap { hardware.status[$0] } ?? mixStatus
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: source.deviceID == nil ? "appletvremote.gen4" : "mic.fill")
                    .foregroundStyle(Color.accentColor).frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).help(source.title)
                    Text(source.detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(height: 42, alignment: .top)
            HStack {
                Text(status).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(AudioMeterScale.label(level)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            meter(level, color: .green, active: audio.isRunning || audio.isMonitoringInput)
            HStack(spacing: 7) {
                Button {
                    guard var value = channel else { return }; value.muted.toggle(); audio.update(value, uid: source.id, input: true)
                } label: { Label("静音", systemImage: channel?.muted == true ? "mic.slash.fill" : "mic.slash").frame(maxWidth: .infinity) }
                    .tint(channel?.muted == true ? .orange : .secondary)
                Button {
                    guard var value = channel else { return }; value.solo.toggle(); audio.update(value, uid: source.id, input: true)
                } label: { Text("独奏").frame(maxWidth: .infinity) }.tint(channel?.solo == true ? .green : .secondary)
            }.buttonStyle(.bordered).controlSize(.small).disabled(channel == nil)
            Divider()
            HStack(spacing: 4) {
                Toggle("参与混音", isOn: Binding(get: { audio.configuration.inputs[source.id] != nil }, set: { audio.quickSelect(source.id, input: true, enabled: $0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
                Spacer(minLength: 0)
                if let deviceID = source.deviceID {
                    Button(audio.defaultInput == deviceID ? "系统输入 ✓" : "设为输入") { audio.setDefault(deviceID, input: true) }
                        .buttonStyle(.borderless).font(.caption2)
                }
            }
        }
        .padding(14).frame(height: 210)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(source.title)
    }
    private var outputCard: some View {
        let level = audio.outputLevels.values.max() ?? 0
        let selected = audio.outputDevices.filter { audio.configuration.outputs[$0.uid] != nil }
        let muted = !selected.isEmpty && selected.allSatisfy { audio.configuration.outputs[$0.uid]?.muted == true }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path").foregroundStyle(.orange).frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("混合输出").font(.system(size: 13, weight: .semibold))
                    Text("\(audio.availableConfiguration.inputs.count) 路输入 → \(selected.count) 路输出").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }.frame(height: 42, alignment: .top)
            HStack {
                Text(muted ? "已静音" : audio.isRunning ? (selected.contains(where: { $0.isVirtualMixDestination }) || audio.isLocalMonitoring ? "正在输出" : "监听已关闭") : "等待启动").font(.caption2).foregroundStyle(.secondary)
                Spacer(); Text(AudioMeterScale.label(level)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            meter(level, color: .orange, active: audio.isRunning)
            Menu {
                ForEach(audio.outputDevices) { device in
                    Toggle(device.name, isOn: Binding(get: { audio.configuration.outputs[device.uid] != nil }, set: { audio.quickSelect(device.uid, input: false, enabled: $0) }))
                }
            } label: {
                Text(selected.isEmpty ? "选择输出设备" : selected.map(\.name).joined(separator: "、"))
                    .font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.controlSize(.small)
            Divider()
            Toggle("监听自己的声音", isOn: Binding(get: { audio.isLocalMonitoring }, set: { audio.setLocalMonitoring($0) }))
                .toggleStyle(.switch).controlSize(.mini).font(.caption)
            Button(muted ? "取消输出静音" : "输出静音") {
                for device in selected {
                    var value = audio.configuration.outputs[device.uid] ?? AudioMixChannel()
                    value.muted = !muted; audio.update(value, uid: device.uid, input: false)
                }
            }.buttonStyle(.borderless).font(.caption).disabled(selected.isEmpty)
        }
        .padding(14).frame(height: 210)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.22)))
    }
    private func meter(_ level: Float, color: Color, active: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(active && index < AudioMeterScale.segments(level) ? color : Color.primary.opacity(0.08)).frame(height: 15)
            }
        }.accessibilityLabel("电平 \(AudioMeterScale.label(level))")
    }
}
