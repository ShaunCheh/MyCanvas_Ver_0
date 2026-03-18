import Foundation

enum CanvasCommandID: String {
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
}

enum CanvasCommand {
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)

    var id: CanvasCommandID {
        switch self {
        case .crop:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            return .selectItem
        case .clearSelection:
            return .clearSelection
        }
    }

    // Command execution can invalidate rotation preview / interaction state, so
    // controllers should cancel active rotation before applying these commands.
    var shouldCancelActiveRotation: Bool {
        switch self {
        case .crop, .undo, .redo, .selectItem, .clearSelection:
            return true
        }
    }

    var shouldResetPointerDragStateWhenCancellingRotation: Bool {
        shouldCancelActiveRotation
    }
}

struct CanvasCommandDescriptor {
    let id: CanvasCommandID
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let isActive: Bool
}

struct CanvasCommandExecutionResult {
    let refreshReason: String?
}
