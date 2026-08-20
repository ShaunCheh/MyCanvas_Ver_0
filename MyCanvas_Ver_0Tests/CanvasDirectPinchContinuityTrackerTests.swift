import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasDirectPinchContinuityTrackerTests: XCTestCase {
    func testStableTwoTouchSamplesProduceContinuousTransform() throws {
        var tracker = CanvasDirectPinchContinuityTracker<Int>()

        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    touchIDs: [1, 2],
                    rawScale: 1,
                    timestamp: 10,
                    anchor: CGPoint(x: 100, y: 120)
                )
            ),
            .rebaselined
        )

        let decision = tracker.consume(
            makeSample(
                touchIDs: [1, 2],
                rawScale: 1.25,
                timestamp: 10.02,
                anchor: CGPoint(x: 106, y: 116)
            )
        )
        guard case let .transform(delta) = decision else {
            return XCTFail("Expected a continuous transform, got \(decision)")
        }

        XCTAssertEqual(delta.translationInViewport.x, 6, accuracy: 0.0001)
        XCTAssertEqual(delta.translationInViewport.y, -4, accuracy: 0.0001)
        XCTAssertEqual(delta.rawScaleDelta, 1.25, accuracy: 0.0001)
        XCTAssertEqual(delta.sampleInterval, 0.02, accuracy: 0.0001)
        XCTAssertEqual(delta.anchorInViewport, CGPoint(x: 106, y: 116))
    }

    func testDroppingToOneTouchSuppressesTransformAndRequiresRebaseline() {
        var tracker = CanvasDirectPinchContinuityTracker<Int>()
        _ = tracker.consume(
            makeSample(
                touchIDs: [1, 2],
                rawScale: 1,
                timestamp: 0,
                anchor: CGPoint(x: 100, y: 100)
            )
        )

        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    recognizerTouchCount: 1,
                    touchIDs: [2],
                    rawScale: 1,
                    timestamp: 0.01,
                    anchor: CGPoint(x: 180, y: 130)
                )
            ),
            .suppressed(.unstableTouchCount)
        )
        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    touchIDs: [1, 2],
                    rawScale: 1.1,
                    timestamp: 0.02,
                    anchor: CGPoint(x: 104, y: 102)
                )
            ),
            .rebaselined
        )
    }

    func testReplacingTouchSetRebaselinesWithoutCrossSetTranslation() {
        var tracker = CanvasDirectPinchContinuityTracker<Int>()
        _ = tracker.consume(
            makeSample(
                touchIDs: [1, 2],
                rawScale: 1,
                timestamp: 0,
                anchor: CGPoint(x: 100, y: 100)
            )
        )

        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    touchIDs: [2, 3],
                    rawScale: 1.4,
                    timestamp: 0.01,
                    anchor: CGPoint(x: 170, y: 140)
                )
            ),
            .rebaselined
        )
    }

    func testInvalidScaleClearsExistingBaseline() {
        var tracker = CanvasDirectPinchContinuityTracker<Int>()
        _ = tracker.consume(
            makeSample(
                touchIDs: [1, 2],
                rawScale: 1,
                timestamp: 0,
                anchor: CGPoint(x: 100, y: 100)
            )
        )

        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    touchIDs: [1, 2],
                    rawScale: .nan,
                    timestamp: 0.01,
                    anchor: CGPoint(x: 101, y: 101)
                )
            ),
            .suppressed(.invalidScale)
        )
        XCTAssertEqual(
            tracker.consume(
                makeSample(
                    touchIDs: [1, 2],
                    rawScale: 1.1,
                    timestamp: 0.02,
                    anchor: CGPoint(x: 102, y: 102)
                )
            ),
            .rebaselined
        )
    }

    private func makeSample(
        recognizerTouchCount: Int = 2,
        touchIDs: Set<Int>,
        rawScale: CGFloat,
        timestamp: TimeInterval,
        anchor: CGPoint
    ) -> CanvasDirectPinchSample<Int> {
        CanvasDirectPinchSample(
            recognizerTouchCount: recognizerTouchCount,
            activeTouchIDs: touchIDs,
            rawScale: rawScale,
            timestamp: timestamp,
            anchorInViewport: anchor
        )
    }
}
