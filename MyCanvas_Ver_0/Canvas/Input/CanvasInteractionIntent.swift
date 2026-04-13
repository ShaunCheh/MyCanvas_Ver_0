import Foundation

// Shared interaction intents live in the downstream interaction lane.
// Raw keyboard, pointer, and touch facts belong to CanvasRawInputIntent.
// These intents still stay upstream of transfer/import lowering.
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}

extension CanvasTransferEntryIntent {
    var debugName: String {
        switch self {
        case .pasteKeyboardShortcut:
            return "pasteKeyboardShortcut"
        case .pasteMenu:
            return "pasteMenu"
        case .importButton:
            return "importButton"
        case .dragAndDrop:
            return "dragAndDrop"
        }
    }
}

extension CanvasInteractionIntent {
    var debugName: String {
        switch self {
        case .transferEntry(let entry):
            return "transferEntry.\(entry.debugName)"
        case .command(let commandID):
            return "command.\(commandID.rawValue)"
        case .contextMenuRequest:
            return "contextMenuRequest"
        case .beginTextEdit:
            return "beginTextEdit"
        }
    }
}
