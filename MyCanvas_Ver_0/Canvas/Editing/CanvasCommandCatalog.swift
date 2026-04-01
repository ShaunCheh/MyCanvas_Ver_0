import Foundation

struct CanvasCommandCatalog {
    func descriptor(
        for commandID: CanvasCommandID,
        session: CanvasEditorSession,
        context: CanvasContextMenuContext? = nil
    ) -> CanvasCommandDescriptor {
        let descriptor: CanvasCommandDescriptor
        switch commandID {
        case .importMedia:
            descriptor = CanvasCommandDescriptor(
                id: .importMedia,
                title: "Import Media",
                systemImageName: "photo.on.rectangle.angled",
                isEnabled: false,
                isActive: false
            )
        case .addTextItem:
            descriptor = CanvasCommandDescriptor(
                id: .addTextItem,
                title: "Add Text",
                systemImageName: "textformat",
                isEnabled: session.canAddTextItem,
                isActive: false
            )
        case .beginTextEdit:
            descriptor = CanvasCommandDescriptor(
                id: .beginTextEdit,
                title: "Edit Text",
                systemImageName: "pencil",
                isEnabled: targetItemID(
                    in: context,
                    session: session
                ).map { itemID in
                    session.canBeginTextEdit(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .commitTextEdit:
            descriptor = CanvasCommandDescriptor(
                id: .commitTextEdit,
                title: "Done",
                systemImageName: "checkmark",
                isEnabled: session.canCommitTextEdit,
                isActive: session.isInlineTextModeActive
            )
        case .crop:
            let isActive = session.isInlineCropModeActive
            descriptor = CanvasCommandDescriptor(
                id: .crop,
                title: isActive ? "Done" : "Crop",
                systemImageName: isActive ? "checkmark" : "crop",
                isEnabled: isActive || session.canBeginCropMode,
                isActive: isActive
            )
        case .undo:
            descriptor = CanvasCommandDescriptor(
                id: .undo,
                title: "Undo",
                systemImageName: "arrow.uturn.backward",
                isEnabled: session.canUndoCommand,
                isActive: false
            )
        case .redo:
            descriptor = CanvasCommandDescriptor(
                id: .redo,
                title: "Redo",
                systemImageName: "arrow.uturn.forward",
                isEnabled: session.canRedoCommand,
                isActive: false
            )
        case .selectItem:
            descriptor = CanvasCommandDescriptor(
                id: .selectItem,
                title: "Select",
                systemImageName: "checkmark.circle",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canSelectItem(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .clearSelection:
            descriptor = CanvasCommandDescriptor(
                id: .clearSelection,
                title: "Deselect",
                systemImageName: "xmark.circle",
                isEnabled: session.canClearSelection,
                isActive: false
            )
        case .duplicateItem:
            descriptor = CanvasCommandDescriptor(
                id: .duplicateItem,
                title: "Duplicate",
                systemImageName: "square.on.square",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canDuplicateItem(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .deleteItem:
            descriptor = CanvasCommandDescriptor(
                id: .deleteItem,
                title: "Delete",
                systemImageName: "trash",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canDeleteItem(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .bringItemForward:
            descriptor = CanvasCommandDescriptor(
                id: .bringItemForward,
                title: "Bring Forward",
                systemImageName: "chevron.up",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canBringItemForward(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .sendItemBackward:
            descriptor = CanvasCommandDescriptor(
                id: .sendItemBackward,
                title: "Send Backward",
                systemImageName: "chevron.down",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canSendItemBackward(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .bringItemToFront:
            descriptor = CanvasCommandDescriptor(
                id: .bringItemToFront,
                title: "Bring To Front",
                systemImageName: "chevron.up.2",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canBringItemToFront(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .sendItemToBack:
            descriptor = CanvasCommandDescriptor(
                id: .sendItemToBack,
                title: "Send To Back",
                systemImageName: "chevron.down.2",
                isEnabled: targetItemID(in: context, session: session).map { itemID in
                    session.canSendItemToBack(withID: itemID)
                } ?? false,
                isActive: false
            )
        }

        return workspaceModeAdjustedDescriptor(
            descriptor,
            session: session
        )
    }

    private func targetItemID(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        context?.targetItemID ?? session.interactionState.selectedItemID
    }

    private func workspaceModeAdjustedDescriptor(
        _ descriptor: CanvasCommandDescriptor,
        session: CanvasEditorSession
    ) -> CanvasCommandDescriptor {
        guard
            session.isReadingModeActive,
            descriptor.id.isAllowedInReadingMode == false
        else {
            return descriptor
        }

        return CanvasCommandDescriptor(
            id: descriptor.id,
            title: descriptor.title,
            systemImageName: descriptor.systemImageName,
            isEnabled: false,
            isActive: false
        )
    }
}
