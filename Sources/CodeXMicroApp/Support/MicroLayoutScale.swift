import SwiftUI

private struct MicroLayoutScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var microLayoutScale: CGFloat {
        get { self[MicroLayoutScaleKey.self] }
        set { self[MicroLayoutScaleKey.self] = newValue }
    }
}
