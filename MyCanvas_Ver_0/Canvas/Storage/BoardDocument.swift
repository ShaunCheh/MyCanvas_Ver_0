import CoreGraphics
import Foundation

struct BoardSummary {
    let boardID: UUID
    let title: String
    let createdAt: Date
    let contentUpdatedAt: Date
    let viewStateUpdatedAt: Date

    var updatedAt: Date {
        contentUpdatedAt
    }
}

struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var contentUpdatedAt: Date
    var viewStateUpdatedAt: Date
    var items: [CanvasBoardItem]
    var groups: [CanvasItemGroup] = []
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState
    var workspaceMode: CanvasWorkspaceMode

    var updatedAt: Date {
        contentUpdatedAt
    }

    static func makeEmpty(
        boardID: UUID = UUID(),
        title: String = BoardDocument.defaultTitle,
        now: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: now,
            contentUpdatedAt: now,
            viewStateUpdatedAt: now,
            items: [],
            groups: [],
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
            contentUpdatedAt: contentUpdatedAt,
            viewStateUpdatedAt: viewStateUpdatedAt
        )
    }

    // Poster-backed items still project through CanvasImageItem so storage and
    // thumbnail code can treat images and video covers as one renderable subset.
    var imageItems: [CanvasImageItem] {
        items.compactMap(\.imageItem)
    }

    var textItems: [CanvasTextItem] {
        items.compactMap(\.textItem)
    }

    var markdownItems: [CanvasMarkdownItem] {
        items.compactMap(\.markdownItem)
    }

    var handDrawingItems: [CanvasHandDrawingItem] {
        items.compactMap(\.handDrawingItem)
    }

    var arrowItems: [CanvasArrowItem] {
        items.compactMap(\.arrowItem)
    }
}

typealias CanvasItemGroupID = UUID

struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]
    var childGroupIDs: [CanvasItemGroupID]
    var frame: CGRect?

    init(
        id: CanvasItemGroupID = UUID(),
        title: String,
        description: String = "",
        itemIDs: [CanvasItemID],
        childGroupIDs: [CanvasItemGroupID] = [],
        frame: CGRect? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.childGroupIDs = Self.normalizedChildGroupIDs(childGroupIDs)
        self.frame = frame?.standardized
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Group" : trimmedTitle
    }

    private static func normalizedItemIDs(
        _ itemIDs: [CanvasItemID]
    ) -> [CanvasItemID] {
        var seenItemIDs = Set<CanvasItemID>()
        return itemIDs.filter { itemID in
            seenItemIDs.insert(itemID).inserted
        }
    }

    private static func normalizedChildGroupIDs(
        _ childGroupIDs: [CanvasItemGroupID]
    ) -> [CanvasItemGroupID] {
        var seenGroupIDs = Set<CanvasItemGroupID>()
        return childGroupIDs.filter { groupID in
            seenGroupIDs.insert(groupID).inserted
        }
    }
}

struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    // Format version 14 lets groups persist direct child group IDs for nested
    // semantic groups.
    static let currentFormatVersion = 14
    static let defaultTitle = "Untitled Board"

    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var contentUpdatedAt: Date
    var viewStateUpdatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    private var storedSelectedItemIDs: [UUID]
    private var storedPrimarySelectedItemID: UUID?
    var selectedItemIDs: [UUID] {
        get {
            storedSelectedItemIDs
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue,
                primarySelectedItemID: storedPrimarySelectedItemID
            )
        }
    }
    var primarySelectedItemID: UUID? {
        get {
            storedPrimarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: storedSelectedItemIDs,
                primarySelectedItemID: newValue
            )
        }
    }
    var selectedItemID: UUID? {
        get {
            primarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue.map { [$0] } ?? [],
                primarySelectedItemID: newValue
            )
        }
    }
    var workspaceMode: CanvasWorkspaceMode?
    var groups: [BoardGroupRecord]
    var items: [BoardItemRecord]

    var updatedAt: Date {
        contentUpdatedAt
    }

    init(
        formatVersion: Int,
        boardID: UUID,
        title: String,
        createdAt: Date,
        contentUpdatedAt: Date,
        viewStateUpdatedAt: Date,
        boardBaseSize: BoardSizeRecord?,
        boardRect: BoardRectRecord?,
        cameraCenter: BoardPointRecord,
        cameraZoomScale: Double,
        selectedItemIDs: [UUID] = [],
        primarySelectedItemID: UUID? = nil,
        workspaceMode: CanvasWorkspaceMode?,
        groups: [BoardGroupRecord] = [],
        items: [BoardItemRecord]
    ) {
        self.formatVersion = formatVersion
        self.boardID = boardID
        self.title = title
        self.createdAt = createdAt
        self.contentUpdatedAt = contentUpdatedAt
        self.viewStateUpdatedAt = viewStateUpdatedAt
        self.boardBaseSize = boardBaseSize
        self.boardRect = boardRect
        self.cameraCenter = cameraCenter
        self.cameraZoomScale = cameraZoomScale
        storedSelectedItemIDs = []
        storedPrimarySelectedItemID = nil
        self.workspaceMode = workspaceMode
        self.groups = groups
        self.items = items
        applyNormalizedSelection(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
    }

    init(
        formatVersion: Int,
        boardID: UUID,
        title: String,
        createdAt: Date,
        contentUpdatedAt: Date,
        viewStateUpdatedAt: Date,
        boardBaseSize: BoardSizeRecord?,
        boardRect: BoardRectRecord?,
        cameraCenter: BoardPointRecord,
        cameraZoomScale: Double,
        selectedItemID: UUID?,
        workspaceMode: CanvasWorkspaceMode?,
        groups: [BoardGroupRecord] = [],
        items: [BoardItemRecord]
    ) {
        self.init(
            formatVersion: formatVersion,
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            contentUpdatedAt: contentUpdatedAt,
            viewStateUpdatedAt: viewStateUpdatedAt,
            boardBaseSize: boardBaseSize,
            boardRect: boardRect,
            cameraCenter: cameraCenter,
            cameraZoomScale: cameraZoomScale,
            selectedItemIDs: selectedItemID.map { [$0] } ?? [],
            primarySelectedItemID: selectedItemID,
            workspaceMode: workspaceMode,
            groups: groups,
            items: items
        )
    }

    var summary: BoardSummary {
        BoardSummary(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            contentUpdatedAt: contentUpdatedAt,
            viewStateUpdatedAt: viewStateUpdatedAt
        )
    }

    var imageItemRecords: [BoardImageItemRecord] {
        items.compactMap(\.imageItemRecord)
    }

    var referencedAssetFilenames: Set<String> {
        items.reduce(into: Set<String>()) { partialResult, record in
            partialResult.formUnion(record.referencedAssetFilenames)
        }
    }

    var referencedHandDrawingDocumentIDs: Set<HandDrawingDocumentID> {
        items.reduce(into: Set<HandDrawingDocumentID>()) { partialResult, record in
            partialResult.formUnion(record.referencedHandDrawingDocumentIDs)
        }
    }

    var textItemRecords: [BoardTextItemRecord] {
        items.compactMap(\.textItemRecord)
    }

    var markdownItemRecords: [BoardMarkdownItemRecord] {
        items.compactMap(\.markdownItemRecord)
    }

    var handDrawingItemRecords: [BoardHandDrawingItemRecord] {
        items.compactMap(\.handDrawingItemRecord)
    }

    var arrowItemRecords: [BoardArrowItemRecord] {
        items.compactMap(\.arrowItemRecord)
    }

    var contentState: BoardDocumentContentState {
        BoardDocumentContentState(
            title: title,
            boardRect: boardRect,
            groups: groups,
            items: items
        )
    }

    var viewState: BoardDocumentViewState {
        BoardDocumentViewState(
            boardBaseSize: boardBaseSize,
            cameraCenter: cameraCenter,
            cameraZoomScale: cameraZoomScale,
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID,
            workspaceMode: workspaceMode
        )
    }

    mutating func replaceContentState(with other: BoardDocument) {
        title = other.title
        boardRect = other.boardRect
        groups = other.groups
        items = other.items
    }

    mutating func replaceViewState(with other: BoardDocument) {
        boardBaseSize = other.boardBaseSize
        cameraCenter = other.cameraCenter
        cameraZoomScale = other.cameraZoomScale
        applyNormalizedSelection(
            selectedItemIDs: other.selectedItemIDs,
            primarySelectedItemID: other.primarySelectedItemID
        )
        workspaceMode = other.workspaceMode
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case boardID
        case title
        case createdAt
        case updatedAt
        case contentUpdatedAt
        case viewStateUpdatedAt
        case boardBaseSize
        case boardRect
        case cameraCenter
        case cameraZoomScale
        case selectedItemID
        case selectedItemIDs
        case primarySelectedItemID
        case workspaceMode
        case groups
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        boardID = try container.decode(UUID.self, forKey: .boardID)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let legacyUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? createdAt
        contentUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .contentUpdatedAt
        ) ?? legacyUpdatedAt
        viewStateUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .viewStateUpdatedAt
        ) ?? legacyUpdatedAt
        boardBaseSize = try container.decodeIfPresent(
            BoardSizeRecord.self,
            forKey: .boardBaseSize
        )
        boardRect = try container.decodeIfPresent(
            BoardRectRecord.self,
            forKey: .boardRect
        )
        cameraCenter = try container.decode(
            BoardPointRecord.self,
            forKey: .cameraCenter
        )
        cameraZoomScale = try container.decode(
            Double.self,
            forKey: .cameraZoomScale
        )
        let legacySelectedItemID = try container.decodeIfPresent(
            UUID.self,
            forKey: .selectedItemID
        )
        let decodedSelectedItemIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .selectedItemIDs
        ) ?? legacySelectedItemID.map { [$0] } ?? []
        let decodedPrimarySelectedItemID = try container.decodeIfPresent(
            UUID.self,
            forKey: .primarySelectedItemID
        ) ?? legacySelectedItemID
        workspaceMode = try container.decodeIfPresent(
            CanvasWorkspaceMode.self,
            forKey: .workspaceMode
        )
        groups = try container.decodeIfPresent(
            [BoardGroupRecord].self,
            forKey: .groups
        ) ?? []
        items = try container.decode([BoardItemRecord].self, forKey: .items)
        storedSelectedItemIDs = []
        storedPrimarySelectedItemID = nil
        applyNormalizedSelection(
            selectedItemIDs: decodedSelectedItemIDs,
            primarySelectedItemID: decodedPrimarySelectedItemID
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(boardID, forKey: .boardID)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(contentUpdatedAt, forKey: .updatedAt)
        try container.encode(contentUpdatedAt, forKey: .contentUpdatedAt)
        try container.encode(viewStateUpdatedAt, forKey: .viewStateUpdatedAt)
        try container.encodeIfPresent(boardBaseSize, forKey: .boardBaseSize)
        try container.encodeIfPresent(boardRect, forKey: .boardRect)
        try container.encode(cameraCenter, forKey: .cameraCenter)
        try container.encode(cameraZoomScale, forKey: .cameraZoomScale)
        try container.encode(selectedItemIDs, forKey: .selectedItemIDs)
        try container.encodeIfPresent(
            primarySelectedItemID,
            forKey: .primarySelectedItemID
        )
        try container.encodeIfPresent(selectedItemID, forKey: .selectedItemID)
        try container.encodeIfPresent(workspaceMode, forKey: .workspaceMode)
        try container.encode(groups, forKey: .groups)
        try container.encode(items, forKey: .items)
    }

    private mutating func applyNormalizedSelection(
        selectedItemIDs: [UUID],
        primarySelectedItemID: UUID?
    ) {
        let normalized = normalizeCanvasSelectionState(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
        storedSelectedItemIDs = normalized.selectedItemIDs
        storedPrimarySelectedItemID = normalized.primarySelectedItemID
    }
}

