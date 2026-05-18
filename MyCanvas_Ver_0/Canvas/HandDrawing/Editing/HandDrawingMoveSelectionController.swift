import CoreGraphics
import Foundation

struct HandDrawingMoveSelectionController {
    private enum Layout {
        static let hitPadding: CGFloat = 12
    }

    private var lastSampleLocation: CGPoint?
    private var hasAppliedMutation = false

    var isActive: Bool {
        lastSampleLocation != nil
    }

    mutating func beginMoving(
        with sample: HandDrawingInputSample,
        engine: HandDrawingEditorEngine
    ) -> Bool {
        guard engine.canInteractWithActiveLayer else {
            return false
        }
        let selectedStrokeIDs = engine.state.selectedStrokeIDs
        guard selectedStrokeIDs.isEmpty == false else {
            return false
        }

        let selectedStrokes = engine.state.document.activeLayerStrokes.filter {
            selectedStrokeIDs.contains($0.id)
        }
        let didHitSelectedStroke = selectedStrokes.contains { stroke in
            HandDrawingStrokeGeometry.contains(
                sample.location,
                in: stroke,
                padding: Layout.hitPadding
            )
        }
        guard didHitSelectedStroke else {
            return false
        }

        lastSampleLocation = sample.location
        hasAppliedMutation = false
        return true
    }

    mutating func appendSamples(
        _ samples: [HandDrawingInputSample],
        engine: inout HandDrawingEditorEngine
    ) {
        guard
            samples.isEmpty == false,
            let initialLastLocation = lastSampleLocation
        else {
            return
        }

        var resolvedLastLocation = initialLastLocation
        for sample in samples {
            let delta = CGPoint(
                x: sample.location.x - resolvedLastLocation.x,
                y: sample.location.y - resolvedLastLocation.y
            )
            let movedStrokeIDs = engine.translateSelectedStrokes(
                by: delta,
                recordUndo: hasAppliedMutation == false
            )
            if movedStrokeIDs.isEmpty == false {
                hasAppliedMutation = true
            }
            resolvedLastLocation = sample.location
        }

        lastSampleLocation = resolvedLastLocation
    }

    mutating func endMoving() {
        reset()
    }

    mutating func cancelMoving(
        engine: inout HandDrawingEditorEngine
    ) {
        if hasAppliedMutation {
            _ = engine.undo()
        }
        reset()
    }

    private mutating func reset() {
        lastSampleLocation = nil
        hasAppliedMutation = false
    }
}
