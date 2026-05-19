import CoreGraphics
import Foundation
import PencilKit

enum HandDrawingDocumentLoaderError: LocalizedError {
    case invalidSourceData

    var errorDescription: String? {
        switch self {
        case .invalidSourceData:
            return "Failed to load the hand drawing document from source data."
        }
    }
}

enum HandDrawingDocumentLoader {
    static func loadDocument(
        from data: Data,
        paper: CanvasHandDrawingPaperSpec
    ) throws -> HandDrawingDocument {
        if data.isEmpty {
            return HandDrawingDocument(paper: HandDrawingPaper(paper))
        }

        if let document = try? HandDrawingDocumentCodec.decodeDocument(from: data) {
            return document
        }

        if let legacyDrawing = try? PKDrawing(data: data) {
            return HandDrawingLegacyPencilKitBridge.makeDocument(
                from: legacyDrawing,
                paper: paper
            )
        }

        throw HandDrawingDocumentLoaderError.invalidSourceData
    }

    static func normalizeDocumentData(
        from data: Data,
        paper: CanvasHandDrawingPaperSpec
    ) throws -> Data {
        try HandDrawingDocumentCodec.makeDocumentData(
            for: loadDocument(from: data, paper: paper)
        )
    }
}

enum HandDrawingLegacyPencilKitBridge {
    static func makeDocument(
        from drawing: PKDrawing,
        paper: CanvasHandDrawingPaperSpec
    ) -> HandDrawingDocument {
        let strokes = drawing.strokes.compactMap(makeStroke(from:))
        return HandDrawingDocument(
            paper: HandDrawingPaper(paper),
            strokes: strokes
        )
    }

    private static func makeStroke(
        from legacyStroke: PKStroke
    ) -> HandDrawingStroke? {
        let points = resolvedInterpolatedPoints(for: legacyStroke.path)
        guard points.isEmpty == false else {
            return nil
        }

        let transformedPoints = points.map { point in
            makeSamplePoint(
                from: point,
                applying: legacyStroke.transform
            )
        }
        let resolvedBrush = makeBrushStyle(
            from: legacyStroke,
            using: points
        )
        return HandDrawingStroke(
            brush: resolvedBrush,
            samplePoints: transformedPoints
        )
    }

    private static func resolvedInterpolatedPoints(
        for path: PKStrokePath
    ) -> [PKStrokePoint] {
        guard path.isEmpty == false else {
            return []
        }
        guard path.count > 1 else {
            return Array(path)
        }

        let widestPoint = path.reduce(CGFloat(0)) { partialResult, point in
            max(partialResult, max(point.size.width, point.size.height))
        }
        let distanceStep = max(widestPoint * 0.25, 1)
        return Array(
            path.interpolatedPoints(
                in: nil,
                by: .distance(distanceStep)
            )
        )
    }

    private static func makeBrushStyle(
        from legacyStroke: PKStroke,
        using points: [PKStrokePoint]
    ) -> HandDrawingBrushStyle {
        let color = HandDrawingColor(platformColor: legacyStroke.ink.color)
        let averageForce = points.reduce(Double(0)) { partialResult, point in
            partialResult + Double(max(point.force, 0.05))
        } / Double(max(points.count, 1))
        let averageWidth = points.reduce(Double(0)) { partialResult, point in
            partialResult + Double(max(point.size.width, point.size.height))
        } / Double(max(points.count, 1))
        let averageOpacity = points.reduce(Double(0)) { partialResult, point in
            partialResult + Double(point.opacity)
        } / Double(max(points.count, 1))
        let resolvedBaseSize = max(averageWidth / max(averageForce, 0.05), 0.25)

        return HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: resolvedBaseSize,
            opacity: averageOpacity
        )
    }

    private static func makeSamplePoint(
        from legacyPoint: PKStrokePoint,
        applying transform: CGAffineTransform
    ) -> HandDrawingSamplePoint {
        HandDrawingSamplePoint(
            point: legacyPoint.location.applying(transform),
            force: Double(max(legacyPoint.force, 0.05)),
            timestamp: legacyPoint.timeOffset,
            azimuthRadians: Double(legacyPoint.azimuth),
            altitudeRadians: Double(legacyPoint.altitude)
        )
    }
}
