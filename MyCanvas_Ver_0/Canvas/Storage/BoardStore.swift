import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument

    var summary: BoardSummary {
        document.summary
    }
}

enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case missingBoardVideoAsset(filename: String)
    case failedToEncodeImageAsset(itemID: UUID)
    case missingAnimatedImageSource(itemID: UUID)

    var errorDescription: String? {
        switch self {
        case .invalidBoardDirectory:
            return "The board directory is invalid."
        case let .invalidBoardImageAsset(filename):
            return "The board image asset could not be decoded: \(filename)"
        case let .missingBoardVideoAsset(filename):
            return "The board video asset is missing: \(filename)"
        case let .failedToEncodeImageAsset(itemID):
            return "The image asset could not be encoded for board item \(itemID.uuidString)."
        case let .missingAnimatedImageSource(itemID):
            return "The original animated image data is unavailable for board item \(itemID.uuidString)."
        }
    }
}

enum BoardStore {
    private static let boardDocumentFilename = "board.json"
    private static let assetsDirectoryName = "assets"
    private static let thumbnailRenderer = BoardThumbnailRenderer()

    static func listBoards(
        userDefaults: UserDefaults = .standard
    ) throws -> [BoardSummary] {
        try listBoardDocumentEntries(userDefaults: userDefaults).map(\.summary)
    }

