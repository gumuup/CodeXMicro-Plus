import Foundation

struct WeeklyQuota: Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Int64

    var remainingPercent: Int {
        Int((100 - usedPercent).clamped(to: 0...100).rounded())
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
