import Foundation
import PencilKit

enum HandDrawingMigrationServiceError: LocalizedError {
    case missingBoardDocument(boardID: UUID)
    case missingHandDrawingRecord(
        boardID: UUID,
        itemID: CanvasItemID
    )
    case invalidLegacyDrawingData(itemID: CanvasItemID)
    case missingLegacyPreviewAsset(
        itemID: CanvasItemID,
        filename: String
    )

    var errorDescription: String? {
        switch self {
        case let .missingBoardDocument(boardID):
            return "The board document is missing for hand drawing migration: \(boardID.uuidString)"
        case let .missingHandDrawingRecord(boardID, itemID):
            return "The hand drawing record is missing for board \(boardID.uuidString), item \(itemID.uuidString)."
        case let .invalidLegacyDrawingData(itemID):
            return "The legacy hand drawing source could not be decoded for item \(itemID.uuidString)."
        case let .missingLegacyPreviewAsset(itemID, filename):
            return "The legacy hand drawing preview asset is missing for item \(itemID.uuidString): \(filename)"
        }
    }
}

struct HandDrawingPreparedEditingDocument {
    let record: BoardHandDrawingItemRecord
    let drawingData: Data
    let didMigrateLegacyDocument: Bool
}

enum HandDrawingMigrationService {
    static func prepareDocumentForEditing(
        boardID: UUID,
        itemID: CanvasItemID,
        userDefaults: UserDefaults = .standard
    ) throws -> HandDrawingPreparedEditingDocument {
        let entry = try resolveBoardDocumentEntry(
            boardID: boardID,
            userDefaults: userDefaults
        )
        let record = try resolveHandDrawingRecord(
            boardID: boardID,
            itemID: itemID,
            document: entry.document
        )

        switch record.storage {
        case .bundle:
            return try prepareBundleDocumentForEditing(
                record: record,
                boardDirectoryURL: entry.boardDirectoryURL
            )
        case .legacyFlatAssetPair:
            return try prepareLegacyDocumentForEditing(
                boardID: boardID,
                itemID: itemID,
                record: record,
                entry: entry,
                userDefaults: userDefaults
            )
        }
    }

    private static func prepareBundleDocumentForEditing(
        record: BoardHandDrawingItemRecord,
        boardDirectoryURL: URL
    ) throws -> HandDrawingPreparedEditingDocument {
        do {
            return HandDrawingPreparedEditingDocument(
                record: record,
                drawingData: try HandDrawingDocumentStore.loadDocumentData(
                    documentID: record.documentID,
                    boardDirectoryURL: boardDirectoryURL
                ),
                didMigrateLegacyDocument: false
            )
        } catch {
            guard let restoredDrawingData = try restoreDocumentFromLegacyBackupIfPossible(
                for: record,
                boardDirectoryURL: boardDirectoryURL
            ) else {
                throw error
            }

            return HandDrawingPreparedEditingDocument(
                record: record,
                drawingData: restoredDrawingData,
                didMigrateLegacyDocument: false
            )
        }
    }

    private static func prepareLegacyDocumentForEditing(
        boardID: UUID,
        itemID: CanvasItemID,
        record: BoardHandDrawingItemRecord,
        entry: BoardDocumentCatalogEntry,
        userDefaults: UserDefaults
    ) throws -> HandDrawingPreparedEditingDocument {
        if let resumedDocument = try resumeLegacyMigrationIfNeeded(
            boardID: boardID,
            itemID: itemID,
            record: record,
            boardDirectoryURL: entry.boardDirectoryURL,
            userDefaults: userDefaults
        ) {
            return resumedDocument
        }

        let legacyDrawingData = try loadLegacyDrawingData(
            for: record,
            assetsDirectoryURL: entry.assetsDirectoryURL
        )
        try validateLegacyDrawingData(
            legacyDrawingData,
            itemID: itemID
        )
        let legacyPreviewImageData = try loadLegacyPreviewImageData(
            for: record,
            itemID: itemID,
            assetsDirectoryURL: entry.assetsDirectoryURL
        )

        do {
            try HandDrawingDocumentStore.persistDocument(
                documentID: record.documentID,
                paper: record.paper.canvasPaperSpec,
                contentRevision: record.contentRevision,
                isEmpty: record.isEmpty,
                drawingData: legacyDrawingData,
                previewImageData: legacyPreviewImageData,
                previewCGImage: nil,
                boardDirectoryURL: entry.boardDirectoryURL,
                migrationOrigin: .legacyFlatAssetPair,
                legacyBackupDrawingData: legacyDrawingData
            )
            try HandDrawingDocumentStore.validateBundleExists(
                documentID: record.documentID,
                boardDirectoryURL: entry.boardDirectoryURL
            )
            try BoardStore.updateHandDrawingStorage(
                boardID: boardID,
                itemID: itemID,
                storage: .bundle,
                userDefaults: userDefaults
            )
        } catch {
            try? HandDrawingDocumentStore.removeDocumentBundle(
                documentID: record.documentID,
                boardDirectoryURL: entry.boardDirectoryURL
            )
            throw error
        }

        return HandDrawingPreparedEditingDocument(
            record: record.replacingStorage(with: .bundle),
            drawingData: legacyDrawingData,
            didMigrateLegacyDocument: true
        )
    }

