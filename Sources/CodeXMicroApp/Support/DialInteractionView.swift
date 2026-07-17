import AppKit
import SwiftUI

struct DialInteractionView: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> DialEventView {
        let view = DialEventView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: DialEventView, context: Context) {
        nsView.onStep = onStep
    }
}

final class DialEventView: NSView {
    var onStep: ((Int) -> Void)?
    private var mouseOrigin = NSPoint.zero
    private var lastDragStep = 0
    private var scrollAccumulator: CGFloat = 0
    private let ignoreScrollUntil = Date().addingTimeInterval(0.8)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseOrigin = convert(event.locationInWindow, from: nil)
        lastDragStep = 0
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let step = Int((point.y - mouseOrigin.y) / 18)
        guard step != lastDragStep else { return }
        for direction in DialStepResolver.dragSteps(from: lastDragStep, to: step) {
            onStep?(direction)
        }
        lastDragStep = step
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - mouseOrigin.x, point.y - mouseOrigin.y) < 4 {
            onStep?(DialStepResolver.tapStep(at: point.x, width: bounds.width))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard Date() >= ignoreScrollUntil, event.momentumPhase.isEmpty else { return }
        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        guard abs(scrollAccumulator) >= threshold else { return }
        onStep?(scrollAccumulator > 0 ? 1 : -1)
        scrollAccumulator = 0
    }

    override func accessibilityPerformIncrement() -> Bool {
        onStep?(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onStep?(-1)
        return true
    }
}
