import CoreGraphics
import Foundation

struct HandDrawingPixelEraserToolController {
    private var strokePathsByID: [UUID: [UUID: HandDrawingErasePath]] = [:]
    private var openPathIDByStrokeID: [UUID: UUID] = [:]
    private var previousSampleHitStrokeIDs: Set<UUID> = []
    private var hasAppliedMutation = false

    var isActive: Bool {
        strokePathsByID.isEmpty == false || openPathIDByStrokeID.isEmpty == false
    }

    mutating func beginErasing(
        with sample: HandDrawingInputSample,
        baseSize: CGFloat,
        engine: inout HandDrawingEditorEngine
    ) {
        process(samples: [sample], baseSize: baseSize, engine: &engine)
    }

    mutating func appendSamples(
        _ samples: [HandDrawingInputSample],
        baseSize: CGFloat,
        engine: inout HandDrawingEditorEngine
    ) {
        process(samples: samples, baseSize: baseSize, engine: &engine)
    }

    mutating func endErasing() {
        resetSessionState()
    }

    mutating func cancelErasing(
        engine: inout HandDrawingEditorEngine
    ) {
        if hasAppliedMutation {
            _ = engine.undo()
        }
        resetSessionState()
    }

    private mutating func process(
        samples: [HandDrawingInputSample],
        baseSize: CGFloat,
        engine: inout HandDrawingEditorEngine
    ) {
        guard samples.isEmpty == false else {
            return
        }

        var updatedPathsByStrokeID: [UUID: [HandDrawingErasePath]] = [:]
        let document = engine.state.document

        for sample in samples {
            let eraseSample = makeEraseSample(
                from: sample,
                baseSize: baseSize
            )
            let hitStrokeIDs: Set<UUID> = Set(
                document.strokes.compactMap { stroke in
                    guard strokeIntersectsEraseSample(stroke, eraseSample: eraseSample) else {
                        return nil
                    }
                    return stroke.id
                }
            )

            for strokeID in openPathIDByStrokeID.keys where hitStrokeIDs.contains(strokeID) == false {
                openPathIDByStrokeID.removeValue(forKey: strokeID)
            }

            for strokeID in hitStrokeIDs {
                let pathID = resolvedPathID(
                    for: strokeID,
                    hitInPreviousSample: previousSampleHitStrokeIDs.contains(strokeID)
                )
                var strokePaths = strokePathsByID[strokeID] ?? [:]
                var erasePath = strokePaths[pathID] ?? HandDrawingErasePath(
                    id: pathID,
                    samplePoints: []
                )
                if erasePath.samplePoints.last != eraseSample {
                    erasePath.samplePoints.append(eraseSample)
                }
                strokePaths[pathID] = erasePath
                strokePathsByID[strokeID] = strokePaths
                updatedPathsByStrokeID[strokeID, default: []].append(erasePath)
            }

            previousSampleHitStrokeIDs = hitStrokeIDs
        }

        guard updatedPathsByStrokeID.isEmpty == false else {
            return
        }

        let appliedStrokeIDs = engine.upsertErasePaths(
            updatedPathsByStrokeID,
            recordUndo: hasAppliedMutation == false
        )
        if appliedStrokeIDs.isEmpty == false {
            hasAppliedMutation = true
        }
    }

    private mutating func resolvedPathID(
        for strokeID: UUID,
        hitInPreviousSample: Bool
    ) -> UUID {
        if hitInPreviousSample,
           let existingPathID = openPathIDByStrokeID[strokeID]
        {
            return existingPathID
        }
        let newPathID = UUID()
        openPathIDByStrokeID[strokeID] = newPathID
        return newPathID
    }

    private func makeEraseSample(
        from sample: HandDrawingInputSample,
        baseSize: CGFloat
    ) -> HandDrawingEraseSamplePoint {
        let clampedForce = min(max(sample.force, 0.05), 1)
        let pressureScale = 0.5 + clampedForce
        let radius = max((baseSize * pressureScale) / 2, 0.25)
        return HandDrawingEraseSamplePoint(
            point: sample.location,
            radius: Double(radius),
            opacity: 1
        )
    }

    private func strokeIntersectsEraseSample(
        _ stroke: HandDrawingStroke,
        eraseSample: HandDrawingEraseSamplePoint
    ) -> Bool {
        HandDrawingStrokeGeometry.intersectsCircle(
            stroke,
            center: eraseSample.cgPoint,
            radius: eraseSample.resolvedRadius
        )
    }

    private mutating func resetSessionState() {
        strokePathsByID.removeAll()
        openPathIDByStrokeID.removeAll()
        previousSampleHitStrokeIDs.removeAll()
        hasAppliedMutation = false
    }
}
