import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class BoardHandDrawingStorageTests: XCTestCase {
    func testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() throws {
        try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let itemID = UUID()
            let documentID = UUID()
            let previewImage = try makeHandDrawingTestImage(
                red: 0.9,
                green: 0.1,
                blue: 0.2
            )
            let drawingData = Data("hand-drawing-v1".utf8)
            let item = makeHandDrawingItem(
                id: itemID,
                documentID: documentID,
                previewImage: previewImage,
                contentRevision: UUID()
            )
            let runtimeState = makeHandDrawingRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_720_000_000),
                item: item
            )
            let snapshot = BoardSaveSnapshot(
                runtimeState: runtimeState,
                transientImageAssetPayloads: [:],
                transientHandDrawingAssetPayloads: [
                    itemID: BoardTransientHandDrawingAssetPayload(
                        itemID: itemID,
                    documentData: drawingData,
                        previewImageData: try makeHandDrawingPNGData(for: previewImage)
                    )
                ]
            )

            let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID,
                userDefaults: userDefaults
            )
            let orphanPreviewURL = assetsDirectoryURL.appendingPathComponent(
                "orphan-preview.png"
            )
            let orphanDrawingURL = assetsDirectoryURL.appendingPathComponent(
                "orphan-drawing.pkdrawing"
            )
            try CoordinatedFileIO.writeData(
                Data("orphan-preview".utf8),
                to: orphanPreviewURL
            )
            try CoordinatedFileIO.writeData(
                Data("orphan-drawing".utf8),
                to: orphanDrawingURL
            )

            try BoardStore.saveBoard(snapshot, userDefaults: userDefaults)

            let entry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let bundleLocator = HandDrawingBundleLocator(documentID: documentID)
            let previewURL = bundleLocator.previewImageURL(
                in: entry.boardDirectoryURL
            )
            let sourceURL = bundleLocator.documentURL(
                in: entry.boardDirectoryURL
            )
            let legacyAssetLocator = BoardHandDrawingAssetLocator(
                documentID: documentID
            )
            XCTAssertEqual(
                try CoordinatedFileIO.readData(at: sourceURL),
                drawingData
            )
            XCTAssertNotNil(try CoordinatedFileIO.modificationDate(at: previewURL))
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: legacyAssetLocator.previewImageURL(in: assetsDirectoryURL)
                )
            )
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
                )
            )
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanPreviewURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanDrawingURL))

            let loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedItem = try XCTUnwrap(loadedState.handDrawingItems.first)
            XCTAssertEqual(loadedItem.id, item.id)
            XCTAssertEqual(loadedItem.documentID, documentID)
            XCTAssertEqual(loadedItem.paper, item.paper)
            XCTAssertEqual(loadedItem.isEmpty, item.isEmpty)
            XCTAssertEqual(loadedItem.contentRevision, item.contentRevision)
            XCTAssertEqual(
                loadedItem.previewAsset.reference.stableAssetFilename,
                item.previewImageFilename
            )
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(
                    loadedItem.previewAsset.posterCGImage
                ),
                BoardThumbnailImageSignature.describe(previewImage)
            )
            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .bundle
            )
            XCTAssertEqual(
                try BoardStore.loadHandDrawingDocumentData(
                    boardID: boardID,
                    documentID: documentID,
                    userDefaults: userDefaults
                ),
                drawingData
            )
        }
    }

    func testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail() throws {
        try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let itemID = UUID()
            let firstPreviewImage = try makeHandDrawingTestImage(
                red: 1,
                green: 0,
                blue: 0
            )
            let secondPreviewImage = try makeHandDrawingTestImage(
                red: 0,
                green: 0,
                blue: 1
            )
            let firstDrawingData = Data("hand-drawing-v1".utf8)
            let secondDrawingData = Data("hand-drawing-v2".utf8)
            let firstRevision = UUID()
            let secondRevision = UUID()

            let firstItem = makeHandDrawingItem(
                id: itemID,
                previewImage: firstPreviewImage,
                contentRevision: firstRevision
            )
            let bundleLocator = HandDrawingBundleLocator(
                documentID: firstItem.documentID
            )
            var runtimeState = makeHandDrawingRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_720_000_200),
                item: firstItem
            )
            try BoardStore.saveBoard(
                BoardSaveSnapshot(
                    runtimeState: runtimeState,
                    transientImageAssetPayloads: [:],
                    transientHandDrawingAssetPayloads: [
                        itemID: BoardTransientHandDrawingAssetPayload(
                            itemID: itemID,
                        documentData: firstDrawingData,
                            previewImageData: try makeHandDrawingPNGData(
                                for: firstPreviewImage
                            )
                        )
                    ]
                ),
                userDefaults: userDefaults
            )

            let firstEntry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let thumbnailURL = BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: firstEntry.boardDirectoryURL
            )
            let firstThumbnailSignature = BoardThumbnailImageSignature.describe(
                try decodeHandDrawingImage(at: thumbnailURL)
            )

            Thread.sleep(forTimeInterval: 1.1)

            runtimeState.items = [
                .handDrawing(
                    makeHandDrawingItem(
                        id: itemID,
                        previewImage: secondPreviewImage,
                        contentRevision: secondRevision
                    )
                )
            ]
            try BoardStore.saveBoard(
                BoardSaveSnapshot(
                    runtimeState: runtimeState,
                    transientImageAssetPayloads: [:],
                    transientHandDrawingAssetPayloads: [
                        itemID: BoardTransientHandDrawingAssetPayload(
                            itemID: itemID,
                        documentData: secondDrawingData,
                            previewImageData: try makeHandDrawingPNGData(
                                for: secondPreviewImage
                            )
                        )
                    ]
                ),
                userDefaults: userDefaults
            )

            let secondEntry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let secondThumbnailSignature = BoardThumbnailImageSignature.describe(
                try decodeHandDrawingImage(
                    at: BoardPersistedThumbnailStore.thumbnailURL(
                        forBoardDirectoryURL: secondEntry.boardDirectoryURL
                    )
                )
            )
            let previewURL = bundleLocator.previewImageURL(
                in: secondEntry.boardDirectoryURL
            )

            XCTAssertNotEqual(firstThumbnailSignature, secondThumbnailSignature)
            XCTAssertGreaterThan(
                secondEntry.document.contentUpdatedAt,
                firstEntry.document.contentUpdatedAt
            )
            XCTAssertEqual(
                try BoardStore.loadHandDrawingDocumentData(
                    boardID: boardID,
                    documentID: runtimeState.handDrawingItems[0].documentID,
                    userDefaults: userDefaults
                ),
                secondDrawingData
            )
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(
                    try decodeHandDrawingImage(at: previewURL)
                ),
                BoardThumbnailImageSignature.describe(secondPreviewImage)
            )
            XCTAssertEqual(
                secondEntry.document.handDrawingItemRecords.first?.contentRevision,
                secondRevision
            )
            XCTAssertEqual(
                secondEntry.document.handDrawingItemRecords.first?.storage,
                .bundle
            )

            let loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedItem = try XCTUnwrap(loadedState.handDrawingItems.first)
            XCTAssertEqual(loadedItem.contentRevision, secondRevision)
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(
                    loadedItem.previewAsset.posterCGImage
                ),
                BoardThumbnailImageSignature.describe(secondPreviewImage)
            )
        }
    }

    func testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing() throws {
        try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let itemID = UUID()
            let transparentPreviewImage = try makeHandDrawingTestImage(
                red: 0,
                green: 0,
                blue: 0,
                alpha: 0
            )
            let drawingData = Data("hand-drawing-empty".utf8)
            var item = makeHandDrawingItem(
                id: itemID,
                previewImage: transparentPreviewImage,
                contentRevision: UUID(),
                isEmpty: true
            )
            item.rotationRadians = 0
            let runtimeState = makeHandDrawingRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_720_000_400),
                item: item
            )

            try BoardStore.saveBoard(
                BoardSaveSnapshot(
                    runtimeState: runtimeState,
                    transientImageAssetPayloads: [:],
                    transientHandDrawingAssetPayloads: [
                        itemID: BoardTransientHandDrawingAssetPayload(
                            itemID: itemID,
                        documentData: drawingData,
                            previewImageData: try makeHandDrawingPNGData(
                                for: transparentPreviewImage
                            )
                        )
                    ]
                ),
                userDefaults: userDefaults
            )

            let entry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let thumbnailImage = try decodeHandDrawingImage(
                at: BoardPersistedThumbnailStore.thumbnailURL(
                    forBoardDirectoryURL: entry.boardDirectoryURL
                )
            )
            let averagePixel = try sampleHandDrawingPixelColor(in: thumbnailImage)

            XCTAssertGreaterThan(averagePixel.alpha, 200)
            XCTAssertGreaterThan(averagePixel.red, 200)
            XCTAssertGreaterThan(averagePixel.green, 200)
            XCTAssertGreaterThan(averagePixel.blue, 200)
            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .bundle
            )
        }
    }

    func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
        try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let sourceItemID = UUID()
            let sourcePreviewImage = try makeHandDrawingTestImage(
                red: 0.2,
                green: 0.55,
                blue: 0.95
            )
            let sourceDrawingData = Data("hand-drawing-duplicate-source".utf8)
            let sourceItem = makeHandDrawingItem(
                id: sourceItemID,
                previewImage: sourcePreviewImage,
                contentRevision: UUID()
            )
            var runtimeState = makeHandDrawingRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_720_000_500),
                item: sourceItem
            )
            try BoardStore.saveBoard(
                BoardSaveSnapshot(
                    runtimeState: runtimeState,
                    transientImageAssetPayloads: [:],
                    transientHandDrawingAssetPayloads: [
                        sourceItemID: BoardTransientHandDrawingAssetPayload(
                            itemID: sourceItemID,
                            documentData: sourceDrawingData,
                            previewImageData: try makeHandDrawingPNGData(
                                for: sourcePreviewImage
                            )
                        )
                    ]
                ),
                userDefaults: userDefaults
            )

            let duplicatedHandDrawingItem = sourceItem.duplicated(
                offsetInWorld: CGPoint(x: 42, y: 24)
            )
            runtimeState.items = [
                .handDrawing(sourceItem),
                .handDrawing(duplicatedHandDrawingItem)
            ]
            let duplicatedSnapshot = BoardSaveSnapshot(
                runtimeState: runtimeState,
                transientImageAssetPayloads: [:],
                transientHandDrawingAssetPayloads: [
                    duplicatedHandDrawingItem.id: BoardTransientHandDrawingAssetPayload(
                        itemID: duplicatedHandDrawingItem.id,
                        documentData: sourceDrawingData,
                        previewCGImage: duplicatedHandDrawingItem.previewAsset.posterCGImage
                    )
                ]
            )

            XCTAssertNotEqual(duplicatedHandDrawingItem.id, sourceItemID)
            XCTAssertNotEqual(
                duplicatedHandDrawingItem.previewImageFilename,
                sourceItem.previewImageFilename
            )
            XCTAssertNotEqual(
                duplicatedHandDrawingItem.sourceDrawingFilename,
                sourceItem.sourceDrawingFilename
            )

            try BoardStore.saveBoard(duplicatedSnapshot, userDefaults: userDefaults)
            let entry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let sourceBundleLocator = HandDrawingBundleLocator(
                documentID: sourceItem.documentID
            )
            let duplicatedBundleLocator = HandDrawingBundleLocator(
                documentID: duplicatedHandDrawingItem.documentID
            )

            let sourceReloadedData = try BoardStore.loadHandDrawingDocumentData(
                boardID: boardID,
                documentID: sourceItem.documentID,
                userDefaults: userDefaults
            )
            let duplicatedReloadedData = try BoardStore.loadHandDrawingDocumentData(
                boardID: boardID,
                documentID: duplicatedHandDrawingItem.documentID,
                userDefaults: userDefaults
            )
            let loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedSourceItem = try XCTUnwrap(
                loadedState.handDrawingItems.first { $0.id == sourceItemID }
            )
            let loadedDuplicatedItem = try XCTUnwrap(
                loadedState.handDrawingItems.first {
                    $0.id == duplicatedHandDrawingItem.id
                }
            )

            XCTAssertEqual(sourceReloadedData, sourceDrawingData)
            XCTAssertEqual(duplicatedReloadedData, sourceDrawingData)
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: sourceBundleLocator.bundleDirectoryURL(in: entry.boardDirectoryURL)
                )
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: duplicatedBundleLocator.bundleDirectoryURL(
                        in: entry.boardDirectoryURL
                    )
                )
            )
            XCTAssertEqual(loadedSourceItem.documentID, sourceItem.documentID)
            XCTAssertEqual(
                loadedDuplicatedItem.documentID,
                duplicatedHandDrawingItem.documentID
            )
            XCTAssertEqual(
                loadedSourceItem.previewAsset.reference.stableAssetFilename,
                sourceItem.previewImageFilename
            )
            XCTAssertEqual(
                loadedDuplicatedItem.previewAsset.reference.stableAssetFilename,
                duplicatedHandDrawingItem.previewImageFilename
            )
            XCTAssertEqual(
                Set(entry.document.handDrawingItemRecords.map(\.storage)),
                [.bundle]
            )
        }
    }

    func testBoardStoreLoadHandDrawingSourceDataFallsBackToLegacyFlatAssets() throws {
        try withTemporaryHandDrawingBoardWorkspace { selectedFolderURL, userDefaults in
            let boardID = UUID()
            let documentID = UUID()
            let boardDirectoryURL = selectedFolderURL
                .appendingPathComponent(
                    SelectedFolderAccess.workspaceDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(
                    SelectedFolderAccess.boardsDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(boardID.uuidString, isDirectory: true)
            let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
                "assets",
                isDirectory: true
            )
            try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)

            let legacyAssetLocator = BoardHandDrawingAssetLocator(
                documentID: documentID
            )
            let legacyDrawingData = Data("legacy-hand-drawing".utf8)
            let previewImage = try makeHandDrawingTestImage(
                red: 0.4,
                green: 0.5,
                blue: 0.6
            )
            try CoordinatedFileIO.writeData(
                legacyDrawingData,
                to: legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
            )
            try CoordinatedFileIO.writeData(
                try makeHandDrawingPNGData(for: previewImage),
                to: legacyAssetLocator.previewImageURL(in: assetsDirectoryURL)
            )

            let legacyItemRecord = BoardHandDrawingItemRecord(
                id: UUID(),
                documentID: documentID,
                center: BoardPointRecord(CGPoint(x: 80, y: 80)),
                size: BoardSizeRecord(CGSize(width: 160, height: 160)),
                zIndex: 1,
                paper: BoardHandDrawingPaperRecord(.square),
                isEmpty: false,
                contentRevision: UUID(),
                rotationRadians: 0,
                storage: .legacyFlatAssetPair
            )
            let document = BoardDocument(
                formatVersion: BoardDocument.currentFormatVersion,
                boardID: boardID,
                title: "Legacy Hand Drawing",
                createdAt: Date(timeIntervalSince1970: 1_720_100_000),
                contentUpdatedAt: Date(timeIntervalSince1970: 1_720_100_000),
                viewStateUpdatedAt: Date(timeIntervalSince1970: 1_720_100_000),
                boardBaseSize: BoardSizeRecord(CGSize(width: 160, height: 160)),
                boardRect: BoardRectRecord(CGRect(x: 0, y: 0, width: 160, height: 160)),
                cameraCenter: BoardPointRecord(CGPoint(x: 80, y: 80)),
                cameraZoomScale: 1,
                workspaceMode: .editing,
                items: [.handDrawing(legacyItemRecord)]
            )
            try CoordinatedFileIO.writeData(
                try makeBoardDocumentData(document),
                to: boardDirectoryURL.appendingPathComponent("board.json")
            )

            XCTAssertEqual(
                try BoardStore.loadHandDrawingDocumentData(
                    boardID: boardID,
                    documentID: documentID,
                    userDefaults: userDefaults
                ),
                legacyDrawingData
            )

            var loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedItem = try XCTUnwrap(loadedState.handDrawingItems.first)
            XCTAssertEqual(loadedItem.documentID, documentID)

            var updatedLegacyItem = loadedItem
            updatedLegacyItem.center = CGPoint(x: 96, y: 104)
            loadedState.items = [.handDrawing(updatedLegacyItem)]
            try BoardStore.saveBoard(loadedState, userDefaults: userDefaults)

            let entry = try XCTUnwrap(
                BoardStore.loadBoardDocumentEntry(id: boardID, userDefaults: userDefaults)
            )
            XCTAssertEqual(
                entry.document.handDrawingItemRecords.first?.storage,
                .legacyFlatAssetPair
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: legacyAssetLocator.sourceDrawingURL(in: assetsDirectoryURL)
                )
            )
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: HandDrawingBundleLocator(documentID: documentID).bundleDirectoryURL(
                        in: boardDirectoryURL
                    )
                )
            )
        }
    }
}

