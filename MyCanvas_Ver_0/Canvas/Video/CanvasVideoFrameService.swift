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

private struct CanvasVideoTimelineStripCacheKey {
    private static let timeBucketScale = 1_000.0
    private static let densityBucketScale = 1_000.0
    private static let layoutBucketScale = 100.0

    let sourceVideoPath: String
    let requestedTimeLowerBucket: Int
    let requestedTimeUpperBucket: Int
    let pointsPerSecondBucket: Int
    let contentWidthBucket: Int
    let thumbnailWidthBucket: Int
    let targetFrameCount: Int
    let maxPixelSize: Int

    init(
        localFileURL: URL,
        request: CanvasVideoTimelineStripRequest,
        targetFrameCount: Int? = nil
    ) {
        sourceVideoPath = localFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        requestedTimeLowerBucket = Self.bucket(
            request.requestedTimeRange.lowerBound,
            scale: Self.timeBucketScale
        )
        requestedTimeUpperBucket = Self.bucket(
            request.requestedTimeRange.upperBound,
            scale: Self.timeBucketScale
        )
        pointsPerSecondBucket = Self.bucket(
            request.viewport.zoomScale.pointsPerSecond,
            scale: Self.densityBucketScale
        )
        contentWidthBucket = Self.bucket(
            request.viewport.contentWidth,
            scale: Self.layoutBucketScale
        )
        thumbnailWidthBucket = Self.bucket(
            request.thumbnailWidth,
            scale: Self.layoutBucketScale
        )
        self.targetFrameCount = max(targetFrameCount ?? request.targetFrameCount, 1)
        maxPixelSize = request.maxPixelSize
    }

    var cacheKey: NSString {
        [
            sourceVideoPath,
            "t\(requestedTimeLowerBucket)-\(requestedTimeUpperBucket)",
            "pps\(pointsPerSecondBucket)",
            "cw\(contentWidthBucket)",
            "tw\(thumbnailWidthBucket)",
            "fc\(targetFrameCount)",
            "px\(maxPixelSize)"
        ].joined(separator: "|") as NSString
    }

    private static func bucket(
        _ value: Double,
        scale: Double
    ) -> Int {
        guard value.isFinite else {
            return 0
        }

        return Int((value * scale).rounded())
    }
}

private final class CanvasVideoTimelineStripCache {
    private final class Entry {
        let strip: CanvasVideoTimelineStrip
        let cost: Int

        init(strip: CanvasVideoTimelineStrip) {
            self.strip = strip
            self.cost = max(
                strip.frames.reduce(0) { partialResult, frame in
                    partialResult + max(frame.cgImage.width * frame.cgImage.height * 4, 1)
                },
                1
            )
        }
    }

    private let lock = NSLock()
    private let countLimit: Int
    private let costLimit: Int
    private var entries: [NSString: Entry] = [:]
    private var orderedKeys: [NSString] = []
    private var totalCost = 0

    init(
        countLimit: Int = 24,
        costLimit: Int = 96 * 1024 * 1024
    ) {
        self.countLimit = max(countLimit, 1)
        self.costLimit = max(costLimit, 1)
    }

    func strip(
        for key: CanvasVideoTimelineStripCacheKey
    ) -> CanvasVideoTimelineStrip? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key.cacheKey] else {
            return nil
        }

        touch(key.cacheKey)
        return entry.strip
    }

    func insert(
        _ strip: CanvasVideoTimelineStrip,
        for key: CanvasVideoTimelineStripCacheKey
    ) {
        let cacheKey = key.cacheKey
        let entry = Entry(strip: strip)

        lock.lock()
        if let existingEntry = entries[cacheKey] {
            totalCost -= existingEntry.cost
        }
        entries[cacheKey] = entry
        touch(cacheKey)
        totalCost += entry.cost
        evictIfNeeded()
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        orderedKeys.removeAll()
        totalCost = 0
        lock.unlock()
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    private func touch(_ key: NSString) {
        orderedKeys.removeAll { $0 == key }
        orderedKeys.append(key)
    }

    private func evictIfNeeded() {
        while
            entries.count > countLimit || totalCost > costLimit,
            let oldestKey = orderedKeys.first
        {
            orderedKeys.removeFirst()
            guard let removedEntry = entries.removeValue(forKey: oldestKey) else {
                continue
            }
            totalCost -= removedEntry.cost
        }
    }
}

private final class CanvasVideoFrameDecodeSessionCache {
    private let lock = NSLock()
    private let countLimit: Int
    private var sessions: [NSString: CanvasVideoFrameDecodeSession] = [:]
    private var orderedKeys: [NSString] = []

    init(countLimit: Int = 12) {
        self.countLimit = max(countLimit, 1)
    }

