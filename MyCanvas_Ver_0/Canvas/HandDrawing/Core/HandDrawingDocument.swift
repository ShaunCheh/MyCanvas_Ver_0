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

    private enum CodingKeys: String, CodingKey {
        case kind
        case color
        case baseSize
        case opacity
        case pressureCurveExponent
        case minSizeRatio
        case maxSizeRatio
        case tiltSizeInfluence
        case tiltOpacityInfluence
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
    var pressureCurveExponent: Double?
    var minSizeRatio: Double?
    var maxSizeRatio: Double?
    var tiltSizeInfluence: Double?
    var tiltOpacityInfluence: Double?

    init(
        kind: Kind = .pen,
        color: HandDrawingColor = .black,
        baseSize: Double = 6,
        opacity: Double = 1,
        pressureCurveExponent: Double? = nil,
        minSizeRatio: Double? = nil,
        maxSizeRatio: Double? = nil,
        tiltSizeInfluence: Double? = nil,
        tiltOpacityInfluence: Double? = nil
    ) {
        self.kind = kind
        self.color = color
        let resolvedBaseSize = baseSize.isFinite ? baseSize : 6
        let resolvedOpacity = opacity.isFinite ? opacity : 1
        let resolvedMinSizeRatio = Self.normalizedNonNegativeOptional(minSizeRatio)
        self.baseSize = max(resolvedBaseSize, 0.25)
        self.opacity = min(max(resolvedOpacity, 0), 1)
        self.pressureCurveExponent = Self.normalizedPositiveOptional(
            pressureCurveExponent
        )
        self.minSizeRatio = resolvedMinSizeRatio
        self.maxSizeRatio = Self.normalizedMaximumOptional(
            maxSizeRatio,
            minimum: resolvedMinSizeRatio
        )
        self.tiltSizeInfluence = Self.normalizedNonNegativeOptional(
            tiltSizeInfluence
        )
        self.tiltOpacityInfluence = Self.normalizedNonNegativeOptional(
            tiltOpacityInfluence
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .pen,
            color: try container.decodeIfPresent(
                HandDrawingColor.self,
                forKey: .color
            ) ?? .black,
            baseSize: try container.decodeIfPresent(Double.self, forKey: .baseSize)
                ?? 6,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity)
                ?? 1,
            pressureCurveExponent: try container.decodeIfPresent(
                Double.self,
                forKey: .pressureCurveExponent
            ),
            minSizeRatio: try container.decodeIfPresent(
                Double.self,
                forKey: .minSizeRatio
            ),
            maxSizeRatio: try container.decodeIfPresent(
                Double.self,
                forKey: .maxSizeRatio
            ),
            tiltSizeInfluence: try container.decodeIfPresent(
                Double.self,
                forKey: .tiltSizeInfluence
            ),
            tiltOpacityInfluence: try container.decodeIfPresent(
                Double.self,
                forKey: .tiltOpacityInfluence
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(color, forKey: .color)
        try container.encode(baseSize, forKey: .baseSize)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(
            pressureCurveExponent,
            forKey: .pressureCurveExponent
        )
        try container.encodeIfPresent(minSizeRatio, forKey: .minSizeRatio)
        try container.encodeIfPresent(maxSizeRatio, forKey: .maxSizeRatio)
        try container.encodeIfPresent(tiltSizeInfluence, forKey: .tiltSizeInfluence)
        try container.encodeIfPresent(
            tiltOpacityInfluence,
            forKey: .tiltOpacityInfluence
        )
    }

    private static func normalizedPositiveOptional(
        _ value: Double?
    ) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }
        return max(value, 0.01)
    }

    private static func normalizedNonNegativeOptional(
        _ value: Double?
    ) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }
        return max(value, 0)
    }

    private static func normalizedMaximumOptional(
        _ value: Double?,
        minimum: Double?
    ) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }
        let resolvedMinimum = minimum ?? 0
        return max(value, resolvedMinimum)
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
        HandDrawingBrushDynamics.radius(
            forSampleAt: index,
            in: self
        )
    }

    var bounds: CGRect? {
        HandDrawingBrushDynamics.bounds(for: self)
    }
}

struct HandDrawingLayer: Codable, Equatable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var strokes: [HandDrawingStroke]

    init(
        id: UUID = UUID(),
        name: String = "",
        isVisible: Bool = true,
        isLocked: Bool = false,
        strokes: [HandDrawingStroke] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.strokes = strokes
    }

    var isEmpty: Bool {
        strokes.allSatisfy(\.isEmpty)
    }

    var isInteractive: Bool {
        isVisible && isLocked == false
    }

    var renderedBounds: CGRect? {
        strokes.compactMap(\.bounds).reduce(nil) { partialResult, bounds in
            partialResult?.union(bounds) ?? bounds
        }
    }

    func stroke(withID id: UUID) -> HandDrawingStroke? {
        strokes.first { $0.id == id }
    }
}

