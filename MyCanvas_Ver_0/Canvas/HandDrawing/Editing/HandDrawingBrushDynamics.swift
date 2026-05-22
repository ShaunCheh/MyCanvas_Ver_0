import CoreGraphics
import Foundation

struct HandDrawingResolvedStampLayout: Equatable {
    let relativeSpacingFactor: CGFloat
    let minimumSpacing: CGFloat

    init(
        relativeSpacingFactor: CGFloat = 0.5,
        minimumSpacing: CGFloat = 0.5
    ) {
        self.relativeSpacingFactor = max(relativeSpacingFactor, 0.05)
        self.minimumSpacing = max(minimumSpacing, 0.05)
    }
}

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
    let rotationRadians: CGFloat

    var minorRadius: CGFloat {
        max(radius, 0.25)
    }

    var majorRadius: CGFloat {
        max(tiltAdjustedRadius, minorRadius)
    }

    var axisAlignedBounds: CGRect {
        let cosTheta = cos(rotationRadians)
        let sinTheta = sin(rotationRadians)
        let halfWidth = sqrt(
            pow(majorRadius * cosTheta, 2)
                + pow(minorRadius * sinTheta, 2)
        )
        let halfHeight = sqrt(
            pow(majorRadius * sinTheta, 2)
                + pow(minorRadius * cosTheta, 2)
        )
        return CGRect(
            x: point.x - halfWidth,
            y: point.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
    }

    func contains(
        _ candidatePoint: CGPoint,
        padding: CGFloat = 0
    ) -> Bool {
        let resolvedMajorRadius = max(majorRadius + padding, 0.25)
        let resolvedMinorRadius = max(minorRadius + padding, 0.25)
        let translatedX = candidatePoint.x - point.x
        let translatedY = candidatePoint.y - point.y
        let cosTheta = cos(rotationRadians)
        let sinTheta = sin(rotationRadians)
        let localX = (translatedX * cosTheta) + (translatedY * sinTheta)
        let localY = (-translatedX * sinTheta) + (translatedY * cosTheta)
        let normalizedDistance = (
            pow(localX / resolvedMajorRadius, 2)
                + pow(localY / resolvedMinorRadius, 2)
        )
        return normalizedDistance <= 1
    }

    func probePoints(
        sampleCount: Int = 8,
        padding: CGFloat = 0
    ) -> [CGPoint] {
        let resolvedMajorRadius = max(majorRadius + padding, 0.5)
        let resolvedMinorRadius = max(minorRadius + padding, 0.5)
        let resolvedSampleCount = max(sampleCount, 4)
        let step = (CGFloat.pi * 2) / CGFloat(resolvedSampleCount)
        var points: [CGPoint] = [point]
        points.reserveCapacity(resolvedSampleCount + 1)

        for index in 0..<resolvedSampleCount {
            let angle = CGFloat(index) * step
            let localX = cos(angle) * resolvedMajorRadius
            let localY = sin(angle) * resolvedMinorRadius
            let cosTheta = cos(rotationRadians)
            let sinTheta = sin(rotationRadians)
            points.append(
                CGPoint(
                    x: point.x + (localX * cosTheta) - (localY * sinTheta),
                    y: point.y + (localX * sinTheta) + (localY * cosTheta)
                )
            )
        }

        return points
    }
}

enum HandDrawingBrushDynamics {
    private static let defaultMinimumSizeRatio: CGFloat = 0.05
    private static let defaultPressureCurveExponent: CGFloat = 1

    struct ResolvedStampUpdate: Equatable {
        let resolvedStamps: [HandDrawingResolvedBrushSample]
        let stablePrefixCount: Int

        var tailStamps: [HandDrawingResolvedBrushSample] {
            Array(resolvedStamps.dropFirst(stablePrefixCount))
        }
    }

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

    static func resolvedStamps(
        brush: HandDrawingBrushStyle,
        normalizedSamples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity,
        layout: HandDrawingResolvedStampLayout? = nil
    ) -> [HandDrawingResolvedBrushSample] {
        guard let stroke = HandDrawingStrokeBuilder.makeStroke(
            brush: brush,
            normalizedSamples: normalizedSamples,
            transform: transform
        ) else {
            return []
        }
        return resolvedStamps(for: stroke, layout: layout)
    }

    static func resolvedStampUpdate(
        brush: HandDrawingBrushStyle,
        normalizedSamples: [HandDrawingInputSample],
        previousResolvedStamps: [HandDrawingResolvedBrushSample] = [],
        transform: HandDrawingStrokeTransform = .identity,
        layout: HandDrawingResolvedStampLayout? = nil
    ) -> ResolvedStampUpdate {
        let resolvedStamps = resolvedStamps(
            brush: brush,
            normalizedSamples: normalizedSamples,
            transform: transform,
            layout: layout
        )
        return ResolvedStampUpdate(
            resolvedStamps: resolvedStamps,
            stablePrefixCount: commonPrefixCount(
                between: previousResolvedStamps,
                and: resolvedStamps
            )
        )
    }

    static func resolvedStamps(
        for stroke: HandDrawingStroke,
        layout: HandDrawingResolvedStampLayout? = nil
    ) -> [HandDrawingResolvedBrushSample] {
        let anchorSamples = resolvedSamples(for: stroke)
        guard anchorSamples.count > 1 else {
            return anchorSamples
        }
        let resolvedLayout = layout
            ?? HandDrawingStrokePerformanceProfile.brushStroke(for: stroke.brush)
                .stampLayout

        var resolvedStamps: [HandDrawingResolvedBrushSample] = [
            anchorSamples[0]
        ]
        resolvedStamps.reserveCapacity(anchorSamples.count * 4)

        for index in 1..<anchorSamples.count {
            resolvedStamps.append(
                contentsOf: interpolatedStamps(
                    from: anchorSamples[index - 1],
                    to: anchorSamples[index],
                    layout: resolvedLayout
                )
            )
        }

        return resolvedStamps
    }

