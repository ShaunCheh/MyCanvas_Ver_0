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
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case attemptTextEdit(itemID: CanvasItemID)
}

struct CanvasClickSelectionDecision: Equatable {
    let target: String
    let affectedItemID: CanvasItemID?
    let action: CanvasClickSelectionAction
}

struct CanvasClickSelectionResolver: Sendable {
    func resolve(
        pressTargetKind: CanvasPointerTargetKind,
        pressedItemID: CanvasItemID?,
        releasedItemID: CanvasItemID?,
        selection: CanvasInteractionState,
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
               selection.singleSelectedItemID == itemID
            {
                return CanvasClickSelectionDecision(
                    target: "item",
                    affectedItemID: itemID,
                    action: .attemptTextEdit(itemID: itemID)
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
                affectedItemID: selection.primarySelectedItemID,
                action: selection.hasSelection ? .clearSelection : .none
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
