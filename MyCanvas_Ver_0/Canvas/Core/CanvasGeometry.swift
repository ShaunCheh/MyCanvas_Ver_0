import CoreGraphics
import Foundation

struct CanvasQuad: Equatable {
    let topLeading: CGPoint
    let topTrailing: CGPoint
    let bottomLeading: CGPoint
    let bottomTrailing: CGPoint

    init(
        topLeading: CGPoint,
        topTrailing: CGPoint,
        bottomLeading: CGPoint,
        bottomTrailing: CGPoint
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    init(rect: CGRect) {
        let standardizedRect = rect.standardized
        self.init(
            topLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.minY),
            topTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.minY),
            bottomLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.maxY),
            bottomTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.maxY)
        )
    }

    var points: [CGPoint] {
        [
            topLeading,
            topTrailing,
            bottomTrailing,
            bottomLeading
        ]
    }

    var edges: [(start: CGPoint, end: CGPoint)] {
        [
            (topLeading, topTrailing),
            (topTrailing, bottomTrailing),
            (bottomTrailing, bottomLeading),
            (bottomLeading, topLeading)
        ]
    }

    var center: CGPoint {
        CGPoint(
            x: (topLeading.x + topTrailing.x + bottomLeading.x + bottomTrailing.x) / 4,
            y: (topLeading.y + topTrailing.y + bottomLeading.y + bottomTrailing.y) / 4
        )
    }

    var topMidpoint: CGPoint {
        midpoint(between: topLeading, and: topTrailing)
    }

    var bottomMidpoint: CGPoint {
        midpoint(between: bottomLeading, and: bottomTrailing)
    }

    var leadingMidpoint: CGPoint {
        midpoint(between: topLeading, and: bottomLeading)
    }

    var trailingMidpoint: CGPoint {
        midpoint(between: topTrailing, and: bottomTrailing)
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        path.move(to: topLeading)
        path.addLine(to: topTrailing)
        path.addLine(to: bottomTrailing)
        path.addLine(to: bottomLeading)
        path.closeSubpath()
        return path
    }

    var boundingRect: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)

        guard
            let minX = xs.min(),
            let maxX = xs.max(),
            let minY = ys.min(),
            let maxY = ys.max()
        else {
            return .zero
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    func map(_ transform: (CGPoint) -> CGPoint) -> CanvasQuad {
        CanvasQuad(
            topLeading: transform(topLeading),
            topTrailing: transform(topTrailing),
            bottomLeading: transform(bottomLeading),
            bottomTrailing: transform(bottomTrailing)
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        if cgPath.contains(
            point,
            using: .winding,
            transform: .identity
        ) {
            return true
        }

        return edges.contains { edge in
            canvasDistance(
                from: point,
                toSegmentStart: edge.start,
                segmentEnd: edge.end
            ) <= canvasQuadContainmentEpsilon
        }
    }

    private func midpoint(
        between lhs: CGPoint,
        and rhs: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: (lhs.x + rhs.x) / 2,
            y: (lhs.y + rhs.y) / 2
        )
    }
}

private let canvasQuadContainmentEpsilon: CGFloat = 0.0001

func canvasDistance(
    from point: CGPoint,
    toSegmentStart start: CGPoint,
    segmentEnd end: CGPoint
) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = (dx * dx) + (dy * dy)
    guard lengthSquared > 0 else {
        return hypot(point.x - start.x, point.y - start.y)
    }

    let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    let clampedProjection = min(max(projection, 0), 1)
    let closestPoint = CGPoint(
        x: start.x + (clampedProjection * dx),
        y: start.y + (clampedProjection * dy)
    )
    return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
}

func normalizedCanvasAngle(_ radians: CGFloat) -> CGFloat {
    atan2(sin(radians), cos(radians))
}

func normalizedCanvasDegrees0To360(_ degrees: CGFloat) -> CGFloat {
    let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
    return normalizedDegrees >= 0
        ? normalizedDegrees
        : normalizedDegrees + 360
}

func canvasDisplayDegrees0To360(
    forRotationRadians radians: CGFloat
) -> CGFloat {
    normalizedCanvasDegrees0To360(radians * 180 / .pi)
}

func canvasCircleRect(
    centeredAt center: CGPoint,
    radius: CGFloat
) -> CGRect {
    let resolvedRadius = max(radius, 0)
    return CGRect(
        x: center.x - resolvedRadius,
        y: center.y - resolvedRadius,
        width: resolvedRadius * 2,
        height: resolvedRadius * 2
    ).standardized
}

func canvasPointOnInteractionCircle(
    centeredAt center: CGPoint,
    radius: CGFloat,
    displayDegrees0To360 degrees: CGFloat,
    zeroReference: CanvasInteractionAngleZeroReference = .up
) -> CGPoint {
    let resolvedRadius = max(radius, 0)
    let normalizedDegrees = normalizedCanvasDegrees0To360(degrees)
    let radians = normalizedDegrees * .pi / 180

    switch zeroReference {
    case .up:
        return CGPoint(
            x: center.x + (sin(radians) * resolvedRadius),
            y: center.y - (cos(radians) * resolvedRadius)
        )
    }
}

func canvasRadialSegment(
    centeredAt center: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat,
    displayDegrees0To360 degrees: CGFloat,
    zeroReference: CanvasInteractionAngleZeroReference = .up
) -> CanvasInteractionLineSegment {
    CanvasInteractionLineSegment(
        start: canvasPointOnInteractionCircle(
            centeredAt: center,
            radius: startRadius,
            displayDegrees0To360: degrees,
            zeroReference: zeroReference
        ),
        end: canvasPointOnInteractionCircle(
            centeredAt: center,
            radius: endRadius,
            displayDegrees0To360: degrees,
            zeroReference: zeroReference
        )
    )
}