    func session(for localFileURL: URL) -> CanvasVideoFrameDecodeSession {
        let standardizedURL = localFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let cacheKey = standardizedURL.path as NSString

        lock.lock()
        if let existingSession = sessions[cacheKey] {
            touch(cacheKey)
            lock.unlock()
            return existingSession
        }

        let session = CanvasVideoFrameDecodeSession(localFileURL: standardizedURL)
        sessions[cacheKey] = session
        touch(cacheKey)
        evictIfNeeded()
        lock.unlock()
        return session
    }

    func removeAll() {
        lock.lock()
        sessions.removeAll()
        orderedKeys.removeAll()
        lock.unlock()
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    private func touch(_ key: NSString) {
        orderedKeys.removeAll { $0 == key }
        orderedKeys.append(key)
    }

    private func evictIfNeeded() {
        while sessions.count > countLimit, let oldestKey = orderedKeys.first {
            orderedKeys.removeFirst()
            sessions.removeValue(forKey: oldestKey)
        }
    }
}

private final class CanvasVideoFrameDecodeSession {
    private enum GeneratorKey: Hashable {
        case posterCommit
        case previewStripThumbnail(maxPixelSize: Int)

        init(quality: CanvasVideoFrameRenderQuality) {
            switch quality {
            case .posterCommit:
                self = .posterCommit
            case let .previewStripThumbnail(maxPixelSize):
                self = .previewStripThumbnail(maxPixelSize: max(maxPixelSize, 1))
            }
        }
    }

    let asset: AVURLAsset
    let filename: String
    let durationSeconds: Double
    let naturalPixelSize: CGSize?

    private let lock = NSLock()
    private var imageGenerators: [GeneratorKey: AVAssetImageGenerator] = [:]

    init(localFileURL: URL) {
        asset = AVURLAsset(url: localFileURL)
        filename = localFileURL.lastPathComponent
        durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
            asset.duration.seconds
        )
        naturalPixelSize = CanvasVideoFrameService.naturalVideoPixelSize(for: asset)
    }

    func frameImage(
        at timeSeconds: Double,
        quality: CanvasVideoFrameRenderQuality
    ) throws -> CanvasVideoFrameImage {
        lock.lock()
        defer { lock.unlock() }

        let imageGenerator = generator(for: quality)
        return try CanvasVideoFrameService.makeFrameImage(
            from: asset,
            filename: filename,
            at: timeSeconds,
            imageGenerator: imageGenerator,
            naturalPixelSize: naturalPixelSize
        )
    }

    func previewStrip(
        frameCount: Int,
        maxPixelSize: Int
    ) throws -> CanvasVideoPreviewStrip {
        lock.lock()
        defer { lock.unlock() }

        let imageGenerator = generator(
            for: .previewStripThumbnail(maxPixelSize: maxPixelSize)
        )
        let sampleTimes = CanvasVideoFrameService.previewSampleTimes(
            durationSeconds: durationSeconds,
            frameCount: max(frameCount, 1)
        )
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try CanvasVideoFrameService.makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator,
                naturalPixelSize: naturalPixelSize
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

    func timelineStrip(
        request: CanvasVideoTimelineStripRequest,
        frameCount: Int
    ) throws -> CanvasVideoTimelineStrip {
        lock.lock()
        defer { lock.unlock() }

        let imageGenerator = generator(
            for: .previewStripThumbnail(maxPixelSize: request.maxPixelSize)
        )
        let sampleTimes = request.sampleTimes(frameCount: frameCount)
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try CanvasVideoFrameService.makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator,
                naturalPixelSize: naturalPixelSize
            )
            return CanvasVideoTimelineStripFrame(
                cgImage: frameImage.cgImage,
                requestedTimeSeconds: sampleTime,
                actualTimeSeconds: frameImage.actualTimeSeconds,
                contentX: request.viewport.contentX(
                    forTimeSeconds: frameImage.actualTimeSeconds
                )
            )
        }
        return CanvasVideoTimelineStrip(
            request: request,
            frames: frames
        )
    }

    private func generator(
        for quality: CanvasVideoFrameRenderQuality
    ) -> AVAssetImageGenerator {
        let generatorKey = GeneratorKey(quality: quality)
        if let existingGenerator = imageGenerators[generatorKey] {
            return existingGenerator
        }

        let generator = CanvasVideoFrameService.makeImageGenerator(
            for: asset,
            quality: quality
        )
        imageGenerators[generatorKey] = generator
        return generator
    }
}

enum CanvasVideoFrameService {
    static let maximumTimelineStripFrameCount = 48

    private static let timelineStripCache = CanvasVideoTimelineStripCache()
    private static let frameDecodeSessionCache = CanvasVideoFrameDecodeSessionCache()

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

