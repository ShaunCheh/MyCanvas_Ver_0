import Foundation

struct CanvasContextMenuActionResolver {
    private let commandCatalog = CanvasCommandCatalog()
    private let interactionPolicy = CanvasInteractionPolicy()

    func actionStates(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession,
        environment: CanvasInteractionEnvironment? = nil
    ) -> [CanvasContextMenuActionState] {
        let resolvedEnvironment = environment ?? .workspaceModeOnly(
            workspaceMode: session.workspaceMode
        )
        let candidateActionIDs = candidateActionIDs(
            for: context,
            session: session
        )
        switch interactionPolicy.decision(
        for: .contextMenuRequest,
        environment: resolvedEnvironment
        ) {
        case .allow:
            break
        case .block(let reason, _):
            print(
                "[Canvas Shared][ContextMenuActions] " +
                context.debugSummary + " " +
                "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
                "enabledIDs=[] " +
                "disabledIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
                "reason=\(describeInteractionBlockReason(reason))"
            )
            return []
        }

        let actionStates = candidateActionIDs.map { actionID in
            CanvasContextMenuActionState(
                actionID: actionID,
                descriptor: descriptor(
                    for: actionID,
                    context: context,
                    session: session
                )
            )
        }
        let enabledStates = actionStates.filter(\.descriptor.isEnabled)
        let enabledIDSet = Set(
            enabledStates.map(\.actionID.rawValueDescription)
        )
        let disabledIDs = candidateActionIDs.filter { actionID in
            enabledIDSet.contains(actionID.rawValueDescription) == false
        }
        print(
            "[Canvas Shared][ContextMenuActions] " +
            context.debugSummary + " " +
            "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
            "enabledIDs=[\(describeContextMenuActionIDs(enabledStates.map(\.actionID)))] " +
            "disabledIDs=[\(describeContextMenuActionIDs(disabledIDs))]"
        )
        return enabledStates
    }

    func command(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext
    ) -> CanvasCommand? {
        switch commandID {
        case .importMedia:
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

    private func descriptor(
        for actionID: CanvasContextMenuActionID,
        context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasContextMenuActionDescriptor {
        switch actionID {
        case let .command(commandID):
            return CanvasContextMenuActionDescriptor(
                commandDescriptor: commandCatalog.descriptor(
                    for: commandID,
                    session: session,
                    context: context
                )
            )
        case let .uiAction(uiActionID):
            return uiActionDescriptor(
                for: uiActionID,
                context: context,
                session: session
            )
        }
    }

    private func uiActionDescriptor(
        for uiActionID: CanvasContextMenuUIActionID,
        context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasContextMenuActionDescriptor {
        switch uiActionID {
        case .editVideoDisplayFrame:
            return CanvasContextMenuActionDescriptor(
                title: "Set Display Frame",
                systemImageName: "movieclapper",
                isEnabled: targetVideoItemID(
                    in: context,
                    session: session
                ) != nil,
                isActive: false
            )
        case .importGIFFrames:
            return CanvasContextMenuActionDescriptor(
                title: "Import GIF Frames",
                systemImageName: "square.grid.3x3",
                isEnabled: targetGIFItemID(
                    in: context,
                    session: session
                ) != nil,
                isActive: false
            )
        }
    }

    private func candidateActionIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasContextMenuActionID] {
        let targetTextItem = context.targetItemID.flatMap { itemID in
            session.scene.textItem(withID: itemID)
        }
        let includeVideoDisplayFrameAction =
            targetVideoItemID(in: context, session: session) != nil
        let includeGIFFrameImportAction =
            targetGIFItemID(in: context, session: session) != nil

        switch context.targetKind {
        case .blank:
            return [
                .command(.clearSelection),
                .command(.undo),
                .command(.redo)
            ]
        case .selectedItemBody, .selectionHandle, .rotateHandle:
            return selectedItemActionIDs(
                includeCropCommand: targetTextItem == nil,
                includeBeginTextEditCommand: targetTextItem != nil,
                includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
                includeGIFFrameImportAction: includeGIFFrameImportAction
            )
        case .unselectedItemBody:
            // Keep invocation target and current selection separate so opening a
            // menu does not rewrite selection/history before the user chooses an
            // explicit command.
            return unselectedItemActionIDs(
                includeBeginTextEditCommand: targetTextItem != nil,
                includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
                includeGIFFrameImportAction: includeGIFFrameImportAction
            )
        case .cropHandle, .cropOutline:
            return selectedItemActionIDs(
                includeCropCommand: true,
                includeBeginTextEditCommand: false,
                includeVideoDisplayFrameAction: false,
                includeGIFFrameImportAction: false
            )
        }
    }

    private func selectedItemActionIDs(
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool,
        includeVideoDisplayFrameAction: Bool,
        includeGIFFrameImportAction: Bool
    ) -> [CanvasContextMenuActionID] {
        var actionIDs: [CanvasContextMenuActionID] = []
        if includeCropCommand {
            actionIDs.append(.command(.crop))
        }
        if includeBeginTextEditCommand {
            actionIDs.append(.command(.beginTextEdit))
        }
        if includeVideoDisplayFrameAction {
            actionIDs.append(.uiAction(.editVideoDisplayFrame))
        }
        if includeGIFFrameImportAction {
            actionIDs.append(.uiAction(.importGIFFrames))
        }
        actionIDs.append(contentsOf: [
            .command(.duplicateItem),
            .command(.deleteItem),
            .command(.bringItemForward),
            .command(.sendItemBackward),
            .command(.bringItemToFront),
            .command(.sendItemToBack),
            .command(.clearSelection),
            .command(.undo),
            .command(.redo)
        ])
        return actionIDs
    }

    private func unselectedItemActionIDs(
        includeBeginTextEditCommand: Bool,
        includeVideoDisplayFrameAction: Bool,
        includeGIFFrameImportAction: Bool
    ) -> [CanvasContextMenuActionID] {
        var actionIDs: [CanvasContextMenuActionID] = [.command(.selectItem)]
        if includeBeginTextEditCommand {
            actionIDs.append(.command(.beginTextEdit))
        }
        if includeVideoDisplayFrameAction {
            actionIDs.append(.uiAction(.editVideoDisplayFrame))
        }
        if includeGIFFrameImportAction {
            actionIDs.append(.uiAction(.importGIFFrames))
        }
        actionIDs.append(contentsOf: [
            .command(.duplicateItem),
            .command(.deleteItem),
            .command(.bringItemForward),
            .command(.sendItemBackward),
            .command(.bringItemToFront),
            .command(.sendItemToBack),
            .command(.undo),
            .command(.redo)
        ])
        return actionIDs
    }

    private func targetVideoItemID(
        in context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        guard
            let itemID = context.targetItemID,
            let item = session.scene.item(withID: itemID),
            item.isVideo
        else {
            return nil
        }

        return itemID
    }

    private func targetGIFItemID(
        in context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        guard
            let itemID = context.targetItemID,
            let item = session.scene.item(withID: itemID),
            item.isVideo == false,
            item.assetKind == .animatedGIF
        else {
            return nil
        }

        return itemID
    }
}

private func describeContextMenuActionIDs(
    _ actionIDs: [CanvasContextMenuActionID]
) -> String {
    actionIDs.map(\.rawValueDescription).joined(separator: ",")
}

private func describeInteractionBlockReason(
    _ reason: CanvasInteractionBlockReason
) -> String {
    switch reason {
    case .readingMode:
        return "readingMode"
    case .transitionInteractionFrozen:
        return "transitionInteractionFrozen"
    }
}
