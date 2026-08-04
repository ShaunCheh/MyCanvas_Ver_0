import CoreGraphics
import Foundation

private let canvasArrowShaftToHeadWidthRatio: CGFloat = 0.44
private let canvasArrowHeadLengthToHeadWidthRatio: CGFloat = 0.95
private let canvasArrowMinimumVisibleLength: CGFloat = 1
private let canvasArrowMinimumVisibleHeight: CGFloat = 1

enum CanvasArrowEndpointRole: CaseIterable, Hashable, Sendable {
    case start
    case end
}

struct CanvasArrowItem {
    let id: CanvasItemID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var shaftThickness: CGFloat
    var zIndex: CGFloat

    init(
        id: CanvasItemID = UUID(),
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.zIndex = zIndex
        shaftThickness = Self.shaftThickness(forOverallHeight: size.height)
        let resolvedEndpoints = Self.resolvedEndpoints(
            center: center,
            length: size.width,
            rotationRadians: rotationRadians
        )
        startPoint = resolvedEndpoints.start
        endPoint = resolvedEndpoints.end
    }

    init(
        id: CanvasItemID = UUID(),
        startPoint: CGPoint,
        endPoint: CGPoint,
        shaftThickness: CGFloat,
        zIndex: CGFloat = 0
    ) {
        self.id = id
        let resolvedEndpoints = Self.resolvedEndpoints(
            startPoint: startPoint,
            endPoint: endPoint,
            fallbackRotationRadians: 0
        )
        self.startPoint = resolvedEndpoints.start
        self.endPoint = resolvedEndpoints.end
        self.shaftThickness = max(
            shaftThickness,
            Self.minimumShaftThickness
        )
        self.zIndex = zIndex
    }

    var center: CGPoint {
        get {
            CGPoint(
                x: (startPoint.x + endPoint.x) / 2,
                y: (startPoint.y + endPoint.y) / 2
            )
        }
        set {
            let delta = CGPoint(
                x: newValue.x - center.x,
                y: newValue.y - center.y
            )
            startPoint = Self.translated(startPoint, by: delta)
            endPoint = Self.translated(endPoint, by: delta)
        }
    }

    var size: CGSize {
        get {
            CGSize(
                width: length,
                height: overallHeight
            )
        }
        set {
            let resolvedEndpoints = Self.resolvedEndpoints(
                center: center,
                length: newValue.width,
                rotationRadians: rotationRadians
            )
            startPoint = resolvedEndpoints.start
            endPoint = resolvedEndpoints.end
            shaftThickness = Self.shaftThickness(
                forOverallHeight: newValue.height
            )
        }
    }

    var rotationRadians: CGFloat {
        get {
            normalizedCanvasAngle(
                atan2(
                    endPoint.y - startPoint.y,
                    endPoint.x - startPoint.x
                )
            )
        }
        set {
            let resolvedEndpoints = Self.resolvedEndpoints(
                center: center,
                length: length,
                rotationRadians: newValue
            )
            startPoint = resolvedEndpoints.start
            endPoint = resolvedEndpoints.end
        }
    }

    var localFrame: CGRect {
        CGRect(
            x: -length / 2,
            y: -overallHeight / 2,
            width: length,
            height: overallHeight
        )
    }

    var localQuad: CanvasQuad {
        CanvasQuad(rect: localFrame)
    }

    var worldQuad: CanvasQuad {
        localQuad.map(worldPoint(fromLocal:))
    }

    var worldFrame: CGRect {
        CGRect(
            x: center.x - length / 2,
            y: center.y - overallHeight / 2,
            width: length,
            height: overallHeight
        )
    }

    var worldBounds: CGRect {
        worldQuad.boundingRect
    }

    func contains(worldPoint: CGPoint) -> Bool {
        let localPoint = localPoint(fromWorld: worldPoint)
        return canvasArrowPath(in: localFrame).contains(localPoint)
    }

    func endpointLocalPoint(
        for role: CanvasArrowEndpointRole
    ) -> CGPoint {
        switch role {
        case .start:
            return CGPoint(x: localFrame.minX, y: 0)
        case .end:
            return CGPoint(x: localFrame.maxX, y: 0)
        }
    }

    func endpointWorldPoint(
        for role: CanvasArrowEndpointRole
    ) -> CGPoint {
        worldPoint(fromLocal: endpointLocalPoint(for: role))
    }

    func worldPoint(fromLocal localPoint: CGPoint) -> CGPoint {
        let rotatedPoint = Self.rotated(localPoint, by: rotationRadians)
        return CGPoint(
            x: rotatedPoint.x + center.x,
            y: rotatedPoint.y + center.y
        )
    }

