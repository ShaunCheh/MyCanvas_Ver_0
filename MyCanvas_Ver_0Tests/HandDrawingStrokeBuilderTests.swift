import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingStrokeBuilderTests: XCTestCase {
    func testHandDrawingStrokeBuilderBuildsSamplePointsFromNormalizedInputSamples() throws {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 20),
                    force: 0.3,
                    timestamp: 0,
                    azimuthRadians: 0.1,
                    altitudeRadians: 0.9
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 54, y: 44),
                    force: 0.8,
                    timestamp: 0.2,
                    azimuthRadians: 0.4,
                    altitudeRadians: 0.7
                )
            ]
        )

        let samplePoints = HandDrawingStrokeBuilder.makeSamplePoints(
            fromNormalizedSamples: normalizedSamples
        )
        let firstSamplePoint = try XCTUnwrap(samplePoints.first)
        let secondSamplePoint = try XCTUnwrap(samplePoints.last)

        XCTAssertEqual(samplePoints.count, 2)
        XCTAssertEqual(firstSamplePoint.cgPoint.x, 18, accuracy: 0.001)
        XCTAssertEqual(firstSamplePoint.cgPoint.y, 20, accuracy: 0.001)
        XCTAssertEqual(firstSamplePoint.force, 0.3, accuracy: 0.001)
        XCTAssertEqual(firstSamplePoint.timestamp, 0, accuracy: 0.001)
        let firstAzimuthRadians = try XCTUnwrap(firstSamplePoint.azimuthRadians)
        let firstAltitudeRadians = try XCTUnwrap(firstSamplePoint.altitudeRadians)
        XCTAssertEqual(firstAzimuthRadians, 0.1, accuracy: 0.001)
        XCTAssertEqual(firstAltitudeRadians, 0.9, accuracy: 0.001)

        XCTAssertEqual(secondSamplePoint.cgPoint.x, 54, accuracy: 0.001)
        XCTAssertEqual(secondSamplePoint.cgPoint.y, 44, accuracy: 0.001)
        XCTAssertEqual(secondSamplePoint.force, 0.8, accuracy: 0.001)
        XCTAssertEqual(secondSamplePoint.timestamp, 0.2, accuracy: 0.001)
        let secondAzimuthRadians = try XCTUnwrap(secondSamplePoint.azimuthRadians)
        let secondAltitudeRadians = try XCTUnwrap(secondSamplePoint.altitudeRadians)
        XCTAssertEqual(secondAzimuthRadians, 0.4, accuracy: 0.001)
        XCTAssertEqual(secondAltitudeRadians, 0.7, accuracy: 0.001)
    }

    func testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.2, green: 0.35, blue: 0.88, alpha: 1),
            baseSize: 12,
            opacity: 1
        )
        let rawSamples = [
            HandDrawingInputSample(
                location: CGPoint(x: 20, y: 20),
                force: 0.2,
                timestamp: 1
            ),
            HandDrawingInputSample(
                location: CGPoint(x: 20.1, y: 20.1),
                force: 0.35,
                timestamp: 0.9
            ),
            HandDrawingInputSample(
                location: CGPoint(x: 64, y: 56),
                force: 0.9,
                timestamp: 1.1,
                azimuthRadians: 0.7,
                altitudeRadians: 0.5
            )
        ]
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            rawSamples,
            configuration: HandDrawingStrokePerformanceProfile
                .brushStroke(for: brush)
                .inputNormalization
        )
        let draftStroke = try XCTUnwrap(
            HandDrawingStrokeBuilder.makeStroke(
                brush: brush,
                normalizedSamples: normalizedSamples
            )
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "phase2-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )

        let committedStroke = try XCTUnwrap(
            engine.appendStroke(
                brush: brush,
                samples: rawSamples
            )
        )

        XCTAssertEqual(draftStroke.brush, committedStroke.brush)
        XCTAssertEqual(draftStroke.transform, committedStroke.transform)
        XCTAssertEqual(draftStroke.samplePoints, committedStroke.samplePoints)
    }

    func testHandDrawingStrokeBuilderUsesBrushAwareSamplingForLargeBrushes() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 18,
            opacity: 1
        )
        let stroke = try XCTUnwrap(
            HandDrawingStrokeBuilder.makeStroke(
                brush: brush,
                samples: [
                    HandDrawingInputSample(
                        location: CGPoint(x: 10, y: 20),
                        force: 1,
                        timestamp: 0
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 10.7, y: 20),
                        force: 0.9,
                        timestamp: 0.01
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 11.4, y: 20),
                        force: 0.85,
                        timestamp: 0.02
                    ),
                    HandDrawingInputSample(
                        location: CGPoint(x: 16, y: 20),
                        force: 0.8,
                        timestamp: 0.03
                    )
                ]
            )
        )

        XCTAssertEqual(stroke.samplePoints.count, 2)
        XCTAssertEqual(stroke.samplePoints[0].cgPoint.x, 11.4, accuracy: 0.001)
        XCTAssertEqual(stroke.samplePoints[1].cgPoint.x, 16, accuracy: 0.001)
    }
}
