import Foundation

enum CanvasLaunchContext: Hashable, Sendable {
    case existing(boardID: UUID)
    case newBoard

    var existingBoardID: UUID? {
        switch self {
        case let .existing(boardID):
            return boardID
        case .newBoard:
            return nil
        }
    }

    var requiresBoardPersistenceOnReturn: Bool {
        switch self {
        case .existing:
            return false
        case .newBoard:
            return true
        }
    }
}

enum AppLaunchDestination: Hashable, Sendable {
    case boardList
    case canvas(CanvasLaunchContext)
}
