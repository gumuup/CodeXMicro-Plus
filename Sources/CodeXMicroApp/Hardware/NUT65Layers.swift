import Foundation

enum NUT65Layers {
    // Editing a VIA layer does not activate it. macOS cannot tell us the
    // keyboard's own Win/Mac mode; never infer a live layer from the host OS.
    static func initialLayer(saved: Int?, count: Int) -> Int {
        if let saved, (0..<count).contains(saved) { return saved }
        return count >= 4 ? 2 : 0
    }

    static func title(_ layer: Int, count: Int) -> String {
        guard count >= 4 else { return "层 \(layer)" }
        switch layer {
        case 0: return "层 0 · Win"
        case 1: return "层 1 · Win Fn"
        case 2: return "层 2 · Mac"
        case 3: return "层 3 · Mac Fn"
        default: return "层 \(layer)"
        }
    }
}
