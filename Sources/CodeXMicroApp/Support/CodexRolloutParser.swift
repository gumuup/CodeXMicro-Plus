import Foundation

enum CodexRolloutParser {
    static func status(from data: Data, seenAt: Int64) -> CodexTaskStatus {
        var started: Int64 = 0
        var completed: Int64 = 0
        var aborted: Int64 = 0
        var errored: Int64 = 0
        var waiting: Int64 = 0

        for rawLine in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any] else { continue }
            let timestamp = parseTimestamp(object["timestamp"] as? String)
            let payload = object["payload"] as? [String: Any] ?? [:]
            let entryType = object["type"] as? String
            let eventType = payload["type"] as? String

            if entryType == "event_msg" || eventType != nil {
                switch eventType {
                case "task_started": started = max(started, timestamp)
                case "task_complete": completed = max(completed, timestamp)
                case "turn_aborted": aborted = max(aborted, timestamp)
                case "error", "stream_error": errored = max(errored, timestamp)
                default: break
                }
            }

            let call = payload["call"] as? [String: Any]
            let name = (payload["name"] as? String) ?? (call?["name"] as? String) ?? ""
            let explicitlyWaiting = (payload["waitingOnUserInput"] as? Bool == true)
                || (payload["waitingOnApproval"] as? Bool == true)
                || (payload["waiting_on_user_input"] as? Bool == true)
                || (payload["waiting_on_approval"] as? Bool == true)
            if name.range(of: "request_user_input", options: .caseInsensitive) != nil
                || name.range(of: "approval", options: .caseInsensitive) != nil
                || explicitlyWaiting {
                waiting = max(waiting, timestamp)
            }
        }

        if started > max(completed, aborted, errored) {
            return waiting > started ? .waiting : .active
        }
        if max(aborted, errored) > completed { return .error }
        if completed > 0 && seenAt < completed { return .complete }
        return .idle
    }

    static func reasoningLevel(from data: Data) -> ReasoningLevel? {
        var latest: ReasoningLevel?
        for rawLine in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            let settings = payload["thread_settings"] as? [String: Any]
            if let value = settings?["reasoning_effort"] as? String,
               let level = ReasoningLevel(rawValue: value) {
                latest = level
            }
        }
        return latest
    }

    static func weeklyQuota(from data: Data) -> WeeklyQuota? {
        var latest: WeeklyQuota?
        for rawLine in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any],
                  (rateLimits["limit_id"] as? String).map({ $0 == "codex" }) ?? true,
                  let primary = rateLimits["primary"] as? [String: Any],
                  let windowMinutes = number(primary["window_minutes"]),
                  Int(windowMinutes) == 10_080,
                  let usedPercent = number(primary["used_percent"]) else { continue }

            let observedAt = parseTimestamp(object["timestamp"] as? String)
            let resetSeconds = number(primary["resets_at"])
            let quota = WeeklyQuota(
                usedPercent: usedPercent,
                resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
                observedAt: observedAt
            )
            if latest == nil || observedAt >= latest!.observedAt { latest = quota }
        }
        return latest
    }

    static func liveWeeklyQuota(from data: Data, observedAt: Date = Date()) -> WeeklyQuota? {
        for rawLine in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  number(object["id"]) == 2,
                  let result = object["result"] as? [String: Any] else { continue }

            let byLimitID = result["rateLimitsByLimitId"] as? [String: Any]
            let snapshot = (byLimitID?["codex"] as? [String: Any])
                ?? (result["rateLimits"] as? [String: Any])
            guard let snapshot,
                  let primary = snapshot["primary"] as? [String: Any],
                  let windowMinutes = number(primary["windowDurationMins"]),
                  Int(windowMinutes) == 10_080,
                  let usedPercent = number(primary["usedPercent"]) else { continue }

            let resetSeconds = number(primary["resetsAt"])
            return WeeklyQuota(
                usedPercent: usedPercent,
                resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
                observedAt: Int64(observedAt.timeIntervalSince1970 * 1_000)
            )
        }
        return nil
    }

    static func liveLifetimeTokens(from data: Data) -> Int64? {
        for rawLine in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  number(object["id"]) == 3,
                  let result = object["result"] as? [String: Any],
                  let summary = result["summary"] as? [String: Any],
                  let tokens = number(summary["lifetimeTokens"]) else { continue }
            return Int64(tokens)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func parseTimestamp(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return Int64((date?.timeIntervalSince1970 ?? 0) * 1_000)
    }
}
