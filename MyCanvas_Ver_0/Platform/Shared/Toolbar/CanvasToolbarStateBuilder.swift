import Foundation

struct CanvasToolbarStateBuilder {
    private let commandCatalog = CanvasCommandCatalog()

    func mainToolbarState(
        session: CanvasEditorSession,
        saveState: CanvasSaveState,
        placement: CanvasToolbarPlacement,
        isImportEnabled: Bool = true,
        showsBackground: Bool = true
    ) -> CanvasToolbarState {
        var itemStates: [CanvasToolbarItemState] = []
        if shouldShowCropItem(session: session) {
            itemStates.append(cropItemState(session: session))
        }
        itemStates.append(saveItemState(saveState: saveState))
        itemStates.append(textItemState(session: session))
        itemStates.append(importItemState(isEnabled: isImportEnabled))

        let toolbarState = CanvasToolbarState(
            placement: placement,
            items: itemStates,
            showsBackground: showsBackground
        )
        logMainToolbarStateIfNeeded(
            toolbarState,
            session: session
        )
        return toolbarState
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

    func importItemState(isEnabled: Bool = true) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .importImage,
            systemImageName: "plus",
            isEnabled: isEnabled,
            accessibilityLabel: "Import image",
            visualRole: .accent
        )
    }

    private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
        guard session.isInlineCropModeActive == false else {
            return true
        }

        return session.selectedBoardItemKind != .text
    }

    private func logMainToolbarStateIfNeeded(
        _ toolbarState: CanvasToolbarState,
        session: CanvasEditorSession
    ) {
        guard
            session.selectedBoardItemKind == .text ||
            session.isInlineTextModeActive
        else {
            return
        }

        let itemSummary = toolbarState.items.map { itemState in
            "\(itemState.id.rawValue):image=\(itemState.systemImageName):enabled=\(itemState.isEnabled):active=\(itemState.isActive)"
        }.joined(separator: ", ")
        print(
            "[Canvas Toolbar Debug][Shared] " +
            "selectedKind=\(describeBoardItemKind(session.selectedBoardItemKind)) " +
            "isInlineText=\(session.isInlineTextModeActive) " +
            "isInlineCrop=\(session.isInlineCropModeActive) " +
            "showsCrop=\(shouldShowCropItem(session: session)) " +
            "placementEdge=\(toolbarState.placement.preferredEdge.rawValue) " +
            "preferredAxis=\(toolbarState.preferredAxis.rawValue) " +
            "items=[\(itemSummary)]"
        )
    }

    private func describeBoardItemKind(
        _ kind: CanvasBoardItemKind?
    ) -> String {
        guard let kind else {
            return "nil"
        }

        switch kind {
        case .image:
            return "image"
        case .text:
            return "text"
        }
    }
}
