import Foundation

struct CanvasContextMenuCommandResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func commandIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        candidateCommandIDs(for: context).filter { commandID in
            commandCatalog.descriptor(
                for: commandID,
                session: session,
                context: context
            ).isEnabled
        }
    }

    func command(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext
    ) -> CanvasCommand? {
        switch commandID {
        case .crop:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .selectItem(
                itemID: itemID,
                recordHistory: true
            )
        case .clearSelection:
            return .clearSelection(recordHistory: true)
        case .duplicateItem:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .duplicateItem(
                itemID: itemID,
                recordHistory: true
            )
        case .deleteItem:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .deleteItem(
                itemID: itemID,
                recordHistory: true
            )
        case .bringItemForward:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .bringItemForward(
                itemID: itemID,
                recordHistory: true
            )
        case .sendItemBackward:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .sendItemBackward(
                itemID: itemID,
                recordHistory: true
            )
        case .bringItemToFront:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .bringItemToFront(
                itemID: itemID,
                recordHistory: true
            )
        case .sendItemToBack:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .sendItemToBack(
                itemID: itemID,
                recordHistory: true
            )
        }
    }

    private func candidateCommandIDs(
        for context: CanvasContextMenuContext
    ) -> [CanvasCommandID] {
        switch context.targetKind {
        case .blank:
            return [
                .clearSelection,
                .undo,
                .redo
            ]
        case .selectedItemBody, .selectionHandle, .rotateHandle:
            return selectedItemCommandIDs(includeCropCommand: true)
        case .unselectedItemBody:
            // Keep invocation target and current selection separate so opening a
            // menu does not rewrite selection/history before the user chooses an
            // explicit command.
            return [
                .selectItem,
                .duplicateItem,
                .deleteItem,
                .bringItemForward,
                .sendItemBackward,
                .bringItemToFront,
                .sendItemToBack,
                .undo,
                .redo
            ]
        case .cropHandle, .cropOutline:
            return selectedItemCommandIDs(includeCropCommand: true)
        }
    }

    private func selectedItemCommandIDs(
        includeCropCommand: Bool
    ) -> [CanvasCommandID] {
        var commandIDs: [CanvasCommandID] = []
        if includeCropCommand {
            commandIDs.append(.crop)
        }
        commandIDs.append(contentsOf: [
            .duplicateItem,
            .deleteItem,
            .bringItemForward,
            .sendItemBackward,
            .bringItemToFront,
            .sendItemToBack,
            .clearSelection,
            .undo,
            .redo
        ])
        return commandIDs
    }
}
