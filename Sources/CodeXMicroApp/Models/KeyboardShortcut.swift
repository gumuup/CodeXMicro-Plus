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
}

enum ShortcutDefaults {
    static let currentVersion = 1

    static let bindings: [ShortcutTarget: KeyboardShortcutBinding] = [
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
    case agent1, agent2, agent3, agent4, agent5, agent6
    case joystickUp, joystickRight, joystickDown, joystickLeft
    case fast, approve, decline, newTask
    case toggleLabels, voice, codexStatus
    case reasoningDown, reasoningUp

    static func agent(at index: Int) -> ShortcutTarget? {
        let targets: [ShortcutTarget] = [.agent1, .agent2, .agent3, .agent4, .agent5, .agent6]
        return targets.indices.contains(index) ? targets[index] : nil
    }

    var title: String {
        switch self {
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
