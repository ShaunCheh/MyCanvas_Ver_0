import Foundation

// Shared interaction intents stay upstream of transfer/import lowering.
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
