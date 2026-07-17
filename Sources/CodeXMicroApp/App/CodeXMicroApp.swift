import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        store.start()
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
        panel.level = .floating
        panel.isFloatingPanel = true
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