struct HandDrawingDocument: Codable, Equatable {
    static let currentFormatVersion = 2
    private static let defaultLayerBaseName = "Layer"

    let formatVersion: Int
    var paper: HandDrawingPaper
    private(set) var layers: [HandDrawingLayer]
    private(set) var activeLayerID: UUID

    init(
        paper: HandDrawingPaper = .square,
        strokes: [HandDrawingStroke] = [],
        formatVersion: Int = Self.currentFormatVersion
    ) {
        let defaultLayer = HandDrawingLayer(
            name: Self.defaultLayerName(at: 1),
            strokes: strokes
        )
        self.init(
            paper: paper,
            layers: [defaultLayer],
            activeLayerID: defaultLayer.id,
            formatVersion: formatVersion
        )
    }

    init(
        paper: HandDrawingPaper = .square,
        layers: [HandDrawingLayer],
        activeLayerID: UUID? = nil,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = Self.normalizedFormatVersion(formatVersion)
        self.paper = paper
        let normalizedLayers = Self.normalizedLayers(layers)
        self.layers = normalizedLayers
        self.activeLayerID = Self.resolvedActiveLayerID(
            activeLayerID,
            layers: normalizedLayers
        )
    }

    var strokes: [HandDrawingStroke] {
        get {
            activeLayer?.strokes ?? []
        }
        set {
            replaceStrokesInActiveLayer(with: newValue)
        }
    }

    var allStrokes: [HandDrawingStroke] {
        layers.flatMap(\.strokes)
    }

    var visibleLayersInRenderOrder: [HandDrawingLayer] {
        layers.filter(\.isVisible)
    }

    var renderedStrokesInOrder: [HandDrawingStroke] {
        visibleLayersInRenderOrder.flatMap(\.strokes)
    }

    var activeLayer: HandDrawingLayer? {
        guard let index = activeLayerIndex else {
            return nil
        }
        return layers[index]
    }

    var activeLayerStrokes: [HandDrawingStroke] {
        activeLayer?.strokes ?? []
    }

    var activeLayerStrokeIDs: Set<UUID> {
        Set(activeLayerStrokes.map(\.id))
    }

    var isActiveLayerInteractive: Bool {
        activeLayer?.isInteractive ?? false
    }

    var activeLayerIndex: Int? {
        layers.firstIndex { $0.id == activeLayerID }
    }

    var paperBounds: CGRect {
        CGRect(origin: .zero, size: paper.size)
    }

    var isEmpty: Bool {
        layers.allSatisfy(\.isEmpty)
    }

    var renderedBounds: CGRect? {
        layers.compactMap(\.renderedBounds).reduce(nil) { partialResult, bounds in
            partialResult?.union(bounds) ?? bounds
        }
    }

    mutating func appendStroke(_ stroke: HandDrawingStroke) {
        ensureActiveLayerExists()
        layers[activeLayerIndex ?? 0].strokes.append(stroke)
    }

    func stroke(withID id: UUID) -> HandDrawingStroke? {
        layers.lazy.compactMap { $0.stroke(withID: id) }.first
    }

    func layer(withID id: UUID) -> HandDrawingLayer? {
        layers.first { $0.id == id }
    }

    @discardableResult
    mutating func setActiveLayer(withID layerID: UUID) -> Bool {
        guard layers.contains(where: { $0.id == layerID }) else {
            return false
        }
        activeLayerID = layerID
        return true
    }

    @discardableResult
    mutating func ensureActiveLayerExists() -> UUID {
        if let activeLayerIndex {
            return layers[activeLayerIndex].id
        }
        if layers.isEmpty {
            let defaultLayer = Self.makeDefaultLayer(at: 1)
            layers = [defaultLayer]
            activeLayerID = defaultLayer.id
            return defaultLayer.id
        }
        activeLayerID = layers[0].id
        return activeLayerID
    }

    @discardableResult
    mutating func insertLayer(
        named proposedName: String? = nil,
        afterLayerID anchorLayerID: UUID? = nil
    ) -> HandDrawingLayer {
        ensureActiveLayerExists()
        let resolvedAnchorLayerID = anchorLayerID ?? activeLayerID
        let insertionIndex: Int
        if let anchorIndex = layers.firstIndex(where: { $0.id == resolvedAnchorLayerID }) {
            insertionIndex = min(anchorIndex + 1, layers.count)
        } else {
            insertionIndex = layers.count
        }
        let layer = HandDrawingLayer(
            name: Self.resolvedLayerName(
                proposedName,
                fallbackIndex: insertionIndex + 1,
                existingLayers: layers
            )
        )
        layers.insert(layer, at: insertionIndex)
        activeLayerID = layer.id
        return layer
    }

