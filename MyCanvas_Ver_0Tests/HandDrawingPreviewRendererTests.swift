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
    color: HandDrawingColor
) -> HandDrawingStroke {
    HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 24, y: y),
                force: force,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: y),
                force: force,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 96, y: y),
                force: force,
                timestamp: 0.2
            )
        ]
    )
}
