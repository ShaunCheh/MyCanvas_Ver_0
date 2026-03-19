import Foundation

enum CanvasSaveState: String, Sendable {
    case idle
    case saving
    case success
    case missingFolder
    case failure

    var systemImageName: String {
        switch self {
        case .idle, .saving:
            return "square.and.arrow.down"
        case .success:
            return "checkmark"
        case .missingFolder:
            return "exclamationmark.triangle"
        case .failure:
            return "xmark"
        }
    }

    var isEnabled: Bool {
        self != .saving
    }

    var accessibilityValue: String? {
        switch self {
        case .idle:
            return nil
        case .saving:
            return "Saving"
        case .success:
            return "Saved"
        case .missingFolder:
            return "No folder selected"
        case .failure:
            return "Save failed"
        }
    }

    var visualRole: CanvasToolbarItemVisualRole {
        switch self {
        case .idle, .saving:
            return .accent
        case .success:
            return .success
        case .missingFolder:
            return .warning
        case .failure:
            return .danger
        }
    }
}
