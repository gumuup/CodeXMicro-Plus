import AppKit
import SwiftUI

@MainActor
final class ClipboardSidebarPanelController {
    private let history: ClipboardHistoryStore
    private let panel: FloatingPanel
    private var previousApplication: NSRunningApplication?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(history: ClipboardHistoryStore) {
        self.history = history
        self.panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 350, height: 720)),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.allowsKeyFocus = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = TransparentHostingView(
            rootView: ClipboardSidebarView(
                history: history,
                onSelect: { [weak self] item in self?.select(item) },
                onDismiss: { [weak self] in self?.hide(restorePreviousApplication: true) }
            )
        )
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        panel.isVisible ? hide(restorePreviousApplication: true) : show()
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        positionOnCurrentScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide(restorePreviousApplication: Bool) {
        panel.orderOut(nil)
        removeDismissMonitors()
        guard restorePreviousApplication else {
            previousApplication = nil
            return
        }
        activatePreviousApplication()
    }

    private func select(_ item: ClipboardHistoryItem) {
        guard history.restore(item) else { return }
        panel.orderOut(nil)
        removeDismissMonitors()
        let application = previousApplication
        previousApplication = nil
        Task { @MainActor in
            if let application, !application.isTerminated {
                application.activate(options: [.activateAllWindows])
            }
            try? await Task.sleep(for: .milliseconds(120))
            sendPasteShortcut()
        }
    }

    private func positionOnCurrentScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width: CGFloat = min(350, visible.width - 24)
        let height: CGFloat = min(760, visible.height - 24)
        panel.setFrame(
            NSRect(x: visible.maxX - width - 12, y: visible.midY - height / 2, width: width, height: height),
            display: true
        )
    }

    private func installDismissMonitors() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide(restorePreviousApplication: false)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel {
                self.hide(restorePreviousApplication: false)
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func activatePreviousApplication() {
        let application = previousApplication
        previousApplication = nil
        if let application, !application.isTerminated {
            application.activate(options: [.activateAllWindows])
        } else {
            NSApp.deactivate()
        }
    }

    private func sendPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        up?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
