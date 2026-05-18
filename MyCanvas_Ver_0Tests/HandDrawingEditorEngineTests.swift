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
        XCTAssertTrue(
            engine.selectStrokes(withIDs: [firstStroke.id, secondStroke.id])
        )
        XCTAssertTrue(
            engine.apply(command: .deselectAll)
        )

        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(
            engine.state.selectedStrokeIDs,
            [firstStroke.id, secondStroke.id]
        )
        XCTAssertEqual(engine.state.document.strokes.count, 2)
        XCTAssertTrue(engine.canRedo)

        XCTAssertTrue(engine.redo())
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(engine.state.document.strokes.count, 2)
    }

    func testHandDrawingEditorEngineLayerSwitchClearsSelectionAndRestoresOnUndoRedo() {
        let baseStroke = makeHandDrawingTestStroke(id: UUID())
        let detailStroke = makeHandDrawingTestStroke(
            id: UUID(),
            transform: HandDrawingStrokeTransform(translationY: 18)
        )
        let baseLayer = makeHandDrawingTestLayer(
            name: "Base",
            strokes: [baseStroke]
        )
        let detailLayer = makeHandDrawingTestLayer(
            name: "Detail",
            strokes: [detailStroke]
        )
        var engine = HandDrawingEditorEngine(
            document: makeHandDrawingLayeredTestDocument(
                layers: [baseLayer, detailLayer],
                activeLayerID: detailLayer.id
            )
        )

        XCTAssertEqual(engine.state.activeLayerID, detailLayer.id)
        XCTAssertTrue(engine.selectStrokes(withIDs: [detailStroke.id]))

        XCTAssertTrue(
            engine.apply(command: .layer(.setActive(id: baseLayer.id)))
        )
        XCTAssertEqual(engine.state.activeLayerID, baseLayer.id)
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(engine.state.document.strokes.map(\.id), [baseStroke.id])

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.state.activeLayerID, detailLayer.id)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [detailStroke.id])
        XCTAssertEqual(engine.state.document.strokes.map(\.id), [detailStroke.id])

        XCTAssertTrue(engine.redo())
        XCTAssertEqual(engine.state.activeLayerID, baseLayer.id)
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(engine.state.document.strokes.map(\.id), [baseStroke.id])
    }

    func testHandDrawingEditorEngineLayerMutationsRoundTripThroughUndoRedo() throws {
        let detailStroke = makeHandDrawingTestStroke(id: UUID())
        let baseLayer = makeHandDrawingTestLayer(
            name: "Base",
            strokes: [makeHandDrawingTestStroke(id: UUID())]
        )
        let detailLayer = makeHandDrawingTestLayer(
            name: "Detail",
            strokes: [detailStroke]
        )
        var engine = HandDrawingEditorEngine(
            document: makeHandDrawingLayeredTestDocument(
                layers: [baseLayer, detailLayer],
                activeLayerID: detailLayer.id
            )
        )

        XCTAssertTrue(engine.selectStrokes(withIDs: [detailStroke.id]))
        XCTAssertTrue(
            engine.apply(command: .layer(.addLayer(name: nil)))
        )
        let newLayerID = engine.state.activeLayerID
        XCTAssertEqual(engine.state.document.layers.count, 3)
        XCTAssertEqual(engine.state.document.layers.last?.id, newLayerID)
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(
            engine.state.document.layer(withID: newLayerID)?.name,
            "Layer 3"
        )

        XCTAssertTrue(
            engine.apply(
                command: .layer(
                    .renameLayer(id: newLayerID, name: "Notes")
                )
            )
        )
        XCTAssertTrue(
            engine.apply(
                command: .layer(
                    .setVisibility(id: newLayerID, isVisible: false)
                )
            )
        )
        XCTAssertTrue(
            engine.apply(
                command: .layer(
                    .setLocked(id: newLayerID, isLocked: true)
                )
            )
        )
        XCTAssertTrue(
            engine.apply(
                command: .layer(
                    .moveLayer(id: newLayerID, toIndex: 0)
                )
            )
        )

        assertLayer(
            try XCTUnwrap(engine.state.document.layer(withID: newLayerID)),
            name: "Notes",
            isVisible: false,
            isLocked: true
        )
        XCTAssertEqual(engine.state.document.layers.first?.id, newLayerID)

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(
            engine.state.document.layers.firstIndex(where: { $0.id == newLayerID }),
            2
        )

        XCTAssertTrue(engine.undo())
        assertLayer(
            try XCTUnwrap(engine.state.document.layer(withID: newLayerID)),
            name: "Notes",
            isVisible: false,
            isLocked: false
        )

        XCTAssertTrue(engine.undo())
        assertLayer(
            try XCTUnwrap(engine.state.document.layer(withID: newLayerID)),
            name: "Notes",
            isVisible: true,
            isLocked: false
        )

        XCTAssertTrue(engine.undo())
        assertLayer(
            try XCTUnwrap(engine.state.document.layer(withID: newLayerID)),
            name: "Layer 3",
            isVisible: true,
            isLocked: false
        )

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(
            engine.state.document.layers.map(\.id),
            [baseLayer.id, detailLayer.id]
        )
        XCTAssertEqual(engine.state.activeLayerID, detailLayer.id)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [detailStroke.id])

        for _ in 0..<5 {
            XCTAssertTrue(engine.redo())
        }
        XCTAssertEqual(engine.state.activeLayerID, newLayerID)
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(engine.state.document.layers.first?.id, newLayerID)
        assertLayer(
            try XCTUnwrap(engine.state.document.layer(withID: newLayerID)),
            name: "Notes",
            isVisible: false,
            isLocked: true
        )
    }

    func testHandDrawingEditorEngineDeleteCurrentLayerSwitchesToAdjacentLayer() {
        let baseLayer = makeHandDrawingTestLayer(
            name: "Base",
            strokes: [makeHandDrawingTestStroke(id: UUID())]
        )
        let detailStroke = makeHandDrawingTestStroke(id: UUID())
        let detailLayer = makeHandDrawingTestLayer(
            name: "Detail",
            strokes: [detailStroke]
        )
        let overlayLayer = makeHandDrawingTestLayer(
            name: "Overlay",
            strokes: [makeHandDrawingTestStroke(id: UUID())]
        )
        var engine = HandDrawingEditorEngine(
            document: makeHandDrawingLayeredTestDocument(
                layers: [baseLayer, detailLayer, overlayLayer],
                activeLayerID: detailLayer.id
            )
        )

        XCTAssertTrue(engine.selectStrokes(withIDs: [detailStroke.id]))
        XCTAssertTrue(
            engine.apply(command: .layer(.deleteLayer(id: detailLayer.id)))
        )
        XCTAssertEqual(
            engine.state.document.layers.map(\.id),
            [baseLayer.id, overlayLayer.id]
        )
        XCTAssertEqual(engine.state.activeLayerID, overlayLayer.id)
        XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
        XCTAssertEqual(
            engine.state.document.strokes.map(\.id),
            overlayLayer.strokes.map(\.id)
        )

        XCTAssertTrue(engine.undo())
        XCTAssertEqual(
            engine.state.document.layers.map(\.id),
            [baseLayer.id, detailLayer.id, overlayLayer.id]
        )
        XCTAssertEqual(engine.state.activeLayerID, detailLayer.id)
        XCTAssertEqual(engine.state.selectedStrokeIDs, [detailStroke.id])
    }

    func testHandDrawingEditorEnginePreventsDeletingLastLayer() {
        let onlyLayer = makeHandDrawingTestLayer(
            name: "Only",
            strokes: [makeHandDrawingTestStroke(id: UUID())]
        )
        var engine = HandDrawingEditorEngine(
            document: makeHandDrawingLayeredTestDocument(
                layers: [onlyLayer],
                activeLayerID: onlyLayer.id
            )
        )

        XCTAssertFalse(
            engine.apply(command: .layer(.deleteLayer(id: onlyLayer.id)))
        )
        XCTAssertEqual(engine.state.document.layers.map(\.id), [onlyLayer.id])
        XCTAssertEqual(engine.state.activeLayerID, onlyLayer.id)
        XCTAssertFalse(engine.canUndo)
        XCTAssertNil(engine.consumeDirtyRegion())
    }

    private func assertLayer(
        _ layer: HandDrawingLayer,
        name: String,
        isVisible: Bool,
        isLocked: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(layer.name, name, file: file, line: line)
        XCTAssertEqual(layer.isVisible, isVisible, file: file, line: line)
        XCTAssertEqual(layer.isLocked, isLocked, file: file, line: line)
    }
}
