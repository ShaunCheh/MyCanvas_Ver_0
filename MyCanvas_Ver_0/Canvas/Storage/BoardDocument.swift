import CoreGraphics
import Foundation

struct BoardSummary {
    let boardID: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState

    static func makeEmpty(
        boardID: UUID = UUID(),
        title: String = BoardDocument.defaultTitle,
        now: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: now,
            updatedAt: now,
            items: [],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState()
        )
    }

    var summary: BoardSummary {
        BoardSummary(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // T-1 keeps persistence and thumbnail generation on the existing image-only
    // path while runtime/history move to mixed item storage.
    var imageItems: [CanvasImageItem] {
        items.compactMap(\.imageItem)
    }

    var textItems: [CanvasTextItem] {
        items.compactMap(\.textItem)
    }
}

struct BoardDocument: Codable {
    static let currentFormatVersion = 2
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var items: [BoardImageItemRecord]

    var summary: BoardSummary {
        BoardSummary(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?
}

struct BoardImageCropRecord: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ cropRect: CanvasImageCropRect) {
        let normalizedRect = cropRect.cgRect
        self.init(
            x: Double(normalizedRect.origin.x),
            y: Double(normalizedRect.origin.y),
            width: Double(normalizedRect.width),
            height: Double(normalizedRect.height)
        )
    }

    var canvasImageCropRect: CanvasImageCropRect {
        CanvasImageCropRect(
            CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }
}

struct BoardPointRecord: Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(
            x: Double(point.x),
            y: Double(point.y)
        )
    }

    var cgPoint: CGPoint {
        CGPoint(
            x: x,
            y: y
        )
    }
}

struct BoardSizeRecord: Codable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.init(
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    var cgSize: CGSize {
        CGSize(
            width: width,
            height: height
        )
    }
}

struct BoardRectRecord: Codable {
    var origin: BoardPointRecord
    var size: BoardSizeRecord

    init(origin: BoardPointRecord, size: BoardSizeRecord) {
        self.origin = origin
        self.size = size
    }

    init(_ rect: CGRect) {
        let standardizedRect = rect.standardized
        self.init(
            origin: BoardPointRecord(standardizedRect.origin),
            size: BoardSizeRecord(standardizedRect.size)
        )
    }

    var cgRect: CGRect {
        CGRect(
            origin: origin.cgPoint,
            size: size.cgSize
        )
    }
}
