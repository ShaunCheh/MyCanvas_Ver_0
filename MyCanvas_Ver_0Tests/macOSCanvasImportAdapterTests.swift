#if os(macOS)
import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class macOSCanvasImportAdapterTests: XCTestCase {
    func testURLImportsDefaultToAutomaticForSingleMultipleAndMixedMedia() throws {
        try withmacOSImportAdapterTestDirectory { directoryURL in
            let staticImageURL = directoryURL.appendingPathComponent(
                "static-image.png"
            )
            let animatedGIFURL = directoryURL.appendingPathComponent(
                "animated-image.gif"
            )
            let videoURL = directoryURL.appendingPathComponent(
                "video.mov"
            )
            try writemacOSImportAdapterTestPNG(to: staticImageURL)
            try writemacOSImportAdapterTestGIF(to: animatedGIFURL)
            try writemacOSImportAdapterTestVideo(to: videoURL)

            let singleRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: [staticImageURL],
                    sourceDescription: "open panel single"
                )
            )
            assertmacOSImportAdapterRequestMetadata(
                singleRequest,
                itemCount: 1,
                sourceDescription: "open panel single"
            )
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(singleRequest.items),
                [.image(.staticImage)]
            )

            let multipleImageRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: [staticImageURL, animatedGIFURL],
                    sourceDescription: "open panel multiple images"
                )
            )
            assertmacOSImportAdapterRequestMetadata(
                multipleImageRequest,
                itemCount: 2,
                sourceDescription: "open panel multiple images"
            )
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(
                    multipleImageRequest.items
                ),
                [
                    .image(.staticImage),
                    .image(.animatedGIF)
                ]
            )

            let mixedRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: [
                        staticImageURL,
                        videoURL,
                        animatedGIFURL
                    ],
                    sourceDescription: "open panel mixed media"
                )
            )
            assertmacOSImportAdapterRequestMetadata(
                mixedRequest,
                itemCount: 3,
                sourceDescription: "open panel mixed media"
            )
            XCTAssertTrue(mixedRequest.containsVideo)
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(mixedRequest.items),
                [
                    .image(.staticImage),
                    .video,
                    .image(.animatedGIF)
                ]
            )
        }
    }

    func testPasteboardDropAndPasteDefaultToAutomaticLayout() throws {
        try withmacOSImportAdapterTestDirectory { directoryURL in
            let imageURL = directoryURL.appendingPathComponent("drop.png")
            let videoURL = directoryURL.appendingPathComponent("drop.mov")
            try writemacOSImportAdapterTestPNG(to: imageURL)
            try writemacOSImportAdapterTestVideo(to: videoURL)

            let filePasteboard = NSPasteboard(
                name: NSPasteboard.Name(
                    "macOSCanvasImportAdapterTests.files.\(UUID().uuidString)"
                )
            )
            filePasteboard.clearContents()
            XCTAssertTrue(
                filePasteboard.writeObjects(
                    [imageURL as NSURL, videoURL as NSURL]
                )
            )

            let dropRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: filePasteboard,
                    sourceDescription: "drag and drop"
                )
            )
            assertmacOSImportAdapterRequestMetadata(
                dropRequest,
                itemCount: 2,
                sourceDescription: "drag and drop"
            )
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(dropRequest.items),
                [.image(.staticImage), .video]
            )

            let pastePayload = try XCTUnwrap(
                macOSCanvasPasteboardPayloadResolver.resolvedPayload(
                    from: filePasteboard,
                    sourceDescription: "pasteboard"
                )
            )
            guard case let .media(pasteRequest) = pastePayload else {
                return XCTFail("Expected media paste payload.")
            }
            assertmacOSImportAdapterRequestMetadata(
                pasteRequest,
                itemCount: 2,
                sourceDescription: "pasteboard"
            )
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(pasteRequest.items),
                [.image(.staticImage), .video]
            )

            let imagePasteboard = NSPasteboard(
                name: NSPasteboard.Name(
                    "macOSCanvasImportAdapterTests.image.\(UUID().uuidString)"
                )
            )
            imagePasteboard.clearContents()
            let copiedImage = NSImage(
                cgImage: try makemacOSImportAdapterTestImage(
                    red: 0.7,
                    green: 0.3,
                    blue: 0.1
                ),
                size: NSSize(width: 12, height: 12)
            )
            XCTAssertTrue(imagePasteboard.writeObjects([copiedImage]))

            let copiedImageRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: imagePasteboard,
                    sourceDescription: "copied bitmap"
                )
            )
            assertmacOSImportAdapterRequestMetadata(
                copiedImageRequest,
                itemCount: 1,
                sourceDescription: "copied bitmap"
            )
            XCTAssertEqual(
                macOSImportAdapterTestItemKinds(copiedImageRequest.items),
                [.image(.staticImage)]
            )
        }
    }

    func testMixedAdapterRequestStaysAutomaticThroughImportServiceAndSession() throws {
        try withmacOSImportAdapterTestBoardWorkspace {
            directoryURL,
            userDefaults in
            let imageURL = directoryURL.appendingPathComponent(
                "pipeline.png"
            )
            let videoURL = directoryURL.appendingPathComponent(
                "pipeline.mov"
            )
            let gifURL = directoryURL.appendingPathComponent(
                "pipeline.gif"
            )
            try writemacOSImportAdapterTestPNG(to: imageURL)
            try writemacOSImportAdapterTestVideo(to: videoURL)
            try writemacOSImportAdapterTestGIF(to: gifURL)

            let transferRequest = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: [imageURL, videoURL, gifURL],
                    sourceDescription: "mixed platform pipeline"
                )
            )
            let importRequest = try XCTUnwrap(
                CanvasMediaImportService.makeImportRequest(
                    from: transferRequest,
                    boardID: UUID(),
                    userDefaults: userDefaults
                )
            )

            XCTAssertEqual(importRequest.placement, .cameraCenter)
            XCTAssertEqual(importRequest.layout, .automatic)
            XCTAssertEqual(importRequest.items.count, 3)

            let session = CanvasEditorSession(
                saveQueueLabel: "macOSCanvasImportAdapterTests",
                logPrefix: "[macOSCanvasImportAdapterTests]",
                userDefaults: userDefaults
            )
            macOSCanvasImportAdapterTestRetainer.sessions.append(session)
            let cameraCenter = CGPoint(x: 260, y: -140)
            session.camera = CanvasCamera(
                center: cameraCenter,
                zoomScale: 1.75,
                viewportSize: CGSize(width: 1000, height: 800)
            )

            let importedItems = session.appendImportedMedia(
                importRequest.items,
                placement: importRequest.placement,
                layout: importRequest.layout,
                presentationTemplate: importRequest.presentationTemplate
            )

            XCTAssertEqual(importedItems.count, 3)
            let firstImportedItem = try XCTUnwrap(importedItems.first)
            let lastImportedItem = try XCTUnwrap(importedItems.last)
            XCTAssertEqual(
                importedItems.map(\.isVideo),
                [false, true, false]
            )
            XCTAssertNotNil(importedItems[1].sourceVideoFilename)
            XCTAssertEqual(
                importedItems.map(\.assetKind),
                [.staticImage, .staticImage, .animatedGIF]
            )
            XCTAssertTrue(
                importedItems.allSatisfy {
                    $0.center.y == cameraCenter.y
                }
            )
            XCTAssertEqual(
                (firstImportedItem.center.x + lastImportedItem.center.x) / 2,
                cameraCenter.x
            )
            assertmacOSImportAdapterItemsDoNotOverlap(importedItems)
        }
    }

    func testAdapterPreservesExplicitProgrammaticDiagonalLayout() throws {
        try withmacOSImportAdapterTestDirectory { directoryURL in
            let imageURL = directoryURL.appendingPathComponent(
                "programmatic.png"
            )
            try writemacOSImportAdapterTestPNG(to: imageURL)
            let placement = CGPoint(x: 80, y: 120)
            let step = CGPoint(x: -16, y: 28)

            let request = try XCTUnwrap(
                macOSCanvasImportAdapter.transferRequest(
                    from: [imageURL, imageURL, imageURL],
                    sourceDescription: "programmatic diagonal",
                    placement: .worldPoint(placement),
                    layout: .diagonal(stepInWorld: step)
                )
            )

            XCTAssertEqual(request.itemCount, 3)
            XCTAssertEqual(
                request.placement,
                .worldPoint(placement)
            )
            XCTAssertEqual(
                request.layout,
                .diagonal(stepInWorld: step)
            )
            XCTAssertEqual(
                request.sourceDescription,
                "programmatic diagonal"
            )
        }
    }
}