    static func loadBoard(
        id: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> BoardRuntimeState {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            let boardDirectoryURL = self.boardDirectoryURL(
                for: id,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
            let document = try readBoardDocument(at: boardDocumentURL)
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            )

            try validateReferencedVideoAssets(
                for: document.imageItemRecords,
                in: assetsDirectoryURL
            )
            let runtimeState = try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
                let assetURL = assetsDirectoryURL.appendingPathComponent(imageRecord.assetFilename)
                let assetData = try CoordinatedFileIO.readData(at: assetURL)
                guard
                    let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil),
                    let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                else {
                    throw BoardStoreError.invalidBoardImageAsset(filename: imageRecord.assetFilename)
                }
                return cgImage
            }
            print(
                "[BoardStore] " +
                "action=loadBoard " +
                "boardID=\(id.uuidString) " +
                "items=\(runtimeState.items.count) " +
                "cameraCenter=\(describeBoardStorePoint(runtimeState.camera.center)) " +
                "cameraZoomScale=\(formatBoardStoreValue(runtimeState.camera.zoomScale)) " +
                "cameraViewportSize=\(describeBoardStoreSize(runtimeState.camera.viewportSize)) " +
                "selectedItemID=\(describeBoardStoreItemID(runtimeState.interactionState.selectedItemID))"
            )
            return runtimeState
        }
    }

    static func loadImageAssetData(
        boardID: UUID,
        filename: String,
        userDefaults: UserDefaults = .standard
    ) throws -> Data {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            let boardDirectoryURL = self.boardDirectoryURL(
                for: boardID,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            )
            let assetURL = assetsDirectoryURL.appendingPathComponent(filename)
            return try CoordinatedFileIO.readData(at: assetURL)
        }
    }

    static func ensureAssetsDirectoryURL(
        for boardID: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> URL {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
            let boardDirectoryURL = self.boardDirectoryURL(
                for: boardID,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            )
            try CoordinatedFileIO.ensureDirectory(at: boardDirectoryURL)
            try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)
            return assetsDirectoryURL
        }
    }

    static func saveBoard(
        _ snapshot: BoardSaveSnapshot,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)

            let boardDirectoryURL = self.boardDirectoryURL(
                for: snapshot.runtimeState.boardID,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            )
            try CoordinatedFileIO.ensureDirectory(at: boardDirectoryURL)
            try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)

            var persistedState = snapshot.runtimeState
            persistedState.updatedAt = Date()
            let persistedSnapshot = BoardSaveSnapshot(
                runtimeState: persistedState,
                transientImageAssetPayloads: snapshot.transientImageAssetPayloads
            )
            let document = BoardDocumentMapper.makeDocument(from: persistedState)

            var writtenPosterAssetFilenames: Set<String> = []
            var validatedVideoAssetFilenames: Set<String> = []
            for item in persistedState.imageItems {
                let posterAssetFilename = item.assetReference.stableAssetFilename
                if writtenPosterAssetFilenames.insert(posterAssetFilename).inserted {
                    let assetURL = assetsDirectoryURL.appendingPathComponent(
                        posterAssetFilename
                    )
                    try persistImageAssetIfNeeded(
                        for: item,
                        snapshot: persistedSnapshot,
                        to: assetURL
                    )
                }

                if let sourceVideoFilename = item.sourceVideoFilename,
                   validatedVideoAssetFilenames.insert(sourceVideoFilename).inserted
                {
                    let videoAssetURL = assetsDirectoryURL.appendingPathComponent(
                        sourceVideoFilename
                    )
                    try validateVideoAssetExists(
                        at: videoAssetURL,
                        filename: sourceVideoFilename
                    )
                }
            }

            try removeOrphanedAssets(
                keeping: document.referencedAssetFilenames,
                in: assetsDirectoryURL
            )

            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
            persistBoardThumbnailIfPossible(
                from: persistedState,
                boardDirectoryURL: boardDirectoryURL
            )
        }
    }

    static func saveBoard(
        _ runtimeState: BoardRuntimeState,
        userDefaults: UserDefaults = .standard
    ) throws {
        try saveBoard(
            BoardSaveSnapshot(runtimeState: runtimeState),
            userDefaults: userDefaults
        )
    }

    static func renameBoard(
        id: UUID,
        title: String,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)

            let boardDirectoryURL = self.boardDirectoryURL(
                for: id,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
            var document = try readBoardDocument(at: boardDocumentURL)
            let normalizedTitle = normalizedBoardTitle(title)
            document.title = normalizedTitle
            document.updatedAt = Date()

            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
            print(
                "[BoardStore] " +
                "action=renameBoard " +
                "boardID=\(id.uuidString) " +
                "title=\"\(normalizedTitle)\""
            )
        }
    }

    static func deleteBoard(
        id: UUID,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            let boardDirectoryURL = self.boardDirectoryURL(
                for: id,
                boardsDirectoryURL: boardsDirectoryURL
            )
            try CoordinatedFileIO.removeItemIfExists(at: boardDirectoryURL)
        }
    }

    static func loadOrCreateInitialBoard(
        userDefaults: UserDefaults = .standard
    ) throws -> BoardRuntimeState {
        let existingBoards = try listBoards(userDefaults: userDefaults)
        if let firstBoard = existingBoards.first {
            let runtimeState = try loadBoard(id: firstBoard.boardID, userDefaults: userDefaults)
            print(
                "[BoardStore] " +
                "action=loadOrCreateInitialBoard " +
                "source=existing " +
                "boardID=\(firstBoard.boardID.uuidString) " +
                "existingBoardCount=\(existingBoards.count) " +
                "cameraViewportSize=\(describeBoardStoreSize(runtimeState.camera.viewportSize))"
            )
            return runtimeState
        }

        let runtimeState = BoardRuntimeState.makeEmpty()
        try saveBoard(runtimeState, userDefaults: userDefaults)
        print(
            "[BoardStore] " +
            "action=loadOrCreateInitialBoard " +
            "source=createdEmpty " +
            "boardID=\(runtimeState.boardID.uuidString) " +
            "existingBoardCount=0 " +
            "cameraViewportSize=\(describeBoardStoreSize(runtimeState.camera.viewportSize))"
        )
        return runtimeState
    }

    static func listBoardDocumentEntries(
        userDefaults: UserDefaults = .standard
    ) throws -> [BoardDocumentCatalogEntry] {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
            let candidateURLs = try CoordinatedFileIO.contentsOfDirectory(
                at: boardsDirectoryURL
            )

            var entries: [BoardDocumentCatalogEntry] = []
            for candidateURL in candidateURLs {
                if let entry = try makeBoardDocumentCatalogEntry(
                    at: candidateURL
                ) {
                    entries.append(entry)
                }
            }

            return entries.sorted { lhs, rhs in
                if lhs.document.updatedAt == rhs.document.updatedAt {
                    return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
                }

                return lhs.document.updatedAt > rhs.document.updatedAt
            }
        }
    }

    static func loadBoardDocumentEntry(
        id: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> BoardDocumentCatalogEntry? {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
            return try makeBoardDocumentCatalogEntry(
                at: boardDirectoryURL(
                    for: id,
                    boardsDirectoryURL: boardsDirectoryURL
                )
            )
        }
    }

    private static func boardDirectoryURL(
        for id: UUID,
        boardsDirectoryURL: URL
    ) -> URL {
        boardsDirectoryURL.appendingPathComponent(
            id.uuidString,
            isDirectory: true
        )
    }

    private static func readBoardDocument(
        at url: URL
    ) throws -> BoardDocument {
        let data = try CoordinatedFileIO.readData(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BoardDocument.self, from: data)
    }

    private static func makeBoardDocumentCatalogEntry(
        at boardDirectoryURL: URL
    ) throws -> BoardDocumentCatalogEntry? {
        guard FileManager.default.fileExists(atPath: boardDirectoryURL.path) else {
            return nil
        }

        guard try isDirectory(boardDirectoryURL) else {
            return nil
        }

        let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
            boardDocumentFilename
        )
        guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
            return nil
        }

        let document = try readBoardDocument(at: boardDocumentURL)
        return BoardDocumentCatalogEntry(
            boardDirectoryURL: boardDirectoryURL,
            documentURL: boardDocumentURL,
            assetsDirectoryURL: boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            ),
            document: document
        )
    }

    private static func makeDocumentData(
        for document: BoardDocument
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private static func makePNGData(
        for image: CGImage,
        itemID: UUID
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard
            let imageDestination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw BoardStoreError.failedToEncodeImageAsset(itemID: itemID)
        }

        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw BoardStoreError.failedToEncodeImageAsset(itemID: itemID)
        }

        return mutableData as Data
    }

    private static func persistImageAssetIfNeeded(
        for item: CanvasImageItem,
        snapshot: BoardSaveSnapshot,
        to assetURL: URL
    ) throws {
        if FileManager.default.fileExists(atPath: assetURL.path) {
            return
        }

        switch item.assetKind {
        case .staticImage:
            let pngData = try makePNGData(
                for: item.posterCGImage,
                itemID: item.id
            )
            try CoordinatedFileIO.writeData(pngData, to: assetURL)
        case .animatedGIF:
            guard
                let assetData = snapshot.transientImageAssetPayload(
                    for: item.assetReference
                )?.source?.data
            else {
                throw BoardStoreError.missingAnimatedImageSource(itemID: item.id)
            }
            try CoordinatedFileIO.writeData(assetData, to: assetURL)
        }
    }

    private static func validateReferencedVideoAssets(
        for imageRecords: [BoardImageItemRecord],
        in assetsDirectoryURL: URL
    ) throws {
        var validatedFilenames: Set<String> = []
        for imageRecord in imageRecords {
            guard let sourceVideoFilename = imageRecord.sourceVideoFilename else {
                continue
            }

            guard validatedFilenames.insert(sourceVideoFilename).inserted else {
                continue
            }

            let videoAssetURL = assetsDirectoryURL.appendingPathComponent(
                sourceVideoFilename
            )
            try validateVideoAssetExists(
                at: videoAssetURL,
                filename: sourceVideoFilename
            )
        }
    }

    private static func validateVideoAssetExists(
        at assetURL: URL,
        filename: String
    ) throws {
        guard try CoordinatedFileIO.modificationDate(at: assetURL) != nil else {
            throw BoardStoreError.missingBoardVideoAsset(filename: filename)
        }
    }

    private static func removeOrphanedAssets(
        keeping assetFilenames: Set<String>,
        in assetsDirectoryURL: URL
    ) throws {
        let assetURLs = try CoordinatedFileIO.contentsOfDirectory(at: assetsDirectoryURL)
        for assetURL in assetURLs {
            if assetFilenames.contains(assetURL.lastPathComponent) {
                continue
            }

            try CoordinatedFileIO.removeItemIfExists(at: assetURL)
        }
    }

    private static func persistBoardThumbnailIfPossible(
        from runtimeState: BoardRuntimeState,
        boardDirectoryURL: URL
    ) {
        do {
            if let thumbnailImage = try thumbnailRenderer.renderPersistedThumbnail(
                for: runtimeState
            ) {
                try BoardPersistedThumbnailStore.writeThumbnail(
                    thumbnailImage,
                    to: boardDirectoryURL,
                    boardID: runtimeState.boardID
                )
            } else {
                try BoardPersistedThumbnailStore.removeThumbnail(
                    at: boardDirectoryURL
                )
            }
        } catch {
            print(
                "[BoardStore] Failed to persist thumbnail " +
                "boardID=\(runtimeState.boardID.uuidString) " +
                "error=\(error)"
            )
        }
    }

    private static func isDirectory(
        _ url: URL
    ) throws -> Bool {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues.isDirectory == true
    }

    private static func normalizedBoardTitle(_ title: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.isEmpty == false else {
            return BoardDocument.defaultTitle
        }

        return normalizedTitle
    }
}

private func describeBoardStorePoint(_ point: CGPoint) -> String {
    "{\(formatBoardStoreValue(point.x)), \(formatBoardStoreValue(point.y))}"
}

private func describeBoardStoreSize(_ size: CGSize) -> String {
    "{\(formatBoardStoreValue(size.width)), \(formatBoardStoreValue(size.height))}"
}

private func describeBoardStoreItemID(_ itemID: UUID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func formatBoardStoreValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
