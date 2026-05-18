import CoreGraphics
import Foundation

struct HandDrawingColor: Codable, Equatable {
    static let black = HandDrawingColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let clear = HandDrawingColor(red: 0, green: 0, blue: 0, alpha: 0)

    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1
    ) {
        self.red = Self.clampedUnit(red)
        self.green = Self.clampedUnit(green)
        self.blue = Self.clampedUnit(blue)
        self.alpha = Self.clampedUnit(alpha)
    }

    var cgColor: CGColor {
        CGColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    func withMultipliedAlpha(_ multiplier: Double) -> HandDrawingColor {
        HandDrawingColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha * Self.clampedUnit(multiplier)
        )
    }

    private static func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct HandDrawingPaper: Codable, Equatable {
    static let minimumDimension: CGFloat = 1
    static let square = HandDrawingPaper(
        id: "square",
        size: CGSize(width: 1_024, height: 1_024)
    )

    var id: String
    var width: Double
    var height: Double

    init(
        id: String,
        size: CGSize
    ) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmedID.isEmpty ? "custom" : trimmedID
        width = Double(max(size.width, Self.minimumDimension))
        height = Double(max(size.height, Self.minimumDimension))
    }

    init(_ paper: CanvasHandDrawingPaperSpec) {
        self.init(id: paper.id, size: paper.size)
    }

    var size: CGSize {
        CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    var canvasPaperSpec: CanvasHandDrawingPaperSpec {
        CanvasHandDrawingPaperSpec(id: id, size: size)
    }
}

struct HandDrawingBrushStyle: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case pen
    }

    static let defaultPen = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 6,
        opacity: 1
    )

    var kind: Kind
    var color: HandDrawingColor
    var baseSize: Double
    var opacity: Double

    init(
        kind: Kind = .pen,
        color: HandDrawingColor = .black,
        baseSize: Double = 6,
        opacity: Double = 1
    ) {
        self.kind = kind
        self.color = color
        self.baseSize = max(baseSize, 0.25)
        self.opacity = min(max(opacity, 0), 1)
    }
}

struct HandDrawingSamplePoint: Codable, Equatable {
    var x: Double
    var y: Double
    var force: Double
    var timestamp: Double
    var azimuthRadians: Double?
    var altitudeRadians: Double?

    init(
        point: CGPoint,
        force: Double = 1,
        timestamp: Double = 0,
        azimuthRadians: Double? = nil,
        altitudeRadians: Double? = nil
    ) {
        x = Double(point.x)
        y = Double(point.y)
        self.force = force
        self.timestamp = timestamp
        self.azimuthRadians = azimuthRadians
        self.altitudeRadians = altitudeRadians
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    var resolvedForce: CGFloat {
        CGFloat(max(force, 0.05))
    }
}

struct HandDrawingEraseSamplePoint: Codable, Equatable {
    var x: Double
    var y: Double
    var radius: Double
    var opacity: Double

    init(
        point: CGPoint,
        radius: Double,
        opacity: Double = 1
    ) {
        x = Double(point.x)
        y = Double(point.y)
        self.radius = max(radius, 0.25)
        self.opacity = min(max(opacity, 0), 1)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    var resolvedRadius: CGFloat {
        CGFloat(max(radius, 0.25))
    }
}

struct HandDrawingErasePath: Codable, Equatable {
    let id: UUID
    var samplePoints: [HandDrawingEraseSamplePoint]

    init(
        id: UUID = UUID(),
        samplePoints: [HandDrawingEraseSamplePoint]
    ) {
        self.id = id
        self.samplePoints = samplePoints
    }
}

struct HandDrawingStrokeTransform: Codable, Equatable {
    static let identity = HandDrawingStrokeTransform()

    var translationX: Double
    var translationY: Double
    var scaleX: Double
    var scaleY: Double
    var rotationRadians: Double

    init(
        translationX: Double = 0,
        translationY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotationRadians: Double = 0
    ) {
        self.translationX = translationX
        self.translationY = translationY
        self.scaleX = scaleX == 0 ? 1 : scaleX
        self.scaleY = scaleY == 0 ? 1 : scaleY
        self.rotationRadians = rotationRadians
    }

    func apply(to point: CGPoint) -> CGPoint {
        let scaledX = point.x * CGFloat(scaleX)
        let scaledY = point.y * CGFloat(scaleY)
        let rotation = CGFloat(rotationRadians)
        let cosTheta = cos(rotation)
        let sinTheta = sin(rotation)
        let rotatedX = scaledX * cosTheta - scaledY * sinTheta
        let rotatedY = scaledX * sinTheta + scaledY * cosTheta
        return CGPoint(
            x: rotatedX + CGFloat(translationX),
            y: rotatedY + CGFloat(translationY)
        )
    }
}

struct HandDrawingStroke: Codable, Equatable {
    let id: UUID
    var brush: HandDrawingBrushStyle
    var samplePoints: [HandDrawingSamplePoint]
    var transform: HandDrawingStrokeTransform
    var eraseMask: [HandDrawingErasePath]

    init(
        id: UUID = UUID(),
        brush: HandDrawingBrushStyle = .defaultPen,
        samplePoints: [HandDrawingSamplePoint],
        transform: HandDrawingStrokeTransform = .identity,
        eraseMask: [HandDrawingErasePath] = []
    ) {
        self.id = id
        self.brush = brush
        self.samplePoints = samplePoints
        self.transform = transform
        self.eraseMask = eraseMask
    }

    var transformedSamplePoints: [CGPoint] {
        samplePoints.map { transform.apply(to: $0.cgPoint) }
    }

    var isEmpty: Bool {
        samplePoints.isEmpty
    }

    func radiusForSample(at index: Int) -> CGFloat {
        guard samplePoints.indices.contains(index) else {
            return CGFloat(brush.baseSize) / 2
        }
        return CGFloat(brush.baseSize) * samplePoints[index].resolvedForce / 2
    }

    var bounds: CGRect? {
        var accumulatedBounds: CGRect?
        let transformedPoints = transformedSamplePoints
        for (index, point) in transformedPoints.enumerated() {
            let radius = radiusForSample(at: index)
            let pointBounds = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
        }
        for erasePath in eraseMask {
            for erasePoint in erasePath.samplePoints {
                let transformedPoint = transform.apply(to: erasePoint.cgPoint)
                let radius = erasePoint.resolvedRadius
                let eraseBounds = CGRect(
                    x: transformedPoint.x - radius,
                    y: transformedPoint.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                accumulatedBounds = accumulatedBounds?.union(eraseBounds) ?? eraseBounds
            }
        }
        return accumulatedBounds
    }
}

struct HandDrawingDocument: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    var paper: HandDrawingPaper
    var strokes: [HandDrawingStroke]

    init(
        paper: HandDrawingPaper = .square,
        strokes: [HandDrawingStroke] = [],
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.paper = paper
        self.strokes = strokes
    }

    var paperBounds: CGRect {
        CGRect(origin: .zero, size: paper.size)
    }

    var isEmpty: Bool {
        strokes.allSatisfy(\.isEmpty)
    }

    var renderedBounds: CGRect? {
        strokes.compactMap(\.bounds).reduce(nil) { partialResult, bounds in
            partialResult?.union(bounds) ?? bounds
        }
    }

    mutating func appendStroke(_ stroke: HandDrawingStroke) {
        strokes.append(stroke)
    }

    func stroke(withID id: UUID) -> HandDrawingStroke? {
        strokes.first { $0.id == id }
    }
}