private enum BoardHandDrawingStorageTestError: Error {
    case invalidImageEncoding
    case invalidImageDecoding
    case invalidBitmapContext
}

private struct HandDrawingPixelColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func withTemporaryHandDrawingBoardWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "MyCanvasHandDrawingBoardStoreTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )

    let suiteName = "MyCanvasHandDrawingBoardStoreTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: handDrawingBookmarkCreationOptions(),
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

private func handDrawingBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
}

private func makeHandDrawingRuntimeState(
    boardID: UUID,
    now: Date,
    item: CanvasHandDrawingItem
) -> BoardRuntimeState {
    var runtimeState = BoardRuntimeState.makeEmpty(
        boardID: boardID,
        title: "Hand Drawing Board",
        now: now
    )
    runtimeState.items = [.handDrawing(item)]
    return runtimeState
}

private func makeHandDrawingItem(
    id: UUID,
    documentID: HandDrawingDocumentID? = nil,
    previewImage: CGImage,
    contentRevision: UUID,
    isEmpty: Bool = false
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: id,
        documentID: documentID,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: documentID ?? id,
            cgImage: previewImage
        ),
        isEmpty: isEmpty,
        contentRevision: contentRevision,
        center: CGPoint(x: 160, y: 160),
        size: CGSize(width: 320, height: 320),
        zIndex: 2,
        rotationRadians: 0.25
    )
}

