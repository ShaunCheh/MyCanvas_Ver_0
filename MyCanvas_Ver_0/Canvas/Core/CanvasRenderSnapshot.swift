import CoreGraphics
import Foundation

// Render items stay focused on image content. Selection chrome travels separately
// so platform overlays and interaction state do not leak into per-item rendering.
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let contentsRect: CGRect
    let rotationRadians: CGFloat
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

enum CanvasEditOverlayKind {
    case selection
    case rotate
    case crop
}

enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case rotate
}

// Unified edit handles carry both their anchor point and the current chrome
// rotation so later stages can keep the resize squares visually aligned.
struct CanvasEditHandleGeometry {
    let role: CanvasEditHandleRole
    let screenCenter: CGPoint
    let screenRotationRadians: CGFloat
}

struct CanvasEditRotateOverlayPayload {
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasEditHandleGeometry
}

struct CanvasEditCropOverlayPayload {
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
}

enum CanvasEditRenderOverlayPayload {
    case selection
    case rotate(CanvasEditRotateOverlayPayload)
    case crop(CanvasEditCropOverlayPayload)
}

// Edit overlay is the future single source of truth for selection, rotate, and
// crop chrome. Old overlay structs remain during the migration so platforms can
// switch over incrementally.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let cornerHandles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

// Shared selection geometry is intentionally platform-neutral: it describes what
// is selected and where it is, while each platform decides visual size and hit slop.
struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let worldQuad: CanvasQuad
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let handles: [CanvasSelectionHandleGeometry]
}

enum CanvasCropHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct CanvasCropHandleGeometry {
    let role: CanvasCropHandleRole
    let screenCenter: CGPoint
}

// Crop overlay stays semantic and neutral: renderer describes the full image
// extent plus the active crop rect, while each platform decides how to dim and
// decorate that geometry for inline editing.
struct CanvasCropRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
    let handles: [CanvasCropHandleGeometry]
}

struct CanvasRotateHandleGeometry {
    let screenCenter: CGPoint
}

// Rotate overlay keeps only semantic geometry for the current item outline,
// pivot guide, and rotate handle. Platforms still decide stroke, fill, and hit slop.
struct CanvasRotateRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let worldQuad: CanvasQuad
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasRotateHandleGeometry
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?
    let rotateOverlay: CanvasRotateRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        editOverlay: nil,
        selectionOverlay: nil,
        cropOverlay: nil,
        rotateOverlay: nil
    )
}
