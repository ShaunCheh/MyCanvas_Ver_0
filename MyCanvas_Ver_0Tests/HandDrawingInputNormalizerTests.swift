import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingInputNormalizerTests: XCTestCase {
    func testHandDrawingInputNormalizerReplacesNearbySamplesAndMonotonizesTimestamps() throws {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 10, y: 10),
                    force: 0,
                    timestamp: 1,
                    azimuthRadians: 0.2,
                    altitudeRadians: 0.4
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 10.2, y: 10.2),
                    force: 0.4,
                    timestamp: 0.5,
                    azimuthRadians: .infinity,
                    altitudeRadians: -.infinity
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 12, y: 10),
                    force: 1.4,
                    timestamp: 0.5,
                    azimuthRadians: 0.8,
                    altitudeRadians: 0.6
                )
            ]
        )

        XCTAssertEqual(normalizedSamples.count, 2)
        XCTAssertEqual(normalizedSamples[0].location.x, 10.2, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[0].location.y, 10.2, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[0].force, 0.4, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[0].timestamp, 1.0001, accuracy: 0.0001)
        XCTAssertNil(normalizedSamples[0].azimuthRadians)
        XCTAssertNil(normalizedSamples[0].altitudeRadians)

        XCTAssertEqual(normalizedSamples[1].location.x, 12, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[1].location.y, 10, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[1].force, 1, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[1].timestamp, 1.0002, accuracy: 0.0001)
        let azimuthRadians = try XCTUnwrap(normalizedSamples[1].azimuthRadians)
        let altitudeRadians = try XCTUnwrap(normalizedSamples[1].altitudeRadians)
        XCTAssertEqual(azimuthRadians, 0.8, accuracy: 0.001)
        XCTAssertEqual(altitudeRadians, 0.6, accuracy: 0.001)
    }

    func testHandDrawingInputNormalizerDropsSamplesWithInvalidLocations() {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: CGFloat.nan, y: 10),
                    force: 0.5,
                    timestamp: 0
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 10, y: CGFloat.infinity),
                    force: 0.5,
                    timestamp: 0.1
                )
            ]
        )

        XCTAssertTrue(normalizedSamples.isEmpty)
    }
}
