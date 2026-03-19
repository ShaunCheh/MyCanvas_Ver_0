import Foundation

enum BoardListCopy {
    static let subtitle = "Select a storage folder to browse or create boards."
    static let selectFolderMessage = "Select a storage folder to browse or create boards."

    static func storageUnavailableMessage(_ description: String) -> String {
        "Storage unavailable: \(description)"
    }
}