private func decodeHandDrawingImage(at url: URL) throws -> CGImage {
    let data = try CoordinatedFileIO.readData(at: url)
    guard
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw BoardHandDrawingStorageTestError.invalidImageDecoding
    }
    return image
}

private func makeHandDrawingPNGData(for image: CGImage) throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw BoardHandDrawingStorageTestError.invalidImageEncoding
    }

    CGImageDestinationAddImage(imageDestination, image, nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw BoardHandDrawingStorageTestError.invalidImageEncoding
    }
    return mutableData as Data
}

private func makeBoardDocumentData(_ document: BoardDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(document)
}

private func sampleHandDrawingPixelColor(
    in image: CGImage
) throws -> HandDrawingPixelColor {
    var pixelBytes = [UInt8](repeating: 0, count: 4)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: &pixelBytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw BoardHandDrawingStorageTestError.invalidBitmapContext
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return HandDrawingPixelColor(
        red: pixelBytes[0],
        green: pixelBytes[1],
        blue: pixelBytes[2],
        alpha: pixelBytes[3]
    )
}

private func makeHandDrawingTestImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1,
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
        throw BoardHandDrawingStorageTestError.invalidBitmapContext
    }

    context.setFillColor(
        red: red,
        green: green,
        blue: blue,
        alpha: alpha
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        throw BoardHandDrawingStorageTestError.invalidBitmapContext
    }
    return image
}
