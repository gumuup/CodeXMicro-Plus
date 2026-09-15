import AppKit
import Combine

struct RemoteButtonMapping: Codable, Equatable {
    var action: RadialMenuAction
    var releaseAction: RadialMenuAction = .unconfigured
    var holdShortcut = false
}

struct RemoteHardwareConfiguration: Codable {
    var enabled: Set<SupportedRemoteID> = []
    var remoteMicrophone: Set<SupportedRemoteID> = []
    var mappings: [String: RemoteButtonMapping] = [:]
    // Optional for backward-compatible decoding of existing 5.0 configurations.
    var presetBanks: [String: HardwarePresetBank]?
}

struct HardwarePresetBank: Codable {
    static let count = RadialMenuProfile.presetCombinationCount
    var selectedIndex = 0
    var combinations: [[String: RemoteButtonMapping]]
    init(seed: [String: RemoteButtonMapping]) {
        combinations = [seed] + Array(repeating: [:], count: Self.count - 1)
    }
    mutating func normalize() {
        combinations = Array(combinations.prefix(Self.count))
        while combinations.count < Self.count { combinations.append([:]) }
        selectedIndex = min(max(selectedIndex, 0), Self.count - 1)
    }
}

/// Main-run-loop HID callbacks and UI edits share this store. Output bindings are
/// snapshotted on key-down so editing/disconnecting cannot leave a key held.
@MainActor
final class RemoteMappingStore: ObservableObject {
    static let shared = RemoteMappingStore()
    static let preferenceKey = "hardware.remotes.v1"
    @Published private(set) var configuration: RemoteHardwareConfiguration
    @Published var inputStatus: [SupportedRemoteID: String] = [:]
    @Published var status: [SupportedRemoteID: String] = [:]
    @Published var connected: Set<SupportedRemoteID> = []
    @Published var lastInput: String = "尚未收到遥控器按键"
    @Published var learning: SupportedRemoteID?
    @Published var learnedButton: String?
    @Published var battery: [SupportedRemoteID: PeripheralBattery] = [:]
    @Published private(set) var batteryUpdatedAt: [SupportedRemoteID: Date] = [:]
    func updateBattery(_ reading: PeripheralBattery?, for remote: SupportedRemoteID) {
        // Missing/invalid samples are not a new battery reading. Voice and HID
        // channels can reconnect independently without invalidating the last one.
        guard let reading else { return }
        battery[remote] = reading
        batteryUpdatedAt[remote] = Date()
    }
    @Published var editing = false
    var onConfigurationChanged: (() -> Void)?
    var onAction: ((RadialMenuAction) -> Void)?
    private var held: [String: KeyboardShortcutBinding] = [:]
    private var pressed: Set<String> = []
    private var releases: [String: RadialMenuAction] = [:]
    private var defaultsHeld: [String: RemoteMappingTarget] = [:]
    private var learningTimeout: Task<Void, Never>?

