import CoreGraphics
import Foundation

struct CanvasSelectedItemDragState: Equatable {
    let itemID: CanvasItemID
    let dragStartWorldLocation: CGPoint
    let dragStartCenter: CGPoint
    var alignmentLock: CanvasAlignmentLockState

    init(
        itemID: CanvasItemID,
        dragStartWorldLocation: CGPoint,
        dragStartCenter: CGPoint,
        alignmentLock: CanvasAlignmentLockState = .none
    ) {
        self.itemID = itemID
        self.dragStartWorldLocation = dragStartWorldLocation
        self.dragStartCenter = dragStartCenter
        self.alignmentLock = alignmentLock
    }

    func proposedCenter(
        for currentWorldLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: dragStartCenter.x + (currentWorldLocation.x - dragStartWorldLocation.x),
            y: dragStartCenter.y + (currentWorldLocation.y - dragStartWorldLocation.y)
        )
    }

    func replacingAlignmentLock(
        _ alignmentLock: CanvasAlignmentLockState
    ) -> CanvasSelectedItemDragState {
        var updatedState = self
        updatedState.alignmentLock = alignmentLock
        return updatedState
    }
}
