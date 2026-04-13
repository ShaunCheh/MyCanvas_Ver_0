import Foundation

// Shared routing normalizes raw input facts before platform code decides how to
// execute or present downstream behavior.
struct CanvasInputRoutingResolver: Sendable {
    func route(_ rawInput: CanvasRawInputIntent) -> CanvasInputRoutingResult {
        switch rawInput {
        case .keyChord(let chord):
            return routeKeyChord(chord)
        case .pointerClick(let button):
            return routePointerClick(button)
        case .gesture(let gesture, _):
            return routeGesture(gesture)
        }
    }

    private func routeKeyChord(
        _ chord: CanvasKeyChord
    ) -> CanvasInputRoutingResult {
        return CanvasInputRoutingResult(
            indicatorEvent: .keyChord(chord),
            interactionIntent: chord.routedInteractionIntent
        )
    }

    private func routePointerClick(
        _ button: CanvasPointerButton
    ) -> CanvasInputRoutingResult {
        CanvasInputRoutingResult(
            indicatorEvent: .action(button.indicatorAction),
            interactionIntent: button.routedInteractionIntent
        )
    }

    private func routeGesture(
        _ gesture: CanvasRawInputGesture
    ) -> CanvasInputRoutingResult {
        CanvasInputRoutingResult(
            indicatorEvent: .action(gesture.indicatorAction),
            interactionIntent: gesture.routedInteractionIntent
        )
    }
}

private extension CanvasKeyChord {
    var routedInteractionIntent: CanvasInteractionIntent? {
        if isPasteKeyboardShortcut {
            return .transferEntry(.pasteKeyboardShortcut)
        }

        if isUndoKeyboardShortcut {
            return .command(.undo)
        }

        if isRedoKeyboardShortcut {
            return .command(.redo)
        }

        return nil
    }

    var isPasteKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("v")
    }

    var isUndoKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("z")
    }

    var isRedoKeyboardShortcut: Bool {
        modifiers == [.command, .shift] && key.matchesCharacter("z")
    }
}

private extension CanvasPointerButton {
    var indicatorAction: CanvasInputIndicatorAction {
        switch self {
        case .primary:
            return .leftClick
        case .secondary:
            return .rightClick
        }
    }

    var routedInteractionIntent: CanvasInteractionIntent? {
        switch self {
        case .primary:
            return nil
        case .secondary:
            return .contextMenuRequest
        }
    }
}

private extension CanvasRawInputGesture {
    var indicatorAction: CanvasInputIndicatorAction {
        switch self {
        case .tap:
            return .tap
        case .longPress:
            return .longPress
        case .scroll:
            return .scroll
        case .pinch:
            return .pinch
        case .zoom:
            return .zoom
        }
    }

    var routedInteractionIntent: CanvasInteractionIntent? {
        switch self {
        case .longPress:
            return .contextMenuRequest
        case .tap,
             .scroll,
             .pinch,
             .zoom:
            return nil
        }
    }
}
