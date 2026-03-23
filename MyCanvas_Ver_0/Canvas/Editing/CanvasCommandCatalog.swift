import Foundation

struct CanvasCommandCatalog {
    func descriptor(
        for commandID: CanvasCommandID,
        session: CanvasEditorSession,
        context: CanvasContextMenuContext? = nil
    ) -> CanvasCommandDescriptor {
        switch commandID {
        case .importImages:
            return CanvasCommandDescriptor(
                id: .importImages,
                title: "Import Images",
                systemImageName: "photo.on.rectangle.angled",
                isEnabled: false,
                isActive: false
            )
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
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canSelectItem(withID: itemID)
                } ?? false,
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
        case .duplicateItem:
            return CanvasCommandDescriptor(
                id: .duplicateItem,
                title: "Duplicate",
                systemImageName: "square.on.square",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canDuplicateItem(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .deleteItem:
            return CanvasCommandDescriptor(
                id: .deleteItem,
                title: "Delete",
                systemImageName: "trash",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canDeleteItem(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .bringItemForward:
            return CanvasCommandDescriptor(
                id: .bringItemForward,
                title: "Bring Forward",
                systemImageName: "chevron.up",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canBringItemForward(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .sendItemBackward:
            return CanvasCommandDescriptor(
                id: .sendItemBackward,
                title: "Send Backward",
                systemImageName: "chevron.down",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canSendItemBackward(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .bringItemToFront:
            return CanvasCommandDescriptor(
                id: .bringItemToFront,
                title: "Bring To Front",
                systemImageName: "chevron.up.2",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canBringItemToFront(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .sendItemToBack:
            return CanvasCommandDescriptor(
                id: .sendItemToBack,
                title: "Send To Back",
                systemImageName: "chevron.down.2",
                isEnabled: targetItemID(in: context).map { itemID in
                    session.canSendItemToBack(withID: itemID)
                } ?? false,
                isActive: false
            )
        }
    }

    private func targetItemID(
        in context: CanvasContextMenuContext?
    ) -> CanvasImageItemID? {
        context?.targetItemID
    }
}