struct BoardDocumentContentState: Equatable {
    var title: String
    var boardRect: BoardRectRecord?
    var groups: [BoardGroupRecord]
    var items: [BoardItemRecord]
}

struct BoardGroupRecord: Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var itemIDs: [UUID]
    var childGroupIDs: [UUID]
    var frame: BoardRectRecord?

    init(
        id: UUID,
        title: String,
        description: String,
        itemIDs: [UUID],
        childGroupIDs: [UUID] = [],
        frame: BoardRectRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.childGroupIDs = Self.normalizedChildGroupIDs(childGroupIDs)
        self.frame = frame
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case itemIDs
        case childGroupIDs
        case frame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        itemIDs = Self.normalizedItemIDs(
            try container.decode([UUID].self, forKey: .itemIDs)
        )
        childGroupIDs = Self.normalizedChildGroupIDs(
            try container.decodeIfPresent([UUID].self, forKey: .childGroupIDs) ?? []
        )
        frame = try container.decodeIfPresent(BoardRectRecord.self, forKey: .frame)
    }

    private static func normalizedItemIDs(_ itemIDs: [UUID]) -> [UUID] {
        var seenItemIDs = Set<UUID>()
        return itemIDs.filter { itemID in
            seenItemIDs.insert(itemID).inserted
        }
    }

    private static func normalizedChildGroupIDs(_ childGroupIDs: [UUID]) -> [UUID] {
        var seenGroupIDs = Set<UUID>()
        return childGroupIDs.filter { groupID in
            seenGroupIDs.insert(groupID).inserted
        }
    }
}

