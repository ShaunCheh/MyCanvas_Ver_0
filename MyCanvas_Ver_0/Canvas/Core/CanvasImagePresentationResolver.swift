import CoreGraphics
import Foundation

struct CanvasImagePresentationResolver {
    func resolve(
        item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasImagePresentation {
        let isCropPreviewActive = inlineEditState?.itemID == item.id
        let isRotationPreviewActive = rotationPreviewState?.itemID == item.id

        var effectiveItem = item
        if let rotationPreviewState, rotationPreviewState.itemID == item.id {
            effectiveItem.rotationRadians = rotationPreviewState.draftRotationRadians
        }

        let effectiveCropRectNormalized = isCropPreviewActive
            ? inlineEditState?.draftCropRectNormalized ?? effectiveItem.cropRectNormalized
            : effectiveItem.cropRectNormalized

        let visibleLocalFrame = isCropPreviewActive
            ? effectiveItem.localFrame(
                forNormalizedCropRect: effectiveCropRectNormalized
            ).standardized
            : effectiveItem.localFrame.standardized
        let visibleWorldQuad = isCropPreviewActive
            ? effectiveItem.worldQuad(
                forNormalizedCropRect: effectiveCropRectNormalized
            )
            : effectiveItem.worldQuad
        let visibleCenter = effectiveItem.worldPoint(
            fromLocal: CGPoint(
                x: visibleLocalFrame.midX,
                y: visibleLocalFrame.midY
            )
        )

        let fullImageLocalFrame = effectiveItem.fullImageLocalFrame.standardized
        let fullImageWorldQuad = effectiveItem.fullImageWorldQuad
        let fullImageCenter = effectiveItem.worldPoint(
            fromLocal: CGPoint(
                x: fullImageLocalFrame.midX,
                y: fullImageLocalFrame.midY
            )
        )

        return CanvasImagePresentation(
            itemID: effectiveItem.id,
            cgImage: effectiveItem.cgImage,
            zIndex: effectiveItem.zIndex,
            effectiveRotationRadians: effectiveItem.rotationRadians,
            effectiveCropRectNormalized: effectiveCropRectNormalized,
            visibleLocalFrame: visibleLocalFrame,
            visibleWorldQuad: visibleWorldQuad,
            visibleCenter: visibleCenter,
            visibleSize: visibleLocalFrame.size,
            fullImageLocalFrame: fullImageLocalFrame,
            fullImageWorldQuad: fullImageWorldQuad,
            fullImageCenter: fullImageCenter,
            fullImageSize: fullImageLocalFrame.size,
            isCropPreviewActive: isCropPreviewActive,
            isRotationPreviewActive: isRotationPreviewActive
        )
    }
}