    @discardableResult
    mutating func removeLayer(withID layerID: UUID) -> HandDrawingLayer? {
        guard
            layers.count > 1,
            let removedIndex = layers.firstIndex(where: { $0.id == layerID })
        else {
            return nil
        }
        let removedLayer = layers.remove(at: removedIndex)
        if activeLayerID == layerID {
            let fallbackIndex = min(removedIndex, layers.count - 1)
            activeLayerID = layers[fallbackIndex].id
        } else {
            _ = ensureActiveLayerExists()
        }
        return removedLayer
    }

    @discardableResult
    mutating func renameLayer(
        withID layerID: UUID,
        to proposedName: String
    ) -> Bool {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return false
        }
        let resolvedName = Self.resolvedLayerName(
            proposedName,
            fallbackIndex: layerIndex + 1,
            existingLayers: layers,
            excludingLayerID: layerID
        )
        guard layers[layerIndex].name != resolvedName else {
            return false
        }
        layers[layerIndex].name = resolvedName
        return true
    }

    @discardableResult
    mutating func moveLayer(
        withID layerID: UUID,
        toIndex proposedIndex: Int
    ) -> Bool {
        guard let currentIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return false
        }
        let destinationIndex = min(max(proposedIndex, 0), layers.count - 1)
        guard currentIndex != destinationIndex else {
            return false
        }
        let layer = layers.remove(at: currentIndex)
        layers.insert(layer, at: destinationIndex)
        return true
    }

    @discardableResult
    mutating func setLayerVisibility(
        withID layerID: UUID,
        isVisible: Bool
    ) -> Bool {
        updateLayer(withID: layerID) { layer in
            layer.isVisible = isVisible
        }
    }

    @discardableResult
    mutating func setLayerLock(
        withID layerID: UUID,
        isLocked: Bool
    ) -> Bool {
        updateLayer(withID: layerID) { layer in
            layer.isLocked = isLocked
        }
    }

    mutating func replaceStrokesInActiveLayer(with strokes: [HandDrawingStroke]) {
        ensureActiveLayerExists()
        layers[activeLayerIndex ?? 0].strokes = strokes
    }

    @discardableResult
    private mutating func updateLayer(
        withID layerID: UUID,
        mutation: (inout HandDrawingLayer) -> Void
    ) -> Bool {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return false
        }
        let originalLayer = layers[layerIndex]
        mutation(&layers[layerIndex])
        return layers[layerIndex] != originalLayer
    }

    private static func normalizedFormatVersion(_ formatVersion: Int) -> Int {
        formatVersion == currentFormatVersion
            ? formatVersion
            : currentFormatVersion
    }

    private static func normalizedLayers(
        _ layers: [HandDrawingLayer]
    ) -> [HandDrawingLayer] {
        guard layers.isEmpty == false else {
            return [makeDefaultLayer(at: 1)]
        }
        return layers.enumerated().map { index, layer in
            var normalizedLayer = layer
            let trimmedName = layer.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            normalizedLayer.name = trimmedName.isEmpty
                ? defaultLayerName(at: index + 1)
                : trimmedName
            return normalizedLayer
        }
    }

    private static func resolvedActiveLayerID(
        _ proposedActiveLayerID: UUID?,
        layers: [HandDrawingLayer]
    ) -> UUID {
        if let proposedActiveLayerID,
           layers.contains(where: { $0.id == proposedActiveLayerID })
        {
            return proposedActiveLayerID
        }
        return layers[0].id
    }

    private static func makeDefaultLayer(at index: Int) -> HandDrawingLayer {
        HandDrawingLayer(name: defaultLayerName(at: index))
    }

    private static func defaultLayerName(at index: Int) -> String {
        "\(defaultLayerBaseName) \(max(index, 1))"
    }

    private static func resolvedLayerName(
        _ proposedName: String?,
        fallbackIndex: Int,
        existingLayers: [HandDrawingLayer],
        excludingLayerID: UUID? = nil
    ) -> String {
        let trimmedName = (proposedName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else {
            return trimmedName
        }
        let existingDefaultNames = Set(
            existingLayers
                .filter { $0.id != excludingLayerID }
                .map {
                    $0.name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                }
        )
        var candidateIndex = max(fallbackIndex, 1)
        var candidateName = defaultLayerName(at: candidateIndex)
        while existingDefaultNames.contains(candidateName.lowercased()) {
            candidateIndex += 1
            candidateName = defaultLayerName(at: candidateIndex)
        }
        return candidateName
    }
}
