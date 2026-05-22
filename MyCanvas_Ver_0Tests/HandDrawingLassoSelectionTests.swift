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

        XCTAssertTrue(
            controller.beginLasso(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 44),
                    timestamp: 0
                ),
                engine: engine
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

    func testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke() {
        let enclosedStroke = makeHandDrawingTestStroke(id: UUID())
        let partiallyOverlappingStroke = makeHandDrawingTestStroke(
            id: UUID(),
            transform: HandDrawingStrokeTransform(translationX: 20)
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "lasso-partial-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [enclosedStroke, partiallyOverlappingStroke]
            )
        )
        var controller = HandDrawingLassoToolController()

        XCTAssertTrue(
            controller.beginLasso(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 44),
                    timestamp: 0
                ),
                engine: engine
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
        XCTAssertFalse(
            engine.state.selectedStrokeIDs.contains(partiallyOverlappingStroke.id)
        )
    }

    func testHandDrawingLassoToolControllerUsesCurrentPressureRadiusForEnclosure() {
        func applyNarrowLasso(
            to engine: inout HandDrawingEditorEngine,
            y: CGFloat
        ) -> Bool {
            var controller = HandDrawingLassoToolController()
            XCTAssertTrue(
                controller.beginLasso(
                    with: HandDrawingInputSample(
                        location: CGPoint(x: 18, y: y - 6),
                        timestamp: 0
                    ),
                    engine: engine
                )
            )
            controller.appendSamples(
                [
                    HandDrawingInputSample(
                        location: CGPoint(x: 102, y: y - 6),
                        timestamp: 0.1
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 102, y: y + 6),
                        timestamp: 0.2
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 18, y: y + 6),
                        timestamp: 0.3
                    )
                ]
            )
            return controller.endLasso(engine: &engine)
        }

        let thinStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            samplePoints: [
                CGPoint(x: 25, y: 42),
                CGPoint(x: 60, y: 42),
                CGPoint(x: 95, y: 42)
            ],
            sampleForces: [0.35, 0.35, 0.35]
        )
        var thinEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "lasso-pressure-thin-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [thinStroke]
            )
        )

        XCTAssertTrue(applyNarrowLasso(to: &thinEngine, y: 42))
        XCTAssertEqual(thinEngine.state.selectedStrokeIDs, [thinStroke.id])

        let thickStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            samplePoints: [
                CGPoint(x: 25, y: 92),
                CGPoint(x: 60, y: 92),
                CGPoint(x: 95, y: 92)
            ],
            sampleForces: [1, 1, 1]
        )
        var thickEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "lasso-pressure-thick-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [thickStroke]
            )
        )

        XCTAssertFalse(applyNarrowLasso(to: &thickEngine, y: 92))
        XCTAssertTrue(thickEngine.state.selectedStrokeIDs.isEmpty)
    }

    func testHandDrawingLassoToolControllerUsesTiltedStampFootprintForEnclosure() {
        func applyCompactLasso(
            to engine: inout HandDrawingEditorEngine
        ) -> Bool {
            var controller = HandDrawingLassoToolController()
            XCTAssertTrue(
                controller.beginLasso(
                    with: HandDrawingInputSample(
                        location: CGPoint(x: 55, y: 50),
                        timestamp: 0
                    ),
                    engine: engine
                )
            )
            controller.appendSamples(
                [
                    HandDrawingInputSample(
                        location: CGPoint(x: 65, y: 50),
                        timestamp: 0.1
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 65, y: 70),
                        timestamp: 0.2
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 55, y: 70),
                        timestamp: 0.3
                    )
                ]
            )
            return controller.endLasso(engine: &engine)
        }

        let circularStroke = makeHandDrawingTestStroke(
            id: UUID(),
            baseSize: 20,
            samplePoints: [CGPoint(x: 60, y: 60)],
            sampleForces: [0.5]
        )
        var circularEngine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "lasso-circle-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [circularStroke]
            )
        )

        XCTAssertTrue(applyCompactLasso(to: &circularEngine))
        XCTAssertEqual(circularEngine.state.selectedStrokeIDs, [circularStroke.id])

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
                    id: "lasso-tilt-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                strokes: [tiltedStroke]
            )
        )

        XCTAssertFalse(applyCompactLasso(to: &tiltedEngine))
        XCTAssertTrue(tiltedEngine.state.selectedStrokeIDs.isEmpty)
    }

    func testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke() {
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
                    id: "lasso-active-layer-paper",
                    size: CGSize(width: 140, height: 140)
                ),
                layers: [inactiveLayer, activeLayer],
                activeLayerID: activeLayer.id
            )
        )
        var controller = HandDrawingLassoToolController()

        XCTAssertTrue(
            controller.beginLasso(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 44),
                    timestamp: 0
                ),
                engine: engine
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
        XCTAssertEqual(engine.state.selectedStrokeIDs, [activeStroke.id])
        XCTAssertFalse(engine.state.selectedStrokeIDs.contains(inactiveStroke.id))
    }

    func testHandDrawingLassoToolControllerDoesNotBeginOnHiddenOrLockedActiveLayer() {
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
            let engine = makeEngine(
                isVisible: configuration.0,
                isLocked: configuration.1
            )
            var controller = HandDrawingLassoToolController()

            XCTAssertFalse(
                controller.beginLasso(
                    with: HandDrawingInputSample(
                        location: CGPoint(x: 18, y: 44),
                        timestamp: 0
                    ),
                    engine: engine
                )
            )
            XCTAssertTrue(controller.points.isEmpty)
        }
    }
}
