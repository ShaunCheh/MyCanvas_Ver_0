import CoreGraphics
import Foundation
import ImageIO

struct CanvasGIFFrameImportEditorContext {
    let itemID: CanvasItemID
    let gifData: Data
    let frameCount: Int
    let selectionGrid: CanvasGIFFrameImportGridConfiguration
    let thumbnailMaxPixelSize: Int

    var frameIndices: Range<Int> {
        0..<frameCount
    }
}

enum CanvasGIFFrameService {
    private static let defaultFrameDelay: TimeInterval = 0.1
    private static let minimumAcceptedFrameDelay: TimeInterval = 0.011
    private static let minimumThumbnailPixelSize = 64

    static func makeImageSource(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    static func frameCount(
        from imageSource: CGImageSource
    ) -> Int {
        CGImageSourceGetCount(imageSource)
    }

    static func animatedMetadata(
        from imageSource: CGImageSource
    ) -> CanvasAnimatedImageMetadata? {
        let frameCount = frameCount(from: imageSource)
        guard frameCount > 1 else {
            return nil
        }

        let frameDelayTimes = (0..<frameCount).map { frameIndex in
            sanitizedFrameDelay(
                forFrameAt: frameIndex,
                imageSource: imageSource
            )
        }
        return CanvasAnimatedImageMetadata(
            frameCount: frameCount,
            frameDelayTimes: frameDelayTimes,
            loopCount: gifLoopCount(from: imageSource)
        )
    }

    static func playbackMetadata(
        from imageSource: CGImageSource,
        importedMetadata: CanvasAnimatedImageMetadata?
    ) -> CanvasAnimatedImageMetadata? {
        let frameCount = frameCount(from: imageSource)
        guard frameCount > 1 else {
            return nil
        }

        if let importedMetadata,
           importedMetadata.frameCount == frameCount,
           importedMetadata.frameDelayTimes.count == frameCount
        {
            return importedMetadata
        }

        return animatedMetadata(from: imageSource)
    }

    static func decodeFrame(
        at frameIndex: Int,
        from imageSource: CGImageSource,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        let frameCount = frameCount(from: imageSource)
        guard frameIndex >= 0, frameIndex < frameCount else {
            return nil
        }

        if let maxPixelSize, maxPixelSize > 0 {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(
                    maxPixelSize,
                    minimumThumbnailPixelSize
                )
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                frameIndex,
                thumbnailOptions as CFDictionary
            ) {
                return thumbnail
            }
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(
            imageSource,
            frameIndex,
            imageOptions as CFDictionary
        )
    }

    private static func gifLoopCount(from imageSource: CGImageSource) -> Int? {
        let properties = CGImageSourceCopyProperties(
            imageSource,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return gifProperties?[kCGImagePropertyGIFLoopCount] as? Int
    }

    private static func sanitizedFrameDelay(
        forFrameAt frameIndex: Int,
        imageSource: CGImageSource
    ) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            frameIndex,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclampedDelay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clampedDelay = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
        let rawDelay = unclampedDelay ?? clampedDelay ?? defaultFrameDelay
        guard rawDelay.isFinite, rawDelay > minimumAcceptedFrameDelay else {
            return defaultFrameDelay
        }

        return rawDelay
    }
}
