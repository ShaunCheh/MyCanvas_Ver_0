import Foundation

enum CanvasInputIndicatorAction: String, Equatable, Sendable {
    case leftClick
    case rightClick
    case tap
    case longPress
    case scroll
    case pinch
    case zoom

    var debugName: String {
        rawValue
    }
}

// Indicator events stay presentation-only even when they mirror a raw input
// fact that also lowers into a business interaction intent.
enum CanvasInputIndicatorEvent: Equatable, Sendable {
    case keyChord(CanvasKeyChord)
    case action(CanvasInputIndicatorAction)

    var debugName: String {
        switch self {
        case .keyChord(let chord):
            return "keyChord.\(chord.debugName)"
        case .action(let action):
            return "action.\(action.debugName)"
        }
    }
}
