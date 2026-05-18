import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingMoveSelectionTests: XCTestCase {
    func testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition() {
        let stroke = makeHandDrawingTestStroke(id: UUID())
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "move-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [stroke]
            )
        )
        XCTAssertTrue(engine.selectStrokes(withIDs: [stroke.id]))

        var controller = HandDrawingMoveSelectionController()
        XCTAssertTrue(
            controller.beginMoving(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 60, y: 60),
                    timestamp: 0
                ),
                engine: engine
            )
        )

        controller.appendSamples(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 76, y: 72),
                    timestamp: 0.1
                )
            ],
            engine: &engine
        )
        controller.endMoving()

        let movedStroke = engine.state.document.strokes[0]
        XCTAssertEqual(movedStroke.transform.translationX, 16, accuracy: 0.001)
        XCTAssertEqual(movedStroke.transform.translationY, 12, accuracy: 0.001)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [stroke.id])
        XCTAssertNotNil(engine.consumeDirtyRegion())

        XCTAssertTrue(engine.undo())
        let restoredStroke = engine.state.document.strokes[0]
        XCTAssertEqual(restoredStroke.transform.translationX, 0, accuracy: 0.001)
        XCTAssertEqual(restoredStroke.transform.translationY, 0, accuracy: 0.001)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [stroke.id])
    }
}
