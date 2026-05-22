import CoreGraphics
import Foundation

enum HandDrawingDocumentStoreError: LocalizedError {
    case missingBundleComponent(
        documentID: HandDrawingDocumentID,
        component: String
    )
    case invalidManifestDocumentID(
        expected: HandDrawingDocumentID,
        actual: HandDrawingDocumentID
    )

    var errorDescription: String? {
        switch self {
        case let .missingBundleComponent(documentID, component):
            return "The hand drawing bundle component is missing for document \(documentID.uuidString): \(component)."
        case let .invalidManifestDocumentID(expected, actual):
            return "The hand drawing manifest document id mismatched. Expected \(expected.uuidString), actual \(actual.uuidString)."
        }
    }
}

enum HandDrawingDocumentStore {
    static func bundleExists(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) -> Bool {
        let bundleURL = HandDrawingBundleLocator(documentID: documentID)
            .bundleDirectoryURL(in: boardDirectoryURL)
        return FileManager.default.fileExists(atPath: bundleURL.path)
    }

    static func loadManifest(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> HandDrawingManifest {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let manifestURL = locator.manifestURL(in: boardDirectoryURL)
        guard try CoordinatedFileIO.modificationDate(at: manifestURL) != nil else {
            throw HandDrawingDocumentStoreError.missingBundleComponent(
                documentID: documentID,
                component: HandDrawingBundleLocator.manifestFilename
            )
        }

        let manifestData = try CoordinatedFileIO.readData(at: manifestURL)
        let manifest = try HandDrawingDocumentCodec.decodeManifest(from: manifestData)
        guard manifest.documentID == documentID else {
            throw HandDrawingDocumentStoreError.invalidManifestDocumentID(
                expected: documentID,
                actual: manifest.documentID
            )
        }
        return manifest
    }

    static func loadDocumentData(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> Data {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let documentURL = locator.documentURL(in: boardDirectoryURL)
        guard try CoordinatedFileIO.modificationDate(at: documentURL) != nil else {
            throw HandDrawingDocumentStoreError.missingBundleComponent(
                documentID: documentID,
                component: HandDrawingBundleLocator.documentFilename
            )
        }

        return try CoordinatedFileIO.readData(at: documentURL)
    }

    static func loadDocument(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> HandDrawingDocument {
        let manifest = try loadManifest(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        return try HandDrawingDocumentLoader.loadDocument(
            from: loadDocumentData(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            ),
            paper: manifest.paper.canvasPaperSpec
        )
    }

    static func loadNormalizedDocumentData(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> Data {
        try HandDrawingDocumentCodec.makeDocumentData(
            for: loadDocument(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        )
    }

    static func loadPreviewImage(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> CGImage {
        let previewImageData = try loadPreviewImageData(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        return try HandDrawingDocumentCodec.decodePreviewImage(
            from: previewImageData,
            documentID: documentID
        )
    }

    static func loadPreviewImageData(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> Data {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let previewImageURL = locator.previewImageURL(in: boardDirectoryURL)
        guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
            throw HandDrawingDocumentStoreError.missingBundleComponent(
                documentID: documentID,
                component: HandDrawingBundleLocator.previewFilename
            )
        }

        return try CoordinatedFileIO.readData(at: previewImageURL)
    }

    static func loadLegacyBackupDrawingData(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> Data {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let legacyBackupURL = locator.legacyBackupURL(in: boardDirectoryURL)
        guard try CoordinatedFileIO.modificationDate(at: legacyBackupURL) != nil else {
            throw HandDrawingDocumentStoreError.missingBundleComponent(
                documentID: documentID,
                component: HandDrawingBundleLocator.legacyBackupFilename
            )
        }

        return try CoordinatedFileIO.readData(at: legacyBackupURL)
    }

    static func validateBundleExists(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws {
        _ = try loadManifest(documentID: documentID, boardDirectoryURL: boardDirectoryURL)
        _ = try loadDocument(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
        _ = try loadPreviewImage(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
    }

    @discardableResult
    static func ensureHandDrawingsDirectoryURL(
        in boardDirectoryURL: URL
    ) throws -> URL {
        let handDrawingsDirectoryURL = HandDrawingBundleLocator.handDrawingsDirectoryURL(
            in: boardDirectoryURL
        )
        try CoordinatedFileIO.ensureDirectory(at: handDrawingsDirectoryURL)
        return handDrawingsDirectoryURL
    }

    static func persistDocument(
        documentID: HandDrawingDocumentID,
        paper: CanvasHandDrawingPaperSpec,
        contentRevision: UUID,
        isEmpty: Bool,
        drawingData: Data,
        previewImageData: Data?,
        previewCGImage: CGImage?,
        boardDirectoryURL: URL,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
        legacyBackupDrawingData: Data? = nil
    ) throws {
        _ = try ensureHandDrawingsDirectoryURL(in: boardDirectoryURL)

        let locator = HandDrawingBundleLocator(documentID: documentID)
        let normalizedDrawingData = try HandDrawingDocumentLoader.normalizeDocumentData(
            from: drawingData,
            paper: paper
        )
        let manifest = HandDrawingManifest(
            documentID: documentID,
            paper: paper,
            contentRevision: contentRevision,
            isEmpty: isEmpty,
            migrationOrigin: migrationOrigin
        )
        let resolvedPreviewImageData: Data
        if let previewImageData {
            resolvedPreviewImageData = previewImageData
        } else if let previewCGImage {
            resolvedPreviewImageData = try HandDrawingDocumentCodec.makePNGData(
                for: previewCGImage,
                documentID: documentID
            )
        } else {
            resolvedPreviewImageData = try makeCanonicalPreviewImageData(
                for: normalizedDrawingData,
                documentID: documentID
            )
        }

        try CoordinatedFileIO.writeData(
            try HandDrawingDocumentCodec.makeManifestData(for: manifest),
            to: locator.manifestURL(in: boardDirectoryURL)
        )
        try CoordinatedFileIO.writeData(
            normalizedDrawingData,
            to: locator.documentURL(in: boardDirectoryURL)
        )
        try CoordinatedFileIO.writeData(
            resolvedPreviewImageData,
            to: locator.previewImageURL(in: boardDirectoryURL)
        )
        if let legacyBackupDrawingData {
            try CoordinatedFileIO.writeData(
                legacyBackupDrawingData,
                to: locator.legacyBackupURL(in: boardDirectoryURL)
            )
        }
    }

    static func persistDocument(
        _ document: HandDrawingDocument,
        documentID: HandDrawingDocumentID,
        contentRevision: UUID,
        previewImageData: Data?,
        previewCGImage: CGImage?,
        boardDirectoryURL: URL,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
        legacyBackupDrawingData: Data? = nil
    ) throws {
        try persistDocument(
            documentID: documentID,
            paper: document.paper.canvasPaperSpec,
            contentRevision: contentRevision,
            isEmpty: document.isEmpty,
            drawingData: try HandDrawingDocumentCodec.makeDocumentData(for: document),
            previewImageData: previewImageData,
            previewCGImage: previewCGImage,
            boardDirectoryURL: boardDirectoryURL,
            migrationOrigin: migrationOrigin,
            legacyBackupDrawingData: legacyBackupDrawingData
        )
    }

    private static func makeCanonicalPreviewImageData(
        for normalizedDrawingData: Data,
        documentID: HandDrawingDocumentID
    ) throws -> Data {
        let normalizedDocument = try HandDrawingDocumentCodec.decodeDocument(
            from: normalizedDrawingData
        )
        let previewImage: CGImage
        if normalizedDocument.isEmpty {
            previewImage = try CanvasHandDrawingPreviewAssetFactory
                .makeTransparentPreview(for: normalizedDocument.paper.canvasPaperSpec)
        } else {
            previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
                for: normalizedDocument,
                scale: 1
            )
        }
        return try HandDrawingDocumentCodec.makePNGData(
            for: previewImage,
            documentID: documentID
        )
    }

    static func removeDocumentBundle(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws {
        let bundleURL = HandDrawingBundleLocator(documentID: documentID)
            .bundleDirectoryURL(in: boardDirectoryURL)
        try CoordinatedFileIO.removeItemIfExists(at: bundleURL)
    }

    static func removeOrphanedBundles(
        keeping documentIDs: Set<HandDrawingDocumentID>,
        boardDirectoryURL: URL
    ) throws {
        let handDrawingsDirectoryURL = HandDrawingBundleLocator.handDrawingsDirectoryURL(
            in: boardDirectoryURL
        )
        let bundleDirectoryNames = Set(
            documentIDs.map { HandDrawingBundleLocator(documentID: $0).bundleDirectoryName }
        )
        let bundleURLs = try CoordinatedFileIO.contentsOfDirectory(
            at: handDrawingsDirectoryURL
        )
        for bundleURL in bundleURLs {
            if bundleDirectoryNames.contains(bundleURL.lastPathComponent) {
                continue
            }

            try CoordinatedFileIO.removeItemIfExists(at: bundleURL)
        }
    }
}
