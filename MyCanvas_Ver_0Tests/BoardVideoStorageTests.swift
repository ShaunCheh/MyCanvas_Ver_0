import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class BoardVideoStorageTests: XCTestCase {
    func testBoardDocumentMapperRoundTripsVideoPosterMetadata() throws {
        let boardID = UUID()
        let itemID = UUID()
        let posterImage = try makeSolidColorImage(red: 1, green: 0, blue: 0)
        let item = makeVideoItem(
            id: itemID,
            posterAsset: .persistedStaticImage(
                filename: "video-poster.png",
                cgImage: posterImage
            ),
            sourceVideoFilename: "clip.mov",
            posterTimeSeconds: 12.5
        )
        var runtimeState = makeRuntimeState(
            boardID: boardID,
            now: Date(timeIntervalSince1970: 1_710_000_000),
            item: item
        )
        runtimeState.title = "Video Mapper"
        runtimeState.contentUpdatedAt = Date(timeIntervalSince1970: 1_710_000_123)
        runtimeState.viewStateUpdatedAt = Date(timeIntervalSince1970: 1_710_000_123)

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let imageRecord = try XCTUnwrap(document.imageItemRecords.first)

        XCTAssertEqual(imageRecord.posterImageFilename, "video-poster.png")
        XCTAssertEqual(imageRecord.sourceVideoFilename, "clip.mov")
        XCTAssertEqual(imageRecord.posterTimeSeconds, 12.5)
        XCTAssertEqual(
            imageRecord.referencedAssetFilenames,
            Set(["video-poster.png", "clip.mov"])
        )
        XCTAssertEqual(
            document.referencedAssetFilenames,
            Set(["video-poster.png", "clip.mov"])
        )

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                posterImage
            }
        )
        let roundTrippedItem = try XCTUnwrap(roundTrippedState.imageItems.first)

        XCTAssertTrue(roundTrippedItem.isVideo)
        XCTAssertEqual(
            roundTrippedItem.assetReference.stableAssetFilename,
            "video-poster.png"
        )
        XCTAssertEqual(roundTrippedItem.sourceVideoFilename, "clip.mov")
        XCTAssertEqual(roundTrippedItem.posterTimeSeconds, 12.5)
        XCTAssertEqual(
            roundTrippedItem.cropRectNormalized.cgRect,
            item.cropRectNormalized.cgRect
        )
        XCTAssertEqual(roundTrippedItem.rotationRadians, item.rotationRadians)
    }

    func testBoardStoreSaveLoadAndCleanupPreservesVideoPosterAndSourceAssets() throws {
        try withTemporaryBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let posterAssetID = UUID()
            let sourceVideoFilename = "source-video.mov"
            let posterImage = try makeSolidColorImage(red: 1, green: 0.2, blue: 0)
            let item = makeVideoItem(
                id: UUID(),
                posterAsset: .transientStaticImage(
                    cgImage: posterImage,
                    assetID: posterAssetID
                ),
                sourceVideoFilename: sourceVideoFilename,
                posterTimeSeconds: 2.75
            )
            let runtimeState = makeRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_710_000_200),
                item: item
            )

            let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID,
                userDefaults: userDefaults
            )
            let sourceVideoURL = assetsDirectoryURL.appendingPathComponent(
                sourceVideoFilename
            )
            try writeDummyVideoAsset(to: sourceVideoURL)

            let orphanPosterURL = assetsDirectoryURL.appendingPathComponent(
                "orphan-poster.png"
            )
            try CoordinatedFileIO.writeData(
                Data("orphan-poster".utf8),
                to: orphanPosterURL
            )
            let orphanVideoURL = assetsDirectoryURL.appendingPathComponent(
                "orphan-video.mov"
            )
            try CoordinatedFileIO.writeData(
                Data("orphan-video".utf8),
                to: orphanVideoURL
            )

            try BoardStore.saveBoard(runtimeState, userDefaults: userDefaults)

            let posterAssetURL = assetsDirectoryURL.appendingPathComponent(
                item.assetReference.stableAssetFilename
            )
            XCTAssertNotNil(try CoordinatedFileIO.modificationDate(at: posterAssetURL))
            XCTAssertNotNil(try CoordinatedFileIO.modificationDate(at: sourceVideoURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanPosterURL))
            XCTAssertNil(try CoordinatedFileIO.modificationDate(at: orphanVideoURL))

            let loadedState = try BoardStore.loadBoard(
                id: boardID,
                userDefaults: userDefaults
            )
            let loadedItem = try XCTUnwrap(loadedState.imageItems.first)

            XCTAssertTrue(loadedItem.isVideo)
            XCTAssertEqual(
                loadedItem.assetReference.stableAssetFilename,
                item.assetReference.stableAssetFilename
            )
            XCTAssertEqual(loadedItem.sourceVideoFilename, sourceVideoFilename)
            XCTAssertEqual(loadedItem.posterTimeSeconds, 2.75)
        }
    }

    func testBoardStoreLoadsStorageSizeSummaryOnDemand() throws {
        try withTemporaryBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let sourceVideoFilename = "source-video.mov"
            let posterImage = try makeSolidColorImage(red: 0.2, green: 0.4, blue: 1)
            let item = makeVideoItem(
                id: UUID(),
                posterAsset: .transientStaticImage(
                    cgImage: posterImage,
                    assetID: UUID()
                ),
                sourceVideoFilename: sourceVideoFilename,
                posterTimeSeconds: 4.5
            )
            let runtimeState = makeRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_710_000_300),
                item: item
            )

            let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID,
                userDefaults: userDefaults
            )
            try writeDummyVideoAsset(
                to: assetsDirectoryURL.appendingPathComponent(sourceVideoFilename)
            )
            try BoardStore.saveBoard(runtimeState, userDefaults: userDefaults)

            let catalogItem = try XCTUnwrap(
                try BoardCatalogLoader(userDefaults: userDefaults)
                    .loadCatalogItem(boardID: boardID)
            )
            let summary = try BoardStore.loadBoardStorageSizeSummary(
                id: boardID,
                userDefaults: userDefaults
            )
            let byteCount = try XCTUnwrap(summary.byteCount)

            XCTAssertGreaterThan(byteCount, 0)
            XCTAssertEqual(catalogItem.boardID, boardID)
            XCTAssertTrue(summary.displayText.hasPrefix("Size: "))
        }
    }

    func testBoardStoreRefreshesPersistedThumbnailWhenVideoPosterChanges() throws {
        try withTemporaryBoardWorkspace { _, userDefaults in
            let boardID = UUID()
            let itemID = UUID()
            let sourceVideoFilename = "source-video.mov"
            let firstPosterAssetID = UUID()
            let secondPosterAssetID = UUID()
            let firstPosterImage = try makeSolidColorImage(red: 1, green: 0, blue: 0)
            let secondPosterImage = try makeSolidColorImage(red: 0, green: 0, blue: 1)

            let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID,
                userDefaults: userDefaults
            )
            try writeDummyVideoAsset(
                to: assetsDirectoryURL.appendingPathComponent(sourceVideoFilename)
            )

            var runtimeState = makeRuntimeState(
                boardID: boardID,
                now: Date(timeIntervalSince1970: 1_710_000_400),
                item: makeVideoItem(
                    id: itemID,
                    posterAsset: .transientStaticImage(
                        cgImage: firstPosterImage,
                        assetID: firstPosterAssetID
                    ),
                    sourceVideoFilename: sourceVideoFilename,
                    posterTimeSeconds: 1.25
                )
            )
            try BoardStore.saveBoard(runtimeState, userDefaults: userDefaults)

            let firstEntry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let thumbnailURL = BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: firstEntry.boardDirectoryURL
            )
            let firstThumbnailSignature = BoardThumbnailImageSignature.describe(
                try decodeImage(at: thumbnailURL)
            )
            let firstPosterFilename = runtimeState.imageItems[0]
                .assetReference
                .stableAssetFilename

            runtimeState.items = [
                .image(
                    makeVideoItem(
                        id: itemID,
                        posterAsset: .transientStaticImage(
                            cgImage: secondPosterImage,
                            assetID: secondPosterAssetID
                        ),
                        sourceVideoFilename: sourceVideoFilename,
                        posterTimeSeconds: 8.5
                    )
                )
            ]
            try BoardStore.saveBoard(runtimeState, userDefaults: userDefaults)

            let secondEntry = try XCTUnwrap(
                BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
            )
            let secondThumbnailSignature = BoardThumbnailImageSignature.describe(
                try decodeImage(
                    at: BoardPersistedThumbnailStore.thumbnailURL(
                        forBoardDirectoryURL: secondEntry.boardDirectoryURL
                    )
                )
            )
            let secondPosterFilename = runtimeState.imageItems[0]
                .assetReference
                .stableAssetFilename

            XCTAssertNotEqual(firstThumbnailSignature, secondThumbnailSignature)
            XCTAssertNil(
                try CoordinatedFileIO.modificationDate(
                    at: secondEntry.assetsDirectoryURL.appendingPathComponent(
                        firstPosterFilename
                    )
                )
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: secondEntry.assetsDirectoryURL.appendingPathComponent(
                        secondPosterFilename
                    )
                )
            )
            XCTAssertNotNil(
                try CoordinatedFileIO.modificationDate(
                    at: secondEntry.assetsDirectoryURL.appendingPathComponent(
                        sourceVideoFilename
                    )
                )
            )
        }
    }

    func testBoardMediaPosterImageResolverLoadsVideoPosterWithoutReadingVideoBytes() throws {
        let fileManager = FileManager.default
        let assetsDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "BoardVideoStorageTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: assetsDirectoryURL,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: assetsDirectoryURL)
        }

        let posterImage = try makeSolidColorImage(red: 0, green: 0.8, blue: 0.2)
        let posterFilename = "video-poster.png"
        try CoordinatedFileIO.writeData(
            try makePNGData(for: posterImage),
            to: assetsDirectoryURL.appendingPathComponent(posterFilename)
        )

        let imageRecord = BoardImageItemRecord(
            id: UUID(),
            center: BoardPointRecord(x: 0, y: 0),
            size: BoardSizeRecord(width: 320, height: 180),
            zIndex: 0,
            assetFilename: posterFilename,
            assetKind: .staticImage,
            posterImageFilename: posterFilename,
            sourceVideoFilename: "missing-source-video.mov",
            posterTimeSeconds: 0.5,
            cropRectNormalized: nil,
            rotationRadians: nil
        )

        let resolvedImage = try BoardMediaPosterImageResolver().resolvePreviewImage(
            for: imageRecord,
            assetsDirectoryURL: assetsDirectoryURL,
            animatedImagePreviewMode: .posterFrameOnly,
            maxPixelSize: 64
        )

        XCTAssertEqual(
            BoardThumbnailImageSignature.describe(resolvedImage),
            BoardThumbnailImageSignature.describe(posterImage)
        )
    }
}

