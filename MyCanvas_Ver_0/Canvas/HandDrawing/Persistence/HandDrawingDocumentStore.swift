import CoreGraphics
import Foundation

enum HandDrawingDocumentStoreError: LocalizedError {
    case missingBundleComponent(
        documentID: HandDrawingDocumentID,
        component: String
    )
    case missingPreviewRepresentation(documentID: HandDrawingDocumentID)
    case invalidManifestDocumentID(
        expected: HandDrawingDocumentID,
        actual: HandDrawingDocumentID
    )

    var errorDescription: String? {
        switch self {
        case let .missingBundleComponent(documentID, component):
            return "The hand drawing bundle component is missing for document \(documentID.uuidString): \(component)."
        case let .missingPreviewRepresentation(documentID):
            return "The hand drawing preview representation is missing for document \(documentID.uuidString)."
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

    static func loadPreviewImage(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> CGImage {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let previewImageURL = locator.previewImageURL(in: boardDirectoryURL)
        guard try CoordinatedFileIO.modificationDate(at: previewImageURL) != nil else {
            throw HandDrawingDocumentStoreError.missingBundleComponent(
                documentID: documentID,
                component: HandDrawingBundleLocator.previewFilename
            )
        }

        let previewImageData = try CoordinatedFileIO.readData(at: previewImageURL)
        return try HandDrawingDocumentCodec.decodePreviewImage(
            from: previewImageData,
            documentID: documentID
        )
    }

    static func validateBundleExists(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws {
        _ = try loadManifest(documentID: documentID, boardDirectoryURL: boardDirectoryURL)
        _ = try loadDocumentData(
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
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil
    ) throws {
        _ = try ensureHandDrawingsDirectoryURL(in: boardDirectoryURL)

        let locator = HandDrawingBundleLocator(documentID: documentID)
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
            throw HandDrawingDocumentStoreError.missingPreviewRepresentation(
                documentID: documentID
            )
        }

        try CoordinatedFileIO.writeData(
            try HandDrawingDocumentCodec.makeManifestData(for: manifest),
            to: locator.manifestURL(in: boardDirectoryURL)
        )
        try CoordinatedFileIO.writeData(
            drawingData,
            to: locator.documentURL(in: boardDirectoryURL)
        )
        try CoordinatedFileIO.writeData(
            resolvedPreviewImageData,
            to: locator.previewImageURL(in: boardDirectoryURL)
        )
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
