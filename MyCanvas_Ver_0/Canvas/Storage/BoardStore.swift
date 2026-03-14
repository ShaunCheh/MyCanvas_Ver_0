import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    static func listBoards(
        userDefaults: UserDefaults = .standard
    ) throws -> [BoardSummary] {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
            try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
            let candidateURLs = try CoordinatedFileIO.contentsOfDirectory(
                at: boardsDirectoryURL
            )

            var summaries: [BoardSummary] = []
            for candidateURL in candidateURLs {
                guard try isDirectory(candidateURL) else {
                    continue
                }

                let boardDocumentURL = candidateURL.appendingPathComponent(boardDocumentFilename)
                guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
                    continue
                }

                let document = try readBoardDocument(at: boardDocumentURL)
                summaries.append(document.summary)
            }

            return summaries.sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.boardID.uuidString < rhs.boardID.uuidString
                }

                return lhs.updatedAt > rhs.updatedAt
            }
        }
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

            return try BoardDocumentMapper.makeRuntimeState(from: document) { imageRecord in
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

            for item in runtimeState.items {
                let assetURL = assetsDirectoryURL.appendingPathComponent(
                    "\(item.id.uuidString).png"
                )
                let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
                try CoordinatedFileIO.writeData(pngData, to: assetURL)
            }

            try removeOrphanedAssets(
                keeping: Set(document.items.map(\.assetFilename)),
                in: assetsDirectoryURL
            )

            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
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
            return try loadBoard(id: firstBoard.boardID, userDefaults: userDefaults)
        }

        let runtimeState = BoardRuntimeState.makeEmpty()
        try saveBoard(runtimeState, userDefaults: userDefaults)
        return runtimeState
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

    private static func isDirectory(
        _ url: URL
    ) throws -> Bool {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues.isDirectory == true
    }
}
