import AppKit

@MainActor
final class HapticService {
    private lazy var keySound = NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)

    func press(strength: HapticStrength, soundEnabled: Bool) {
        guard strength != .off else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = strength == .subtle ? .alignment : .generic
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        if soundEnabled {
            keySound?.stop()
            keySound?.volume = strength == .strong ? 0.48 : strength == .standard ? 0.32 : 0.18
            keySound?.play()
        }
    }

    func detent(strength: HapticStrength) {
        guard strength != .off else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func joystickDetent(strength: HapticStrength) {
        guard strength != .off else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = strength == .strong ? .generic : .alignment
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func radialReveal(strength: HapticStrength) {
        guard strength != .off else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func radialSelectionDetent(strength: HapticStrength) {
        guard strength != .off else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = strength == .strong ? .levelChange : .alignment
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func radialConfirmation(strength: HapticStrength, soundEnabled: Bool) {
        guard strength != .off else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        if soundEnabled {
            keySound?.stop()
            keySound?.volume = strength == .strong ? 0.48 : strength == .standard ? 0.32 : 0.18
            keySound?.play()
        }
    }
}
