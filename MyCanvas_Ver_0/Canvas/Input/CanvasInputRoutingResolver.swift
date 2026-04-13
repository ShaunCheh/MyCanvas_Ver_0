import Foundation

// Shared routing normalizes raw input facts before platform code decides how to
// execute or present downstream behavior.
struct CanvasInputRoutingResolver: Sendable {
    func route(_ rawInput: CanvasRawInputIntent) -> CanvasInputRoutingResult {
        switch rawInput {
        case .keyChord(let chord):
            return routeKeyChord(chord)
        case .pointerClick(let button):
            return CanvasInputRoutingResult(
                indicatorEvent: .action(button.indicatorAction)
            )
        case .gesture(let gesture, _):
            return CanvasInputRoutingResult(
                indicatorEvent: .action(gesture.indicatorAction)
            )
        }
    }

    private func routeKeyChord(
        _ chord: CanvasKeyChord
    ) -> CanvasInputRoutingResult {
        let interactionIntent: CanvasInteractionIntent?
        if chord.isPasteKeyboardShortcut {
            interactionIntent = .transferEntry(.pasteKeyboardShortcut)
        } else {
            interactionIntent = nil
        }

        return CanvasInputRoutingResult(
            indicatorEvent: .keyChord(chord),
            interactionIntent: interactionIntent
        )
    }
}

private extension CanvasKeyChord {
    var isPasteKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("v")
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
}
