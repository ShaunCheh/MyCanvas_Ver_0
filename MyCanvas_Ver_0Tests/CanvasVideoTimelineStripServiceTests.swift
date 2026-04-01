import AVFoundation
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoTimelineStripServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CanvasVideoFrameService.resetTimelineStripCache()
        CanvasVideoFrameService.resetFrameDecodeSessionCache()
    }

    override func tearDown() {
        CanvasVideoFrameService.resetTimelineStripCache()
        CanvasVideoFrameService.resetFrameDecodeSessionCache()
        super.tearDown()
    }

    func testTimelineStripCachesRepeatedRequestForSameVideo() throws {
        let videoURL = try makeTestVideoURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try writeTestVideo(to: videoURL)

        let request = makeTimelineStripRequest(
            durationSeconds: resolvedDurationSeconds(for: videoURL),
            playheadTimeSeconds: 0.8,
            zoomScale: 1,
            visibleWidth: 30,
            contentOffsetX: 2,
            overscanWidth: 8
        )

        let firstStrip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )
        XCTAssertEqual(CanvasVideoFrameService.timelineStripCacheEntryCount(), 1)

        let secondStrip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )

        XCTAssertEqual(CanvasVideoFrameService.timelineStripCacheEntryCount(), 1)
        XCTAssertEqual(
            firstStrip.frames.map(\.actualTimeSeconds),
            secondStrip.frames.map(\.actualTimeSeconds)
        )
        XCTAssertEqual(
            firstStrip.frames.map(\.contentX),
            secondStrip.frames.map(\.contentX)
        )
    }

    func testTimelineStripCacheKeyChangesWhenZoomOrTimeRangeChanges() {
        let videoURL = URL(fileURLWithPath: "/tmp/timeline-cache-key.mov")
        let baseRequest = makeTimelineStripRequest(
            durationSeconds: 10,
            playheadTimeSeconds: 2,
            zoomScale: 1,
            visibleWidth: 30,
            contentOffsetX: 0,
            overscanWidth: 8
        )
        let zoomedRequest = makeTimelineStripRequest(
            durationSeconds: 10,
            playheadTimeSeconds: 2,
            zoomScale: 2,
            visibleWidth: 30,
            contentOffsetX: 0,
            overscanWidth: 8
        )
        let shiftedRequest = makeTimelineStripRequest(
            durationSeconds: 10,
            playheadTimeSeconds: 2,
            zoomScale: 1,
            visibleWidth: 30,
            contentOffsetX: 12,
            overscanWidth: 8
        )

        let baseKey = CanvasVideoFrameService.timelineStripCacheKeyDescription(
            from: videoURL,
            request: baseRequest
        )
        let zoomedKey = CanvasVideoFrameService.timelineStripCacheKeyDescription(
            from: videoURL,
            request: zoomedRequest
        )
        let shiftedKey = CanvasVideoFrameService.timelineStripCacheKeyDescription(
            from: videoURL,
            request: shiftedRequest
        )

        XCTAssertNotEqual(baseKey, zoomedKey)
        XCTAssertNotEqual(baseKey, shiftedKey)
        XCTAssertNotEqual(zoomedKey, shiftedKey)
    }

    func testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan() throws {
        let videoURL = try makeTestVideoURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try writeTestVideo(to: videoURL)

        let actualDurationSeconds = resolvedDurationSeconds(for: videoURL)
        let request = makeTimelineStripRequest(
            durationSeconds: 999,
            playheadTimeSeconds: 1,
            zoomScale: 1.5,
            visibleWidth: 30,
            contentOffsetX: 4,
            overscanWidth: 10
        )

        let strip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )

        XCTAssertEqual(
            strip.request.viewport.durationSeconds,
            actualDurationSeconds,
            accuracy: 0.01
        )
        XCTAssertLessThanOrEqual(
            strip.request.requestedTimeRange.lowerBound,
            strip.request.visibleTimeRange.lowerBound
        )
        XCTAssertGreaterThanOrEqual(
            strip.request.requestedTimeRange.upperBound,
            strip.request.visibleTimeRange.upperBound
        )
        XCTAssertEqual(
            strip.frames.count,
            min(
                strip.request.targetFrameCount,
                CanvasVideoFrameService.maximumTimelineStripFrameCount
            )
        )
        XCTAssertTrue(strip.frames.isEmpty == false)
        XCTAssertTrue(framesAreMonotonic(strip.frames))
    }

    func testFrameDecodeSessionCacheReusesSessionForRepeatedFrameRequests() throws {
        let videoURL = try makeTestVideoURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try writeTestVideo(to: videoURL)

        _ = try CanvasVideoFrameService.frameImage(
            from: videoURL,
            at: 0.2,
            quality: .posterCommit
        )
        _ = try CanvasVideoFrameService.frameImage(
            from: videoURL,
            at: 0.8,
            quality: .previewStripThumbnail(maxPixelSize: 48)
        )

        XCTAssertEqual(CanvasVideoFrameService.frameDecodeSessionEntryCount(), 1)
    }

    func testTimelineStripCapsFrameCountForExtremelyWideViewportRequests() throws {
        let videoURL = try makeTestVideoURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try writeTestVideo(to: videoURL)

        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: resolvedDurationSeconds(for: videoURL),
            playheadTimeSeconds: 0.8,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 32,
                basePointsPerSecond: 180,
                minZoomScale: 1,
                maxZoomScale: 64
            ),
            visibleWidth: 3_000,
            contentOffsetX: 100,
            minimumContentWidth: 1
        )
        let request = CanvasVideoTimelineStripRequest(
            viewport: viewport,
            thumbnailWidth: 10,
            maxPixelSize: 48,
            overscanWidth: 1_500
        )

        XCTAssertGreaterThan(
            request.targetFrameCount,
            CanvasVideoFrameService.maximumTimelineStripFrameCount
        )

        let strip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )

        XCTAssertEqual(
            strip.frames.count,
            CanvasVideoFrameService.maximumTimelineStripFrameCount
        )
    }
}

