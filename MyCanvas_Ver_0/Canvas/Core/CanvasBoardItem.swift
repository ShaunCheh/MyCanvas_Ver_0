import CoreGraphics
import Foundation

enum CanvasBoardItemKind: Equatable {
    case image
    case text
    case markdown
    case handDrawing
}

struct CanvasTextColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let black = CanvasTextColor(
        red: 0,
        green: 0,
        blue: 0,
        alpha: 1
    )

    init(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
        self.alpha = Self.clamped(alpha)
    }

    private static func clamped(_ component: CGFloat) -> CGFloat {
        min(max(component, 0), 1)
    }
}

struct CanvasTextStyle: Equatable {
    private static let fallbackFontName = "System"

    var fontName: String
    var fontSize: CGFloat
    var color: CanvasTextColor

    static let `default` = CanvasTextStyle()

    init(
        fontName: String = CanvasTextStyle.fallbackFontName,
        fontSize: CGFloat = 32,
        color: CanvasTextColor = .black
    ) {
        self.fontName = fontName.isEmpty
            ? Self.fallbackFontName
            : fontName
        self.fontSize = max(fontSize, 1)
        self.color = color
    }
}

struct CanvasTextItem {
    let id: CanvasItemID
    var text: String
    var style: CanvasTextStyle
    var center: CGPoint
    // Text size is the shared layout bounds consumed by rendering, hit-testing,
    // and selection geometry. Shared text measurement should own new text sizes
    // so every surface follows the same contract.
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    init(
        id: CanvasItemID = UUID(),
        text: String,
        style: CanvasTextStyle = .default,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.rotationRadians = rotationRadians
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

struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    // Markdown keeps explicit canvas container geometry in the model. Width is
    // the persisted layout width source; height is the committed container or
    // clip height and may intentionally differ from the current intrinsic
    // content height after manual resize.
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    init(
        id: CanvasItemID = UUID(),
        markdownSource: String,
        style: CanvasTextStyle = .default,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.markdownSource = markdownSource
        self.style = style
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.rotationRadians = rotationRadians
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

    func matchesDocumentState(_ other: CanvasMarkdownItem) -> Bool {
        id == other.id &&
            markdownSource == other.markdownSource &&
            style == other.style &&
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

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)
    case markdown(CanvasMarkdownItem)
    case handDrawing(CanvasHandDrawingItem)

    var kind: CanvasBoardItemKind {
        switch self {
        case .image:
            return .image
        case .text:
            return .text
        case .markdown:
            return .markdown
        case .handDrawing:
            return .handDrawing
        }
    }

    var id: CanvasItemID {
        switch self {
        case let .image(item):
            return item.id
        case let .text(item):
            return item.id
        case let .markdown(item):
            return item.id
        case let .handDrawing(item):
            return item.id
        }
    }

    var center: CGPoint {
        get {
            switch self {
            case let .image(item):
                return item.center
            case let .text(item):
                return item.center
            case let .markdown(item):
                return item.center
            case let .handDrawing(item):
                return item.center
            }
        }
        set {
            switch self {
            case var .image(item):
                item.center = newValue
                self = .image(item)
            case var .text(item):
                item.center = newValue
                self = .text(item)
            case var .markdown(item):
                item.center = newValue
                self = .markdown(item)
            case var .handDrawing(item):
                item.center = newValue
                self = .handDrawing(item)
            }
        }
    }

    var size: CGSize {
        get {
            switch self {
            case let .image(item):
                return item.size
            case let .text(item):
                return item.size
            case let .markdown(item):
                return item.size
            case let .handDrawing(item):
                return item.size
            }
        }
        set {
            switch self {
            case var .image(item):
                item.size = newValue
                self = .image(item)
            case var .text(item):
                item.size = newValue
                self = .text(item)
            case var .markdown(item):
                item.size = newValue
                self = .markdown(item)
            case var .handDrawing(item):
                item.size = newValue
                self = .handDrawing(item)
            }
        }
    }

    var zIndex: CGFloat {
        get {
            switch self {
            case let .image(item):
                return item.zIndex
            case let .text(item):
                return item.zIndex
            case let .markdown(item):
                return item.zIndex
            case let .handDrawing(item):
                return item.zIndex
            }
        }
        set {
            switch self {
            case var .image(item):
                item.zIndex = newValue
                self = .image(item)
            case var .text(item):
                item.zIndex = newValue
                self = .text(item)
            case var .markdown(item):
                item.zIndex = newValue
                self = .markdown(item)
            case var .handDrawing(item):
                item.zIndex = newValue
                self = .handDrawing(item)
            }
        }
    }

    var rotationRadians: CGFloat {
        get {
            switch self {
            case let .image(item):
                return item.rotationRadians
            case let .text(item):
                return item.rotationRadians
            case let .markdown(item):
                return item.rotationRadians
            case let .handDrawing(item):
                return item.rotationRadians
            }
        }
        set {
            switch self {
            case var .image(item):
                item.rotationRadians = newValue
                self = .image(item)
            case var .text(item):
                item.rotationRadians = newValue
                self = .text(item)
            case var .markdown(item):
                item.rotationRadians = newValue
                self = .markdown(item)
            case var .handDrawing(item):
                item.rotationRadians = newValue
                self = .handDrawing(item)
            }
        }
    }

    var localFrame: CGRect {
        switch self {
        case let .image(item):
            return item.localFrame
        case let .text(item):
            return item.localFrame
        case let .markdown(item):
            return item.localFrame
        case let .handDrawing(item):
            return item.localFrame
        }
    }

    var worldQuad: CanvasQuad {
        switch self {
        case let .image(item):
            return item.worldQuad
        case let .text(item):
            return item.worldQuad
        case let .markdown(item):
            return item.worldQuad
        case let .handDrawing(item):
            return item.worldQuad
        }
    }

    var worldFrame: CGRect {
        switch self {
        case let .image(item):
            return item.worldFrame
        case let .text(item):
            return item.worldFrame
        case let .markdown(item):
            return item.worldFrame
        case let .handDrawing(item):
            return item.worldFrame
        }
    }

    var worldBounds: CGRect {
        switch self {
        case let .image(item):
            return item.worldBounds
        case let .text(item):
            return item.worldBounds
        case let .markdown(item):
            return item.worldBounds
        case let .handDrawing(item):
            return item.worldBounds
        }
    }

    var imageItem: CanvasImageItem? {
        guard case let .image(item) = self else {
            return nil
        }

        return item
    }

    var textItem: CanvasTextItem? {
        guard case let .text(item) = self else {
            return nil
        }

        return item
    }

    var markdownItem: CanvasMarkdownItem? {
        guard case let .markdown(item) = self else {
            return nil
        }

        return item
    }

    var handDrawingItem: CanvasHandDrawingItem? {
        guard case let .handDrawing(item) = self else {
            return nil
        }

        return item
    }

    func contains(worldPoint: CGPoint) -> Bool {
        switch self {
        case let .image(item):
            return item.contains(worldPoint: worldPoint)
        case let .text(item):
            return item.contains(worldPoint: worldPoint)
        case let .markdown(item):
            return item.contains(worldPoint: worldPoint)
        case let .handDrawing(item):
            return item.contains(worldPoint: worldPoint)
        }
    }

    func worldPoint(fromLocal localPoint: CGPoint) -> CGPoint {
        switch self {
        case let .image(item):
            return item.worldPoint(fromLocal: localPoint)
        case let .text(item):
            return item.worldPoint(fromLocal: localPoint)
        case let .markdown(item):
            return item.worldPoint(fromLocal: localPoint)
        case let .handDrawing(item):
            return item.worldPoint(fromLocal: localPoint)
        }
    }
}