    static func bounds(
        for stroke: HandDrawingStroke
    ) -> CGRect? {
        var accumulatedBounds: CGRect?
        for sample in resolvedStamps(for: stroke) {
            let pointBounds = sample.axisAlignedBounds
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
            tiltAdjustedRadius: max(radius * tiltSizeFactor, radius),
            opacity: resolvedOpacity,
            pressureSizeRatio: pressureSizeRatio,
            tiltSizeFactor: tiltSizeFactor,
            tiltOpacityFactor: tiltOpacityFactor,
            azimuthRadians: sample.azimuthRadians.map { CGFloat($0) },
            altitudeRadians: sample.altitudeRadians.map { CGFloat($0) },
            rotationRadians: sample.azimuthRadians.map { CGFloat($0) } ?? 0
        )
    }

    private static func interpolatedStamps(
        from start: HandDrawingResolvedBrushSample,
        to end: HandDrawingResolvedBrushSample,
        layout: HandDrawingResolvedStampLayout
    ) -> [HandDrawingResolvedBrushSample] {
        let distance = hypot(
            end.point.x - start.point.x,
            end.point.y - start.point.y
        )
        let stepDistance = interpolationStepDistance(
            from: start,
            to: end,
            layout: layout
        )
        let stepCount = max(Int(ceil(distance / stepDistance)), 1)
        return (1...stepCount).map { index in
            let fraction = CGFloat(index) / CGFloat(stepCount)
            return interpolatedStamp(
                from: start,
                to: end,
                fraction: fraction
            )
        }
    }

    private static func interpolationStepDistance(
        from start: HandDrawingResolvedBrushSample,
        to end: HandDrawingResolvedBrushSample,
        layout: HandDrawingResolvedStampLayout
    ) -> CGFloat {
        max(
            min(start.minorRadius, end.minorRadius) * layout.relativeSpacingFactor,
            layout.minimumSpacing
        )
    }

    private static func interpolatedStamp(
        from start: HandDrawingResolvedBrushSample,
        to end: HandDrawingResolvedBrushSample,
        fraction: CGFloat
    ) -> HandDrawingResolvedBrushSample {
        let interpolatedPoint = CGPoint(
            x: start.point.x + ((end.point.x - start.point.x) * fraction),
            y: start.point.y + ((end.point.y - start.point.y) * fraction)
        )
        let rotationRadians = interpolatedAngle(
            from: start.rotationRadians,
            to: end.rotationRadians,
            fraction: fraction
        )
        return HandDrawingResolvedBrushSample(
            point: interpolatedPoint,
            radius: interpolatedValue(
                from: start.radius,
                to: end.radius,
                fraction: fraction
            ),
            tiltAdjustedRadius: interpolatedValue(
                from: start.tiltAdjustedRadius,
                to: end.tiltAdjustedRadius,
                fraction: fraction
            ),
            opacity: interpolatedValue(
                from: start.opacity,
                to: end.opacity,
                fraction: fraction
            ),
            pressureSizeRatio: interpolatedValue(
                from: start.pressureSizeRatio,
                to: end.pressureSizeRatio,
                fraction: fraction
            ),
            tiltSizeFactor: interpolatedValue(
                from: start.tiltSizeFactor,
                to: end.tiltSizeFactor,
                fraction: fraction
            ),
            tiltOpacityFactor: interpolatedValue(
                from: start.tiltOpacityFactor,
                to: end.tiltOpacityFactor,
                fraction: fraction
            ),
            azimuthRadians: interpolatedOptionalValue(
                from: start.azimuthRadians,
                to: end.azimuthRadians,
                fraction: fraction
            ) ?? rotationRadians,
            altitudeRadians: interpolatedOptionalValue(
                from: start.altitudeRadians,
                to: end.altitudeRadians,
                fraction: fraction
            ),
            rotationRadians: rotationRadians
        )
    }

    private static func interpolatedValue(
        from start: CGFloat,
        to end: CGFloat,
        fraction: CGFloat
    ) -> CGFloat {
        start + ((end - start) * fraction)
    }

    private static func interpolatedOptionalValue(
        from start: CGFloat?,
        to end: CGFloat?,
        fraction: CGFloat
    ) -> CGFloat? {
        switch (start, end) {
        case let (start?, end?):
            return interpolatedValue(from: start, to: end, fraction: fraction)
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        case (nil, nil):
            return nil
        }
    }

    private static func interpolatedAngle(
        from start: CGFloat,
        to end: CGFloat,
        fraction: CGFloat
    ) -> CGFloat {
        let delta = normalizedAngle(end - start)
        return normalizedAngle(start + (delta * fraction))
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        var resolvedAngle = angle.truncatingRemainder(dividingBy: twoPi)
        if resolvedAngle <= -.pi {
            resolvedAngle += twoPi
        } else if resolvedAngle > .pi {
            resolvedAngle -= twoPi
        }
        return resolvedAngle
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

    private static func commonPrefixCount<T: Equatable>(
        between lhs: [T],
        and rhs: [T]
    ) -> Int {
        let maximumSharedCount = min(lhs.count, rhs.count)
        for index in 0..<maximumSharedCount where lhs[index] != rhs[index] {
            return index
        }
        return maximumSharedCount
    }
}
