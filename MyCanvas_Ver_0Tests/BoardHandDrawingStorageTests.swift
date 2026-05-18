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
            let previewImage = try makeHandDrawingTestImage(
                red: 0.9,
                green: 0.1,
                blue: 0.2
            )
            let drawingData = Data("hand-drawing-v1".utf8)
            let item = makeHandDrawingItem(
                id: itemID,
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
                        drawingData: drawingData,
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

            let assetLocator = BoardHandDrawingAssetLocator(itemID: itemID)
            let previewURL = assetLocator.previewImageURL(in: assetsDirectoryURL)
            let sourceURL = assetLocator.sourceDrawingURL(in: assetsDirectoryURL)
            XCTAssertEqual(
                try CoordinatedFileIO.readData(at: sourceURL),
                drawingData
            )
            XCTAssertNotNil(try CoordinatedFileIO.modificationDate(at: previewURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanPreviewURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanDrawingURL))

            let loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedItem = try XCTUnwrap(loadedState.handDrawingItems.first)
            XCTAssertEqual(loadedItem.id, item.id)
            XCTAssertEqual(loadedItem.paper, item.paper)
            XCTAssertEqual(loadedItem.isEmpty, item.isEmpty)
            XCTAssertEqual(loadedItem.contentRevision, item.contentRevision)
            XCTAssertEqual(
                loadedItem.previewAsset.reference.stableAssetFilename,
                assetLocator.previewImageFilename
            )
            XCTAssertEqual(
                BoardThumbnailImageSignature.describe(
                    loadedItem.previewAsset.posterCGImage
                ),
                BoardThumbnailImageSignature.describe(previewImage)
            )
            XCTAssertEqual(
                try BoardStore.loadHandDrawingSourceData(
                    boardID: boardID,
                    itemID: itemID,
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

            let assetLocator = BoardHandDrawingAssetLocator(itemID: itemID)
            var runtimeState = makeHandDrawingRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_720_000_200),
                item: makeHandDrawingItem(
                    id: itemID,
                    previewImage: firstPreviewImage,
                    contentRevision: firstRevision
                )
            )
            try BoardStore.saveBoard(
                BoardSaveSnapshot(
                    runtimeState: runtimeState,
                    transientImageAssetPayloads: [:],
                    transientHandDrawingAssetPayloads: [
                        itemID: BoardTransientHandDrawingAssetPayload(
                            itemID: itemID,
                            drawingData: firstDrawingData,
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
                            drawingData: secondDrawingData,
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
            let previewURL = assetLocator.previewImageURL(
                in: secondEntry.assetsDirectoryURL
            )

            XCTAssertNotEqual(firstThumbnailSignature, secondThumbnailSignature)
            XCTAssertGreaterThan(
                secondEntry.document.contentUpdatedAt,
                firstEntry.document.contentUpdatedAt
            )
            XCTAssertEqual(
                try BoardStore.loadHandDrawingSourceData(
                    boardID: boardID,
                    itemID: itemID,
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
                            drawingData: sourceDrawingData,
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
                        drawingData: sourceDrawingData,
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

            let sourceReloadedData = try BoardStore.loadHandDrawingSourceData(
                boardID: boardID,
                itemID: sourceItemID,
                userDefaults: userDefaults
            )
            let duplicatedReloadedData = try BoardStore.loadHandDrawingSourceData(
                boardID: boardID,
                itemID: duplicatedHandDrawingItem.id,
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
            XCTAssertEqual(
                loadedSourceItem.previewAsset.reference.stableAssetFilename,
                sourceItem.previewImageFilename
            )
            XCTAssertEqual(
                loadedDuplicatedItem.previewAsset.reference.stableAssetFilename,
                duplicatedHandDrawingItem.previewImageFilename
            )
        }
    }
}

private enum BoardHandDrawingStorageTestError: Error {
    case invalidImageEncoding
    case invalidImageDecoding
    case invalidBitmapContext
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
    previewImage: CGImage,
    contentRevision: UUID,
    isEmpty: Bool = false
) -> CanvasHandDrawingItem {
    CanvasHandDrawingItem(
        id: id,
        paper: .square,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: id,
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
