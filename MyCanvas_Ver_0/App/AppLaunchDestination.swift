import Foundation

enum CanvasLaunchContext {
    case existing(boardID: UUID)
    case newBoard
}

enum AppLaunchDestination {
    case boardList
    case canvas(CanvasLaunchContext)
}
