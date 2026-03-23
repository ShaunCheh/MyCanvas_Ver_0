import Foundation

enum CanvasCommandID: String {
    case importImages
    case addTextItem
    case beginTextEdit
    case commitTextEdit
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
    case duplicateItem
    case deleteItem
    case bringItemForward
    case sendItemBackward
    case bringItemToFront
    case sendItemToBack
}

enum CanvasCommand {
    case importImages(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasItemID, recordHistory: Bool)

    var id: CanvasCommandID {
        switch self {
        case .importImages:
            return .importImages
        case .addTextItem:
            return .addTextItem
        case .beginTextEdit:
            return .beginTextEdit
        case .commitTextEdit:
            return .commitTextEdit
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
        case .duplicateItem:
            return .duplicateItem
        case .deleteItem:
            return .deleteItem
        case .bringItemForward:
            return .bringItemForward
        case .sendItemBackward:
            return .sendItemBackward
        case .bringItemToFront:
            return .bringItemToFront
        case .sendItemToBack:
            return .sendItemToBack
        }
    }

    // Command execution can invalidate rotation preview / interaction state, so
    // controllers should cancel active rotation before applying these commands.
    var shouldCancelActiveRotation: Bool {
        switch self {
        case .importImages,
             .addTextItem,
             .beginTextEdit,
             .commitTextEdit,
             .crop,
             .undo,
             .redo,
             .selectItem,
             .clearSelection,
             .duplicateItem,
             .deleteItem,
             .bringItemForward,
             .sendItemBackward,
             .bringItemToFront,
             .sendItemToBack:
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
