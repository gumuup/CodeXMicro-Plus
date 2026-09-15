import AppKit

@MainActor
final class RemoteHardwareService {
    private let chromecast = ChromecastRemoteHIDBridge()
    private let x6 = X6HIDBridge()
    private let mx = MXMasterHIDBridge()
    private let batteries = HardwareBatteryMonitor()
    private var voices: [SupportedRemoteID: RemoteVoiceBridge] = [:]
    private var audio: [SupportedRemoteID: RemoteAudioOutput] = [:]
    private let mappings = RemoteMappingStore.shared
    private var started = false

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
                self.voices[.x6]?.toggleMicrophone()
            }
        }
        // X6 key-up does not close the microphone or invoke a release action.
        for remote in SupportedRemoteID.allCases where remote != .mxMaster3s {
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
                if AudioSettingsStore.shared.receiveRemote(samples, rate: rate, remote: remote) { output.stop(); return }
                do { try output.feed(samples, rate: rate) }
                catch { self.mappings.status[remote] = error.localizedDescription }
            }
            voices[remote] = voice; audio[remote] = output
        }
        chromecast.start(); x6.start(); mx.start(); batteries.start(); configure()
    }
    private func connection(_ remote: SupportedRemoteID, _ connected: Bool) {
        if connected { mappings.connected.insert(remote) }
        else { mappings.connected.remove(remote); mappings.releaseAll(for: remote); voices[remote]?.closeMicrophone(); audio[remote]?.stop() }
    }
    private func configure() {
        chromecast.setRemappingEnabled(mappings.isEnabled(.chromecast))
        x6.setRemappingEnabled(mappings.isEnabled(.x6))
        for remote in SupportedRemoteID.allCases where remote != .mxMaster3s {
            if !mappings.configuration.remoteMicrophone.contains(remote) { voices[remote]?.closeMicrophone(); audio[remote]?.stop() }
            if mappings.isEnabled(remote) { voices[remote]?.start() }
            else { voices[remote]?.stop(); audio[remote]?.stop() }
        }
    }
    func stop() {
        chromecast.stop(); x6.stop(); mx.stop(); batteries.stop()
        for voice in voices.values { voice.stop() }
        for output in audio.values { output.stop() }
        started = false
    }
}
