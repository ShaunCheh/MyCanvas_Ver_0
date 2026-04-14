import Foundation

final class CanvasCommandExecutor {
    private let session: CanvasEditorSession
    private let interactionPolicy = CanvasInteractionPolicy()

    init(session: CanvasEditorSession) {
        self.session = session
    }

    func canExecute(_ command: CanvasCommand) -> Bool {
        guard case .allow = interactionPolicy.commandDecision(
            for: command.id,
            workspaceMode: session.workspaceMode
        ) else {
            return false
        }

        switch command {
        case let .importMedia(request):
            return request.isEmpty == false
        case .addTextItem:
            return session.canAddTextItem
        case let .beginTextEdit(itemID):
            return session.canBeginTextEdit(withID: itemID)
        case .commitTextEdit:
            return session.canCommitTextEdit
        case .crop:
            return session.isInlineCropModeActive || session.canBeginCropMode
        case .undo:
            return session.canUndoCommand
        case .redo:
            return session.canRedoCommand
        case let .selectItem(itemID, _):
            return session.canSelectItem(withID: itemID)
        case let .toggleSelectionMembership(itemID, _):
            return session.canToggleSelectionMembership(withID: itemID)
        case .clearSelection:
            return session.canClearSelection
        case let .duplicateItem(itemID, _, _):
            return session.canDuplicateItem(withID: itemID)
        case .duplicateSelection:
            return session.canDuplicateSelection
        case let .deleteItem(itemID, _):
            return session.canDeleteItem(withID: itemID)
        case .deleteSelection:
            return session.canDeleteSelection
        case let .bringItemForward(itemID, _):
            return session.canBringItemForward(withID: itemID)
        case .bringSelectionForward:
            return session.canBringSelectionForward
        case let .sendItemBackward(itemID, _):
            return session.canSendItemBackward(withID: itemID)
        case .sendSelectionBackward:
            return session.canSendSelectionBackward
        case let .bringItemToFront(itemID, _):
            return session.canBringItemToFront(withID: itemID)
        case .bringSelectionToFront:
            return session.canBringSelectionToFront
        case let .sendItemToBack(itemID, _):
            return session.canSendItemToBack(withID: itemID)
        case .sendSelectionToBack:
            return session.canSendSelectionToBack
        }
    }

    func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
        guard canExecute(command) else {
            return nil
        }

