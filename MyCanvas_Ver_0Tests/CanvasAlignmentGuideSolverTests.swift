import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasAlignmentGuideSolverTests: XCTestCase {
    func testSolveSnapsOnBothAxesAndReturnsCenterGuides() {
        let movingItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 40)
        )
        let referenceItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 100, y: 200),
            size: CGSize(width: 60, height: 60),
            zIndex: 1
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(referenceItem)
            ]
        )
        let solver = CanvasAlignmentGuideSolver(
            configuration: CanvasAlignmentSolverConfiguration(
                snapThresholdInViewport: 5,
                searchPaddingInViewport: 160
            )
        )

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: CGPoint(x: 104, y: 204),
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, CGPoint(x: 100, y: 200))
        let interactionState = try? XCTUnwrap(result.interactionState)
        XCTAssertEqual(interactionState?.xMatch?.movingAnchor, .centerX)
        XCTAssertEqual(interactionState?.yMatch?.movingAnchor, .centerY)
        XCTAssertEqual(interactionState?.guides.count, 2)
        XCTAssertEqual(
            interactionState?.guides.map(\.orientation),
            [.vertical, .horizontal]
        )
    }

    func testSolvePrefersNearestReferenceWhenMultipleCandidatesExist() {
        let movingItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 40)
        )
        let nearerReference = makeAlignmentTestTextItem(
            center: CGPoint(x: 80, y: 0),
            size: CGSize(width: 40, height: 40),
            zIndex: 1
        )
        let fartherReference = makeAlignmentTestTextItem(
            center: CGPoint(x: 84, y: 0),
            size: CGSize(width: 40, height: 40),
            zIndex: 2
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(nearerReference),
                .text(fartherReference)
            ]
        )
        let solver = CanvasAlignmentGuideSolver()

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: CGPoint(x: 78, y: 0),
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, CGPoint(x: 80, y: 0))
        XCTAssertEqual(
            result.interactionState?.xMatch?.referenceSource,
            .item(nearerReference.id)
        )
    }

    func testSolveReturnsPassthroughWhenNoCandidateFallsWithinThreshold() {
        let movingItem = makeAlignmentTestTextItem(center: CGPoint(x: 0, y: 0))
        let referenceItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 240, y: 200),
            zIndex: 1
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(referenceItem)
            ]
        )
        let solver = CanvasAlignmentGuideSolver()
        let proposedCenter = CGPoint(x: 40, y: 0)

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: proposedCenter,
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, proposedCenter)
        XCTAssertNil(result.interactionState)
    }

    func testSolveUsesViewportDistanceThresholdAcrossZoomLevels() {
        let movingItem = makeAlignmentTestTextItem(center: CGPoint(x: 0, y: 0))
        let referenceItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 120, y: 120),
            zIndex: 1
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(referenceItem)
            ]
        )
        let solver = CanvasAlignmentGuideSolver()
        let proposedCenter = CGPoint(x: 115, y: 0)

        let zoomScaleOneResult = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: proposedCenter,
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera(zoomScale: 1)
            )
        )
        let zoomScaleTwoResult = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: proposedCenter,
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera(zoomScale: 2)
            )
        )

        XCTAssertEqual(zoomScaleOneResult.resolvedCenter, CGPoint(x: 120, y: 0))
        XCTAssertEqual(zoomScaleTwoResult.resolvedCenter, proposedCenter)
        XCTAssertNotNil(zoomScaleOneResult.interactionState)
        XCTAssertNil(zoomScaleTwoResult.interactionState)
    }

    func testSolveUsesWorldFrameInsteadOfWorldBoundsForRotatedReference() {
        let movingItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 40)
        )
        let rotatedReference = makeAlignmentTestTextItem(
            center: CGPoint(x: 200, y: 0),
            size: CGSize(width: 100, height: 100),
            rotationRadians: .pi / 4,
            zIndex: 1
        )
        let scene = makeAlignmentTestScene(
            items: [
                .text(movingItem),
                .text(rotatedReference)
            ]
        )
        let solver = CanvasAlignmentGuideSolver()

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: CGPoint(x: 166, y: 0),
                scene: scene,
                boardState: nil,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, CGPoint(x: 170, y: 0))
        XCTAssertEqual(result.interactionState?.xMatch?.movingAnchor, .left)
        XCTAssertEqual(
            result.interactionState?.xMatch?.referenceSource,
            .item(rotatedReference.id)
        )
    }

    func testSolveCanSnapAgainstBoardReference() {
        let movingItem = makeAlignmentTestTextItem(
            center: CGPoint(x: 0, y: 0),
            size: CGSize(width: 40, height: 40)
        )
        let scene = makeAlignmentTestScene(items: [.text(movingItem)])
        let boardState = CanvasBoardState(
            baseSize: CGSize(width: 400, height: 300),
            centeredAt: .zero
        )
        let solver = CanvasAlignmentGuideSolver()

        let result = solver.solve(
            CanvasAlignmentSolveRequest(
                movingItemID: movingItem.id,
                proposedCenter: CGPoint(x: -182, y: 0),
                scene: scene,
                boardState: boardState,
                camera: makeAlignmentTestCamera()
            )
        )

        XCTAssertEqual(result.resolvedCenter, CGPoint(x: -180, y: 0))
        XCTAssertEqual(result.interactionState?.xMatch?.movingAnchor, .left)
        XCTAssertEqual(result.interactionState?.xMatch?.referenceSource, .board)
    }
}

private enum CanvasAlignmentGuideSolverTestRetainer {
    static var scenes: [CanvasScene] = []
}

private func makeAlignmentTestScene(
    items: [CanvasBoardItem]
) -> CanvasScene {
    let scene = CanvasScene(items: items)
    CanvasAlignmentGuideSolverTestRetainer.scenes.append(scene)
    return scene
}

private func makeAlignmentTestCamera(
    zoomScale: CGFloat = 1
) -> CanvasCamera {
    CanvasCamera(
        center: .zero,
        zoomScale: zoomScale,
        viewportSize: CGSize(width: 600, height: 400)
    )
}

private func makeAlignmentTestTextItem(
    center: CGPoint,
    size: CGSize = CGSize(width: 40, height: 40),
    rotationRadians: CGFloat = 0,
    zIndex: CGFloat = 0
) -> CanvasTextItem {
    CanvasTextItem(
        text: "alignment",
        center: center,
        size: size,
        zIndex: zIndex,
        rotationRadians: rotationRadians
    )
}
