import Foundation

enum PointerPanelPlacement {
    static func origin(
        pointer: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let desired = CGPoint(
            x: pointer.x - panelSize.width / 2,
            y: pointer.y - panelSize.height / 2
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(desired.x, visibleFrame.minX), maximumX),
            y: min(max(desired.y, visibleFrame.minY), maximumY)
        )
    }
}
