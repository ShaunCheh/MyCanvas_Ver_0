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
    var workspaceMode: CanvasWorkspaceMode

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
            interactionState: CanvasInteractionState(),
            workspaceMode: .editing
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

    // Image-backed items still need a projection because storage and thumbnail
    // code still reason about persisted image assets as a filtered subset.
    var imageItems: [CanvasImageItem] {
        items.compactMap(\.imageItem)
    }

    var textItems: [CanvasTextItem] {
        items.compactMap(\.textItem)
    }
}

struct BoardDocument: Codable {
    static let currentFormatVersion =
        CanvasImageAssetContract.current.targetDocumentFormatVersion
    static let targetFormatVersionForImageAssets = currentFormatVersion
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
    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]

    var summary: BoardSummary {
        BoardSummary(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var imageItemRecords: [BoardImageItemRecord] {
        items.compactMap(\.imageItemRecord)
    }

    var textItemRecords: [BoardTextItemRecord] {
        items.compactMap(\.textItemRecord)
    }
}

struct BoardImageItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var assetFilename: String
    var assetKind: CanvasImageAssetKind
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?

    init(
        id: UUID,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        assetFilename: String,
        assetKind: CanvasImageAssetKind = .staticImage,
        cropRectNormalized: BoardImageCropRecord?,
        rotationRadians: Double?
    ) {
        self.id = id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.assetFilename = assetFilename
        self.assetKind = assetKind
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case center
        case size
        case zIndex
        case assetFilename
        case assetKind
        case cropRectNormalized
        case rotationRadians
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        center = try container.decode(BoardPointRecord.self, forKey: .center)
        size = try container.decode(BoardSizeRecord.self, forKey: .size)
        zIndex = try container.decode(Double.self, forKey: .zIndex)
        assetFilename = try container.decode(String.self, forKey: .assetFilename)
        assetKind = try container.decodeIfPresent(
            CanvasImageAssetKind.self,
            forKey: .assetKind
        ) ?? CanvasImageAssetKind.inferredPersistedKind(from: assetFilename)
        cropRectNormalized = try container.decodeIfPresent(
            BoardImageCropRecord.self,
            forKey: .cropRectNormalized
        )
        rotationRadians = try container.decodeIfPresent(
            Double.self,
            forKey: .rotationRadians
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center, forKey: .center)
        try container.encode(size, forKey: .size)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(assetFilename, forKey: .assetFilename)
        try container.encode(assetKind, forKey: .assetKind)
        try container.encodeIfPresent(
            cropRectNormalized,
            forKey: .cropRectNormalized
        )
        try container.encodeIfPresent(
            rotationRadians,
            forKey: .rotationRadians
        )
    }

    var assetReference: CanvasImageAssetReference {
        .persisted(
            kind: assetKind,
            filename: assetFilename
        )
    }
}

struct BoardTextColorRecord: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: CanvasTextColor) {
        self.init(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            alpha: Double(color.alpha)
        )
    }

    var canvasTextColor: CanvasTextColor {
        CanvasTextColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct BoardTextStyleRecord: Codable {
    var fontName: String
    var fontSize: Double
    var color: BoardTextColorRecord

    init(
        fontName: String,
        fontSize: Double,
        color: BoardTextColorRecord
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
    }

    init(_ style: CanvasTextStyle) {
        self.init(
            fontName: style.fontName,
            fontSize: Double(style.fontSize),
            color: BoardTextColorRecord(style.color)
        )
    }

    var canvasTextStyle: CanvasTextStyle {
        CanvasTextStyle(
            fontName: fontName,
            fontSize: CGFloat(fontSize),
            color: color.canvasTextColor
        )
    }
}

struct BoardTextItemRecord: Codable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var text: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
}

enum BoardItemRecord: Codable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)

    private enum CodingKeys: String, CodingKey {
        case type
        case image
        case text
    }

    private enum ItemType: String, Codable {
        case image
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try container.decodeIfPresent(ItemType.self, forKey: .type) {
            switch type {
            case .image:
                self = .image(
                    try container.decode(
                        BoardImageItemRecord.self,
                        forKey: .image
                    )
                )
            case .text:
                self = .text(
                    try container.decode(
                        BoardTextItemRecord.self,
                        forKey: .text
                    )
                )
            }
            return
        }

        // v2 documents stored plain image records without a type tag.
        self = .image(try BoardImageItemRecord(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .image(record):
            try container.encode(ItemType.image, forKey: .type)
            try container.encode(record, forKey: .image)
        case let .text(record):
            try container.encode(ItemType.text, forKey: .type)
            try container.encode(record, forKey: .text)
        }
    }

    var id: UUID {
        switch self {
        case let .image(record):
            return record.id
        case let .text(record):
            return record.id
        }
    }

    var zIndex: Double {
        switch self {
        case let .image(record):
            return record.zIndex
        case let .text(record):
            return record.zIndex
        }
    }

    var imageItemRecord: BoardImageItemRecord? {
        guard case let .image(record) = self else {
            return nil
        }

        return record
    }

    var textItemRecord: BoardTextItemRecord? {
        guard case let .text(record) = self else {
            return nil
        }

        return record
    }
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
