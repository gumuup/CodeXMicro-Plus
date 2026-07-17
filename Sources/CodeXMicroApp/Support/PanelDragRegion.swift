import AppKit
import SwiftUI

struct PanelDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelDragRegionView {
        let view = PanelDragRegionView()
        view.toolTip = "拖动悬浮键盘"
        return view
    }

    func updateNSView(_ nsView: PanelDragRegionView, context: Context) {}
}

final class PanelDragRegionView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
