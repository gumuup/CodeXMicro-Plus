import Foundation

enum AudioMeterScale {
    static func segments(_ amplitude: Float) -> Int {
        guard amplitude.isFinite, amplitude > 0.001 else { return 0 }
        let fraction = min(1, max(0, (20 * log10(amplitude) + 60) / 60))
        return Int(ceil(fraction * 12))
    }
    static func label(_ amplitude: Float) -> String {
        guard amplitude.isFinite, amplitude > 0.00001 else { return "−∞ dB" }
        return String(format: "%.0f dB", 20 * log10(amplitude)).replacingOccurrences(of: "-", with: "−")
    }
}
