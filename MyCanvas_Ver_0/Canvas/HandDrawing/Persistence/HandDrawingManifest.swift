import CoreGraphics
import Foundation

enum HandDrawingManifestMigrationOrigin: String, Codable, Equatable {
    case legacyFlatAssetPair
}

struct HandDrawingManifestPaperRecord: Codable, Equatable {
    var id: String
    var width: Double
    var height: Double

    init(_ paper: CanvasHandDrawingPaperSpec) {
        id = paper.id
        width = Double(paper.size.width)
        height = Double(paper.size.height)
    }

    var canvasPaperSpec: CanvasHandDrawingPaperSpec {
        CanvasHandDrawingPaperSpec(
            id: id,
            size: CGSize(width: CGFloat(width), height: CGFloat(height))
        )
    }
}

struct HandDrawingManifest: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let documentID: HandDrawingDocumentID
    var paper: HandDrawingManifestPaperRecord
    var contentRevision: UUID
    var isEmpty: Bool
    var migrationOrigin: HandDrawingManifestMigrationOrigin?

    init(
        documentID: HandDrawingDocumentID,
        paper: CanvasHandDrawingPaperSpec,
        contentRevision: UUID,
        isEmpty: Bool,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.documentID = documentID
        self.paper = HandDrawingManifestPaperRecord(paper)
        self.contentRevision = contentRevision
        self.isEmpty = isEmpty
        self.migrationOrigin = migrationOrigin
    }
}
