import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    var glyphs: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct KeyboardShortcutBinding: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let keyLabel: String

    var displayName: String { modifiers.glyphs + keyLabel }
    var activationMode: ShortcutActivationMode {
        modifiers.isEmpty ? .directKey : .registeredHotKey
    }
    var gesture: ShortcutGesture {
        ShortcutGesture(keyCode: keyCode, modifiers: modifiers)
    }
}

struct ShortcutGesture: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
}

enum ShortcutActivationMode: String, Sendable {
    case directKey
    case registeredHotKey

    var label: String {
        switch self {
        case .directKey: "物理按键映射 · 一级"
        case .registeredHotKey: "组合按键映射 · 一级监听"
        }
    }
}

enum SystemShortcutRegistry {
    private static let relevantModifierMask: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    static func contains(_ binding: KeyboardShortcutBinding) -> Bool {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let entries = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }
        return contains(binding, in: entries)
    }

    static func contains(_ binding: KeyboardShortcutBinding, in entries: [String: Any]) -> Bool {
        let expectedModifiers = modifierFlags(for: binding.modifiers)
        return entries.values.contains { rawEntry in
            guard let entry = rawEntry as? [String: Any],
                  (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3 else {
                return false
            }
            let keyCode = UInt16(truncatingIfNeeded: parameters[1].uintValue)
            let modifiers = parameters[2].uintValue & relevantModifierMask
            return keyCode == binding.keyCode && modifiers == expectedModifiers
        }
    }

    private static func modifierFlags(for modifiers: ShortcutModifiers) -> UInt {
        var flags: UInt = 0
        if modifiers.contains(.shift) { flags |= 1 << 17 }
        if modifiers.contains(.control) { flags |= 1 << 18 }
        if modifiers.contains(.option) { flags |= 1 << 19 }
        if modifiers.contains(.command) { flags |= 1 << 20 }
        return flags
    }
}

enum ShortcutKeyCatalog {
    private static let dedicatedKeyLabels: [UInt16: String] = [
        64: "F17", 65: "Num .", 67: "Num ×", 69: "Num +", 71: "Num Clear",
        75: "Num ÷", 76: "Num Enter", 78: "Num −", 79: "F18", 80: "F19",
        81: "Num =", 82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3",
        86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7", 90: "F20",
        91: "Num 8", 92: "Num 9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
        106: "F16", 107: "F14", 109: "F10", 110: "Menu", 111: "F12",
        113: "F15", 114: "Insert / Help", 115: "Home", 116: "Page Up",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func label(for keyCode: UInt16) -> String? {
        PhysicalModifierKey(keyCode: keyCode)?.label
            ?? dedicatedKeyLabels[keyCode]
            ?? commonKeyLabels[keyCode]
    }

    static func keyCode(for label: String) -> UInt16? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: UInt16] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49,
            "backspace": 51, "delete": 51, "escape": 53, "esc": 53,
            "left": 123, "right": 124, "down": 125, "up": 126
        ]
        if let alias = aliases[normalized] { return alias }

        let labels = dedicatedKeyLabels.merging(commonKeyLabels) { current, _ in current }
        return labels.first(where: { $0.value.lowercased() == normalized })?.key
    }

    private static let commonKeyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "Esc", 117: "⌦"
    ]
}

enum PhysicalModifierKey: UInt16, CaseIterable, Sendable {
    case rightCommand = 54
    case leftCommand = 55
    case leftShift = 56
    case capsLock = 57
    case leftOption = 58
    case leftControl = 59
    case rightShift = 60
    case rightOption = 61
    case rightControl = 62
    case function = 63

    init?(keyCode: UInt16) {
        self.init(rawValue: keyCode)
    }

    var label: String {
        switch self {
        case .rightCommand: "右 Command"
        case .leftCommand: "左 Command"
        case .leftShift: "左 Shift"
        case .capsLock: "Caps Lock"
        case .leftOption: "左 Option"
        case .leftControl: "左 Control"
        case .rightShift: "右 Shift"
        case .rightOption: "右 Option"
        case .rightControl: "右 Control"
        case .function: "Fn"
        }
    }

    var shortcutModifier: ShortcutModifiers? {
        switch self {
        case .leftCommand, .rightCommand: .command
        case .leftShift, .rightShift: .shift
        case .leftOption, .rightOption: .option
        case .leftControl, .rightControl: .control
        case .capsLock, .function: nil
        }
    }

    /// Raw `CGEventFlags` value. Keeping CoreGraphics out of this model makes
    /// the matcher portable to the native logic test target.
    var eventFlagRawValue: UInt64 {
        switch self {
        case .leftCommand, .rightCommand: 1 << 20
        case .leftShift, .rightShift: 1 << 17
        case .leftOption, .rightOption: 1 << 19
        case .leftControl, .rightControl: 1 << 18
        case .capsLock: 1 << 16
        case .function: 1 << 23
        }
    }
}

