import Foundation

struct BoardListHeaderState {
    let title: String
    let detail: String
    let fullPath: String?
    let isError: Bool
}

enum BoardListHeaderStateBuilder {
    static func make(
        bookmarkStatus: FolderBookmarkStore.BookmarkStatus,
        boardCount: Int? = nil,
        storageErrorDescription: String? = nil
    ) -> BoardListHeaderState {
        switch bookmarkStatus {
        case .missing:
            return BoardListHeaderState(
                title: "No Folder Selected",
                detail: BoardListCopy.selectFolderMessage,
                fullPath: nil,
                isError: false
            )

        case .unresolved:
            return BoardListHeaderState(
                title: "Folder Bookmark Unavailable",
                detail: storageErrorDescription
                    ?? "Bookmark exists, but the folder path could not be resolved.",
                fullPath: nil,
                isError: true
            )

        case let .resolved(resolvedBookmark):
            let folderPath = resolvedBookmark.url.path
            let folderName = resolvedBookmark.url.lastPathComponent.isEmpty
                ? folderPath
                : resolvedBookmark.url.lastPathComponent

            if let storageErrorDescription {
                return BoardListHeaderState(
                    title: "Folder: \(folderName)",
                    detail: "Storage error: \(storageErrorDescription)",
                    fullPath: folderPath,
                    isError: true
                )
            }

            var detailComponents: [String] = []
            if let boardCount {
                let boardText = boardCount == 1 ? "1 board" : "\(boardCount) boards"
                detailComponents.append(boardText)
            } else {
                detailComponents.append("Folder selected")
            }

            if resolvedBookmark.isStale {
                detailComponents.append("Bookmark stale")
            }

            return BoardListHeaderState(
                title: "Folder: \(folderName)",
                detail: detailComponents.joined(separator: " | "),
                fullPath: folderPath,
                isError: false
            )
        }
    }
}
