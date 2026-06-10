import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditorSessionAlignmentOverlayTests: XCTestCase {
    func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.camera = CanvasCamera(
            center: .zero,
            zoomScale: 2,
            viewportSize: CGSize(width: 600, height: 400)
        )
        session.alignmentInteractionState = CanvasAlignmentInteractionState(
            itemID: item.id,
            guides: [
                CanvasAlignmentGuide(
                    orientation: .vertical,
                    worldStart: CGPoint(x: 50, y: -20),
                    worldEnd: CGPoint(x: 50, y: 80),
                    movingAnchor: .centerX,
                    referenceAnchor: .centerX,
                    referenceSource: .board
                )
            ],
            xMatch: CanvasAlignmentMatch(
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board,
                referenceCoordinate: 50,
                distanceInWorld: 0
            ),
            yMatch: nil
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case let .alignment(payload) = interactionOverlay.payload else {
            XCTFail("Expected alignment interaction overlay payload.")
            return
        }

        XCTAssertTrue(payload.isActive)
        XCTAssertEqual(payload.xMatch?.referenceSource, .board)
        XCTAssertEqual(payload.guideSegments.count, 1)
        XCTAssertEqual(
            payload.guideSegments.first?.start,
            CGPoint(x: 400, y: 160)
        )
        XCTAssertEqual(
            payload.guideSegments.first?.end,
            CGPoint(x: 400, y: 360)
        )
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.workspaceMode = .reading
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()

        XCTAssertNil(snapshot.interactionOverlay)
    }

    func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: item.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case .rotation = interactionOverlay.payload else {
            XCTFail("Expected rotation interaction overlay to win priority.")
            return
        }
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.inlineEditState = CanvasInlineEditState(item: item)
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()

        XCTAssertNil(snapshot.interactionOverlay)
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineCropEdit() throws {
        let item = try makeAlignmentOverlayTestImageItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.inlineEditState = CanvasInlineEditState(item: item)
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()

        XCTAssertNil(snapshot.interactionOverlay)
    }

    func testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState() {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        let baselineSnapshot = session.currentBoardHistorySnapshot()

        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: item.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: item.id
        )

        let historySnapshot = session.currentBoardHistorySnapshot()

        XCTAssertEqual(historySnapshot, baselineSnapshot)
    }

    func testApplyBoardRuntimeStateClearsTransientAlignmentState() {
        let currentItem = makeAlignmentOverlayTestItem()
        let replacementItem = CanvasTextItem(
            text: "restored",
            center: CGPoint(x: 160, y: 80),
            size: CGSize(width: 110, height: 44)
        )
        let session = makeAlignmentOverlayTestSession(with: currentItem)
        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: currentItem.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: currentItem.id
        )

        session.applyBoardRuntimeState(
            makeAlignmentOverlayTestRuntimeState(
                items: [.text(replacementItem)],
                selectedItemID: replacementItem.id
            )
        )

        XCTAssertNil(session.rotationInteractionState)
        XCTAssertNil(session.alignmentInteractionState)
        XCTAssertEqual(
            session.scene.boardItem(withID: replacementItem.id)?.id,
            replacementItem.id
        )
        XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
    }

    func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithoutActiveBoard() {
        let currentItem = makeAlignmentOverlayTestItem()
        let replacementItem = CanvasTextItem(
            text: "undo target",
            center: CGPoint(x: 180, y: 120),
            size: CGSize(width: 120, height: 48)
        )
        let session = makeAlignmentOverlayTestSession(with: currentItem)
        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: currentItem.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: currentItem.id
        )

        session.applyBoardHistorySnapshot(
            BoardHistorySnapshot(
                items: [.text(replacementItem)],
                boardState: nil,
                interactionState: CanvasInteractionState(
                    selectedItemID: replacementItem.id
                )
            )
        )

        XCTAssertNil(session.rotationInteractionState)
        XCTAssertNil(session.alignmentInteractionState)
        XCTAssertEqual(
            session.scene.boardItem(withID: replacementItem.id)?.id,
            replacementItem.id
        )
        XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
    }

    func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithActiveBoard() {
        let currentItem = makeAlignmentOverlayTestItem()
        let replacementItem = CanvasTextItem(
            text: "redo target",
            center: CGPoint(x: 220, y: 140),
            size: CGSize(width: 140, height: 52)
        )
        let session = makeAlignmentOverlayTestSession(with: currentItem)
        session.applyBoardRuntimeState(
            makeAlignmentOverlayTestRuntimeState(
                items: [.text(currentItem)],
                selectedItemID: currentItem.id
            )
        )
        session.rotationInteractionState = CanvasRotationInteractionState(
            itemID: currentItem.id
        )
        session.alignmentInteractionState = makeAlignmentOverlayTestState(
            itemID: currentItem.id
        )

        session.applyBoardHistorySnapshot(
            BoardHistorySnapshot(
                items: [.text(replacementItem)],
                boardState: nil,
                interactionState: CanvasInteractionState(
                    selectedItemID: replacementItem.id
                )
            )
        )

        XCTAssertNil(session.rotationInteractionState)
        XCTAssertNil(session.alignmentInteractionState)
        XCTAssertEqual(
            session.scene.boardItem(withID: replacementItem.id)?.id,
            replacementItem.id
        )
        XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
    }

    func testMakeCanvasSnapshotProducesSelectionHighlightsAndGroupOverlayForMultiSelection() {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -40, y: 10),
            size: CGSize(width: 80, height: 40),
            rotationRadians: .pi / 12
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 60, y: 40),
            size: CGSize(width: 120, height: 50),
            rotationRadians: -.pi / 18
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try? XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(snapshot.selectionHighlights.map(\.itemID), [firstItem.id, secondItem.id])
        XCTAssertEqual(snapshot.selectionHighlights.count, 2)
        guard
            let editOverlay,
            case let .selection(payload) = editOverlay.payload,
            case let .group(primaryItemID, memberItemIDs) = payload.subject
        else {
            XCTFail("Expected multi-selection snapshot to expose a group selection overlay.")
            return
        }

        let expectedWorldBounds = firstItem.worldBounds
            .union(secondItem.worldBounds)
            .standardized
        XCTAssertEqual(primaryItemID, secondItem.id)
        XCTAssertEqual(memberItemIDs, [firstItem.id, secondItem.id])
        XCTAssertEqual(editOverlay.activeWorldQuad.boundingRect.standardized, expectedWorldBounds)
        XCTAssertEqual(editOverlay.handles.count, 4)
    }

    func testMakeCanvasSnapshotOmitsResizeHandlesForSingleTextSelection() throws {
        let item = CanvasTextItem(
            text: "single text",
            center: CGPoint(x: 40, y: 20),
            size: CGSize(width: 120, height: 48)
        )
        let session = makeAlignmentOverlayTestSession(with: item)

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        guard case let .selection(payload) = editOverlay.payload else {
            XCTFail("Expected single text selection overlay payload.")
            return
        }

        XCTAssertEqual(editOverlay.itemID, item.id)
        XCTAssertTrue(editOverlay.handles.isEmpty)
        let rotateAffordance = try XCTUnwrap(payload.rotateAffordance)
        XCTAssertFalse(rotateAffordance.handle.screenCenter.x.isNaN)
    }

    func testMakeCanvasSnapshotKeepsResizeHandlesForSingleImageSelection() throws {
        let item = try makeAlignmentOverlayTestImageItem()
        let session = makeAlignmentOverlayTestSession(with: item)

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(editOverlay.itemID, item.id)
        XCTAssertEqual(editOverlay.handles.count, 4)
    }

    func testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection() throws {
        let item = CanvasMarkdownItem(
            markdownSource: "## Markdown",
            center: CGPoint(x: 40, y: 20),
            size: CGSize(width: 140, height: 84)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.markdown(item)],
            selectedItemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(editOverlay.itemID, item.id)
        XCTAssertEqual(editOverlay.handles.map(\.role), [.top, .trailing, .bottom, .leading])
    }

    func testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection() throws {
        let item = CanvasArrowItem(
            center: CGPoint(x: 40, y: 20),
            size: CGSize(width: 180, height: 72),
            rotationRadians: .pi / 6
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.arrow(item)],
            selectedItemID: item.id
        )

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        guard case let .selection(payload) = editOverlay.payload else {
            XCTFail("Expected single arrow selection overlay payload.")
            return
        }

        XCTAssertEqual(editOverlay.itemID, item.id)
        XCTAssertEqual(editOverlay.handles.map(\.role), [.arrowStart, .arrowEnd])
        XCTAssertNil(payload.rotateAffordance)
        XCTAssertNotNil(payload.outlineScreenPath)
        XCTAssertNotNil(payload.translationScreenPath)
    }

    func testMakeCanvasSnapshotUsesWidthOnlyHandlesForAllMarkdownMultiSelection() throws {
        let firstItem = CanvasMarkdownItem(
            markdownSource: "## First",
            center: CGPoint(x: -60, y: 0),
            size: CGSize(width: 140, height: 84)
        )
        let secondItem = CanvasMarkdownItem(
            markdownSource: "## Second",
            center: CGPoint(x: 80, y: 40),
            size: CGSize(width: 180, height: 96)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.markdown(firstItem), .markdown(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(editOverlay.handles.map(\.role), [.top, .trailing, .bottom, .leading])
    }

    func testResolvePointerTargetHitsSelectionTranslationAreaForSingleSelectionOutline() throws {
        let item = CanvasTextItem(
            text: "single",
            center: .zero,
            size: CGSize(width: 160, height: 80)
        )
        let session = makeAlignmentOverlayTestSession(with: item)
        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)

        let pressContext = session.resolvePointerTarget(
            at: editOverlay.activeScreenQuad.leadingMidpoint,
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case .selectionTranslationArea = pressContext.targetKind else {
            XCTFail("Expected single-selection outline hit to resolve as selectionTranslationArea.")
            return
        }
        XCTAssertEqual(pressContext.targetItemID, item.id)
    }

    func testResolvePointerTargetKeepsSingleSelectionBodyAsSelectedItemBody() {
        let item = CanvasTextItem(
            text: "single body",
            center: CGPoint(x: 20, y: 10),
            size: CGSize(width: 180, height: 90)
        )
        let session = makeAlignmentOverlayTestSession(with: item)
        _ = session.makeCanvasSnapshot()

        let pressContext = session.resolvePointerTarget(
            at: session.camera.worldToViewport(item.center),
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case .selectedItemBody = pressContext.targetKind else {
            XCTFail("Expected single-selection body hit to stay as selectedItemBody.")
            return
        }
        XCTAssertEqual(pressContext.targetItemID, item.id)
    }

    func testResolvePointerTargetHitsSelectionTranslationAreaForMultiSelectionInteriorBlank() throws {
        let firstItem = CanvasTextItem(
            text: "left",
            center: CGPoint(x: -120, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "right",
            center: CGPoint(x: 120, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        let interiorBlankPoint = editOverlay.activeScreenQuad.center

        XCTAssertFalse(
            snapshot.items.contains(where: { item in
                item.screenQuad.contains(interiorBlankPoint)
            })
        )

        let pressContext = session.resolvePointerTarget(
            at: interiorBlankPoint,
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case .selectionTranslationArea = pressContext.targetKind else {
            XCTFail("Expected multi-selection interior blank hit to resolve as selectionTranslationArea.")
            return
        }
        XCTAssertEqual(pressContext.targetItemID, secondItem.id)
    }

    func testResolvePointerTargetTreatsEverySelectedMemberBodyAsSelected() {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -30, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 70, y: 20),
            size: CGSize(width: 100, height: 44)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        _ = session.makeCanvasSnapshot()

        let pressContext = session.resolvePointerTarget(
            at: session.camera.worldToViewport(firstItem.center),
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case .selectedItemBody = pressContext.targetKind else {
            XCTFail("Expected every selected member body to resolve as selected.")
            return
        }
        XCTAssertEqual(pressContext.targetItemID, firstItem.id)
    }

    func testResolvePointerTargetHitsGroupSelectionHandleForMultiSelection() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -20, y: 10),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 80, y: 50),
            size: CGSize(width: 120, height: 60)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        let topLeadingHandle = try XCTUnwrap(
            editOverlay.handles.first(where: { $0.role == .topLeading })
        )

        let pressContext = session.resolvePointerTarget(
            at: topLeadingHandle.screenCenter,
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case let .groupSelectionHandle(role) = pressContext.targetKind else {
            XCTFail("Expected multi-selection handle hit to resolve as groupSelectionHandle.")
            return
        }
        XCTAssertEqual(role, .topLeading)
        XCTAssertEqual(pressContext.targetItemID, secondItem.id)
    }

    func testResolvePointerTargetHitsGroupWidthOnlySelectionHandleForMarkdownMultiSelection() throws {
        let firstItem = CanvasMarkdownItem(
            markdownSource: "## First",
            center: CGPoint(x: -40, y: 0),
            size: CGSize(width: 140, height: 84)
        )
        let secondItem = CanvasMarkdownItem(
            markdownSource: "## Second",
            center: CGPoint(x: 100, y: 50),
            size: CGSize(width: 180, height: 96)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.markdown(firstItem), .markdown(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        let leadingHandle = try XCTUnwrap(
            editOverlay.handles.first(where: { $0.role == .leading })
        )

        let pressContext = session.resolvePointerTarget(
            at: leadingHandle.screenCenter,
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case let .groupSelectionHandle(role) = pressContext.targetKind else {
            XCTFail("Expected all-markdown multi-selection handle hit to resolve as groupSelectionHandle.")
            return
        }
        XCTAssertEqual(role, .leading)
        XCTAssertEqual(pressContext.targetItemID, secondItem.id)
    }

    func testResolvePointerTargetHitsGroupRotateHandleForMultiSelection() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -10, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 90, y: 40),
            size: CGSize(width: 120, height: 60)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        guard case let .selection(payload) = editOverlay.payload else {
            XCTFail("Expected selection payload.")
            return
        }
        let rotateAffordance = try XCTUnwrap(payload.rotateAffordance)

        let pressContext = session.resolvePointerTarget(
            at: rotateAffordance.handle.screenCenter,
            interactionMetrics: makeAlignmentOverlayTestContextResolverMetrics()
        )

        guard case .groupRotateHandle = pressContext.targetKind else {
            XCTFail("Expected multi-selection rotate hit to resolve as groupRotateHandle.")
            return
        }
        XCTAssertEqual(pressContext.targetItemID, secondItem.id)
    }

    func testMakeCanvasSnapshotProducesAlignmentOverlayForGroupSelection() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -30, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 70, y: 20),
            size: CGSize(width: 100, height: 44)
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        session.alignmentInteractionState = CanvasAlignmentInteractionState(
            primaryItemID: secondItem.id,
            memberItemIDs: [firstItem.id, secondItem.id],
            guides: [
                CanvasAlignmentGuide(
                    orientation: .vertical,
                    worldStart: CGPoint(x: 30, y: -20),
                    worldEnd: CGPoint(x: 30, y: 60),
                    movingAnchor: .centerX,
                    referenceAnchor: .centerX,
                    referenceSource: .board
                )
            ],
            xMatch: CanvasAlignmentMatch(
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board,
                referenceCoordinate: 30,
                distanceInWorld: 0
            ),
            yMatch: nil
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case let .alignment(payload) = interactionOverlay.payload else {
            XCTFail("Expected alignment overlay payload for group selection.")
            return
        }

        XCTAssertEqual(interactionOverlay.itemID, secondItem.id)
        XCTAssertTrue(payload.isActive)
        XCTAssertEqual(payload.guideSegments.count, 1)
        XCTAssertEqual(payload.xMatch?.referenceSource, .board)
    }

    func testMakeCanvasSnapshotAppliesGroupRotationPreviewToOverlayBounds() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: 20, y: 0),
            size: CGSize(width: 40, height: 20)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 80, y: 40),
            size: CGSize(width: 60, height: 24)
        )
        let interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )
        let session = makeAlignmentOverlayTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: interactionState
        )
        let transformSnapshot = try XCTUnwrap(
            CanvasSelectionTransformSnapshot(
                scene: session.scene,
                interactionState: interactionState
            )
        )
        let rotatedGeometries = transformSnapshot.rotatedMemberGeometries(
            by: .pi / 2
        )
        session.rotationInteractionState = CanvasRotationInteractionState(
            primaryItemID: secondItem.id,
            memberItemIDs: [firstItem.id, secondItem.id]
        )
        session.rotationPreviewState = CanvasRotationPreviewState(
            snapshot: transformSnapshot,
            draftGeometries: rotatedGeometries,
            displayRotationRadians: .pi / 2
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        guard case let .rotation(payload) = interactionOverlay.payload else {
            XCTFail("Expected rotation overlay payload for group rotation.")
            return
        }

        let expectedBounds = CanvasSelectionTransformSnapshot.selectionBounds(
            for: rotatedGeometries
        )
        let expectedScreenCenter = session.camera.worldToViewport(
            CGPoint(x: expectedBounds.midX, y: expectedBounds.midY)
        )
        let actualBounds = editOverlay.activeWorldQuad.boundingRect.standardized
        XCTAssertEqual(interactionOverlay.itemID, secondItem.id)
        XCTAssertEqual(payload.currentRotationRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(payload.screenCenter.x, expectedScreenCenter.x, accuracy: 0.0001)
        XCTAssertEqual(payload.screenCenter.y, expectedScreenCenter.y, accuracy: 0.0001)
        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 0.0001)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.0001)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 0.0001)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 0.0001)
    }
}

