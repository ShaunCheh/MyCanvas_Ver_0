import CoreGraphics
import Foundation

struct HandDrawingResolvedBrushSample: Equatable {
    let point: CGPoint
    let radius: CGFloat
    let tiltAdjustedRadius: CGFloat
    let opacity: CGFloat
    let pressureSizeRatio: CGFloat
    let tiltSizeFactor: CGFloat
    let tiltOpacityFactor: CGFloat
    let azimuthRadians: CGFloat?
    let altitudeRadians: CGFloat?
}

enum HandDrawingBrushDynamics {
    private static let defaultMinimumSizeRatio: CGFloat = 0.05
    private static let defaultPressureCurveExponent: CGFloat = 1

    struct Configuration: Equatable {
        let baseSize: CGFloat
        let baseOpacity: CGFloat
        let pressureCurveExponent: CGFloat
        let minSizeRatio: CGFloat
        let maxSizeRatio: CGFloat?
        let tiltSizeInfluence: CGFloat
        let tiltOpacityInfluence: CGFloat
    }

    static func configuration(
        for brush: HandDrawingBrushStyle
    ) -> Configuration {
        Configuration(
            baseSize: CGFloat(brush.baseSize),
            baseOpacity: CGFloat(brush.opacity),
            pressureCurveExponent: CGFloat(
                brush.pressureCurveExponent ?? Double(defaultPressureCurveExponent)
            ),
            minSizeRatio: CGFloat(
                brush.minSizeRatio ?? Double(defaultMinimumSizeRatio)
            ),
            maxSizeRatio: brush.maxSizeRatio.map { CGFloat($0) },
            tiltSizeInfluence: CGFloat(brush.tiltSizeInfluence ?? 0),
            tiltOpacityInfluence: CGFloat(brush.tiltOpacityInfluence ?? 0)
        )
    }

    static func radius(
        forSampleAt index: Int,
        in stroke: HandDrawingStroke
    ) -> CGFloat {
        let sample = stroke.samplePoints.indices.contains(index)
            ? stroke.samplePoints[index]
            : nil
        return radius(for: sample, with: stroke.brush)
    }

    static func radius(
        for sample: HandDrawingSamplePoint?,
        with brush: HandDrawingBrushStyle
    ) -> CGFloat {
        let configuration = configuration(for: brush)
        return resolveRadius(for: sample, configuration: configuration)
    }

    static func resolvedSamples(
        for stroke: HandDrawingStroke
    ) -> [HandDrawingResolvedBrushSample] {
        let transformedPoints = stroke.transformedSamplePoints
        let configuration = configuration(for: stroke.brush)
        return stroke.samplePoints.enumerated().compactMap { index, sample in
            guard transformedPoints.indices.contains(index) else {
                return nil
            }
            return resolveSample(
                sample,
                point: transformedPoints[index],
                configuration: configuration
            )
        }
    }

    static func bounds(
        for stroke: HandDrawingStroke
    ) -> CGRect? {
        var accumulatedBounds: CGRect?
        for sample in resolvedSamples(for: stroke) {
            // Phase 1 keeps bounds on the current pressure-only radius.
            let pointBounds = CGRect(
                x: sample.point.x - sample.radius,
                y: sample.point.y - sample.radius,
                width: sample.radius * 2,
                height: sample.radius * 2
            )
            accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
        }
        for erasePath in stroke.eraseMask {
            for erasePoint in erasePath.samplePoints {
                let transformedPoint = stroke.transform.apply(to: erasePoint.cgPoint)
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

    private static func resolveSample(
        _ sample: HandDrawingSamplePoint,
        point: CGPoint,
        configuration: Configuration
    ) -> HandDrawingResolvedBrushSample {
        let pressureSizeRatio = resolvePressureSizeRatio(
            for: sample,
            configuration: configuration
        )
        let radius = (configuration.baseSize * pressureSizeRatio) / 2
        let tiltSizeFactor = resolveTiltFactor(
            altitudeRadians: sample.altitudeRadians,
            influence: configuration.tiltSizeInfluence
        )
        let tiltOpacityFactor = resolveTiltFactor(
            altitudeRadians: sample.altitudeRadians,
            influence: configuration.tiltOpacityInfluence
        )
        let resolvedOpacity = min(
            max(configuration.baseOpacity * tiltOpacityFactor, CGFloat.zero),
            CGFloat(1)
        )
        return HandDrawingResolvedBrushSample(
            point: point,
            radius: radius,
            tiltAdjustedRadius: radius * tiltSizeFactor,
            opacity: resolvedOpacity,
            pressureSizeRatio: pressureSizeRatio,
            tiltSizeFactor: tiltSizeFactor,
            tiltOpacityFactor: tiltOpacityFactor,
            azimuthRadians: sample.azimuthRadians.map { CGFloat($0) },
            altitudeRadians: sample.altitudeRadians.map { CGFloat($0) }
        )
    }

    private static func resolveRadius(
        for sample: HandDrawingSamplePoint?,
        configuration: Configuration
    ) -> CGFloat {
        let sizeRatio = resolvePressureSizeRatio(
            for: sample,
            configuration: configuration
        )
        return (configuration.baseSize * sizeRatio) / 2
    }

    private static func resolvePressureSizeRatio(
        for sample: HandDrawingSamplePoint?,
        configuration: Configuration
    ) -> CGFloat {
        let rawForce = sample?.force ?? 1
        let finiteForce = rawForce.isFinite ? rawForce : 1
        let inputRatio = max(CGFloat(finiteForce), configuration.minSizeRatio)
        var resolvedSizeRatio = CGFloat(
            Foundation.pow(
                Double(inputRatio),
                Double(configuration.pressureCurveExponent)
            )
        )
        resolvedSizeRatio = max(resolvedSizeRatio, configuration.minSizeRatio)
        if let maxSizeRatio = configuration.maxSizeRatio {
            resolvedSizeRatio = min(resolvedSizeRatio, maxSizeRatio)
        }
        return resolvedSizeRatio
    }

    private static func resolveTiltFactor(
        altitudeRadians: Double?,
        influence: CGFloat
    ) -> CGFloat {
        guard
            influence > 0,
            let normalizedTilt = normalizedTilt(
                altitudeRadians: altitudeRadians
            )
        else {
            return 1
        }
        return 1 + (normalizedTilt * influence)
    }

    private static func normalizedTilt(
        altitudeRadians: Double?
    ) -> CGFloat? {
        guard
            let altitudeRadians,
            altitudeRadians.isFinite
        else {
            return nil
        }
        let maximumAltitude = CGFloat.pi / 2
        let clampedAltitude = min(
            max(CGFloat(altitudeRadians), 0),
            maximumAltitude
        )
        return 1 - (clampedAltitude / maximumAltitude)
    }
}
