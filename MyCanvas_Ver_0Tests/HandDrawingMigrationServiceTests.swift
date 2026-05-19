import CoreGraphics
import Foundation
import PencilKit
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingMigrationServiceTests: XCTestCase {
    func testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() throws {
        try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
            let fixture = try makeLegacyHandDrawingFixture(
                selectedFolderURL: selectedFolderURL,
                drawingData: PKDrawing().dataRepresentation()
            )

            let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
                boardID: fixture.boardID,
                itemID: fixture.itemID,
                userDefaults: userDefaults
            )

            XCTAssertEqual(preparedDocument.record.storage, .bundle)
            XCTAssertTrue(preparedDocument.didMigrateLegacyDocument)
            try assertNormalizedEmptyDocumentData(preparedDocument.documentData)

            let manifest = try HandDrawingDocumentStore.loadManifest(
                documentID: fixture.documentID,
                boardDirectoryURL: fixture.boardDirectoryURL
            )
            let storedDocumentData = try HandDrawingDocumentStore.loadDocumentData(
                documentID: fixture.documentID,
                boardDirectoryURL: fixture.boardDirectoryURL
            )
            let storedLegacyBackupData = try HandDrawingDocumentStore
                .loadLegacyBackupDrawingData(
                    documentID: fixture.documentID,
                    boardDirectoryURL: fixture.boardDirectoryURL
                )
            let entry = try XCTUnwrap(
                BoardStore.loadBoardDocumentEntry(
                    id: fixture.boardID,
                    userDefaults: userDefaults
                )
            )

            XCTAssertEqual(manifest.migrationOrigin, .legacyFlatAssetPair)
            try assertNormalizedEmptyDocumentData(storedDocumentData)
            XCTAssertEqual(storedLegacyBackupData, fixture.drawingData)
            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .bundle
            )
            try assertNormalizedEmptyDocumentData(
                BoardStore.loadHandDrawingDocumentData(
                    boardID: fixture.boardID,
                    documentID: fixture.documentID,
                    userDefaults: userDefaults
                )
            )
        }
    }

    func testHandDrawingMigrationServiceRollsBackWhenLegacyDrawingIsInvalid() throws {
        try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
            let fixture = try makeLegacyHandDrawingFixture(
                selectedFolderURL: selectedFolderURL,
                drawingData: Data("invalid-pkdrawing".utf8)
            )

            XCTAssertThrowsError(
                try HandDrawingMigrationService.prepareDocumentForEditing(
                    boardID: fixture.boardID,
                    itemID: fixture.itemID,
                    userDefaults: userDefaults
                )
            ) { error in
                guard case HandDrawingMigrationServiceError.invalidLegacyDrawingData =
                    error
                else {
                    return XCTFail("Unexpected migration error: \(error)")
                }
            }

            let entry = try XCTUnwrap(
                BoardStore.loadBoardDocumentEntry(
                    id: fixture.boardID,
                    userDefaults: userDefaults
                )
            )

            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .legacyFlatAssetPair
            )
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: HandDrawingBundleLocator(documentID: fixture.documentID)
                        .bundleDirectoryURL(in: fixture.boardDirectoryURL)
                )
            )
        }
    }

    func testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup() throws {
        try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
            let boardID = UUID()
            let itemID = UUID()
            let documentID = UUID()
            let boardDirectoryURL = makeMigrationBoardDirectoryURL(
                selectedFolderURL: selectedFolderURL,
                boardID: boardID
            )
            let previewImage = try makeHandDrawingMigrationTestImage(alpha: 0)
            let previewImageData = try HandDrawingDocumentCodec.makePNGData(
                for: previewImage,
                documentID: documentID
            )
            let legacyBackupData = PKDrawing().dataRepresentation()
            let bundleRecord = BoardHandDrawingItemRecord(
                id: itemID,
                documentID: documentID,
                center: BoardPointRecord(CGPoint(x: 128, y: 128)),
                size: BoardSizeRecord(CGSize(width: 256, height: 256)),
                zIndex: 2,
                paper: BoardHandDrawingPaperRecord(.square),
                isEmpty: true,
                contentRevision: UUID(),
                rotationRadians: 0,
                storage: .bundle
            )
            let document = makeMigrationBoardDocument(
                boardID: boardID,
                itemRecord: bundleRecord
            )

            try CoordinatedFileIO.writeData(
                try makeMigrationBoardDocumentData(document),
                to: boardDirectoryURL.appendingPathComponent("board.json")
            )
            try HandDrawingDocumentStore.persistDocument(
                documentID: documentID,
                paper: .square,
                contentRevision: bundleRecord.contentRevision,
                isEmpty: true,
                drawingData: legacyBackupData,
                previewImageData: previewImageData,
                previewCGImage: nil,
                boardDirectoryURL: boardDirectoryURL,
                migrationOrigin: .legacyFlatAssetPair,
                legacyBackupDrawingData: legacyBackupData
            )
            try CoordinatedFileIO.removeItemIfExists(
                at: HandDrawingBundleLocator(documentID: documentID).documentURL(
                    in: boardDirectoryURL
                )
            )

            let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
                boardID: boardID,
                itemID: itemID,
                userDefaults: userDefaults
            )

            XCTAssertFalse(preparedDocument.didMigrateLegacyDocument)
            XCTAssertEqual(preparedDocument.record.storage, .bundle)
            try assertNormalizedEmptyDocumentData(preparedDocument.documentData)
            try assertNormalizedEmptyDocumentData(
                HandDrawingDocumentStore.loadDocumentData(
                    documentID: documentID,
                    boardDirectoryURL: boardDirectoryURL
                )
            )
        }
    }

    func testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen() throws {
        try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
            let fixture = try makeLegacyHandDrawingFixture(
                selectedFolderURL: selectedFolderURL,
                drawingData: PKDrawing().dataRepresentation()
            )
            let session = CanvasEditorSession(
                saveQueueLabel: "HandDrawingMigrationServiceTests.Session",
                logPrefix: "[HandDrawingMigrationServiceTests]",
                userDefaults: userDefaults
            )
            HandDrawingMigrationServiceTestRetainer.sessions.append(session)

            try session.loadBoard(id: fixture.boardID)
            let firstContext = try session.handDrawingEditorContext(for: fixture.itemID)
            let secondContext = try session.handDrawingEditorContext(for: fixture.itemID)
            let entry = try XCTUnwrap(
                BoardStore.loadBoardDocumentEntry(
                    id: fixture.boardID,
                    userDefaults: userDefaults
                )
            )

            XCTAssertEqual(firstContext.itemID, fixture.itemID)
            XCTAssertEqual(firstContext.documentID, fixture.documentID)
            XCTAssertEqual(firstContext.storage, .bundle)
            XCTAssertTrue(firstContext.didMigrateLegacyDocument)
            try assertNormalizedEmptyDocumentData(firstContext.documentData)

            XCTAssertEqual(secondContext.storage, .bundle)
            XCTAssertFalse(secondContext.didMigrateLegacyDocument)
            try assertNormalizedEmptyDocumentData(secondContext.documentData)
            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .bundle
            )
        }
    }

    func testCanvasEditorSessionCommitHandDrawingEditPersistsMigratedDocumentAsBundle() throws {
        try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
            let fixture = try makeLegacyHandDrawingFixture(
                selectedFolderURL: selectedFolderURL,
                drawingData: PKDrawing().dataRepresentation()
            )
            let session = CanvasEditorSession(
                saveQueueLabel: "HandDrawingMigrationServiceTests.Commit",
                logPrefix: "[HandDrawingMigrationServiceTests]",
                userDefaults: userDefaults
            )
            HandDrawingMigrationServiceTestRetainer.sessions.append(session)

            try session.loadBoard(id: fixture.boardID)
            let editorContext = try session.handDrawingEditorContext(for: fixture.itemID)
            let updatedDocumentData = try HandDrawingDocumentCodec.makeDocumentData(
                for: makeHandDrawingTestDocument(includeEraseMask: true)
            )
            let updatedPreviewImage = try makeHandDrawingMigrationTestImage(alpha: 1)
            let updatedRevision = UUID()

            XCTAssertTrue(editorContext.didMigrateLegacyDocument)

            let commitResult = try XCTUnwrap(
                session.commitHandDrawingEdit(
                    withID: fixture.itemID,
                    submission: CanvasHandDrawingEditSubmission(
                        documentData: updatedDocumentData,
                        previewCGImage: updatedPreviewImage,
                        isEmpty: false,
                        contentRevision: updatedRevision
                    )
                )
            )
            let saveSnapshot = try XCTUnwrap(session.currentBoardSaveSnapshot())
            try BoardStore.saveBoard(saveSnapshot, userDefaults: userDefaults)

            let entry = try XCTUnwrap(
                BoardStore.loadBoardDocumentEntry(
                    id: fixture.boardID,
                    userDefaults: userDefaults
                )
            )
            let bundleLocator = HandDrawingBundleLocator(documentID: fixture.documentID)
            let legacyAssetLocator = BoardHandDrawingAssetLocator(
                documentID: fixture.documentID
            )

            XCTAssertEqual(commitResult.refreshReason, "commit hand drawing edit")
            XCTAssertEqual(commitResult.item.contentRevision, updatedRevision)
            XCTAssertEqual(entry.document.handDrawingItemRecords.first?.storage, .bundle)
            XCTAssertEqual(
                try HandDrawingDocumentStore.loadDocumentData(
                    documentID: fixture.documentID,
                    boardDirectoryURL: fixture.boardDirectoryURL
                ),
                updatedDocumentData
            )
            XCTAssertEqual(
                try BoardStore.loadHandDrawingDocumentData(
                    boardID: fixture.boardID,
                    documentID: fixture.documentID,
                    userDefaults: userDefaults
                ),
                updatedDocumentData
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: bundleLocator.bundleDirectoryURL(in: fixture.boardDirectoryURL)
                )
            )
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: legacyAssetLocator.sourceDrawingURL(in: fixture.assetsDirectoryURL)
                )
            )
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: legacyAssetLocator.previewImageURL(in: fixture.assetsDirectoryURL)
                )
            )
        }
    }
}

