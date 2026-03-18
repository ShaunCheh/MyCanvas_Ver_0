import Foundation

struct CanvasContextMenuCommandResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func commandIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        let candidateIDs: [CanvasCommandID]

        switch context.targetKind {
        case .blank:
            candidateIDs = [
                .clearSelection,
                .undo,
                .redo
            ]
        case .selectedItemBody:
            candidateIDs = [
                .crop,
                .clearSelection,
                .undo,
                .redo
            ]
        case .unselectedItemBody:
            // Keep invocation target and current selection separate so secondary
            // click does not mutate selection/history before the user picks a
            // concrete command.
            candidateIDs = [
                .selectItem,
                .undo,
                .redo
            ]
        case .rotateHandle, .cropHandle, .cropOutline, .selectionHandle:
            return []
        }

        return candidateIDs.filter { commandID in
            canPresent(
                commandID,
                for: context,
                session: session
            )
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
        }
    }

    private func canPresent(
        _ commandID: CanvasCommandID,
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> Bool {
        switch commandID {
        case .selectItem:
            guard
                let itemID = context.targetItemID,
                session.canSelectItem(withID: itemID)
            else {
                return false
            }
        case .clearSelection:
            guard context.selectedItemID != nil else {
                return false
            }
        case .crop, .undo, .redo:
            break
        }

        return commandCatalog.descriptor(
            for: commandID,
            session: session
        ).isEnabled
    }
}
