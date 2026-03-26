import Foundation

enum CanvasWorkspaceMode: String, CaseIterable, Codable, Sendable {
    case editing
    case reading

    var systemImageName: String {
        switch self {
        case .editing:
            return "pencil"
        case .reading:
            return "book.closed"
        }
    }

    var displayName: String {
        switch self {
        case .editing:
            return "Editing"
        case .reading:
            return "Reading"
        }
    }

    var accessibilityLabel: String {
        "Canvas mode"
    }

    var accessibilityValue: String {
        displayName
    }

    var toggled: CanvasWorkspaceMode {
        switch self {
        case .editing:
            return .reading
        case .reading:
            return .editing
        }
    }
}
