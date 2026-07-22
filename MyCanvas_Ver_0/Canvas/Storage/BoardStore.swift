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

struct BoardStorageSizeSummary: Hashable, Sendable {
    let byteCount: Int64?

    static let unavailable = BoardStorageSizeSummary(byteCount: nil)
    static let loadingDisplayText = "Size: Loading..."

    var displayText: String {
        guard let byteCount else {
            return "Size unavailable"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "Size: \(formatter.string(fromByteCount: byteCount))"
    }
}

enum BoardStoreError: LocalizedError {
    case invalidBoardDirectory
    case invalidBoardImageAsset(filename: String)
    case missingBoardVideoAsset(filename: String)
    case missingBoardHandDrawingSourceAsset(filename: String)
    case missingBoardHandDrawingItem(itemID: CanvasItemID)
    case failedToEncodeImageAsset(itemID: UUID)
    case missingAnimatedImageSource(itemID: UUID)
    case missingHandDrawingAssetPayload(itemID: UUID)

    var errorDescription: String? {
        switch self {
        case .invalidBoardDirectory:
            return "The board directory is invalid."
        case let .invalidBoardImageAsset(filename):
            return "The board image asset could not be decoded: \(filename)"
        case let .missingBoardVideoAsset(filename):
            return "The board video asset is missing: \(filename)"
        case let .missingBoardHandDrawingSourceAsset(filename):
            return "The board hand drawing source asset is missing: \(filename)"
        case let .missingBoardHandDrawingItem(itemID):
            return "The board hand drawing item is missing: \(itemID.uuidString)"
        case let .failedToEncodeImageAsset(itemID):
            return "The image asset could not be encoded for board item \(itemID.uuidString)."
        case let .missingAnimatedImageSource(itemID):
            return "The original animated image data is unavailable for board item \(itemID.uuidString)."
        case let .missingHandDrawingAssetPayload(itemID):
            return "The transient hand drawing asset payload is unavailable for board item \(itemID.uuidString)."
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
            try validateReferencedHandDrawingAssets(
                for: document.handDrawingItemRecords,
                boardDirectoryURL: boardDirectoryURL,
                assetsDirectoryURL: assetsDirectoryURL
            )
            let runtimeState = try BoardDocumentMapper.makeRuntimeState(
                from: document,
                imageLoader: { imageRecord in
                    let assetURL = assetsDirectoryURL.appendingPathComponent(
                        imageRecord.assetFilename
                    )
                    return try loadBoardImageAsset(
                        at: assetURL,
                        filename: imageRecord.assetFilename
                    )
                },
                handDrawingPreviewLoader: { handDrawingRecord in
                    try loadHandDrawingPreviewImage(
                        for: handDrawingRecord,
                        boardDirectoryURL: boardDirectoryURL,
                        assetsDirectoryURL: assetsDirectoryURL
                    )
                }
            )
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

    static func loadHandDrawingDocumentData(
        boardID: UUID,
        documentID: HandDrawingDocumentID,
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
            if HandDrawingDocumentStore.bundleExists(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            ) {
                return try HandDrawingDocumentStore.loadNormalizedDocumentData(
                    documentID: documentID,
                    boardDirectoryURL: boardDirectoryURL
                )
            }

            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
                boardDocumentFilename
            )
            let boardDocument = try readBoardDocument(at: boardDocumentURL)
            let sourceURL = BoardHandDrawingAssetLocator(documentID: documentID)
                .sourceDrawingURL(in: assetsDirectoryURL)
            let sourceData = try CoordinatedFileIO.readData(at: sourceURL)
            guard
                let record = boardDocument.handDrawingItemRecords.first(where: {
                    $0.documentID == documentID
                })
            else {
                return sourceData
            }
            return try HandDrawingDocumentLoader.normalizeDocumentData(
                from: sourceData,
                paper: record.paper.canvasPaperSpec
            )
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

            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
                boardDocumentFilename
            )
            let existingDocument: BoardDocument?
            if FileManager.default.fileExists(atPath: boardDocumentURL.path) {
                existingDocument = try readBoardDocument(at: boardDocumentURL)
            } else {
                existingDocument = nil
            }

            var document = BoardDocumentMapper.makeDocument(from: snapshot.runtimeState)
            if let existingDocument {
                if snapshot.updateKind.affectsContent == false {
                    document.replaceContentState(with: existingDocument)
                }
                if snapshot.updateKind.affectsViewState == false {
                    document.replaceViewState(with: existingDocument)
                }
            }
            if snapshot.updateKind.affectsContent {
                normalizePersistedHandDrawingStorage(
                    in: &document,
                    existingDocument: existingDocument
                )
            }

            let now = Date()
            let contentChanged = existingDocument.map {
                document.contentState != $0.contentState
            } ?? true
            let viewStateChanged = existingDocument.map {
                document.viewState != $0.viewState
            } ?? true
            document.contentUpdatedAt = existingDocument.map {
                contentChanged ? now : $0.contentUpdatedAt
            } ?? now
            document.viewStateUpdatedAt = existingDocument.map {
                viewStateChanged ? now : $0.viewStateUpdatedAt
            } ?? now

            var persistedState = snapshot.runtimeState
            persistedState.contentUpdatedAt = document.contentUpdatedAt
            persistedState.viewStateUpdatedAt = document.viewStateUpdatedAt
            let persistedSnapshot = BoardSaveSnapshot(
                runtimeState: persistedState,
                transientImageAssetPayloads: snapshot.transientImageAssetPayloads,
                transientHandDrawingAssetPayloads: snapshot.transientHandDrawingAssetPayloads,
                updateKind: snapshot.updateKind
            )

            if contentChanged {
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

                let handDrawingRecordByID = Dictionary(
                    uniqueKeysWithValues: document.handDrawingItemRecords.map { ($0.id, $0) }
                )
                for item in persistedState.handDrawingItems {
                    guard let handDrawingRecord = handDrawingRecordByID[item.id] else {
                        continue
                    }
                    try persistHandDrawingAssetsIfNeeded(
                        for: item,
                        record: handDrawingRecord,
                        snapshot: persistedSnapshot,
                        boardDirectoryURL: boardDirectoryURL,
                        in: assetsDirectoryURL
                    )
                }

                try removeOrphanedAssets(
                    keeping: document.referencedAssetFilenames,
                    in: assetsDirectoryURL
                )
                try HandDrawingDocumentStore.removeOrphanedBundles(
                    keeping: document.referencedHandDrawingDocumentIDs,
                    boardDirectoryURL: boardDirectoryURL
                )
            }

            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
            if contentChanged {
                persistBoardThumbnailIfPossible(
                    from: persistedState,
                    boardDirectoryURL: boardDirectoryURL
                )
            }
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
            document.contentUpdatedAt = Date()

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
                if lhs.document.contentUpdatedAt == rhs.document.contentUpdatedAt {
                    return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
                }

                return lhs.document.contentUpdatedAt > rhs.document.contentUpdatedAt
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

    static func loadBoardStorageSizeSummary(
        id: UUID,
        userDefaults: UserDefaults = .standard
    ) throws -> BoardStorageSizeSummary {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            let boardDirectoryURL = self.boardDirectoryURL(
                for: id,
                boardsDirectoryURL: boardsDirectoryURL
            )
            guard FileManager.default.fileExists(atPath: boardDirectoryURL.path),
                  try isDirectory(boardDirectoryURL)
            else {
                throw BoardStoreError.invalidBoardDirectory
            }

            return BoardStorageSizeSummary(
                byteCount: try boardDirectoryStorageByteCount(at: boardDirectoryURL)
            )
        }
    }

