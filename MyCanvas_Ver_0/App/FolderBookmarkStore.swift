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
        persist(bookmarkData, in: userDefaults)

        if let sharedUserDefaults = sharedUserDefaults(
            distinctFrom: userDefaults
        ) {
            persist(bookmarkData, in: sharedUserDefaults)
        }
    }

    static func storedBookmarkData(userDefaults: UserDefaults = .standard) -> Data? {
        if let bookmarkData = userDefaults.data(forKey: bookmarkDefaultsKey) {
            return bookmarkData
        }

        return fallbackBookmarkData(for: userDefaults)
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

    static func mirrorStoredBookmarkToSharedStoreIfNeeded(
        userDefaults: UserDefaults = .standard
    ) {
        guard
            let sharedUserDefaults = sharedUserDefaults(distinctFrom: userDefaults),
            sharedUserDefaults.data(forKey: bookmarkDefaultsKey) == nil,
            let bookmarkData = userDefaults.data(forKey: bookmarkDefaultsKey)
        else {
            return
        }

        persist(bookmarkData, in: sharedUserDefaults)
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
        let hasPrimaryBookmark = userDefaults.data(forKey: bookmarkDefaultsKey) != nil
        let hasSharedBookmark = MyCanvasSharedAppGroup.sharedUserDefaults?
            .data(forKey: bookmarkDefaultsKey) != nil
        print(
            "[FolderBookmark] " +
                "primaryHasBookmark=\(hasPrimaryBookmark) " +
                "sharedHasBookmark=\(hasSharedBookmark)"
        )
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static func persist(
        _ bookmarkData: Data,
        in userDefaults: UserDefaults
    ) {
        userDefaults.set(bookmarkData, forKey: bookmarkDefaultsKey)
    }

    private static func fallbackBookmarkData(
        for userDefaults: UserDefaults
    ) -> Data? {
        guard let sharedUserDefaults = sharedUserDefaults(distinctFrom: userDefaults) else {
            return nil
        }

        return sharedUserDefaults.data(forKey: bookmarkDefaultsKey)
    }

    private static func sharedUserDefaults(
        distinctFrom userDefaults: UserDefaults
    ) -> UserDefaults? {
        guard let sharedUserDefaults = MyCanvasSharedAppGroup.sharedUserDefaults else {
            return nil
        }

        guard sharedUserDefaults !== userDefaults else {
            return nil
        }

        return sharedUserDefaults
    }
}
