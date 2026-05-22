import CoreGraphics
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

#if canImport(UIKit)
@MainActor
final class HandDrawingEditorCoordinatorBrushPresetTests: XCTestCase {
    func testHandDrawingEditorCoordinatorCommitsSelectedBrushPresetWithFullDynamics() throws {
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "coordinator-preset-paper",
                size: CGSize(width: 120, height: 120)
            )
        )
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: document
            )
        )
        var paletteState: HandDrawingToolPaletteState?
        coordinator.onPaletteStateChange = { paletteState = $0 }
        coordinator.activate()

        let selectedColor = HandDrawingColor(
            red: 0.84,
            green: 0.26,
            blue: 0.19,
            alpha: 1
        )
        let selectedPreset = try XCTUnwrap(paletteState?.availableBrushPresets.last)
        coordinator.selectColor(selectedColor)
        coordinator.selectBrushPreset(selectedPreset.id)
        coordinator.handlePencilStrokeBegan(
            HandDrawingInputSample(
                location: CGPoint(x: 24, y: 30),
                force: 0.4,
                timestamp: 0
            )
        )
        coordinator.handlePencilStrokeEnded([
            HandDrawingInputSample(
                location: CGPoint(x: 88, y: 42),
                force: 0.9,
                timestamp: 0.1,
                azimuthRadians: 0.5,
                altitudeRadians: .pi / 3
            )
        ])

        let submission = try XCTUnwrap(coordinator.makeCommitSubmissionIfNeeded())
        let committedDocument = try HandDrawingDocumentCodec.decodeDocument(
            from: submission.documentData
        )
        let committedStroke = try XCTUnwrap(committedDocument.strokes.last)

        XCTAssertEqual(
            committedStroke.brush,
            selectedPreset.makeBrushStyle(color: selectedColor)
        )
    }

    func testHandDrawingEditorCoordinatorRestoresCustomBrushPresetFromDocument() throws {
        let customBrush = HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.21, green: 0.35, blue: 0.82, alpha: 1),
            baseSize: 8,
            opacity: 0.72,
            pressureCurveExponent: 1.65,
            minSizeRatio: 0.18,
            maxSizeRatio: 0.91,
            tiltSizeInfluence: 0.44,
            tiltOpacityInfluence: 0.12
        )
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "coordinator-restore-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [
                HandDrawingStroke(
                    brush: customBrush,
                    samplePoints: [
                        HandDrawingSamplePoint(
                            point: CGPoint(x: 22, y: 28),
                            force: 0.55,
                            timestamp: 0
                        ),
                        HandDrawingSamplePoint(
                            point: CGPoint(x: 86, y: 44),
                            force: 0.9,
                            timestamp: 0.1,
                            azimuthRadians: 0.8,
                            altitudeRadians: .pi / 4
                        )
                    ]
                )
            ]
        )
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: document
            )
        )
        var paletteState: HandDrawingToolPaletteState?
        coordinator.onPaletteStateChange = { paletteState = $0 }
        coordinator.activate()

        let selectedPresetID = try XCTUnwrap(paletteState?.selectedBrushPresetID)
        let restoredPreset = try XCTUnwrap(
            paletteState?.availableBrushPresets.first {
                $0.id == selectedPresetID
            }
        )
        coordinator.handlePencilStrokeBegan(
            HandDrawingInputSample(
                location: CGPoint(x: 20, y: 82),
                force: 0.45,
                timestamp: 1
            )
        )
        coordinator.handlePencilStrokeEnded([
            HandDrawingInputSample(
                location: CGPoint(x: 90, y: 92),
                force: 1,
                timestamp: 1.1,
                azimuthRadians: 0.7,
                altitudeRadians: .pi / 5
            )
        ])

        let submission = try XCTUnwrap(coordinator.makeCommitSubmissionIfNeeded())
        let committedDocument = try HandDrawingDocumentCodec.decodeDocument(
            from: submission.documentData
        )
        let committedStroke = try XCTUnwrap(committedDocument.strokes.last)

        XCTAssertEqual(restoredPreset.id, HandDrawingEditorCoordinator.defaultBrushPresets[1].id)
        XCTAssertEqual(
            restoredPreset.makeBrushStyle(color: customBrush.color),
            customBrush
        )
        XCTAssertEqual(committedStroke.brush, customBrush)
    }
}

