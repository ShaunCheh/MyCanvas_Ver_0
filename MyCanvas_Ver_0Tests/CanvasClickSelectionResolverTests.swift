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
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [currentSelectionItemID],
                    primarySelectedItemID: currentSelectionItemID
                )
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
            selection: CanvasClickSelectionState(),
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
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [tappedItemID],
                    primarySelectedItemID: tappedItemID
                )
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
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [selectedItemID],
                    primarySelectedItemID: selectedItemID
                )
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

    func testResolveClearsGroupSelectionOnBlankClick() {
        let selectedGroupID = CanvasItemGroupID()

        let decision = resolver.resolve(
            pressTargetKind: .blank,
            pressedItemID: nil,
            releasedItemID: nil,
            selection: CanvasClickSelectionState(
                selectedGroupID: selectedGroupID
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision,
            CanvasClickSelectionDecision(
                target: "blank",
                affectedItemID: nil,
                action: .clearSelection
            )
        )
    }

    func testResolveReentersSoleSelectedItem() {
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [tappedItemID],
                    primarySelectedItemID: tappedItemID
                )
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision.action,
            .reenterSelectedItem(itemID: tappedItemID)
        )
    }

    func testResolveReturnsNoOpForSelectionTranslationAreaClick() {
        let tappedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectionTranslationArea,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [tappedItemID],
                    primarySelectedItemID: tappedItemID
                )
            ),
            isPersistentMultiSelectModeEnabled: false,
            pressedModifiers: .none,
            releasedModifiers: .none
        )

        XCTAssertEqual(
            decision,
            CanvasClickSelectionDecision(
                target: "selection_translation_area",
                affectedItemID: tappedItemID,
                action: .none
            )
        )
    }

    func testResolveCollapsesExistingMultiSelectionToSingleItemInReplaceMode() {
        let tappedItemID = CanvasItemID()
        let otherSelectedItemID = CanvasItemID()

        let decision = resolver.resolve(
            pressTargetKind: .selectedItemBody,
            pressedItemID: tappedItemID,
            releasedItemID: tappedItemID,
            selection: CanvasClickSelectionState(
                itemSelection: CanvasInteractionState(
                    selectedItemIDs: [tappedItemID, otherSelectedItemID],
                    primarySelectedItemID: otherSelectedItemID
                )
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
