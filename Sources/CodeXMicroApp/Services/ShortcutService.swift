import AppKit
import ApplicationServices
import Carbon
import OSLog

private let shortcutHotKeySignature: OSType = 0x434D_4943 // "CMIC"

private enum DirectKeyEventKind: Sendable {
    case down
    case up
    case flagsChanged
    case tapDisabled
    case other
}

private struct DirectKeyEventSnapshot: Sendable {
    let kind: DirectKeyEventKind
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let eventFlagsRawValue: UInt64
    let keyLabel: String
    let isRepeat: Bool
    let isSynthetic: Bool
}

private struct DirectKeyEventDecision: Sendable {
    let suppress: Bool
    let modifierFlagsToStripRawValue: UInt64
}

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
    let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.handleRegisteredHotKey(id: hotKeyID.id, isPressed: isPressed)
    }
    return noErr
}

private let shortcutDirectKeyEventTapCallback: CGEventTapCallBack = { _, type, event, userData in
    guard let userData else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    let kind: DirectKeyEventKind = switch type {
    case .keyDown: .down
    case .keyUp: .up
    case .flagsChanged: .flagsChanged
    case .tapDisabledByTimeout, .tapDisabledByUserInput: .tapDisabled
    default: .other
    }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let snapshot = DirectKeyEventSnapshot(
        kind: kind,
        keyCode: keyCode,
        modifiers: ShortcutModifiers(event.flags),
        eventFlagsRawValue: event.flags.rawValue,
        keyLabel: ShortcutKeyCatalog.label(for: keyCode) ?? "Key \(keyCode)",
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        isSynthetic: event.getIntegerValueField(.eventSourceUserData) == ShortcutEventMarker.codexAutomation
    )
    let decision = MainActor.assumeIsolated {
        service.handleDirectKeyEvent(snapshot)
    }
    if decision.suppress { return nil }
    if decision.modifierFlagsToStripRawValue != 0 {
        event.flags = CGEventFlags(
            rawValue: event.flags.rawValue & ~decision.modifierFlagsToStripRawValue
        )
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class ShortcutService {
    private static let logger = Logger(subsystem: "com.gumu.codexmicro.virtual", category: "shortcuts")

    enum CaptureEvent: Sendable {
        case captured(ShortcutTarget, KeyboardShortcutBinding)
        case cancelled(ShortcutTarget)
    }

    enum RegistrationFailure: Equatable {
        case duplicateBinding
        case hotKeyConflict
        case shadowedByPhysicalMapping
        case accessibilityRequired
        case directMonitorUnavailable

        var preventsSaving: Bool {
            switch self {
            case .duplicateBinding, .hotKeyConflict, .shadowedByPhysicalMapping: true
            case .accessibilityRequired, .directMonitorUnavailable: false
            }
        }
    }

    private var bindings: [ShortcutTarget: KeyboardShortcutBinding] = [:]
    private var recordingTarget: ShortcutTarget?
    private var directKeyTargetsByKeyCode: [UInt16: ShortcutTarget] = [:]
    private var directKeyEventMatcher = DirectKeyEventMatcher()
    private var physicalModifierKeyState = PhysicalModifierKeyState()
    private var pendingRecordingModifierKeyCode: UInt16?
    private var pressedHotKeyTargets: Set<ShortcutTarget> = []
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var hotKeyHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var registeredHotKeys: [ShortcutTarget: EventHotKeyRef] = [:]
    nonisolated(unsafe) private var directKeyEventTap: CFMachPort?
    nonisolated(unsafe) private var directKeyRunLoopSource: CFRunLoopSource?
    private var targetsByHotKeyID: [UInt32: ShortcutTarget] = [:]
    private var onTrigger: ((ShortcutTarget) -> Void)?
    private var onRelease: ((ShortcutTarget) -> Void)?
    private var onCapture: ((CaptureEvent) -> Void)?

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for hotKey in registeredHotKeys.values { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
        if let directKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), directKeyRunLoopSource, .commonModes)
        }
        if let directKeyEventTap {
            CGEvent.tapEnable(tap: directKeyEventTap, enable: false)
            CFMachPortInvalidate(directKeyEventTap)
        }
    }

    var isDirectKeyMonitoringActive: Bool {
        guard !directKeyTargetsByKeyCode.isEmpty, let directKeyEventTap else { return false }
        return CGEvent.tapIsEnabled(tap: directKeyEventTap)
    }

    func start(
        onTrigger: @escaping (ShortcutTarget) -> Void,
        onRelease: @escaping (ShortcutTarget) -> Void,
        onCapture: @escaping (CaptureEvent) -> Void
    ) {
        self.onTrigger = onTrigger
        self.onRelease = onRelease
        self.onCapture = onCapture
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        installHotKeyHandler()
        _ = registerCurrentBindings()
    }

    @discardableResult
    func update(bindings: [ShortcutTarget: KeyboardShortcutBinding]) -> [ShortcutTarget: RegistrationFailure] {
        self.bindings = bindings
        guard recordingTarget == nil else { return [:] }
        return registerCurrentBindings()
    }

    func beginRecording(for target: ShortcutTarget) {
        unregisterAllHotKeys()
        releaseSuppressedDirectKeys()
        pendingRecordingModifierKeyCode = nil
        recordingTarget = target
        _ = installDirectKeyMonitorIfNeeded()
    }

    func cancelRecording() {
        guard let target = recordingTarget else { return }
        recordingTarget = nil
        pendingRecordingModifierKeyCode = nil
        onCapture?(.cancelled(target))
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let target = recordingTarget else { return false }
        guard !event.isARepeat else { return true }
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ShortcutEventMarker.codexAutomation {
            return false
        }

        if event.type == .flagsChanged, PhysicalModifierKey(keyCode: event.keyCode) != nil {
            let phase = updatePhysicalModifierState(
                keyCode: event.keyCode,
                eventFlagsRawValue: event.cgEvent?.flags.rawValue ?? 0
            )
            if phase == .down {
                pendingRecordingModifierKeyCode = event.keyCode
                return true
            }

            if pendingRecordingModifierKeyCode == event.keyCode {
                recordingTarget = nil
                pendingRecordingModifierKeyCode = nil
                physicalModifierKeyState.reset()
                onCapture?(.captured(
                    target,
                    KeyboardShortcutBinding(
                        keyCode: event.keyCode,
                        modifiers: [],
                        keyLabel: Self.keyLabel(for: event)
                    )
                ))
            }
            return true
        }

        guard event.type == .keyDown else { return false }

        let binding = KeyboardShortcutBinding(
            keyCode: event.keyCode,
            modifiers: ShortcutModifiers(event.modifierFlags),
            keyLabel: Self.keyLabel(for: event)
        )
        recordingTarget = nil
        pendingRecordingModifierKeyCode = nil
        physicalModifierKeyState.reset()
        onCapture?(.captured(target, binding))
        return true
    }

    fileprivate func handleDirectKeyEvent(_ event: DirectKeyEventSnapshot) -> DirectKeyEventDecision {
        if event.kind == .tapDisabled {
            releaseSuppressedDirectKeys()
            physicalModifierKeyState.reset()
            if let directKeyEventTap {
                CGEvent.tapEnable(tap: directKeyEventTap, enable: true)
                Self.logger.warning("Direct key event tap was disabled and has been re-enabled")
            }
            return DirectKeyEventDecision(suppress: false, modifierFlagsToStripRawValue: 0)
        }

        let modifierPhase: ShortcutKeyPhase? = if event.kind == .flagsChanged,
                                                   PhysicalModifierKey(keyCode: event.keyCode) != nil {
            updatePhysicalModifierState(
                keyCode: event.keyCode,
                eventFlagsRawValue: event.eventFlagsRawValue
            )
        } else {
            nil
        }

        if let target = recordingTarget {
            guard !event.isSynthetic else { return eventDecision(suppress: false) }

            if event.kind == .flagsChanged, let modifierPhase {
                if modifierPhase == .down {
                    pendingRecordingModifierKeyCode = event.keyCode
                } else if pendingRecordingModifierKeyCode == event.keyCode {
                    recordingTarget = nil
                    pendingRecordingModifierKeyCode = nil
                    physicalModifierKeyState.reset()
                    deliverCaptureAfterEventTap(.captured(
                        target,
                        KeyboardShortcutBinding(
                            keyCode: event.keyCode,
                            modifiers: [],
                            keyLabel: event.keyLabel
                        )
                    ))
                }
                return eventDecision(suppress: true)
            }

            guard event.kind == .down else { return eventDecision(suppress: false) }
            guard !event.isRepeat else { return eventDecision(suppress: true) }

            recordingTarget = nil
            pendingRecordingModifierKeyCode = nil
            physicalModifierKeyState.reset()
            deliverCaptureAfterEventTap(.captured(
                target,
                KeyboardShortcutBinding(
                    keyCode: event.keyCode,
                    modifiers: event.modifiers,
                    keyLabel: event.keyLabel
                )
            ))
            return eventDecision(suppress: true)
        }

        let phase: ShortcutKeyPhase
        switch event.kind {
        case .down: phase = .down
        case .up: phase = .up
        case .flagsChanged:
            guard let modifierPhase else { return eventDecision(suppress: false) }
            phase = modifierPhase
        default: return eventDecision(suppress: false)
        }

        let outcome = directKeyEventMatcher.handle(
            keyCode: event.keyCode,
            modifiers: event.modifiers,
            phase: phase,
            isRepeat: event.isRepeat,
            isSynthetic: event.isSynthetic,
            targetsByKeyCode: directKeyTargetsByKeyCode
        )

        switch outcome {
        case .passThrough:
            return eventDecision(suppress: false)
        case .suppress:
            return eventDecision(suppress: true)
        case let .trigger(target):
            if event.kind == .flagsChanged {
                physicalModifierKeyState.setMappedKeySuppressed(true, keyCode: event.keyCode)
            }
            Self.logger.info("Direct key triggered \(target.rawValue, privacy: .public)")
            onTrigger?(target)
            return eventDecision(suppress: true)
        case let .release(target):
            physicalModifierKeyState.setMappedKeySuppressed(false, keyCode: event.keyCode)
            onRelease?(target)
            return eventDecision(suppress: true)
        }
    }

    fileprivate func handleRegisteredHotKey(id: UInt32, isPressed: Bool) {
        guard recordingTarget == nil, let target = targetsByHotKeyID[id] else { return }
        if isPressed {
            guard pressedHotKeyTargets.insert(target).inserted else { return }
            Self.logger.info("Triggered \(target.rawValue, privacy: .public)")
            onTrigger?(target)
        } else {
            guard pressedHotKeyTargets.remove(target) != nil else { return }
            onRelease?(target)
        }
    }

    private func installHotKeyHandler() {
        guard hotKeyHandlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                shortcutHotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &hotKeyHandlerRef
            )
        }
        Self.logger.info("Hotkey handler install status: \(status, privacy: .public)")
    }

    private func registerCurrentBindings() -> [ShortcutTarget: RegistrationFailure] {
        unregisterAllHotKeys()
        releaseSuppressedDirectKeys()
        directKeyTargetsByKeyCode.removeAll()

        var failures: [ShortcutTarget: RegistrationFailure] = [:]
        let directBindings = ShortcutTarget.allCases.compactMap { target -> (ShortcutTarget, KeyboardShortcutBinding)? in
            guard let binding = bindings[target], binding.activationMode == .directKey else { return nil }
            return (target, binding)
        }

        if directBindings.isEmpty {
            uninstallDirectKeyMonitor()
        } else if let failure = installDirectKeyMonitorIfNeeded() {
            for (target, _) in directBindings { failures[target] = failure }
        } else {
            for (target, binding) in directBindings {
                if directKeyTargetsByKeyCode[binding.keyCode] == nil {
                    directKeyTargetsByKeyCode[binding.keyCode] = target
                    Self.logger.info("Monitoring \(target.rawValue, privacy: .public) directly as \(binding.displayName, privacy: .public)")
                } else {
                    failures[target] = .duplicateBinding
                }
            }
        }

        let mappedKeyCodes = Set(directBindings.map { $0.1.keyCode })
        var fullyMappedModifierFlags: ShortcutModifiers = []
        for modifier in [
            ShortcutModifiers.command,
            .control,
            .option,
            .shift
        ] {
            let keyCodes = PhysicalModifierKey.allCases
                .filter { $0.shortcutModifier == modifier }
                .map(\.rawValue)
            if !keyCodes.isEmpty, keyCodes.allSatisfy(mappedKeyCodes.contains) {
                fullyMappedModifierFlags.insert(modifier)
            }
        }

        for target in ShortcutTarget.allCases {
            guard let binding = bindings[target], binding.activationMode == .registeredHotKey else { continue }
            guard !mappedKeyCodes.contains(binding.keyCode),
                  binding.modifiers.intersection(fullyMappedModifierFlags).isEmpty else {
                failures[target] = .shadowedByPhysicalMapping
                continue
            }
            guard hotKeyHandlerRef != nil else {
                failures[target] = .hotKeyConflict
                continue
            }
            guard let index = ShortcutTarget.allCases.firstIndex(of: target) else { continue }
            let id = UInt32(index + 1)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.modifiers.carbonFlags,
                EventHotKeyID(signature: shortcutHotKeySignature, id: id),
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive),
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                registeredHotKeys[target] = hotKeyRef
                targetsByHotKeyID[id] = target
                Self.logger.info("Registered \(target.rawValue, privacy: .public) as \(binding.displayName, privacy: .public)")
            } else {
                failures[target] = .hotKeyConflict
                Self.logger.error("Failed to register \(target.rawValue, privacy: .public) as \(binding.displayName, privacy: .public): \(status, privacy: .public)")
            }
        }
        return failures
    }

    private func installDirectKeyMonitorIfNeeded() -> RegistrationFailure? {
        guard AXIsProcessTrusted() else {
            uninstallDirectKeyMonitor()
            return .accessibilityRequired
        }

        if let directKeyEventTap {
            if !CGEvent.tapIsEnabled(tap: directKeyEventTap) {
                CGEvent.tapEnable(tap: directKeyEventTap, enable: true)
            }
            if CGEvent.tapIsEnabled(tap: directKeyEventTap) { return nil }
            uninstallDirectKeyMonitor()
        }

        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: shortcutDirectKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            uninstallDirectKeyMonitor()
            Self.logger.error("Could not create direct key event tap")
            return .directMonitorUnavailable
        }

        directKeyEventTap = eventTap
        directKeyRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Self.logger.info("Direct key event tap installed")
        return nil
    }

    private func uninstallDirectKeyMonitor() {
        releaseSuppressedDirectKeys()
        if let directKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), directKeyRunLoopSource, .commonModes)
        }
        if let directKeyEventTap {
            CGEvent.tapEnable(tap: directKeyEventTap, enable: false)
            CFMachPortInvalidate(directKeyEventTap)
        }
        directKeyRunLoopSource = nil
        directKeyEventTap = nil
        directKeyTargetsByKeyCode.removeAll()
        physicalModifierKeyState.reset()
    }

    private func unregisterAllHotKeys() {
        for target in pressedHotKeyTargets { onRelease?(target) }
        pressedHotKeyTargets.removeAll()
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
        targetsByHotKeyID.removeAll()
    }

    private func releaseSuppressedDirectKeys() {
        for target in directKeyEventMatcher.drainTargets() {
            onRelease?(target)
        }
        physicalModifierKeyState.clearSuppressedMappings()
    }

    private func updatePhysicalModifierState(
        keyCode: UInt16,
        eventFlagsRawValue: UInt64
    ) -> ShortcutKeyPhase {
        physicalModifierKeyState.update(
            keyCode: keyCode,
            eventFlagsRawValue: eventFlagsRawValue
        )
    }

    private func eventDecision(suppress: Bool) -> DirectKeyEventDecision {
        DirectKeyEventDecision(
            suppress: suppress,
            modifierFlagsToStripRawValue: physicalModifierKeyState.modifierFlagsToStripRawValue
        )
    }

    private func deliverCaptureAfterEventTap(_ event: CaptureEvent) {
        Task { @MainActor [weak self] in
            self?.onCapture?(event)
        }
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if let label = ShortcutKeyCatalog.label(for: event.keyCode) { return label }
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
    init(_ flags: CGEventFlags) {
        var value: ShortcutModifiers = []
        if flags.contains(.maskCommand) { value.insert(.command) }
        if flags.contains(.maskControl) { value.insert(.control) }
        if flags.contains(.maskAlternate) { value.insert(.option) }
        if flags.contains(.maskShift) { value.insert(.shift) }
        self = value
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
