import CoreGraphics
import Foundation

struct HandDrawingLassoToolController {
    private enum Layout {
        static let minimumPathLength: CGFloat = 24
        static let minimumBoundsExtent: CGFloat = 12
    }

    private(set) var points: [CGPoint] = []

    var isActive: Bool {
        points.isEmpty == false
    }

    @discardableResult
    mutating func beginLasso(
        with sample: HandDrawingInputSample,
        engine: HandDrawingEditorEngine
    ) -> Bool {
        guard engine.canInteractWithActiveLayer else {
            return false
        }
        points = [sample.location]
        return true
    }

    mutating func appendSamples(
        _ samples: [HandDrawingInputSample]
    ) {
        guard
            samples.isEmpty == false,
            points.isEmpty == false
        else {
            return
        }
        for sample in samples {
            if let lastPoint = points.last,
               hypot(lastPoint.x - sample.location.x, lastPoint.y - sample.location.y) < 1
            {
                continue
            }
            points.append(sample.location)
        }
    }

    @discardableResult
    mutating func endLasso(
        engine: inout HandDrawingEditorEngine
    ) -> Bool {
        defer {
            points.removeAll()
        }
        guard
            isMeaningfulLasso,
            engine.canInteractWithActiveLayer
        else {
            return false
        }
        let selectedStrokeIDs: Set<UUID> = Set(
            engine.state.document.activeLayerStrokes.compactMap { stroke in
                guard HandDrawingStrokeGeometry.isStroke(stroke, enclosedBy: points) else {
                    return nil
                }
                return stroke.id
            }
        )
        return engine.selectStrokes(withIDs: selectedStrokeIDs)
    }

    mutating func cancelLasso() {
        points.removeAll()
    }

    private var isMeaningfulLasso: Bool {
        guard points.count >= 3 else {
            return false
        }
        let pathLength = zip(points, points.dropFirst()).reduce(CGFloat.zero) { partialResult, segment in
            partialResult + hypot(segment.0.x - segment.1.x, segment.0.y - segment.1.y)
        }
        guard pathLength >= Layout.minimumPathLength else {
            return false
        }
        let bounds = points.reduce(into: CGRect.null) { partialResult, point in
            partialResult = partialResult.union(
                CGRect(x: point.x, y: point.y, width: 0, height: 0)
            )
        }
        return max(bounds.width, bounds.height) >= Layout.minimumBoundsExtent
    }
}
