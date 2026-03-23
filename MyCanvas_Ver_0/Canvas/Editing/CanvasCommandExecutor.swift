import Foundation

final class CanvasCommandExecutor {
    private let session: CanvasEditorSession

    init(session: CanvasEditorSession) {
        self.session = session
    }

    func canExecute(_ command: CanvasCommand) -> Bool {
        switch command {
        case let .importImages(request):
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
        case .clearSelection:
            return session.canClearSelection
        case let .duplicateItem(itemID, _):
            return session.canDuplicateItem(withID: itemID)
        case let .deleteItem(itemID, _):
            return session.canDeleteItem(withID: itemID)
        case let .bringItemForward(itemID, _):
            return session.canBringItemForward(withID: itemID)
        case let .sendItemBackward(itemID, _):
            return session.canSendItemBackward(withID: itemID)
        case let .bringItemToFront(itemID, _):
            return session.canBringItemToFront(withID: itemID)
        case let .sendItemToBack(itemID, _):
            return session.canSendItemToBack(withID: itemID)
        }
    }

    func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
        guard canExecute(command) else {
            return nil
        }

        switch command {
        case let .importImages(request):
            let importedItems = session.appendImportedImages(
                request.images,
                placement: request.placement,
                layout: request.layout
            )
            let imageCount = importedItems.count
            let imageLabel = imageCount == 1 ? "image" : "images"
            let sourceDescription = request.sourceDescription.isEmpty
                ? ""
                : " from \(request.sourceDescription)"
            return CanvasCommandExecutionResult(
                refreshReason: "import \(imageCount) \(imageLabel)\(sourceDescription)"
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
        case let .clearSelection(recordHistory):
            guard session.clearSelection(recordHistory: recordHistory) else {
                return nil
            }

            return CanvasCommandExecutionResult(
                refreshReason: "clear selection"
            )
        case let .duplicateItem(itemID, recordHistory):
            guard let duplicatedItem = session.duplicateItem(
                withID: itemID,
                recordHistory: recordHistory
            ) else {
                return nil
            }

            session.scheduleAutosave(reason: "duplicate item")
            return CanvasCommandExecutionResult(
                refreshReason: "duplicate item \(duplicatedItem.id.uuidString)"
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
        }
    }
}
