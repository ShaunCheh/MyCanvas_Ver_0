import Foundation

enum FolderBookmarkStoreError: LocalizedError {
    case missingBookmarkData

    var errorDescription: String? {
        switch self {
        case .missingBookmarkData:
            return "No folder bookmark has been saved yet."
        }
    }
}

enum FolderBookmarkStore {
    struct ResolvedFolderBookmark {
        let url: URL
        let isStale: Bool
    }

    private static let bookmarkDefaultsKey = "SelectedFolderBookmarkData"

    static func save(_ bookmarkData: Data, userDefaults: UserDefaults = .standard) {
        userDefaults.set(bookmarkData, forKey: bookmarkDefaultsKey)
    }

    static func storedBookmarkData(userDefaults: UserDefaults = .standard) -> Data? {
        userDefaults.data(forKey: bookmarkDefaultsKey)
    }

    static func hasStoredBookmarkData(userDefaults: UserDefaults = .standard) -> Bool {
        storedBookmarkData(userDefaults: userDefaults) != nil
    }

    static func resolveStoredFolderBookmark(
        userDefaults: UserDefaults = .standard
    ) throws -> ResolvedFolderBookmark {
        guard let bookmarkData = storedBookmarkData(userDefaults: userDefaults) else {
            throw FolderBookmarkStoreError.missingBookmarkData
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            print("[FolderBookmark] Resolved bookmark is stale.")
        }
        return ResolvedFolderBookmark(url: url, isStale: isStale)
    }

    static func storedFolderPath(userDefaults: UserDefaults = .standard) -> String? {
        do {
            return try resolveStoredFolderBookmark(userDefaults: userDefaults).url.path
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return nil
        } catch {
            print("[FolderBookmark] Failed to resolve bookmark path: \(error)")
            return nil
        }
    }

    static func statusText(userDefaults: UserDefaults = .standard) -> String {
        if let path = storedFolderPath(userDefaults: userDefaults) {
            return "Saved folder path:\n\(path)"
        }

        if hasStoredBookmarkData(userDefaults: userDefaults) {
            return "Bookmark data exists in UserDefaults, but the path could not be resolved."
        }

        return "No bookmark data stored in UserDefaults."
    }

    static func logStoredBookmarkPresence(userDefaults: UserDefaults = .standard) {
        print("[FolderBookmark] UserDefaults has bookmark data: \(hasStoredBookmarkData(userDefaults: userDefaults))")
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}
