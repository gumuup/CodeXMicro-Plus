import AppKit

@MainActor
final class RemoteHardwareService {
    private let chromecast = ChromecastRemoteHIDBridge()
    private let x6 = X6HIDBridge()
    private let mx = MXMasterHIDBridge()
    private let dji = DJIMicMini2Adapter()
    private let batteries = HardwareBatteryMonitor()
    private var voices: [SupportedRemoteID: RemoteVoiceBridge] = [:]
    private var audio: [SupportedRemoteID: RemoteAudioOutput] = [:]
    private let mappings = RemoteMappingStore.shared
    private var started = false
    private var preparingX6: Task<Void, Never>?
    private var weChatSession = X6VoiceInputSession()

    private func toggleX6Microphone() {
        if let preparingX6 {
            preparingX6.cancel(); self.preparingX6 = nil
            weChatSession.end()
            return
        }
        guard let voice = voices[.x6] else { return }
        if voice.microphoneRequested {
            weChatSession.end(); voice.closeMicrophone()
            mappings.status[.x6] = "麦克风已关闭；微信语音可按任意键结束"
            return
        }
        guard mappings.x6WeChatVoiceEnabled else { voice.toggleMicrophone(); return }
        weChatSession.begin()
        preparingX6 = Task { [weak self] in
            guard let self else { return }
            let ready = await AudioSettingsStore.shared.prepareX6WeChatMix()
            guard !Task.isCancelled else { return }
            self.preparingX6 = nil
            guard ready, self.mappings.x6WeChatVoiceEnabled,
                  self.mappings.isEnabled(.x6), self.mappings.configuration.remoteMicrophone.contains(.x6),
                  !self.mappings.editing, self.mappings.learning == nil else {
                self.mappings.status[.x6] = AudioSettingsStore.shared.message ?? "语音启动已取消"
                return
            }
            voice.toggleMicrophone()
        }
    }

    private func startWeChatIfReady() {
        guard mappings.x6WeChatVoiceEnabled, mappings.isEnabled(.x6),
              mappings.configuration.remoteMicrophone.contains(.x6),
              !mappings.editing, mappings.learning == nil,
              voices[.x6]?.microphoneRequested == true,
              AudioSettingsStore.shared.hasX6WeChatRoute else { return }
        mappings.startWeChatVoice()
        mappings.status[.x6] = "X6 已开麦 · 已发送微信语音快捷键 ⌃I"
    }
    private func x6VoiceReleased() {
        if weChatSession.keyReleased() { startWeChatIfReady() }
    }

    func start(store: CodexStore) {
        guard !started else { return }; started = true
        mappings.onAction = { [weak store] action in
            store?.performHardwareAction(action)
        }
        mappings.onConfigurationChanged = { [weak self] in self?.configure() }
        chromecast.onConnectionChanged = { [weak self] connected in self?.connection(.chromecast, connected) }
        x6.onConnectionChanged = { [weak self] connected in self?.connection(.x6, connected) }
        chromecast.onError = { [weak self] in self?.mappings.status[.chromecast] = $0 }
        x6.onInputStatus = { [weak self] in self?.mappings.inputStatus[.x6] = $0 }
        x6.onError = { [weak self] in self?.mappings.status[.x6] = $0 }
        // X6 reports Search first, then 0xAA for a hold. Upstream consolidates
        // that transition; route one down/up pair to the configurable actions.
        x6.onPhysicalVoiceDown = { [weak self] in
            guard let self, self.mappings.isEnabled(.x6), !self.mappings.editing else { return }
            if self.mappings.learning == .x6 { self.mappings.voice(.x6, down: true); return }
            guard self.mappings.learning == nil else { return }
            if self.mappings.configuration.remoteMicrophone.contains(.x6) {
                self.toggleX6Microphone()
            }
        }
        // Physical release starts WeChat only after audio is ready; it never closes the mic.
        x6.onShortPress = { [weak self] in self?.x6VoiceReleased() }
        x6.onLongPressEnded = { [weak self] in self?.x6VoiceReleased() }
        for remote in SupportedRemoteID.allCases where remote.hasRemoteAudio {
            let voice = RemoteVoiceBridge(remote: remote)
            let output = RemoteAudioOutput()
            voice.onBattery = { [weak self] in self?.mappings.updateBattery($0, for: remote) }
            voice.onStatus = { [weak self] in self?.mappings.status[remote] = $0 }
            voice.onVoice = { [weak self] down in
                guard let self else { return }
                if remote == .chromecast { self.mappings.voice(remote, down: down) }
                if !down { self.audio[remote]?.stop() }
            }
            voice.onSamples = { [weak self] samples, rate in
                guard let self, self.mappings.isEnabled(remote), self.mappings.configuration.remoteMicrophone.contains(remote), !self.mappings.editing, self.mappings.learning == nil else { return }
                if AudioSettingsStore.shared.receiveRemote(samples, rate: rate, remote: remote) {
                    output.stop()
                    if remote == .x6, self.mappings.x6WeChatVoiceEnabled,
                       self.voices[.x6]?.microphoneRequested == true,
                       AudioSettingsStore.shared.hasX6WeChatRoute,
                       self.weChatSession.audioArrived(sampleCount: samples.count) {
                        self.startWeChatIfReady()
                    }
                    return
                }
                do { try output.feed(samples, rate: rate) }
                catch { self.mappings.status[remote] = error.localizedDescription }
            }
            voices[remote] = voice; audio[remote] = output
        }
        chromecast.start(); x6.start(); mx.start(); dji.start(); batteries.start(); configure()
    }
    private func connection(_ remote: SupportedRemoteID, _ connected: Bool) {
        if connected { mappings.connected.insert(remote) }
        else { mappings.connected.remove(remote); mappings.releaseAll(for: remote); voices[remote]?.closeMicrophone(); audio[remote]?.stop() }
    }
    private func configure() {
        preparingX6?.cancel(); preparingX6 = nil
        weChatSession.end()
        chromecast.setRemappingEnabled(mappings.isEnabled(.chromecast))
        x6.setRemappingEnabled(mappings.isEnabled(.x6))
        for remote in SupportedRemoteID.allCases where remote.hasRemoteAudio {
            if !mappings.configuration.remoteMicrophone.contains(remote) { voices[remote]?.closeMicrophone(); audio[remote]?.stop() }
            if mappings.isEnabled(remote) { voices[remote]?.start() }
            else { voices[remote]?.stop(); audio[remote]?.stop() }
        }
    }
    func stop() {
        preparingX6?.cancel(); preparingX6 = nil; weChatSession.end()
        chromecast.stop(); x6.stop(); mx.stop(); dji.stop(); batteries.stop()
        for voice in voices.values { voice.stop() }
        for output in audio.values { output.stop() }
        started = false
    }
}
