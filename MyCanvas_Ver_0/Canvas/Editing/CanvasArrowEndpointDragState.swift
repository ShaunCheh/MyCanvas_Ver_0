import CoreGraphics
import Foundation

struct CanvasArrowEndpointDragState {
    let itemID: CanvasItemID
    let draggedEndpointRole: CanvasArrowEndpointRole
    let fixedEndpointWorldPoint: CGPoint
    let preservedOverallHeight: CGFloat
    let minimumLength: CGFloat
    let fallbackRotationRadians: CGFloat

    init(
        item: CanvasArrowItem,
        draggedEndpointRole: CanvasArrowEndpointRole,
        minimumLength: CGFloat
    ) {
        self.itemID = item.id
        self.draggedEndpointRole = draggedEndpointRole
        fixedEndpointWorldPoint = item.endpointWorldPoint(
            for: draggedEndpointRole == .start ? .end : .start
        )
        preservedOverallHeight = item.size.height
        self.minimumLength = max(minimumLength, 1)
        fallbackRotationRadians = item.rotationRadians
    }

    func updatedGeometry(
        draggedWorldPoint: CGPoint
    ) -> CanvasBoardItemGeometry {
        var startWorldPoint = draggedEndpointRole == .start
            ? draggedWorldPoint
            : fixedEndpointWorldPoint
        var endWorldPoint = draggedEndpointRole == .end
            ? draggedWorldPoint
            : fixedEndpointWorldPoint

        var direction = CGPoint(
            x: endWorldPoint.x - startWorldPoint.x,
            y: endWorldPoint.y - startWorldPoint.y
        )
        var length = hypot(direction.x, direction.y)
        if length < minimumLength {
            if length > 0.0001 {
                direction.x /= length
                direction.y /= length
            } else {
                direction = CGPoint(
                    x: cos(fallbackRotationRadians),
                    y: sin(fallbackRotationRadians)
                )
            }

            if draggedEndpointRole == .start {
                startWorldPoint = CGPoint(
                    x: endWorldPoint.x - direction.x * minimumLength,
                    y: endWorldPoint.y - direction.y * minimumLength
                )
            } else {
                endWorldPoint = CGPoint(
                    x: startWorldPoint.x + direction.x * minimumLength,
                    y: startWorldPoint.y + direction.y * minimumLength
                )
            }

            direction = CGPoint(
                x: endWorldPoint.x - startWorldPoint.x,
                y: endWorldPoint.y - startWorldPoint.y
            )
            length = hypot(direction.x, direction.y)
        }

        return CanvasBoardItemGeometry(
            itemID: itemID,
            center: CGPoint(
                x: (startWorldPoint.x + endWorldPoint.x) / 2,
                y: (startWorldPoint.y + endWorldPoint.y) / 2
            ),
            size: CGSize(
                width: length,
                height: preservedOverallHeight
            ),
            rotationRadians: atan2(direction.y, direction.x)
        )
    }
}