    static func updateHandDrawingStorage(
        boardID: UUID,
        itemID: CanvasItemID,
        storage: BoardHandDrawingStorageRecord,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            let boardDirectoryURL = self.boardDirectoryURL(
                for: boardID,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
                boardDocumentFilename
            )
            var document = try readBoardDocument(at: boardDocumentURL)
            var didUpdateRecord = false
            document.items = document.items.map { itemRecord in
                guard case let .handDrawing(record) = itemRecord else {
                    return itemRecord
                }
                guard record.id == itemID else {
                    return itemRecord
                }

                didUpdateRecord = true
                guard record.storage != storage else {
                    return itemRecord
                }
                return .handDrawing(record.replacingStorage(with: storage))
            }
            guard didUpdateRecord else {
                throw BoardStoreError.missingBoardHandDrawingItem(itemID: itemID)
            }

            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
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

    private static func boardDirectoryStorageByteCount(
        at boardDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: boardDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var byteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isRegularFile == true else {
                continue
            }

            byteCount += Int64(max(resourceValues.fileSize ?? 0, 0))
        }

        return byteCount
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

    private static func loadBoardImageAsset(
        at assetURL: URL,
        filename: String
    ) throws -> CGImage {
        let assetData = try CoordinatedFileIO.readData(at: assetURL)
        guard
            let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw BoardStoreError.invalidBoardImageAsset(filename: filename)
        }
        return cgImage
    }

