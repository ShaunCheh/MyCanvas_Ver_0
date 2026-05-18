import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingLassoSelectionTests: XCTestCase {
    func testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo() {
        let enclosedStroke = makeHandDrawingTestStroke(id: UUID())
        let outsideStroke = makeHandDrawingTestStroke(
            id: UUID(),
            transform: HandDrawingStrokeTransform(translationY: -30)
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "lasso-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [enclosedStroke, outsideStroke]
            )
        )
        var controller = HandDrawingLassoToolController()

        controller.beginLasso(
            with: HandDrawingInputSample(
                location: CGPoint(x: 18, y: 44),
                timestamp: 0
            )
        )
        controller.appendSamples(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 102, y: 44),
                    timestamp: 0.1
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 102, y: 78),
                    timestamp: 0.2
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 78),
                    timestamp: 0.3
                )
            ]
        )

        XCTAssertTrue(controller.endLasso(engine: &engine))
        XCTAssertEqual(engine.state.selectedStrokeIDs, [enclosedStroke.id])
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        XCTAssertTrue(engine.undo())
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertTrue(engine.canRedo)

        XCTAssertTrue(engine.redo())
        XCTAssertEqual(engine.state.selectedStrokeIDs, [enclosedStroke.id])
    }
}
