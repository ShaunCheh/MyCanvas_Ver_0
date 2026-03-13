import CoreGraphics
import Foundation

struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let items: [CanvasRenderItem]

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        items: []
    )
}
