import Foundation

struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        if environment.isTransitionInteractionFrozen {
            return .block(reason: .transitionInteractionFrozen, feedback: nil)
        }

        guard environment.workspaceMode == .reading else {
            return .allow
        }

        switch intent {
        case .transferEntry(let entry):
            return .block(reason: .readingMode, feedback: entry.readingModeFeedbackHint)
        case .command(let commandID):
            guard commandID.isAllowedInReadingMode == false else {
                return .allow
            }

            return .block(reason: .readingMode, feedback: nil)
        case .contextMenuRequest,
             .beginTextEdit:
            return .block(reason: .readingMode, feedback: nil)
        }
    }

    func commandDecision(
        for commandID: CanvasCommandID,
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionDecision {
        decision(
            for: .command(commandID),
            environment: .commandLane(workspaceMode: workspaceMode)
        )
    }
}

private extension CanvasTransferEntryIntent {
    var readingModeFeedbackHint: CanvasInteractionFeedbackHint? {
        switch self {
        case .pasteKeyboardShortcut:
            return .shakeWorkspaceModeButton
        case .pasteMenu,
             .importButton,
             .dragAndDrop:
            return nil
        }
    }
}
