import Foundation

// Shared raw-input sources describe logical capture origin, not platform-local
// delivery details such as responder chain or monitor type.
enum CanvasRawInputSource: String, Equatable, Sendable {
    case keyboard
    case pointer
    case touch

    var debugName: String {
        rawValue
    }
}

enum CanvasKeyModifier: String, CaseIterable, Sendable {
    case command
    case shift
    case option
    case control
    case globe

    fileprivate static let debugOrder: [CanvasKeyModifier] = [
        .command,
        .shift,
        .option,
        .control,
        .globe
    ]

    var debugName: String {
        rawValue
    }
}

enum CanvasNamedKey: String, Equatable, Sendable {
    case returnKey
    case escape
    case delete
    case forwardDelete
    case tab
    case space
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow

    var debugName: String {
        rawValue
    }
}

enum CanvasKey: Equatable, Sendable {
    case character(String)
    case named(CanvasNamedKey)

    fileprivate var normalized: CanvasKey {
        switch self {
        case .character(let value):
            return .character(value.lowercased())
        case .named:
            return self
        }
    }

    var debugName: String {
        switch self {
        case .character(let value):
            return value.uppercased()
        case .named(let namedKey):
            return namedKey.debugName
        }
    }

    func matchesCharacter(_ value: String) -> Bool {
        guard case .character(let currentValue) = self else {
            return false
        }

        return currentValue.caseInsensitiveCompare(value) == .orderedSame
    }
}

// Shared key-chord naming stays upstream of command or transfer lowering.
struct CanvasKeyChord: Equatable, Sendable {
    let modifiers: Set<CanvasKeyModifier>
    let key: CanvasKey

    init(
        modifiers: Set<CanvasKeyModifier> = [],
        key: CanvasKey
    ) {
        self.modifiers = modifiers
        self.key = key.normalized
    }

    var debugName: String {
        let modifierComponents = CanvasKeyModifier.debugOrder
            .filter { modifiers.contains($0) }
            .map(\.debugName)
        let components = modifierComponents + [key.debugName]
        return components.joined(separator: "+")
    }
}

enum CanvasPointerButton: String, Equatable, Sendable {
    case primary
    case secondary

    var debugName: String {
        rawValue
    }
}

enum CanvasRawInputGesture: String, Equatable, Sendable {
    case tap
    case longPress
    case scroll
    case pinch
    case zoom

    var debugName: String {
        rawValue
    }
}

// Raw input facts are not business intents and must not be added to
// CanvasInteractionIntent.
enum CanvasRawInputIntent: Equatable, Sendable {
    case keyChord(CanvasKeyChord)
    case pointerClick(CanvasPointerButton)
    case gesture(
        CanvasRawInputGesture,
        source: CanvasRawInputSource
    )

    var source: CanvasRawInputSource {
        switch self {
        case .keyChord:
            return .keyboard
        case .pointerClick:
            return .pointer
        case .gesture(_, let source):
            return source
        }
    }

    var debugName: String {
        switch self {
        case .keyChord(let chord):
            return "keyChord.\(chord.debugName)"
        case .pointerClick(let button):
            return "pointerClick.\(button.debugName)"
        case .gesture(let gesture, let source):
            return "gesture.\(gesture.debugName).\(source.debugName)"
        }
    }
}
