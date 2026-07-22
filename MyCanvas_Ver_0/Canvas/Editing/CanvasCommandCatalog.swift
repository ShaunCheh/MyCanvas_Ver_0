import Foundation

struct CanvasCommandCatalog {
    private let interactionPolicy = CanvasInteractionPolicy()

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
        case .addMarkdownItem:
            descriptor = CanvasCommandDescriptor(
                id: .addMarkdownItem,
                title: "Add Markdown",
                systemImageName: "text.alignleft",
                isEnabled: session.canAddMarkdownItem,
                isActive: false
            )
        case .addHandDrawingItem:
            descriptor = CanvasCommandDescriptor(
                id: .addHandDrawingItem,
                title: "Add Hand Drawing",
                systemImageName: "scribble",
                isEnabled: session.canAddHandDrawingItem,
                isActive: false
            )
        case .addArrowItem:
            descriptor = CanvasCommandDescriptor(
                id: .addArrowItem,
                title: "Add Arrow",
                systemImageName: "arrowshape.right.fill",
                isEnabled: session.canAddArrowItem,
                isActive: false
            )
        case .addGroup:
            descriptor = CanvasCommandDescriptor(
                id: .addGroup,
                title: "Add Group",
                systemImageName: "rectangle.dashed",
                isEnabled: session.canAddGroup,
                isActive: false
            )
        case .beginTextEdit:
            let resolvedTargetItemID = singleEffectiveItemID(
                in: context,
                session: session
            )
            descriptor = CanvasCommandDescriptor(
                id: .beginTextEdit,
                title: "Edit Text",
                systemImageName: "pencil",
                isEnabled: resolvedTargetItemID.map { itemID in
                    return session.canBeginTextEdit(withID: itemID)
                } ?? false,
                isActive: false
            )
        case .beginMarkdownEdit:
            let resolvedTargetItemID = singleEffectiveItemID(
                in: context,
                session: session
            )
            descriptor = CanvasCommandDescriptor(
                id: .beginMarkdownEdit,
                title: "Edit Markdown",
                systemImageName: "pencil",
                isEnabled: resolvedTargetItemID.map { itemID in
                    return session.canBeginMarkdownEdit(withID: itemID)
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
        case .commitMarkdownEdit:
            descriptor = CanvasCommandDescriptor(
                id: .commitMarkdownEdit,
                title: "Done",
                systemImageName: "checkmark",
                isEnabled: session.canCommitMarkdownEdit,
                isActive: false
            )
        case .decreaseTextFontSize:
            descriptor = CanvasCommandDescriptor(
                id: .decreaseTextFontSize,
                title: "Smaller Text",
                systemImageName: "minus",
                isEnabled: session.canDecreaseInlineTextFontSize,
                isActive: false
            )
        case .increaseTextFontSize:
            descriptor = CanvasCommandDescriptor(
                id: .increaseTextFontSize,
                title: "Larger Text",
                systemImageName: "plus",
                isEnabled: session.canIncreaseInlineTextFontSize,
                isActive: false
            )
        case .decreaseMarkdownContentSize:
            descriptor = CanvasCommandDescriptor(
                id: .decreaseMarkdownContentSize,
                title: "Smaller Markdown",
                systemImageName: "minus",
                isEnabled: session.canDecreaseMarkdownContentSize,
                isActive: false
            )
        case .increaseMarkdownContentSize:
            descriptor = CanvasCommandDescriptor(
                id: .increaseMarkdownContentSize,
                title: "Larger Markdown",
                systemImageName: "plus",
                isEnabled: session.canIncreaseMarkdownContentSize,
                isActive: false
            )
        case .decreaseArrowThickness:
            descriptor = CanvasCommandDescriptor(
                id: .decreaseArrowThickness,
                title: "Thinner Arrow",
                systemImageName: "minus",
                isEnabled: session.canDecreaseArrowThickness,
                isActive: false
            )
        case .increaseArrowThickness:
            descriptor = CanvasCommandDescriptor(
                id: .increaseArrowThickness,
                title: "Thicker Arrow",
                systemImageName: "plus",
                isEnabled: session.canIncreaseArrowThickness,
                isActive: false
            )
        case .crop:
            let isActive = session.isInlineCropModeActive
            let resolvedTargetItemID = singleEffectiveItemID(
                in: context,
                session: session
            )
            descriptor = CanvasCommandDescriptor(
                id: .crop,
                title: isActive ? "Done" : "Crop",
                systemImageName: isActive ? "checkmark" : "crop",
                isEnabled: isActive || resolvedTargetItemID.map { itemID in
                    session.canBeginCropMode(withID: itemID)
                } ?? false,
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
                isEnabled: duplicateCommandIsEnabled(
                    in: context,
                    session: session
                ),
                isActive: false
            )
        case .deleteItem:
            descriptor = CanvasCommandDescriptor(
                id: .deleteItem,
                title: "Delete",
                systemImageName: "trash",
                isEnabled: deleteCommandIsEnabled(
                    in: context,
                    session: session
                ),
                isActive: false
            )
        case .bringItemForward:
            descriptor = CanvasCommandDescriptor(
                id: .bringItemForward,
                title: "Bring Forward",
                systemImageName: "chevron.up",
                isEnabled: bringForwardCommandIsEnabled(
                    in: context,
                    session: session
                ),
                isActive: false
            )
        case .sendItemBackward:
            descriptor = CanvasCommandDescriptor(
                id: .sendItemBackward,
                title: "Send Backward",
                systemImageName: "chevron.down",
                isEnabled: sendBackwardCommandIsEnabled(
                    in: context,
                    session: session
                ),
                isActive: false
            )
        case .bringItemToFront:
            descriptor = CanvasCommandDescriptor(
                id: .bringItemToFront,
                title: "Bring To Front",
                systemImageName: "chevron.up.2",
                isEnabled: bringToFrontCommandIsEnabled(
                    in: context,
                    session: session
                ),
                isActive: false
            )
        case .sendItemToBack:
            descriptor = CanvasCommandDescriptor(
                id: .sendItemToBack,
                title: "Send To Back",
                systemImageName: "chevron.down.2",
                isEnabled: sendToBackCommandIsEnabled(
                    in: context,
                    session: session
                ),
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
        context?.targetItemID ?? session.primarySelectedItemID
    }

    private func singleEffectiveItemID(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        context?.singleEffectiveItemID ?? session.singleSelectedItemID
    }

    private func operatesOnCurrentSelection(
        in context: CanvasContextMenuContext?
    ) -> Bool {
        context?.operatesOnCurrentSelection ?? true
    }

    private func duplicateCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canDuplicateSelection
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canDuplicateItem(withID: itemID)
        } ?? false
    }

