import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingRenderingContractsTests: XCTestCase {
    func testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately() {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 12,
            opacity: 0.9,
            tiltSizeInfluence: 0.65,
            tiltOpacityInfluence: 0.14
        )
        let performanceProfile = HandDrawingStrokePerformanceProfile
            .brushStroke(for: brush)
        let strokeID = UUID()

        let committedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 20, y: 24),
                    force: 0.4,
                    timestamp: 0
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 58, y: 42),
                    force: 0.72,
                    timestamp: 0.1,
                    azimuthRadians: 0.42,
                    altitudeRadians: .pi / 4
                )
            ],
            configuration: performanceProfile.inputNormalization
        )
        let committedResolvedStamps = HandDrawingBrushDynamics.resolvedStamps(
            brush: brush,
            normalizedSamples: committedSamples,
            layout: performanceProfile.stampLayout
        )
        let predictedTailSamples = HandDrawingInputNormalizer.normalizedPredictedTail(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 96, y: 60),
                    force: 0.95,
                    timestamp: 0.2,
                    azimuthRadians: 0.75,
                    altitudeRadians: .pi / 5
                )
            ],
            onto: committedSamples,
            configuration: performanceProfile.inputNormalization
        )
        let predictedTailUpdate = HandDrawingBrushDynamics.resolvedStampUpdate(
            brush: brush,
            normalizedSamples: committedSamples + predictedTailSamples,
            previousResolvedStamps: committedResolvedStamps,
            layout: performanceProfile.stampLayout
        )

        let packet = HandDrawingRealtimeDraftPacket(
            strokeID: strokeID,
            brush: brush,
            performanceProfile: performanceProfile,
            committedSamples: HandDrawingRealtimeNormalizedSampleUpdate(
                stablePrefixCount: 1,
                tailSamples: Array(committedSamples.dropFirst())
            ),
            committedResolvedStamps: HandDrawingRealtimeResolvedStampUpdate(
                stablePrefixCount: committedResolvedStamps.count,
                tailStamps: []
            ),
            predictedTail: HandDrawingRealtimePredictedTail(
                normalizedSamples: predictedTailSamples,
                resolvedStamps: predictedTailUpdate.tailStamps
            )
        )

        XCTAssertEqual(packet.strokeID, strokeID)
        XCTAssertEqual(packet.brush, brush)
        XCTAssertEqual(packet.performanceProfile, performanceProfile)
        XCTAssertEqual(packet.committedSamples.stablePrefixCount, 1)
        XCTAssertEqual(packet.committedSamples.tailSamples.count, 1)
        XCTAssertEqual(packet.predictedTail.normalizedSamples.count, 1)
        XCTAssertFalse(packet.predictedTail.resolvedStamps.isEmpty)
    }
}
