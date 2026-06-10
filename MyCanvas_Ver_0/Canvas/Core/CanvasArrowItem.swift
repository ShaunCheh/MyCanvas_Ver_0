import CoreGraphics
import Foundation

enum CanvasArrowEndpointRole: CaseIterable {
    case start
    case end
}

struct CanvasArrowItem {
    let id: CanvasItemID
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    init(
        id: CanvasItemID = UUID(),
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.rotationRadians = rotationRadians
    }

    var localFrame: CGRect {
        CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
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
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
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
            return CGPoint(x: localFrame.minX, y: localFrame.midY)
        case .end:
            return CGPoint(x: localFrame.maxX, y: localFrame.midY)
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
            center: CGPoint(
                x: center.x + offsetInWorld.x,
                y: center.y + offsetInWorld.y
            ),
            size: size,
            zIndex: zIndex,
            rotationRadians: rotationRadians
        )
    }

    func matchesDocumentState(_ other: CanvasArrowItem) -> Bool {
        id == other.id &&
            center == other.center &&
            size == other.size &&
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
    let tailHalfHeight = standardizedRect.height * 0.22
    let preferredHeadLength = max(
        standardizedRect.width * 0.28,
        standardizedRect.height * 0.95
    )
    let headLength = min(
        max(preferredHeadLength, standardizedRect.width * 0.18),
        standardizedRect.width * 0.55
    )
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