    private static func resumeLegacyMigrationIfNeeded(
        boardID: UUID,
        itemID: CanvasItemID,
        record: BoardHandDrawingItemRecord,
        boardDirectoryURL: URL,
        userDefaults: UserDefaults
    ) throws -> HandDrawingPreparedEditingDocument? {
        guard HandDrawingDocumentStore.bundleExists(
            documentID: record.documentID,
            boardDirectoryURL: boardDirectoryURL
        ) else {
            return nil
        }

        do {
            let drawingData = try HandDrawingDocumentStore.loadDocumentData(
                documentID: record.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            try BoardStore.updateHandDrawingStorage(
                boardID: boardID,
                itemID: itemID,
                storage: .bundle,
                userDefaults: userDefaults
            )
            return HandDrawingPreparedEditingDocument(
                record: record.replacingStorage(with: .bundle),
                drawingData: drawingData,
                didMigrateLegacyDocument: true
            )
        } catch {
            try? HandDrawingDocumentStore.removeDocumentBundle(
                documentID: record.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            return nil
        }
    }

    private static func restoreDocumentFromLegacyBackupIfPossible(
        for record: BoardHandDrawingItemRecord,
        boardDirectoryURL: URL
    ) throws -> Data? {
        let manifest = try? HandDrawingDocumentStore.loadManifest(
            documentID: record.documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        guard manifest?.migrationOrigin == .legacyFlatAssetPair else {
            return nil
        }

        let legacyBackupDrawingData = try HandDrawingDocumentStore
            .loadLegacyBackupDrawingData(
                documentID: record.documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        try validateLegacyDrawingData(
            legacyBackupDrawingData,
            itemID: record.id
        )
        let previewImageData = try HandDrawingDocumentStore.loadPreviewImageData(
            documentID: record.documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        let resolvedMigrationOrigin = manifest.flatMap(\.migrationOrigin)

        try HandDrawingDocumentStore.persistDocument(
            documentID: record.documentID,
            paper: manifest?.paper.canvasPaperSpec ?? record.paper.canvasPaperSpec,
            contentRevision: manifest?.contentRevision ?? record.contentRevision,
            isEmpty: manifest?.isEmpty ?? record.isEmpty,
            drawingData: legacyBackupDrawingData,
            previewImageData: previewImageData,
            previewCGImage: nil,
            boardDirectoryURL: boardDirectoryURL,
            migrationOrigin: resolvedMigrationOrigin,
            legacyBackupDrawingData: legacyBackupDrawingData
        )
        return legacyBackupDrawingData
    }

    private static func resolveBoardDocumentEntry(
        boardID: UUID,
        userDefaults: UserDefaults
    ) throws -> BoardDocumentCatalogEntry {
        guard let entry = try BoardStore.loadBoardDocumentEntry(
            id: boardID,
            userDefaults: userDefaults
        ) else {
            throw HandDrawingMigrationServiceError.missingBoardDocument(
                boardID: boardID
            )
        }
        return entry
    }

    private static func resolveHandDrawingRecord(
        boardID: UUID,
        itemID: CanvasItemID,
        document: BoardDocument
    ) throws -> BoardHandDrawingItemRecord {
        guard let record = document.handDrawingItemRecords.first(where: { $0.id == itemID })
        else {
            throw HandDrawingMigrationServiceError.missingHandDrawingRecord(
                boardID: boardID,
                itemID: itemID
            )
        }
        return record
    }

    private static func loadLegacyDrawingData(
        for record: BoardHandDrawingItemRecord,
        assetsDirectoryURL: URL
    ) throws -> Data {
        try CoordinatedFileIO.readData(
            at: record.legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
        )
    }

    private static func loadLegacyPreviewImageData(
        for record: BoardHandDrawingItemRecord,
        itemID: CanvasItemID,
        assetsDirectoryURL: URL
    ) throws -> Data {
        let previewURL = record.legacyAssetLocator.previewImageURL(
            in: assetsDirectoryURL
        )
        guard try CoordinatedFileIO.modificationDate(at: previewURL) != nil else {
            throw HandDrawingMigrationServiceError.missingLegacyPreviewAsset(
                itemID: itemID,
                filename: record.legacyAssetLocator.previewImageFilename
            )
        }
        return try CoordinatedFileIO.readData(at: previewURL)
    }

    private static func validateLegacyDrawingData(
        _ data: Data,
        itemID: CanvasItemID
    ) throws {
        guard data.isEmpty == false else {
            return
        }

        do {
            _ = try PKDrawing(data: data)
        } catch {
            throw HandDrawingMigrationServiceError.invalidLegacyDrawingData(
                itemID: itemID
            )
        }
    }
}
