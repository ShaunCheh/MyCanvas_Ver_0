import CoreGraphics
import Foundation

struct BoardHistorySnapshot {
    var items: [CanvasImageItem]
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}

extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
        lhs.interactionState.selectedItemID == rhs.interactionState.selectedItemID
    }

    private static func itemsMatch(
        _ lhsItems: [CanvasImageItem],
        _ rhsItems: [CanvasImageItem]
    ) -> Bool {
        guard lhsItems.count == rhsItems.count else {
            return false
        }

        return zip(lhsItems, rhsItems).allSatisfy { lhsItem, rhsItem in
            lhsItem.id == rhsItem.id &&
            lhsItem.center == rhsItem.center &&
            lhsItem.size == rhsItem.size &&
            lhsItem.zIndex == rhsItem.zIndex &&
            lhsItem.cropRectNormalized == rhsItem.cropRectNormalized &&
            lhsItem.rotationRadians == rhsItem.rotationRadians
        }
    }

    private static func boardStatesMatch(
        _ lhsBoardState: CanvasBoardState?,
        _ rhsBoardState: CanvasBoardState?
    ) -> Bool {
        switch (lhsBoardState, rhsBoardState) {
        case (.none, .none):
            return true
        case let (.some(lhsBoardState), .some(rhsBoardState)):
            return lhsBoardState.baseSize == rhsBoardState.baseSize &&
            lhsBoardState.worldRect == rhsBoardState.worldRect
        default:
            return false
        }
    }
}

extension BoardRuntimeState {
    var historySnapshot: BoardHistorySnapshot {
        BoardHistorySnapshot(
            items: items,
            boardState: boardState,
            interactionState: interactionState
        )
    }

    func replacingDocumentState(
        with snapshot: BoardHistorySnapshot,
        updatedAt: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            items: snapshot.items,
            boardState: snapshot.boardState,
            camera: camera,
            interactionState: snapshot.interactionState
        )
    }
}
