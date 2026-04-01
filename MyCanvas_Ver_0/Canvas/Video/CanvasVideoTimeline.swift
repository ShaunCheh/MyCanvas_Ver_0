import CoreGraphics
import Foundation

enum CanvasVideoTimelineMath {
    static let frameBoundaryEpsilonSeconds = 1.0 / 600.0

    static func sanitizedTimeSeconds(_ timeSeconds: Double) -> Double {
        guard timeSeconds.isFinite else {
            return 0
        }

        return max(timeSeconds, 0)
    }

    static func sanitizedDurationSeconds(_ durationSeconds: Double) -> Double {
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return 0
        }

        return durationSeconds
    }

    static func upperBoundTimeSeconds(durationSeconds: Double) -> Double {
        let durationSeconds = sanitizedDurationSeconds(durationSeconds)
        guard durationSeconds > 0 else {
            return 0
        }

        return max(durationSeconds - frameBoundaryEpsilonSeconds, 0)
    }

    static func clampedTimeSeconds(
        _ timeSeconds: Double,
        durationSeconds: Double
    ) -> Double {
        let upperBoundTimeSeconds = upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
        guard upperBoundTimeSeconds > 0 else {
            return 0
        }

        return min(
            sanitizedTimeSeconds(timeSeconds),
            upperBoundTimeSeconds
        )
    }

    static func evenlySpacedSampleTimes(
        in timeRange: ClosedRange<Double>,
        frameCount: Int
    ) -> [Double] {
        let frameCount = max(frameCount, 1)
        let lowerBound = min(timeRange.lowerBound, timeRange.upperBound)
        let upperBound = max(timeRange.lowerBound, timeRange.upperBound)
        guard lowerBound.isFinite, upperBound.isFinite else {
            return Array(repeating: 0, count: frameCount)
        }
        guard frameCount > 1 else {
            return [lowerBound]
        }
        guard upperBound > lowerBound else {
            return Array(repeating: lowerBound, count: frameCount)
        }

        let denominator = Double(frameCount - 1)
        return (0..<frameCount).map { index in
            lowerBound + ((upperBound - lowerBound) * Double(index) / denominator)
        }
    }
}

struct CanvasVideoTimelineScale: Equatable {
    static let defaultBasePointsPerSecond = 18.0
    static let defaultMinZoomScale = 1.0
    static let defaultMaxZoomScale = 32.0
    static let `default` = CanvasVideoTimelineScale()

    let zoomScale: Double
    let basePointsPerSecond: Double
    let minZoomScale: Double
    let maxZoomScale: Double

    init(
        zoomScale: Double = 1,
        basePointsPerSecond: Double = CanvasVideoTimelineScale
            .defaultBasePointsPerSecond,
        minZoomScale: Double = CanvasVideoTimelineScale.defaultMinZoomScale,
        maxZoomScale: Double = CanvasVideoTimelineScale.defaultMaxZoomScale
    ) {
        let sanitizedBasePointsPerSecond = basePointsPerSecond.isFinite
            ? max(basePointsPerSecond, 1)
            : CanvasVideoTimelineScale.defaultBasePointsPerSecond
        let sanitizedMinZoomScale = minZoomScale.isFinite
            ? max(minZoomScale, 0.01)
            : CanvasVideoTimelineScale.defaultMinZoomScale
        let sanitizedMaxZoomScale = maxZoomScale.isFinite
            ? max(maxZoomScale, sanitizedMinZoomScale)
            : CanvasVideoTimelineScale.defaultMaxZoomScale
        let sanitizedZoomScale = zoomScale.isFinite
            ? min(
                max(zoomScale, sanitizedMinZoomScale),
                sanitizedMaxZoomScale
            )
            : sanitizedMinZoomScale

        self.zoomScale = sanitizedZoomScale
        self.basePointsPerSecond = sanitizedBasePointsPerSecond
        self.minZoomScale = sanitizedMinZoomScale
        self.maxZoomScale = sanitizedMaxZoomScale
    }

    var pointsPerSecond: Double {
        basePointsPerSecond * zoomScale
    }

    var nominalSecondsPerPoint: Double {
        guard pointsPerSecond > 0 else {
            return 0
        }

        return 1 / pointsPerSecond
    }

    func withZoomScale(_ zoomScale: Double) -> CanvasVideoTimelineScale {
        CanvasVideoTimelineScale(
            zoomScale: zoomScale,
            basePointsPerSecond: basePointsPerSecond,
            minZoomScale: minZoomScale,
            maxZoomScale: maxZoomScale
        )
    }
}

struct CanvasVideoTimelineViewport: Equatable {
    let durationSeconds: Double
    let playheadTimeSeconds: Double
    let zoomScale: CanvasVideoTimelineScale
    let visibleWidth: Double
    let contentOffsetX: Double
    let minimumContentWidth: Double