private enum CanvasEditorSessionAlignmentOverlayTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeAlignmentOverlayTestSession(
    with item: CanvasTextItem
) -> CanvasEditorSession {
    makeAlignmentOverlayTestSession(
        items: [.text(item)],
        selectedItemID: item.id
    )
}

private func makeAlignmentOverlayTestSession(
    with item: CanvasImageItem
) -> CanvasEditorSession {
    makeAlignmentOverlayTestSession(
        items: [.image(item)],
        selectedItemID: item.id
    )
}

private func makeAlignmentOverlayTestSession(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID
) -> CanvasEditorSession {
    makeAlignmentOverlayTestSession(
        items: items,
        interactionState: CanvasInteractionState(selectedItemID: selectedItemID)
    )
}

private func makeAlignmentOverlayTestSession(
    items: [CanvasBoardItem],
    interactionState: CanvasInteractionState
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems(items)
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 600, height: 400)
    )
    session.interactionState = interactionState
    CanvasEditorSessionAlignmentOverlayTestRetainer.sessions.append(session)
    return session
}

private func makeAlignmentOverlayTestItem() -> CanvasTextItem {
    CanvasTextItem(
        text: "alignment overlay",
        center: CGPoint(x: 20, y: 20),
        size: CGSize(width: 80, height: 40)
    )
}

