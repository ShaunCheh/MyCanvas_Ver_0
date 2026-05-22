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

    func testHandDrawingMoveSelectionControllerHitTestingUsesCurrentStrokeRadiusWithPadding() {
        let hitSample = HandDrawingInputSample(
            location: CGPoint(x: 60, y: 77),
            timestamp: 0
        )

        let thinStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            sampleForces: [0.35, 0.35, 0.35]
        )
        var thinEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "move-pressure-thin-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [thinStroke]
            )
        )
        XCTAssertTrue(thinEngine.selectStrokes(withIDs: [thinStroke.id]))

        var thinController = HandDrawingMoveSelectionController()
        XCTAssertFalse(
            thinController.beginMoving(
                with: hitSample,
                engine: thinEngine
            )
        )
        XCTAssertFalse(thinController.isActive)

        let thickStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            sampleForces: [1, 1, 1]
        )
        var thickEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "move-pressure-thick-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [thickStroke]
            )
        )
        XCTAssertTrue(thickEngine.selectStrokes(withIDs: [thickStroke.id]))

        var thickController = HandDrawingMoveSelectionController()
        XCTAssertTrue(
            thickController.beginMoving(
                with: hitSample,
                engine: thickEngine
            )
        )
        XCTAssertTrue(thickController.isActive)
    }

    func testHandDrawingMoveSelectionControllerCancelRestoresPosition() {
        let stroke = makeHandDrawingTestStroke(id: UUID())
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "move-cancel-paper",
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
                    location: CGPoint(x: 74, y: 68),
                    timestamp: 0.1
                )
            ],
            engine: &engine
        )
        controller.cancelMoving(engine: &engine)

        let restoredStroke = engine.state.document.strokes[0]
        XCTAssertEqual(restoredStroke.transform.translationX, 0, accuracy: 0.001)
        XCTAssertEqual(restoredStroke.transform.translationY, 0, accuracy: 0.001)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [stroke.id])
        XCTAssertFalse(controller.isActive)
    }

    func testHandDrawingMoveSelectionControllerOnlyMovesActiveLayerSelection() throws {
        let inactiveStroke = makeHandDrawingTestStroke(id: UUID())
        let activeStroke = makeHandDrawingTestStroke(id: UUID())
        let inactiveLayer = makeHandDrawingTestLayer(
            name: "Inactive",
            strokes: [inactiveStroke]
        )
        let activeLayer = makeHandDrawingTestLayer(
            name: "Active",
            strokes: [activeStroke]
        )
        var engine = HandDrawingEditorEngine(
            document: makeHandDrawingLayeredTestDocument(
                paper: HandDrawingPaper(
                    id: "move-active-layer-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                layers: [inactiveLayer, activeLayer],
                activeLayerID: activeLayer.id
            )
        )
        XCTAssertTrue(engine.selectStrokes(withIDs: [inactiveStroke.id, activeStroke.id]))
        XCTAssertEqual(engine.state.selectedStrokeIDs, [activeStroke.id])

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
                    location: CGPoint(x: 70, y: 68),
                    timestamp: 0.1
                )
            ],
            engine: &engine
        )
        controller.endMoving()

        let movedActiveStroke = try XCTUnwrap(
            engine.state.document.layer(withID: activeLayer.id)?.strokes.first
        )
        let untouchedInactiveStroke = try XCTUnwrap(
            engine.state.document.layer(withID: inactiveLayer.id)?.strokes.first
        )
        XCTAssertEqual(movedActiveStroke.transform.translationX, 10, accuracy: 0.001)
        XCTAssertEqual(movedActiveStroke.transform.translationY, 8, accuracy: 0.001)
        XCTAssertEqual(untouchedInactiveStroke.transform.translationX, 0, accuracy: 0.001)
        XCTAssertEqual(untouchedInactiveStroke.transform.translationY, 0, accuracy: 0.001)
    }

    func testHandDrawingMoveSelectionControllerCannotBeginOnHiddenOrLockedActiveLayer() {
        func makeEngine(
            isVisible: Bool,
            isLocked: Bool
        ) -> HandDrawingEditorEngine {
            let stroke = makeHandDrawingTestStroke(id: UUID())
            let activeLayer = makeHandDrawingTestLayer(
                name: "Active",
                isVisible: isVisible,
                isLocked: isLocked,
                strokes: [stroke]
            )
            var engine = HandDrawingEditorEngine(
                document: makeHandDrawingLayeredTestDocument(
                    paper: HandDrawingPaper(
                        id: "move-guard-paper",
                        size: CGSize(width: 140, height: 140)
                    ),
                    layers: [activeLayer],
                    activeLayerID: activeLayer.id
                )
            )
            XCTAssertTrue(engine.selectStrokes(withIDs: [stroke.id]))
            return engine
        }

        for configuration in [(false, false), (true, true)] {
            let engine = makeEngine(
                isVisible: configuration.0,
                isLocked: configuration.1
            )
            var controller = HandDrawingMoveSelectionController()

            XCTAssertFalse(
                controller.beginMoving(
                    with: HandDrawingInputSample(
                        location: CGPoint(x: 60, y: 60),
                        timestamp: 0
                    ),
                    engine: engine
                )
            )
            XCTAssertFalse(controller.isActive)
        }
    }
}
