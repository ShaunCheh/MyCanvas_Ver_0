import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HandDrawingDocumentCodecError: LocalizedError {
    case failedToEncodePreviewImage(documentID: HandDrawingDocumentID)
    case invalidPreviewImage(documentID: HandDrawingDocumentID)

    var errorDescription: String? {
        switch self {
        case let .failedToEncodePreviewImage(documentID):
            return "Failed to encode preview image for hand drawing document \(documentID.uuidString)."
        case let .invalidPreviewImage(documentID):
            return "Failed to decode preview image for hand drawing document \(documentID.uuidString)."
        }
    }
}

enum HandDrawingDocumentCodec {
    static func makeManifestData(for manifest: HandDrawingManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    static func decodeManifest(from data: Data) throws -> HandDrawingManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(HandDrawingManifest.self, from: data)
    }

    static func makePNGData(
        for previewImage: CGImage,
        documentID: HandDrawingDocumentID
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard
            let imageDestination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw HandDrawingDocumentCodecError.failedToEncodePreviewImage(
                documentID: documentID
            )
        }

        CGImageDestinationAddImage(imageDestination, previewImage, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw HandDrawingDocumentCodecError.failedToEncodePreviewImage(
                documentID: documentID
            )
        }

        return mutableData as Data
    }

    static func decodePreviewImage(
        from data: Data,
        documentID: HandDrawingDocumentID
    ) throws -> CGImage {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let previewImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw HandDrawingDocumentCodecError.invalidPreviewImage(
                documentID: documentID
            )
        }

        return previewImage
    }
}
