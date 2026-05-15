import Foundation

enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case beginTextEdit
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
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

    // Current CanvasCommand set only covers document-mutating editing operations.
    // Navigation stays at the controller/input layer, so reading mode blocks all
    // of these commands until explicit read-safe commands are introduced.
    var isAllowedInReadingMode: Bool {
        switch self {
        case .importMedia,
             .addTextItem,
             .beginTextEdit,
             .commitTextEdit,
             .decreaseTextFontSize,
             .increaseTextFontSize,
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
            return false
        }
    }
}

enum CanvasCommand {
    // importMedia lives in the command lane after transfer/import lowering and
    // intentionally consumes CanvasImportRequest instead of raw capture input.
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    case beginCropMode(itemID: CanvasItemID)
    case undo
    case redo
    case selectItem(itemID: CanvasItemID, recordHistory: Bool)
    case toggleSelectionMembership(itemID: CanvasItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(
        itemID: CanvasItemID,
        selectDuplicatedItem: Bool,
        recordHistory: Bool
    )
    case duplicateSelection(recordHistory: Bool)
    case deleteItem(itemID: CanvasItemID, recordHistory: Bool)
    case deleteSelection(recordHistory: Bool)
    case bringItemForward(itemID: CanvasItemID, recordHistory: Bool)
    case bringSelectionForward(recordHistory: Bool)
    case sendItemBackward(itemID: CanvasItemID, recordHistory: Bool)
    case sendSelectionBackward(recordHistory: Bool)
    case bringItemToFront(itemID: CanvasItemID, recordHistory: Bool)
    case bringSelectionToFront(recordHistory: Bool)
    case sendItemToBack(itemID: CanvasItemID, recordHistory: Bool)
    case sendSelectionToBack(recordHistory: Bool)

    var id: CanvasCommandID {
        switch self {
        case .importMedia:
            return .importMedia
        case .addTextItem:
            return .addTextItem
        case .beginTextEdit:
            return .beginTextEdit
        case .commitTextEdit:
            return .commitTextEdit
        case .decreaseTextFontSize:
            return .decreaseTextFontSize
        case .increaseTextFontSize:
            return .increaseTextFontSize
        case .crop:
            return .crop
        case .beginCropMode:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            return .selectItem
        case .toggleSelectionMembership:
            return .selectItem
        case .clearSelection:
            return .clearSelection
        case .duplicateItem:
            return .duplicateItem
        case .duplicateSelection:
            return .duplicateItem
        case .deleteItem:
            return .deleteItem
        case .deleteSelection:
            return .deleteItem
        case .bringItemForward:
            return .bringItemForward
        case .bringSelectionForward:
            return .bringItemForward
        case .sendItemBackward:
            return .sendItemBackward
        case .sendSelectionBackward:
            return .sendItemBackward
        case .bringItemToFront:
            return .bringItemToFront
        case .bringSelectionToFront:
            return .bringItemToFront
        case .sendItemToBack:
            return .sendItemToBack
        case .sendSelectionToBack:
            return .sendItemToBack
        }
    }

    var isAllowedInReadingMode: Bool {
        id.isAllowedInReadingMode
    }

    var shouldCommitActiveInlineTextBeforeExecuting: Bool {
        switch self {
        case .commitTextEdit,
             .decreaseTextFontSize,
             .increaseTextFontSize:
            return false
        case .importMedia,
             .addTextItem,
             .beginTextEdit,
             .crop,
             .beginCropMode,
             .undo,
             .redo,
             .selectItem,
             .toggleSelectionMembership,
             .clearSelection,
             .duplicateItem,
             .duplicateSelection,
             .deleteItem,
             .deleteSelection,
             .bringItemForward,
             .bringSelectionForward,
             .sendItemBackward,
             .sendSelectionBackward,
             .bringItemToFront,
             .bringSelectionToFront,
             .sendItemToBack,
             .sendSelectionToBack:
            return true
        }
    }

    // Command execution can invalidate rotation preview / interaction state, so
    // controllers should cancel active rotation before applying these commands.
    var shouldCancelActiveRotation: Bool {
        switch self {
        case .importMedia,
             .addTextItem,
             .beginTextEdit,
             .commitTextEdit,
             .decreaseTextFontSize,
             .increaseTextFontSize,
             .crop,
             .beginCropMode,
             .undo,
             .redo,
             .selectItem,
             .toggleSelectionMembership,
             .clearSelection,
             .duplicateItem,
             .duplicateSelection,
             .deleteItem,
             .deleteSelection,
             .bringItemForward,
             .bringSelectionForward,
             .sendItemBackward,
             .sendSelectionBackward,
             .bringItemToFront,
             .bringSelectionToFront,
             .sendItemToBack,
             .sendSelectionToBack:
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
