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
        try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
            BoardCatalogItem(
                document: entry.document,
                previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
            )
        }
    }
}
