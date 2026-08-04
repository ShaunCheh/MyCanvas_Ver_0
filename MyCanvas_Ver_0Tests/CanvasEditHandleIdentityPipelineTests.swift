import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditHandleIdentityPipelineTests: XCTestCase {
    func testSelectionAndCropSameRoleKeepDistinctIdentitiesThroughHitPipeline() throws {
        let item = try makeHandleIdentityTestImageItem()
        let session = makeHandleIdentityTestSession(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id)
        )
        let metrics = makeHandleIdentityTestMetrics()

        let selectionSnapshot = session.makeCanvasSnapshot()
        let selectionOverlay = try XCTUnwrap(selectionSnapshot.editOverlay)
        let selectionHandle = try XCTUnwrap(
            selectionOverlay.handles.first(where: { $0.role == .topLeading })
        )
        let expectedSelectionIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .selectionResize(.topLeading)
        )

        XCTAssertEqual(selectionHandle.identity, expectedSelectionIdentity)
        XCTAssertEqual(selectionHandle.visualState, .normal)
        let selectionHitTarget = try XCTUnwrap(
            CanvasEditOverlayHitTester().resolve(
                at: selectionHandle.screenCenter,
                renderSnapshot: selectionSnapshot,
                metrics: metrics
            )
        )
        XCTAssertEqual(
            selectionHitTarget.targetHandleIdentity,
            selectionHandle.identity
        )
        let selectionPressContext = session.resolvePointerTarget(
            at: selectionHandle.screenCenter,
            interactionMetrics: metrics
        )
        guard case let .selectionHandle(role) = selectionPressContext.targetKind else {
            XCTFail("Expected a single-selection resize handle.")
            return
        }
        XCTAssertEqual(role, .topLeading)
        XCTAssertEqual(
            selectionPressContext.targetHandleIdentity,
            selectionHandle.identity
        )

        guard case let .selection(selectionPayload) = selectionOverlay.payload else {
            XCTFail("Expected a selection overlay.")
            return
        }
        let rotateHandle = try XCTUnwrap(
            selectionPayload.rotateAffordance?.handle
        )
        XCTAssertEqual(
            rotateHandle.identity,
            CanvasEditHandleIdentity(
                owner: .item(item.id),
                kind: .rotate
            )
        )
        XCTAssertEqual(rotateHandle.visualState, .normal)

        session.inlineEditState = CanvasInlineEditState(item: item)
        let cropSnapshot = session.makeCanvasSnapshot()
        let cropOverlay = try XCTUnwrap(cropSnapshot.editOverlay)
        let cropHandle = try XCTUnwrap(
            cropOverlay.handles.first(where: { $0.role == .topLeading })
        )

        XCTAssertEqual(
            cropHandle.identity,
            CanvasEditHandleIdentity(
                owner: .item(item.id),
                kind: .cropResize(.topLeading)
            )
        )
        XCTAssertEqual(cropHandle.visualState, .normal)
        XCTAssertNotEqual(selectionHandle.identity, cropHandle.identity)

        let cropHitTarget = try XCTUnwrap(
            CanvasEditOverlayHitTester().resolve(
                at: cropHandle.screenCenter,
                renderSnapshot: cropSnapshot,
                metrics: metrics
            )
        )
        XCTAssertEqual(cropHitTarget.targetHandleIdentity, cropHandle.identity)
        let cropPressContext = session.resolvePointerTarget(
            at: cropHandle.screenCenter,
            interactionMetrics: metrics
        )
        guard case let .cropHandle(role) = cropPressContext.targetKind else {
            XCTFail("Expected a crop resize handle.")
            return
        }
        XCTAssertEqual(role, .topLeading)
        XCTAssertEqual(
            cropPressContext.targetHandleIdentity,
            cropHandle.identity
        )
    }

    func testMultiSelectionResizeAndRotateUseCanonicalSelectionOwner() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -80, y: -20),
            size: CGSize(width: 90, height: 48)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 90, y: 40),
            size: CGSize(width: 120, height: 56)
        )
        let session = makeHandleIdentityTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let expectedOwner = CanvasEditHandleOwner.selection(
            CanvasEditHandleSelectionIdentity(
                primaryItemID: secondItem.id,
                memberItemIDs: [secondItem.id, firstItem.id]
            )
        )

        let snapshot = session.makeCanvasSnapshot()
        let editOverlay = try XCTUnwrap(snapshot.editOverlay)
        for handle in editOverlay.handles {
            let role = try XCTUnwrap(handle.role.selectionHandleRole)
            XCTAssertEqual(
                handle.identity,
                CanvasEditHandleIdentity(
                    owner: expectedOwner,
                    kind: .selectionResize(role)
                )
            )
            XCTAssertEqual(handle.visualState, .normal)
        }

        guard case let .selection(payload) = editOverlay.payload else {
            XCTFail("Expected a multi-selection overlay.")
            return
        }
        let rotateHandle = try XCTUnwrap(payload.rotateAffordance?.handle)
        XCTAssertEqual(
            rotateHandle.identity,
            CanvasEditHandleIdentity(
                owner: expectedOwner,
                kind: .rotate
            )
        )
        XCTAssertEqual(rotateHandle.visualState, .normal)

        let resizeHandle = try XCTUnwrap(
            editOverlay.handles.first(where: { $0.role == .topLeading })
        )
        let resizePressContext = session.resolvePointerTarget(
            at: resizeHandle.screenCenter,
            interactionMetrics: makeHandleIdentityTestMetrics()
        )
        XCTAssertEqual(
            resizePressContext.targetHandleIdentity,
            resizeHandle.identity
        )

        let rotatePressContext = session.resolvePointerTarget(
            at: rotateHandle.screenCenter,
            interactionMetrics: makeHandleIdentityTestMetrics()
        )
        XCTAssertEqual(
            rotatePressContext.targetHandleIdentity,
            rotateHandle.identity
        )
    }

    func testMarkdownEdgesAndArrowEndpointsReceiveSemanticIdentities() throws {
        let firstMarkdown = CanvasMarkdownItem(
            markdownSource: "## First",
            center: CGPoint(x: -70, y: -20),
            size: CGSize(width: 140, height: 84)
        )
        let secondMarkdown = CanvasMarkdownItem(
            markdownSource: "## Second",
            center: CGPoint(x: 90, y: 40),
            size: CGSize(width: 180, height: 96)
        )
        let markdownSession = makeHandleIdentityTestSession(
            items: [.markdown(firstMarkdown), .markdown(secondMarkdown)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstMarkdown.id, secondMarkdown.id],
                primarySelectedItemID: secondMarkdown.id
            )
        )
        let markdownOwner = CanvasEditHandleOwner.selection(
            CanvasEditHandleSelectionIdentity(
                primaryItemID: secondMarkdown.id,
                memberItemIDs: [firstMarkdown.id, secondMarkdown.id]
            )
        )

        let markdownSnapshot = markdownSession.makeCanvasSnapshot()
        let markdownOverlay = try XCTUnwrap(markdownSnapshot.editOverlay)
        XCTAssertEqual(
            markdownOverlay.handles.map(\.role),
            [.top, .trailing, .bottom, .leading]
        )
        for handle in markdownOverlay.handles {
            let role = try XCTUnwrap(handle.role.selectionHandleRole)
            XCTAssertEqual(
                handle.identity,
                CanvasEditHandleIdentity(
                    owner: markdownOwner,
                    kind: .selectionResize(role)
                )
            )
            XCTAssertEqual(handle.visualState, .normal)
        }

        let arrow = CanvasArrowItem(
            center: CGPoint(x: 20, y: 10),
            size: CGSize(width: 180, height: 72),
            rotationRadians: .pi / 8
        )
        let arrowSession = makeHandleIdentityTestSession(
            items: [.arrow(arrow)],
            interactionState: CanvasInteractionState(selectedItemID: arrow.id)
        )
        let arrowSnapshot = arrowSession.makeCanvasSnapshot()
        let arrowOverlay = try XCTUnwrap(arrowSnapshot.editOverlay)
        XCTAssertEqual(
            arrowOverlay.handles.map(\.role),
            [.arrowStart, .arrowEnd]
        )
        for handle in arrowOverlay.handles {
            let role = try XCTUnwrap(handle.role.arrowEndpointRole)
            XCTAssertEqual(
                handle.identity,
                CanvasEditHandleIdentity(
                    owner: .item(arrow.id),
                    kind: .arrowEndpoint(role)
                )
            )
            XCTAssertEqual(handle.visualState, .normal)

            let pressContext = arrowSession.resolvePointerTarget(
                at: handle.screenCenter,
                interactionMetrics: makeHandleIdentityTestMetrics()
            )
            XCTAssertEqual(
                pressContext.targetHandleIdentity,
                handle.identity
            )
        }
    }

    func testCanvasGroupFrameIdentityStaysDistinctFromMultiSelection() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -40, y: 0),
            size: CGSize(width: 80, height: 40)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 60, y: 30),
            size: CGSize(width: 100, height: 48)
        )
        let selectionSession = makeHandleIdentityTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let selectionSnapshot = selectionSession.makeCanvasSnapshot()
        let selectionOverlay = try XCTUnwrap(selectionSnapshot.editOverlay)
        let selectionHandle = try XCTUnwrap(
            selectionOverlay.handles.first(where: { $0.role == .topLeading })
        )

        let groupID = CanvasItemGroupID()
        let groupSession = makeHandleIdentityTestSession(
            groups: [
                CanvasItemGroup(
                    id: groupID,
                    title: "Group",
                    itemIDs: [],
                    frame: CGRect(x: -120, y: -90, width: 240, height: 180)
                )
            ],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            )
        )
        let groupSnapshot = groupSession.makeCanvasSnapshot()
        let groupOverlay = try XCTUnwrap(groupSnapshot.groupEditOverlay)
        let groupHandle = try XCTUnwrap(
            groupOverlay.handles.first(where: { $0.role == .topLeading })
        )

        XCTAssertEqual(
            groupHandle.identity,
            CanvasEditHandleIdentity(
                owner: .group(groupID),
                kind: .groupFrameResize(.topLeading)
            )
        )
        XCTAssertEqual(groupHandle.visualState, .normal)
        XCTAssertNotEqual(selectionHandle.identity, groupHandle.identity)

        let pressContext = groupSession.resolvePointerTarget(
            at: groupHandle.screenCenter,
            interactionMetrics: makeHandleIdentityTestMetrics()
        )
        guard case let .groupFrameResizeHandle(role) = pressContext.targetKind else {
            XCTFail("Expected a canvas group frame resize handle.")
            return
        }
        XCTAssertEqual(role, .topLeading)
        XCTAssertEqual(pressContext.targetGroupID, groupID)
        XCTAssertEqual(
            pressContext.targetHandleIdentity,
            groupHandle.identity
        )
    }

    func testTranslationBodyAndBlankTargetsNeverCarryHandleIdentity() throws {
        let textItem = CanvasTextItem(
            text: "text",
            center: .zero,
            size: CGSize(width: 160, height: 80)
        )
        let textSession = makeHandleIdentityTestSession(
            items: [.text(textItem)],
            interactionState: CanvasInteractionState(
                selectedItemID: textItem.id
            )
        )
        let textSnapshot = textSession.makeCanvasSnapshot()
        let textOverlay = try XCTUnwrap(textSnapshot.editOverlay)
        let metrics = makeHandleIdentityTestMetrics()

        let translationContext = textSession.resolvePointerTarget(
            at: textOverlay.activeScreenQuad.leadingMidpoint,
            interactionMetrics: metrics
        )
        guard case .selectionTranslationArea = translationContext.targetKind else {
            XCTFail("Expected the selection translation area.")
            return
        }
        XCTAssertNil(translationContext.targetHandleIdentity)

        let bodyContext = textSession.resolvePointerTarget(
            at: textSession.camera.worldToViewport(textItem.center),
            interactionMetrics: metrics
        )
        guard case .selectedItemBody = bodyContext.targetKind else {
            XCTFail("Expected the selected item body.")
            return
        }
        XCTAssertNil(bodyContext.targetHandleIdentity)

        let blankContext = textSession.resolvePointerTarget(
            at: CGPoint(x: -500, y: -500),
            interactionMetrics: metrics
        )
        guard case .blank = blankContext.targetKind else {
            XCTFail("Expected blank canvas.")
            return
        }
        XCTAssertNil(blankContext.targetHandleIdentity)

        let unselectedItem = CanvasTextItem(
            text: "unselected",
            center: CGPoint(x: 120, y: -80),
            size: CGSize(width: 140, height: 72)
        )
        let unselectedSession = makeHandleIdentityTestSession(
            items: [.text(unselectedItem)]
        )
        _ = unselectedSession.makeCanvasSnapshot()
        let unselectedBodyContext = unselectedSession.resolvePointerTarget(
            at: unselectedSession.camera.worldToViewport(unselectedItem.center),
            interactionMetrics: metrics
        )
        guard case .unselectedItemBody = unselectedBodyContext.targetKind else {
            XCTFail("Expected the unselected item body.")
            return
        }
        XCTAssertNil(unselectedBodyContext.targetHandleIdentity)

        let imageItem = try makeHandleIdentityTestImageItem()
        let cropSession = makeHandleIdentityTestSession(
            items: [.image(imageItem)]
        )
        cropSession.inlineEditState = CanvasInlineEditState(item: imageItem)
        let cropSnapshot = cropSession.makeCanvasSnapshot()
        let cropOverlay = try XCTUnwrap(cropSnapshot.editOverlay)
        let cropTranslationContext = cropSession.resolvePointerTarget(
            at: cropOverlay.activeScreenQuad.center,
            interactionMetrics: metrics
        )
        guard case .cropTranslationArea = cropTranslationContext.targetKind else {
            XCTFail("Expected the crop translation area.")
            return
        }
        XCTAssertNil(cropTranslationContext.targetHandleIdentity)

        let groupID = CanvasItemGroupID()
        let groupFrame = CGRect(x: -100, y: -80, width: 200, height: 160)
        let groupSession = makeHandleIdentityTestSession(
            groups: [
                CanvasItemGroup(
                    id: groupID,
                    title: "Group",
                    itemIDs: [],
                    frame: groupFrame
                )
            ],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            )
        )
        _ = groupSession.makeCanvasSnapshot()
        let groupBodyContext = groupSession.resolvePointerTarget(
            at: groupSession.camera.worldToViewport(
                CGPoint(x: groupFrame.midX, y: groupFrame.midY)
            ),
            interactionMetrics: metrics
        )
        guard case .groupFrameBody = groupBodyContext.targetKind else {
            XCTFail("Expected the canvas group frame body.")
            return
        }
        XCTAssertNil(groupBodyContext.targetHandleIdentity)
    }

    func testContextResolverPreservesEverySingleSelectionHandleIdentity() throws {
        let item = try makeHandleIdentityTestImageItem()
        let session = makeHandleIdentityTestSession(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id)
        )
        let metrics = makeHandleIdentityTestMetrics()
        let snapshot = session.makeCanvasSnapshot()
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        for handle in overlay.handles {
            let expectedRole = try XCTUnwrap(
                handle.role.selectionHandleRole
            )
            let pressContext = try assertEditOverlayHandleIdentityHit(
                session: session,
                snapshot: snapshot,
                handle: handle,
                metrics: metrics
            )
            guard case let .selectionHandle(role) = pressContext.targetKind else {
                XCTFail("Expected a single-selection resize handle.")
                return
            }
            XCTAssertEqual(role, expectedRole)
        }

        guard case let .selection(payload) = overlay.payload else {
            XCTFail("Expected a single-selection overlay.")
            return
        }
        let rotateHandle = try XCTUnwrap(payload.rotateAffordance?.handle)
        let rotatePressContext = try assertEditOverlayHandleIdentityHit(
            session: session,
            snapshot: snapshot,
            handle: rotateHandle,
            metrics: metrics
        )
        guard case .rotateHandle = rotatePressContext.targetKind else {
            XCTFail("Expected a single-selection rotate handle.")
            return
        }
    }

    func testContextResolverPreservesEveryCropHandleIdentity() throws {
        let item = try makeHandleIdentityTestImageItem()
        let session = makeHandleIdentityTestSession(
            items: [.image(item)]
        )
        session.inlineEditState = CanvasInlineEditState(item: item)
        let metrics = makeHandleIdentityTestMetrics()
        let snapshot = session.makeCanvasSnapshot()
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        for handle in overlay.handles {
            let expectedRole = try XCTUnwrap(handle.role.cropHandleRole)
            let pressContext = try assertEditOverlayHandleIdentityHit(
                session: session,
                snapshot: snapshot,
                handle: handle,
                metrics: metrics
            )
            guard case let .cropHandle(role) = pressContext.targetKind else {
                XCTFail("Expected a crop resize handle.")
                return
            }
            XCTAssertEqual(role, expectedRole)
        }
    }

    func testContextResolverPreservesEveryGroupSelectionHandleIdentity() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -80, y: -20),
            size: CGSize(width: 90, height: 48)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 90, y: 40),
            size: CGSize(width: 120, height: 56)
        )
        let session = makeHandleIdentityTestSession(
            items: [.text(firstItem), .text(secondItem)],
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            )
        )
        let metrics = makeHandleIdentityTestMetrics()
        let snapshot = session.makeCanvasSnapshot()
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        for handle in overlay.handles {
            let expectedRole = try XCTUnwrap(
                handle.role.selectionHandleRole
            )
            let pressContext = try assertEditOverlayHandleIdentityHit(
                session: session,
                snapshot: snapshot,
                handle: handle,
                metrics: metrics
            )
            guard case let .groupSelectionHandle(role) =
                pressContext.targetKind
            else {
                XCTFail("Expected a group-selection resize handle.")
                return
            }
            XCTAssertEqual(role, expectedRole)
        }

        guard case let .selection(payload) = overlay.payload else {
            XCTFail("Expected a group-selection overlay.")
            return
        }
        let rotateHandle = try XCTUnwrap(payload.rotateAffordance?.handle)
        let rotatePressContext = try assertEditOverlayHandleIdentityHit(
            session: session,
            snapshot: snapshot,
            handle: rotateHandle,
            metrics: metrics
        )
        guard case .groupRotateHandle = rotatePressContext.targetKind else {
            XCTFail("Expected a group-selection rotate handle.")
            return
        }
    }

    func testContextResolverPreservesEveryArrowEndpointIdentity() throws {
        let arrow = CanvasArrowItem(
            center: CGPoint(x: 20, y: 10),
            size: CGSize(width: 180, height: 72),
            rotationRadians: .pi / 8
        )
        let session = makeHandleIdentityTestSession(
            items: [.arrow(arrow)],
            interactionState: CanvasInteractionState(selectedItemID: arrow.id)
        )
        let metrics = makeHandleIdentityTestMetrics()
        let snapshot = session.makeCanvasSnapshot()
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        for handle in overlay.handles {
            let expectedRole = try XCTUnwrap(handle.role.arrowEndpointRole)
            let pressContext = try assertEditOverlayHandleIdentityHit(
                session: session,
                snapshot: snapshot,
                handle: handle,
                metrics: metrics
            )
            guard case let .arrowEndpointHandle(role) =
                pressContext.targetKind
            else {
                XCTFail("Expected an arrow endpoint handle.")
                return
            }
            XCTAssertEqual(role, expectedRole)
        }
    }

    func testContextResolverPreservesEveryGroupFrameHandleIdentity() throws {
        let groupID = CanvasItemGroupID()
        let session = makeHandleIdentityTestSession(
            groups: [
                CanvasItemGroup(
                    id: groupID,
                    title: "Group",
                    itemIDs: [],
                    frame: CGRect(x: -120, y: -90, width: 240, height: 180)
                )
            ],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            )
        )
        let metrics = makeHandleIdentityTestMetrics()
        let snapshot = session.makeCanvasSnapshot()
        let overlay = try XCTUnwrap(snapshot.groupEditOverlay)

        for handle in overlay.handles {
            let expectedRole = try XCTUnwrap(
                handle.role.selectionHandleRole
            )
            let pressContext = session.resolvePointerTarget(
                at: handle.screenCenter,
                interactionMetrics: metrics
            )
            guard case let .groupFrameResizeHandle(role) =
                pressContext.targetKind
            else {
                XCTFail("Expected a canvas group frame resize handle.")
                return
            }
            XCTAssertEqual(role, expectedRole)
            XCTAssertEqual(pressContext.targetGroupID, groupID)
            XCTAssertNil(pressContext.targetItemID)
            XCTAssertEqual(
                pressContext.targetHandleIdentity,
                handle.identity
            )
        }
    }

    func testSessionProjectsOnlyExactSelectionOrRotateIdentityAsActive() throws {
        let item = try makeHandleIdentityTestImageItem()
        let session = makeHandleIdentityTestSession(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id)
        )
        let resizeIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .selectionResize(.topLeading)
        )
        _ = session.editHandleInteractionState.apply(.press(resizeIdentity))

        let resizeSnapshot = session.makeCanvasSnapshot()
        let resizeOverlay = try XCTUnwrap(resizeSnapshot.editOverlay)
        XCTAssertEqual(
            resizeOverlay.handles.filter { $0.visualState == .active }.map(\.identity),
            [resizeIdentity]
        )
        guard case let .selection(resizePayload) = resizeOverlay.payload else {
            XCTFail("Expected a selection overlay.")
            return
        }
        XCTAssertEqual(
            resizePayload.rotateAffordance?.handle.visualState,
            .normal
        )

        let rotateIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .rotate
        )
        _ = session.editHandleInteractionState.apply(.press(rotateIdentity))

        let rotateSnapshot = session.makeCanvasSnapshot()
        let rotateOverlay = try XCTUnwrap(rotateSnapshot.editOverlay)
        guard case let .selection(rotatePayload) = rotateOverlay.payload else {
            XCTFail("Expected a selection overlay.")
            return
        }
        XCTAssertTrue(
            rotateOverlay.handles.allSatisfy { $0.visualState == .normal }
        )
        XCTAssertEqual(
            rotatePayload.rotateAffordance?.handle.identity,
            rotateIdentity
        )
        XCTAssertEqual(
            rotatePayload.rotateAffordance?.handle.visualState,
            .active
        )
    }

    func testInlineCropActivatesOnlyMatchingCropIdentity() throws {
        let item = try makeHandleIdentityTestImageItem()
        let session = makeHandleIdentityTestSession(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id)
        )
        let selectionIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .selectionResize(.topLeading)
        )
        _ = session.editHandleInteractionState.apply(.press(selectionIdentity))
        session.inlineEditState = CanvasInlineEditState(item: item)

        let unmatchedSnapshot = session.makeCanvasSnapshot()
        let unmatchedOverlay = try XCTUnwrap(unmatchedSnapshot.editOverlay)
        XCTAssertTrue(
            unmatchedOverlay.handles.allSatisfy { $0.visualState == .normal }
        )

        let cropIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .cropResize(.topLeading)
        )
        _ = session.editHandleInteractionState.apply(.press(cropIdentity))

        let cropSnapshot = session.makeCanvasSnapshot()
        let cropOverlay = try XCTUnwrap(cropSnapshot.editOverlay)
        XCTAssertEqual(
            cropOverlay.handles.filter { $0.visualState == .active }.map(\.identity),
            [cropIdentity]
        )
    }

    func testReadingModeSuppressesActiveGroupHandleWithoutMutatingRawState() throws {
        let groupID = CanvasItemGroupID()
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .group(groupID),
            kind: .groupFrameResize(.topLeading)
        )
        let session = makeHandleIdentityTestSession(
            groups: [
                CanvasItemGroup(
                    id: groupID,
                    title: "Group",
                    itemIDs: [],
                    frame: CGRect(x: -120, y: -90, width: 240, height: 180)
                )
            ],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            )
        )
        _ = session.editHandleInteractionState.apply(.press(activeIdentity))

        let editingSnapshot = session.makeCanvasSnapshot()
        let editingOverlay = try XCTUnwrap(editingSnapshot.groupEditOverlay)
        XCTAssertEqual(
            editingOverlay.handles.filter { $0.visualState == .active }.map(\.identity),
            [activeIdentity]
        )

        session.workspaceMode = .reading
        let readingSnapshot = session.makeCanvasSnapshot()
        let readingOverlay = try XCTUnwrap(readingSnapshot.groupEditOverlay)
        XCTAssertTrue(
            readingOverlay.handles.allSatisfy { $0.visualState == .normal }
        )
        XCTAssertEqual(
            session.editHandleInteractionState.phase,
            .pressed(activeIdentity)
        )
    }

    func testInlineTextSuppressesActiveFeedbackWithoutMutatingRawState() {
        let item = CanvasTextItem(
            text: "editable",
            center: .zero,
            size: CGSize(width: 160, height: 80)
        )
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .rotate
        )
        let session = makeHandleIdentityTestSession(
            items: [.text(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id)
        )
        _ = session.editHandleInteractionState.apply(.press(activeIdentity))
        session.inlineEditState = CanvasInlineEditState(item: item)

        XCTAssertEqual(
            session.presentationEditHandleInteractionState.phase,
            .inactive
        )
        let snapshot = session.makeCanvasSnapshot()
        XCTAssertNil(snapshot.editOverlay)
        XCTAssertEqual(
            session.editHandleInteractionState.phase,
            .pressed(activeIdentity)
        )
    }
}

private enum CanvasEditHandleIdentityPipelineTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

@MainActor
private func makeHandleIdentityTestSession(
    items: [CanvasBoardItem] = [],
    interactionState: CanvasInteractionState? = nil,
    groups: [CanvasItemGroup] = [],
    groupInteractionState: CanvasGroupInteractionState? = nil
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditHandleIdentityPipelineTests.save",
        logPrefix: "[CanvasEditHandleIdentityPipelineTests]"
    )
    session.scene.setItems(items)
    session.groups = groups
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 800, height: 600)
    )
    session.interactionState = interactionState ?? CanvasInteractionState()
    session.groupInteractionState =
        groupInteractionState ?? CanvasGroupInteractionState()
    CanvasEditHandleIdentityPipelineTestRetainer.sessions.append(session)
    return session
}

@MainActor
private func assertEditOverlayHandleIdentityHit(
    session: CanvasEditorSession,
    snapshot: CanvasRenderSnapshot,
    handle: CanvasEditHandleGeometry,
    metrics: CanvasContextResolverMetrics,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> CanvasPointerPressContext {
    let hitTarget = try XCTUnwrap(
        CanvasEditOverlayHitTester().resolve(
            at: handle.screenCenter,
            renderSnapshot: snapshot,
            metrics: metrics
        ),
        file: file,
        line: line
    )
    XCTAssertEqual(
        hitTarget.targetHandleIdentity,
        handle.identity,
        file: file,
        line: line
    )

    let pressContext = session.resolvePointerTarget(
        at: handle.screenCenter,
        interactionMetrics: metrics
    )
    XCTAssertEqual(
        pressContext.targetHandleIdentity,
        handle.identity,
        file: file,
        line: line
    )
    return pressContext
}

private func makeHandleIdentityTestMetrics() -> CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: 28,
        selectionOutlineHitTargetWidth: 24,
        cropHandleHitTargetSize: 28,
        cropOutlineHitTargetWidth: 24,
        rotateHandleHitTargetSize: 28
    )
}

private func makeHandleIdentityTestImageItem() throws -> CanvasImageItem {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw CanvasEditHandleIdentityPipelineTestError.failedToCreateImage
    }
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage() else {
        throw CanvasEditHandleIdentityPipelineTestError.failedToCreateImage
    }
    return CanvasImageItem(
        asset: .transientStaticImage(cgImage: image),
        center: .zero,
        size: CGSize(width: 160, height: 100)
    )
}

private enum CanvasEditHandleIdentityPipelineTestError: Error {
    case failedToCreateImage
}
