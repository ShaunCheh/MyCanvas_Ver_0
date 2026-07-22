import CoreGraphics
import Foundation

struct BoardHistorySnapshot {
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
    var groupInteractionState: CanvasGroupInteractionState = CanvasGroupInteractionState()
}

extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        lhs.groups == rhs.groups &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
            lhs.interactionState == rhs.interactionState &&
            lhs.groupInteractionState == rhs.groupInteractionState
    }

    private static func itemsMatch(
        _ lhsItems: [CanvasBoardItem],
        _ rhsItems: [CanvasBoardItem]
    ) -> Bool {
        guard lhsItems.count == rhsItems.count else {
            return false
        }

        return zip(lhsItems, rhsItems).allSatisfy { lhsItem, rhsItem in
            switch (lhsItem, rhsItem) {
            case let (.image(lhsImage), .image(rhsImage)):
                return lhsImage.matchesDocumentState(rhsImage)
            case let (.text(lhsText), .text(rhsText)):
                return lhsText.id == rhsText.id &&
                    lhsText.text == rhsText.text &&
                    lhsText.style == rhsText.style &&
                    lhsText.center == rhsText.center &&
                    lhsText.size == rhsText.size &&
                    lhsText.zIndex == rhsText.zIndex &&
                    lhsText.rotationRadians == rhsText.rotationRadians
            case let (.markdown(lhsMarkdown), .markdown(rhsMarkdown)):
                return lhsMarkdown.matchesDocumentState(rhsMarkdown)
            case let (.handDrawing(lhsHandDrawing), .handDrawing(rhsHandDrawing)):
                return lhsHandDrawing.matchesDocumentState(rhsHandDrawing)
            case let (.arrow(lhsArrow), .arrow(rhsArrow)):
                return lhsArrow.matchesDocumentState(rhsArrow)
            default:
                return false
            }
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
            groups: groups,
            boardState: boardState,
            interactionState: interactionState,
            groupInteractionState: CanvasGroupInteractionState()
        )
    }

    func replacingDocumentState(
        with snapshot: BoardHistorySnapshot,
        contentUpdatedAt: Date? = nil,
        viewStateUpdatedAt: Date? = nil
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            contentUpdatedAt: contentUpdatedAt ?? self.contentUpdatedAt,
            viewStateUpdatedAt: viewStateUpdatedAt ?? self.viewStateUpdatedAt,
            items: snapshot.items,
            groups: snapshot.groups,
            boardState: snapshot.boardState,
            camera: camera,
            interactionState: snapshot.interactionState,
            workspaceMode: workspaceMode
        )
    }
}
