import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasGIFFrameImportBuilderTests: XCTestCase {
    func testBuilderCreatesStaticGridRequestFromSelectedGIFFrames() throws {
        let gifData = try makeGIFFrameImportTestGIFData(
            frames: [
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.1
                ),
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 0,
                        green: 1,
                        blue: 0
                    ),
                    delayTime: 0.1
                ),
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 0,
                        green: 0,
                        blue: 1
                    ),
                    delayTime: 0.1
                )
            ]
        )
        let cropRect = CanvasImageCropRect(
            CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.7)
        )
        let sourceItem = CanvasImageItem(
            asset: CanvasImageAsset.transientAnimatedGIF(
                posterCGImage: try makeGIFFrameImportTestImage(
                    red: 1,
                    green: 0,
                    blue: 0
                )
            ),
            center: CGPoint(x: 120, y: 200),
            size: CGSize(width: 180, height: 120),
            zIndex: 0,
            cropRectNormalized: cropRect,
            rotationRadians: .pi / 6
        )
        let configuration = CanvasGIFFrameImportConfiguration(
            selectionGrid: CanvasGIFFrameImportConfiguration.current.selectionGrid,
            boardPlacementGrid: CanvasGIFFrameImportGridConfiguration(
                columns: 2,
                horizontalSpacing: 30,
                verticalSpacing: 40,
                contentInsets: CanvasGIFFrameImportInsets(
                    top: 18,
                    leading: 12,
                    bottom: 26,
                    trailing: 10
                )
            ),
            thumbnailMaxPixelSize: 240
        )

        let request = try CanvasGIFFrameImportBuilder.makeImportRequest(
            from: sourceItem,
            gifData: gifData,
            selectedFrameIndices: [2, 0, 2],
            configuration: configuration
        )

        let importedImages = try request.resolvedImagesForTesting()
        XCTAssertEqual(importedImages.count, 2)
        XCTAssertEqual(importedImages[0].assetKind, .staticImage)
        XCTAssertNil(importedImages[0].importedSource)
        XCTAssertNil(importedImages[0].animatedMetadata)
        XCTAssertEqual(importedImages[1].assetKind, .staticImage)

        let firstPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[0].cgImage
        )
        let secondPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[1].cgImage
        )
        XCTAssertGreaterThan(firstPixel.red, firstPixel.green)
        XCTAssertGreaterThan(firstPixel.red, firstPixel.blue)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.red)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.green)

        let expectedPlacement = CGPoint(
            x: sourceItem.worldBounds.minX + 12 + sourceItem.size.width / 2,
            y: sourceItem.worldBounds.maxY + 18 + sourceItem.size.height / 2
        )
        guard case let .worldPoint(actualPlacement) = request.placement else {
            return XCTFail("Expected worldPoint placement.")
        }
        XCTAssertEqual(actualPlacement, expectedPlacement)

        let gridConfiguration = try XCTUnwrap(request.layout.gridConfiguration)
        XCTAssertEqual(gridConfiguration.columns, 2)
        XCTAssertEqual(gridConfiguration.horizontalSpacing, 30)
        XCTAssertEqual(gridConfiguration.verticalSpacing, 40)
        XCTAssertEqual(request.sourceDescription, "gif-derived frames")

        let template = try XCTUnwrap(request.presentationTemplate)
        XCTAssertEqual(template.size, sourceItem.size)
        XCTAssertEqual(template.cropRectNormalized, cropRect)
        XCTAssertEqual(
            template.resolvedRotationRadians(
                assetDefaultRadians: sourceItem.rotationRadians
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testSessionGIFFrameImportRequestUsesTransientPayloadSourceData() throws {
        let session = makeGIFFrameImportTestSession()
        XCTAssertNil(session.activeBoardID)

        let gifData = try makeGIFFrameImportTestGIFData(
            frames: [
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.1
                ),
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 0,
                        green: 1,
                        blue: 0
                    ),
                    delayTime: 0.1
                ),
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 0,
                        green: 0,
                        blue: 1
                    ),
                    delayTime: 0.1
                )
            ]
        )
        let cropRect = CanvasImageCropRect(
            CGRect(x: 0.15, y: 0.2, width: 0.55, height: 0.6)
        )
        let sourceImage = try XCTUnwrap(
            CanvasResolvedImportImage(
                data: gifData,
                typeIdentifier: UTType.gif.identifier,
                filenameHint: "transient-source.gif"
            )
        )
        let importedItem = try XCTUnwrap(
            session.appendImportedMedia(
                [.image(sourceImage)],
                placement: .worldPoint(CGPoint(x: 60, y: 80)),
                layout: .stacked,
                presentationTemplate: CanvasImportPresentationTemplate(
                    size: CGSize(width: 160, height: 110),
                    cropRectNormalized: cropRect,
                    rotationPolicy: .fixed(.pi / 3)
                )
            ).first
        )

        let request = try session.gifFrameImportRequest(
            for: importedItem.id,
            frameIndices: [1, 2]
        )
        let importedImages = try request.resolvedImagesForTesting()

        XCTAssertEqual(importedImages.count, 2)
        let firstPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[0].cgImage
        )
        let secondPixel = try sampleGIFFrameImportPixelColor(
            in: importedImages[1].cgImage
        )
        XCTAssertGreaterThan(firstPixel.green, firstPixel.red)
        XCTAssertGreaterThan(firstPixel.green, firstPixel.blue)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.red)
        XCTAssertGreaterThan(secondPixel.blue, secondPixel.green)

        let template = try XCTUnwrap(request.presentationTemplate)
        XCTAssertEqual(template.size, importedItem.size)
        XCTAssertEqual(template.cropRectNormalized, importedItem.cropRectNormalized)
        XCTAssertEqual(
            template.resolvedRotationRadians(
                assetDefaultRadians: importedItem.rotationRadians
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testSessionGIFFrameImportRequestFallsBackToPersistedGIFAssetData() throws {
        try withTemporaryGIFFrameImportWorkspace { _, userDefaults in
            let session = makeGIFFrameImportTestSession()
            session.startNewBoard(
                now: Date(timeIntervalSince1970: 1_710_001_000)
            )
            let boardID = try XCTUnwrap(session.activeBoardID)
            let gifData = try makeGIFFrameImportTestGIFData(
                frames: [
                    GIFFrameImportTestSpec(
                        image: try makeGIFFrameImportTestImage(
                            red: 1,
                            green: 0,
                            blue: 0
                        ),
                        delayTime: 0.1
                    ),
                    GIFFrameImportTestSpec(
                        image: try makeGIFFrameImportTestImage(
                            red: 0,
                            green: 1,
                            blue: 0
                        ),
                        delayTime: 0.1
                    )
                ]
            )
            let persistedFilename = "persisted-source.gif"
            let posterImage = try makeGIFFrameImportTestImage(
                red: 1,
                green: 0,
                blue: 0
            )
            let sourceItem = CanvasImageItem(
                asset: CanvasImageAsset(
                    reference: .persistedAnimatedGIF(filename: persistedFilename),
                    poster: CanvasImagePoster(cgImage: posterImage),
                    logicalPixelSize: CGSize(
                        width: posterImage.width,
                        height: posterImage.height
                    )
                ),
                center: CGPoint(x: 45, y: 70),
                size: CGSize(width: 140, height: 90),
                zIndex: 0,
                cropRectNormalized: CanvasImageCropRect(
                    CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
                ),
                rotationRadians: 0.45
            )
            session.scene.append(sourceItem)

            let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID,
                userDefaults: userDefaults
            )
            try CoordinatedFileIO.writeData(
                gifData,
                to: assetsDirectoryURL.appendingPathComponent(
                    persistedFilename
                )
            )

            let request = try session.gifFrameImportRequest(
                for: sourceItem.id,
                frameIndices: [1],
                userDefaults: userDefaults
            )
            let importedImages = try request.resolvedImagesForTesting()
            XCTAssertEqual(importedImages.count, 1)

            let pixel = try sampleGIFFrameImportPixelColor(
                in: importedImages[0].cgImage
            )
            XCTAssertGreaterThan(pixel.green, pixel.red)
            XCTAssertGreaterThan(pixel.green, pixel.blue)
        }
    }
}