    private let defaults: UserDefaults
    var keyEventSink: ((KeyboardShortcutBinding, Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = defaults.data(forKey: Self.preferenceKey)
            .flatMap { try? JSONDecoder().decode(RemoteHardwareConfiguration.self, from: $0) }
            ?? RemoteHardwareConfiguration()
    }
    func key(_ remote: SupportedRemoteID, _ button: String) -> String { remote.rawValue + "." + button }
    func isEnabled(_ remote: SupportedRemoteID) -> Bool { configuration.enabled.contains(remote) }
    func setEnabled(_ enabled: Bool, for remote: SupportedRemoteID) {
        releaseAll(for: remote)
        if enabled { configuration.enabled.insert(remote) } else { configuration.enabled.remove(remote) }
        save(); onConfigurationChanged?()
    }
    func setRemoteMicrophone(_ enabled: Bool, for remote: SupportedRemoteID) {
        if enabled { configuration.remoteMicrophone.insert(remote) } else { configuration.remoteMicrophone.remove(remote) }
        save(); onConfigurationChanged?()
    }
    func mapping(_ remote: SupportedRemoteID, _ button: String) -> RemoteButtonMapping? {
        configuration.mappings[key(remote, button)]
    }
    func setMapping(_ value: RemoteButtonMapping?, remote: SupportedRemoteID, button: String) {
        releaseAll(for: remote)
        configuration.mappings[key(remote, button)] = value
        saveActivePreset(remote)
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: Self.preferenceKey) }
    }
    func selectedPreset(for remote: SupportedRemoteID) -> Int {
        min(max(configuration.presetBanks?[remote.rawValue]?.selectedIndex ?? 0, 0), HardwarePresetBank.count - 1)
    }
    private func activeMappings(_ remote: SupportedRemoteID) -> [String: RemoteButtonMapping] {
        configuration.mappings.filter { $0.key.hasPrefix(remote.rawValue + ".") }
    }
    private func saveActivePreset(_ remote: SupportedRemoteID) {
        var banks = configuration.presetBanks ?? [:]
        var bank = banks[remote.rawValue] ?? HardwarePresetBank(seed: activeMappings(remote))
        bank.normalize()
        bank.combinations[bank.selectedIndex] = activeMappings(remote)
        banks[remote.rawValue] = bank
        configuration.presetBanks = banks
    }
    func selectPreset(at index: Int, for remote: SupportedRemoteID) {
        guard (0..<HardwarePresetBank.count).contains(index), index != selectedPreset(for: remote), !editing else { return }
        cancelLearning(); learnedButton = nil
        releaseAll(for: remote)
        saveActivePreset(remote)
        guard var bank = configuration.presetBanks?[remote.rawValue] else { return }
        bank.selectedIndex = index
        configuration.mappings = configuration.mappings.filter { !$0.key.hasPrefix(remote.rawValue + ".") }
        for (key, value) in bank.combinations[index] where key.hasPrefix(remote.rawValue + ".") {
            configuration.mappings[key] = value
        }
        configuration.presetBanks?[remote.rawValue] = bank
        save(); onConfigurationChanged?()
    }

    func targetTitle(for button: RemoteButtonDefinition, remote: SupportedRemoteID) -> String {
        if remote == .x6, button.voiceControlled { return "切换麦克风开关" }
        if let mapping = mapping(remote, button.id) { return mapping.action == .unconfigured ? "禁用" : mapping.action.summary }
        if remote == .mxMaster3s { return RemoteProfiles.mxNativeTitle(for: button.id) }
        return button.voiceControlled ? "待配置语音操作" : button.defaultTarget.title
    }
    func learn(_ remote: SupportedRemoteID) {
        learningTimeout?.cancel()
        learning = remote; learnedButton = nil
        learningTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remote == .mxMaster3s ? 60 : 15))
            guard !Task.isCancelled else { return }
            self?.learning = nil
        }
    }
    func cancelLearning() { learningTimeout?.cancel(); learning = nil }
    func post(button: RemoteButtonDefinition, remote: SupportedRemoteID, isDown: Bool) {
        let id = key(remote, button.id)
        if isDown {
            lastInput = "\(remote.title) · \(button.title)"
            if learning == remote { learnedButton = button.id; cancelLearning(); return }
            guard !editing, isEnabled(remote), pressed.insert(id).inserted else { return }
            if let mapping = mapping(remote, button.id) {
                if case let .keyboardShortcut(binding) = mapping.action, !binding.isMouse,
                   mapping.holdShortcut || PhysicalModifierKey(keyCode: binding.keyCode) != nil {
                    if mapping.holdShortcut {
                        let alreadyHeld = held.values.contains(binding)
                        held[id] = binding
                        if !alreadyHeld { postKey(binding, down: true) }
                    } else { postKey(binding, down: true); postKey(binding, down: false) }
                } else if mapping.action != .unconfigured { onAction?(mapping.action) }
                if mapping.releaseAction != .unconfigured { releases[id] = mapping.releaseAction }
            } else if !button.voiceControlled {
                defaultsHeld[id] = button.defaultTarget
                button.defaultTarget.post(isDown: true)
            }
        } else {
            pressed.remove(id)
            if let binding = held.removeValue(forKey: id), !held.values.contains(binding) { postKey(binding, down: false) }
            defaultsHeld.removeValue(forKey: id)?.post(isDown: false)
            if let action = releases.removeValue(forKey: id) { onAction?(action) }
        }
    }
    func voice(_ remote: SupportedRemoteID, down: Bool) {
        guard let button = RemoteProfiles.buttons(for: remote).first(where: \.voiceControlled) else { return }
        post(button: button, remote: remote, isDown: down)
    }
    func releaseAll(for remote: SupportedRemoteID) {
        for button in RemoteProfiles.buttons(for: remote) { post(button: button, remote: remote, isDown: false) }
    }
    private func postKey(_ binding: KeyboardShortcutBinding, down: Bool) {
        if let keyEventSink { keyEventSink(binding, down); return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: binding.keyCode, keyDown: down) else { return }
        event.flags = binding.modifiers.cgEventFlags
        if let modifier = PhysicalModifierKey(keyCode: binding.keyCode) {
            event.type = .flagsChanged
            if down { event.flags.insert(CGEventFlags(rawValue: modifier.eventFlagRawValue)) }
        }
        event.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        event.post(tap: .cghidEventTap)
    }
}