struct PhysicalModifierKeyState: Sendable {
    private(set) var pressedKeyCodes: Set<UInt16> = []
    private(set) var suppressedMappedKeyCodes: Set<UInt16> = []

    mutating func update(
        keyCode: UInt16,
        eventFlagsRawValue: UInt64
    ) -> ShortcutKeyPhase {
        guard let modifierKey = PhysicalModifierKey(keyCode: keyCode) else { return .down }
        if pressedKeyCodes.remove(keyCode) != nil { return .up }
        if eventFlagsRawValue & modifierKey.eventFlagRawValue == 0 { return .up }
        pressedKeyCodes.insert(keyCode)
        return .down
    }

    mutating func setMappedKeySuppressed(_ suppressed: Bool, keyCode: UInt16) {
        if suppressed {
            suppressedMappedKeyCodes.insert(keyCode)
        } else {
            suppressedMappedKeyCodes.remove(keyCode)
        }
    }

    mutating func clearSuppressedMappings() {
        suppressedMappedKeyCodes.removeAll()
    }

    mutating func reset() {
        pressedKeyCodes.removeAll()
        suppressedMappedKeyCodes.removeAll()
    }

    var modifierFlagsToStripRawValue: UInt64 {
        var result: UInt64 = 0
        let groupedKeyCodes = Dictionary(grouping: PhysicalModifierKey.allCases, by: \.eventFlagRawValue)
        for (flag, keys) in groupedKeyCodes {
            let heldKeyCodes = Set(keys.map(\.rawValue)).intersection(pressedKeyCodes)
            guard !heldKeyCodes.isEmpty,
                  heldKeyCodes.isSubset(of: suppressedMappedKeyCodes) else { continue }
            result |= flag
        }
        return result
    }
}

enum ShortcutKeyPhase: Sendable {
    case down
    case up
}

enum DirectKeyEventOutcome: Equatable, Sendable {
    case passThrough
    case suppress
    case trigger(ShortcutTarget)
    case release(ShortcutTarget)
}

struct DirectKeyEventMatcher: Sendable {
    private struct SuppressedKey: Sendable {
        let target: ShortcutTarget
        let didTrigger: Bool
    }

    private var suppressedKeysByKeyCode: [UInt16: SuppressedKey] = [:]

    mutating func handle(
        keyCode: UInt16,
        modifiers _: ShortcutModifiers,
        phase: ShortcutKeyPhase,
        isRepeat: Bool,
        isSynthetic: Bool,
        targetsByKeyCode: [UInt16: ShortcutTarget]
    ) -> DirectKeyEventOutcome {
        guard !isSynthetic else { return .passThrough }

        switch phase {
        case .up:
            guard let suppressedKey = suppressedKeysByKeyCode.removeValue(forKey: keyCode) else {
                return .passThrough
            }
            return suppressedKey.didTrigger ? .release(suppressedKey.target) : .suppress
        case .down:
            if isRepeat {
                if suppressedKeysByKeyCode[keyCode] != nil { return .suppress }
                guard let target = targetsByKeyCode[keyCode] else {
                    return .passThrough
                }
                suppressedKeysByKeyCode[keyCode] = SuppressedKey(target: target, didTrigger: false)
                return .suppress
            }
            guard let target = targetsByKeyCode[keyCode] else {
                suppressedKeysByKeyCode.removeValue(forKey: keyCode)
                return .passThrough
            }
            suppressedKeysByKeyCode[keyCode] = SuppressedKey(target: target, didTrigger: true)
            return .trigger(target)
        }
    }

    mutating func drainTargets() -> Set<ShortcutTarget> {
        let targets = Set(suppressedKeysByKeyCode.values.compactMap { key in
            key.didTrigger ? key.target : nil
        })
        suppressedKeysByKeyCode.removeAll()
        return targets
    }
}

struct CombinationKeyEventMatcher: Sendable {
    private var pressedTargetsByKeyCode: [UInt16: ShortcutTarget] = [:]

    mutating func handle(
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        phase: ShortcutKeyPhase,
        isRepeat: Bool,
        isSynthetic: Bool,
        targetsByGesture: [ShortcutGesture: ShortcutTarget]
    ) -> DirectKeyEventOutcome {
        guard !isSynthetic else { return .passThrough }

        switch phase {
        case .up:
            guard let target = pressedTargetsByKeyCode.removeValue(forKey: keyCode) else {
                return .passThrough
            }
            return .release(target)
        case .down:
            if pressedTargetsByKeyCode[keyCode] != nil { return .suppress }
            guard !modifiers.isEmpty,
                  let target = targetsByGesture[
                    ShortcutGesture(keyCode: keyCode, modifiers: modifiers)
                  ] else {
                return .passThrough
            }
            pressedTargetsByKeyCode[keyCode] = target
            return isRepeat ? .suppress : .trigger(target)
        }
    }

