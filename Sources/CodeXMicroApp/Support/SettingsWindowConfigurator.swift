import AppKit
import SwiftUI

/// SwiftUI 的 Settings Scene 不公开完整窗口样式；这个零尺寸探针只负责恢复标准 NSWindow 行为。
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowProbeView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SettingsWindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in
            // Settings Scene 会先挂载内容视图，再在后续主循环关联宿主窗口。
            // 等待关联完成后再补齐标准窗口样式和三色交通灯。
            for _ in 0..<4 {
                await Task.yield()
                if let window = self?.window {
                    window.level = .normal
                    window.hidesOnDeactivate = false
                    window.collectionBehavior.remove(.fullScreenAuxiliary)
                    window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
                    window.contentMinSize = NSSize(width: 780, height: 680)

                    for buttonType in [
                        NSWindow.ButtonType.closeButton,
                        .miniaturizeButton,
                        .zoomButton,
                    ] {
                        window.standardWindowButton(buttonType)?.isHidden = false
                        window.standardWindowButton(buttonType)?.isEnabled = true
                    }
                    return
                }
            }
        }
    }
}
