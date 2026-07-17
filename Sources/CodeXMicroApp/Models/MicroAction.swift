import Foundation

enum MicroAction: String, CaseIterable, Sendable {
    case fast
    case approve
    case decline
    case newTask
    case send
    case plan
    case goal
    case fork
    case openCodex
    case reasoningUp
    case reasoningDown

    var accessibilityLabel: String {
        switch self {
        case .fast: "切换 Fast 模式"
        case .approve: "同意或确认"
        case .decline: "拒绝或取消"
        case .newTask: "新任务"
        case .send: "发送"
        case .plan: "切换 Plan 模式"
        case .goal: "开启目标模式"
        case .fork: "分叉任务"
        case .openCodex: "打开 Codex"
        case .reasoningUp: "提高推理强度"
        case .reasoningDown: "降低推理强度"
        }
    }
}

enum ReasoningLevel: String, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh

    var label: String {
        switch self {
        case .low: "轻度"
        case .medium: "中"
        case .high: "高"
        case .xhigh: "极高"
        }
    }

    /// The dial marker uses the four cardinal directions as fixed detents.
    var dialAngleDegrees: Double {
        switch self {
        case .low: -90
        case .medium: 0
        case .high: 90
        case .xhigh: 180
        }
    }

    func stepped(by delta: Int) -> ReasoningLevel {
        let levels = Self.allCases
        let current = levels.firstIndex(of: self) ?? 1
        return levels[min(max(current + delta, 0), levels.count - 1)]
    }
}

enum JoystickDirection: String, Sendable {
    case up
    case right
    case down
    case left

    var title: String {
        switch self {
        case .up: "计划模式"
        case .right: "下一个任务"
        case .down: "目标模式"
        case .left: "上一个任务"
        }
    }
}

enum HapticStrength: String, CaseIterable, Identifiable {
    case off
    case subtle
    case standard
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "关闭"
        case .subtle: "轻"
        case .standard: "标准"
        case .strong: "强"
        }
    }
}
