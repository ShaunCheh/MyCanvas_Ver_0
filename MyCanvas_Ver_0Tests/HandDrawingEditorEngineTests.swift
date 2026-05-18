import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingEditorEngineTests: XCTestCase {
    func testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() throws {
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "engine-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )

        let stroke = try XCTUnwrap(
            engine.appendStroke(
                brush: .defaultPen,
                samples: [
                    HandDrawingInputSample(
                        location: CGPoint(x: 20, y: 20),
                        force: 0.8,
                        timestamp: 0
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 80, y: 80),
                        force: 1,
                        timestamp: 0.2
                    )
                ]
            )
        )

        XCTAssertEqual(engine.state.document.strokes.count, 1)
        XCTAssertEqual(engine.state.document.strokes.first?.id, stroke.id)
        XCTAssertNotNil(engine.consumeDirtyRegion())
        XCTAssertNil(engine.consumeDirtyRegion())

        let encodedData = try engine.encodedDocumentData()
        let restoredEngine = try HandDrawingEditorEngine(documentData: encodedData)
        XCTAssertEqual(restoredEngine.state.document, engine.state.document)
    }

    func testHandDrawingEditorEngineUndoRedoAndDeselect() {
        let firstStroke = makeHandDrawingTestStroke(id: UUID())
        let secondStroke = makeHandDrawingTestStroke(
            id: UUID(),
            transform: HandDrawingStrokeTransform(translationY: 18)
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "history-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )

        engine.appendStroke(firstStroke)
        engine.appendStroke(secondStroke)
        engine.selectStrokes(withIDs: [firstStroke.id, secondStroke.id])
        engine.apply(command: .deselectAll)

        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.document.strokes.count, 1)
        XCTAssertTrue(engine.canRedo)

        XCTAssertTrue(engine.redo())
        XCTAssertEqual(engine.state.document.strokes.count, 2)
    }
}
