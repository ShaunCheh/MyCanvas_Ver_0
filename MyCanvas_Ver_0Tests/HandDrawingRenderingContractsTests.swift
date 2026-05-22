import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingRenderingContractsTests: XCTestCase {
    func testHandDrawingCPURealtimeBrushRendererReturnsDraftStrokeFromPacket() throws {
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
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
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
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 96, y: 60),
                    force: 0.95,
                    timestamp: 0.2,
                    azimuthRadians: 0.75,
                    altitudeRadians: .pi / 5
                )
            ],
            configuration: performanceProfile.inputNormalization
        )
        let draftStroke = try XCTUnwrap(
            HandDrawingStrokeBuilder.makeStroke(
                brush: brush,
                normalizedSamples: normalizedSamples
            )
        )
        let packet = HandDrawingRealtimeDraftPacket(
            brush: brush,
            performanceProfile: performanceProfile,
            normalizedSamples: normalizedSamples,
            draftStroke: draftStroke,
            resolvedStamps: HandDrawingBrushDynamics.resolvedStamps(
                for: draftStroke,
                layout: performanceProfile.stampLayout
            )
        )
        let renderer = HandDrawingCPURealtimeBrushRenderer()

        XCTAssertNil(renderer.render(packet: nil).stroke)
        XCTAssertEqual(renderer.render(packet: packet).stroke, draftStroke)
    }
}
