import CoreGraphics
import Foundation

// Image render payloads carry a stable display contract rather than a current
// animation frame, so later GIF playback can update CALayer contents directly
// without forcing renderer snapshots to tick every frame.
struct CanvasImageDisplayContract {
    let assetReference: CanvasImageAssetReference
    let posterCGImage: CGImage
    let allowsAnimatedPlayback: Bool

    var isAnimatedAsset: Bool {
        allowsAnimatedPlayback && assetReference.kind.isAnimated
    }
}

// Render items now carry image, hand-drawing, or text payloads while keeping
// geometry shared, so viewport reconciliation stays type-aware without
// re-solving layout.
struct CanvasImageRenderPayload {
    let displayContract: CanvasImageDisplayContract
    let contentsRect: CGRect
}

struct CanvasHandDrawingRenderPayload {
    let previewAssetReference: CanvasImageAssetReference
    let previewCGImage: CGImage
    let paper: CanvasHandDrawingPaperSpec
    let isEmpty: Bool
}

struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

// Markdown payload stays strictly render-time. It carries stable world-space
// layout inputs plus the current camera zoom for rasterization decisions;
// future bitmap caches or intermediate artifacts must remain outside the
// document model.
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let logicalSize: CGSize
    let cameraZoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
    case markdown(CanvasMarkdownRenderPayload)
}

// Screen geometry is the shared contract consumed by selection chrome,
// accessory anchors, hit-testing, and viewport layers across item types.
struct CanvasRenderItem {
    let id: CanvasItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let rotationRadians: CGFloat
    let zIndex: CGFloat
    let payload: CanvasRenderPayload
}

// Workspace chrome is now the shared source of truth for board surface and
// background grid geometry across macOS and iOS viewports.
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
    case leading
    case trailing
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

struct CanvasSelectionHighlight: Equatable {
    let itemID: CanvasItemID
    let screenQuad: CanvasQuad
    let isPrimary: Bool
}

enum CanvasEditSelectionOverlaySubject: Equatable {
    case singleItem(itemID: CanvasItemID)
    case group(primaryItemID: CanvasItemID, memberItemIDs: [CanvasItemID])

    var primaryItemID: CanvasItemID {
        switch self {
        case let .singleItem(itemID):
            return itemID
        case let .group(primaryItemID, _):
            return primaryItemID
        }
    }

    var memberItemIDs: [CanvasItemID] {
        switch self {
        case let .singleItem(itemID):
            return [itemID]
        case let .group(_, memberItemIDs):
            return memberItemIDs
        }
    }

    var isGroupSelection: Bool {
        switch self {
        case .singleItem:
            return false
        case .group:
            return true
        }
    }
}

struct CanvasEditSelectionOverlayPayload {
    let subject: CanvasEditSelectionOverlaySubject
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
    let itemID: CanvasItemID
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
    case alignment
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

// Alignment overlay also stays in transient interaction space; the renderer
// will later map world-space guides into these screen-space segments.
struct CanvasAlignmentInteractionOverlayPayload {
    let guideSegments: [CanvasInteractionLineSegment]
    let xMatch: CanvasAlignmentMatch?
    let yMatch: CanvasAlignmentMatch?
    let isActive: Bool
}

enum CanvasInteractionRenderOverlayPayload {
    case rotation(CanvasRotationInteractionOverlayPayload)
    case alignment(CanvasAlignmentInteractionOverlayPayload)
}

// Interaction overlays intentionally live alongside edit overlays so transient
// gesture HUDs can evolve without being folded back into selection/crop chrome.
struct CanvasInteractionRenderOverlay {
    let itemID: CanvasItemID
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
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    var isWidthOnly: Bool {
        switch self {
        case .leading, .trailing:
            return true
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return false
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
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .top, .bottom, .rotate:
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
    let items: [CanvasRenderItem]
    let selectionHighlights: [CanvasSelectionHighlight]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        workspaceOverlay: nil,
        items: [],
        selectionHighlights: [],
        editOverlay: nil,
        interactionOverlay: nil
    )
}