        let decodeSession = frameDecodeSession(for: sourceVideoURL)
        return CanvasVideoEditorContext(
            boardID: boardID,
            itemID: item.id,
            sourceVideoURL: sourceVideoURL,
            sourceVideoFilename: sourceVideoFilename,
            currentPosterFilename: item.assetReference.stableAssetFilename,
            currentPosterTimeSeconds: sanitizedTimeSeconds(
                item.posterTimeSeconds ?? 0
            ),
            durationSeconds: decodeSession.durationSeconds,
            naturalPixelSize: decodeSession.naturalPixelSize ?? item.logicalPixelSize
        )
    }

    static func frameImage(
        from localFileURL: URL,
        at timeSeconds: Double,
        quality: CanvasVideoFrameRenderQuality
    ) throws -> CanvasVideoFrameImage {
        try frameDecodeSession(for: localFileURL).frameImage(
            at: timeSeconds,
            quality: quality
        )
    }

    static func previewStrip(
        from localFileURL: URL,
        frameCount: Int,
        maxPixelSize: Int
    ) throws -> CanvasVideoPreviewStrip {
        try frameDecodeSession(for: localFileURL).previewStrip(
            frameCount: frameCount,
            maxPixelSize: maxPixelSize
        )
    }

    static func timelineStrip(
        from localFileURL: URL,
        request: CanvasVideoTimelineStripRequest
    ) throws -> CanvasVideoTimelineStrip {
        let decodeSession = frameDecodeSession(for: localFileURL)
        let normalizedRequest = CanvasVideoTimelineStripRequest(
            viewport: request.viewport.with(
                durationSeconds: decodeSession.durationSeconds
            ),
            thumbnailWidth: request.thumbnailWidth,
            maxPixelSize: request.maxPixelSize,
            overscanWidth: request.overscanWidth
        )
        let targetFrameCount = effectiveTimelineStripFrameCount(
            for: normalizedRequest
        )
        let cacheKey = CanvasVideoTimelineStripCacheKey(
            localFileURL: localFileURL,
            request: normalizedRequest,
            targetFrameCount: targetFrameCount
        )
        if let cachedStrip = timelineStripCache.strip(for: cacheKey) {
            return cachedStrip
        }

        let strip = try decodeSession.timelineStrip(
            request: normalizedRequest,
            frameCount: targetFrameCount
        )
        timelineStripCache.insert(strip, for: cacheKey)
        return strip
    }

    static func timelineStripCacheEntryCount() -> Int {
        timelineStripCache.entryCount
    }

    static func resetTimelineStripCache() {
        timelineStripCache.removeAll()
    }

    static func frameDecodeSessionEntryCount() -> Int {
        frameDecodeSessionCache.entryCount
    }

    static func resetFrameDecodeSessionCache() {
        frameDecodeSessionCache.removeAll()
    }

    static func timelineStripCacheKeyDescription(
        from localFileURL: URL,
        request: CanvasVideoTimelineStripRequest
    ) -> String {
        CanvasVideoTimelineStripCacheKey(
            localFileURL: localFileURL,
            request: request,
            targetFrameCount: effectiveTimelineStripFrameCount(for: request)
        ).cacheKey as String
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

    fileprivate static func makeFrameImage(
        from asset: AVAsset,
        filename: String,
        at timeSeconds: Double,
        imageGenerator: AVAssetImageGenerator,
        naturalPixelSize: CGSize?
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
            logicalPixelSize: naturalPixelSize ?? CGSize(
                width: cgImage.width,
                height: cgImage.height
            ),
            requestedTimeSeconds: clampedTimeSeconds,
            actualTimeSeconds: actualTimeSeconds
        )
    }

    fileprivate static func makeImageGenerator(
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

    fileprivate static func previewSampleTimes(
        durationSeconds: Double,
        frameCount: Int
    ) -> [Double] {
        let upperBound = previewUpperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
        return CanvasVideoTimelineMath.evenlySpacedSampleTimes(
            in: 0...upperBound,
            frameCount: frameCount
        )
    }

    private static func frameDecodeSession(
        for localFileURL: URL
    ) -> CanvasVideoFrameDecodeSession {
        frameDecodeSessionCache.session(for: localFileURL)
    }

    private static func effectiveTimelineStripFrameCount(
        for request: CanvasVideoTimelineStripRequest
    ) -> Int {
        min(max(request.targetFrameCount, 1), maximumTimelineStripFrameCount)
    }

    private static func sanitizedTimeSeconds(
        _ timeSeconds: Double
    ) -> Double {
        CanvasVideoTimelineMath.sanitizedTimeSeconds(timeSeconds)
    }

    private static func sanitizedDurationSeconds(
        _ duration: CMTime
    ) -> Double {
        CanvasVideoTimelineMath.sanitizedDurationSeconds(duration.seconds)
    }

    private static func clampedTimeSeconds(
        _ timeSeconds: Double,
        for asset: AVAsset
    ) -> Double {
        CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: sanitizedDurationSeconds(asset.duration)
        )
    }

    private static func previewUpperBoundTimeSeconds(
        durationSeconds: Double
    ) -> Double {
        CanvasVideoTimelineMath.upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
    }

    fileprivate static func naturalVideoPixelSize(
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
