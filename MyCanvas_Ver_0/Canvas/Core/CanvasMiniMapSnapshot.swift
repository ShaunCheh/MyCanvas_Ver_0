import CoreGraphics
import Foundation

// Minimap nodes stay geometry-first so future text/sticker/shape support can
// reuse the same snapshot and platform views without depending on image layers.
enum CanvasMiniMapNodeKind {
    case image
    case text
    case sticker
    case shape
}

struct CanvasMiniMapNode {
    let id: UUID
    let kind: CanvasMiniMapNodeKind
    let worldQuad: CanvasQuad
    let zIndex: CGFloat
    let isPreviewActive: Bool

    var worldBounds: CGRect {
        worldQuad.boundingRect.standardized
    }
}

struct CanvasMiniMapSnapshot {
    let boardWorldRect: CGRect
    let displayWorldRect: CGRect
    let visibleWorldRect: CGRect
    let nodes: [CanvasMiniMapNode]

    static let empty = CanvasMiniMapSnapshot(
        boardWorldRect: .zero,
        displayWorldRect: .zero,
        visibleWorldRect: .zero,
        nodes: []
    )
}
