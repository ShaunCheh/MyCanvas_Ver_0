import CoreGraphics
import Foundation

enum HandDrawingStrokeGeometry {
    private static let polygonBoundaryTolerance: CGFloat = 0.75

    static func intersectsCircle(
        _ stroke: HandDrawingStroke,
        center: CGPoint,
        radius: CGFloat
    ) -> Bool {
        guard let strokeBounds = stroke.bounds else {
            return false
        }

        let resolvedRadius = max(radius, 0.25)
        let expandedBounds = CGRect(
            x: center.x - resolvedRadius,
            y: center.y - resolvedRadius,
            width: resolvedRadius * 2,
            height: resolvedRadius * 2
        )
        guard strokeBounds.intersects(expandedBounds) else {
            return false
        }

        let transformedPoints = stroke.transformedSamplePoints
        if transformedPoints.isEmpty {
            return false
        }

        for (index, point) in transformedPoints.enumerated() {
            let strokeRadius = stroke.radiusForSample(at: index)
            if distanceBetween(point, center) <= strokeRadius + resolvedRadius {
                return true
            }
        }

        guard transformedPoints.count > 1 else {
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
                center,
                toSegmentFrom: startPoint,
                to: endPoint
            )
            if distanceToSegment <= strokeRadius + resolvedRadius {
                return true
            }
        }

        return false
    }

    static func contains(
        _ point: CGPoint,
        in stroke: HandDrawingStroke,
        padding: CGFloat = 0
    ) -> Bool {
        intersectsCircle(
            stroke,
            center: point,
            radius: max(padding, 0.25)
        )
    }

    static func isStroke(
        _ stroke: HandDrawingStroke,
        enclosedBy polygonPoints: [CGPoint]
    ) -> Bool {
        let resolvedPolygonPoints = normalizedPolygonPoints(polygonPoints)
        guard
            resolvedPolygonPoints.count >= 3,
            let strokeBounds = stroke.bounds
        else {
            return false
        }

        let polygonBounds = bounds(for: resolvedPolygonPoints)
        guard polygonBounds.intersects(strokeBounds) else {
            return false
        }

        let transformedPoints = stroke.transformedSamplePoints
        guard transformedPoints.isEmpty == false else {
            return false
        }

        for (index, point) in transformedPoints.enumerated() {
            let radius = stroke.radiusForSample(at: index)
            guard probePoints(around: point, radius: radius).allSatisfy({
                contains($0, inPolygon: resolvedPolygonPoints)
            }) else {
                return false
            }
        }

        guard transformedPoints.count > 1 else {
            return true
        }

        let segmentFractions: [CGFloat] = [0.25, 0.5, 0.75]
        for index in 1..<transformedPoints.count {
            let startPoint = transformedPoints[index - 1]
            let endPoint = transformedPoints[index]
            let segmentRadius = max(
                stroke.radiusForSample(at: index - 1),
                stroke.radiusForSample(at: index)
            )
            for fraction in segmentFractions {
                let sampledPoint = interpolatedPoint(
                    from: startPoint,
                    to: endPoint,
                    fraction: fraction
                )
                guard probePoints(around: sampledPoint, radius: segmentRadius).allSatisfy({
                    contains($0, inPolygon: resolvedPolygonPoints)
                }) else {
                    return false
                }
            }
        }

        return true
    }

    static func unionBounds(
        for strokes: [HandDrawingStroke]
    ) -> CGRect? {
        strokes.compactMap(\.bounds).reduce(nil) { partialResult, bounds in
            partialResult?.union(bounds) ?? bounds
        }
    }

    static func unionBounds(
        forStrokeIDs strokeIDs: Set<UUID>,
        in strokes: [HandDrawingStroke]
    ) -> CGRect? {
        unionBounds(
            for: strokes.filter { strokeIDs.contains($0.id) }
        )
    }

    private static func normalizedPolygonPoints(
        _ points: [CGPoint]
    ) -> [CGPoint] {
        var resolvedPoints: [CGPoint] = []
        for point in points {
            if let lastPoint = resolvedPoints.last,
               distanceBetween(lastPoint, point) < 1
            {
                continue
            }
            resolvedPoints.append(point)
        }
        if
            let firstPoint = resolvedPoints.first,
            let lastPoint = resolvedPoints.last,
            resolvedPoints.count > 1,
            distanceBetween(firstPoint, lastPoint) < 1
        {
            resolvedPoints.removeLast()
        }
        return resolvedPoints
    }

    private static func probePoints(
        around point: CGPoint,
        radius: CGFloat
    ) -> [CGPoint] {
        let resolvedRadius = max(radius, 0.5)
        return [
            point,
            CGPoint(x: point.x + resolvedRadius, y: point.y),
            CGPoint(x: point.x - resolvedRadius, y: point.y),
            CGPoint(x: point.x, y: point.y + resolvedRadius),
            CGPoint(x: point.x, y: point.y - resolvedRadius)
        ]
    }

    private static func contains(
        _ point: CGPoint,
        inPolygon polygonPoints: [CGPoint]
    ) -> Bool {
        let path = CGMutablePath()
        path.addLines(between: polygonPoints)
        path.closeSubpath()
        if path.contains(point) {
            return true
        }
        return distanceToPolygonBoundary(
            point,
            polygonPoints: polygonPoints
        ) <= polygonBoundaryTolerance
    }

    private static func bounds(
        for points: [CGPoint]
    ) -> CGRect {
        points.reduce(into: CGRect.null) { partialResult, point in
            partialResult = partialResult.union(
                CGRect(x: point.x, y: point.y, width: 0, height: 0)
            )
        }
    }

    private static func interpolatedPoint(
        from start: CGPoint,
        to end: CGPoint,
        fraction: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + ((end.x - start.x) * fraction),
            y: start.y + ((end.y - start.y) * fraction)
        )
    }

    private static func distanceToPolygonBoundary(
        _ point: CGPoint,
        polygonPoints: [CGPoint]
    ) -> CGFloat {
        guard polygonPoints.count > 1 else {
            return .greatestFiniteMagnitude
        }

        var minimumDistance = CGFloat.greatestFiniteMagnitude
        for index in polygonPoints.indices {
            let nextIndex = (index + 1) % polygonPoints.count
            let distance = distanceFromPoint(
                point,
                toSegmentFrom: polygonPoints[index],
                to: polygonPoints[nextIndex]
            )
            minimumDistance = min(minimumDistance, distance)
        }
        return minimumDistance
    }

    private static func distanceBetween(
        _ lhs: CGPoint,
        _ rhs: CGPoint
    ) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func distanceFromPoint(
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
}