struct BoardDocumentViewState: Equatable {
    var boardBaseSize: BoardSizeRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    private var storedSelectedItemIDs: [UUID]
    private var storedPrimarySelectedItemID: UUID?
    var selectedItemIDs: [UUID] {
        get {
            storedSelectedItemIDs
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue,
                primarySelectedItemID: storedPrimarySelectedItemID
            )
        }
    }
    var primarySelectedItemID: UUID? {
        get {
            storedPrimarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: storedSelectedItemIDs,
                primarySelectedItemID: newValue
            )
        }
    }
    var selectedItemID: UUID? {
        get {
            primarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue.map { [$0] } ?? [],
                primarySelectedItemID: newValue
            )
        }
    }
    var workspaceMode: CanvasWorkspaceMode?

    init(
        boardBaseSize: BoardSizeRecord?,
        cameraCenter: BoardPointRecord,
        cameraZoomScale: Double,
        selectedItemIDs: [UUID] = [],
        primarySelectedItemID: UUID? = nil,
        workspaceMode: CanvasWorkspaceMode?
    ) {
        self.boardBaseSize = boardBaseSize
        self.cameraCenter = cameraCenter
        self.cameraZoomScale = cameraZoomScale
        storedSelectedItemIDs = []
        storedPrimarySelectedItemID = nil
        self.workspaceMode = workspaceMode
        applyNormalizedSelection(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
    }

    init(
        boardBaseSize: BoardSizeRecord?,
        cameraCenter: BoardPointRecord,
        cameraZoomScale: Double,
        selectedItemID: UUID?,
        workspaceMode: CanvasWorkspaceMode?
    ) {
        self.init(
            boardBaseSize: boardBaseSize,
            cameraCenter: cameraCenter,
            cameraZoomScale: cameraZoomScale,
            selectedItemIDs: selectedItemID.map { [$0] } ?? [],
            primarySelectedItemID: selectedItemID,
            workspaceMode: workspaceMode
        )
    }

    private mutating func applyNormalizedSelection(
        selectedItemIDs: [UUID],
        primarySelectedItemID: UUID?
    ) {
        let normalized = normalizeCanvasSelectionState(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
        storedSelectedItemIDs = normalized.selectedItemIDs
        storedPrimarySelectedItemID = normalized.primarySelectedItemID
    }
}

struct BoardImageItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var posterImageFilename: String
    var assetKind: CanvasImageAssetKind
    var sourceVideoFilename: String?
    var posterTimeSeconds: Double?
    var cropRectNormalized: BoardImageCropRecord?
    var rotationRadians: Double?

    init(
        id: UUID,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        assetFilename: String,
        assetKind: CanvasImageAssetKind = .staticImage,
        posterImageFilename: String? = nil,
        sourceVideoFilename: String? = nil,
        posterTimeSeconds: Double? = nil,
        cropRectNormalized: BoardImageCropRecord?,
        rotationRadians: Double?
    ) {
        self.id = id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.posterImageFilename = Self.sanitizedAssetFilename(
            posterImageFilename ?? assetFilename
        )
        self.assetKind = assetKind
        self.sourceVideoFilename = Self.sanitizedOptionalAssetFilename(
            sourceVideoFilename
        )
        self.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds
        )
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
        case posterImageFilename
        case sourceVideoFilename
        case posterTimeSeconds
        case cropRectNormalized
        case rotationRadians
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        center = try container.decode(BoardPointRecord.self, forKey: .center)
        size = try container.decode(BoardSizeRecord.self, forKey: .size)
        zIndex = try container.decode(Double.self, forKey: .zIndex)
        let legacyAssetFilename = try container.decode(
            String.self,
            forKey: .assetFilename
        )
        posterImageFilename = Self.sanitizedAssetFilename(
            try container.decodeIfPresent(
                String.self,
                forKey: .posterImageFilename
            ) ?? legacyAssetFilename
        )
        assetKind = try container.decodeIfPresent(
            CanvasImageAssetKind.self,
            forKey: .assetKind
        ) ?? CanvasImageAssetKind.inferredPersistedKind(
            from: posterImageFilename
        )
        sourceVideoFilename = Self.sanitizedOptionalAssetFilename(
            try container.decodeIfPresent(
                String.self,
                forKey: .sourceVideoFilename
            )
        )
        posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            try container.decodeIfPresent(
                Double.self,
                forKey: .posterTimeSeconds
            )
        )
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
        // Keep the legacy key aligned with the poster filename so older preview
        // code paths can continue to read the current display image.
        try container.encode(posterImageFilename, forKey: .assetFilename)
        try container.encode(assetKind, forKey: .assetKind)
        try container.encode(posterImageFilename, forKey: .posterImageFilename)
        try container.encodeIfPresent(
            sourceVideoFilename,
            forKey: .sourceVideoFilename
        )
        try container.encodeIfPresent(
            posterTimeSeconds,
            forKey: .posterTimeSeconds
        )
        try container.encodeIfPresent(
            cropRectNormalized,
            forKey: .cropRectNormalized
        )
        try container.encodeIfPresent(
            rotationRadians,
            forKey: .rotationRadians
        )
    }

    var assetFilename: String {
        posterImageFilename
    }

    var isVideo: Bool {
        sourceVideoFilename != nil
    }

    var assetReference: CanvasImageAssetReference {
        .persisted(
            kind: assetKind,
            filename: posterImageFilename
        )
    }

    var videoSource: CanvasVideoSource? {
        guard let sourceVideoFilename else {
            return nil
        }

        return CanvasVideoSource(
            assetReference: .persisted(filename: sourceVideoFilename)
        )
    }

    var referencedAssetFilenames: Set<String> {
        var filenames: Set<String> = [posterImageFilename]
        if let sourceVideoFilename {
            filenames.insert(sourceVideoFilename)
        }
        return filenames
    }

    private static func sanitizedAssetFilename(
        _ filename: String
    ) -> String {
        let trimmedFilename = filename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedFilename.isEmpty == false else {
            assertionFailure("Persisted asset filenames must not be empty.")
            return "asset.png"
        }

        return trimmedFilename
    }

    private static func sanitizedOptionalAssetFilename(
        _ filename: String?
    ) -> String? {
        guard let filename else {
            return nil
        }

        let trimmedFilename = filename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedFilename.isEmpty == false else {
            assertionFailure("Persisted asset filenames must not be empty.")
            return nil
        }

        return trimmedFilename
    }

    private static func sanitizedPosterTimeSeconds(
        _ posterTimeSeconds: Double?
    ) -> Double? {
        guard let posterTimeSeconds else {
            return nil
        }

        guard posterTimeSeconds.isFinite else {
            return 0
        }

        return max(posterTimeSeconds, 0)
    }
}

