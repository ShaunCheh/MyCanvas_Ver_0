import Foundation

struct CanvasToolbarStateBuilder {
    private let commandCatalog = CanvasCommandCatalog()

    func mainToolbarState(
        session: CanvasEditorSession,
        saveState: CanvasSaveState,
        placement: CanvasToolbarPlacement,
        supportsHandDrawingEditing: Bool = false,
        isMultiSelectModeActive: Bool = false,
        isImportEnabled: Bool = true,
        showsBackground: Bool = true,
        includesHistoryItems: Bool = false
    ) -> CanvasToolbarState {
        guard session.isReadingModeActive == false else {
            return CanvasToolbarState(
                placement: placement,
                items: [],
                showsBackground: showsBackground
            )
        }

        var itemStates: [CanvasToolbarItemState] = []
        if includesHistoryItems {
            itemStates.append(contentsOf: historyItemStates(session: session))
        }
        if shouldShowCropItem(session: session) {
            itemStates.append(cropItemState(session: session))
        }
        itemStates.append(
            multiSelectItemState(
                isActive: isMultiSelectModeActive,
                isEnabled: canToggleMultiSelectMode(session: session)
            )
        )
        if shouldShowDeleteItem(
            session: session,
            isMultiSelectModeActive: isMultiSelectModeActive
        ) {
            itemStates.append(deleteItemState(session: session))
        }
        itemStates.append(saveItemState(saveState: saveState))
        itemStates.append(textItemState(session: session))
        itemStates.append(markdownItemState(session: session))
        if supportsHandDrawingEditing {
            itemStates.append(handDrawingItemState(session: session))
        }
        itemStates.append(importItemState(isEnabled: isImportEnabled))

        return CanvasToolbarState(
            placement: placement,
            items: itemStates,
            showsBackground: showsBackground
        )
    }

    func historyItemStates(session: CanvasEditorSession) -> [CanvasToolbarItemState] {
        [
            undoItemState(session: session),
            redoItemState(session: session)
        ]
    }

    func undoItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .undo,
            session: session
        )
        return CanvasToolbarItemState(
            id: .undo,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            accessibilityLabel: descriptor.title,
            visualRole: .accent
        )
    }

    func redoItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .redo,
            session: session
        )
        return CanvasToolbarItemState(
            id: .redo,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            accessibilityLabel: descriptor.title,
            visualRole: .accent
        )
    }

    func cropItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .crop,
            session: session
        )
        return cropItemState(from: descriptor)
    }

    func cropItemState(from descriptor: CanvasCommandDescriptor) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .crop,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: descriptor.title == "Done" ? "Done cropping" : "Crop",
            visualRole: descriptor.isActive ? .warning : .accent
        )
    }

    func saveItemState(saveState: CanvasSaveState) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .save,
            systemImageName: saveState.systemImageName,
            isEnabled: saveState.isEnabled,
            accessibilityLabel: "Save board",
            accessibilityValue: saveState.accessibilityValue,
            visualRole: saveState.visualRole,
            preservesVisualRoleWhenDisabled: saveState == .saving
        )
    }

    func multiSelectItemState(
        isActive: Bool,
        isEnabled: Bool = true
    ) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .multiSelect,
            systemImageName: "checklist",
            isEnabled: isEnabled,
            isActive: isActive,
            accessibilityLabel: "Multi-select",
            accessibilityValue: isActive ? "On" : "Off",
            visualRole: isActive ? .accent : .neutral
        )
    }

    func deleteItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .deleteItem,
            session: session
        )
        let selectionCount = session.selectionCount
        let accessibilityLabel = selectionCount > 1
            ? "Delete selected items"
            : "Delete selected item"
        return CanvasToolbarItemState(
            id: .deleteSelection,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            accessibilityLabel: accessibilityLabel,
            visualRole: .danger
        )
    }

    func textItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: session.isInlineTextModeActive ? .commitTextEdit : .addTextItem,
            session: session
        )
        return CanvasToolbarItemState(
            id: .text,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: descriptor.title == "Done" ? "Done editing text" : "Add text",
            visualRole: descriptor.isActive ? .success : .accent
        )
    }

    func markdownItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .addMarkdownItem,
            session: session
        )
        return CanvasToolbarItemState(
            id: .markdown,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: "Add markdown",
            visualRole: .accent
        )
    }

    func handDrawingItemState(
        session: CanvasEditorSession
    ) -> CanvasToolbarItemState {
        if session.canEditSelectedHandDrawing {
            return CanvasToolbarItemState(
                id: .handDrawing,
                systemImageName: "pencil.and.scribble",
                accessibilityLabel: "Edit hand drawing",
                visualRole: .accent
            )
        }

        let descriptor = commandCatalog.descriptor(
            for: .addHandDrawingItem,
            session: session
        )
        return CanvasToolbarItemState(
            id: .handDrawing,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: "Add hand drawing",
            visualRole: .accent
        )
    }

    func importItemState(isEnabled: Bool = true) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .importMedia,
            systemImageName: "plus",
            isEnabled: isEnabled,
            accessibilityLabel: "Import media",
            visualRole: .accent
        )
    }

    private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
        guard session.isInlineCropModeActive == false else {
            return true
        }

        guard let selectedBoardItemKind = session.selectedBoardItemKind else {
            return true
        }

        return selectedBoardItemKind == .image
    }

    private func canToggleMultiSelectMode(
        session: CanvasEditorSession
    ) -> Bool {
        session.isInlineEditModeActive == false
    }

    private func shouldShowDeleteItem(
        session: CanvasEditorSession,
        isMultiSelectModeActive: Bool
    ) -> Bool {
        guard session.canDeleteSelection else {
            return false
        }

        if isMultiSelectModeActive {
            return true
        }

        if session.selectionCount > 1 {
            return true
        }

        return canShowDeleteForSingleSelection(session: session)
    }

    private func canShowDeleteForSingleSelection(
        session: CanvasEditorSession
    ) -> Bool {
        switch session.selectedBoardItemKind {
        case .text, .markdown, .handDrawing:
            return true
        case .image, .none:
            return false
        }
    }
}
