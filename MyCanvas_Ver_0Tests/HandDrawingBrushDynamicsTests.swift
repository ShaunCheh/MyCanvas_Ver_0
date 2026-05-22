import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingBrushDynamicsTests: XCTestCase {
    func testHandDrawingBrushDynamicsDefaultConfigurationMatchesCurrentPressureOnlyRadiusMapping() {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 0.8
        )
        let lowPressureSample = HandDrawingSamplePoint(
            point: .zero,
            force: 0.25,
            timestamp: 0
        )
        let highPressureSample = HandDrawingSamplePoint(
            point: .zero,
            force: 1,
            timestamp: 0.1
        )
        let floorPressureSample = HandDrawingSamplePoint(
            point: .zero,
            force: 0.01,
            timestamp: 0.2
        )

        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: lowPressureSample,
                with: brush
            ),
            2.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: highPressureSample,
                with: brush
            ),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: floorPressureSample,
                with: brush
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: nil,
                with: brush
            ),
            10,
            accuracy: 0.001
        )
    }

    func testHandDrawingBrushDynamicsCustomPressureCurveAndBoundsStayInSync() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 1,
            pressureCurveExponent: 2,
            minSizeRatio: 0.2,
            maxSizeRatio: 0.8
        )
        let stroke = HandDrawingStroke(
            brush: brush,
            samplePoints: [
                HandDrawingSamplePoint(
                    point: CGPoint(x: 25, y: 60),
                    force: 0.1,
                    timestamp: 0
                ),
                HandDrawingSamplePoint(
                    point: CGPoint(x: 60, y: 60),
                    force: 0.5,
                    timestamp: 0.1
                ),
                HandDrawingSamplePoint(
                    point: CGPoint(x: 95, y: 60),
                    force: 1,
                    timestamp: 0.2
                )
            ]
        )

        XCTAssertEqual(stroke.radiusForSample(at: 0), 2, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 1), 2.5, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 2), 8, accuracy: 0.001)

        let bounds = try XCTUnwrap(stroke.bounds)
        XCTAssertEqual(bounds.minX, 23, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 103, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 52, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 68, accuracy: 0.001)
    }

    func testHandDrawingBrushDynamicsResolvesTiltFactorsWithoutChangingCurrentRadiusSemantics() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 0.8,
            tiltSizeInfluence: 0.6,
            tiltOpacityInfluence: 0.25
        )
        let stroke = HandDrawingStroke(
            brush: brush,
            samplePoints: [
                HandDrawingSamplePoint(
                    point: CGPoint(x: 24, y: 24),
                    force: 0.5,
                    timestamp: 0,
                    azimuthRadians: 1.1,
                    altitudeRadians: .pi / 6
                )
            ]
        )

        let resolvedSample = try XCTUnwrap(
            HandDrawingBrushDynamics.resolvedSamples(for: stroke).first
        )

        XCTAssertEqual(resolvedSample.radius, 5, accuracy: 0.001)
        XCTAssertGreaterThan(
            resolvedSample.tiltAdjustedRadius,
            resolvedSample.radius
        )
        XCTAssertEqual(resolvedSample.rotationRadians, 1.1, accuracy: 0.001)
        XCTAssertGreaterThan(resolvedSample.majorRadius, resolvedSample.minorRadius)
        XCTAssertGreaterThan(resolvedSample.opacity, 0.8)
        XCTAssertGreaterThan(resolvedSample.tiltSizeFactor, 1)
        XCTAssertGreaterThan(resolvedSample.tiltOpacityFactor, 1)
        let azimuthRadians = try XCTUnwrap(resolvedSample.azimuthRadians)
        let altitudeRadians = try XCTUnwrap(resolvedSample.altitudeRadians)
        XCTAssertEqual(azimuthRadians, 1.1, accuracy: 0.001)
        XCTAssertEqual(
            altitudeRadians,
            .pi / 6,
            accuracy: 0.001
        )
    }

    func testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent() throws {
        let stroke = makeHandDrawingTestStroke(
            baseSize: 20,
            samplePoints: [CGPoint(x: 60, y: 60)],
            sampleForces: [0.5],
            sampleAzimuths: [.pi / 4],
            sampleAltitudes: [0],
            tiltSizeInfluence: 1
        )

        let resolvedStamp = try XCTUnwrap(
            HandDrawingBrushDynamics.resolvedStamps(for: stroke).first
        )
        let bounds = try XCTUnwrap(stroke.bounds)
        let expectedHalfExtent = sqrt(62.5)

        XCTAssertEqual(resolvedStamp.minorRadius, 5, accuracy: 0.001)
        XCTAssertEqual(resolvedStamp.majorRadius, 10, accuracy: 0.001)
        XCTAssertEqual(bounds.minX, 60 - expectedHalfExtent, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 60 + expectedHalfExtent, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 60 - expectedHalfExtent, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 60 + expectedHalfExtent, accuracy: 0.001)
    }

    func testHandDrawingBrushPresetCatalogResolvesDefaultPresetAndBuildsFullBrushStyle() throws {
        let presets = HandDrawingBrushPresetCatalog.defaultPenPresets(
            lineWidths: [4, 8, 12, 18],
            tiltSizeInfluence: 0.85,
            tiltOpacityInfluence: 0
        )
        let selectedColor = HandDrawingColor(
            red: 0.18,
            green: 0.46,
            blue: 0.81,
            alpha: 1
        )
        let selectedBrush = presets[2].makeBrushStyle(color: selectedColor)
        let selection = HandDrawingBrushPresetCatalog.resolveSelection(
            for: selectedBrush,
            presets: presets
        )
        let selectedPreset = try XCTUnwrap(
            selection.availablePresets.first { $0.id == selection.selectedPresetID }
        )

        XCTAssertEqual(selection.selectedPresetID, presets[2].id)
        XCTAssertEqual(selection.availablePresets, presets)
        XCTAssertEqual(
            selectedPreset.makeBrushStyle(color: selectedColor),
            selectedBrush
        )
        XCTAssertEqual(
            try XCTUnwrap(selectedPreset.brushTemplate.tiltSizeInfluence),
            0.85,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(selectedPreset.brushTemplate.tiltOpacityInfluence),
            0,
            accuracy: 0.001
        )
    }

    func testHandDrawingBrushPresetCatalogPreservesDocumentBrushDynamicsAtMatchingWidth() throws {
        let presets = HandDrawingBrushPresetCatalog.defaultPenPresets(
            lineWidths: [4, 8, 12, 18],
            tiltSizeInfluence: 0.85,
            tiltOpacityInfluence: 0
        )
        let reopenedBrush = HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.73, green: 0.22, blue: 0.4, alpha: 1),
            baseSize: 8,
            opacity: 0.76,
            pressureCurveExponent: 1.7,
            minSizeRatio: 0.18,
            maxSizeRatio: 0.94,
            tiltSizeInfluence: 0.42,
            tiltOpacityInfluence: 0.16
        )
        let selection = HandDrawingBrushPresetCatalog.resolveSelection(
            for: reopenedBrush,
            presets: presets
        )
        let selectedPreset = try XCTUnwrap(
            selection.availablePresets.first { $0.id == selection.selectedPresetID }
        )

        XCTAssertEqual(selection.availablePresets.count, presets.count)
        XCTAssertEqual(selection.selectedPresetID, presets[1].id)
        XCTAssertTrue(selectedPreset.matches(reopenedBrush))
        XCTAssertEqual(
            selectedPreset.makeBrushStyle(color: reopenedBrush.color),
            reopenedBrush
        )
    }

    func testHandDrawingBrushPresetCatalogInsertsNonPresetWidthInSortedOrder() {
        let presets = HandDrawingBrushPresetCatalog.defaultPenPresets(
            lineWidths: [4, 8, 12, 18],
            tiltSizeInfluence: 0.85,
            tiltOpacityInfluence: 0
        )
        let reopenedBrush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 10,
            opacity: 0.9,
            tiltSizeInfluence: 0.6,
            tiltOpacityInfluence: 0.05
        )
        let selection = HandDrawingBrushPresetCatalog.resolveSelection(
            for: reopenedBrush,
            presets: presets
        )

        XCTAssertEqual(
            selection.availablePresets.map(\.displayLineWidth),
            [4, 8, 10, 12, 18]
        )
        XCTAssertEqual(selection.selectedPresetID, "custom-10")
    }
}
