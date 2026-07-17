import Foundation

enum CodexUsageMetric: String, Sendable {
    case weeklyRemaining
    case lifetimeConsumed

    mutating func toggle() {
        self = self == .weeklyRemaining ? .lifetimeConsumed : .weeklyRemaining
    }
}

struct CodexAccountMetrics: Sendable {
    let weeklyQuota: WeeklyQuota?
    let lifetimeTokens: Int64?
}

enum TokenCountFormatter {
    static func compact(_ tokens: Int64?) -> String {
        guard let tokens else { return "--" }
        let value = Double(max(tokens, 0))
        if value >= 100_000_000 { return oneDecimal(value / 100_000_000) + "亿" }
        if value >= 10_000 { return oneDecimal(value / 10_000) + "万" }
        return String(tokens)
    }

    static func full(_ tokens: Int64?) -> String {
        guard let tokens else { return "暂不可用" }
        return tokens.formatted(.number.grouping(.automatic))
    }

    private static func oneDecimal(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}
