import Foundation

// Shared click selection resolution keeps iOS/macOS selection semantics aligned.
struct CanvasPointerModifiers: Equatable, Sendable {
    var isCommandPressed = false
    var isShiftPressed = false
    var isOptionPressed = false
    var isControlPressed = false

    static let none = Self()

    func merging(_ other: CanvasPointerModifiers) -> CanvasPointerModifiers {
        CanvasPointerModifiers(
            isCommandPressed: isCommandPressed || other.isCommandPressed,
            isShiftPressed: isShiftPressed || other.isShiftPressed,
            isOptionPressed: isOptionPressed || other.isOptionPressed,
            isControlPressed: isControlPressed || other.isControlPressed
        )
    }
}

enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case selectGroup(groupID: CanvasItemGroupID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case reenterSelectedItem(itemID: CanvasItemID)
}

struct CanvasClickSelectionDecision: Equatable {
    let target: String
    let affectedItemID: CanvasItemID?
    let action: CanvasClickSelectionAction
}

struct CanvasClickSelectionState: Equatable, Sendable {
    let itemSelection: CanvasInteractionState
    let selectedGroupID: CanvasItemGroupID?

    init(
        itemSelection: CanvasInteractionState = CanvasInteractionState(),
        selectedGroupID: CanvasItemGroupID? = nil
    ) {
        self.itemSelection = itemSelection
        self.selectedGroupID = selectedGroupID
    }

    var hasAnySelection: Bool {
        itemSelection.hasSelection || selectedGroupID != nil
    }
}

struct CanvasClickSelectionResolver: Sendable {
    func resolve(
        pressTargetKind: CanvasPointerTargetKind,
        pressedItemID: CanvasItemID?,
        releasedItemID: CanvasItemID?,
        pressedGroupID: CanvasItemGroupID? = nil,
        releasedGroupID: CanvasItemGroupID? = nil,
        selection: CanvasClickSelectionState,
        isPersistentMultiSelectModeEnabled: Bool,
        pressedModifiers: CanvasPointerModifiers,
        releasedModifiers: CanvasPointerModifiers
    ) -> CanvasClickSelectionDecision {
        switch pressTargetKind {
        case .rotateHandle:
            return CanvasClickSelectionDecision(
                target: "rotate_handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .groupRotateHandle:
            return CanvasClickSelectionDecision(
                target: "group_rotate_handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .cropHandle:
            return CanvasClickSelectionDecision(
                target: "crop_handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .cropTranslationArea:
            return CanvasClickSelectionDecision(
                target: "crop_translation_area",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .selectionHandle:
            return CanvasClickSelectionDecision(
                target: "handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .groupSelectionHandle:
            return CanvasClickSelectionDecision(
                target: "group_handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .arrowEndpointHandle:
            return CanvasClickSelectionDecision(
                target: "arrow_endpoint_handle",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .selectionTranslationArea:
            return CanvasClickSelectionDecision(
                target: "selection_translation_area",
                affectedItemID: pressedItemID,
                action: .none
            )
        case .groupFrameBody:
            guard
                let groupID = pressedGroupID,
                releasedGroupID == groupID
            else {
                return CanvasClickSelectionDecision(
                    target: "mismatched_group_hit_test",
                    affectedItemID: nil,
                    action: .none
                )
            }

            return CanvasClickSelectionDecision(
                target: "group_frame_body",
                affectedItemID: nil,
                action: .selectGroup(groupID: groupID)
            )
        case .groupFrameResizeHandle:
            return CanvasClickSelectionDecision(
                target: "group_frame_resize_handle",
                affectedItemID: nil,
                action: .none
            )
        case .selectedItemBody, .unselectedItemBody:
            guard
                let itemID = pressedItemID,
                releasedItemID == itemID
            else {
                return CanvasClickSelectionDecision(
                    target: "mismatched_hit_test",
                    affectedItemID: releasedItemID ?? pressedItemID,
                    action: .none
                )
            }

            if selectionMode(
                isPersistentMultiSelectModeEnabled: isPersistentMultiSelectModeEnabled,
                pressedModifiers: pressedModifiers,
                releasedModifiers: releasedModifiers
            ) == .toggleMembership {
                return CanvasClickSelectionDecision(
                    target: "item",
                    affectedItemID: itemID,
                    action: .toggleMembership(itemID: itemID)
                )
            }

            if case .selectedItemBody = pressTargetKind,
               selection.itemSelection.singleSelectedItemID == itemID
            {
                return CanvasClickSelectionDecision(
                    target: "item",
                    affectedItemID: itemID,
                    action: .reenterSelectedItem(itemID: itemID)
                )
            }

            return CanvasClickSelectionDecision(
                target: "item",
                affectedItemID: itemID,
                action: .selectSingle(itemID: itemID)
            )
        case .blank:
            guard releasedItemID == nil else {
                return CanvasClickSelectionDecision(
                    target: "mismatched_hit_test",
                    affectedItemID: releasedItemID,
                    action: .none
                )
            }

            return CanvasClickSelectionDecision(
                target: "blank",
                affectedItemID: selection.itemSelection.primarySelectedItemID,
                action: selection.hasAnySelection ? .clearSelection : .none
            )
        }
    }

    private func selectionMode(
        isPersistentMultiSelectModeEnabled: Bool,
        pressedModifiers: CanvasPointerModifiers,
        releasedModifiers: CanvasPointerModifiers
    ) -> CanvasClickSelectionMode {
        let mergedModifiers = pressedModifiers.merging(releasedModifiers)
        if isPersistentMultiSelectModeEnabled || mergedModifiers.isCommandPressed {
            return .toggleMembership
        }
        return .replaceSelection
    }
}

private enum CanvasClickSelectionMode {
    case replaceSelection
    case toggleMembership
}