private enum BoardVideoStorageTestError: Error {
    case invalidBitmapContext
    case invalidImageEncoding
    case invalidImageDecoding
}

private func withTemporaryBoardWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "MyCanvasBoardStoreTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )

    let suiteName = "MyCanvasBoardStoreTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: bookmarkCreationOptions(),
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

private func bookmarkCreationOptions() -> URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
}

private func makeRuntimeState(
    boardID: UUID,
    now: Date,
    item: CanvasImageItem
) -> BoardRuntimeState {
    var runtimeState = BoardRuntimeState.makeEmpty(
        boardID: boardID,
        title: "Video Board",
        now: now
    )
    runtimeState.items = [.image(item)]
    return runtimeState
}

private func makeVideoItem(
    id: UUID,
    posterAsset: CanvasImageAsset,
    sourceVideoFilename: String,
    posterTimeSeconds: Double
) -> CanvasImageItem {
    CanvasImageItem(
        id: id,
        asset: posterAsset,
        videoSource: CanvasVideoSource(
            assetReference: .persisted(filename: sourceVideoFilename)
        ),
        posterTimeSeconds: posterTimeSeconds,
        center: CGPoint(x: 160, y: 90),
        size: CGSize(width: 320, height: 180),
        zIndex: 4,
        cropRectNormalized: CanvasImageCropRect(
            CGRect(x: 0.1, y: 0.15, width: 0.7, height: 0.6)
        ),
        rotationRadians: 0.35
    )
}

private func writeDummyVideoAsset(to url: URL) throws {
    try CoordinatedFileIO.writeData(Data("video-bytes".utf8), to: url)
}

private func decodeImage(at url: URL) throws -> CGImage {
    let data = try CoordinatedFileIO.readData(at: url)
    guard
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw BoardVideoStorageTestError.invalidImageDecoding
    }
    return image
}

private func makePNGData(for image: CGImage) throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw BoardVideoStorageTestError.invalidImageEncoding
    }

    CGImageDestinationAddImage(imageDestination, image, nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw BoardVideoStorageTestError.invalidImageEncoding
    }
    return mutableData as Data
}

private func makeSolidColorImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1,
    size: CGSize = CGSize(width: 48, height: 32)
) throws -> CGImage {
    let width = max(Int(size.width), 1)
    let height = max(Int(size.height), 1)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    else {
        throw BoardVideoStorageTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
    )

    guard let image = context.makeImage() else {
        throw BoardVideoStorageTestError.invalidBitmapContext
    }
    return image
}
