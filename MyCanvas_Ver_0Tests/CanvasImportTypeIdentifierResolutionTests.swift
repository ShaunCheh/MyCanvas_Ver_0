import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasImportTypeIdentifierResolutionTests: XCTestCase {
    func testImportedImageSourceResolvesDeclaredPublicTypeIdentifier() {
        let source = CanvasImportedImageSource(
            data: Data(),
            typeIdentifier: UTType.jpeg.identifier,
            filenameHint: "photo.jpg"
        )

        XCTAssertEqual(source.contentType?.identifier, UTType.jpeg.identifier)
    }

    func testResolvedImportImageFallsBackFromIgnoredPrivateThumbnailType() throws {
        let resolvedImage = try XCTUnwrap(
            CanvasResolvedImportImage(
                data: try makePNGData(),
                typeIdentifier: "com.apple.private.photos.thumbnail.low",
                filenameHint: "thumbnail"
            )
        )

        XCTAssertEqual(
            resolvedImage.importedSource?.typeIdentifier,
            UTType.png.identifier
        )
        XCTAssertEqual(
            resolvedImage.importedContentType?.identifier,
            UTType.png.identifier
        )
    }

    func testImportedVideoSourceFallsBackToFilenameExtensionWhenIdentifierIsIgnored() {
        let source = CanvasImportedVideoSource(
            localFileURL: URL(fileURLWithPath: "/tmp/example-video.mp4"),
            typeIdentifier: "com.apple.private.photos.thumbnail.standard",
            filenameHint: nil,
            shouldDeleteAfterImport: false
        )

        XCTAssertEqual(
            source.contentType?.identifier,
            UTType(filenameExtension: "mp4")?.identifier
        )
    }
}

private enum CanvasImportTypeIdentifierResolutionTestError: Error {
    case invalidBitmapContext
    case invalidImageEncoding
}

private func makePNGData() throws -> Data {
    let mutableData = NSMutableData()
    guard
        let imageDestination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CanvasImportTypeIdentifierResolutionTestError.invalidImageEncoding
    }

    CGImageDestinationAddImage(imageDestination, try makeSolidColorImage(), nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw CanvasImportTypeIdentifierResolutionTestError.invalidImageEncoding
    }
    return mutableData as Data
}

private func makeSolidColorImage() throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasImportTypeIdentifierResolutionTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
    )
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))

    guard let image = context.makeImage() else {
        throw CanvasImportTypeIdentifierResolutionTestError.invalidBitmapContext
    }
    return image
}
