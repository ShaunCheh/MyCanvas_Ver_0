import CoreGraphics
import Foundation

enum HandDrawingInputNormalizer {
    struct Configuration: Equatable {
        static let brushStroke = Configuration()

        let minimumSampleDistance: CGFloat
        let minimumTimestampDelta: TimeInterval
        let minimumForce: CGFloat
        let maximumForce: CGFloat

        init(
            minimumSampleDistance: CGFloat = 0.5,
            minimumTimestampDelta: TimeInterval = 0.0001,
            minimumForce: CGFloat = 0.05,
            maximumForce: CGFloat = 1
        ) {
            self.minimumSampleDistance = max(minimumSampleDistance, 0)
            self.minimumTimestampDelta = max(minimumTimestampDelta, 0)
            self.minimumForce = max(minimumForce, 0)
            self.maximumForce = max(maximumForce, self.minimumForce)
        }
    }

    static func normalized(
        _ rawSamples: [HandDrawingInputSample],
        appendingTo existingSamples: [HandDrawingInputSample] = [],
        configuration: Configuration = .brushStroke
    ) -> [HandDrawingInputSample] {
        var normalizedSamples = existingSamples

        for rawSample in rawSamples {
            guard
                var sample = sanitized(
                    rawSample,
                    previousSample: normalizedSamples.last,
                    configuration: configuration
                )
            else {
                continue
            }

            if let previousSample = normalizedSamples.last {
                let distance = hypot(
                    sample.location.x - previousSample.location.x,
                    sample.location.y - previousSample.location.y
                )
                if distance < configuration.minimumSampleDistance {
                    normalizedSamples[normalizedSamples.count - 1] = sample
                    continue
                }

                if sample.timestamp <= previousSample.timestamp {
                    sample.timestamp = previousSample.timestamp
                        + configuration.minimumTimestampDelta
                }
            }

            normalizedSamples.append(sample)
        }

        return normalizedSamples
    }

    private static func sanitized(
        _ rawSample: HandDrawingInputSample,
        previousSample: HandDrawingInputSample?,
        configuration: Configuration
    ) -> HandDrawingInputSample? {
        guard
            rawSample.location.x.isFinite,
            rawSample.location.y.isFinite
        else {
            return nil
        }

        let previousTimestamp = previousSample?.timestamp ?? 0
        let rawTimestamp = rawSample.timestamp.isFinite
            ? rawSample.timestamp
            : previousTimestamp
        let resolvedTimestamp: TimeInterval
        if previousSample == nil {
            resolvedTimestamp = rawTimestamp
        } else {
            resolvedTimestamp = max(
                rawTimestamp,
                previousTimestamp + configuration.minimumTimestampDelta
            )
        }

        let rawForce = rawSample.force.isFinite
            ? rawSample.force
            : previousSample?.force ?? configuration.maximumForce
        let resolvedForce = min(
            max(rawForce, configuration.minimumForce),
            configuration.maximumForce
        )

        return HandDrawingInputSample(
            location: rawSample.location,
            force: resolvedForce,
            timestamp: resolvedTimestamp,
            azimuthRadians: sanitizedAngle(rawSample.azimuthRadians),
            altitudeRadians: sanitizedAngle(rawSample.altitudeRadians)
        )
    }

    private static func sanitizedAngle(_ angle: CGFloat?) -> CGFloat? {
        guard let angle, angle.isFinite else {
            return nil
        }
        return angle
    }
}
