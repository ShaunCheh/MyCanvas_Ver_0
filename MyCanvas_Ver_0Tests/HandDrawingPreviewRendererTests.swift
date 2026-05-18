import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingPreviewRendererTests: XCTestCase {
    func testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument()

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let centerPixel = sampleRGBA(from: image, x: 60, y: 60)

        XCTAssertGreaterThan(centerPixel.alpha, 0)
        XCTAssertGreaterThan(centerPixel.blue, centerPixel.red)
    }

    func testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument(includeEraseMask: true)

        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let erasedPixel = sampleRGBA(from: image, x: 60, y: 60)
        let preservedPixel = sampleRGBA(from: image, x: 35, y: 60)

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
        let thinCenterPixel = sampleRGBA(from: image, x: 60, y: 34)
        let thickCenterPixel = sampleRGBA(from: image, x: 60, y: 86)
        let thinEdgePixel = sampleRGBA(from: image, x: 60, y: 42)
        let thickEdgePixel = sampleRGBA(from: image, x: 60, y: 94)

        XCTAssertGreaterThan(thinCenterPixel.red, thinCenterPixel.green)
        XCTAssertGreaterThan(thickCenterPixel.green, thickCenterPixel.red)
        XCTAssertLessThan(thinEdgePixel.alpha, 16)
        XCTAssertGreaterThan(thickEdgePixel.alpha, 64)
    }
}

private func makePreviewRendererTestStroke(
    y: CGFloat,
    baseSize: Double,
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
                force: 1,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: y),
                force: 1,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 96, y: y),
                force: 1,
                timestamp: 0.2
            )
        ]
    )
}
