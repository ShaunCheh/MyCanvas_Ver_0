import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HandDrawingDocumentCodecError: LocalizedError {
    case invalidDocumentData
    case unsupportedDocumentFormatVersion(Int)
    case failedToEncodePreviewImage(documentID: HandDrawingDocumentID)
    case invalidPreviewImage(documentID: HandDrawingDocumentID)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentData:
            return "Failed to decode the hand drawing document data."
        case let .unsupportedDocumentFormatVersion(formatVersion):
            return "Unsupported hand drawing document format version: \(formatVersion)."
        case let .failedToEncodePreviewImage(documentID):
            return "Failed to encode preview image for hand drawing document \(documentID.uuidString)."
        case let .invalidPreviewImage(documentID):
            return "Failed to decode preview image for hand drawing document \(documentID.uuidString)."
        }
    }
}

enum HandDrawingDocumentCodec {
    private struct FormatVersionProbe: Decodable {
        let formatVersion: Int
    }

    static func makeManifestData(for manifest: HandDrawingManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    static func decodeManifest(from data: Data) throws -> HandDrawingManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(HandDrawingManifest.self, from: data)
    }

    static func makeDocumentData(for document: HandDrawingDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decodeDocument(from data: Data) throws -> HandDrawingDocument {
        let decoder = JSONDecoder()
        let formatProbe: FormatVersionProbe
        do {
            formatProbe = try decoder.decode(FormatVersionProbe.self, from: data)
        } catch {
            throw HandDrawingDocumentCodecError.invalidDocumentData
        }
        guard formatProbe.formatVersion == HandDrawingDocument.currentFormatVersion else {
            throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
                formatProbe.formatVersion
            )
        }
        do {
            return try decoder.decode(HandDrawingDocument.self, from: data)
        } catch {
            throw HandDrawingDocumentCodecError.invalidDocumentData
        }
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