    init(
        durationSeconds: Double,
        playheadTimeSeconds: Double,
        zoomScale: CanvasVideoTimelineScale = .default,
        visibleWidth: Double,
        contentOffsetX: Double = 0,
        minimumContentWidth: Double? = nil
    ) {
        let sanitizedDurationSeconds = CanvasVideoTimelineMath
            .sanitizedDurationSeconds(durationSeconds)
        let sanitizedVisibleWidth = visibleWidth.isFinite
            ? max(visibleWidth, 0)
            : 0
        let sanitizedMinimumContentWidth = max(
            minimumContentWidth?.isFinite == true
                ? minimumContentWidth ?? 0
                : sanitizedVisibleWidth,
            0
        )

        self.durationSeconds = sanitizedDurationSeconds
        self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            playheadTimeSeconds,
            durationSeconds: sanitizedDurationSeconds
        )
        self.zoomScale = zoomScale
        self.visibleWidth = sanitizedVisibleWidth
        self.minimumContentWidth = sanitizedMinimumContentWidth
        self.contentOffsetX = Self.clampedContentOffsetX(
            contentOffsetX,
            durationSeconds: sanitizedDurationSeconds,
            zoomScale: zoomScale,
            visibleWidth: sanitizedVisibleWidth,
            minimumContentWidth: sanitizedMinimumContentWidth
        )
    }

    var upperBoundTimeSeconds: Double {
        CanvasVideoTimelineMath.upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
    }

    var intrinsicContentWidth: Double {
        upperBoundTimeSeconds * zoomScale.pointsPerSecond
    }

    var contentWidth: Double {
        max(intrinsicContentWidth, minimumContentWidth)
    }

    var maximumContentOffsetX: Double {
        max(contentWidth - visibleWidth, 0)
    }

    var nominalSecondsPerPoint: Double {
        zoomScale.nominalSecondsPerPoint
    }

    var displayedSecondsPerPoint: Double {
        guard contentWidth > 0, upperBoundTimeSeconds > 0 else {
            return 0
        }

        return upperBoundTimeSeconds / contentWidth
    }

    var visibleContentRange: ClosedRange<Double> {
        let lowerBound = min(max(contentOffsetX, 0), contentWidth)
        let upperBound = min(
            max(contentOffsetX + visibleWidth, lowerBound),
            contentWidth
        )
        return lowerBound...upperBound
    }

    var visibleTimeRange: ClosedRange<Double> {
        timeRange(forContentRange: visibleContentRange)
    }

    var playheadContentX: Double {
        contentX(forTimeSeconds: playheadTimeSeconds)
    }

    func contentX(forTimeSeconds timeSeconds: Double) -> Double {
        guard upperBoundTimeSeconds > 0, contentWidth > 0 else {
            return 0
        }

        let clampedTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: durationSeconds
        )
        return (clampedTimeSeconds / upperBoundTimeSeconds) * contentWidth
    }

    func timeSeconds(forContentX contentX: Double) -> Double {
        guard upperBoundTimeSeconds > 0, contentWidth > 0 else {
            return 0
        }

        let clampedContentX = min(max(contentX, 0), contentWidth)
        return (clampedContentX / contentWidth) * upperBoundTimeSeconds
    }

    func timeSeconds(forContentOffsetX contentOffsetX: Double) -> Double {
        timeSeconds(forContentX: contentOffsetX)
    }

    func timeRange(
        forContentRange contentRange: ClosedRange<Double>
    ) -> ClosedRange<Double> {
        let lowerBound = timeSeconds(forContentX: contentRange.lowerBound)
        let upperBound = timeSeconds(forContentX: contentRange.upperBound)
        return lowerBound...max(upperBound, lowerBound)
    }

    func centeredContentOffsetX(for timeSeconds: Double) -> Double {
        let centeredOffsetX = contentX(forTimeSeconds: timeSeconds)
            - (visibleWidth / 2)
        return min(max(centeredOffsetX, 0), maximumContentOffsetX)
    }

    func with(
        durationSeconds: Double? = nil,
        playheadTimeSeconds: Double? = nil,
        zoomScale: CanvasVideoTimelineScale? = nil,
        visibleWidth: Double? = nil,
        contentOffsetX: Double? = nil,
        minimumContentWidth: Double? = nil
    ) -> CanvasVideoTimelineViewport {
        CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds ?? self.durationSeconds,
            playheadTimeSeconds: playheadTimeSeconds ?? self.playheadTimeSeconds,
            zoomScale: zoomScale ?? self.zoomScale,
            visibleWidth: visibleWidth ?? self.visibleWidth,
            contentOffsetX: contentOffsetX ?? self.contentOffsetX,
            minimumContentWidth: minimumContentWidth ?? self.minimumContentWidth
        )
    }

    static func clampedTimeSeconds(
        _ timeSeconds: Double,
        durationSeconds: Double
    ) -> Double {
        CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: durationSeconds
        )
    }

    private static func clampedContentOffsetX(
        _ contentOffsetX: Double,
        durationSeconds: Double,
        zoomScale: CanvasVideoTimelineScale,
        visibleWidth: Double,
        minimumContentWidth: Double
    ) -> Double {
        guard contentOffsetX.isFinite else {
            return 0
        }

        let upperBoundTimeSeconds = CanvasVideoTimelineMath.upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
        let intrinsicContentWidth = upperBoundTimeSeconds * zoomScale.pointsPerSecond
        let contentWidth = max(intrinsicContentWidth, minimumContentWidth)
        let maximumContentOffsetX = max(contentWidth - visibleWidth, 0)
        return min(max(contentOffsetX, 0), maximumContentOffsetX)
    }
}