private enum CanvasGIFFrameImportBuilderTestError: Error {
    case invalidBitmapContext
    case invalidImageDestination
    case invalidImageEncoding
    case unexpectedImportItemKind
}

private enum CanvasGIFFrameImportBuilderTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private struct GIFFrameImportTestSpec {
    let image: CGImage
    let delayTime: TimeInterval
}

private struct GIFFrameImportPixelColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func makeGIFFrameImportTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasGIFFrameImportBuilderTests",
        logPrefix: "[CanvasGIFFrameImportBuilderTests]"
    )
    CanvasGIFFrameImportBuilderTestRetainer.sessions.append(session)
    return session
}

private func withTemporaryGIFFrameImportWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let selectedFolderURL = fileManager.temporaryDirectory.appendingPathComponent(
        "CanvasGIFFrameImportBuilderTests-\(identifier)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: selectedFolderURL,
        withIntermediateDirectories: true
    )

    let suiteName = "CanvasGIFFrameImportBuilderTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Failed to create isolated UserDefaults suite.")
        return
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    let bookmarkData = try selectedFolderURL.bookmarkData(
        options: gifFrameImportBookmarkCreationOptions(),
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

private func gifFrameImportBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
}

private func makeGIFFrameImportTestGIFData(
    frames: [GIFFrameImportTestSpec],
    loopCount: Int = 0
) throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        )
    else {
        throw CanvasGIFFrameImportBuilderTestError.invalidImageDestination
    }

    CGImageDestinationSetProperties(
        imageDestination,
        [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]
        ] as CFDictionary
    )

    for frame in frames {
        CGImageDestinationAddImage(
            imageDestination,
            frame.image,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: frame.delayTime,
                    kCGImagePropertyGIFDelayTime: frame.delayTime
                ]
            ] as CFDictionary
        )
    }

    guard CGImageDestinationFinalize(imageDestination) else {
        throw CanvasGIFFrameImportBuilderTestError.invalidImageEncoding
    }
    return mutableData as Data
}

private func makeGIFFrameImportTestImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1,
    size: CGSize = CGSize(width: 24, height: 16)
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
        throw CanvasGIFFrameImportBuilderTestError.invalidBitmapContext
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
        throw CanvasGIFFrameImportBuilderTestError.invalidBitmapContext
    }
    return image
}

private func sampleGIFFrameImportPixelColor(
    in image: CGImage
) throws -> GIFFrameImportPixelColor {
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
        throw CanvasGIFFrameImportBuilderTestError.invalidBitmapContext
    }

    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return GIFFrameImportPixelColor(
        red: pixelBytes[0],
        green: pixelBytes[1],
        blue: pixelBytes[2],
        alpha: pixelBytes[3]
    )
}

private extension CanvasImportRequest {
    func resolvedImagesForTesting() throws -> [CanvasResolvedImportImage] {
        try items.map { item in
            guard case let .image(image) = item else {
                throw CanvasGIFFrameImportBuilderTestError.unexpectedImportItemKind
            }
            return image
        }
    }
}
