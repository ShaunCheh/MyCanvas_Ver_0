import Foundation

struct BoardCatalogLoader {
    private let userDefaults: UserDefaults
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder

    init(
        userDefaults: UserDefaults = .standard,
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder()
    ) {
        self.userDefaults = userDefaults
        self.geometryPreviewBuilder = geometryPreviewBuilder
    }

    func loadCatalog() throws -> [BoardCatalogItem] {
        try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map {
            makeCatalogItem(from: $0)
        }
    }

    func loadCatalogItem(
        boardID: UUID
    ) throws -> BoardCatalogItem? {
        guard
            let entry = try BoardStore.loadBoardDocumentEntry(
                id: boardID,
                userDefaults: userDefaults
            )
        else {
            return nil
        }

        return makeCatalogItem(from: entry)
    }

    private func makeCatalogItem(
        from entry: BoardDocumentCatalogEntry
    ) -> BoardCatalogItem {
        BoardCatalogItem(
            document: entry.document,
            persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: entry.boardDirectoryURL
            ),
            assetsDirectoryURL: entry.assetsDirectoryURL,
            storageSizeSummary: entry.storageSizeSummary,
            previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
        )
    }
}
