import CoreGraphics
import Foundation

struct CanvasImagePresentationResolver {
    func resolve(
        item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasImagePresentation {
        let isCropPreviewActive =
            inlineEditState?.mode == .crop &&
            inlineEditState?.itemID == item.id
        let previewGeometry = rotationPreviewState?.geometry(for: item.id)
        let isRotationPreviewActive = previewGeometry != nil

        var effectiveItem = item
        if let previewGeometry {
            effectiveItem.center = previewGeometry.center
            effectiveItem.size = previewGeometry.size
            effectiveItem.rotationRadians = previewGeometry.rotationRadians
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
            assetReference: effectiveItem.assetReference,
            assetKind: effectiveItem.assetKind,
            posterCGImage: effectiveItem.posterCGImage,
            allowsAnimatedPlayback: effectiveItem.allowsAnimatedPlayback,
            logicalPixelSize: effectiveItem.logicalPixelSize,
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
