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
}