struct CanvasVideoTimelineStripRequest: Equatable {
    let viewport: CanvasVideoTimelineViewport
    let thumbnailWidth: Double
    let maxPixelSize: Int
    let overscanWidth: Double

    init(
        viewport: CanvasVideoTimelineViewport,
        thumbnailWidth: Double,
        maxPixelSize: Int,
        overscanWidth: Double = 0
    ) {
        self.viewport = viewport
        self.thumbnailWidth = thumbnailWidth.isFinite
            ? max(thumbnailWidth, 1)
            : 1
        self.maxPixelSize = max(maxPixelSize, 1)
        self.overscanWidth = overscanWidth.isFinite
            ? max(overscanWidth, 0)
            : 0
    }

    var visibleContentRange: ClosedRange<Double> {
        viewport.visibleContentRange
    }

    var requestedContentRange: ClosedRange<Double> {
        let lowerBound = max(visibleContentRange.lowerBound - overscanWidth, 0)
        let upperBound = min(
            visibleContentRange.upperBound + overscanWidth,
            viewport.contentWidth
        )
        return lowerBound...max(upperBound, lowerBound)
    }

    var visibleTimeRange: ClosedRange<Double> {
        viewport.visibleTimeRange
    }

    var requestedTimeRange: ClosedRange<Double> {
        viewport.timeRange(forContentRange: requestedContentRange)
    }

    var targetFrameCount: Int {
        let requestedWidth = requestedContentRange.upperBound
            - requestedContentRange.lowerBound
        guard requestedWidth > 0 else {
            return 1
        }

        return max(Int(ceil(requestedWidth / thumbnailWidth)) + 1, 2)
    }

    func sampleTimes(frameCount: Int? = nil) -> [Double] {
        CanvasVideoTimelineMath.evenlySpacedSampleTimes(
            in: requestedTimeRange,
            frameCount: max(frameCount ?? targetFrameCount, 1)
        )
    }
}

struct CanvasVideoTimelineStripResult: Equatable {
    struct Sample: Equatable {
        let timeSeconds: Double
        let contentX: Double
    }

    let request: CanvasVideoTimelineStripRequest
    let samples: [Sample]

    init(
        request: CanvasVideoTimelineStripRequest,
        sampleTimes: [Double]? = nil
    ) {
        self.request = request
        self.samples = (sampleTimes ?? request.sampleTimes()).map { timeSeconds in
            let clampedTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
                timeSeconds,
                durationSeconds: request.viewport.durationSeconds
            )
            return Sample(
                timeSeconds: clampedTimeSeconds,
                contentX: request.viewport.contentX(
                    forTimeSeconds: clampedTimeSeconds
                )
            )
        }
    }

    var contentWidth: Double {
        request.viewport.contentWidth
    }

    var visibleTimeRange: ClosedRange<Double> {
        request.visibleTimeRange
    }

    var highlightedSampleIndex: Int? {
        guard samples.isEmpty == false else {
            return nil
        }

        let playheadContentX = request.viewport.playheadContentX
        return samples.enumerated().min { lhs, rhs in
            abs(lhs.element.contentX - playheadContentX)
                < abs(rhs.element.contentX - playheadContentX)
        }?.offset
    }
}

struct CanvasVideoTimelineStripFrame {
    let cgImage: CGImage
    let requestedTimeSeconds: Double
    let actualTimeSeconds: Double
    let contentX: Double
}

struct CanvasVideoTimelineStrip {
    let request: CanvasVideoTimelineStripRequest
    let frames: [CanvasVideoTimelineStripFrame]

    var visibleTimeRange: ClosedRange<Double> {
        request.visibleTimeRange
    }

    var requestedTimeRange: ClosedRange<Double> {
        request.requestedTimeRange
    }

    var highlightedFrameIndex: Int? {
        guard frames.isEmpty == false else {
            return nil
        }

        let playheadContentX = request.viewport.playheadContentX
        return frames.enumerated().min { lhs, rhs in
            abs(lhs.element.contentX - playheadContentX)
                < abs(rhs.element.contentX - playheadContentX)
        }?.offset
    }
}

enum CanvasVideoTimelinePlaceholderState: Equatable {
    case hidden
    case loading(message: String)
    case message(String)
}
