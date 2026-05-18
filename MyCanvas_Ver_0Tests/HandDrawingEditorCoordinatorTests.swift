import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingLayerPanelStateTests: XCTestCase {
    func testLayerPanelStateBuilderUsesTopFirstOrderingAndMoveCapabilities() {
        let baseLayerID = UUID()
        let detailLayerID = UUID()
        var document = makeHandDrawingLayeredTestDocument(
            layers: [
                makeHandDrawingTestLayer(
                    id: baseLayerID,
                    name: "Base",
                    strokes: [makeHandDrawingTestStroke()]
                ),
                makeHandDrawingTestLayer(
                    id: detailLayerID,
                    name: "Detail",
                    strokes: [makeHandDrawingTestStroke()]
                )
            ],
            activeLayerID: detailLayerID
        )

        let initialPanelState = HandDrawingLayerPanelStateBuilder.makeState(
            from: document
        )
        XCTAssertEqual(initialPanelState.buttonTitle, "Layers (2)")
        XCTAssertEqual(initialPanelState.buttonSubtitle, "Detail")
        XCTAssertEqual(initialPanelState.layers.map(\.name), ["Detail", "Base"])
        XCTAssertTrue(initialPanelState.layers[0].isActive)
        XCTAssertFalse(initialPanelState.layers[0].canMoveUp)
        XCTAssertTrue(initialPanelState.layers[0].canMoveDown)
        XCTAssertTrue(initialPanelState.layers[1].canMoveUp)
        XCTAssertFalse(initialPanelState.layers[1].canMoveDown)

        XCTAssertTrue(document.moveLayer(withID: detailLayerID, toIndex: 0))
        let movedPanelState = HandDrawingLayerPanelStateBuilder.makeState(
            from: document
        )
        XCTAssertEqual(movedPanelState.layers.map(\.name), ["Base", "Detail"])
        XCTAssertFalse(movedPanelState.layers[0].isActive)
        XCTAssertTrue(movedPanelState.layers[1].isActive)
    }

    func testLayerPanelStateBuilderReflectsHiddenLockedAndInsertedLayerState() {
        let layerID = UUID()
        var document = makeHandDrawingLayeredTestDocument(
            layers: [
                makeHandDrawingTestLayer(
                    id: layerID,
                    name: "Draft",
                    strokes: [makeHandDrawingTestStroke()]
                )
            ],
            activeLayerID: layerID
        )

        XCTAssertTrue(document.setLayerVisibility(withID: layerID, isVisible: false))
        let hiddenLayerState = HandDrawingLayerPanelStateBuilder
            .makeState(from: document)
            .layers[0]
        XCTAssertFalse(hiddenLayerState.isVisible)
        XCTAssertEqual(hiddenLayerState.subtitle, "Current · Hidden")

        XCTAssertTrue(document.setLayerVisibility(withID: layerID, isVisible: true))
        XCTAssertTrue(document.setLayerLock(withID: layerID, isLocked: true))
        let lockedLayerState = HandDrawingLayerPanelStateBuilder
            .makeState(from: document)
            .layers[0]
        XCTAssertTrue(lockedLayerState.isLocked)
        XCTAssertEqual(lockedLayerState.subtitle, "Current · Locked")

        _ = document.setLayerLock(withID: layerID, isLocked: false)
        let insertedLayer = document.insertLayer()
        let insertedLayerState = HandDrawingLayerPanelStateBuilder.makeState(
            from: document
        )
        XCTAssertEqual(insertedLayerState.buttonTitle, "Layers (2)")
        XCTAssertEqual(insertedLayerState.buttonSubtitle, insertedLayer.name)
        XCTAssertEqual(
            insertedLayerState.layers.map(\.name),
            [insertedLayer.name, "Draft"]
        )
        XCTAssertTrue(insertedLayerState.layers[0].isActive)
        XCTAssertTrue(insertedLayerState.layers[0].canDelete)
        XCTAssertEqual(insertedLayerState.layers[0].subtitle, "Current")
    }
}