private struct HandDrawingMigrationFixture {
    let boardID: UUID
    let itemID: UUID
    let documentID: UUID
    let boardDirectoryURL: URL
    let assetsDirectoryURL: URL
    let drawingData: Data
}

private enum HandDrawingMigrationServiceTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private enum HandDrawingMigrationServiceTestError: Error {
    case invalidBitmapContext
}

private func withTemporaryHandDrawingMigrationWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "HandDrawingMigrationServiceTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )

    let suiteName = "HandDrawingMigrationServiceTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: handDrawingMigrationBookmarkCreationOptions(),
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    FolderBookmarkStore.save(bookmarkData, userDefaults: userDefaults)

    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: selectedFolderURL)
    }

    try body(selectedFolderURL, userDefaults)
}

private func handDrawingMigrationBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
}

private func makeLegacyHandDrawingFixture(
    selectedFolderURL: URL,
    drawingData: Data
) throws -> HandDrawingMigrationFixture {
    let boardID = UUID()
    let itemID = UUID()
    let documentID = UUID()
    let boardDirectoryURL = makeMigrationBoardDirectoryURL(
        selectedFolderURL: selectedFolderURL,
        boardID: boardID
    )
    let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
        "assets",
        isDirectory: true
    )
    let previewImage = try makeHandDrawingMigrationTestImage(alpha: 0)
    let legacyRecord = BoardHandDrawingItemRecord(
        id: itemID,
        documentID: documentID,
        center: BoardPointRecord(CGPoint(x: 128, y: 128)),
        size: BoardSizeRecord(CGSize(width: 256, height: 256)),
        zIndex: 2,
        paper: BoardHandDrawingPaperRecord(.square),
        isEmpty: true,
        contentRevision: UUID(),
        rotationRadians: 0,
        storage: .legacyFlatAssetPair
    )
    let boardDocument = makeMigrationBoardDocument(
        boardID: boardID,
        itemRecord: legacyRecord
    )
    let legacyAssetLocator = BoardHandDrawingAssetLocator(documentID: documentID)

    try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)
    try CoordinatedFileIO.writeData(
        drawingData,
        to: legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
    )
    try CoordinatedFileIO.writeData(
        try HandDrawingDocumentCodec.makePNGData(
            for: previewImage,
            documentID: documentID
        ),
        to: legacyAssetLocator.previewImageURL(in: assetsDirectoryURL)
    )
    try CoordinatedFileIO.writeData(
        try makeMigrationBoardDocumentData(boardDocument),
        to: boardDirectoryURL.appendingPathComponent("board.json")
    )

    return HandDrawingMigrationFixture(
        boardID: boardID,
        itemID: itemID,
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL,
        assetsDirectoryURL: assetsDirectoryURL,
        drawingData: drawingData
    )
}

