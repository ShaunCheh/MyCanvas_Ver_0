import Foundation

struct CanvasContextMenuCommandResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func commandIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        let candidateIDs = candidateCommandIDs(
            for: context,
            session: session
        )
        let enabledIDs = candidateIDs.filter { commandID in
            commandCatalog.descriptor(
                for: commandID,
                session: session,
                context: context
            ).isEnabled
        }
        let enabledIDSet = Set(enabledIDs)
        let disabledIDs = candidateIDs.filter { enabledIDSet.contains($0) == false }
        print(
            "[Canvas Shared][ContextMenuCommands] " +
            context.debugSummary + " " +
            "candidateIDs=[\(describeContextMenuCommandIDs(candidateIDs))] " +
            "enabledIDs=[\(describeContextMenuCommandIDs(enabledIDs))] " +
            "disabledIDs=[\(describeContextMenuCommandIDs(disabledIDs))]"
        )
        return enabledIDs
    }

    func command(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext
    ) -> CanvasCommand? {
        switch commandID {
        case .importImages:
            return nil
        case .addTextItem:
            return .addTextItem
        case .beginTextEdit:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .beginTextEdit(itemID: itemID)
        case .commitTextEdit:
            return .commitTextEdit
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
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        let targetTextItem = context.targetItemID.flatMap { itemID in
            session.scene.textItem(withID: itemID)
        }

        switch context.targetKind {
        case .blank:
            return [
                .clearSelection,
                .undo,
                .redo
            ]
        case .selectedItemBody, .selectionHandle, .rotateHandle:
            return selectedItemCommandIDs(
                includeCropCommand: targetTextItem == nil,
                includeBeginTextEditCommand: targetTextItem != nil
            )
        case .unselectedItemBody:
            // Keep invocation target and current selection separate so opening a
            // menu does not rewrite selection/history before the user chooses an
            // explicit command.
            return unselectedItemCommandIDs(
                includeBeginTextEditCommand: targetTextItem != nil
            )
        case .cropHandle, .cropOutline:
            return selectedItemCommandIDs(
                includeCropCommand: true,
                includeBeginTextEditCommand: false
            )
        }
    }

    private func selectedItemCommandIDs(
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool
    ) -> [CanvasCommandID] {
        var commandIDs: [CanvasCommandID] = []
        if includeCropCommand {
            commandIDs.append(.crop)
        }
        if includeBeginTextEditCommand {
            commandIDs.append(.beginTextEdit)
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

    private func unselectedItemCommandIDs(
        includeBeginTextEditCommand: Bool
    ) -> [CanvasCommandID] {
        var commandIDs: [CanvasCommandID] = [.selectItem]
        if includeBeginTextEditCommand {
            commandIDs.append(.beginTextEdit)
        }
        commandIDs.append(contentsOf: [
            .duplicateItem,
            .deleteItem,
            .bringItemForward,
            .sendItemBackward,
            .bringItemToFront,
            .sendItemToBack,
            .undo,
            .redo
        ])
        return commandIDs
    }
}

private func describeContextMenuCommandIDs(_ commandIDs: [CanvasCommandID]) -> String {
    commandIDs.map(\.rawValue).joined(separator: ",")
}
