import CoreGraphics
import Foundation

enum CanvasInlineEditMode: Equatable {
    case crop
}

struct CanvasInlineCropSession {
    var draftCropRectNormalized: CanvasImageCropRect
}

// Keep rotation preview separate from crop-only inline edit state so selected
// items can rotate directly without entering a dedicated mode.
struct CanvasRotationPreviewState {
    let itemID: CanvasImageItemID
    var draftRotationRadians: CGFloat
}

// Track the active rotation gesture separately from the draft angle so later
// overlays can appear immediately when rotation starts, even before the angle
// diverges from the persisted item rotation.
struct CanvasRotationInteractionState {
    let itemID: CanvasImageItemID
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var cropSession: CanvasInlineCropSession

    var mode: CanvasInlineEditMode {
        .crop
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            return cropSession.draftCropRectNormalized
        }
        set {
            cropSession.draftCropRectNormalized = newValue
        }
    }

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage
    ) {
        self.itemID = itemID
        switch mode {
        case .crop:
            cropSession = CanvasInlineCropSession(
                draftCropRectNormalized: draftCropRectNormalized
            )
        }
    }

    init(
        itemID: CanvasImageItemID,
        cropSession: CanvasInlineCropSession
    ) {
        self.itemID = itemID
        self.cropSession = cropSession
    }

    init(
        item: CanvasImageItem,
        mode: CanvasInlineEditMode = .crop
    ) {
        self.init(
            itemID: item.id,
            mode: mode,
            draftCropRectNormalized: item.cropRectNormalized
        )
    }
}
