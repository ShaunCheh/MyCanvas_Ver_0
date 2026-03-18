import Foundation

final class CanvasCommandExecutor {
    private let session: CanvasEditorSession

    init(session: CanvasEditorSession) {
        self.session = session
    }

    func canExecute(_ command: CanvasCommand) -> Bool {
        switch command {
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
        }
    }

    func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
        guard canExecute(command) else {
            return nil
        }

        switch command {
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
        }
    }
}
