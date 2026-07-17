import AppKit
import SwiftUI

enum PanelResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var cursor: NSCursor {
        let symbolName = switch self {
        case .topLeft, .bottomRight:
            "arrow.up.left.and.arrow.down.right"
        case .topRight, .bottomLeft:
            "arrow.up.right.and.arrow.down.left"
        }

        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "调整窗口大小"
        ) else {
            return .crosshair
        }

        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            symbol.draw(in: rect.insetBy(dx: 1, dy: 1))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 11, y: 11))
    }

    func sizeDelta(from start: NSPoint, to current: NSPoint) -> CGFloat {
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y

        return switch self {
        case .topLeft:
            (-deltaX + deltaY) / 2
        case .topRight:
            (deltaX + deltaY) / 2
        case .bottomLeft:
            (-deltaX - deltaY) / 2
        case .bottomRight:
            (deltaX - deltaY) / 2
        }
    }

    func frame(size: CGFloat, anchoredTo initialFrame: NSRect) -> NSRect {
        let origin = switch self {
        case .topLeft:
            NSPoint(x: initialFrame.maxX - size, y: initialFrame.minY)
        case .topRight:
            initialFrame.origin
        case .bottomLeft:
            NSPoint(x: initialFrame.maxX - size, y: initialFrame.maxY - size)
        case .bottomRight:
            NSPoint(x: initialFrame.minX, y: initialFrame.maxY - size)
        }

        return NSRect(origin: origin, size: NSSize(width: size, height: size))
    }
}

struct PanelResizeHandle: NSViewRepresentable {
    let corner: PanelResizeCorner

    func makeNSView(context: Context) -> PanelResizeHandleView {
        let view = PanelResizeHandleView(corner: corner)
        view.toolTip = "拖动调整悬浮键盘大小"
        return view
    }

    func updateNSView(_ nsView: PanelResizeHandleView, context: Context) {
        nsView.corner = corner
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class PanelResizeHandleView: NSView {
    var corner: PanelResizeCorner

    private var initialFrame: NSRect?
    private var initialMouseLocation: NSPoint?
    private var cornerTrackingArea: NSTrackingArea?

    init(corner: PanelResizeCorner) {
        self.corner = corner
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: corner.cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cornerTrackingArea {
            removeTrackingArea(cornerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cornerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        corner.cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        if initialFrame == nil {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        corner.cursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
        corner.cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let initialFrame,
            let initialMouseLocation
        else { return }

        let proposedSize = initialFrame.width
            + corner.sizeDelta(from: initialMouseLocation, to: NSEvent.mouseLocation)
        let minimumSize = max(window.contentMinSize.width, window.contentMinSize.height)
        let maximumSize = min(window.contentMaxSize.width, window.contentMaxSize.height)
        let size = min(max(proposedSize, minimumSize), maximumSize)

        window.setFrame(corner.frame(size: size, anchoredTo: initialFrame), display: true)
        corner.cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        initialFrame = nil
        initialMouseLocation = nil
        NSCursor.arrow.set()
    }
}