    func localPoint(fromWorld worldPoint: CGPoint) -> CGPoint {
        let translatedPoint = CGPoint(
            x: worldPoint.x - center.x,
            y: worldPoint.y - center.y
        )
        return Self.rotated(translatedPoint, by: -rotationRadians)
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasArrowItem {
        CanvasArrowItem(
            startPoint: CGPoint(
                x: startPoint.x + offsetInWorld.x,
                y: startPoint.y + offsetInWorld.y
            ),
            endPoint: CGPoint(
                x: endPoint.x + offsetInWorld.x,
                y: endPoint.y + offsetInWorld.y
            ),
            shaftThickness: shaftThickness,
            zIndex: zIndex
        )
    }

    func adjustingShaftThickness(by delta: CGFloat) -> CanvasArrowItem {
        guard delta.isFinite else {
            return self
        }

        let proposedShaftThickness = shaftThickness + delta
        guard proposedShaftThickness.isFinite else {
            return self
        }

        var adjustedItem = self
        adjustedItem.shaftThickness = max(
            proposedShaftThickness,
            Self.minimumShaftThickness
        )
        return adjustedItem
    }

    func matchesDocumentState(_ other: CanvasArrowItem) -> Bool {
        id == other.id &&
            startPoint == other.startPoint &&
            endPoint == other.endPoint &&
            shaftThickness == other.shaftThickness &&
            zIndex == other.zIndex &&
            rotationRadians == other.rotationRadians
    }

    private static func rotated(
        _ point: CGPoint,
        by radians: CGFloat
    ) -> CGPoint {
        guard radians != 0 else {
            return point
        }

        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }

    private var length: CGFloat {
        max(
            hypot(
                endPoint.x - startPoint.x,
                endPoint.y - startPoint.y
            ),
            Self.minimumLength
        )
    }

    private var overallHeight: CGFloat {
        Self.overallHeight(forShaftThickness: shaftThickness)
    }

    private static var minimumLength: CGFloat {
        canvasArrowMinimumVisibleLength
    }

    private static var minimumShaftThickness: CGFloat {
        shaftThickness(forOverallHeight: canvasArrowMinimumVisibleHeight)
    }

    private static func overallHeight(
        forShaftThickness shaftThickness: CGFloat
    ) -> CGFloat {
        max(shaftThickness, minimumShaftThickness) / canvasArrowShaftToHeadWidthRatio
    }

    private static func shaftThickness(
        forOverallHeight overallHeight: CGFloat
    ) -> CGFloat {
        max(overallHeight, canvasArrowMinimumVisibleHeight) * canvasArrowShaftToHeadWidthRatio
    }

    private static func resolvedEndpoints(
        center: CGPoint,
        length: CGFloat,
        rotationRadians: CGFloat
    ) -> (start: CGPoint, end: CGPoint) {
        let resolvedLength = max(length, minimumLength)
        let halfLength = resolvedLength / 2
        let direction = CGPoint(
            x: cos(normalizedCanvasAngle(rotationRadians)),
            y: sin(normalizedCanvasAngle(rotationRadians))
        )
        return (
            start: CGPoint(
                x: center.x - direction.x * halfLength,
                y: center.y - direction.y * halfLength
            ),
            end: CGPoint(
                x: center.x + direction.x * halfLength,
                y: center.y + direction.y * halfLength
            )
        )
    }

    private static func resolvedEndpoints(
        startPoint: CGPoint,
        endPoint: CGPoint,
        fallbackRotationRadians: CGFloat
    ) -> (start: CGPoint, end: CGPoint) {
        let center = CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
        let delta = CGPoint(
            x: endPoint.x - startPoint.x,
            y: endPoint.y - startPoint.y
        )
        let length = hypot(delta.x, delta.y)
        if length >= minimumLength {
            return (startPoint, endPoint)
        }

        let direction: CGPoint
        if length > 0.0001 {
            direction = CGPoint(
                x: delta.x / length,
                y: delta.y / length
            )
        } else {
            direction = CGPoint(
                x: cos(normalizedCanvasAngle(fallbackRotationRadians)),
                y: sin(normalizedCanvasAngle(fallbackRotationRadians))
            )
        }

        let halfLength = minimumLength / 2
        return (
            start: CGPoint(
                x: center.x - direction.x * halfLength,
                y: center.y - direction.y * halfLength
            ),
            end: CGPoint(
                x: center.x + direction.x * halfLength,
                y: center.y + direction.y * halfLength
            )
        )
    }

    private static func translated(
        _ point: CGPoint,
        by delta: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: point.x + delta.x,
            y: point.y + delta.y
        )
    }
}

func canvasArrowPath(in rect: CGRect) -> CGPath {
    let points = canvasArrowPolygonPoints(in: rect)
    let path = CGMutablePath()
    guard let firstPoint = points.first else {
        return path
    }

    path.move(to: firstPoint)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func canvasArrowPolygonPoints(in rect: CGRect) -> [CGPoint] {
    let standardizedRect = rect.standardized
    guard
        standardizedRect.width > 0,
        standardizedRect.height > 0
    else {
        return []
    }

    let startX = standardizedRect.minX
    let endX = standardizedRect.maxX
    let centerY = standardizedRect.midY
    let tailHalfHeight = standardizedRect.height * canvasArrowShaftToHeadWidthRatio / 2
    let headLength = standardizedRect.height * canvasArrowHeadLengthToHeadWidthRatio
    let neckX = max(
        endX - headLength,
        startX + (standardizedRect.width * 0.15)
    )

    return [
        CGPoint(x: startX, y: centerY - tailHalfHeight),
        CGPoint(x: neckX, y: centerY - tailHalfHeight),
        CGPoint(x: neckX, y: standardizedRect.minY),
        CGPoint(x: endX, y: centerY),
        CGPoint(x: neckX, y: standardizedRect.maxY),
        CGPoint(x: neckX, y: centerY + tailHalfHeight),
        CGPoint(x: startX, y: centerY + tailHalfHeight)
    ]
}
