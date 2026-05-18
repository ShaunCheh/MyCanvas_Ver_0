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

    private struct LegacyFlatDocumentPayload: Decodable {
        let formatVersion: Int
        let paper: HandDrawingPaper
        let strokes: [HandDrawingStroke]
    }

    private struct LayeredDocumentPayload: Decodable {
        let formatVersion: Int
        let paper: HandDrawingPaper
        let layers: [HandDrawingLayer]
        let activeLayerID: UUID
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
        guard
            supportedDocumentFormatVersions.contains(formatProbe.formatVersion)
        else {
            throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
                formatProbe.formatVersion
            )
        }

        switch formatProbe.formatVersion {
        case 1:
            return try decodeLegacyFlatDocument(
                from: data,
                using: decoder
            )
        case HandDrawingDocument.currentFormatVersion:
            return try decodeLayeredDocument(
                from: data,
                using: decoder
            )
        default:
            throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
                formatProbe.formatVersion
            )
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

    private static var supportedDocumentFormatVersions: Set<Int> {
        [1, HandDrawingDocument.currentFormatVersion]
    }

    private static func decodeLegacyFlatDocument(
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> HandDrawingDocument {
        do {
            let legacyPayload = try decoder.decode(
                LegacyFlatDocumentPayload.self,
                from: data
            )
            return HandDrawingDocument(
                paper: legacyPayload.paper,
                strokes: legacyPayload.strokes
            )
        } catch {
            throw HandDrawingDocumentCodecError.invalidDocumentData
        }
    }

    private static func decodeLayeredDocument(
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> HandDrawingDocument {
        do {
            let payload = try decoder.decode(
                LayeredDocumentPayload.self,
                from: data
            )
            return HandDrawingDocument(
                paper: payload.paper,
                layers: payload.layers,
                activeLayerID: payload.activeLayerID,
                formatVersion: payload.formatVersion
            )
        } catch {
            throw HandDrawingDocumentCodecError.invalidDocumentData
        }
    }
}
