import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasGIFFrameServiceTests: XCTestCase {
    func testAnimatedMetadataReadsFrameCountDelayTimesAndLoopCount() throws {
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.2
                ),
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 0,
                        green: 0,
                        blue: 1
                    ),
                    delayTime: 0.05
                )
            ],
            loopCount: 2
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let metadata = try XCTUnwrap(
            CanvasGIFFrameService.animatedMetadata(from: imageSource)
        )

        XCTAssertEqual(metadata.frameCount, 2)
        XCTAssertEqual(metadata.frameDelayTimes.count, 2)
        XCTAssertEqual(metadata.loopCount, 2)
        XCTAssertEqual(metadata.frameDelayTimes[0], 0.2, accuracy: 0.02)
        XCTAssertEqual(metadata.frameDelayTimes[1], 0.05, accuracy: 0.02)
    }

    func testDecodeFrameReturnsRequestedFrame() throws {
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.12
                ),
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 0,
                        green: 1,
                        blue: 0
                    ),
                    delayTime: 0.12
                )
            ]
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let firstFrame = try XCTUnwrap(
            CanvasGIFFrameService.decodeFrame(at: 0, from: imageSource)
        )
        let secondFrame = try XCTUnwrap(
            CanvasGIFFrameService.decodeFrame(at: 1, from: imageSource)
        )

        let firstPixel = try samplePixelColor(in: firstFrame)
        let secondPixel = try samplePixelColor(in: secondFrame)

        XCTAssertGreaterThan(firstPixel.red, 220)
        XCTAssertLessThan(firstPixel.green, 40)
        XCTAssertLessThan(firstPixel.blue, 40)

        XCTAssertLessThan(secondPixel.red, 40)
        XCTAssertGreaterThan(secondPixel.green, 220)
        XCTAssertLessThan(secondPixel.blue, 40)
    }

    func testDecodeFrameThumbnailUsesRequestedMaxPixelSize() throws {
        let originalImage = try makeSolidColorImage(
            red: 0,
            green: 0,
            blue: 1,
            size: CGSize(width: 240, height: 120)
        )
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(image: originalImage, delayTime: 0.12),
                GIFFrameSpec(image: originalImage, delayTime: 0.12)
            ]
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let thumbnailFrame = try XCTUnwrap(
            CanvasGIFFrameService.decodeFrame(
                at: 1,
                from: imageSource,
                maxPixelSize: 80
            )
        )

        XCTAssertLessThanOrEqual(
            max(thumbnailFrame.width, thumbnailFrame.height),
            80
        )
        XCTAssertLessThan(thumbnailFrame.width, originalImage.width)

        let thumbnailPixel = try samplePixelColor(in: thumbnailFrame)
        XCTAssertGreaterThan(thumbnailPixel.blue, 220)
        XCTAssertLessThan(thumbnailPixel.red, thumbnailPixel.blue)
        XCTAssertLessThan(thumbnailPixel.green, thumbnailPixel.blue)
    }

    func testPlaybackMetadataPrefersImportedMetadataWhenShapeMatches() throws {
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.08
                ),
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 0,
                        green: 1,
                        blue: 0
                    ),
                    delayTime: 0.09
                )
            ],
            loopCount: 4
        )
        let importedMetadata = CanvasAnimatedImageMetadata(
            frameCount: 2,
            frameDelayTimes: [0.3, 0.4],
            loopCount: 7
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let resolvedMetadata = try XCTUnwrap(
            CanvasGIFFrameService.playbackMetadata(
                from: imageSource,
                importedMetadata: importedMetadata
            )
        )

        XCTAssertEqual(resolvedMetadata, importedMetadata)
    }

    func testPlaybackMetadataFallsBackWhenImportedMetadataShapeMismatches() throws {
        let gifData = try makeGIFData(
            frames: [
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.11
                ),
                GIFFrameSpec(
                    image: try makeSolidColorImage(
                        red: 0,
                        green: 0,
                        blue: 1
                    ),
                    delayTime: 0.13
                )
            ],
            loopCount: 3
        )
        let mismatchedMetadata = CanvasAnimatedImageMetadata(
            frameCount: 3,
            frameDelayTimes: [0.4, 0.4, 0.4],
            loopCount: 9
        )

        let imageSource = try XCTUnwrap(
            CanvasGIFFrameService.makeImageSource(from: gifData)
        )
        let resolvedMetadata = try XCTUnwrap(
            CanvasGIFFrameService.playbackMetadata(
                from: imageSource,
                importedMetadata: mismatchedMetadata
            )
        )

        XCTAssertEqual(resolvedMetadata.frameCount, 2)
        XCTAssertEqual(resolvedMetadata.frameDelayTimes.count, 2)
        XCTAssertEqual(resolvedMetadata.loopCount, 3)
        XCTAssertEqual(resolvedMetadata.frameDelayTimes[0], 0.11, accuracy: 0.02)
        XCTAssertEqual(resolvedMetadata.frameDelayTimes[1], 0.13, accuracy: 0.02)
    }
}

private struct GIFFrameSpec {
    let image: CGImage
    let delayTime: TimeInterval
}

private struct PixelColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private enum CanvasGIFFrameServiceTestError: Error {
    case invalidImageDestination
    case invalidBitmapContext
    case invalidImageDecoding
}

private func makeGIFData(
    frames: [GIFFrameSpec],
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
        throw CanvasGIFFrameServiceTestError.invalidImageDestination
    }

    let containerProperties = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: loopCount
        ]
    ] as CFDictionary
    CGImageDestinationSetProperties(
        imageDestination,
        containerProperties
    )

    for frame in frames {
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: frame.delayTime,
                kCGImagePropertyGIFDelayTime: frame.delayTime
            ]
        ] as CFDictionary
        CGImageDestinationAddImage(
            imageDestination,
            frame.image,
            frameProperties
        )
    }

    guard CGImageDestinationFinalize(imageDestination) else {
        throw CanvasGIFFrameServiceTestError.invalidImageDestination
    }

    return mutableData as Data
}

private func makeSolidColorImage(
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
        throw CanvasGIFFrameServiceTestError.invalidBitmapContext
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
        throw CanvasGIFFrameServiceTestError.invalidBitmapContext
    }
    return image
}

private func samplePixelColor(in image: CGImage) throws -> PixelColor {
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
        throw CanvasGIFFrameServiceTestError.invalidBitmapContext
    }

    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return PixelColor(
        red: pixelBytes[0],
        green: pixelBytes[1],
        blue: pixelBytes[2],
        alpha: pixelBytes[3]
    )
}
