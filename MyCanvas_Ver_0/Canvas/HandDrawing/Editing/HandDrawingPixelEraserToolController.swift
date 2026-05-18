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
        guard let strokeBounds = stroke.bounds else {
            return false
        }

        let expandedSampleBounds = CGRect(
            x: eraseSample.cgPoint.x - eraseSample.resolvedRadius,
            y: eraseSample.cgPoint.y - eraseSample.resolvedRadius,
            width: eraseSample.resolvedRadius * 2,
            height: eraseSample.resolvedRadius * 2
        )
        guard strokeBounds.intersects(expandedSampleBounds) else {
            return false
        }

        let transformedPoints = stroke.transformedSamplePoints
        if transformedPoints.isEmpty {
            return false
        }

        let eraseCenter = eraseSample.cgPoint
        let eraseRadius = eraseSample.resolvedRadius

        for (index, point) in transformedPoints.enumerated() {
            let strokeRadius = stroke.radiusForSample(at: index)
            if distanceBetween(point, eraseCenter) <= strokeRadius + eraseRadius {
                return true
            }
        }

        if transformedPoints.count == 1 {
            return false
        }

        for index in 1..<transformedPoints.count {
            let startPoint = transformedPoints[index - 1]
            let endPoint = transformedPoints[index]
            let strokeRadius = max(
                stroke.radiusForSample(at: index - 1),
                stroke.radiusForSample(at: index)
            )
            let distanceToSegment = distanceFromPoint(
                eraseCenter,
                toSegmentFrom: startPoint,
                to: endPoint
            )
            if distanceToSegment <= strokeRadius + eraseRadius {
                return true
            }
        }

        return false
    }

    private func distanceBetween(
        _ lhs: CGPoint,
        _ rhs: CGPoint
    ) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distanceFromPoint(
        _ point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else {
            return distanceBetween(point, start)
        }
        let projection = (
            ((point.x - start.x) * deltaX) + ((point.y - start.y) * deltaY)
        ) / lengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let projectedPoint = CGPoint(
            x: start.x + (deltaX * clampedProjection),
            y: start.y + (deltaY * clampedProjection)
        )
        return distanceBetween(point, projectedPoint)
    }

    private mutating func resetSessionState() {
        strokePathsByID.removeAll()
        openPathIDByStrokeID.removeAll()
        previousSampleHitStrokeIDs.removeAll()
        hasAppliedMutation = false
    }
}
