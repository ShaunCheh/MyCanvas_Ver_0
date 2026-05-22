import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingPreviewRendererTests: XCTestCase {
    func testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument()

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let centerPixel = sampleDisplayedRGBA(from: image, x: 60, y: 60)

        XCTAssertGreaterThan(centerPixel.alpha, 0)
        XCTAssertGreaterThan(centerPixel.blue, centerPixel.red)
    }

    func testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument(includeEraseMask: true)

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let erasedPixel = sampleDisplayedRGBA(from: image, x: 60, y: 60)
        let preservedPixel = sampleDisplayedRGBA(from: image, x: 35, y: 60)

        XCTAssertLessThan(erasedPixel.alpha, preservedPixel.alpha)
        XCTAssertGreaterThan(preservedPixel.alpha, 0)
    }

    func testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences() throws {
        let renderer = HandDrawingPreviewRenderer()
        let thinStroke = makePreviewRendererTestStroke(
            y: 34,
            baseSize: 6,
            color: HandDrawingColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)
        )
        let thickStroke = makePreviewRendererTestStroke(
            y: 86,
            baseSize: 24,
            color: HandDrawingColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1)
        )
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(id: "preview-paper", size: CGSize(width: 120, height: 120)),
            strokes: [thinStroke, thickStroke]
        )

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let thinCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 34)
        let thickCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 86)
        let thinEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 42)
        let thickEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 94)

        XCTAssertGreaterThan(thinCenterPixel.red, thinCenterPixel.green)
        XCTAssertGreaterThan(thickCenterPixel.green, thickCenterPixel.red)
        XCTAssertLessThan(thinEdgePixel.alpha, 16)
        XCTAssertGreaterThan(thickEdgePixel.alpha, 64)
    }

    func testHandDrawingPreviewRendererReflectsPressureDrivenWidthDifferences() throws {
        let renderer = HandDrawingPreviewRenderer()
        let lowPressureStroke = makePreviewRendererTestStroke(
            y: 34,
            baseSize: 20,
            force: 0.35,
            color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
        )
        let highPressureStroke = makePreviewRendererTestStroke(
            y: 86,
            baseSize: 20,
            force: 1,
            color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
        )
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(id: "pressure-paper", size: CGSize(width: 120, height: 120)),
            strokes: [lowPressureStroke, highPressureStroke]
        )

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let lowCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 34)
        let highCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 86)
        let lowEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 40)
        let highEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 92)

        XCTAssertGreaterThan(lowCenterPixel.red, lowCenterPixel.green)
        XCTAssertGreaterThan(highCenterPixel.green, highCenterPixel.red)
        XCTAssertLessThan(lowEdgePixel.alpha, 16)
        XCTAssertGreaterThan(highEdgePixel.alpha, 64)
    }

    func testHandDrawingPreviewRendererRendersTiltAwareStampOrientation() throws {
        let renderer = HandDrawingPreviewRenderer()
        let horizontalTiltStroke = makePreviewRendererTestStroke(
            y: 60,
            baseSize: 20,
            force: 0.5,
            samplePoints: [CGPoint(x: 36, y: 60)],
            azimuthRadians: [0],
            altitudeRadians: [0],
            tiltSizeInfluence: 1,
            color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
        )
        let verticalTiltStroke = makePreviewRendererTestStroke(
            y: 60,
            baseSize: 20,
            force: 0.5,
            samplePoints: [CGPoint(x: 84, y: 60)],
            azimuthRadians: [.pi / 2],
            altitudeRadians: [0],
            tiltSizeInfluence: 1,
            color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
        )
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "tilt-preview-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [horizontalTiltStroke, verticalTiltStroke]
        )

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let horizontalRightPixel = sampleDisplayedRGBA(from: image, x: 44, y: 60)
        let horizontalDownPixel = sampleDisplayedRGBA(from: image, x: 36, y: 68)
        let verticalRightPixel = sampleDisplayedRGBA(from: image, x: 92, y: 60)
        let verticalDownPixel = sampleDisplayedRGBA(from: image, x: 84, y: 68)

        XCTAssertGreaterThan(horizontalRightPixel.alpha, 48)
        XCTAssertLessThan(horizontalDownPixel.alpha, 16)
        XCTAssertLessThan(verticalRightPixel.alpha, 16)
        XCTAssertGreaterThan(verticalDownPixel.alpha, 48)
    }

    func testHandDrawingPreviewRendererRespectsVisibleLayerOrder() throws {
        let renderer = HandDrawingPreviewRenderer()
        let baseLayer = makeHandDrawingTestLayer(
            name: "Base",
            strokes: [
                makePreviewRendererTestStroke(
                    y: 60,
                    baseSize: 18,
                    color: HandDrawingColor(red: 0.92, green: 0.12, blue: 0.1, alpha: 1)
                )
            ]
        )
        let visibleOverlayLayer = makeHandDrawingTestLayer(
            name: "Overlay",
            isVisible: true,
            strokes: [
                makePreviewRendererTestStroke(
                    y: 60,
                    baseSize: 18,
                    color: HandDrawingColor(red: 0.12, green: 0.86, blue: 0.18, alpha: 1)
                )
            ]
        )
        let hiddenOverlayLayer = makeHandDrawingTestLayer(
            id: visibleOverlayLayer.id,
            name: visibleOverlayLayer.name,
            isVisible: false,
            strokes: visibleOverlayLayer.strokes
        )
        let visibleDocument = makeHandDrawingLayeredTestDocument(
            layers: [baseLayer, visibleOverlayLayer],
            activeLayerID: visibleOverlayLayer.id
        )
        let hiddenDocument = makeHandDrawingLayeredTestDocument(
            layers: [baseLayer, hiddenOverlayLayer],
            activeLayerID: hiddenOverlayLayer.id
        )

        let visibleImage = try renderer.renderPreviewImage(for: visibleDocument, scale: 1)
        let hiddenImage = try renderer.renderPreviewImage(for: hiddenDocument, scale: 1)
        let visiblePixel = sampleDisplayedRGBA(from: visibleImage, x: 60, y: 60)
        let hiddenPixel = sampleDisplayedRGBA(from: hiddenImage, x: 60, y: 60)

        XCTAssertGreaterThan(visiblePixel.green, visiblePixel.red)
        XCTAssertGreaterThan(hiddenPixel.red, hiddenPixel.green)
    }
}

