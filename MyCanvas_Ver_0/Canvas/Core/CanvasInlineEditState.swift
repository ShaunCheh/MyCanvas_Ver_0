import CoreGraphics
import Foundation

enum CanvasInlineEditMode {
    case crop
    case rotate
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop and rotate drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var mode: CanvasInlineEditMode
    var draftCropRectNormalized: CanvasImageCropRect
    var draftRotationRadians: CGFloat

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage,
        draftRotationRadians: CGFloat = 0
    ) {
        self.itemID = itemID
        self.mode = mode
        self.draftCropRectNormalized = draftCropRectNormalized
        self.draftRotationRadians = draftRotationRadians
    }

    init(
        item: CanvasImageItem,
        mode: CanvasInlineEditMode
    ) {
        self.init(
            itemID: item.id,
            mode: mode,
            draftCropRectNormalized: item.cropRectNormalized,
            draftRotationRadians: item.rotationRadians
        )
    }
}
