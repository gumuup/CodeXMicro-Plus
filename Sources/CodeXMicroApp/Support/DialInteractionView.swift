import AppKit
import SwiftUI

struct DialInteractionView: NSViewRepresentable {
    let onStep: (Int) -> Void
    let shortcutName: (Int) -> String?
    let onConfigureShortcut: (Int) -> Void
    let onClearShortcut: (Int) -> Void

    func makeNSView(context: Context) -> DialEventView {
        let view = DialEventView()
        view.onStep = onStep
        view.shortcutName = shortcutName
        view.onConfigureShortcut = onConfigureShortcut
        view.onClearShortcut = onClearShortcut
        return view
    }

    func updateNSView(_ nsView: DialEventView, context: Context) {
        nsView.onStep = onStep
        nsView.shortcutName = shortcutName
        nsView.onConfigureShortcut = onConfigureShortcut
        nsView.onClearShortcut = onClearShortcut
    }
}

final class DialEventView: NSView {
    var onStep: ((Int) -> Void)?
    var shortcutName: ((Int) -> String?)?
    var onConfigureShortcut: ((Int) -> Void)?
    var onClearShortcut: ((Int) -> Void)?
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

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let step = DialStepResolver.tapStep(at: point.x, width: bounds.width)
        NSMenu.popUpContextMenu(shortcutMenu(for: step), with: event, for: self)
    }

    func shortcutMenu(for step: Int) -> NSMenu {
        let actionTitle = step < 0 ? "降低推理强度" : "提高推理强度"
        let menu = NSMenu()
        menu.autoenablesItems = false

        let configureItem = NSMenuItem(
            title: "设置\(actionTitle)快捷键…",
            action: #selector(configureShortcut(_:)),
            keyEquivalent: ""
        )
        configureItem.target = self
        configureItem.representedObject = step
        configureItem.isEnabled = true
        menu.addItem(configureItem)

        if let currentShortcut = shortcutName?(step) {
            menu.addItem(.separator())

            let currentItem = NSMenuItem(title: "当前：\(currentShortcut)", action: nil, keyEquivalent: "")
            currentItem.isEnabled = false
            menu.addItem(currentItem)

            let clearItem = NSMenuItem(
                title: "清除\(actionTitle)快捷键",
                action: #selector(clearShortcut(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            clearItem.representedObject = step
            clearItem.isEnabled = true
            menu.addItem(clearItem)
        }

        return menu
    }

    @objc private func configureShortcut(_ sender: NSMenuItem) {
        guard let step = sender.representedObject as? Int else { return }
        onConfigureShortcut?(step)
    }

    @objc private func clearShortcut(_ sender: NSMenuItem) {
        guard let step = sender.representedObject as? Int else { return }
        onClearShortcut?(step)
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