private enum macOSCanvasImportAdapterTestError: Error {
    case invalidBitmapContext
    case invalidImageDestination
    case failedToFinalizeImage
    case failedToAddVideoInput
    case failedToStartVideoWriter
    case videoInputTimedOut
    case failedToCreatePixelBuffer
    case failedToAppendVideoFrame
    case videoWriterTimedOut
    case failedToFinishVideoWriter
    case failedToCreateUserDefaults
}

private enum macOSCanvasImportAdapterTestItemKind: Equatable {
    case image(CanvasImageAssetKind)
    case video
}

private enum macOSCanvasImportAdapterTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

@MainActor
private func assertmacOSImportAdapterRequestMetadata(
    _ request: CanvasTransferRequest,
    itemCount: Int,
    sourceDescription: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(request.itemCount, itemCount, file: file, line: line)
    XCTAssertEqual(
        request.placement,
        .cameraCenter,
        file: file,
        line: line
    )
    XCTAssertEqual(
        request.layout,
        .automatic,
        file: file,
        line: line
    )
    XCTAssertEqual(
        request.sourceDescription,
        sourceDescription,
        file: file,
        line: line
    )
}

@MainActor
private func macOSImportAdapterTestItemKinds(
    _ items: [CanvasTransferItem]
) -> [macOSCanvasImportAdapterTestItemKind] {
    items.map { item in
        switch item {
        case let .image(image):
            return .image(image.assetKind)
        case .video:
            return .video
        }
    }
}

