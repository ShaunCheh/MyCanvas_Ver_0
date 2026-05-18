import CoreGraphics
import Foundation

struct CanvasHandDrawingPaperSpec: Equatable {
    private static let fallbackID = "custom"
    private static let minimumDimension: CGFloat = 1

    let id: String
    let size: CGSize

    static let square = CanvasHandDrawingPaperSpec(
        id: "square",
        size: CGSize(width: 1_024, height: 1_024)
    )

    init(
        id: String,
        size: CGSize
    ) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmedID.isEmpty ? Self.fallbackID : trimmedID
        self.size = Self.sanitizedSize(size)
    }

    var aspectRatio: CGFloat {
        size.width / max(size.height, Self.minimumDimension)
    }

    private static func sanitizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width, minimumDimension),
            height: max(size.height, minimumDimension)
        )
    }
}

struct CanvasHandDrawingItem {
    static let previewImageFileExtension = "png"
    static let sourceDrawingFileExtension = "pkdrawing"
    private static let minimumCanvasDimension: CGFloat = 1

    let id: CanvasItemID
    var paper: CanvasHandDrawingPaperSpec
    var previewAsset: CanvasImageAsset
    var isEmpty: Bool
    var contentRevision: UUID
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    init(
        id: CanvasItemID = UUID(),
        paper: CanvasHandDrawingPaperSpec = .square,
        previewAsset: CanvasImageAsset,
        isEmpty: Bool,
        contentRevision: UUID = UUID(),
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.paper = paper
        self.previewAsset = previewAsset
        self.isEmpty = isEmpty
        self.contentRevision = contentRevision
        self.center = center
        self.size = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
        self.zIndex = zIndex
        self.rotationRadians = rotationRadians
    }

    var previewImageFilename: String {
        Self.defaultPreviewImageFilename(for: id)
    }

    var sourceDrawingFilename: String {
        Self.defaultSourceDrawingFilename(for: id)
    }

    var localFrame: CGRect {
        CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var localQuad: CanvasQuad {
        CanvasQuad(rect: localFrame)
    }

    var worldQuad: CanvasQuad {
        localQuad.map(worldPoint(fromLocal:))
    }

    var worldFrame: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var worldBounds: CGRect {
        worldQuad.boundingRect
    }

    var currentPaperScale: CGFloat {
        let resolvedPaperSize = paper.size
        let widthScale = size.width / max(
            resolvedPaperSize.width,
            Self.minimumCanvasDimension
        )
        let heightScale = size.height / max(
            resolvedPaperSize.height,
            Self.minimumCanvasDimension
        )
        return max(widthScale, heightScale)
    }

    static func defaultPreviewImageFilename(
        for itemID: CanvasItemID
    ) -> String {
        "\(itemID.uuidString).\(previewImageFileExtension)"
    }

    static func defaultSourceDrawingFilename(
        for itemID: CanvasItemID
    ) -> String {
        "\(itemID.uuidString).\(sourceDrawingFileExtension)"
    }

    static func persistedPreviewAsset(
        for itemID: CanvasItemID,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil
    ) -> CanvasImageAsset {
        CanvasImageAsset.persistedStaticImage(
            filename: defaultPreviewImageFilename(for: itemID),
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize
        )
    }

    func normalizedCanvasSize(for proposedSize: CGSize) -> CGSize {
        let resolvedPaperSize = paper.size
        let sanitizedSize = CGSize(
            width: max(proposedSize.width, Self.minimumCanvasDimension),
            height: max(proposedSize.height, Self.minimumCanvasDimension)
        )
        let widthScale = sanitizedSize.width / max(
            resolvedPaperSize.width,
            Self.minimumCanvasDimension
        )
        let heightScale = sanitizedSize.height / max(
            resolvedPaperSize.height,
            Self.minimumCanvasDimension
        )
        let resolvedScale = max(widthScale, heightScale)
        return CGSize(
            width: max(
                resolvedPaperSize.width * resolvedScale,
                Self.minimumCanvasDimension
            ),
            height: max(
                resolvedPaperSize.height * resolvedScale,
                Self.minimumCanvasDimension
            )
        )
    }

    func scaledCanvasSize(by scale: CGFloat) -> CGSize {
        let resolvedScale = max(scale, 0)
        return normalizedCanvasSize(
            for: CGSize(
                width: paper.size.width * currentPaperScale * resolvedScale,
                height: paper.size.height * currentPaperScale * resolvedScale
            )
        )
    }

    func resized(
        center: CGPoint,
        proposedSize: CGSize,
        rotationRadians: CGFloat? = nil
    ) -> CanvasHandDrawingItem {
        CanvasHandDrawingItem(
            id: id,
            paper: paper,
            previewAsset: previewAsset,
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            center: center,
            size: normalizedCanvasSize(for: proposedSize),
            zIndex: zIndex,
            rotationRadians: rotationRadians ?? self.rotationRadians
        )
    }

    func contains(worldPoint: CGPoint) -> Bool {
        localFrame.contains(localPoint(fromWorld: worldPoint))
    }

    func worldPoint(fromLocal localPoint: CGPoint) -> CGPoint {
        let rotatedPoint = Self.rotated(localPoint, by: rotationRadians)
        return CGPoint(
            x: rotatedPoint.x + center.x,
            y: rotatedPoint.y + center.y
        )
    }

    func localPoint(fromWorld worldPoint: CGPoint) -> CGPoint {
        let translatedPoint = CGPoint(
            x: worldPoint.x - center.x,
            y: worldPoint.y - center.y
        )
        return Self.rotated(translatedPoint, by: -rotationRadians)
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasHandDrawingItem {
        let duplicatedID = UUID()
        return CanvasHandDrawingItem(
            id: duplicatedID,
            paper: paper,
            previewAsset: Self.persistedPreviewAsset(
                for: duplicatedID,
                cgImage: previewAsset.posterCGImage,
                logicalPixelSize: previewAsset.logicalPixelSize
            ),
            isEmpty: isEmpty,
            contentRevision: contentRevision,
            center: CGPoint(
                x: center.x + offsetInWorld.x,
                y: center.y + offsetInWorld.y
            ),
            size: normalizedCanvasSize(for: size),
            zIndex: zIndex,
            rotationRadians: rotationRadians
        )
    }

    func matchesDocumentState(_ other: CanvasHandDrawingItem) -> Bool {
        id == other.id &&
            paper == other.paper &&
            isEmpty == other.isEmpty &&
            contentRevision == other.contentRevision &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            rotationRadians == other.rotationRadians
    }

    private static func rotated(
        _ point: CGPoint,
        by radians: CGFloat
    ) -> CGPoint {
        guard radians != 0 else {
            return point
        }

        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }
}
