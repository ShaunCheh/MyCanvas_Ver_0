import CoreGraphics
import Foundation

enum BoardMediaPosterImageResolverError: LocalizedError {
    case invalidPosterAsset(filename: String)

    var errorDescription: String? {
        switch self {
        case let .invalidPosterAsset(filename):
            return "The board preview poster asset could not be decoded: \(filename)"
        }
    }
}

struct BoardMediaPosterImageResolver {
    private enum PosterSource {
        case imageAsset(filename: String)
        case videoPoster(filename: String)
    }

    func previewAssetFilename(
        for itemRecord: BoardImageItemRecord
    ) -> String {
        switch posterSource(for: itemRecord) {
        case let .imageAsset(filename), let .videoPoster(filename):
            return filename
        }
    }

    func resolvePreviewImage(
        for itemRecord: BoardImageItemRecord,
        assetsDirectoryURL: URL,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        maxPixelSize: Int
    ) throws -> CGImage {
        switch posterSource(for: itemRecord) {
        case let .imageAsset(filename):
            return try loadImageAssetPosterFrame(
                named: filename,
                in: assetsDirectoryURL,
                animatedImagePreviewMode: animatedImagePreviewMode,
                maxPixelSize: maxPixelSize
            )
        case let .videoPoster(filename):
            // Video items already own a persisted poster image, so BoardList
            // should read that cached poster directly instead of touching the
            // original video file.
            return try loadVideoPosterImage(
                named: filename,
                in: assetsDirectoryURL,
                maxPixelSize: maxPixelSize
            )
        }
    }

    private func posterSource(
        for itemRecord: BoardImageItemRecord
    ) -> PosterSource {
        if itemRecord.isVideo {
            return .videoPoster(filename: itemRecord.posterImageFilename)
        }

        return .imageAsset(filename: itemRecord.assetFilename)
    }

    private func loadImageAssetPosterFrame(
        named filename: String,
        in assetsDirectoryURL: URL,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        maxPixelSize: Int
    ) throws -> CGImage {
        let assetURL = assetsDirectoryURL.appendingPathComponent(filename)
        let assetData = try CoordinatedFileIO.readData(at: assetURL)
        let image: CGImage?

        switch animatedImagePreviewMode {
        case .posterFrameOnly:
            image = CanvasImagePosterFrameDecoder.decodePosterFrame(
                from: assetData,
                maxPixelSize: maxPixelSize
            )
        }

        guard let image else {
            throw BoardMediaPosterImageResolverError.invalidPosterAsset(
                filename: filename
            )
        }

        return image
    }

    private func loadVideoPosterImage(
        named filename: String,
        in assetsDirectoryURL: URL,
        maxPixelSize: Int
    ) throws -> CGImage {
        let posterURL = assetsDirectoryURL.appendingPathComponent(filename)
        let posterData = try CoordinatedFileIO.readData(at: posterURL)
        guard let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
            from: posterData,
            maxPixelSize: maxPixelSize
        ) else {
            throw BoardMediaPosterImageResolverError.invalidPosterAsset(
                filename: filename
            )
        }

        return image
    }
}
