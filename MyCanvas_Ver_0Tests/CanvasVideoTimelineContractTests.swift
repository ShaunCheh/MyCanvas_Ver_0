import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoTimelineContractTests: XCTestCase {
    func testTimelineScaleClampsZoomAndCalculatesNominalDensity() {
        let scale = CanvasVideoTimelineScale(
            zoomScale: 100,
            basePointsPerSecond: 20,
            minZoomScale: 1,
            maxZoomScale: 4
        )

        XCTAssertEqual(scale.zoomScale, 4)
        XCTAssertEqual(scale.pointsPerSecond, 80)
        XCTAssertEqual(scale.nominalSecondsPerPoint, 0.0125, accuracy: 0.0001)
    }

    func testTimelineViewportMapsTimeToContentXAndBack() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 20,
            playheadTimeSeconds: 6,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 2,
                basePointsPerSecond: 10,
                minZoomScale: 1,
                maxZoomScale: 4
            ),
            visibleWidth: 160,
            contentOffsetX: 40,
            minimumContentWidth: 160
        )

        let contentX = viewport.contentX(forTimeSeconds: 8)
        let roundTrippedTime = viewport.timeSeconds(forContentX: contentX)

        XCTAssertEqual(contentX, 160, accuracy: 0.05)
        XCTAssertEqual(
            roundTrippedTime,
            CanvasVideoTimelineViewport.clampedTimeSeconds(
                8,
                durationSeconds: 20
            ),
            accuracy: 0.001
        )
    }

    func testTimelineViewportComputesVisibleTimeRangeFromViewportGeometry() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 30,
            playheadTimeSeconds: 8,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 1,
                basePointsPerSecond: 10
            ),
            visibleWidth: 120,
            contentOffsetX: 60,
            minimumContentWidth: 120
        )

        XCTAssertEqual(viewport.visibleTimeRange.lowerBound, 6, accuracy: 0.05)
        XCTAssertEqual(viewport.visibleTimeRange.upperBound, 18, accuracy: 0.05)
        XCTAssertEqual(viewport.centeredContentOffsetX(for: 12), 60, accuracy: 0.05)
    }

    func testTimelineStripRequestDerivesRequestedRangeAndFrameCount() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 30,
            playheadTimeSeconds: 10,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 1,
                basePointsPerSecond: 10
            ),
            visibleWidth: 120,
            contentOffsetX: 60,
            minimumContentWidth: 120
        )
        let request = CanvasVideoTimelineStripRequest(
            viewport: viewport,
            thumbnailWidth: 40,
            maxPixelSize: 180,
            overscanWidth: 20
        )

        XCTAssertEqual(request.targetFrameCount, 5)
        XCTAssertEqual(request.requestedTimeRange.lowerBound, 4, accuracy: 0.05)
        XCTAssertEqual(request.requestedTimeRange.upperBound, 20, accuracy: 0.05)
        XCTAssertEqual(request.sampleTimes().count, 5)
    }

    func testTimelineStripResultSelectsSampleNearestToPlayhead() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 20,
            playheadTimeSeconds: 11.6,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 1,
                basePointsPerSecond: 10
            ),
            visibleWidth: 120,
            contentOffsetX: 0,
            minimumContentWidth: 120
        )
        let request = CanvasVideoTimelineStripRequest(
            viewport: viewport,
            thumbnailWidth: 40,
            maxPixelSize: 180
        )
        let result = CanvasVideoTimelineStripResult(
            request: request,
            sampleTimes: [0, 5, 10, 15, 19.5]
        )

        XCTAssertEqual(result.highlightedSampleIndex, 2)
        XCTAssertEqual(
            result.samples[result.highlightedSampleIndex ?? 0].timeSeconds,
            10,
            accuracy: 0.001
        )
    }
}
