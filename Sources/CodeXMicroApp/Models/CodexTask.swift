import Foundation
import SwiftUI

enum CodexTaskStatus: String, Codable, Sendable {
    case active
    case waiting
    case complete
    case error
    case idle

    var label: String {
        switch self {
        case .active: "运行中"
        case .waiting: "等待"
        case .complete: "完成"
        case .error: "异常"
        case .idle: "空闲"
        }
    }

    var color: Color {
        switch self {
        case .active: Color(red: 0.35, green: 0.52, blue: 1.0)
        case .waiting: Color(red: 1.0, green: 0.69, blue: 0.23)
        case .complete: Color(red: 0.25, green: 0.83, blue: 0.56)
        case .error: Color(red: 1.0, green: 0.31, blue: 0.42)
        case .idle: Color(red: 0.66, green: 0.69, blue: 0.75)
        }
    }
}

struct CodexTask: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let cwd: String
    let rolloutPath: String
    let updatedAt: Int64
    let status: CodexTaskStatus

    var shortTitle: String {
        let cleaned = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.isEmpty ? "未命名任务" : cleaned
    }
}

enum CodexTaskNavigator {
    static func targetIndex(
        taskIDs: [String],
        currentTaskID: String?,
        direction: JoystickDirection
    ) -> Int? {
        guard !taskIDs.isEmpty else { return nil }
        let currentIndex = currentTaskID.flatMap(taskIDs.firstIndex(of:)) ?? 0
        switch direction {
        case .left:
            return (currentIndex - 1 + taskIDs.count) % taskIDs.count
        case .right:
            return (currentIndex + 1) % taskIDs.count
        case .up, .down:
            return nil
        }
    }
}
