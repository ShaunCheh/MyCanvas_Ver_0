import CoreGraphics
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingDocumentStoreTests: XCTestCase {
    func testHandDrawingDocumentStorePersistsBundleRoundTrip() throws {
        try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
            let documentID = UUID()
            let contentRevision = UUID()
            let drawingData = Data("bundle-round-trip".utf8)
            let previewImage = try makeHandDrawingDocumentStoreTestImage(
                red: 0.15,
                green: 0.35,
                blue: 0.85
            )

            try HandDrawingDocumentStore.persistDocument(
                documentID: documentID,
                paper: .square,
                contentRevision: contentRevision,
                isEmpty: false,
                drawingData: drawingData,
                previewImageData: nil,
                previewCGImage: previewImage,
                boardDirectoryURL: boardDirectoryURL
            )

            let manifest = try HandDrawingDocumentStore.loadManifest(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            let loadedDrawingData = try HandDrawingDocumentStore.loadDocumentData(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            let loadedPreviewImage = try HandDrawingDocumentStore.loadPreviewImage(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            let bundleLocator = HandDrawingBundleLocator(documentID: documentID)

            XCTAssertEqual(manifest.documentID, documentID)
            XCTAssertEqual(manifest.paper.canvasPaperSpec, .square)
            XCTAssertEqual(manifest.contentRevision, contentRevision)
            XCTAssertFalse(manifest.isEmpty)
            XCTAssertEqual(loadedDrawingData, drawingData)
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(loadedPreviewImage),
                BoardThumbnailImageSignature.describe(previewImage)
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: bundleLocator.manifestURL(in: boardDirectoryURL)
                )
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: bundleLocator.documentURL(in: boardDirectoryURL)
                )
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: bundleLocator.previewImageURL(in: boardDirectoryURL)
                )
            )
        }
    }

    func testHandDrawingDocumentStorePersistsTypedDocumentRoundTrip() throws {
        try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
            let documentID = UUID()
            let contentRevision = UUID()
            let document = makeHandDrawingTestDocument(includeEraseMask: true)
            let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
                for: document,
                scale: 1
            )

            try HandDrawingDocumentStore.persistDocument(
                document,
                documentID: documentID,
                contentRevision: contentRevision,
                previewImageData: nil,
                previewCGImage: previewImage,
                boardDirectoryURL: boardDirectoryURL
            )

            let loadedDocument = try HandDrawingDocumentStore.loadDocument(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            XCTAssertEqual(loadedDocument, document)
        }
    }

    func testHandDrawingDocumentStorePersistsProvidedPreviewImageData() throws {
        try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
            let documentID = UUID()
            let contentRevision = UUID()
            let previewImage = try makeHandDrawingDocumentStoreTestImage(
                red: 0.25,
                green: 0.7,
                blue: 0.35
            )
            let previewImageData = try HandDrawingDocumentCodec.makePNGData(
                for: previewImage,
                documentID: documentID
            )

            try HandDrawingDocumentStore.persistDocument(
                documentID: documentID,
                paper: .square,
                contentRevision: contentRevision,
                isEmpty: false,
                drawingData: Data("preview-image-data-round-trip".utf8),
                previewImageData: previewImageData,
                previewCGImage: nil,
                boardDirectoryURL: boardDirectoryURL
            )

            let storedPreviewImageData = try HandDrawingDocumentStore
                .loadPreviewImageData(
                    documentID: documentID,
                    boardDirectoryURL: boardDirectoryURL
                )
            let loadedPreviewImage = try HandDrawingDocumentStore.loadPreviewImage(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )

            XCTAssertEqual(storedPreviewImageData, previewImageData)
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(loadedPreviewImage),
                BoardThumbnailImageSignature.describe(previewImage)
            )
        }
    }

    func testHandDrawingDocumentStoreRemovesOrphanedBundles() throws {
        try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
            let keptDocumentID = UUID()
            let orphanDocumentID = UUID()
            let previewImage = try makeHandDrawingDocumentStoreTestImage(
                red: 0.9,
                green: 0.2,
                blue: 0.4
            )

            for documentID in [keptDocumentID, orphanDocumentID] {
                try HandDrawingDocumentStore.persistDocument(
                    documentID: documentID,
                    paper: .square,
                    contentRevision: UUID(),
                    isEmpty: false,
                    drawingData: Data(documentID.uuidString.utf8),
                    previewImageData: nil,
                    previewCGImage: previewImage,
                    boardDirectoryURL: boardDirectoryURL
                )
            }

            try HandDrawingDocumentStore.removeOrphanedBundles(
                keeping: [keptDocumentID],
                boardDirectoryURL: boardDirectoryURL
            )

            let keptBundleURL = HandDrawingBundleLocator(documentID: keptDocumentID)
                .bundleDirectoryURL(in: boardDirectoryURL)
            let orphanBundleURL = HandDrawingBundleLocator(documentID: orphanDocumentID)
                .bundleDirectoryURL(in: boardDirectoryURL)

            XCTAssertNotNil(try CoordinatedFileIO.modificationDate(at: keptBundleURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanBundleURL))
        }
    }
}

private enum HandDrawingDocumentStoreTestsError: Error {
    case invalidBitmapContext
}

private func withTemporaryHandDrawingBoardDirectory(
    _ body: (URL) throws -> Void
) throws {
    let fileManager = FileManager.default
    let rootDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(
        "HandDrawingDocumentStoreTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let boardDirectoryURL = rootDirectoryURL.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: boardDirectoryURL,
        withIntermediateDirectories: true,
        attributes: nil
    )
    defer {
        try? fileManager.removeItem(at: rootDirectoryURL)
    }

    try body(boardDirectoryURL)
}

private func makeHandDrawingDocumentStoreTestImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat
) throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw HandDrawingDocumentStoreTestsError.invalidBitmapContext
    }

    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    guard let image = context.makeImage() else {
        throw HandDrawingDocumentStoreTestsError.invalidBitmapContext
    }

    return image
}
