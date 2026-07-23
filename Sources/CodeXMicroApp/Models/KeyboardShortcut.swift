import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

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

    init(eventFlagsRawValue: UInt64) {
        var value: ShortcutModifiers = []
        if eventFlagsRawValue & (1 << 20) != 0 { value.insert(.command) }
        if eventFlagsRawValue & (1 << 18) != 0 { value.insert(.control) }
        if eventFlagsRawValue & (1 << 19) != 0 { value.insert(.option) }
        if eventFlagsRawValue & (1 << 17) != 0 { value.insert(.shift) }
        self = value
    }
}

struct KeyboardShortcutBinding: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let keyLabel: String
    let mouseButton: UInt32?
    let hidButton: HIDButtonIdentifier?

    init(
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        keyLabel: String,
        mouseButton: UInt32? = nil,
        hidButton: HIDButtonIdentifier? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
        self.mouseButton = mouseButton
        self.hidButton = hidButton
    }

    static func mouse(button: UInt32, modifiers: ShortcutModifiers) -> KeyboardShortcutBinding {
        KeyboardShortcutBinding(
            keyCode: 0,
            modifiers: modifiers,
            keyLabel: MouseButtonCatalog.label(for: button),
            mouseButton: button
        )
    }

    static func hidButton(
        _ button: HIDButtonIdentifier,
        modifiers: ShortcutModifiers
    ) -> KeyboardShortcutBinding {
        KeyboardShortcutBinding(
            keyCode: 0,
            modifiers: modifiers,
            keyLabel: button.displayName,
            hidButton: button
        )
    }

    var displayName: String { modifiers.glyphs + keyLabel }
    var isMouse: Bool { mouseButton != nil || hidButton != nil }
    var isHIDButton: Bool { hidButton != nil }
    var isUnsafeUnmodifiedPrimaryMouseButton: Bool {
        guard modifiers.isEmpty else { return false }
        if mouseButton == 0 || mouseButton == 1 { return true }
        return hidButton?.isPrimaryMouseButton == true
    }
    var activationMode: ShortcutActivationMode {
        if isHIDButton { return .hidButton }
        if isMouse { return .mouseButton }
        return modifiers.isEmpty ? .directKey : .registeredHotKey
    }
    var gesture: ShortcutGesture {
        if let hidButton {
            return ShortcutGesture(hidButton: hidButton, modifiers: modifiers)
        }
        if let mouseButton {
            return ShortcutGesture(mouseButton: mouseButton, modifiers: modifiers)
        }
        return ShortcutGesture(keyCode: keyCode, modifiers: modifiers)
    }
}

struct ShortcutGesture: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
    let mouseButton: UInt32?
    let hidButton: HIDButtonIdentifier?

    init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.mouseButton = nil
        self.hidButton = nil
    }

    init(mouseButton: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = 0
        self.modifiers = modifiers
        self.mouseButton = mouseButton
        self.hidButton = nil
    }

    init(hidButton: HIDButtonIdentifier, modifiers: ShortcutModifiers) {
        self.keyCode = 0
        self.modifiers = modifiers
        self.mouseButton = nil
        self.hidButton = hidButton
    }
}

struct HIDButtonIdentifier: Codable, Sendable {
    static let genericDesktopUsagePage: UInt32 = 0x01
    static let buttonUsagePage: UInt32 = 0x09
    static let consumerUsagePage: UInt32 = 0x0C
    static let mouseUsage: UInt32 = 0x02
    static let dialUsage: UInt32 = 0x37
    static let wheelUsage: UInt32 = 0x38

    let vendorID: Int
    let productID: Int
    let usagePage: UInt32
    let usage: UInt32
    let direction: Int8
    let deviceUsagePage: UInt32
    let deviceUsage: UInt32
    let deviceName: String

    init(
        vendorID: Int,
        productID: Int,
        usagePage: UInt32 = HIDButtonIdentifier.buttonUsagePage,
        usage: UInt32,
        direction: Int8 = 0,
        deviceUsagePage: UInt32 = HIDButtonIdentifier.genericDesktopUsagePage,
        deviceUsage: UInt32 = HIDButtonIdentifier.mouseUsage,
        deviceName: String
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.direction = direction
        self.deviceUsagePage = deviceUsagePage
        self.deviceUsage = deviceUsage
        self.deviceName = deviceName
    }

    private enum CodingKeys: String, CodingKey {
        case vendorID
        case productID
        case usagePage
        case usage
        case direction
        case deviceUsagePage
        case deviceUsage
        case deviceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try container.decode(Int.self, forKey: .vendorID)
        productID = try container.decode(Int.self, forKey: .productID)
        usagePage = try container.decodeIfPresent(UInt32.self, forKey: .usagePage)
            ?? Self.buttonUsagePage
        usage = try container.decode(UInt32.self, forKey: .usage)
        direction = try container.decodeIfPresent(Int8.self, forKey: .direction) ?? 0
        deviceUsagePage = try container.decodeIfPresent(UInt32.self, forKey: .deviceUsagePage)
            ?? Self.genericDesktopUsagePage
        deviceUsage = try container.decodeIfPresent(UInt32.self, forKey: .deviceUsage)
            ?? Self.mouseUsage
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
    }

    var isPrimaryMouseButton: Bool {
        usagePage == Self.buttonUsagePage
            && deviceUsagePage == Self.genericDesktopUsagePage
            && deviceUsage == Self.mouseUsage
            && usage <= 3
    }

    var isSafeRawCapture: Bool {
        !isPrimaryMouseButton
    }