private func withmacOSImportAdapterTestDirectory(
    _ body: (URL) throws -> Void
) throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "macOSCanvasImportAdapterTests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    try body(directoryURL)
}

private func withmacOSImportAdapterTestBoardWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    let identifier = UUID().uuidString
    let suiteName = "macOSCanvasImportAdapterTests.\(identifier)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        throw macOSCanvasImportAdapterTestError.failedToCreateUserDefaults
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    try withmacOSImportAdapterTestDirectory { directoryURL in
        let bookmarkData = try directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        FolderBookmarkStore.save(
            bookmarkData,
            userDefaults: userDefaults
        )
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(directoryURL, userDefaults)
    }
}

@MainActor
private func assertmacOSImportAdapterItemsDoNotOverlap(
    _ items: [CanvasImageItem],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for firstIndex in items.indices {
        for secondIndex in items.indices where secondIndex > firstIndex {
            XCTAssertFalse(
                items[firstIndex].worldBounds.intersects(
                    items[secondIndex].worldBounds
                ),
                "Items \(firstIndex) and \(secondIndex) overlap.",
                file: file,
                line: line
            )
        }
    }
}

private func writemacOSImportAdapterTestPNG(
    to url: URL
) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw macOSCanvasImportAdapterTestError.invalidImageDestination
    }

    CGImageDestinationAddImage(
        destination,
        try makemacOSImportAdapterTestImage(
            red: 0.2,
            green: 0.6,
            blue: 0.9
        ),
        nil
    )
    guard CGImageDestinationFinalize(destination) else {
        throw macOSCanvasImportAdapterTestError.failedToFinalizeImage
    }
}

