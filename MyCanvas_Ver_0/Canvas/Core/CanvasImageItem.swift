import CoreGraphics
import Foundation

typealias CanvasItemID = UUID
typealias CanvasImageItemID = CanvasItemID

// Crop stays in normalized image space so later editing can change what is shown
// without mutating the original image asset in memory or on disk.
struct CanvasImageCropRect: Equatable {
    private static let fullImageRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    static let fullImage = CanvasImageCropRect(fullImageRect)

    let cgRect: CGRect

    init(_ cgRect: CGRect = CanvasImageCropRect.fullImageRect) {
        self.cgRect = Self.sanitizedRect(from: cgRect)
    }

    var isFullImage: Bool {
        cgRect == Self.fullImage.cgRect
    }

    private static func sanitizedRect(from cgRect: CGRect) -> CGRect {
        guard cgRect.isNull == false, cgRect.isInfinite == false else {
            return fullImageRect
        }

        let standardized = cgRect.standardized
        let minX = min(max(standardized.minX, fullImageRect.minX), fullImageRect.maxX)
        let minY = min(max(standardized.minY, fullImageRect.minY), fullImageRect.maxY)
        let maxX = min(max(standardized.maxX, fullImageRect.minX), fullImageRect.maxX)
        let maxY = min(max(standardized.maxY, fullImageRect.minY), fullImageRect.maxY)
        let width = maxX - minX
        let height = maxY - minY

        guard width > 0, height > 0 else {
            return fullImageRect
        }

        return CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
    }
}