@MainActor
final class HandDrawingEditorCoordinatorSurfaceStateTests: XCTestCase {
    func testHandDrawingEditorCoordinatorPublishesSeparatedCommittedAndRealtimeHostState() throws {
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "coordinator-surface-paper",
                size: CGSize(width: 120, height: 120)
            )
        )
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: document
            )
        )
        var latestSurfaceState: HandDrawingCanvasSurfaceState?
        coordinator.onSurfaceStateChange = { latestSurfaceState = $0 }

        coordinator.activate()

        let initialSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNotNil(initialSurfaceState.committedHost.output.image)
        XCTAssertNil(initialSurfaceState.realtimeDraftHost.packet)
        XCTAssertEqual(initialSurfaceState.realtimeDraftHost.revision, 0)
        XCTAssertTrue(initialSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNil(initialSurfaceState.interactionOverlay.selectedStrokeBounds)

        coordinator.handlePencilStrokeBegan(
            makeHandDrawingCoordinatorInputSample(
                x: 24,
                y: 30,
                timestamp: 0
            )
        )

        let activeDraftSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNotNil(activeDraftSurfaceState.committedHost.output.image)
        let realtimePacket = try XCTUnwrap(activeDraftSurfaceState.realtimeDraftHost.packet)
        XCTAssertGreaterThan(activeDraftSurfaceState.realtimeDraftHost.revision, 0)
        XCTAssertFalse(realtimePacket.committedResolvedStamps.tailStamps.isEmpty)
        XCTAssertTrue(realtimePacket.predictedTail.isEmpty)
        XCTAssertTrue(activeDraftSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNil(activeDraftSurfaceState.interactionOverlay.selectedStrokeBounds)
    }

    func testHandDrawingEditorCoordinatorKeepsInteractionOverlaySeparateFromRealtimeDraftHost() throws {
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: makeHandDrawingTestDocument()
            )
        )
        var latestSurfaceState: HandDrawingCanvasSurfaceState?
        coordinator.onSurfaceStateChange = { latestSurfaceState = $0 }
        coordinator.activate()
        coordinator.selectTool(.lasso)

        coordinator.handlePencilStrokeBegan(
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 40,
                timestamp: 0
            )
        )
        coordinator.handlePencilStrokeMoved([
            makeHandDrawingCoordinatorInputSample(
                x: 110,
                y: 40,
                timestamp: 0.1
            ),
            makeHandDrawingCoordinatorInputSample(
                x: 110,
                y: 80,
                timestamp: 0.2
            ),
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 80,
                timestamp: 0.3
            )
        ])

        let activeLassoSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNil(activeLassoSurfaceState.realtimeDraftHost.packet)
        XCTAssertEqual(activeLassoSurfaceState.interactionOverlay.lassoPathPoints.count, 4)
        XCTAssertNil(activeLassoSurfaceState.interactionOverlay.selectedStrokeBounds)

        coordinator.handlePencilStrokeEnded([
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 40,
                timestamp: 0.4
            )
        ])

        let selectedSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNil(selectedSurfaceState.realtimeDraftHost.packet)
        XCTAssertTrue(selectedSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNotNil(selectedSurfaceState.interactionOverlay.selectedStrokeBounds)
    }

    func testHandDrawingEditorCoordinatorPublishesPredictedTailSeparatelyFromCommittedRealtimePacket() throws {
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: HandDrawingDocument(
                    paper: HandDrawingPaper(
                        id: "coordinator-predicted-tail-paper",
                        size: CGSize(width: 120, height: 120)
                    )
                )
            )
        )
        var latestSurfaceState: HandDrawingCanvasSurfaceState?
        coordinator.onSurfaceStateChange = { latestSurfaceState = $0 }
        coordinator.activate()

        coordinator.handlePencilStrokeBegan(
            makeHandDrawingCoordinatorInputSample(
                x: 18,
                y: 24,
                timestamp: 0
            )
        )
        coordinator.handlePencilStrokeMoved(
            HandDrawingLiveInputBatch(
                committedSamples: [
                    makeHandDrawingCoordinatorInputSample(
                        x: 52,
                        y: 40,
                        timestamp: 0.1
                    )
                ],
                predictedSamples: [
                    makeHandDrawingCoordinatorInputSample(
                        x: 86,
                        y: 56,
                        timestamp: 0.2
                    )
                ]
            )
        )

        let realtimePacket = try XCTUnwrap(latestSurfaceState?.realtimeDraftHost.packet)
        XCTAssertEqual(realtimePacket.committedSamples.stablePrefixCount, 1)
        XCTAssertEqual(realtimePacket.committedSamples.tailSamples.count, 1)
        XCTAssertEqual(realtimePacket.predictedTail.normalizedSamples.count, 1)
        XCTAssertFalse(realtimePacket.predictedTail.resolvedStamps.isEmpty)
    }
}

private func makeHandDrawingEditorCoordinatorTestContext(
    document: HandDrawingDocument
) throws -> CanvasHandDrawingEditorContext {
    CanvasHandDrawingEditorContext(
        itemID: CanvasItemID(),
        documentID: UUID(),
        paper: document.paper.canvasPaperSpec,
        documentData: try HandDrawingDocumentCodec.makeDocumentData(for: document),
        isEmpty: document.isEmpty,
        storage: .bundle,
        didMigrateLegacyDocument: false
    )
}

private func makeHandDrawingCoordinatorInputSample(
    x: CGFloat,
    y: CGFloat,
    timestamp: TimeInterval
) -> HandDrawingInputSample {
    HandDrawingInputSample(
        location: CGPoint(x: x, y: y),
        force: 0.8,
        timestamp: timestamp
    )
}
#endif
