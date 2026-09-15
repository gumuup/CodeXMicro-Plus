import AppKit
import AVFoundation
import Combine
import CoreAudio

@MainActor
final class AudioSettingsStore: ObservableObject {
    static let shared = AudioSettingsStore()
    static let preferenceKey = "audio.mix.v1"
    @Published private(set) var devices: [SystemAudioDevice] = []
    @Published private(set) var defaultInput: AudioDeviceID = 0
    @Published private(set) var defaultOutput: AudioDeviceID = 0
    @Published private(set) var effectsOutput: AudioDeviceID = 0
    @Published private(set) var configuration: AudioMixConfiguration
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    private var activeMix: AudioMixConfiguration?
    var availableConfiguration: AudioMixConfiguration {
        let remoteUIDs = SupportedRemoteID.allCases.filter {
            $0 != .mxMaster3s && RemoteMappingStore.shared.connected.contains($0)
        }.map(AudioMixConfiguration.remoteUID)
        return configuration.availableSubset(inputs: Set(inputs.map(\.uid)).union(remoteUIDs),
                                             outputs: Set(outputDevices.map(\.uid)))
    }
    @Published private(set) var isLocalMonitoring = false
    func setLocalMonitoring(_ enabled: Bool) {
        isLocalMonitoring = enabled
        for (uid, output) in outputs {
            let virtual = outputDevices.first(where: { $0.uid == uid })?.isVirtualMixDestination == true
            output.state.setPlaybackEnabled(virtual || enabled)
        }
    }
    @Published private(set) var inputLevels: [String: Float] = [:]
    @Published private(set) var outputLevels: [String: Float] = [:]
    @Published var message: String?
    @Published var startFailure: String?
    @Published private(set) var hiddenCardUIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "audio.hiddenCards.v1") ?? [])
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var meterTimer: Timer?
    private var captures: [AudioDeviceCapture] = []
    private var outputs: [String: AudioMixOutput] = [:]
    private var meters = AudioInputLevels()
    private var remoteResamplers: [String: AudioStreamingResampler] = [:]
    @Published private(set) var isMonitoringInput = false
    private var previewCapture: AudioDeviceCapture?
    private var previewGeneration = 0
    private var startGeneration = 0
    private var started = false

    private init() {
        configuration = UserDefaults.standard.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode(AudioMixConfiguration.self, from: $0) } ?? AudioMixConfiguration()
    }
    var inputs: [SystemAudioDevice] { devices.filter { $0.inputChannels > 0 } }
    var outputDevices: [SystemAudioDevice] { devices.filter { $0.outputChannels > 0 } }
    func start() {
        guard !started else { return }; started = true
        refresh()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning || self.isMonitoringInput else { return }
                if self.isRunning && self.outputs.values.contains(where: { !$0.isRunning }) {
                    do { for output in self.outputs.values where !output.isRunning { try output.recoverAfterDeviceChange() } }
                    catch { self.stopMix(); self.message = "音频输出无法恢复：\(error.localizedDescription)"; return }
                }
                if self.isRunning && SupportedRemoteID.allCases.contains(where: {
                    self.activeMix?.inputs[AudioMixConfiguration.remoteUID($0)] != nil && !RemoteMappingStore.shared.connected.contains($0)
                }) {
                    self.stopMix(); self.message = "参与混音的遥控器已断开，混音已停止。"; return
                }
                self.inputLevels = self.meters.snapshot()
                self.outputLevels = self.outputs.mapValues { $0.state.level() }
            }
        }
    }
    func refresh() {
        let previous = devices
        let previousInput = defaultInput
        devices = SystemAudioDevices.devices()
        defaultInput = SystemAudioDevices.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        defaultOutput = SystemAudioDevices.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        effectsOutput = SystemAudioDevices.defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
        if previousInput != defaultInput { stopInputMonitor(); setLocalMonitoring(false) }
        if isRunning {
            let used = Set(activeMix?.inputs.keys.map { $0 } ?? []).union(activeMix?.outputs.keys.map { $0 } ?? [])
            let oldDevices = previous.filter { used.contains($0.uid) }
            if oldDevices.contains(where: { old in !devices.contains(where: { $0.uid == old.uid && $0.id == old.id && $0.inputChannels == old.inputChannels && $0.outputChannels == old.outputChannels }) }) {
                stopMix(); message = "使用中的设备已断开或音频格式改变，混音已停止。重新连接后可手动启动。"
            }
        }
        if previous.map(\.id) != devices.map(\.id) || listeners.isEmpty { installListeners() }
    }
    private func installListeners() {
        for (id, var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
        listeners.removeAll()
        let systemProperties: [AudioObjectPropertySelector] = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
        for selector in systemProperties { observe(SystemAudioDevices.system, address: SystemAudioDevices.address(selector)) }
        for device in devices {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute, kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyNominalSampleRate] {
                observe(device.id, address: AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeWildcard, mElement: kAudioObjectPropertyElementWildcard))
            }
        }
    }
    private func observe(_ id: AudioObjectID, address: AudioObjectPropertyAddress) {
        var property = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        if AudioObjectAddPropertyListenerBlock(id, &property, .main, block) == noErr { listeners.append((id, address, block)) }
    }
    func setDefault(_ id: AudioDeviceID, input: Bool) {
        do {
            try SystemAudioDevices.setDefault(id, selector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
            message = nil; refresh()
        } catch { message = error.localizedDescription }
    }
    func setEffectsOutput(_ id: AudioDeviceID) {
        do { try SystemAudioDevices.setDefault(id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice); refresh(); message = nil }
        catch { message = error.localizedDescription }
    }
    func setVolume(_ value: Float, device: SystemAudioDevice, input: Bool) {
        do { try SystemAudioDevices.setVolume(value, device: device, input: input); objectWillChange.send() }
        catch { message = error.localizedDescription }
    }
    func setMuted(_ value: Bool, device: SystemAudioDevice, input: Bool) {
        do { try SystemAudioDevices.setMuted(value, device: device, input: input); objectWillChange.send() }
        catch { message = error.localizedDescription }
    }
    func prepareVoiceMix() {
        stopMix(); refresh()
        var inputs: [String: AudioMixChannel] = [:]
        if let builtin = self.inputs.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) { inputs[builtin.uid] = AudioMixChannel() }
        for remote in SupportedRemoteID.allCases where remote != .mxMaster3s && RemoteMappingStore.shared.connected.contains(remote) {
            inputs[AudioMixConfiguration.remoteUID(remote)] = AudioMixChannel()
        }
        let loopback = outputDevices.first { $0.isLoopback && $0.inputChannels > 0 && !inputs.keys.contains($0.uid) }
        configuration = AudioMixConfiguration(inputs: inputs, outputs: loopback.map { [$0.uid: AudioMixChannel()] } ?? [:])
        save()
        message = loopback == nil ? "已选择内置和已连接遥控器，请再选择混音输出设备。" : "已准备内置麦克风与遥控器混音。请确认硬件页已启用遥控器麦克风，再启动混音。"
    }

    func setCardHidden(_ hidden: Bool, uid: String) {
        if hidden { hiddenCardUIDs.insert(uid) } else { hiddenCardUIDs.remove(uid) }
        UserDefaults.standard.set(hiddenCardUIDs.sorted(), forKey: "audio.hiddenCards.v1")
    }

    func quickSelect(_ uid: String, input: Bool, enabled: Bool) {
        select(uid, input: input, enabled: enabled)
    }

    func select(_ uid: String, input: Bool, enabled: Bool) {
        // Every edit invalidates an in-flight start, even before its Task runs.
        stopMix()
        if input { configuration.inputs[uid] = enabled ? (configuration.inputs[uid] ?? AudioMixChannel()) : nil }
        else { configuration.outputs[uid] = enabled ? (configuration.outputs[uid] ?? AudioMixChannel()) : nil }
        startFailure = nil
        message = configuration.outputs.isEmpty ? "请先在右侧“混合输出”选择输出设备，再启动混音。"
            : configuration.inputs.isEmpty ? "请至少开启一个设备的“参与混音”。"
            : "混音设备已保存，点击“启动混音”开始收音。"
        save()
    }
    func requestStartMix() {
        let generation = startGeneration
        startFailure = nil
        Task {
            guard generation == startGeneration else { return }
            await startMix()
            if !isRunning, !isStarting, let message { startFailure = message }
        }
    }
    func update(_ channel: AudioMixChannel, uid: String, input: Bool) {
        var value = channel; value.gain = min(2, max(0, value.gain.isFinite ? value.gain : 1))
        if input { configuration.inputs[uid] = value } else { configuration.outputs[uid] = value }
        for (uid, output) in outputs {
            let activeInputs = configuration.inputs.filter { activeMix?.inputs[$0.key] != nil }
            output.state.configure(inputs: activeInputs, output: configuration.outputs[uid] ?? AudioMixChannel())
        }
        save()
    }
    private func save() { if let data = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(data, forKey: Self.preferenceKey) } }
    func toggleInputMonitor() async {
        if isMonitoringInput { stopInputMonitor(); return }
        guard !isRunning, !isStarting, let device = inputs.first(where: { $0.id == defaultInput }) else { return }
        previewGeneration += 1
        let generation = previewGeneration
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        if permission == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) }
        else { granted = permission == .authorized }
        guard previewGeneration == generation, !isRunning, !isStarting else { return }
        guard granted else { message = "请在系统设置的麦克风权限中允许 CodeXMicro++。"; return }
        meters = AudioInputLevels()
        let capture = AudioDeviceCapture(uid: device.uid, destinations: [], levels: meters) { [weak self] message in
            Task { @MainActor in
                guard let self, self.previewGeneration == generation else { return }
                self.stopInputMonitor(); self.message = message
            }
        }
        previewCapture = capture; isMonitoringInput = true; message = nil; capture.start()
    }
    func stopInputMonitor() {
        previewGeneration += 1; previewCapture?.stop(); previewCapture = nil
        isMonitoringInput = false
        if !isRunning { inputLevels = [:] }
    }

    func startMix() async {
        guard !isRunning, !isStarting else { return }
        refresh(); message = nil
        let remotes = RemoteMappingStore.shared
        let remoteUIDs = Set(SupportedRemoteID.allCases.filter { $0 != .mxMaster3s && remotes.connected.contains($0) }.map(AudioMixConfiguration.remoteUID))
        let mix = availableConfiguration
        if let error = mix.validationError(availableInputs: Set(inputs.map(\.uid)).union(remoteUIDs), availableOutputs: Set(outputDevices.map(\.uid)), feedbackSensitiveUIDs: Set(devices.filter(\.isLoopback).map(\.uid))) { message = error; return }
        let skipped = configuration.inputs.count + configuration.outputs.count - mix.inputs.count - mix.outputs.count
        for remote in SupportedRemoteID.allCases where mix.inputs[AudioMixConfiguration.remoteUID(remote)] != nil {
            guard remotes.isEnabled(remote), remotes.configuration.remoteMicrophone.contains(remote) else { message = "请先在“硬件”中为 \(remote.title) 启用映射和遥控器麦克风。"; return }
        }
        stopInputMonitor()
        isStarting = true; startGeneration += 1
        let generation = startGeneration
        if mix.inputs.keys.contains(where: { !$0.hasPrefix("remote:") }) {
            let permission = AVCaptureDevice.authorizationStatus(for: .audio)
            let granted: Bool
            if permission == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) }
            else { granted = permission == .authorized }
            guard generation == startGeneration else { return }
            guard granted else { isStarting = false; message = "需要麦克风权限才能混音。请在系统设置 → 隐私与安全性 → 麦克风中允许 CodeXMicro++。"; return }
        }
        do {
            meters = AudioInputLevels()
            activeMix = mix
            for (uid, channel) in mix.outputs {
                guard let device = outputDevices.first(where: { $0.uid == uid }) else { throw AudioSettingsError.message("输出设备已断开。") }
                outputs[uid] = try AudioMixOutput(device: device, inputs: mix.inputs, output: channel,
                                                 playbackEnabled: device.isVirtualMixDestination || isLocalMonitoring)
            }
            let states = outputs.values.map(\.state)
            for uid in mix.inputs.keys where !uid.hasPrefix("remote:") {
                let capture = AudioDeviceCapture(uid: uid, destinations: states, levels: meters) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.startGeneration == generation else { return }
                        self.stopMix(); self.message = message
                    }
                }
                captures.append(capture); capture.start()
            }
            isStarting = false; isRunning = true
            if skipped > 0 { message = "混音已启动，本次跳过 \(skipped) 个已断开的输入／输出；原配置已保留。" }
        } catch { stopMix(); message = error.localizedDescription }
    }
    func stopMix() {
        startGeneration += 1
        isStarting = false; isRunning = false
        activeMix = nil
        setLocalMonitoring(false)
        for capture in captures { capture.stop() }; captures.removeAll()
        for output in outputs.values { output.stop() }; outputs.removeAll()
        inputLevels = [:]; outputLevels = [:]; remoteResamplers = [:]
    }
    /// Running mixer owns remote routing, preventing the legacy loopback output
    /// from also playing a second copy outside mute/solo controls.
    func receiveRemote(_ samples: [Int16], rate: Int, remote: SupportedRemoteID) -> Bool {
        guard isRunning else { return false }
        let uid = AudioMixConfiguration.remoteUID(remote)
        guard activeMix?.inputs[uid] != nil else { return true }
        let floats = samples.map { max(-1, min(1, Float($0) / 32768 * 10)) }
        meters.record(floats, uid: uid)
        var resampler = remoteResamplers[uid] ?? AudioStreamingResampler()
        let normalized = resampler.convert(floats, from: Double(rate)); remoteResamplers[uid] = resampler
        for output in outputs.values { output.state.push(normalized, source: uid) }
        return true
    }
    func openSystemSound() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
