import CoreGraphics
import Foundation

enum CanvasDirectPinchSuppressionReason: Equatable {
    case invalidScale
    case unstableTouchCount
}

struct CanvasDirectPinchSample<TouchID: Hashable> {
    let recognizerTouchCount: Int
    let activeTouchIDs: Set<TouchID>
    let rawScale: CGFloat
    let timestamp: TimeInterval
    let anchorInViewport: CGPoint
}

struct CanvasDirectPinchContinuousDelta: Equatable {
    let translationInViewport: CGPoint
    let rawScaleDelta: CGFloat
    let sampleInterval: TimeInterval
    let anchorInViewport: CGPoint
}

enum CanvasDirectPinchDecision: Equatable {
    case rebaselined
    case suppressed(CanvasDirectPinchSuppressionReason)
    case transform(CanvasDirectPinchContinuousDelta)
}

struct CanvasDirectPinchContinuityTracker<TouchID: Hashable> {
    private struct Baseline {
        let touchIDs: Set<TouchID>
        let rawScale: CGFloat
        let timestamp: TimeInterval
        let anchor: CGPoint
    }

    private var baseline: Baseline?

    mutating func consume(
        _ sample: CanvasDirectPinchSample<TouchID>
    ) -> CanvasDirectPinchDecision {
        guard sample.rawScale.isFinite, sample.rawScale > 0 else {
            baseline = nil
            return .suppressed(.invalidScale)
        }

        guard
            sample.recognizerTouchCount == 2,
            sample.activeTouchIDs.count == 2
        else {
            baseline = nil
            return .suppressed(.unstableTouchCount)
        }

        let nextBaseline = Baseline(
            touchIDs: sample.activeTouchIDs,
            rawScale: sample.rawScale,
            timestamp: sample.timestamp,
            anchor: sample.anchorInViewport
        )
        guard
            let previousBaseline = baseline,
            previousBaseline.touchIDs == sample.activeTouchIDs
        else {
            baseline = nextBaseline
            return .rebaselined
        }

        baseline = nextBaseline
        return .transform(
            CanvasDirectPinchContinuousDelta(
                translationInViewport: CGPoint(
                    x: sample.anchorInViewport.x - previousBaseline.anchor.x,
                    y: sample.anchorInViewport.y - previousBaseline.anchor.y
                ),
                rawScaleDelta: sample.rawScale / max(previousBaseline.rawScale, 0.0001),
                sampleInterval: max(sample.timestamp - previousBaseline.timestamp, 0),
                anchorInViewport: sample.anchorInViewport
            )
        )
    }

    mutating func reset() {
        baseline = nil
    }
}