private func makeMigrationBoardDirectoryURL(
    selectedFolderURL: URL,
    boardID: UUID
) -> URL {
    selectedFolderURL
        .appendingPathComponent(
            SelectedFolderAccess.workspaceDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent(
            SelectedFolderAccess.boardsDirectoryName,
            isDirectory: true
        )
        .appendingPathComponent(boardID.uuidString, isDirectory: true)
}

private func makeMigrationBoardDocument(
    boardID: UUID,
    itemRecord: BoardHandDrawingItemRecord
) -> BoardDocument {
    BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: boardID,
        title: "Legacy Migration Board",
        createdAt: Date(timeIntervalSince1970: 1_720_200_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_720_200_000),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_720_200_000),
        boardBaseSize: BoardSizeRecord(CGSize(width: 256, height: 256)),
        boardRect: BoardRectRecord(CGRect(x: 0, y: 0, width: 256, height: 256)),
        cameraCenter: BoardPointRecord(CGPoint(x: 128, y: 128)),
        cameraZoomScale: 1,
        workspaceMode: .editing,
        items: [.handDrawing(itemRecord)]
    )
}

private func assertNormalizedEmptyDocumentData(
    _ data: Data,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let document = try HandDrawingDocumentCodec.decodeDocument(from: data)
    XCTAssertEqual(document.paper, HandDrawingPaper(.square), file: file, line: line)
    XCTAssertTrue(document.isEmpty, file: file, line: line)
    XCTAssertEqual(document.layers.count, 1, file: file, line: line)
    XCTAssertEqual(document.activeLayerStrokes.count, 0, file: file, line: line)
}

private func makeMigrationBoardDocumentData(
    _ document: BoardDocument
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(document)
}

private func makeHandDrawingMigrationTestImage(
    alpha: CGFloat,
    size: CGSize = CGSize(width: 48, height: 48)
) throws -> CGImage {
    let width = max(Int(size.width), 1)
    let height = max(Int(size.height), 1)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw HandDrawingMigrationServiceTestError.invalidBitmapContext
    }

    context.setFillColor(
        red: 0.25,
        green: 0.45,
        blue: 0.85,
        alpha: alpha
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        throw HandDrawingMigrationServiceTestError.invalidBitmapContext
    }
    return image
}
