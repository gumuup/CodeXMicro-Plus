import AppKit
import Combine
import SwiftUI

final class FloatingPanel: NSPanel {
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparentBacking()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparentBacking()
    }

    private func configureTransparentBacking() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = CodexStore()
    private var panel: FloatingPanel?
    private var panelPositionCancellable: AnyCancellable?
    private var shortcutRecordingCancellable: AnyCancellable?
    private var applicationActiveBeforeRecording: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        panelPositionCancellable = store.$panelPosition
            .removeDuplicates()
            .sink { [weak self] position in
                self?.applyPanelPosition(position)
            }
        shortcutRecordingCancellable = store.$shortcutRecordingTarget
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isRecording in
                self?.setShortcutRecordingFocus(isRecording)
            }
        store.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func showPanel() {
        panel?.orderFrontRegardless()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func togglePanel() {
        panel?.isVisible == true ? hidePanel() : showPanel()
    }

    private func createPanel() {
        let size = NSSize(width: 438, height: 438)
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        configurePanelLevel(panel, for: store.panelPosition)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.contentAspectRatio = NSSize(width: 1, height: 1)
        panel.contentMinSize = NSSize(width: 300, height: 300)
        panel.contentMaxSize = NSSize(width: 700, height: 700)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameAutosaveName("CodexMicroFloatingPanel")
        let hostingView = TransparentHostingView(rootView: MicroPadView(store: store) { [weak self] in self?.hidePanel() })
        panel.contentView = hostingView

        if !panel.setFrameUsingName("CodexMicroFloatingPanel"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func applyPanelPosition(_ position: PanelPosition) {
        guard let panel else { return }
        let wasVisible = panel.isVisible
        configurePanelLevel(panel, for: position)
        if wasVisible {
            panel.orderFrontRegardless()
        }
    }

    private func setShortcutRecordingFocus(_ isRecording: Bool) {
        guard let panel else { return }
        if isRecording {
            let frontmost = NSWorkspace.shared.frontmostApplication
            applicationActiveBeforeRecording = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil
                : frontmost
            panel.allowsKeyFocus = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        panel.allowsKeyFocus = false
        panel.resignKey()
        panel.orderFrontRegardless()
        let previousApplication = applicationActiveBeforeRecording
        applicationActiveBeforeRecording = nil
        Task { @MainActor in
            await Task.yield()
            if let previousApplication, !previousApplication.isTerminated {
                previousApplication.activate(options: [.activateAllWindows])
            } else {
                NSApp.deactivate()
            }
        }
    }

    private func configurePanelLevel(_ panel: FloatingPanel, for position: PanelPosition) {
        switch position {
        case .top:
            panel.isFloatingPanel = true
            panel.level = .floating
        case .bottom:
            panel.isFloatingPanel = false
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
            panel.level = NSWindow.Level(rawValue: desktopLevel)
        }
    }
}

@main
struct CodeXMicroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("CodeXMicro++", systemImage: "keyboard.badge.ellipsis") {
            Button(appDelegate.panelIsVisible ? "隐藏悬浮键盘" : "显示悬浮键盘") {
                appDelegate.togglePanel()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            Divider()
            SettingsLink { Text("设置…") }
            Divider()
            Button("退出 CodeXMicro++") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}

private extension AppDelegate {
    var panelIsVisible: Bool { panel?.isVisible == true }
}
