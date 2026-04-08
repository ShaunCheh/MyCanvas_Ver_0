import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasSelectedItemDragStateTests: XCTestCase {
    func testProposedCenterUsesDragStartCenterAndAccumulatedWorldDelta() {
        let dragState = CanvasSelectedItemDragState(
            itemID: CanvasItemID(),
            dragStartWorldLocation: CGPoint(x: 200, y: 300),
            dragStartCenter: CGPoint(x: 40, y: 60)
        )

        let proposedCenter = dragState.proposedCenter(
            for: CGPoint(x: 215, y: 282)
        )

        XCTAssertEqual(proposedCenter, CGPoint(x: 55, y: 42))
    }

    func testReplacingAlignmentLockDoesNotChangeDragBaseline() {
        let dragState = CanvasSelectedItemDragState(
            itemID: CanvasItemID(),
            dragStartWorldLocation: CGPoint(x: 10, y: 20),
            dragStartCenter: CGPoint(x: 100, y: 120)
        )
        let updatedState = dragState.replacingAlignmentLock(
            CanvasAlignmentLockState(
                xAxis: CanvasAlignmentAxisLock(
                    movingAnchor: .centerX,
                    referenceAnchor: .centerX,
                    referenceSource: .board
                )
            )
        )

        XCTAssertEqual(
            updatedState.proposedCenter(for: CGPoint(x: 16, y: 12)),
            CGPoint(x: 106, y: 112)
        )
    }
}
