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
    case failedToEncodeImageAsset(itemID: UUID)

    var errorDescription: String? {
        switch self {
        case .invalidBoardDirectory:
            return "The board directory is invalid."
        case let .invalidBoardImageAsset(filename):
            return "The board image asset could not be decoded: \(filename)"
        case let .failedToEncodeImageAsset(itemID):
            return "The image asset could not be encoded for board item \(itemID.uuidString)."
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

    static func saveBoard(
        _ runtimeState: BoardRuntimeState,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)

            let boardDirectoryURL = self.boardDirectoryURL(
                for: runtimeState.boardID,
                boardsDirectoryURL: boardsDirectoryURL
            )
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                assetsDirectoryName,
                isDirectory: true
            )
            try CoordinatedFileIO.ensureDirectory(at: boardDirectoryURL)
            try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)

            var persistedState = runtimeState
            persistedState.updatedAt = Date()
            let document = BoardDocumentMapper.makeDocument(from: persistedState)

            for item in persistedState.imageItems {
                let assetURL = assetsDirectoryURL.appendingPathComponent(
                    "\(item.id.uuidString).png"
                )
                let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
                try CoordinatedFileIO.writeData(pngData, to: assetURL)
            }

            try removeOrphanedAssets(
                keeping: Set(document.imageItemRecords.map(\.assetFilename)),
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
                guard try isDirectory(candidateURL) else {
                    continue
                }

                let boardDocumentURL = candidateURL.appendingPathComponent(boardDocumentFilename)
                guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
                    continue
                }

                let document = try readBoardDocument(at: boardDocumentURL)
                entries.append(
                    BoardDocumentCatalogEntry(
                        boardDirectoryURL: candidateURL,
                        documentURL: boardDocumentURL,
                        assetsDirectoryURL: candidateURL.appendingPathComponent(
                            assetsDirectoryName,
                            isDirectory: true
                        ),
                        document: document
                    )
                )
            }

            return entries.sorted { lhs, rhs in
                if lhs.document.updatedAt == rhs.document.updatedAt {
                    return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
                }

                return lhs.document.updatedAt > rhs.document.updatedAt
            }
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
                    to: boardDirectoryURL
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
