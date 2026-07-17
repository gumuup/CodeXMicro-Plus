import Foundation

enum DialStepResolver {
    static func tapStep(at x: CGFloat, width: CGFloat) -> Int {
        x < width / 2 ? -1 : 1
    }

    static func dragSteps(from previous: Int, to current: Int) -> [Int] {
        guard previous != current else { return [] }
        return Array(repeating: current > previous ? 1 : -1, count: abs(current - previous))
    }
}
