import AppKit
import ApplicationServices
import Carbon
import OSLog

private enum DirectKeyEventKind: Sendable {
    case down
    case up
    case flagsChanged
    case mouseDown
    case mouseUp
    case tapDisabled
    case other
}

private struct DirectKeyEventSnapshot: Sendable {
    let kind: DirectKeyEventKind
    let keyCode: UInt16
    let mouseButton: UInt32?
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

private let shortcutDirectKeyEventTapCallback: CGEventTapCallBack = { _, type, event, userData in
    guard let userData else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    let kind: DirectKeyEventKind = switch type {
    case .keyDown: .down
    case .keyUp: .up
    case .flagsChanged: .flagsChanged
    case .leftMouseDown, .rightMouseDown, .otherMouseDown: .mouseDown
    case .leftMouseUp, .rightMouseUp, .otherMouseUp: .mouseUp
    case .tapDisabledByTimeout, .tapDisabledByUserInput: .tapDisabled
    default: .other
    }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let mouseButton: UInt32? = switch kind {
    case .mouseDown, .mouseUp:
        UInt32(truncatingIfNeeded: event.getIntegerValueField(.mouseEventButtonNumber))
    default:
        nil
    }
    let snapshot = DirectKeyEventSnapshot(
        kind: kind,
        keyCode: keyCode,
        mouseButton: mouseButton,
        modifiers: ShortcutModifiers(event.flags),
        eventFlagsRawValue: event.flags.rawValue,
        keyLabel: mouseButton.map(MouseButtonCatalog.label(for:))
            ?? ShortcutKeyCatalog.label(for: keyCode)
            ?? "宏键 \(keyCode)",
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

private let shortcutHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
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
    guard status == noErr else { return status }
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    let eventKind = GetEventKind(event)
    MainActor.assumeIsolated {
        service.handleSystemHotKey(id: hotKeyID.id, isPressed: eventKind == kEventHotKeyPressed)
    }
    return noErr
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
        case shadowedByPhysicalMapping
        case systemHotKeyConflict
        case hotKeyRegistrationUnavailable
        case accessibilityRequired
        case directMonitorUnavailable

        var preventsSaving: Bool {
            switch self {
            case .duplicateBinding, .shadowedByPhysicalMapping,
                 .hotKeyRegistrationUnavailable: true
            case .systemHotKeyConflict, .accessibilityRequired,
                 .directMonitorUnavailable: false
            }
        }
    }

    private struct RegisteredHotKey: @unchecked Sendable {
        let target: ShortcutTarget
        let reference: EventHotKeyRef
    }

    private static let hotKeySignature: OSType = 0x4344_584D
    private static let systemHotKeyTargets: [ShortcutTarget] = [.quickLaunch, .radialMenu]

    private var bindings: [ShortcutTarget: KeyboardShortcutBinding] = [:]
    private var recordingTarget: ShortcutTarget?
    private var directKeyTargetsByKeyCode: [UInt16: ShortcutTarget] = [:]
    private var combinationTargetsByGesture: [ShortcutGesture: ShortcutTarget] = [:]
    private var mouseTargetsByGesture: [ShortcutGesture: ShortcutTarget] = [:]
    private var hidTargetsByGesture: [ShortcutGesture: ShortcutTarget] = [:]
    private var directKeyEventMatcher = DirectKeyEventMatcher()
    private var combinationKeyEventMatcher = CombinationKeyEventMatcher()
    private var mouseButtonEventMatcher = MouseButtonEventMatcher()
    private var hidButtonEventMatcher = HIDButtonEventMatcher()
    private var physicalModifierKeyState = PhysicalModifierKeyState()
    private var pendingRecordingModifierKeyCode: UInt16?
    private var registeredHotKeysByID: [UInt32: RegisteredHotKey] = [:]
    private var pressedHotKeyIDs: Set<UInt32> = []
    nonisolated(unsafe) private var hotKeyEventHandler: EventHandlerRef?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var directKeyEventTap: CFMachPort?
    nonisolated(unsafe) private var directKeyRunLoopSource: CFRunLoopSource?
    private var hidObserverToken: UUID?
    private var onTrigger: ((ShortcutTarget) -> Void)?
    private var onRelease: ((ShortcutTarget) -> Void)?
    private var onCapture: ((CaptureEvent) -> Void)?

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for hotKey in registeredHotKeysByID.values {
            UnregisterEventHotKey(hotKey.reference)
        }
        if let hotKeyEventHandler { RemoveEventHandler(hotKeyEventHandler) }
        if let directKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), directKeyRunLoopSource, .commonModes)
        }
        if let directKeyEventTap {
            CGEvent.tapEnable(tap: directKeyEventTap, enable: false)
            CFMachPortInvalidate(directKeyEventTap)
        }
        let token = hidObserverToken
        Task { @MainActor in HIDButtonMonitor.shared.removeObserver(token) }
    }

    var isKeyMonitoringActive: Bool {
        guard !bindings.isEmpty else { return false }
        let priorityBindings = bindings.filter {
            !$0.value.isHIDButton
                && (!Self.systemHotKeyTargets.contains($0.key) || $0.value.isMouse)
        }
        let priorityMonitoringActive = priorityBindings.isEmpty
            || directKeyEventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        let systemHotKeysActive = Self.systemHotKeyTargets.allSatisfy { target in
            guard let binding = bindings[target] else { return true }
            if binding.isMouse {
                if binding.isHIDButton {
                    return hidTargetsByGesture[binding.gesture] == target
                        && HIDButtonMonitor.shared.isAvailable
                }
                return mouseTargetsByGesture[binding.gesture] == target
                    && directKeyEventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
            }
            return registeredHotKeysByID.values.contains { $0.target == target }
        }
        return priorityMonitoringActive && systemHotKeysActive
    }

    func isActive(_ target: ShortcutTarget) -> Bool {
        guard let binding = bindings[target] else { return false }
        switch binding.activationMode {
        case .directKey:
            return directKeyTargetsByKeyCode[binding.keyCode] == target
                && directKeyEventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        case .registeredHotKey:
            if Self.systemHotKeyTargets.contains(target) {
                return registeredHotKeysByID.values.contains { $0.target == target }
            }
            return combinationTargetsByGesture[binding.gesture] == target
                && directKeyEventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        case .mouseButton:
            return mouseTargetsByGesture[binding.gesture] == target
                && directKeyEventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
        case .hidButton:
            return hidTargetsByGesture[binding.gesture] == target
                && HIDButtonMonitor.shared.isAvailable
        }
    }

    func start(
        onTrigger: @escaping (ShortcutTarget) -> Void,
        onRelease: @escaping (ShortcutTarget) -> Void,
        onCapture: @escaping (CaptureEvent) -> Void
    ) {
        self.onTrigger = onTrigger
        self.onRelease = onRelease
        self.onCapture = onCapture
        if hidObserverToken == nil {
            hidObserverToken = HIDButtonMonitor.shared.addObserver { [weak self] event in
                self?.handleHIDButtonEvent(event)
            }
        }
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        _ = registerCurrentBindings()
    }

    @discardableResult
    func update(bindings: [ShortcutTarget: KeyboardShortcutBinding]) -> [ShortcutTarget: RegistrationFailure] {
        self.bindings = bindings
        guard recordingTarget == nil else { return [:] }
        return registerCurrentBindings()
    }

    func beginRecording(for target: ShortcutTarget) {
        releaseSuppressedKeyEvents()
        unregisterSystemHotKeys()
        pendingRecordingModifierKeyCode = nil
        recordingTarget = target
        _ = installDirectKeyMonitorIfNeeded()
    }

    private func handleHIDButtonEvent(_ event: HIDButtonEvent) {
        let modifiers = ShortcutModifiers(
            eventFlagsRawValue: CGEventSource.flagsState(.combinedSessionState).rawValue
        )

        if let target = recordingTarget, event.phase == .down {
            guard event.identifier.usage > 3 else { return }
            recordingTarget = nil
            pendingRecordingModifierKeyCode = nil
            physicalModifierKeyState.reset()
            onCapture?(.captured(
                target,
                .hidButton(event.identifier, modifiers: modifiers)
            ))
            return
        }

        let outcome = hidButtonEventMatcher.handle(
            button: event.identifier,
            modifiers: modifiers,
            phase: event.phase,
            targetsByGesture: hidTargetsByGesture
        )
        switch outcome {
        case .passThrough, .suppress:
            break
        case let .trigger(target):
            Self.logger.info("Raw HID macro button triggered \(target.rawValue, privacy: .public)")
            onTrigger?(target)
        case let .release(target):
            onRelease?(target)
        }
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
            releaseSuppressedKeyEvents()
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

            if event.kind == .mouseDown, let mouseButton = event.mouseButton {
                recordingTarget = nil
                pendingRecordingModifierKeyCode = nil
                physicalModifierKeyState.reset()
                deliverCaptureAfterEventTap(.captured(
                    target,
                    .mouse(button: mouseButton, modifiers: event.modifiers)
                ))
                return eventDecision(suppress: true)
            }

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

        if let mouseButton = event.mouseButton {
            let phase: ShortcutKeyPhase = event.kind == .mouseDown ? .down : .up
            let outcome = mouseButtonEventMatcher.handle(
                button: mouseButton,
                modifiers: event.modifiers,
                phase: phase,
                isSynthetic: event.isSynthetic,
                targetsByGesture: mouseTargetsByGesture
            )
            switch outcome {
            case .passThrough:
                return eventDecision(suppress: false)
            case .suppress:
                return eventDecision(suppress: true)
            case let .trigger(target):
                Self.logger.info("Mapped mouse button triggered \(target.rawValue, privacy: .public)")
                onTrigger?(target)
                return eventDecision(suppress: true)
            case let .release(target):
                onRelease?(target)
                return eventDecision(suppress: true)
            }
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

        let directOutcome = directKeyEventMatcher.handle(
            keyCode: event.keyCode,
            modifiers: event.modifiers,
            phase: phase,
            isRepeat: event.isRepeat,
            isSynthetic: event.isSynthetic,
            targetsByKeyCode: directKeyTargetsByKeyCode
        )
        let outcome = if case .passThrough = directOutcome {
            combinationKeyEventMatcher.handle(
                keyCode: event.keyCode,
                modifiers: event.modifiers,
                phase: phase,
                isRepeat: event.isRepeat,
                isSynthetic: event.isSynthetic,
                targetsByGesture: combinationTargetsByGesture
            )
        } else {
            directOutcome
        }
        switch outcome {
        case .passThrough:
            return eventDecision(suppress: false)
        case .suppress:
            return eventDecision(suppress: true)
        case let .trigger(target):
            if event.kind == .flagsChanged {
                physicalModifierKeyState.setMappedKeySuppressed(true, keyCode: event.keyCode)
            }
            Self.logger.info("Mapped key triggered \(target.rawValue, privacy: .public)")
            onTrigger?(target)
            return eventDecision(suppress: true)
        case let .release(target):
            physicalModifierKeyState.setMappedKeySuppressed(false, keyCode: event.keyCode)
            onRelease?(target)
            return eventDecision(suppress: true)
        }
    }

    private func registerCurrentBindings() -> [ShortcutTarget: RegistrationFailure] {
        releaseSuppressedKeyEvents()
        unregisterSystemHotKeys()
        directKeyTargetsByKeyCode.removeAll()
        combinationTargetsByGesture.removeAll()
        mouseTargetsByGesture.removeAll()
        hidTargetsByGesture.removeAll()

        var failures: [ShortcutTarget: RegistrationFailure] = [:]
        let priorityBindings = ShortcutTarget.allCases.compactMap { target -> (ShortcutTarget, KeyboardShortcutBinding)? in
            guard let binding = bindings[target],
                  !binding.isHIDButton,
                  (!Self.systemHotKeyTargets.contains(target) || binding.isMouse) else { return nil }
            return (target, binding)
        }
        let directBindings = ShortcutTarget.allCases.compactMap { target -> (ShortcutTarget, KeyboardShortcutBinding)? in
            guard !Self.systemHotKeyTargets.contains(target),
                  let binding = bindings[target],
                  binding.activationMode == .directKey else { return nil }
            return (target, binding)
        }
        let mouseBindings = ShortcutTarget.allCases.compactMap { target -> (ShortcutTarget, KeyboardShortcutBinding)? in
            guard let binding = bindings[target], binding.isMouse, !binding.isHIDButton else { return nil }
            return (target, binding)
        }
        let hidBindings = ShortcutTarget.allCases.compactMap { target -> (ShortcutTarget, KeyboardShortcutBinding)? in
            guard let binding = bindings[target], binding.isHIDButton else { return nil }
            return (target, binding)
        }

        for (target, binding) in hidBindings {
            if hidTargetsByGesture[binding.gesture] == nil {
                hidTargetsByGesture[binding.gesture] = target
                Self.logger.info("Monitoring \(target.rawValue, privacy: .public) as raw HID \(binding.displayName, privacy: .public)")
            } else {
                failures[target] = .duplicateBinding
            }
        }

        if priorityBindings.isEmpty {
            uninstallDirectKeyMonitor()
        } else if let failure = installDirectKeyMonitorIfNeeded() {
            for (target, _) in priorityBindings { failures[target] = failure }
        } else {
            for (target, binding) in directBindings {
                if directKeyTargetsByKeyCode[binding.keyCode] == nil {
                    directKeyTargetsByKeyCode[binding.keyCode] = target
                    Self.logger.info("Monitoring \(target.rawValue, privacy: .public) directly as \(binding.displayName, privacy: .public)")
                } else {
                    failures[target] = .duplicateBinding
                }
            }
            for (target, binding) in mouseBindings {
                if mouseTargetsByGesture[binding.gesture] == nil {
                    mouseTargetsByGesture[binding.gesture] = target
                    Self.logger.info("Monitoring \(target.rawValue, privacy: .public) as \(binding.displayName, privacy: .public)")
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

        for target in ShortcutTarget.allCases where !Self.systemHotKeyTargets.contains(target) {
            guard let binding = bindings[target], binding.activationMode == .registeredHotKey else { continue }
            guard !mappedKeyCodes.contains(binding.keyCode),
                  binding.modifiers.intersection(fullyMappedModifierFlags).isEmpty else {
                failures[target] = .shadowedByPhysicalMapping
                continue
            }
            guard combinationTargetsByGesture[binding.gesture] == nil else {
                failures[target] = .duplicateBinding
                continue
            }
            combinationTargetsByGesture[binding.gesture] = target
            Self.logger.info("Monitoring \(target.rawValue, privacy: .public) as priority combination \(binding.displayName, privacy: .public)")
        }

        for (index, target) in Self.systemHotKeyTargets.enumerated() {
            guard let binding = bindings[target] else { continue }
            if binding.isMouse { continue }
            guard binding.activationMode == .registeredHotKey else {
                failures[target] = .hotKeyRegistrationUnavailable
                continue
            }
            guard !mappedKeyCodes.contains(binding.keyCode),
                  binding.modifiers.intersection(fullyMappedModifierFlags).isEmpty else {
                failures[target] = .shadowedByPhysicalMapping
                continue
            }
            guard combinationTargetsByGesture[binding.gesture] == nil else {
                failures[target] = .duplicateBinding
                continue
            }
            guard !SystemShortcutRegistry.contains(binding) else {
                failures[target] = .systemHotKeyConflict
                Self.logger.warning("Rejected \(target.rawValue, privacy: .public): \(binding.displayName, privacy: .public) is reserved by macOS")
                continue
            }
            guard installHotKeyEventHandlerIfNeeded() else {
                failures[target] = .hotKeyRegistrationUnavailable
                continue
            }

            let hotKeyID = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.modifiers.carbonFlags,
                EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyID),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                failures[target] = status == eventHotKeyExistsErr
                    ? .systemHotKeyConflict
                    : .hotKeyRegistrationUnavailable
                Self.logger.warning(
                    "Rejected \(target.rawValue, privacy: .public): system registration for \(binding.displayName, privacy: .public) failed with \(status)"
                )
                continue
            }
            registeredHotKeysByID[hotKeyID] = RegisteredHotKey(target: target, reference: reference)
            Self.logger.info("Registered \(target.rawValue, privacy: .public) as checked system hot key \(binding.displayName, privacy: .public)")
        }
        return failures
    }

    fileprivate func handleSystemHotKey(id: UInt32, isPressed: Bool) {
        guard let hotKey = registeredHotKeysByID[id] else { return }
        if isPressed {
            guard pressedHotKeyIDs.insert(id).inserted else { return }
            onTrigger?(hotKey.target)
        } else if pressedHotKeyIDs.remove(id) != nil {
            onRelease?(hotKey.target)
        }
    }

    private func installHotKeyEventHandlerIfNeeded() -> Bool {
        if hotKeyEventHandler != nil { return true }
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                shortcutHotKeyEventHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &hotKeyEventHandler
            )
        }
        return status == noErr && hotKeyEventHandler != nil
    }

    private func unregisterSystemHotKeys() {
        for id in pressedHotKeyIDs {
            if let hotKey = registeredHotKeysByID[id] {
                onRelease?(hotKey.target)
            }
        }
        for hotKey in registeredHotKeysByID.values {
            UnregisterEventHotKey(hotKey.reference)
        }
        registeredHotKeysByID.removeAll()
        pressedHotKeyIDs.removeAll()
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
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
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
        releaseSuppressedKeyEvents()
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
        combinationTargetsByGesture.removeAll()
        mouseTargetsByGesture.removeAll()
        physicalModifierKeyState.reset()
    }

    private func releaseSuppressedKeyEvents() {
        let targets = directKeyEventMatcher.drainTargets()
            .union(combinationKeyEventMatcher.drainTargets())
            .union(mouseButtonEventMatcher.drainTargets())
            .union(hidButtonEventMatcher.drainTargets())
        for target in targets {
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
        return value.isEmpty ? "宏键 \(event.keyCode)" : value.uppercased()
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
