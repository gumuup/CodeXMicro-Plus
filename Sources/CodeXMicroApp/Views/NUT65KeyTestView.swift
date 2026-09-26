import AppKit
import SwiftUI

/// A focus-only tester. It neither records globally nor synthesizes a key event.
struct NUT65KeyTestView: NSViewRepresentable {
    let onKey: (UInt16, String) -> Void
    func makeNSView(context: Context) -> KeyTestSurface { KeyTestSurface(onKey: onKey) }
    func updateNSView(_ nsView: KeyTestSurface, context: Context) { nsView.onKey = onKey }

    final class KeyTestSurface: NSView {
        var onKey: (UInt16, String) -> Void
        init(onKey: @escaping (UInt16, String) -> Void) {
            self.onKey = onKey
            super.init(frame: .zero)
            setAccessibilityRole(.button)
            setAccessibilityLabel("按键实测区，点击后按 NUT65 的实体按键")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
        override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
        override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
        override func keyDown(with event: NSEvent) {
            onKey(event.keyCode, event.charactersIgnoringModifiers ?? "")
        }
        override func keyUp(with event: NSEvent) {}
        override func draw(_ dirtyRect: NSRect) {
            let focused = window?.firstResponder === self
            let text = focused ? "现在按键盘实体键（点击其他区域退出）" : "点击这里，再按键盘实体键"
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (text as NSString).draw(in: bounds.insetBy(dx: 8, dy: 10), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: focused ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ])
        }
    }
}