struct BoardTextColorRecord: Codable, Equatable {
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

struct BoardTextStyleRecord: Codable, Equatable {
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

struct BoardTextItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var text: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
}

struct BoardMarkdownItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var markdownSource: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
    var scrollOffsetY: Double? = nil
}

struct BoardHandDrawingPaperRecord: Codable, Equatable {
    var id: String
    var size: BoardSizeRecord

    init(
        id: String,
        size: BoardSizeRecord
    ) {
        self.id = id
        self.size = size
    }

    init(_ paper: CanvasHandDrawingPaperSpec) {
        self.init(
            id: paper.id,
            size: BoardSizeRecord(paper.size)
        )
    }

    var canvasPaperSpec: CanvasHandDrawingPaperSpec {
        CanvasHandDrawingPaperSpec(
            id: id,
            size: size.cgSize
        )
    }
}

enum BoardHandDrawingStorageRecord: String, Codable, Equatable {
    case legacyFlatAssetPair
    case bundle
}

struct BoardHandDrawingItemRecord: Codable, Equatable {
    let id: UUID
    let documentID: HandDrawingDocumentID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var paper: BoardHandDrawingPaperRecord
    var isEmpty: Bool
    var contentRevision: UUID
    var rotationRadians: Double?
    var storage: BoardHandDrawingStorageRecord

