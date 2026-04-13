import Foundation

struct CanvasInputIndicatorFormatter {
    func text(for event: CanvasInputIndicatorEvent) -> String {
        switch event {
        case .keyChord(let chord):
            return formattedText(for: chord)
        case .action(let action):
            return action.displayText
        }
    }

    private func formattedText(for chord: CanvasKeyChord) -> String {
        let modifierComponents = CanvasKeyModifier.displayOrder
            .filter { chord.modifiers.contains($0) }
            .map(\.displayText)
        let components = modifierComponents + [chord.key.displayText]
        return components.joined(separator: " + ")
    }
}

private extension CanvasKeyModifier {
    static let displayOrder: [CanvasKeyModifier] = [
        .command,
        .shift,
        .option,
        .control,
        .globe
    ]

    var displayText: String {
        switch self {
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .globe:
            return "Globe"
        }
    }
}

private extension CanvasNamedKey {
    var displayText: String {
        switch self {
        case .returnKey:
            return "Return"
        case .escape:
            return "Escape"
        case .delete:
            return "Delete"
        case .forwardDelete:
            return "Forward Delete"
        case .tab:
            return "Tab"
        case .space:
            return "Space"
        case .upArrow:
            return "Up Arrow"
        case .downArrow:
            return "Down Arrow"
        case .leftArrow:
            return "Left Arrow"
        case .rightArrow:
            return "Right Arrow"
        }
    }
}

private extension CanvasKey {
    var displayText: String {
        switch self {
        case .character(let value):
            return value.uppercased()
        case .named(let namedKey):
            return namedKey.displayText
        }
    }
}

private extension CanvasInputIndicatorAction {
    var displayText: String {
        switch self {
        case .leftClick:
            return "Left Click"
        case .rightClick:
            return "Right Click"
        case .tap:
            return "Tap"
        case .longPress:
            return "Long Press"
        case .scroll:
            return "Scroll"
        case .pinch:
            return "Pinch"
        case .zoom:
            return "Zoom"
        }
    }
}
