import CoreGraphics
import Foundation
import ImageIO

enum CanvasImagePosterFrameDecoder {
    static func decodePosterFrame(
        from data: Data,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return decodePosterFrame(
            from: imageSource,
            maxPixelSize: maxPixelSize
        )
    }

    static func decodePosterFrame(
        from imageSource: CGImageSource,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        if let maxPixelSize, maxPixelSize > 0 {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
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
            0,
            imageOptions as CFDictionary
        )
    }
}