    private enum CodingKeys: String, CodingKey {
        case id
        case documentID
        case center
        case size
        case zIndex
        case paper
        case isEmpty
        case contentRevision
        case rotationRadians
        case storage
    }

    init(
        id: UUID,
        documentID: HandDrawingDocumentID? = nil,
        center: BoardPointRecord,
        size: BoardSizeRecord,
        zIndex: Double,
        paper: BoardHandDrawingPaperRecord,
        isEmpty: Bool,
        contentRevision: UUID,
        rotationRadians: Double?,
        storage: BoardHandDrawingStorageRecord = .legacyFlatAssetPair
    ) {
        self.id = id
        self.documentID = documentID ?? id
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.paper = paper
        self.isEmpty = isEmpty
        self.contentRevision = contentRevision
        self.rotationRadians = rotationRadians
        self.storage = storage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        self.init(
            id: id,
            documentID: try container.decodeIfPresent(
                HandDrawingDocumentID.self,
                forKey: .documentID
            ) ?? id,
            center: try container.decode(BoardPointRecord.self, forKey: .center),
            size: try container.decode(BoardSizeRecord.self, forKey: .size),
            zIndex: try container.decode(Double.self, forKey: .zIndex),
            paper: try container.decode(
                BoardHandDrawingPaperRecord.self,
                forKey: .paper
            ),
            isEmpty: try container.decode(Bool.self, forKey: .isEmpty),
            contentRevision: try container.decode(
                UUID.self,
                forKey: .contentRevision
            ),
            rotationRadians: try container.decodeIfPresent(
                Double.self,
                forKey: .rotationRadians
            ),
            storage: try container.decodeIfPresent(
                BoardHandDrawingStorageRecord.self,
                forKey: .storage
            ) ?? .legacyFlatAssetPair
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(center, forKey: .center)
        try container.encode(size, forKey: .size)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(paper, forKey: .paper)
        try container.encode(isEmpty, forKey: .isEmpty)
        try container.encode(contentRevision, forKey: .contentRevision)
        try container.encodeIfPresent(rotationRadians, forKey: .rotationRadians)
        try container.encode(storage, forKey: .storage)
    }

    func replacingStorage(
        with storage: BoardHandDrawingStorageRecord
    ) -> BoardHandDrawingItemRecord {
        BoardHandDrawingItemRecord(
            id: id,
            documentID: documentID,
            center: center,
            size: size,
            zIndex: zIndex,
            paper: paper,
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            rotationRadians: rotationRadians,
            storage: storage
        )
    }

    var previewImageFilename: String {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.previewImageFilename
        case .bundle:
            return bundleLocator.previewImageRelativePath
        }
    }

