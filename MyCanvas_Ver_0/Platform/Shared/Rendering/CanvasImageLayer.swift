import CoreGraphics
import QuartzCore

private enum CanvasImageLayerDisplayMode: Equatable {
    case staticPoster
    case animatedPlaybackReady
}

private enum CanvasImageLayerFrameSource: Equatable {
    case poster
    case playback
}

// Image layers only render image content. Selection visuals live in viewport
// overlays so shared render items stay free of platform-specific chrome.
final class CanvasImageLayer: CALayer {
    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastDisplayedImage: CGImage?
    private var lastAppliedPosterImage: CGImage?
    private var lastAppliedAssetReference: CanvasImageAssetReference?
    private var lastAppliedDisplayMode: CanvasImageLayerDisplayMode?
    private var currentFrameSource: CanvasImageLayerFrameSource
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedContentsRect: CGRect
    private var lastAppliedRotationRadians: CGFloat

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastDisplayedImage = nil
        lastAppliedPosterImage = nil
        lastAppliedAssetReference = nil
        lastAppliedDisplayMode = nil
        currentFrameSource = .poster
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedContentsRect = .null
        lastAppliedRotationRadians = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let imageLayer = layer as? CanvasImageLayer {
            itemID = imageLayer.itemID
            lastAppliedPosition = imageLayer.lastAppliedPosition
            lastAppliedBoundsSize = imageLayer.lastAppliedBoundsSize
            lastDisplayedImage = imageLayer.lastDisplayedImage
            lastAppliedPosterImage = imageLayer.lastAppliedPosterImage
            lastAppliedAssetReference = imageLayer.lastAppliedAssetReference
            lastAppliedDisplayMode = imageLayer.lastAppliedDisplayMode
            currentFrameSource = imageLayer.currentFrameSource
            lastAppliedZIndex = imageLayer.lastAppliedZIndex
            lastAppliedContentsScale = imageLayer.lastAppliedContentsScale
            lastAppliedContentsRect = imageLayer.lastAppliedContentsRect
            lastAppliedRotationRadians = imageLayer.lastAppliedRotationRadians
        } else {
            itemID = UUID()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastDisplayedImage = nil
            lastAppliedPosterImage = nil
            lastAppliedAssetReference = nil
            lastAppliedDisplayMode = nil
            currentFrameSource = .poster
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedContentsRect = .null
            lastAppliedRotationRadians = .nan
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func updateStaticPresentation(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        performWithoutActions {
            applyGeometry(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            applyDisplayContract(
                imagePayload.displayContract,
                displayMode: .staticPoster
            )
        }
    }

    func updateAnimatedPresentation(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        performWithoutActions {
            applyGeometry(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            applyDisplayContract(
                imagePayload.displayContract,
                displayMode: .animatedPlaybackReady
            )
        }
    }

    // Stage 4 intentionally keeps playback out of render snapshots. A later
    // playback controller can push decoded frames directly into the reused
    // CALayer without disturbing geometry reconciliation.
    func displayPlaybackFrame(
        _ cgImage: CGImage,
        for assetReference: CanvasImageAssetReference
    ) {
        guard
            lastAppliedAssetReference == assetReference,
            lastAppliedDisplayMode == .animatedPlaybackReady
        else {
            return
        }

        performWithoutActions {
            applyDisplayedImageIfNeeded(cgImage)
            currentFrameSource = .playback
        }
    }

    func restorePosterFrameIfNeeded(
        for assetReference: CanvasImageAssetReference? = nil
    ) {
        performWithoutActions {
            restorePosterFrameWithoutActionsIfNeeded(
                for: assetReference
            )
        }
    }

    private func configureLayer() {
        contentsGravity = .resize
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
    }

    private func applyGeometry(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if lastAppliedContentsRect != imagePayload.contentsRect {
            contentsRect = imagePayload.contentsRect
            lastAppliedContentsRect = imagePayload.contentsRect
        }

        if lastAppliedRotationRadians != item.rotationRadians {
            transform = CATransform3DMakeRotation(item.rotationRadians, 0, 0, 1)
            lastAppliedRotationRadians = item.rotationRadians
        }

        if lastAppliedZIndex != item.zIndex {
            zPosition = item.zIndex
            lastAppliedZIndex = item.zIndex
        }

        if lastAppliedContentsScale != contentsScale {
            self.contentsScale = contentsScale
            lastAppliedContentsScale = contentsScale
        }
    }

    private func applyDisplayContract(
        _ displayContract: CanvasImageDisplayContract,
        displayMode: CanvasImageLayerDisplayMode
    ) {
        let assetChanged = lastAppliedAssetReference != displayContract.assetReference
        let posterChanged = isSameImage(
            lastAppliedPosterImage,
            as: displayContract.posterCGImage
        ) == false
        let displayModeChanged = lastAppliedDisplayMode != displayMode

        if assetChanged {
            lastAppliedAssetReference = displayContract.assetReference
            lastAppliedPosterImage = displayContract.posterCGImage
            currentFrameSource = .poster
            applyDisplayedImageIfNeeded(displayContract.posterCGImage)
        } else if posterChanged {
            lastAppliedPosterImage = displayContract.posterCGImage
            if currentFrameSource == .poster {
                applyDisplayedImageIfNeeded(displayContract.posterCGImage)
            }
        }

        switch displayMode {
        case .staticPoster:
            restorePosterFrameWithoutActionsIfNeeded(
                for: displayContract.assetReference
            )
        case .animatedPlaybackReady:
            if displayModeChanged && currentFrameSource == .poster {
                restorePosterFrameWithoutActionsIfNeeded(
                    for: displayContract.assetReference
                )
            }
        }

        lastAppliedDisplayMode = displayMode
    }

    private func applyDisplayedImageIfNeeded(_ cgImage: CGImage) {
        guard isSameImage(lastDisplayedImage, as: cgImage) == false else {
            return
        }

        contents = cgImage
        lastDisplayedImage = cgImage
    }

    private func restorePosterFrameWithoutActionsIfNeeded(
        for assetReference: CanvasImageAssetReference? = nil
    ) {
        guard
            assetReference == nil || lastAppliedAssetReference == assetReference,
            let posterImage = lastAppliedPosterImage
        else {
            return
        }

        applyDisplayedImageIfNeeded(posterImage)
        currentFrameSource = .poster
    }

    private func isSameImage(
        _ appliedImage: CGImage?,
        as candidateImage: CGImage
    ) -> Bool {
        guard let appliedImage else {
            return false
        }

        return appliedImage === candidateImage
    }

    private func performWithoutActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
