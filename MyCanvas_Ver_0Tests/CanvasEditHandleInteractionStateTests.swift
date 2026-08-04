import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditHandleInteractionStateTests: XCTestCase {
    func testSelectionIdentityIgnoresMemberOrderingAndDuplicates() {
        let primaryItemID = CanvasItemID()
        let secondaryItemID = CanvasItemID()

        let first = CanvasEditHandleSelectionIdentity(
            primaryItemID: primaryItemID,
            memberItemIDs: [primaryItemID, secondaryItemID]
        )
        let second = CanvasEditHandleSelectionIdentity(
            primaryItemID: primaryItemID,
            memberItemIDs: [
                secondaryItemID,
                primaryItemID,
                secondaryItemID
            ]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.memberItemIDs,
            Set([primaryItemID, secondaryItemID])
        )
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testSelectionIdentityAlwaysIncludesPrimaryItem() {
        let primaryItemID = CanvasItemID()
        let secondaryItemID = CanvasItemID()

        let identity = CanvasEditHandleSelectionIdentity(
            primaryItemID: primaryItemID,
            memberItemIDs: [secondaryItemID]
        )

        XCTAssertEqual(
            identity.memberItemIDs,
            Set([primaryItemID, secondaryItemID])
        )
    }

    func testHandleIdentityDistinguishesOwnerKindAndRole() {
        let itemID = CanvasItemID()
        let groupID = CanvasItemGroupID()
        let selectionResize = CanvasEditHandleIdentity(
            owner: .item(itemID),
            kind: .selectionResize(.trailing)
        )
        let cropResize = CanvasEditHandleIdentity(
            owner: .item(itemID),
            kind: .cropResize(.trailing)
        )
        let differentRole = CanvasEditHandleIdentity(
            owner: .item(itemID),
            kind: .selectionResize(.leading)
        )
        let groupResize = CanvasEditHandleIdentity(
            owner: .group(groupID),
            kind: .groupFrameResize(.trailing)
        )

        XCTAssertNotEqual(selectionResize, cropResize)
        XCTAssertNotEqual(selectionResize, differentRole)
        XCTAssertNotEqual(selectionResize, groupResize)
    }

    func testHandleIdentityCoversEveryHandleFamilyAndOwnerShape() {
        let primaryItemID = CanvasItemID()
        let secondaryItemID = CanvasItemID()
        let groupID = CanvasItemGroupID()
        let multiSelection = CanvasEditHandleSelectionIdentity(
            primaryItemID: primaryItemID,
            memberItemIDs: [secondaryItemID, primaryItemID]
        )
        let identities: [CanvasEditHandleIdentity] = [
            CanvasEditHandleIdentity(
                owner: .item(primaryItemID),
                kind: .selectionResize(.topLeading)
            ),
            CanvasEditHandleIdentity(
                owner: .item(primaryItemID),
                kind: .cropResize(.topLeading)
            ),
            CanvasEditHandleIdentity(
                owner: .selection(multiSelection),
                kind: .rotate
            ),
            CanvasEditHandleIdentity(
                owner: .item(primaryItemID),
                kind: .arrowEndpoint(.start)
            ),
            CanvasEditHandleIdentity(
                owner: .group(groupID),
                kind: .groupFrameResize(.topLeading)
            )
        ]

        XCTAssertEqual(Set(identities).count, identities.count)

        let arrowEnd = CanvasEditHandleIdentity(
            owner: .item(primaryItemID),
            kind: .arrowEndpoint(.end)
        )
        XCTAssertNotEqual(identities[3], arrowEnd)
    }

    func testPressActivatesOnlyPressedHandle() {
        let pressedIdentity = makeItemResizeIdentity(role: .topLeading)
        let otherIdentity = makeItemResizeIdentity(role: .bottomTrailing)
        var state = CanvasEditHandleInteractionState()

        let transition = state.apply(.press(pressedIdentity))

        XCTAssertTrue(transition.didChangeState)
        XCTAssertTrue(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .pressed(pressedIdentity))
        XCTAssertEqual(state.activeIdentity, pressedIdentity)
        XCTAssertEqual(state.visualState(for: pressedIdentity), .active)
        XCTAssertEqual(state.visualState(for: otherIdentity), .normal)
    }

    func testRepeatedPressOfSameHandleIsIdempotent() {
        let identity = makeItemResizeIdentity()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(identity))

        let transition = state.apply(.press(identity))

        XCTAssertFalse(transition.didChangeState)
        XCTAssertFalse(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .pressed(identity))
    }

    func testBeginDraggingRequiresPressedIdentityWithoutVisualRefresh() {
        let identity = makeItemResizeIdentity()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(identity))

        let transition = state.apply(
            .beginDragging(expectedIdentity: identity)
        )

        XCTAssertTrue(transition.didChangeState)
        XCTAssertFalse(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .dragging(identity))
        XCTAssertEqual(state.visualState(for: identity), .active)

        let repeatedTransition = state.apply(
            .beginDragging(expectedIdentity: identity)
        )
        XCTAssertFalse(repeatedTransition.didChangeState)
        XCTAssertFalse(repeatedTransition.didChangeVisualState)
    }

    func testMismatchedBeginDraggingDoesNotReplacePressedHandle() {
        let pressedIdentity = makeItemResizeIdentity(role: .topLeading)
        let mismatchedIdentity = makeItemResizeIdentity(role: .bottomTrailing)
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(pressedIdentity))

        let transition = state.apply(
            .beginDragging(expectedIdentity: mismatchedIdentity)
        )

        XCTAssertFalse(transition.didChangeState)
        XCTAssertFalse(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .pressed(pressedIdentity))
        XCTAssertEqual(state.visualState(for: mismatchedIdentity), .normal)
    }

    func testPressingDifferentHandleTransfersVisualActivity() {
        let firstIdentity = makeItemResizeIdentity(role: .topLeading)
        let secondIdentity = makeItemResizeIdentity(role: .bottomTrailing)
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(firstIdentity))

        let transition = state.apply(.press(secondIdentity))

        XCTAssertTrue(transition.didChangeState)
        XCTAssertTrue(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .pressed(secondIdentity))
        XCTAssertEqual(state.visualState(for: firstIdentity), .normal)
        XCTAssertEqual(state.visualState(for: secondIdentity), .active)
    }

    func testPressNilClearsStaleHandleState() {
        let identity = makeItemResizeIdentity()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(identity))
        _ = state.apply(.beginDragging(expectedIdentity: identity))

        let transition = state.apply(.press(nil))

        XCTAssertTrue(transition.didChangeState)
        XCTAssertTrue(transition.didChangeVisualState)
        XCTAssertEqual(state.phase, .inactive)
        XCTAssertNil(state.activeIdentity)
        XCTAssertEqual(state.visualState(for: identity), .normal)
    }

    func testEndAndCancelAlwaysReturnToInactive() {
        let identity = makeItemResizeIdentity()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(identity))

        let endTransition = state.apply(.end)

        XCTAssertTrue(endTransition.didChangeState)
        XCTAssertTrue(endTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .inactive)

        let inactiveCancelTransition = state.apply(.cancel)
        XCTAssertFalse(inactiveCancelTransition.didChangeState)
        XCTAssertFalse(inactiveCancelTransition.didChangeVisualState)

        _ = state.apply(.press(identity))
        _ = state.apply(.beginDragging(expectedIdentity: identity))
        let draggingCancelTransition = state.apply(.cancel)

        XCTAssertTrue(draggingCancelTransition.didChangeState)
        XCTAssertTrue(draggingCancelTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .inactive)
    }

    func testControllerAdapterKeepsPressedIdentityThroughDragActivation() {
        let identity = makeItemResizeIdentity()
        var adapter = CanvasEditHandleControllerAdapter()
        var state = CanvasEditHandleInteractionState()

        let pressEvent = adapter.event(for: .pressed(identity))
        let pressTransition = state.apply(pressEvent)

        XCTAssertEqual(pressEvent, .press(identity))
        XCTAssertEqual(adapter.expectedDraggingIdentity, identity)
        XCTAssertTrue(pressTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .pressed(identity))

        let dragEvent = adapter.event(for: .draggingHandle)
        let dragTransition = state.apply(dragEvent)

        XCTAssertEqual(
            dragEvent,
            .beginDragging(expectedIdentity: identity)
        )
        XCTAssertEqual(adapter.expectedDraggingIdentity, identity)
        XCTAssertTrue(dragTransition.didChangeState)
        XCTAssertFalse(dragTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .dragging(identity))
    }

    func testControllerAdapterInactiveClearsIdentityAndVisualState() {
        let identity = makeItemResizeIdentity()
        var adapter = CanvasEditHandleControllerAdapter()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(adapter.event(for: .pressed(identity)))
        _ = state.apply(adapter.event(for: .draggingHandle))

        let endEvent = adapter.event(for: .inactive)
        let endTransition = state.apply(endEvent)

        XCTAssertEqual(endEvent, .end)
        XCTAssertNil(adapter.expectedDraggingIdentity)
        XCTAssertTrue(endTransition.didChangeState)
        XCTAssertTrue(endTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .inactive)

        let repeatedEndTransition = state.apply(
            adapter.event(for: .inactive)
        )
        XCTAssertFalse(repeatedEndTransition.didChangeState)
        XCTAssertFalse(repeatedEndTransition.didChangeVisualState)
    }

    func testControllerAdapterNilPressAndOrphanDragCannotActivateHandle() {
        let staleIdentity = makeItemResizeIdentity()
        var adapter = CanvasEditHandleControllerAdapter()
        var state = CanvasEditHandleInteractionState()
        _ = state.apply(.press(staleIdentity))

        let orphanDragEvent = adapter.event(for: .draggingHandle)
        let orphanDragTransition = state.apply(orphanDragEvent)

        XCTAssertEqual(orphanDragEvent, .cancel)
        XCTAssertNil(adapter.expectedDraggingIdentity)
        XCTAssertTrue(orphanDragTransition.didChangeVisualState)
        XCTAssertEqual(state.phase, .inactive)

        let nilPressEvent = adapter.event(for: .pressed(nil))
        let nilPressTransition = state.apply(nilPressEvent)

        XCTAssertEqual(nilPressEvent, .press(nil))
        XCTAssertNil(adapter.expectedDraggingIdentity)
        XCTAssertFalse(nilPressTransition.didChangeState)
        XCTAssertFalse(nilPressTransition.didChangeVisualState)
    }

    private func makeItemResizeIdentity(
        itemID: CanvasItemID = CanvasItemID(),
        role: CanvasSelectionHandleRole = .topLeading
    ) -> CanvasEditHandleIdentity {
        CanvasEditHandleIdentity(
            owner: .item(itemID),
            kind: .selectionResize(role)
        )
    }
}