    mutating func drainTargets() -> Set<ShortcutTarget> {
        let targets = Set(pressedTargetsByKeyCode.values)
        pressedTargetsByKeyCode.removeAll()
        return targets
    }
}

enum ShortcutDefaults {
    static let currentVersion = 5

    static let legacyQuickLaunchBinding = KeyboardShortcutBinding(
        keyCode: 49,
        modifiers: .control,
        keyLabel: "Space"
    )

    static let bindings: [ShortcutTarget: KeyboardShortcutBinding] = [
        .quickLaunch: KeyboardShortcutBinding(
            keyCode: 49,
            modifiers: .option,
            keyLabel: "Space"
        ),
        .radialMenu: KeyboardShortcutBinding(
            keyCode: 6,
            modifiers: .control,
            keyLabel: "Z"
        ),
        .togglePanelPosition: control(keyCode: 35, label: "P"),
        .fast: control(keyCode: 3, label: "F"),
        .approve: control(keyCode: 33, label: "["),
        .decline: control(keyCode: 30, label: "]"),
        .reasoningDown: control(keyCode: 27, label: "-"),
        .reasoningUp: control(keyCode: 24, label: "="),
        .newTask: control(keyCode: 45, label: "N"),
        .voice: control(keyCode: 2, label: "D", additionalModifiers: .shift),
        .toggleLabels: control(keyCode: 4, label: "H"),
        .codexStatus: control(keyCode: 8, label: "C"),
        .joystickUp: control(keyCode: 13, label: "W"),
        .joystickDown: control(keyCode: 1, label: "S"),
        .joystickLeft: control(keyCode: 0, label: "A"),
        .joystickRight: control(keyCode: 2, label: "D"),
        .agent1: control(keyCode: 18, label: "1"),
        .agent2: control(keyCode: 19, label: "2"),
        .agent3: control(keyCode: 20, label: "3"),
        .agent4: control(keyCode: 21, label: "4"),
        .agent5: control(keyCode: 23, label: "5"),
        .agent6: control(keyCode: 22, label: "6")
    ]

    static func merging(into existing: [ShortcutTarget: KeyboardShortcutBinding]) -> [ShortcutTarget: KeyboardShortcutBinding] {
        bindings.merging(existing) { _, userBinding in userBinding }
    }

    private static func control(
        keyCode: UInt16,
        label: String,
        additionalModifiers: ShortcutModifiers = []
    ) -> KeyboardShortcutBinding {
        KeyboardShortcutBinding(
            keyCode: keyCode,
            modifiers: [.control, additionalModifiers],
            keyLabel: label
        )
    }
}

enum ShortcutTarget: String, CaseIterable, Codable, Hashable, Sendable {
    case quickLaunch
    case radialMenu
    case togglePanelPosition
    case agent1, agent2, agent3, agent4, agent5, agent6
    case joystickUp, joystickRight, joystickDown, joystickLeft
    case fast, approve, decline, newTask
    case toggleLabels, voice, codexStatus
    case reasoningDown, reasoningUp

    static func agent(at index: Int) -> ShortcutTarget? {
        let targets: [ShortcutTarget] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6]
        return targets.indices.contains(index) ? targets[index] : nil
    }

    static var configurablePadCases: [ShortcutTarget] {
        allCases.filter { $0 != .quickLaunch && $0 != .radialMenu && $0 != .togglePanelPosition }
    }

    var title: String {
        switch self {
        case .quickLaunch: "快速启动"
        case .radialMenu: "轮盘"
        case .togglePanelPosition: "切换悬浮位置"
        case .agent1: "A1"
        case .agent2: "A2"
        case .agent3: "A3"
        case .agent4: "A4"
        case .agent5: "A5"
        case .agent6: "A6"
        case .joystickUp: "摇杆上 · 计划模式"
        case .joystickRight: "摇杆右 · 下一个任务"
        case .joystickDown: "摇杆下 · 目标模式"
        case .joystickLeft: "摇杆左 · 上一个任务"
        case .fast: "FAST"
        case .approve: "同意"
        case .decline: "拒绝"
        case .newTask: "新任务"
        case .toggleLabels: "显示 / 隐藏标注"
        case .voice: "语音听写"
        case .codexStatus: "Codex 状态"
        case .reasoningDown: "降低推理强度"
        case .reasoningUp: "提高推理强度"
        }
    }
}

enum ShortcutEventMarker {
    /// Synthetic key events sent to Codex must never re-trigger CodeXMicro shortcuts.
    static let codexAutomation: Int64 = 0x434F_4445_584D_4943
}
