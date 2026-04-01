import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CanvasVideoFrameServiceError: LocalizedError {
    case invalidVideoItem(itemID: UUID)
    case missingBoardIdentity
    case missingSourceVideoFilename(itemID: UUID)
    case missingVideoAsset(filename: String)
    case failedToGenerateFrame(filename: String, requestedTimeSeconds: Double)
    case failedToEncodePoster(filename: String)

    var errorDescription: String? {
        switch self {
        case let .invalidVideoItem(itemID):
            return "The selected item is not a valid video item: \(itemID.uuidString)"
        case .missingBoardIdentity:
            return "Unable to resolve the active board for video editing."
        case let .missingSourceVideoFilename(itemID):
            return "The video item is missing its source asset reference: \(itemID.uuidString)"
        case let .missingVideoAsset(filename):
            return "The video asset is missing from board assets: \(filename)"
        case let .failedToGenerateFrame(filename, requestedTimeSeconds):
            return "Unable to generate a video frame from \(filename) at \(requestedTimeSeconds)s."
        case let .failedToEncodePoster(filename):
            return "Unable to encode the video poster image: \(filename)"
        }
    }
}

enum CanvasVideoFrameRenderQuality {
    case posterCommit
    case previewStripThumbnail(maxPixelSize: Int)
}

struct CanvasVideoFrameImage {
    let cgImage: CGImage
    let logicalPixelSize: CGSize
    let requestedTimeSeconds: Double
    let actualTimeSeconds: Double
}

struct CanvasVideoPreviewStripFrame {
    let cgImage: CGImage
    let timeSeconds: Double
}

struct CanvasVideoPreviewStrip {
    let durationSeconds: Double
    let frames: [CanvasVideoPreviewStripFrame]
}

struct CanvasVideoEditorContext {
    let boardID: UUID
    let itemID: CanvasItemID
    let sourceVideoURL: URL
    let sourceVideoFilename: String
    let currentPosterFilename: String
    let currentPosterTimeSeconds: Double
    let durationSeconds: Double
    let naturalPixelSize: CGSize
}

struct CanvasPersistedVideoPoster {
    let asset: CanvasImageAsset
    let assetURL: URL
    let posterTimeSeconds: Double
}

enum CanvasVideoFrameService {
    static func editorContext(
        for item: CanvasImageItem,
        boardID: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasVideoEditorContext {
        guard item.isVideo else {
            throw CanvasVideoFrameServiceError.invalidVideoItem(itemID: item.id)
        }
        guard let sourceVideoFilename = item.sourceVideoFilename else {
            throw CanvasVideoFrameServiceError.missingSourceVideoFilename(
                itemID: item.id
            )
        }

        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        let sourceVideoURL = assetsDirectoryURL.appendingPathComponent(
            sourceVideoFilename
        )
        guard try CoordinatedFileIO.modificationDate(at: sourceVideoURL) != nil else {
            throw CanvasVideoFrameServiceError.missingVideoAsset(
                filename: sourceVideoFilename
            )
        }

        let asset = AVURLAsset(url: sourceVideoURL)
        return CanvasVideoEditorContext(
            boardID: boardID,
            itemID: item.id,
            sourceVideoURL: sourceVideoURL,
            sourceVideoFilename: sourceVideoFilename,
            currentPosterFilename: item.assetReference.stableAssetFilename,
            currentPosterTimeSeconds: sanitizedTimeSeconds(
                item.posterTimeSeconds ?? 0
            ),
            durationSeconds: sanitizedDurationSeconds(asset.duration),
            naturalPixelSize: naturalVideoPixelSize(for: asset) ?? item.logicalPixelSize
        )
    }

    static func frameImage(
        from localFileURL: URL,
        at timeSeconds: Double,
        quality: CanvasVideoFrameRenderQuality
    ) throws -> CanvasVideoFrameImage {
        let asset = AVURLAsset(url: localFileURL)
        let filename = localFileURL.lastPathComponent
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: quality
        )
        return try makeFrameImage(
            from: asset,
            filename: filename,
            at: timeSeconds,
            imageGenerator: imageGenerator
        )
    }

