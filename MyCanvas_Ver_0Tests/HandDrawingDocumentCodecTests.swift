import CoreGraphics
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingDocumentCodecTests: XCTestCase {
    func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
        let document = makeHandDrawingTestDocument(includeEraseMask: true)

        let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)

        XCTAssertEqual(decodedDocument, document)
    }

    func testHandDrawingDocumentCodecRoundTripsManifest() throws {
        let manifest = HandDrawingManifest(
            documentID: UUID(),
            paper: CanvasHandDrawingPaperSpec(
                id: "codec-paper",
                size: CGSize(width: 240, height: 180)
            ),
            contentRevision: UUID(),
            isEmpty: false,
            migrationOrigin: .legacyFlatAssetPair
        )

        let encodedData = try HandDrawingDocumentCodec.makeManifestData(for: manifest)
        let decodedManifest = try HandDrawingDocumentCodec.decodeManifest(
            from: encodedData
        )

        XCTAssertEqual(decodedManifest, manifest)
    }

    func testHandDrawingDocumentCodecRoundTripsPreviewPNGData() throws {
        let documentID = UUID()
        let previewImage = try makeHandDrawingDocumentCodecTestImage(
            red: 0.85,
            green: 0.25,
            blue: 0.35
        )

        let previewImageData = try HandDrawingDocumentCodec.makePNGData(
            for: previewImage,
            documentID: documentID
        )
        let decodedPreviewImage = try HandDrawingDocumentCodec.decodePreviewImage(
            from: previewImageData,
            documentID: documentID
        )

        XCTAssertEqual(
            BoardThumbnailImageSignature.describe(decodedPreviewImage),
            BoardThumbnailImageSignature.describe(previewImage)
        )
    }

    func testHandDrawingDocumentCodecRejectsUnsupportedFormatVersion() throws {
        let document = makeHandDrawingTestDocument()
        let encodedData = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        payload["formatVersion"] = HandDrawingDocument.currentFormatVersion + 1
        let mutatedData = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(
            try HandDrawingDocumentCodec.decodeDocument(from: mutatedData)
        ) { error in
            guard
                case let HandDrawingDocumentCodecError
                    .unsupportedDocumentFormatVersion(formatVersion) = error
            else {
                return XCTFail("Expected unsupported format version error, got \(error).")
            }
            XCTAssertEqual(
                formatVersion,
                HandDrawingDocument.currentFormatVersion + 1
            )
        }
    }

    func testHandDrawingDocumentCodecRejectsInvalidPreviewImageData() throws {
        let documentID = UUID()

        XCTAssertThrowsError(
            try HandDrawingDocumentCodec.decodePreviewImage(
                from: Data("not-a-preview".utf8),
                documentID: documentID
            )
        ) { error in
            guard
                case let HandDrawingDocumentCodecError
                    .invalidPreviewImage(invalidDocumentID) = error
            else {
                return XCTFail("Expected invalid preview image error, got \(error).")
            }
            XCTAssertEqual(invalidDocumentID, documentID)
        }
    }
}

private func makeHandDrawingDocumentCodecTestImage(
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
            width: 14,
            height: 14,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw HandDrawingDocumentCodecTestError.invalidBitmapContext
    }

    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 14, height: 14))
    guard let image = context.makeImage() else {
        throw HandDrawingDocumentCodecTestError.invalidBitmapContext
    }
    return image
}

private enum HandDrawingDocumentCodecTestError: Error {
    case invalidBitmapContext
}
