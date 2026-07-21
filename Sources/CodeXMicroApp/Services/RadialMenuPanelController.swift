import AppKit
import SwiftUI

@MainActor
final class RadialMenuPanelController {
    private let store: CodexStore
    private let interaction = RadialMenuInteractionState()
    private let panel: FloatingPanel
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var isHotKeyHeld = false
    private var ignoresCurrentHotKeyRelease = false

    init(store: CodexStore) {
        self.store = store
        self.panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 430, height: 430)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel.contentView = TransparentHostingView(
            rootView: RadialMenuView(
                store: store,
                interaction: interaction,
                onSelect: { [weak self] item in self?.execute(item) },
                onDismiss: { [weak self] in self?.hide() }
            )
        )
    }

    var isVisible: Bool { panel.isVisible }

    func toggleFromMenuBar(previewItems: [RadialMenuItem]? = nil) {
        if panel.isVisible {
            hide()
        } else {
            isHotKeyHeld = false
            ignoresCurrentHotKeyRelease = false
            showAtPointer(items: previewItems ?? store.radialMenuItemsForFrontmostApplication())
        }
    }

    func hotKeyPressed() {
        if panel.isVisible, !isHotKeyHeld {
            ignoresCurrentHotKeyRelease = true
            hide()
            return
        }
        ignoresCurrentHotKeyRelease = false
        isHotKeyHeld = true
        showAtPointer(items: store.radialMenuItemsForFrontmostApplication())
    }

    func hotKeyReleased() {
        defer { isHotKeyHeld = false }
        guard !ignoresCurrentHotKeyRelease else {
            ignoresCurrentHotKeyRelease = false
            return
        }
        guard panel.isVisible,
              let id = interaction.selectedItemID,
              let item = interaction.items.first(where: { $0.id == id }) else {
            // A quick tap intentionally leaves the wheel open for click selection.
            return
        }
        execute(item)
    }

    func hide() {
        interaction.isPresented = false
        panel.orderOut(nil)
        interaction.selectedItemID = nil
        removeDismissMonitors()
    }

    private func showAtPointer(items: [RadialMenuItem]) {
        interaction.isPresented = false
        interaction.selectedItemID = nil
        interaction.items = items
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        let desired = NSPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2)
        let origin = NSPoint(
            x: min(max(desired.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
            y: min(max(desired.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        store.radialMenuAppeared()
        DispatchQueue.main.async { [weak self] in
            self?.interaction.isPresented = true
        }
        installDismissMonitors()
    }

    private func execute(_ item: RadialMenuItem) {
        hide()
        store.perform(item)
    }

    private func installDismissMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel { self.hide() }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeDismissMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}
