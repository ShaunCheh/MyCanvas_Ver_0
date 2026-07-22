import Foundation

// History tracks document state only. Camera stays outside so undo/redo can
// restore board edits and selection without unexpectedly jumping the viewport.
final class BoardHistoryController {
    private struct BoardHistoryEntry {
        let beforeSnapshot: BoardHistorySnapshot
        let afterSnapshot: BoardHistorySnapshot
        let reason: String
    }

    private struct BoardHistoryTransaction {
        let initialSnapshot: BoardHistorySnapshot
        let reason: String
    }

    private var undoStack: [BoardHistoryEntry] = []
    private var redoStack: [BoardHistoryEntry] = []
    private var pendingTransaction: BoardHistoryTransaction?

    var canUndo: Bool {
        undoStack.isEmpty == false
    }

    var canRedo: Bool {
        redoStack.isEmpty == false
    }

    var hasPendingTransaction: Bool {
        pendingTransaction != nil
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        pendingTransaction = nil
    }

    func beginTransaction(
        from snapshot: BoardHistorySnapshot,
        reason: String
    ) {
        guard pendingTransaction == nil else {
            return
        }

        pendingTransaction = BoardHistoryTransaction(
            initialSnapshot: snapshot,
            reason: reason
        )
    }

    func cancelPendingTransaction() {
        pendingTransaction = nil
    }

    func pendingTransactionHasChanges(
        to snapshot: BoardHistorySnapshot
    ) -> Bool? {
        guard let pendingTransaction else {
            return nil
        }

        return pendingTransaction.initialSnapshot != snapshot
    }

    @discardableResult
    func commitPendingTransaction(
        to snapshot: BoardHistorySnapshot
    ) -> Bool {
        guard let pendingTransaction else {
            return false
        }

        self.pendingTransaction = nil
        return recordChange(
            from: pendingTransaction.initialSnapshot,
            to: snapshot,
            reason: pendingTransaction.reason
        )
    }

    @discardableResult
    func recordChange(
        from beforeSnapshot: BoardHistorySnapshot,
        to afterSnapshot: BoardHistorySnapshot,
        reason: String
    ) -> Bool {
        guard beforeSnapshot != afterSnapshot else {
            return false
        }

        undoStack.append(
            BoardHistoryEntry(
                beforeSnapshot: beforeSnapshot,
                afterSnapshot: afterSnapshot,
                reason: reason
            )
        )
        redoStack.removeAll()
        return true
    }

    func undo() -> BoardHistorySnapshot? {
        guard let entry = undoStack.popLast() else {
            return nil
        }

        redoStack.append(entry)
        pendingTransaction = nil
        return entry.beforeSnapshot
    }

    func redo() -> BoardHistorySnapshot? {
        guard let entry = redoStack.popLast() else {
            return nil
        }

        undoStack.append(entry)
        pendingTransaction = nil
        return entry.afterSnapshot
    }
}