struct CanvasImageItem {
    let id: CanvasImageItemID
    var asset: CanvasImageAsset
    var videoSource: CanvasVideoSource?
    var posterTimeSeconds: Double?
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        asset: CanvasImageAsset,
        videoSource: CanvasVideoSource? = nil,
        posterTimeSeconds: Double? = nil,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.asset = asset
        self.videoSource = videoSource
        self.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds,
            isVideo: videoSource != nil
        )
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    static var assetContract: CanvasImageAssetContract {
        .current
    }

    var assetReference: CanvasImageAssetReference {
        asset.reference
    }

    var assetKind: CanvasImageAssetKind {
        assetReference.kind
    }

    var isVideo: Bool {
        videoSource != nil
    }

    var allowsAnimatedPlayback: Bool {
        isVideo == false
    }

    var sourceVideoFilename: String? {
        videoSource?.sourceVideoFilename
    }

    var posterCGImage: CGImage {
        asset.posterCGImage
    }

    var logicalPixelSize: CGSize {
        asset.logicalPixelSize
    }

    var localFrame: CGRect {
        CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var localQuad: CanvasQuad {
        CanvasQuad(rect: localFrame)
    }

    // Reconstruct the uncropped image extent in the item's local space so crop
    // editing can preview and adjust against the original full image footprint.
    var fullImageLocalFrame: CGRect {
        let normalizedCropRect = cropRectNormalized.cgRect
        let fullImageSize = CGSize(
            width: size.width / normalizedCropRect.width,
            height: size.height / normalizedCropRect.height
        )
        return CGRect(
            x: localFrame.minX - (normalizedCropRect.minX * fullImageSize.width),
            y: localFrame.minY - (normalizedCropRect.minY * fullImageSize.height),
            width: fullImageSize.width,
            height: fullImageSize.height
        )
    }

    var fullImageLocalQuad: CanvasQuad {
        CanvasQuad(rect: fullImageLocalFrame)
    }

    var fullImageWorldQuad: CanvasQuad {
        fullImageLocalQuad.map(worldPoint(fromLocal:))
    }

    var worldQuad: CanvasQuad {
        localQuad.map(worldPoint(fromLocal:))
    }

    // `worldFrame` intentionally remains the unrotated visible frame so the
    // existing axis-aligned move/resize flows can keep compiling during the
    // staged rotation rollout. Use `worldBounds` for transformed culling/hit-test.
    var worldFrame: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var worldBounds: CGRect {
        worldQuad.boundingRect
    }

    var imageContentsRect: CGRect {
        cropRectNormalized.cgRect
    }

    // Static images/GIFs keep sharing one underlying asset reference, while
    // video items share only the source video and get an independent poster file.
    func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
        let duplicatedAsset: CanvasImageAsset
        if isVideo {
            // Video items own their poster image independently so later cover
            // changes do not rewrite another duplicated item's display frame.
            duplicatedAsset = CanvasImageAsset.transientStaticImage(
                cgImage: asset.posterCGImage,
                logicalPixelSize: asset.logicalPixelSize
            )
        } else {
            duplicatedAsset = asset
        }

        CanvasImageItem(
            asset: duplicatedAsset,
            videoSource: videoSource,
            posterTimeSeconds: posterTimeSeconds,
            center: CGPoint(
                x: center.x + offsetInWorld.x,
                y: center.y + offsetInWorld.y
            ),
            size: size,
            zIndex: zIndex,
            cropRectNormalized: cropRectNormalized,
            rotationRadians: rotationRadians
        )
    }

    // History should track persisted document state and resource identity, but
    // must continue to ignore transient playback progress.
    func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
        id == other.id &&
            assetReference == other.assetReference &&
            videoSource == other.videoSource &&
            posterTimeSeconds == other.posterTimeSeconds &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            cropRectNormalized == other.cropRectNormalized &&
            rotationRadians == other.rotationRadians
    }

    func updatingVideoPoster(
        posterAsset: CanvasImageAsset,
        posterTimeSeconds: Double
    ) -> CanvasImageItem? {
        guard isVideo else {
            return nil
        }

        var updatedItem = self
        updatedItem.asset = posterAsset
        updatedItem.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds,
            isVideo: true
        )
        return updatedItem
    }

    func localFrame(forNormalizedCropRect normalizedCropRect: CanvasImageCropRect) -> CGRect {
        let cropRect = normalizedCropRect.cgRect
        let fullImageFrame = fullImageLocalFrame
        return CGRect(
            x: fullImageFrame.minX + (cropRect.minX * fullImageFrame.width),
            y: fullImageFrame.minY + (cropRect.minY * fullImageFrame.height),
            width: fullImageFrame.width * cropRect.width,
            height: fullImageFrame.height * cropRect.height
        )
    }

    func localQuad(forNormalizedCropRect normalizedCropRect: CanvasImageCropRect) -> CanvasQuad {
        CanvasQuad(rect: localFrame(forNormalizedCropRect: normalizedCropRect))
    }

    func worldQuad(forNormalizedCropRect normalizedCropRect: CanvasImageCropRect) -> CanvasQuad {
        localQuad(forNormalizedCropRect: normalizedCropRect).map(worldPoint(fromLocal:))
    }

    func normalizedCropRect(fromLocalFrame localCropFrame: CGRect) -> CanvasImageCropRect {
        let fullImageFrame = fullImageLocalFrame
        guard
            fullImageFrame.width > 0,
            fullImageFrame.height > 0
        else {
            return .fullImage
        }

        return CanvasImageCropRect(
            CGRect(
                x: (localCropFrame.minX - fullImageFrame.minX) / fullImageFrame.width,
                y: (localCropFrame.minY - fullImageFrame.minY) / fullImageFrame.height,
                width: localCropFrame.width / fullImageFrame.width,
                height: localCropFrame.height / fullImageFrame.height
            )
        )
    }

    func contains(worldPoint: CGPoint) -> Bool {
        localFrame.contains(localPoint(fromWorld: worldPoint))
    }

    func worldPoint(fromLocal localPoint: CGPoint) -> CGPoint {
        let rotatedPoint = Self.rotated(localPoint, by: rotationRadians)
        return CGPoint(
            x: rotatedPoint.x + center.x,
            y: rotatedPoint.y + center.y
        )
    }

    func localPoint(fromWorld worldPoint: CGPoint) -> CGPoint {
        let translatedPoint = CGPoint(
            x: worldPoint.x - center.x,
            y: worldPoint.y - center.y
        )
        return Self.rotated(translatedPoint, by: -rotationRadians)
    }

    private static func rotated(
        _ point: CGPoint,
        by radians: CGFloat
    ) -> CGPoint {
        guard radians != 0 else {
            return point
        }

        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }

    private static func sanitizedPosterTimeSeconds(
        _ posterTimeSeconds: Double?,
        isVideo: Bool
    ) -> Double? {
        guard isVideo else {
            return nil
        }

        guard let posterTimeSeconds else {
            return 0
        }

        guard posterTimeSeconds.isFinite else {
            return 0
        }

        return max(posterTimeSeconds, 0)
    }
}
