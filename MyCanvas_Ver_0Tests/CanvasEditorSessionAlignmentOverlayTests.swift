import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditorSessionAlignmentOverlayTests: XCTestCase {
    func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.camera = CanvasCamera(
            center: .zero,
            zoomScale: 2,
            viewportSize: CGSize(width: 600, height: 400)
        )
        session.alignmentInteractionState = CanvasAlignmentInteractionState(
            itemID: item.id,
            guides: [
                CanvasAlignmentGuide(
                    orientation: .vertical,
                    worldStart: CGPoint(x: 50, y: -20),
                    worldEnd: CGPoint(x: 50, y: 80),
                    movingAnchor: .centerX,
                    referenceAnchor: .centerX,
                    referenceSource: .board
                )
            ],
            xMatch: CanvasAlignmentMatch(
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board,
                referenceCoordinate: 50,
                distanceInWorld: 0
            ),
            yMatch: nil
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case let .alignment(payload) = interactionOverlay.payload else {
            XCTFail("Expected alignment interaction overlay payload.")
            return
        }

        XCTAssertTrue(payload.isActive)
        XCTAssertEqual(payload.xMatch?.referenceSource, .board)
        XCTAssertEqual(payload.guideSegments.count, 1)
        XCTAssertEqual(
            payload.guideSegments.first?.start,
            CGPoint(x: 400, y: 160)
        )
        XCTAssertEqual(
            payload.guideSegments.first?.end,
            CGPoint(x: 400, y: 360)
        )
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.workspaceMode = .reading
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()

        XCTAssertNil(snapshot.interactionOverlay)
    }

    func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: item.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case .rotation = interactionOverlay.payload else {
            XCTFail("Expected rotation interaction overlay to win priority.")
            return
        }
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.inlineEditState = CanvasInlineEditState(item: item)
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()

        XCTAssertNil(snapshot.interactionOverlay)
    }
}

private enum CanvasEditorSessionAlignmentOverlayTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeAlignmentOverlayTestSession(
    with item: CanvasTextItem
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems([.text(item)])
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 600, height: 400)
    )
    session.interactionState.selectedItemID = item.id
    CanvasEditorSessionAlignmentOverlayTestRetainer.sessions.append(session)
    return session
}

private func makeAlignmentOverlayTestItem() -> CanvasTextItem {
    CanvasTextItem(
        text: "alignment overlay",
        center: CGPoint(x: 20, y: 20),
        size: CGSize(width: 80, height: 40)
    )
}

private func makeAlignmentOverlayTestState(
    itemID: CanvasItemID
) -> CanvasAlignmentInteractionState {
    CanvasAlignmentInteractionState(
        itemID: itemID,
        guides: [
            CanvasAlignmentGuide(
                orientation: .vertical,
                worldStart: CGPoint(x: 30, y: -20),
                worldEnd: CGPoint(x: 30, y: 60),
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board
            )
        ],
        xMatch: CanvasAlignmentMatch(
            movingAnchor: .centerX,
            referenceAnchor: .centerX,
            referenceSource: .board,
            referenceCoordinate: 30,
            distanceInWorld: 0
        ),
        yMatch: nil
    )
}