    var sourceDrawingFilename: String {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.sourceDrawingFilename
        case .bundle:
            return bundleLocator.sourceDrawingRelativePath
        }
    }

    var referencedAssetFilenames: Set<String> {
        switch storage {
        case .legacyFlatAssetPair:
            return legacyAssetLocator.referencedAssetFilenames
        case .bundle:
            return []
        }
    }

    var referencedHandDrawingDocumentIDs: Set<HandDrawingDocumentID> {
        switch storage {
        case .legacyFlatAssetPair:
            return []
        case .bundle:
            return [documentID]
        }
    }

    var previewImageRecord: BoardImageItemRecord {
        BoardImageItemRecord(
            id: id,
            center: center,
            size: size,
            zIndex: zIndex,
            assetFilename: previewImageFilename,
            assetKind: .staticImage,
            posterImageFilename: previewImageFilename,
            sourceVideoFilename: nil,
            posterTimeSeconds: nil,
            cropRectNormalized: nil,
            rotationRadians: rotationRadians
        )
    }

    var legacyAssetLocator: BoardHandDrawingAssetLocator {
        BoardHandDrawingAssetLocator(documentID: documentID)
    }

    var bundleLocator: HandDrawingBundleLocator {
        HandDrawingBundleLocator(documentID: documentID)
    }
}