    private func deleteCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canDeleteSelection
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canDeleteItem(withID: itemID)
        } ?? false
    }

    private func bringForwardCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canBringSelectionForward
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canBringItemForward(withID: itemID)
        } ?? false
    }

    private func sendBackwardCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canSendSelectionBackward
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canSendItemBackward(withID: itemID)
        } ?? false
    }

    private func bringToFrontCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canBringSelectionToFront
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canBringItemToFront(withID: itemID)
        } ?? false
    }

    private func sendToBackCommandIsEnabled(
        in context: CanvasContextMenuContext?,
        session: CanvasEditorSession
    ) -> Bool {
        if operatesOnCurrentSelection(in: context) {
            return session.canSendSelectionToBack
        }

        return targetItemID(in: context, session: session).map { itemID in
            session.canSendItemToBack(withID: itemID)
        } ?? false
    }

    private func workspaceModeAdjustedDescriptor(
        _ descriptor: CanvasCommandDescriptor,
        session: CanvasEditorSession
    ) -> CanvasCommandDescriptor {
        switch interactionPolicy.commandDecision(
        for: descriptor.id,
        workspaceMode: session.workspaceMode
        ) {
        case .allow:
            return descriptor
        case .block:
            return CanvasCommandDescriptor(
                id: descriptor.id,
                title: descriptor.title,
                systemImageName: descriptor.systemImageName,
                isEnabled: false,
                isActive: false
            )
        }
    }
}