    private static func loadHandDrawingPreviewImage(
        for record: BoardHandDrawingItemRecord,
        boardDirectoryURL: URL,
        assetsDirectoryURL: URL
    ) throws -> CGImage {
        switch record.storage {
        case .legacyFlatAssetPair:
            return try loadBoardImageAsset(
                at: record.legacyAssetLocator.previewImageURL(in: assetsDirectoryURL),
                filename: record.previewImageFilename
            )
        case .bundle:
            return try HandDrawingDocumentStore.loadPreviewImage(
                documentID: record.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
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

    private static func validateReferencedHandDrawingAssets(
        for handDrawingRecords: [BoardHandDrawingItemRecord],
        boardDirectoryURL: URL,
        assetsDirectoryURL: URL
    ) throws {
        for handDrawingRecord in handDrawingRecords {
            switch handDrawingRecord.storage {
            case .legacyFlatAssetPair:
                try validateHandDrawingSourceAssetExists(
                    at: handDrawingRecord.legacyAssetLocator.sourceDrawingURL(
                        in: assetsDirectoryURL
                    ),
                    filename: handDrawingRecord.sourceDrawingFilename
                )
            case .bundle:
                try HandDrawingDocumentStore.validateBundleExists(
                    documentID: handDrawingRecord.documentID,
                    boardDirectoryURL: boardDirectoryURL
                )
            }
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

    private static func validateHandDrawingSourceAssetExists(
        at assetURL: URL,
        filename: String
    ) throws {
        guard try CoordinatedFileIO.modificationDate(at: assetURL) != nil else {
            throw BoardStoreError.missingBoardHandDrawingSourceAsset(
                filename: filename
            )
        }
    }

    private static func persistHandDrawingAssetsIfNeeded(
        for item: CanvasHandDrawingItem,
        record: BoardHandDrawingItemRecord,
        snapshot: BoardSaveSnapshot,
        boardDirectoryURL: URL,
        in assetsDirectoryURL: URL
    ) throws {
        switch record.storage {
        case .legacyFlatAssetPair:
            try persistLegacyHandDrawingAssetsIfNeeded(
                for: item,
                snapshot: snapshot,
                in: assetsDirectoryURL
            )
        case .bundle:
            try persistBundleHandDrawingDocumentIfNeeded(
                for: item,
                snapshot: snapshot,
                boardDirectoryURL: boardDirectoryURL
            )
        }
    }

    private static func persistLegacyHandDrawingAssetsIfNeeded(
        for item: CanvasHandDrawingItem,
        snapshot: BoardSaveSnapshot,
        in assetsDirectoryURL: URL
    ) throws {
        let assetLocator = BoardHandDrawingAssetLocator(documentID: item.documentID)
        let previewImageURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
        let sourceDrawingURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)

        if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
            try CoordinatedFileIO.writeData(payload.documentData, to: sourceDrawingURL)
            let previewImageData: Data
            if let encodedPreviewImageData = payload.previewImageData {
                previewImageData = encodedPreviewImageData
            } else if let previewCGImage = payload.previewCGImage {
                previewImageData = try makePNGData(
                    for: previewCGImage,
                    itemID: item.id
                )
            } else {
                throw BoardStoreError.missingHandDrawingAssetPayload(itemID: item.id)
            }
            try CoordinatedFileIO.writeData(previewImageData, to: previewImageURL)
            return
        }

        guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
            throw BoardStoreError.missingHandDrawingAssetPayload(itemID: item.id)
        }
        try validateHandDrawingSourceAssetExists(
            at: sourceDrawingURL,
            filename: assetLocator.sourceDrawingFilename
        )
    }

    private static func persistBundleHandDrawingDocumentIfNeeded(
        for item: CanvasHandDrawingItem,
        snapshot: BoardSaveSnapshot,
        boardDirectoryURL: URL
    ) throws {
        if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
            try HandDrawingDocumentStore.persistDocument(
                documentID: item.documentID,
                paper: item.paper,
                contentRevision: item.contentRevision,
                isEmpty: item.isEmpty,
                drawingData: payload.documentData,
                previewImageData: payload.previewImageData,
                previewCGImage: payload.previewCGImage,
                boardDirectoryURL: boardDirectoryURL
            )
            return
        }

        try HandDrawingDocumentStore.validateBundleExists(
            documentID: item.documentID,
            boardDirectoryURL: boardDirectoryURL
        )
    }

    private static func normalizePersistedHandDrawingStorage(
        in document: inout BoardDocument,
        existingDocument: BoardDocument?
    ) {
        let existingStorageByItemID = Dictionary(
            uniqueKeysWithValues: existingDocument?.handDrawingItemRecords.map {
                ($0.id, $0.storage)
            } ?? []
        )
        document.items = document.items.map { itemRecord in
            guard case let .handDrawing(record) = itemRecord else {
                return itemRecord
            }

            let resolvedStorage = existingStorageByItemID[record.id] ?? .bundle
            return .handDrawing(record.replacingStorage(with: resolvedStorage))
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