struct BoardArrowItemRecord: Codable, Equatable {
    let id: UUID
    var startPoint: BoardPointRecord
    var endPoint: BoardPointRecord
    var shaftThickness: Double
    var zIndex: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case startPoint
        case endPoint
        case shaftThickness
        case zIndex
        case center
        case size
        case rotationRadians
    }

    init(
        id: UUID,
        startPoint: BoardPointRecord,
        endPoint: BoardPointRecord,
        shaftThickness: Double,
        zIndex: Double
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.shaftThickness = shaftThickness
        self.zIndex = zIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let zIndex = try container.decode(Double.self, forKey: .zIndex)

        let item: CanvasArrowItem
        if
            let startPoint = try container.decodeIfPresent(
                BoardPointRecord.self,
                forKey: .startPoint
            ),
            let endPoint = try container.decodeIfPresent(
                BoardPointRecord.self,
                forKey: .endPoint
            )
        {
            item = CanvasArrowItem(
                id: id,
                startPoint: startPoint.cgPoint,
                endPoint: endPoint.cgPoint,
                shaftThickness: CGFloat(
                    try container.decodeIfPresent(
                        Double.self,
                        forKey: .shaftThickness
                    ) ?? 0
                ),
                zIndex: CGFloat(zIndex)
            )
        } else {
            item = CanvasArrowItem(
                id: id,
                center: try container.decode(
                    BoardPointRecord.self,
                    forKey: .center
                ).cgPoint,
                size: try container.decode(
                    BoardSizeRecord.self,
                    forKey: .size
                ).cgSize,
                zIndex: CGFloat(zIndex),
                rotationRadians: CGFloat(
                    try container.decodeIfPresent(
                        Double.self,
                        forKey: .rotationRadians
                    ) ?? 0
                )
            )
        }

        self.init(
            id: item.id,
            startPoint: BoardPointRecord(item.startPoint),
            endPoint: BoardPointRecord(item.endPoint),
            shaftThickness: Double(item.shaftThickness),
            zIndex: Double(item.zIndex)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startPoint, forKey: .startPoint)
        try container.encode(endPoint, forKey: .endPoint)
        try container.encode(shaftThickness, forKey: .shaftThickness)
        try container.encode(zIndex, forKey: .zIndex)
    }
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case markdown(BoardMarkdownItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)
    case arrow(BoardArrowItemRecord)

    private enum CodingKeys: String, CodingKey {
        case type
        case image
        case text
        case markdown
        case handDrawing
        case arrow
    }

    private enum ItemType: String, Codable {
        case image
        case text
        case markdown
        case handDrawing
        case arrow
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
            case .markdown:
                self = .markdown(
                    try container.decode(
                        BoardMarkdownItemRecord.self,
                        forKey: .markdown
                    )
                )
            case .handDrawing:
                self = .handDrawing(
                    try container.decode(
                        BoardHandDrawingItemRecord.self,
                        forKey: .handDrawing
                    )
                )
            case .arrow:
                self = .arrow(
                    try container.decode(
                        BoardArrowItemRecord.self,
                        forKey: .arrow
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
        case let .markdown(record):
            try container.encode(ItemType.markdown, forKey: .type)
            try container.encode(record, forKey: .markdown)
        case let .handDrawing(record):
            try container.encode(ItemType.handDrawing, forKey: .type)
            try container.encode(record, forKey: .handDrawing)
        case let .arrow(record):
            try container.encode(ItemType.arrow, forKey: .type)
            try container.encode(record, forKey: .arrow)
        }
    }

    var id: UUID {
        switch self {
        case let .image(record):
            return record.id
        case let .text(record):
            return record.id
        case let .markdown(record):
            return record.id
        case let .handDrawing(record):
            return record.id
        case let .arrow(record):
            return record.id
        }
    }

    var zIndex: Double {
        switch self {
        case let .image(record):
            return record.zIndex
        case let .text(record):
            return record.zIndex
        case let .markdown(record):
            return record.zIndex
        case let .handDrawing(record):
            return record.zIndex
        case let .arrow(record):
            return record.zIndex
        }
    }

    var referencedAssetFilenames: Set<String> {
        switch self {
        case let .image(record):
            return record.referencedAssetFilenames
        case .text, .markdown, .arrow:
            return []
        case let .handDrawing(record):
            return record.referencedAssetFilenames
        }
    }

    var referencedHandDrawingDocumentIDs: Set<HandDrawingDocumentID> {
        switch self {
        case .image, .text, .markdown, .arrow:
            return []
        case let .handDrawing(record):
            return record.referencedHandDrawingDocumentIDs
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

    var markdownItemRecord: BoardMarkdownItemRecord? {
        guard case let .markdown(record) = self else {
            return nil
        }

        return record
    }

    var handDrawingItemRecord: BoardHandDrawingItemRecord? {
        guard case let .handDrawing(record) = self else {
            return nil
        }

        return record
    }

    var arrowItemRecord: BoardArrowItemRecord? {
        guard case let .arrow(record) = self else {
            return nil
        }

        return record
    }
}

struct BoardImageCropRecord: Codable, Equatable {
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

struct BoardPointRecord: Codable, Equatable {
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

struct BoardSizeRecord: Codable, Equatable {
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

struct BoardRectRecord: Codable, Equatable {
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