private func makePreviewRendererTestStroke(
    y: CGFloat,
    baseSize: Double,
    force: Double = 1,
    samplePoints: [CGPoint]? = nil,
    azimuthRadians: [Double?]? = nil,
    altitudeRadians: [Double?]? = nil,
    tiltSizeInfluence: Double? = nil,
    tiltOpacityInfluence: Double? = nil,
    color: HandDrawingColor
) -> HandDrawingStroke {
    let resolvedSamplePoints = samplePoints ?? [
        CGPoint(x: 24, y: y),
        CGPoint(x: 60, y: y),
        CGPoint(x: 96, y: y)
    ]
    if let azimuthRadians {
        precondition(
            azimuthRadians.count == resolvedSamplePoints.count,
            "Preview renderer test azimuth samples must align with sample points."
        )
    }
    if let altitudeRadians {
        precondition(
            altitudeRadians.count == resolvedSamplePoints.count,
            "Preview renderer test altitude samples must align with sample points."
        )
    }
    return HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1,
            tiltSizeInfluence: tiltSizeInfluence,
            tiltOpacityInfluence: tiltOpacityInfluence
        ),
        samplePoints: resolvedSamplePoints.enumerated().map { index, point in
            HandDrawingSamplePoint(
                point: point,
                force: force,
                timestamp: Double(index) * 0.1,
                azimuthRadians: azimuthRadians?[index],
                altitudeRadians: altitudeRadians?[index]
            )
        }
    )
}