        switch command {
        case let .importMedia(request):
            let importedItems = session.appendImportedMedia(
                request.items,
                placement: request.placement,
                layout: request.layout,
                presentationTemplate: request.presentationTemplate
            )
            let importedItemCount = importedItems.count
            let itemLabel = importedItemCount == 1 ? "item" : "items"
            let sourceDescription = request.sourceDescription.isEmpty
                ? ""
                : " from \(request.sourceDescription)"
            return CanvasCommandExecutionResult(
                refreshReason: "import \(importedItemCount) \(itemLabel)\(sourceDescription)"
            )
        case .addTextItem:
            guard let addedTextItem = session.addTextItem() else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "add text item \(addedTextItem.id.uuidString)"
            )
        case let .beginTextEdit(itemID):
            guard session.beginTextEdit(withID: itemID) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "begin text edit \(itemID.uuidString)"
            )
        case .commitTextEdit:
            guard let commitResult = session.commitTextEdit() else {
                return nil
            }

            let refreshReason: String
            if commitResult.didDeleteItem {
                refreshReason = "delete empty text item \(commitResult.itemID.uuidString)"
            } else if commitResult.didChangeDocument {
                refreshReason = "commit text edit \(commitResult.itemID.uuidString)"
            } else {
                refreshReason = "finish text edit \(commitResult.itemID.uuidString)"
            }

            return CanvasCommandExecutionResult(
                refreshReason: refreshReason
            )
        case .crop:
            if session.isInlineCropModeActive {
                guard session.endInlineEditMode() else {
                    return nil
                }

                return CanvasCommandExecutionResult(
                    refreshReason: "exit crop mode"
                )
            }

            guard session.beginCropModeIfPossible() else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "enter crop mode"
            )
        case .undo:
            guard let snapshot = session.undoHistorySnapshot() else {
                return nil
            }

            session.applyBoardHistorySnapshot(snapshot)
            session.scheduleAutosave(reason: "undo change")
            return CanvasCommandExecutionResult(
                refreshReason: "apply history snapshot"
            )
        case .redo:
            guard let snapshot = session.redoHistorySnapshot() else {
                return nil
            }

            session.applyBoardHistorySnapshot(snapshot)
            session.scheduleAutosave(reason: "redo change")
            return CanvasCommandExecutionResult(
                refreshReason: "apply history snapshot"
            )
        case let .selectItem(itemID, recordHistory):
            guard session.selectItem(withID: itemID, recordHistory: recordHistory) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "select item \(itemID.uuidString)"
            )
        case let .toggleSelectionMembership(itemID, recordHistory):
            guard session.toggleSelectionMembership(
                of: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "toggle selection membership \(itemID.uuidString)"
            )
        case let .clearSelection(recordHistory):
            guard session.clearSelection(recordHistory: recordHistory) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "clear selection"
            )
        case let .duplicateItem(itemID, selectDuplicatedItem, recordHistory):
            guard let duplicatedItem = session.duplicateItem(
                withID: itemID,
                selectDuplicatedItem: selectDuplicatedItem,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "duplicate item")
            return CanvasCommandExecutionResult(
                refreshReason: "duplicate item \(duplicatedItem.id.uuidString)"
            )
        case let .duplicateSelection(recordHistory):
            guard let duplicatedItems = session.duplicateSelection(
                recordHistory: recordHistory
            ) else {
                return nil
            }

            let duplicatedItemCount = duplicatedItems.count
            let itemLabel = duplicatedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "duplicate selection")
            return CanvasCommandExecutionResult(
                refreshReason: "duplicate selection \(duplicatedItemCount) \(itemLabel)"
            )
        case let .deleteItem(itemID, recordHistory):
            guard session.deleteItem(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "delete item")
            return CanvasCommandExecutionResult(
                refreshReason: "delete item \(itemID.uuidString)"
            )
        case let .deleteSelection(recordHistory):
            let selectedItemCount = session.selectedBoardItems.count
            guard session.deleteSelection(recordHistory: recordHistory) else {
                return nil
            }

            let itemLabel = selectedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "delete selection")
            return CanvasCommandExecutionResult(
                refreshReason: "delete selection \(selectedItemCount) \(itemLabel)"
            )
        case let .bringItemForward(itemID, recordHistory):
            guard session.bringItemForward(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "bring item forward")
            return CanvasCommandExecutionResult(
                refreshReason: "bring item forward \(itemID.uuidString)"
            )
        case let .bringSelectionForward(recordHistory):
            let selectedItemCount = session.selectedBoardItems.count
            guard session.bringSelectionForward(recordHistory: recordHistory) else {
                return nil
            }

            let itemLabel = selectedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "bring selection forward")
            return CanvasCommandExecutionResult(
                refreshReason: "bring selection forward \(selectedItemCount) \(itemLabel)"
            )
        case let .sendItemBackward(itemID, recordHistory):
            guard session.sendItemBackward(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "send item backward")
            return CanvasCommandExecutionResult(
                refreshReason: "send item backward \(itemID.uuidString)"
            )
        case let .sendSelectionBackward(recordHistory):
            let selectedItemCount = session.selectedBoardItems.count
            guard session.sendSelectionBackward(recordHistory: recordHistory) else {
                return nil
            }

            let itemLabel = selectedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "send selection backward")
            return CanvasCommandExecutionResult(
                refreshReason: "send selection backward \(selectedItemCount) \(itemLabel)"
            )
        case let .bringItemToFront(itemID, recordHistory):
            guard session.bringItemToFront(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "bring item to front")
            return CanvasCommandExecutionResult(
                refreshReason: "bring item to front \(itemID.uuidString)"
            )
        case let .bringSelectionToFront(recordHistory):
            let selectedItemCount = session.selectedBoardItems.count
            guard session.bringSelectionToFront(recordHistory: recordHistory) else {
                return nil
            }

            let itemLabel = selectedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "bring selection to front")
            return CanvasCommandExecutionResult(
                refreshReason: "bring selection to front \(selectedItemCount) \(itemLabel)"
            )
        case let .sendItemToBack(itemID, recordHistory):
            guard session.sendItemToBack(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "send item to back")
            return CanvasCommandExecutionResult(
                refreshReason: "send item to back \(itemID.uuidString)"
            )
        case let .sendSelectionToBack(recordHistory):
            let selectedItemCount = session.selectedBoardItems.count
            guard session.sendSelectionToBack(recordHistory: recordHistory) else {
                return nil
            }

            let itemLabel = selectedItemCount == 1 ? "item" : "items"
            session.scheduleAutosave(reason: "send selection to back")
            return CanvasCommandExecutionResult(
                refreshReason: "send selection to back \(selectedItemCount) \(itemLabel)"
            )
        }
    }
}
