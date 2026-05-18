import Foundation

struct HandDrawingHistorySnapshot: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs.intersection(
            Set(document.strokes.map(\.id))
        )
    }

    var activeLayerID: UUID {
        document.activeLayerID
    }
}

struct HandDrawingHistoryController {
    private var undoStack: [HandDrawingHistorySnapshot] = []
    private var redoStack: [HandDrawingHistorySnapshot] = []

    var canUndo: Bool {
        undoStack.isEmpty == false
    }

    var canRedo: Bool {
        redoStack.isEmpty == false
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    mutating func record(snapshot: HandDrawingHistorySnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    mutating func undo(
        current: HandDrawingHistorySnapshot
    ) -> HandDrawingHistorySnapshot? {
        guard let previousSnapshot = undoStack.popLast() else {
            return nil
        }
        redoStack.append(current)
        return previousSnapshot
    }

    mutating func redo(
        current: HandDrawingHistorySnapshot
    ) -> HandDrawingHistorySnapshot? {
        guard let redoSnapshot = redoStack.popLast() else {
            return nil
        }
        undoStack.append(current)
        return redoSnapshot
    }
}