    static func supportsRawElement(
        usagePage: UInt32,
        usage: UInt32,
        isRelative: Bool,
        logicalMinimum: Int,
        logicalMaximum: Int
    ) -> Bool {
        guard usage > 0 else { return false }
        if usagePage == buttonUsagePage {
            return true
        }
        let isBinaryControl = logicalMinimum == 0 && logicalMaximum == 1
        if usagePage == consumerUsagePage {
            return isRelative || isBinaryControl
        }
        if usagePage == genericDesktopUsagePage {
            return isRelative && (usage == dialUsage || usage == wheelUsage)
        }
        // Vendor pages frequently mix real controls with absolute axes and
        // device-status fields. Only these two shapes have safe key semantics.
        return usagePage >= 0xFF00 && (isRelative || isBinaryControl)
    }

    var displayName: String {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmedName.isEmpty ? "外接设备" : trimmedName
        return "\(prefix) · \(controlLabel)"
    }

    private var controlLabel: String {
        if direction != 0 {
            let directionLabel = direction > 0 ? "顺时针" : "逆时针"
            return "旋钮\(directionLabel)"
        }
        if usagePage == Self.consumerUsagePage {
            return switch usage {
            case 0xB5: "下一首"
            case 0xB6: "上一首"
            case 0xCD: "播放/暂停"
            case 0xE2: "静音"
            case 0xE9: "音量增加"
            case 0xEA: "音量降低"
            default: "媒体控制 \(usage)"
            }
        }
        if usagePage == Self.genericDesktopUsagePage,
           usage == Self.dialUsage || usage == Self.wheelUsage {
            return "旋钮"
        }
        return "宏键 \(usage)"
    }
}

extension HIDButtonIdentifier: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.vendorID == rhs.vendorID
            && lhs.productID == rhs.productID
            && lhs.usagePage == rhs.usagePage
            && lhs.usage == rhs.usage
            && lhs.direction == rhs.direction
            && lhs.deviceUsagePage == rhs.deviceUsagePage
            && lhs.deviceUsage == rhs.deviceUsage
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(vendorID)
        hasher.combine(productID)
        hasher.combine(usagePage)
        hasher.combine(usage)
        hasher.combine(direction)
        hasher.combine(deviceUsagePage)
        hasher.combine(deviceUsage)
    }
}

enum ShortcutActivationMode: String, Sendable {
    case directKey
    case registeredHotKey
    case mouseButton
    case hidButton

    var label: String {
        switch self {
        case .directKey: "物理按键映射 · 一级"
        case .registeredHotKey: "组合按键映射 · 一级监听"
        case .mouseButton: "鼠标按键映射 · 一级"
        case .hidButton: "原始 HID 宏键 · 一级监听"
        }
    }
}

enum MouseButtonCatalog {
    static func label(for button: UInt32) -> String {
        switch button {
        case 0: "鼠标左键"
        case 1: "鼠标右键"
        case 2: "鼠标中键"
        case 3: "鼠标侧键 1"
        case 4: "鼠标侧键 2"
        default: "鼠标按键 \(button + 1)"
        }
    }
}

enum SystemShortcutRegistry {
    private static let relevantModifierMask: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    static func contains(_ binding: KeyboardShortcutBinding) -> Bool {
        guard !binding.isMouse else { return false }
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let entries = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }
        return contains(binding, in: entries)
    }

    static func contains(_ binding: KeyboardShortcutBinding, in entries: [String: Any]) -> Bool {
        guard !binding.isMouse else { return false }
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

struct MouseButtonEventMatcher: Sendable {
    private var pressedTargetsByButton: [UInt32: ShortcutTarget] = [:]

    mutating func handle(
        button: UInt32,
        modifiers: ShortcutModifiers,
        phase: ShortcutKeyPhase,
        isSynthetic: Bool,
        targetsByGesture: [ShortcutGesture: ShortcutTarget]
    ) -> DirectKeyEventOutcome {
        guard !isSynthetic else { return .passThrough }

        switch phase {
        case .up:
            guard let target = pressedTargetsByButton.removeValue(forKey: button) else {
                return .passThrough
            }
            return .release(target)
        case .down:
            if pressedTargetsByButton[button] != nil { return .suppress }
            guard let target = targetsByGesture[
                ShortcutGesture(mouseButton: button, modifiers: modifiers)
            ] else {
                return .passThrough
            }
            pressedTargetsByButton[button] = target
            return .trigger(target)
        }
    }

    mutating func drainTargets() -> Set<ShortcutTarget> {
        let targets = Set(pressedTargetsByButton.values)
        pressedTargetsByButton.removeAll()
        return targets
    }
}

struct HIDButtonEventMatcher: Sendable {
    private var pressedTargetsByButton: [HIDButtonIdentifier: ShortcutTarget] = [:]

    mutating func handle(
        button: HIDButtonIdentifier,
        modifiers: ShortcutModifiers,
        phase: ShortcutKeyPhase,
        targetsByGesture: [ShortcutGesture: ShortcutTarget]
    ) -> DirectKeyEventOutcome {
        switch phase {
        case .up:
            guard let target = pressedTargetsByButton.removeValue(forKey: button) else {
                return .passThrough
            }
            return .release(target)
        case .down:
            if pressedTargetsByButton[button] != nil { return .suppress }
            guard let target = targetsByGesture[
                ShortcutGesture(hidButton: button, modifiers: modifiers)
            ] else {
                return .passThrough
            }
            pressedTargetsByButton[button] = target
            return .trigger(target)
        }
    }

    mutating func drainTargets() -> Set<ShortcutTarget> {
        let targets = Set(pressedTargetsByButton.values)
        pressedTargetsByButton.removeAll()
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
