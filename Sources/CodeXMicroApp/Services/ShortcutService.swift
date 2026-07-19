import AppKit
import Carbon
import OSLog

private let shortcutHotKeySignature: OSType = 0x434D_4943 // "CMIC"

private let shortcutHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == shortcutHotKeySignature else { return status }
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.handleRegisteredHotKey(id: hotKeyID.id)
    }
    return noErr
}

@MainActor
final class ShortcutService {
    private static let logger = Logger(subsystem: "com.gumu.codexmicro.virtual", category: "shortcuts")
    enum CaptureEvent {
        case captured(ShortcutTarget, KeyboardShortcutBinding)
        case cleared(ShortcutTarget)
        case cancelled(ShortcutTarget)
        case invalid(String)
    }

    private var bindings: [ShortcutTarget: KeyboardShortcutBinding] = [:]
    private var recordingTarget: ShortcutTarget?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var hotKeyHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var registeredHotKeys: [ShortcutTarget: EventHotKeyRef] = [:]
    private var targetsByHotKeyID: [UInt32: ShortcutTarget] = [:]
    private var onTrigger: ((ShortcutTarget) -> Void)?
    private var onCapture: ((CaptureEvent) -> Void)?

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for hotKey in registeredHotKeys.values { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
    }

    func start(
        onTrigger: @escaping (ShortcutTarget) -> Void,
        onCapture: @escaping (CaptureEvent) -> Void
    ) {
        self.onTrigger = onTrigger
        self.onCapture = onCapture
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        installHotKeyHandler()
        _ = registerCurrentBindings()
    }

    @discardableResult
    func update(bindings: [ShortcutTarget: KeyboardShortcutBinding]) -> Set<ShortcutTarget> {
        self.bindings = bindings
        guard recordingTarget == nil else { return [] }
        return registerCurrentBindings()
    }

    func beginRecording(for target: ShortcutTarget) {
        unregisterAllHotKeys()
        recordingTarget = target
    }

    func cancelRecording() {
        guard let target = recordingTarget else { return }
        recordingTarget = nil
        onCapture?(.cancelled(target))
        _ = registerCurrentBindings()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return recordingTarget != nil }
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ShortcutEventMarker.codexAutomation {
            return false
        }

        if let target = recordingTarget {
            if event.keyCode == 53 {
                recordingTarget = nil
                onCapture?(.cancelled(target))
                _ = registerCurrentBindings()
                return true
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                recordingTarget = nil
                onCapture?(.cleared(target))
                return true
            }

            let modifiers = ShortcutModifiers(event.modifierFlags)
            guard !modifiers.isEmpty || Self.isFunctionKey(event.keyCode) else {
                onCapture?(.invalid("快捷键需要至少一个修饰键（⌃⌥⇧⌘）"))
                return true
            }

            let binding = KeyboardShortcutBinding(
                keyCode: event.keyCode,
                modifiers: modifiers,
                keyLabel: Self.keyLabel(for: event)
            )
            recordingTarget = nil
            onCapture?(.captured(target, binding))
            return true
        }
        return false
    }

    fileprivate func handleRegisteredHotKey(id: UInt32) {
        guard recordingTarget == nil, let target = targetsByHotKeyID[id] else { return }
        Self.logger.info("Triggered \(target.rawValue, privacy: .public)")
        onTrigger?(target)
    }

    private func installHotKeyHandler() {
        guard hotKeyHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            shortcutHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
        Self.logger.info("Hotkey handler install status: \(status, privacy: .public)")
    }

    private func registerCurrentBindings() -> Set<ShortcutTarget> {
        unregisterAllHotKeys()
        guard hotKeyHandlerRef != nil else { return Set(bindings.keys) }

        var failures: Set<ShortcutTarget> = []
        for (target, binding) in bindings {
            guard let index = ShortcutTarget.allCases.firstIndex(of: target) else { continue }
            let id = UInt32(index + 1)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.modifiers.carbonFlags,
                EventHotKeyID(signature: shortcutHotKeySignature, id: id),
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                registeredHotKeys[target] = hotKeyRef
                targetsByHotKeyID[id] = target
                Self.logger.info("Registered \(target.rawValue, privacy: .public) as \(binding.displayName, privacy: .public)")
            } else {
                failures.insert(target)
                Self.logger.error("Failed to register \(target.rawValue, privacy: .public) as \(binding.displayName, privacy: .public): \(status, privacy: .public)")
            }
        }
        return failures
    }

    private func unregisterAllHotKeys() {
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
        targetsByHotKeyID.removeAll()
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (122...126).contains(keyCode) || (96...111).contains(keyCode)
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let namedKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let label = namedKeys[event.keyCode] { return label }
        let value = event.charactersIgnoringModifiers?.trimmingCharacters(in: .controlCharacters) ?? ""
        return value.isEmpty ? "Key \(event.keyCode)" : value.uppercased()
    }
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

private extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        if normalized.contains(.command) { value.insert(.command) }
        if normalized.contains(.control) { value.insert(.control) }
        if normalized.contains(.option) { value.insert(.option) }
        if normalized.contains(.shift) { value.insert(.shift) }
        self = value
    }
}