private enum CanvasVideoTimelineStripServiceTestError: Error {
    case failedToAddInput
    case failedToCreatePixelBuffer
    case failedToStartWriting
    case failedToAppendFrame(Int)
    case failedToFinishWriting
}

private func makeTimelineStripRequest(
    durationSeconds: Double,
    playheadTimeSeconds: Double,
    zoomScale: Double,
    visibleWidth: Double,
    contentOffsetX: Double,
    overscanWidth: Double,
    thumbnailWidth: Double = 10,
    maxPixelSize: Int = 48
) -> CanvasVideoTimelineStripRequest {
    let viewport = CanvasVideoTimelineViewport(
        durationSeconds: durationSeconds,
        playheadTimeSeconds: playheadTimeSeconds,
        zoomScale: CanvasVideoTimelineScale(
            zoomScale: zoomScale,
            basePointsPerSecond: 18,
            minZoomScale: 1,
            maxZoomScale: 8
        ),
        visibleWidth: visibleWidth,
        contentOffsetX: contentOffsetX,
        minimumContentWidth: 1
    )
    return CanvasVideoTimelineStripRequest(
        viewport: viewport,
        thumbnailWidth: thumbnailWidth,
        maxPixelSize: maxPixelSize,
        overscanWidth: overscanWidth
    )
}

private func makeTestVideoURL() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    return directoryURL.appendingPathComponent("timeline-strip.mov")
}

private func resolvedDurationSeconds(for videoURL: URL) -> Double {
    let durationSeconds = AVURLAsset(url: videoURL).duration.seconds
    if durationSeconds.isFinite, durationSeconds > 0 {
        return durationSeconds
    }

    return 0
}

private func writeTestVideo(
    to videoURL: URL,
    frameCount: Int = 24,
    frameRate: Int32 = 12,
    width: Int = 24,
    height: Int = 24
) throws {
    let writer = try AVAssetWriter(url: videoURL, fileType: .mov)
    let outputSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: outputSettings
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    guard writer.canAdd(input) else {
        throw CanvasVideoTimelineStripServiceTestError.failedToAddInput
    }
    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error ?? CanvasVideoTimelineStripServiceTestError.failedToStartWriting
    }
    writer.startSession(atSourceTime: .zero)

    for frameIndex in 0..<frameCount {
        while input.isReadyForMoreMediaData == false {
            Thread.sleep(forTimeInterval: 0.001)
        }

        let red = UInt8((frameIndex * 17) % 255)
        let green = UInt8((frameIndex * 29) % 255)
        let blue = UInt8((frameIndex * 41) % 255)
        let pixelBuffer = try makeSolidColorPixelBuffer(
            width: width,
            height: height,
            red: red,
            green: green,
            blue: blue
        )
        let presentationTime = CMTime(
            value: CMTimeValue(frameIndex),
            timescale: frameRate
        )
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? CanvasVideoTimelineStripServiceTestError
                .failedToAppendFrame(frameIndex)
        }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()

    guard writer.status == .completed else {
        throw writer.error ?? CanvasVideoTimelineStripServiceTestError.failedToFinishWriting
    }
}

private func makeSolidColorPixelBuffer(
    width: Int,
    height: Int,
    red: UInt8,
    green: UInt8,
    blue: UInt8
) throws -> CVPixelBuffer {
    var maybePixelBuffer: CVPixelBuffer?
    let attributes = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ] as CFDictionary
    let status = CVPixelBufferCreate(
        nil,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes,
        &maybePixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
        throw CanvasVideoTimelineStripServiceTestError.failedToCreatePixelBuffer
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw CanvasVideoTimelineStripServiceTestError.failedToCreatePixelBuffer
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for row in 0..<height {
        for column in 0..<width {
            let pixelOffset = (row * bytesPerRow) + (column * 4)
            buffer[pixelOffset] = blue
            buffer[pixelOffset + 1] = green
            buffer[pixelOffset + 2] = red
            buffer[pixelOffset + 3] = 255
        }
    }

    return pixelBuffer
}

private func framesAreMonotonic(
    _ frames: [CanvasVideoTimelineStripFrame]
) -> Bool {
    guard frames.count > 1 else {
        return true
    }

    for (previousFrame, nextFrame) in zip(frames, frames.dropFirst()) {
        guard
            previousFrame.actualTimeSeconds <= nextFrame.actualTimeSeconds,
            previousFrame.contentX <= nextFrame.contentX
        else {
            return false
        }
    }

    return true
}
