import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasClickSelectionResolverTests: XCTestCase {
    private let resolver = CanvasClickSelectionResolver()

    func testResolveSelectsSingleItemWhenMultiSelectIsOff() {
        let currentSelectionItemID = CanvasItemID()
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .unselectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasInteractionState(
                selectedItemIDs: [currentSelectionItemID],
                primarySelectedItemID: currentSelectionItemID
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision,
            CanvasClickSelectionDecision(
                target: "item",
                affectedItemID: tappedItemID,
                action: .selectSingle(itemID: tappedItemID)
            )
        )
    }

    func testResolveUsesPersistentMultiSelectModeToToggleMembership() {
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .unselectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasInteractionState(),
            isPersistentMultiSelectModeEnabled: true,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision.action,
            .toggleMembership(itemID: tappedItemID)
        )
    }

    func testResolveUsesCommandClickToToggleMembership() {
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasInteractionState(
                selectedItemIDs: [tappedItemID],
                primarySelectedItemID: tappedItemID
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: CanvasPointerModifiers(isCommandPressed: true),
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision.action,
            .toggleMembership(itemID: tappedItemID)
        )
    }

    func testResolveClearsSelectionOnBlankClickEvenWhenMultiSelectModeIsOn() {
        let selectedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .blank,
            pressedItemID: nil,
            releasedItemID: nil,
            selection: CanvasInteractionState(
                selectedItemIDs: [selectedItemID],
                primarySelectedItemID: selectedItemID
            ),
            isPersistentMultiSelectModeEnabled: true,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision,
            CanvasClickSelectionDecision(
                target: "blank",
                affectedItemID: selectedItemID,
                action: .clearSelection
            )
        )
    }

    func testResolvePrefersTextEditOnlyForSoleSelectedItem() {
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasInteractionState(
                selectedItemIDs: [tappedItemID],
                primarySelectedItemID: tappedItemID
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision.action,
            .attemptTextEdit(itemID: tappedItemID)
        )
    }

    func testResolveCollapsesExistingMultiSelectionToSingleItemInReplaceMode() {
        let tappedItemID = CanvasItemID()
        let otherSelectedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasInteractionState(
                selectedItemIDs: [tappedItemID, otherSelectedItemID],
                primarySelectedItemID: otherSelectedItemID
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision.action,
            .selectSingle(itemID: tappedItemID)
        )
    }
}
