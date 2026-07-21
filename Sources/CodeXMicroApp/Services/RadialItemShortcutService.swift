import Carbon
import Foundation

private let radialItemHotKeyCallback: EventHandlerUPP = { _, event, userData in
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
    let service = Unmanaged<RadialItemShortcutService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

@MainActor
final class RadialItemShortcutService {
    private struct RegisteredHotKey: @unchecked Sendable {
        let reference: EventHotKeyRef
        let gesture: ShortcutGesture
    }

    private static let hotKeySignature: OSType = 0x5244_4C49

    private var registeredHotKeys: [UInt32: RegisteredHotKey] = [:]
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var onTrigger: ((ShortcutGesture) -> Void)?
    private var profiles: [RadialMenuProfile] = []
    private var isSuspended = false

    deinit {
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey.reference)
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func start(onTrigger: @escaping (ShortcutGesture) -> Void) {
        self.onTrigger = onTrigger
        _ = installEventHandlerIfNeeded()
        _ = registerCurrentProfiles()
    }

    @discardableResult
    func update(profiles: [RadialMenuProfile]) -> Set<UUID> {
        self.profiles = profiles
        guard onTrigger != nil, !isSuspended else { return [] }
        return registerCurrentProfiles()
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            unregisterAll()
        } else {
            _ = registerCurrentProfiles()
        }
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let registered = registeredHotKeys[id] else { return }
        onTrigger?(registered.gesture)
    }

    private func registerCurrentProfiles() -> Set<UUID> {
        unregisterAll()
        guard installEventHandlerIfNeeded() else {
            return Set(profiles.flatMap(\.items).compactMap { $0.triggerShortcut == nil ? nil : $0.id })
        }

        var itemIDsByGesture: [ShortcutGesture: [UUID]] = [:]
        for profile in profiles {
            for item in profile.items {
                guard let binding = item.triggerShortcut, !binding.modifiers.isEmpty else { continue }
                itemIDsByGesture[binding.gesture, default: []].append(item.id)
            }
        }

        var failures: Set<UUID> = []
        for (offset, entry) in itemIDsByGesture.sorted(by: { lhs, rhs in
            if lhs.key.keyCode != rhs.key.keyCode { return lhs.key.keyCode < rhs.key.keyCode }
            return lhs.key.modifiers.rawValue < rhs.key.modifiers.rawValue
        }).enumerated() {
            let id = UInt32(offset + 1)
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
            let status = RegisterEventHotKey(
                UInt32(entry.key.keyCode),
                carbonFlags(for: entry.key.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                failures.formUnion(entry.value)
                continue
            }
            registeredHotKeys[id] = RegisteredHotKey(reference: reference, gesture: entry.key)
        }
        return failures
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            radialItemHotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status == noErr && eventHandler != nil
    }

    private func unregisterAll() {
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey.reference)
        }
        registeredHotKeys.removeAll()
    }

    private func carbonFlags(for modifiers: ShortcutModifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