    static func previewStrip(
        from localFileURL: URL,
        frameCount: Int,
        maxPixelSize: Int
    ) throws -> CanvasVideoPreviewStrip {
        let asset = AVURLAsset(url: localFileURL)
        let filename = localFileURL.lastPathComponent
        let durationSeconds = sanitizedDurationSeconds(asset.duration)
        let requestedFrameCount = max(frameCount, 1)
        let sampleTimes = previewSampleTimes(
            durationSeconds: durationSeconds,
            frameCount: requestedFrameCount
        )
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: .previewStripThumbnail(maxPixelSize: maxPixelSize)
        )
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator
            )
            return CanvasVideoPreviewStripFrame(
                cgImage: frameImage.cgImage,
                timeSeconds: frameImage.actualTimeSeconds
            )
        }
        return CanvasVideoPreviewStrip(
            durationSeconds: durationSeconds,
            frames: frames
        )
    }

    static func persistPosterAsset(
        cgImage: CGImage,
        logicalPixelSize: CGSize,
        posterTimeSeconds: Double,
        itemID: CanvasItemID? = nil,
        to assetsDirectoryURL: URL
    ) throws -> CanvasPersistedVideoPoster {
        let posterFilename = makePosterFilename(for: itemID)
        let posterAssetURL = assetsDirectoryURL.appendingPathComponent(
            posterFilename
        )
        try CoordinatedFileIO.writeData(
            makePNGData(for: cgImage, filename: posterFilename),
            to: posterAssetURL
        )
        return CanvasPersistedVideoPoster(
            asset: CanvasImageAsset.persistedStaticImage(
                filename: posterFilename,
                cgImage: cgImage,
                logicalPixelSize: logicalPixelSize
            ),
            assetURL: posterAssetURL,
            posterTimeSeconds: sanitizedTimeSeconds(posterTimeSeconds)
        )
    }

    static func persistPosterAsset(
        cgImage: CGImage,
        logicalPixelSize: CGSize,
        posterTimeSeconds: Double,
        boardID: UUID,
        itemID: CanvasItemID? = nil,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasPersistedVideoPoster {
        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        return try persistPosterAsset(
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize,
            posterTimeSeconds: posterTimeSeconds,
            itemID: itemID,
            to: assetsDirectoryURL
        )
    }

    private static func makeFrameImage(
        from asset: AVAsset,
        filename: String,
        at timeSeconds: Double,
        imageGenerator: AVAssetImageGenerator
    ) throws -> CanvasVideoFrameImage {
        let clampedTimeSeconds = clampedTimeSeconds(
            timeSeconds,
            for: asset
        )
        var actualTime = CMTime.zero
        let requestedTime = CMTime(
            seconds: clampedTimeSeconds,
            preferredTimescale: 600
        )
        guard let cgImage = try? imageGenerator.copyCGImage(
            at: requestedTime,
            actualTime: &actualTime
        ) else {
            throw CanvasVideoFrameServiceError.failedToGenerateFrame(
                filename: filename,
                requestedTimeSeconds: clampedTimeSeconds
            )
        }

        let actualTimeSeconds = actualTime.seconds.isFinite
            ? max(actualTime.seconds, 0)
            : clampedTimeSeconds
        return CanvasVideoFrameImage(
            cgImage: cgImage,
            logicalPixelSize: naturalVideoPixelSize(for: asset) ?? CGSize(
                width: cgImage.width,
                height: cgImage.height
            ),
            requestedTimeSeconds: clampedTimeSeconds,
            actualTimeSeconds: actualTimeSeconds
        )
    }

    private static func makeImageGenerator(
        for asset: AVAsset,
        quality: CanvasVideoFrameRenderQuality
    ) -> AVAssetImageGenerator {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        switch quality {
        case .posterCommit:
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
        case let .previewStripThumbnail(maxPixelSize):
            imageGenerator.maximumSize = CGSize(
                width: max(maxPixelSize, 1),
                height: max(maxPixelSize, 1)
            )
            let tolerance = CMTime(
                seconds: 0.25,
                preferredTimescale: 600
            )
            imageGenerator.requestedTimeToleranceBefore = tolerance
            imageGenerator.requestedTimeToleranceAfter = tolerance
        }
        return imageGenerator
    }

    private static func makePosterFilename(
        for itemID: CanvasItemID?
    ) -> String {
        if let itemID {
            return "video-poster-\(itemID.uuidString)-\(UUID().uuidString).png"
        }

        return "video-poster-\(UUID().uuidString).png"
    }

    private static func makePNGData(
        for image: CGImage,
        filename: String
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CanvasVideoFrameServiceError.failedToEncodePoster(
                filename: filename
            )
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CanvasVideoFrameServiceError.failedToEncodePoster(
                filename: filename
            )
        }

        return mutableData as Data
    }

    private static func previewSampleTimes(
        durationSeconds: Double,
        frameCount: Int
    ) -> [Double] {
        guard frameCount > 1 else {
            return [0]
        }

        let upperBound = previewUpperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
        guard upperBound > 0 else {
            return Array(repeating: 0, count: frameCount)
        }

        let denominator = Double(frameCount - 1)
        return (0..<frameCount).map { index in
            (upperBound * Double(index)) / denominator
        }
    }

    private static func sanitizedTimeSeconds(
        _ timeSeconds: Double
    ) -> Double {
        guard timeSeconds.isFinite else {
            return 0
        }

        return max(timeSeconds, 0)
    }

    private static func sanitizedDurationSeconds(
        _ duration: CMTime
    ) -> Double {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return seconds
    }

    private static func clampedTimeSeconds(
        _ timeSeconds: Double,
        for asset: AVAsset
    ) -> Double {
        let sanitizedTimeSeconds = sanitizedTimeSeconds(timeSeconds)
        let upperBound = previewUpperBoundTimeSeconds(
            durationSeconds: sanitizedDurationSeconds(asset.duration)
        )
        guard upperBound > 0 else {
            return 0
        }

        return min(sanitizedTimeSeconds, upperBound)
    }

    private static func previewUpperBoundTimeSeconds(
        durationSeconds: Double
    ) -> Double {
        guard durationSeconds > 0 else {
            return 0
        }

        return max(durationSeconds - (1.0 / 600.0), 0)
    }

    private static func naturalVideoPixelSize(
        for asset: AVAsset
    ) -> CGSize? {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return nil
        }

        let transformedSize = videoTrack.naturalSize.applying(
            videoTrack.preferredTransform
        )
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        guard width > 0, height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}
