import Foundation

enum BoardListEntryID: Hashable {
    case newBoard
    case board(UUID)
}

enum BoardListEntry {
    static let newBoardTitle = "New Board"

    case newBoardPlaceholder
    case board(BoardCatalogItem)

    var id: BoardListEntryID {
        switch self {
        case .newBoardPlaceholder:
            return .newBoard
        case let .board(item):
            return .board(item.boardID)
        }
    }

    var title: String {
        switch self {
        case .newBoardPlaceholder:
            return Self.newBoardTitle
        case let .board(item):
            return item.title
        }
    }

    var isPlaceholder: Bool {
        if case .newBoardPlaceholder = self {
            return true
        }

        return false
    }

    var boardID: UUID? {
        switch self {
        case .newBoardPlaceholder:
            return nil
        case let .board(item):
            return item.boardID
        }
    }

    var catalogItem: BoardCatalogItem? {
        switch self {
        case .newBoardPlaceholder:
            return nil
        case let .board(item):
            return item
        }
    }

    var canRequestPreview: Bool {
        catalogItem != nil
    }

    var revisionToken: String? {
        catalogItem?.revisionToken
    }
}
