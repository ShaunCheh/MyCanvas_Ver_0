import Foundation

enum MyCanvasSharedAppGroupError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The shared MyCanvas app group is unavailable."
        }
    }
}

enum MyCanvasSharedAppGroup {
    static let identifier = "group.shaunyu.MyCanvas-Ver-0.shared"

    static var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static func requireSharedUserDefaults() throws -> UserDefaults {
        guard let sharedUserDefaults else {
            throw MyCanvasSharedAppGroupError.unavailable
        }

        return sharedUserDefaults
    }
}
