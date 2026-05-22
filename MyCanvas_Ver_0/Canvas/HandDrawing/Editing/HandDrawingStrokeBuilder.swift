import Foundation

enum HandDrawingStrokeBuilder {
    static func makeStroke(
        brush: HandDrawingBrushStyle,
        samples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity,
        normalization: HandDrawingInputNormalizer.Configuration? = nil
    ) -> HandDrawingStroke? {
        let resolvedNormalization = normalization
            ?? HandDrawingStrokePerformanceProfile.brushStroke(for: brush)
                .inputNormalization
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            samples,
            configuration: resolvedNormalization
        )
        return makeStroke(
            brush: brush,
            normalizedSamples: normalizedSamples,
            transform: transform
        )
    }

    static func makeStroke(
        brush: HandDrawingBrushStyle,
        normalizedSamples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity
    ) -> HandDrawingStroke? {
        let samplePoints = makeSamplePoints(
            fromNormalizedSamples: normalizedSamples
        )
        guard samplePoints.isEmpty == false else {
            return nil
        }
        return HandDrawingStroke(
            brush: brush,
            samplePoints: samplePoints,
            transform: transform
        )
    }

    static func makeSamplePoints(
        from samples: [HandDrawingInputSample],
        normalization: HandDrawingInputNormalizer.Configuration = .brushStroke
    ) -> [HandDrawingSamplePoint] {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            samples,
            configuration: normalization
        )
        return makeSamplePoints(fromNormalizedSamples: normalizedSamples)
    }

    static func makeSamplePoints(
        fromNormalizedSamples normalizedSamples: [HandDrawingInputSample]
    ) -> [HandDrawingSamplePoint] {
        normalizedSamples.map {
            HandDrawingSamplePoint(
                point: $0.location,
                force: Double($0.force),
                timestamp: $0.timestamp,
                azimuthRadians: $0.azimuthRadians.map(Double.init),
                altitudeRadians: $0.altitudeRadians.map(Double.init)
            )
        }
    }
}
