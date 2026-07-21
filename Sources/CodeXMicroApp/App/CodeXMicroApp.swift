import AppKit
import Combine
import OSLog
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
    private static let logger = Logger(
        subsystem: "com.gumu.codexmicro.virtual",
        category: "application"
    )

    let store = CodexStore()
    private var panel: FloatingPanel?
    private var radialMenuController: RadialMenuPanelController?
    private var panelPositionCancellable: AnyCancellable?
    private var shortcutRecordingCancellable: AnyCancellable?
    private var startupTask: Task<Void, Never>?
    private var applicationActiveBeforeRecording: NSRunningApplication?
    private var didTakePanelFocusForShortcutRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        radialMenuController = RadialMenuPanelController(store: store)
        store.quickLaunchHandler = { [weak self] in
            self?.togglePanel()
        }
        store.radialMenuHandler = { [weak self] in
            self?.radialMenuController?.hotKeyPressed()
        }
        store.radialMenuReleaseHandler = { [weak self] in
            self?.radialMenuController?.hotKeyReleased()
        }
        store.radialMenuPreviewHandler = { [weak self] items in
            self?.radialMenuController?.toggleFromMenuBar(previewItems: items)
        }
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
        startAfterRetiringDuplicateInstances()
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
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

    func toggleRadialMenu() {
        radialMenuController?.toggleFromMenuBar()
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

    private func startAfterRetiringDuplicateInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            store.start()
            return
        }

        let duplicateInstances = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID && $0.bundleIdentifier == bundleIdentifier
        }
        guard !duplicateInstances.isEmpty else {
            store.start()
            return
        }

        for application in duplicateInstances {
            Self.logger.notice(
                "Retiring duplicate instance pid=\(application.processIdentifier, privacy: .public)"
            )
            _ = application.terminate()
        }

        startupTask = Task { @MainActor [weak self] in
            // Two active event taps would execute every mapping twice. Give the
            // previous instance a brief graceful-termination window.
            for _ in 0..<12 {
                guard !Task.isCancelled else { return }
                if duplicateInstances.allSatisfy(\.isTerminated) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }

            for application in duplicateInstances where !application.isTerminated {
                Self.logger.warning(
                    "Force retiring duplicate instance pid=\(application.processIdentifier, privacy: .public)"
                )
                _ = application.forceTerminate()
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.store.start()
        }
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
            let isConfiguringInSettings = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                && NSApp.keyWindow != nil
                && NSApp.keyWindow !== panel
            if isConfiguringInSettings {
                didTakePanelFocusForShortcutRecording = false
                applicationActiveBeforeRecording = nil
                return
            }

            didTakePanelFocusForShortcutRecording = true
            applicationActiveBeforeRecording = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil
                : frontmost
            panel.allowsKeyFocus = true
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        guard didTakePanelFocusForShortcutRecording else { return }
        didTakePanelFocusForShortcutRecording = false
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
            let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
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
            Button("显示快速启动轮盘") {
                appDelegate.toggleRadialMenu()
            }
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
