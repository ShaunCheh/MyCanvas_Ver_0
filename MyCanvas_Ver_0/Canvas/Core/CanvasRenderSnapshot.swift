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

// Workspace chrome is an additive contract during the migration away from
// board highlight rendering. Platform viewports can adopt this geometry
// incrementally while the legacy board overlay remains available.
struct CanvasWorkspaceGridLineSegment {
    let start: CGPoint
    let end: CGPoint
}

struct CanvasWorkspaceRenderOverlay {
    let viewportBounds: CGRect
    let boardSurfaceWorldRect: CGRect
    let boardSurfaceScreenRect: CGRect
    let minorGridStepWorld: CGFloat
    let majorGridLineEvery: Int
    let minorGridSegments: [CanvasWorkspaceGridLineSegment]
    let majorGridSegments: [CanvasWorkspaceGridLineSegment]
}

enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

enum CanvasEditOverlayKind {
    case selection
    case crop
}

enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
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

struct CanvasEditSelectionOverlayPayload {
    let rotateAffordance: CanvasEditRotateOverlayPayload
}

struct CanvasEditCropOverlayPayload {
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
}

enum CanvasEditRenderOverlayPayload {
    case selection(CanvasEditSelectionOverlayPayload)
    case crop(CanvasEditCropOverlayPayload)
}

// Edit overlay is now the single shared source of truth for selection chrome
// (including rotate affordances) and crop chrome across renderer, viewport,
// and controller layers.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

struct CanvasInteractionLineSegment {
    let start: CGPoint
    let end: CGPoint
}

enum CanvasInteractionOverlayKind {
    case rotation
}

enum CanvasInteractionAngleZeroReference {
    case up
}

struct CanvasRotationInteractionOverlayPayload {
    let screenCenter: CGPoint
    let currentRotationRadians: CGFloat
    let displayDegrees0To360: CGFloat
    let zeroReference: CanvasInteractionAngleZeroReference
    let tickStepDegrees: CGFloat
    let ringRadius: CGFloat
    let ringScreenRect: CGRect
    let tickSegments: [CanvasInteractionLineSegment]
    let zeroReferenceSegment: CanvasInteractionLineSegment
    let currentAngleSegment: CanvasInteractionLineSegment
    let textScreenAnchor: CGPoint
    let isActive: Bool
}

enum CanvasInteractionRenderOverlayPayload {
    case rotation(CanvasRotationInteractionOverlayPayload)
}

// Interaction overlays intentionally live alongside edit overlays so transient
// gesture HUDs can evolve without being folded back into selection/crop chrome.
struct CanvasInteractionRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasInteractionOverlayKind
    let payload: CanvasInteractionRenderOverlayPayload
}

enum CanvasCropHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
}

extension CanvasSelectionHandleRole {
    var editHandleRole: CanvasEditHandleRole {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

extension CanvasCropHandleRole {
    var editHandleRole: CanvasEditHandleRole {
        switch self {
        case .topLeading:
            return .topLeading
        case .top:
            return .top
        case .topTrailing:
            return .topTrailing
        case .trailing:
            return .trailing
        case .bottom:
            return .bottom
        case .leading:
            return .leading
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

extension CanvasEditHandleRole {
    var selectionHandleRole: CanvasSelectionHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .top, .trailing, .bottom, .leading, .rotate:
            return nil
        }
    }

    var cropHandleRole: CanvasCropHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .top:
            return .top
        case .topTrailing:
            return .topTrailing
        case .trailing:
            return .trailing
        case .bottom:
            return .bottom
        case .leading:
            return .leading
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .rotate:
            return nil
        }
    }
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        workspaceOverlay: nil,
        boardOverlay: nil,
        items: [],
        editOverlay: nil,
        interactionOverlay: nil
    )
}
