import Foundation

enum SelectedFolderAccess {
    static let workspaceDirectoryName = "MyCanvasData"
    static let boardsDirectoryName = "boards"

    static func withSelectedFolderURL<T>(
        userDefaults: UserDefaults = .standard,
        _ body: (URL) throws -> T
    ) throws -> T {
        let resolvedBookmark = try FolderBookmarkStore.resolveStoredFolderBookmark(
            userDefaults: userDefaults
        )
        let url = resolvedBookmark.url
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try body(url)
    }

    static func withWorkspaceURL<T>(
        userDefaults: UserDefaults = .standard,
        _ body: (URL) throws -> T
    ) throws -> T {
        try withSelectedFolderURL(userDefaults: userDefaults) { selectedFolderURL in
            let workspaceURL = selectedFolderURL.appendingPathComponent(
                workspaceDirectoryName,
                isDirectory: true
            )
            return try body(workspaceURL)
        }
    }

    static func withBoardsDirectoryURL<T>(
        userDefaults: UserDefaults = .standard,
        _ body: (URL) throws -> T
    ) throws -> T {
        try withWorkspaceURL(userDefaults: userDefaults) { workspaceURL in
            let boardsDirectoryURL = workspaceURL.appendingPathComponent(
                boardsDirectoryName,
                isDirectory: true
            )
            return try body(boardsDirectoryURL)
        }
    }
}
