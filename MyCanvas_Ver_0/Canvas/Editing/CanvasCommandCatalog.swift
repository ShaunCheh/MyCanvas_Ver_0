import Foundation

struct CanvasCommandCatalog {
    func descriptor(
        for commandID: CanvasCommandID,
        session: CanvasEditorSession
    ) -> CanvasCommandDescriptor {
        switch commandID {
        case .crop:
            let isActive = session.isInlineCropModeActive
            return CanvasCommandDescriptor(
                id: .crop,
                title: isActive ? "Done" : "Crop",
                systemImageName: isActive ? "checkmark" : "crop",
                isEnabled: isActive || session.canBeginCropMode,
                isActive: isActive
            )
        case .undo:
            return CanvasCommandDescriptor(
                id: .undo,
                title: "Undo",
                systemImageName: "arrow.uturn.backward",
                isEnabled: session.canUndoCommand,
                isActive: false
            )
        case .redo:
            return CanvasCommandDescriptor(
                id: .redo,
                title: "Redo",
                systemImageName: "arrow.uturn.forward",
                isEnabled: session.canRedoCommand,
                isActive: false
            )
        case .selectItem:
            return CanvasCommandDescriptor(
                id: .selectItem,
                title: "Select",
                systemImageName: "checkmark.circle",
                isEnabled: true,
                isActive: false
            )
        case .clearSelection:
            return CanvasCommandDescriptor(
                id: .clearSelection,
                title: "Deselect",
                systemImageName: "xmark.circle",
                isEnabled: session.canClearSelection,
                isActive: false
            )
        }
    }
}
