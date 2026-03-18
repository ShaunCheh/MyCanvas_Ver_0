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

    enum BookmarkStatus {
        case missing
        case resolved(ResolvedFolderBookmark)
        case unresolved

        var hasSelectedFolder: Bool {
            if case .resolved = self {
                return true
            }

            return false
        }
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

    static func bookmarkStatus(userDefaults: UserDefaults = .standard) -> BookmarkStatus {
        do {
            return .resolved(try resolveStoredFolderBookmark(userDefaults: userDefaults))
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return .missing
        } catch {
            print("[FolderBookmark] Failed to resolve bookmark status: \(error)")
            return .unresolved
        }
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