private func makeAlignmentOverlayTestState(
    itemID: CanvasItemID
) -> CanvasAlignmentInteractionState {
    CanvasAlignmentInteractionState(
        itemID: itemID,
        guides: [
            CanvasAlignmentGuide(
                orientation: .vertical,
                worldStart: CGPoint(x: 30, y: -20),
                worldEnd: CGPoint(x: 30, y: 60),
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board
            )
        ],
        xMatch: CanvasAlignmentMatch(
            movingAnchor: .centerX,
            referenceAnchor: .centerX,
            referenceSource: .board,
            referenceCoordinate: 30,
            distanceInWorld: 0
        ),
        yMatch: nil
    )
}

private func makeAlignmentOverlayTestRuntimeState(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID? = nil
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: UUID(),
        title: "Alignment Test Board",
        createdAt: Date(timeIntervalSince1970: 0),
        contentUpdatedAt: Date(timeIntervalSince1970: 0),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 0),
        items: items,
        boardState: nil,
        camera: CanvasCamera(
            center: .zero,
            zoomScale: 1,
            viewportSize: CGSize(width: 600, height: 400)
        ),
        interactionState: CanvasInteractionState(selectedItemID: selectedItemID),
        workspaceMode: .editing
    )
}

private func makeAlignmentOverlayTestImageItem() throws -> CanvasImageItem {
    CanvasImageItem(
        asset: .transientStaticImage(
            cgImage: try makeAlignmentOverlayTestCGImage()
        ),
        center: CGPoint(x: 20, y: 20),
        size: CGSize(width: 96, height: 64)
    )
}

private func makeAlignmentOverlayTestCGImage() throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 2 * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw AlignmentOverlayTestImageError.failedToCreateBitmapContext
    }
    context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage() else {
        throw AlignmentOverlayTestImageError.failedToCreateImage
    }
    return image
}

private func makeAlignmentOverlayTestContextResolverMetrics() -> CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: 28,
        selectionOutlineHitTargetWidth: 24,
        cropHandleHitTargetSize: 28,
        cropOutlineHitTargetWidth: 24,
        rotateHandleHitTargetSize: 28
    )
}

private enum AlignmentOverlayTestImageError: Error {
    case failedToCreateBitmapContext
    case failedToCreateImage
}
