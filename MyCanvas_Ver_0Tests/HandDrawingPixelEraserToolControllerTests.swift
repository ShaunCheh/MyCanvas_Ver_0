import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingPixelEraserToolControllerTests: XCTestCase {
    func testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() {
        let targetStroke = makeHandDrawingTestStroke(id: UUID())
        let untouchedStroke = makeHandDrawingTestStroke(
            id: UUID(),
            transform: HandDrawingStrokeTransform(translationY: -30)
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "eraser-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [targetStroke, untouchedStroke]
            )
        )
        var controller = HandDrawingPixelEraserToolController()

        controller.beginErasing(
            with: HandDrawingInputSample(
                location: CGPoint(x: 60, y: 60),
                force: 1,
                timestamp: 0
            ),
            baseSize: 20,
            engine: &engine
        )
        controller.endErasing()

        let mutatedTargetStroke = engine.state.document.strokes[0]
        let untouchedResultStroke = engine.state.document.strokes[1]
        XCTAssertEqual(mutatedTargetStroke.eraseMask.count, 1)
        XCTAssertTrue(untouchedResultStroke.eraseMask.isEmpty)
        XCTAssertEqual(
            mutatedTargetStroke.eraseMask[0].samplePoints[0].radius,
            15,
            accuracy: 0.001
        )
        XCTAssertNotNil(engine.consumeDirtyRegion())

        XCTAssertTrue(engine.undo())
        XCTAssertTrue(engine.state.document.strokes[0].eraseMask.isEmpty)
        XCTAssertTrue(engine.state.document.strokes[1].eraseMask.isEmpty)
    }

    func testHandDrawingPixelEraserToolControllerHitTestingUsesCurrentStrokeRadius() {
        let eraseSample = HandDrawingInputSample(
            location: CGPoint(x: 60, y: 66),
            force: 0.05,
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
                    id: "eraser-pressure-thin-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [thinStroke]
            )
        )
        var thinController = HandDrawingPixelEraserToolController()

        thinController.beginErasing(
            with: eraseSample,
            baseSize: 1,
            engine: &thinEngine
        )
        thinController.endErasing()

        XCTAssertTrue(thinEngine.state.document.strokes[0].eraseMask.isEmpty)
        XCTAssertFalse(thinEngine.canUndo)
        XCTAssertNil(thinEngine.consumeDirtyRegion())

        let thickStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            sampleForces: [1, 1, 1]
        )
        var thickEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "eraser-pressure-thick-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [thickStroke]
            )
        )
        var thickController = HandDrawingPixelEraserToolController()

        thickController.beginErasing(
            with: eraseSample,
            baseSize: 1,
            engine: &thickEngine
        )
        thickController.endErasing()

        XCTAssertEqual(thickEngine.state.document.strokes[0].eraseMask.count, 1)
        XCTAssertEqual(
            thickEngine.state.document.strokes[0].eraseMask[0].samplePoints.count,
            1
        )
        XCTAssertTrue(thickEngine.canUndo)
        XCTAssertNotNil(thickEngine.consumeDirtyRegion())
    }

    func testHandDrawingPixelEraserToolControllerHitTestingUsesTiltedStampFootprint() {
        let eraseSample = HandDrawingInputSample(
            location: CGPoint(x: 68, y: 60),
            force: 0.05,
            timestamp: 0
        )

        let circularStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            samplePoints: [CGPoint(x: 60, y: 60)],
            sampleForces: [0.5]
        )
        var circularEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "eraser-circle-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [circularStroke]
            )
        )
        var circularController = HandDrawingPixelEraserToolController()

        circularController.beginErasing(
            with: eraseSample,
            baseSize: 1,
            engine: &circularEngine
        )
        circularController.endErasing()

        XCTAssertTrue(circularEngine.state.document.strokes[0].eraseMask.isEmpty)
        XCTAssertFalse(circularEngine.canUndo)

        let tiltedStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            samplePoints: [CGPoint(x: 60, y: 60)],
            sampleForces: [0.5],
            sampleAzimuths: [0],
            sampleAltitudes: [0],
            tiltSizeInfluence: 1
        )
        var tiltedEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "eraser-tilt-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [tiltedStroke]
            )
        )
        var tiltedController = HandDrawingPixelEraserToolController()

        tiltedController.beginErasing(
            with: eraseSample,
            baseSize: 1,
            engine: &tiltedEngine
        )
        tiltedController.endErasing()

        XCTAssertEqual(tiltedEngine.state.document.strokes[0].eraseMask.count, 1)
        XCTAssertTrue(tiltedEngine.canUndo)
    }

    func testHandDrawingPixelEraserToolControllerSplitsDisjointHitSequencesIntoSeparateErasePaths() {
        let stroke = makeHandDrawingTestStroke(id: UUID())
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "split-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [stroke]
            )
        )
        var controller = HandDrawingPixelEraserToolController()

        controller.beginErasing(
            with: HandDrawingInputSample(
                location: CGPoint(x: 35, y: 60),
                force: 0.8,
                timestamp: 0
            ),
            baseSize: 12,
            engine: &engine
        )
        controller.appendSamples(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 60, y: 20),
                    force: 0.8,
                    timestamp: 0.1
                )
            ],
            baseSize: 12,
            engine: &engine
        )
        controller.appendSamples(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 85, y: 60),
                    force: 0.8,
                    timestamp: 0.2
                )
            ],
            baseSize: 12,
            engine: &engine
        )
        controller.endErasing()

        let eraseMask = engine.state.document.strokes[0].eraseMask
        XCTAssertEqual(eraseMask.count, 2)
        XCTAssertEqual(eraseMask[0].samplePoints.count, 1)
        XCTAssertEqual(eraseMask[1].samplePoints.count, 1)
    }

    func testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument() {
        let stroke = makeHandDrawingTestStroke(id: UUID())
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "cancel-paper",
                    size: CGSize(width: 120, height: 120)
                ),
                strokes: [stroke]
            )
        )
        var controller = HandDrawingPixelEraserToolController()

        controller.beginErasing(
            with: HandDrawingInputSample(
                location: CGPoint(x: 60, y: 60),
                force: 1,
                timestamp: 0
            ),
            baseSize: 18,
            engine: &engine
        )

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(engine.state.document.strokes[0].eraseMask.count, 1)

        controller.cancelErasing(engine: &engine)

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(engine.state.document.strokes[0].eraseMask.isEmpty)
    }

    func testHandDrawingPixelEraserToolControllerOnlyMutatesActiveLayerStroke() throws {
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
                layers: [inactiveLayer, activeLayer],
                activeLayerID: activeLayer.id
            )
        )
        var controller = HandDrawingPixelEraserToolController()

        controller.beginErasing(
            with: HandDrawingInputSample(
                location: CGPoint(x: 60, y: 60),
                force: 1,
                timestamp: 0
            ),
            baseSize: 20,
            engine: &engine
        )
        controller.endErasing()

        let mutatedActiveStroke = try XCTUnwrap(
            engine.state.document.layer(withID: activeLayer.id)?.strokes.first
        )
        let untouchedInactiveStroke = try XCTUnwrap(
            engine.state.document.layer(withID: inactiveLayer.id)?.strokes.first
        )
        XCTAssertEqual(mutatedActiveStroke.eraseMask.count, 1)
        XCTAssertTrue(untouchedInactiveStroke.eraseMask.isEmpty)
    }

    func testHandDrawingPixelEraserToolControllerDoesNotStartOnHiddenOrLockedActiveLayer() {
        func makeEngine(
            isVisible: Bool,
            isLocked: Bool
        ) -> HandDrawingEditorEngine {
            let activeLayer = makeHandDrawingTestLayer(
                name: "Active",
                isVisible: isVisible,
                isLocked: isLocked,
                strokes: [makeHandDrawingTestStroke(id: UUID())]
            )
            return HandDrawingEditorEngine(
                document: makeHandDrawingLayeredTestDocument(
                    layers: [activeLayer],
                    activeLayerID: activeLayer.id
                )
            )
        }

        for configuration in [(false, false), (true, true)] {
            var engine = makeEngine(
                isVisible: configuration.0,
                isLocked: configuration.1
            )
            var controller = HandDrawingPixelEraserToolController()

            controller.beginErasing(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 60, y: 60),
                    force: 1,
                    timestamp: 0
                ),
                baseSize: 18,
                engine: &engine
            )

            XCTAssertFalse(controller.isActive)
            XCTAssertTrue(engine.state.document.activeLayerStrokes[0].eraseMask.isEmpty)
            XCTAssertFalse(engine.canUndo)
            XCTAssertNil(engine.consumeDirtyRegion())
        }
    }
}
