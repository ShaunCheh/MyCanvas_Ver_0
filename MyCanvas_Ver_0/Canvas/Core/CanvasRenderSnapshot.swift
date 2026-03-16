import CoreGraphics
import Foundation

struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct CanvasSelectionHandleGeometry {
    let role: CanvasSelectionHandleRole
    let screenCenter: CGPoint
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasSelectionHandleGeometry]
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil
    )
}
