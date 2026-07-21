import Foundation

struct CanvasContextMenuActionResolver {
    private let commandCatalog = CanvasCommandCatalog()
    private let interactionPolicy = CanvasInteractionPolicy()

    func actionStates(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession,
        environment: CanvasInteractionEnvironment? = nil,
        supportsHandDrawingEditing: Bool = false
    ) -> [CanvasContextMenuActionState] {
        let resolvedEnvironment = environment ?? .workspaceModeOnly(
            workspaceMode: session.workspaceMode
        )
        let intent = CanvasInteractionIntent.contextMenuRequest
        let candidateActionIDs = candidateActionIDs(
            for: context,
            session: session,
            supportsHandDrawingEditing: supportsHandDrawingEditing
        )
        let decision = interactionPolicy.decision(
            for: intent,
            environment: resolvedEnvironment
        )
        switch decision {
        case .allow:
            break
        case .block:
            logContextMenuInteractionDecision(
                intent: intent,
                decision: decision,
                environment: resolvedEnvironment,
                context: context,
                candidateActionIDs: candidateActionIDs,
                enabledActionIDs: [],
                disabledActionIDs: candidateActionIDs
            )
            return []
        }

        let actionStates = candidateActionIDs.map { actionID in
            CanvasContextMenuActionState(
                actionID: actionID,
                descriptor: descriptor(
                    for: actionID,
                    context: context,
                    session: session,
                    supportsHandDrawingEditing: supportsHandDrawingEditing
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
        logContextMenuInteractionDecision(
            intent: intent,
            decision: decision,
            environment: resolvedEnvironment,
            context: context,
            candidateActionIDs: candidateActionIDs,
            enabledActionIDs: enabledStates.map(\.actionID),
            disabledActionIDs: disabledIDs
        )
        return enabledStates
    }

    func command(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext,
        session _: CanvasEditorSession
    ) -> CanvasCommand? {
        switch commandID {
        case .importMedia:
            return nil
        case .addTextItem:
            return .addTextItem
        case .addMarkdownItem:
            return .addMarkdownItem(markdownSource: nil)
        case .addHandDrawingItem:
            return .addHandDrawingItem(paper: .square)
        case .addArrowItem:
            return .addArrowItem
        case .beginTextEdit:
            guard let itemID = context.singleEffectiveItemID else {
                return nil
            }

            return .beginTextEdit(itemID: itemID)
        case .beginMarkdownEdit:
            guard let itemID = context.singleEffectiveItemID else {
                return nil
            }

            return .beginMarkdownEdit(itemID: itemID)
        case .commitTextEdit:
            return .commitTextEdit
        case .commitMarkdownEdit:
            return nil
        case .decreaseTextFontSize,
             .increaseTextFontSize,
             .decreaseMarkdownContentSize,
             .increaseMarkdownContentSize,
             .decreaseArrowThickness,
             .increaseArrowThickness:
            return nil
        case .crop:
            if context.isInlineCropModeActive {
                return .crop
            }

            guard let itemID = context.singleEffectiveItemID else {
                return nil
            }

            if context.operatesOnCurrentSelection {
                return .crop
            }

            return .beginCropMode(itemID: itemID)
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
            if operatesOnCurrentSelection(in: context) {
                return .duplicateSelection(recordHistory: true)
            }

            guard let itemID = context.targetItemID else {
                return nil
            }
            return .duplicateItem(
                itemID: itemID,
                selectDuplicatedItem: false,
                recordHistory: true
            )
        case .deleteItem:
            if operatesOnCurrentSelection(in: context) {
                return .deleteSelection(recordHistory: true)
            }

            guard let itemID = context.targetItemID else {
                return nil
            }
            return .deleteItem(
                itemID: itemID,
                recordHistory: true
            )
        case .bringItemForward:
            if operatesOnCurrentSelection(in: context) {
                return .bringSelectionForward(recordHistory: true)
            }

            guard let itemID = context.targetItemID else {
                return nil
            }
            return .bringItemForward(
                itemID: itemID,
                recordHistory: true
            )
        case .sendItemBackward:
            if operatesOnCurrentSelection(in: context) {
                return .sendSelectionBackward(recordHistory: true)
            }

            guard let itemID = context.targetItemID else {
                return nil
            }
            return .sendItemBackward(
                itemID: itemID,
                recordHistory: true
            )
        case .bringItemToFront:
            if operatesOnCurrentSelection(in: context) {
                return .bringSelectionToFront(recordHistory: true)
            }

            guard let itemID = context.targetItemID else {
                return nil
            }
            return .bringItemToFront(
                itemID: itemID,
                recordHistory: true
            )
        case .sendItemToBack:
            if operatesOnCurrentSelection(in: context) {
                return .sendSelectionToBack(recordHistory: true)
            }

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
        session: CanvasEditorSession,
        supportsHandDrawingEditing: Bool
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
                session: session,
                supportsHandDrawingEditing: supportsHandDrawingEditing
            )
        }
    }

    private func uiActionDescriptor(
        for uiActionID: CanvasContextMenuUIActionID,
        context: CanvasContextMenuContext,
        session: CanvasEditorSession,
        supportsHandDrawingEditing: Bool
    ) -> CanvasContextMenuActionDescriptor {
        switch uiActionID {
        case .editHandDrawing:
            return CanvasContextMenuActionDescriptor(
                title: "Edit Hand Drawing",
                systemImageName: "scribble",
                isEnabled: supportsHandDrawingEditing && targetHandDrawingItemID(
                    in: context,
                    session: session
                ) != nil,
                isActive: false
            )
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
        session: CanvasEditorSession,
        supportsHandDrawingEditing: Bool
    ) -> [CanvasContextMenuActionID] {
        if context.isInlineCropModeActive {
            switch context.targetKind {
            case .cropHandle, .cropOutline:
                return [.command(.crop)]
            case .rotateHandle,
                 .groupRotateHandle,
                 .selectionHandle,
                 .groupSelectionHandle,
                 .arrowEndpointHandle,
                 .selectedItemBody,
                 .unselectedItemBody,
                 .blank:
                return []
            }
        }

        if context.isInlineEditModeActive {
            return []
        }

        let targetTextItem = context.singleEffectiveItemID.flatMap { itemID in
            session.scene.textItem(withID: itemID)
        }
        let includeCropCommand = context.singleEffectiveItemID.map { itemID in
            session.scene.textItem(withID: itemID) == nil
                && session.scene.item(withID: itemID) != nil
        } ?? false
        let includeVideoDisplayFrameAction =
            targetVideoItemID(in: context, session: session) != nil
        let includeGIFFrameImportAction =
            targetGIFItemID(in: context, session: session) != nil
        let includeHandDrawingEditAction =
            supportsHandDrawingEditing
            && targetHandDrawingItemID(in: context, session: session) != nil

        switch context.targetKind {
        case .blank:
            return [
                .command(.clearSelection),
                .command(.undo),
                .command(.redo)
            ]
        case .selectedItemBody, .selectionHandle, .arrowEndpointHandle, .rotateHandle:
            return selectedItemActionIDs(
                includeCropCommand: includeCropCommand,
                includeBeginTextEditCommand: targetTextItem != nil,
                includeHandDrawingEditAction: includeHandDrawingEditAction,
                includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
                includeGIFFrameImportAction: includeGIFFrameImportAction
            )
        case .groupSelectionHandle, .groupRotateHandle:
            return selectedItemActionIDs(
                includeCropCommand: false,
                includeBeginTextEditCommand: false,
                includeHandDrawingEditAction: false,
                includeVideoDisplayFrameAction: false,
                includeGIFFrameImportAction: false
            )
        case .unselectedItemBody:
            // Keep invocation target and current selection separate so opening a
            // menu does not rewrite selection/history before the user chooses an
            // explicit command.
            return unselectedItemActionIDs(
                includeCropCommand: includeCropCommand,
                includeBeginTextEditCommand: targetTextItem != nil,
                includeHandDrawingEditAction: includeHandDrawingEditAction,
                includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
                includeGIFFrameImportAction: includeGIFFrameImportAction
            )
        case .cropHandle, .cropOutline:
            return [.command(.crop)]
        }
    }

    private func selectedItemActionIDs(
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool,
        includeHandDrawingEditAction: Bool,
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
        if includeHandDrawingEditAction {
            actionIDs.append(.uiAction(.editHandDrawing))
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
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool,
        includeHandDrawingEditAction: Bool,
        includeVideoDisplayFrameAction: Bool,
        includeGIFFrameImportAction: Bool
    ) -> [CanvasContextMenuActionID] {
        var actionIDs: [CanvasContextMenuActionID] = [.command(.selectItem)]
        if includeCropCommand {
            actionIDs.append(.command(.crop))
        }
        if includeBeginTextEditCommand {
            actionIDs.append(.command(.beginTextEdit))
        }
        if includeHandDrawingEditAction {
            actionIDs.append(.uiAction(.editHandDrawing))
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

    private func operatesOnCurrentSelection(
        in context: CanvasContextMenuContext
    ) -> Bool {
        context.operatesOnCurrentSelection
    }

    private func targetVideoItemID(
        in context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        guard
            let itemID = context.singleEffectiveItemID,
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
            let itemID = context.singleEffectiveItemID,
            let item = session.scene.item(withID: itemID),
            item.isVideo == false,
            item.assetKind == .animatedGIF
        else {
            return nil
        }

        return itemID
    }

    private func targetHandDrawingItemID(
        in context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        guard let itemID = context.singleEffectiveItemID else {
            return nil
        }

        return session.canEditHandDrawing(withID: itemID)
            ? itemID
            : nil
    }
}

private func describeContextMenuActionIDs(
    _ actionIDs: [CanvasContextMenuActionID]
) -> String {
    actionIDs.map(\.rawValueDescription).joined(separator: ",")
}

private func logContextMenuInteractionDecision(
    intent: CanvasInteractionIntent,
    decision: CanvasInteractionDecision,
    environment: CanvasInteractionEnvironment,
    context: CanvasContextMenuContext,
    candidateActionIDs: [CanvasContextMenuActionID],
    enabledActionIDs: [CanvasContextMenuActionID],
    disabledActionIDs: [CanvasContextMenuActionID]
) {
    print(
        "[Canvas Shared][InteractionGate] " +
        "source=\"contextMenuResolver\" " +
        "intent=\(intent.debugName) " +
        "decision=\(decision.debugName) " +
        "reason=\(decision.blockReason?.debugName ?? "none") " +
        "feedback=\(decision.feedbackHint?.debugName ?? "none") " +
        "workspaceMode=\(environment.workspaceMode.rawValue) " +
        "frozen=\(environment.isTransitionInteractionFrozen) " +
        context.debugSummary + " " +
        "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
        "enabledIDs=[\(describeContextMenuActionIDs(enabledActionIDs))] " +
        "disabledIDs=[\(describeContextMenuActionIDs(disabledActionIDs))]"
    )
}