private func writemacOSImportAdapterTestGIF(
    to url: URL
) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            2,
            nil
        )
    else {
        throw macOSCanvasImportAdapterTestError.invalidImageDestination
    }

    CGImageDestinationSetProperties(
        destination,
        [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ] as CFDictionary
    )
    let frameProperties = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFDelayTime as String: 0.1
        ]
    ] as CFDictionary
    CGImageDestinationAddImage(
        destination,
        try makemacOSImportAdapterTestImage(
            red: 0.9,
            green: 0.1,
            blue: 0.2
        ),
        frameProperties
    )
    CGImageDestinationAddImage(
        destination,
        try makemacOSImportAdapterTestImage(
            red: 0.1,
            green: 0.8,
            blue: 0.3
        ),
        frameProperties
    )
    guard CGImageDestinationFinalize(destination) else {
        throw macOSCanvasImportAdapterTestError.failedToFinalizeImage
    }
}

private func makemacOSImportAdapterTestImage(
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
            width: 12,
            height: 12,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw macOSCanvasImportAdapterTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    )
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    guard let image = context.makeImage() else {
        throw macOSCanvasImportAdapterTestError.invalidBitmapContext
    }
    return image
}

private func writemacOSImportAdapterTestVideo(
    to videoURL: URL
) throws {
    let writer = try AVAssetWriter(url: videoURL, fileType: .mov)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 24,
            AVVideoHeightKey: 24
        ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(
                kCVPixelFormatType_32BGRA
            ),
            kCVPixelBufferWidthKey as String: 24,
            kCVPixelBufferHeightKey as String: 24
        ]
    )
    guard writer.canAdd(input) else {
        throw macOSCanvasImportAdapterTestError.failedToAddVideoInput
    }
    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error
            ?? macOSCanvasImportAdapterTestError.failedToStartVideoWriter
    }
    writer.startSession(atSourceTime: .zero)

    for frameIndex in 0..<3 {
        let deadline = Date().addingTimeInterval(5)
        while input.isReadyForMoreMediaData == false {
            guard Date() < deadline else {
                throw macOSCanvasImportAdapterTestError.videoInputTimedOut
            }
            Thread.sleep(forTimeInterval: 0.001)
        }

        let pixelBuffer = try makemacOSImportAdapterTestPixelBuffer(
            red: UInt8(70 + frameIndex * 40),
            green: UInt8(120 + frameIndex * 20),
            blue: UInt8(180 - frameIndex * 30)
        )
        guard adaptor.append(
            pixelBuffer,
            withPresentationTime: CMTime(
                value: CMTimeValue(frameIndex),
                timescale: 10
            )
        ) else {
            throw writer.error
                ?? macOSCanvasImportAdapterTestError.failedToAppendVideoFrame
        }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 10) == .success else {
        throw macOSCanvasImportAdapterTestError.videoWriterTimedOut
    }
    guard writer.status == .completed else {
        throw writer.error
            ?? macOSCanvasImportAdapterTestError.failedToFinishVideoWriter
    }
}

private func makemacOSImportAdapterTestPixelBuffer(
    red: UInt8,
    green: UInt8,
    blue: UInt8
) throws -> CVPixelBuffer {
    var maybePixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil,
        24,
        24,
        kCVPixelFormatType_32BGRA,
        [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ] as CFDictionary,
        &maybePixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
        throw macOSCanvasImportAdapterTestError.failedToCreatePixelBuffer
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw macOSCanvasImportAdapterTestError.failedToCreatePixelBuffer
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    for row in 0..<24 {
        for column in 0..<24 {
            let offset = row * bytesPerRow + column * 4
            buffer[offset] = blue
            buffer[offset + 1] = green
            buffer[offset + 2] = red
            buffer[offset + 3] = 255
        }
    }
    return pixelBuffer
}
#endif
