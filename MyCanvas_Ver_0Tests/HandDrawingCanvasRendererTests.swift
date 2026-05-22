import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingCanvasRendererTests: XCTestCase {
    func testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate() throws {
        let initialDocument = makeHandDrawingTestDocument()
        let renderer = try HandDrawingCanvasRenderer(
            paperSize: initialDocument.paper.size
        )
        _ = try renderer.render(
            document: initialDocument,
            dirtyRegion: initialDocument.paperBounds
        )

        var updatedDocument = initialDocument
        guard var updatedStroke = updatedDocument.strokes.first else {
            XCTFail("Expected a test stroke in the document.")
            return
        }
        updatedStroke.eraseMask = [
            HandDrawingErasePath(
                samplePoints: [
                    HandDrawingEraseSamplePoint(
                        point: CGPoint(x: 60, y: 60),
                        radius: 10
                    )
                ]
            )
        ]
        updatedDocument.strokes[0] = updatedStroke

        let dirtyRegion = CGRect(x: 48, y: 48, width: 24, height: 24)
        let canvasImage = try renderer.render(
            document: updatedDocument,
            dirtyRegion: dirtyRegion
        )
        let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: updatedDocument,
            scale: 1
        )

        assertPixelsEqual(
            sampleDisplayedRGBA(from: canvasImage, x: 60, y: 60),
            sampleDisplayedRGBA(from: previewImage, x: 60, y: 60)
        )
        assertPixelsEqual(
            sampleDisplayedRGBA(from: canvasImage, x: 35, y: 60),
            sampleDisplayedRGBA(from: previewImage, x: 35, y: 60)
        )
        assertPixelsEqual(
            sampleDisplayedRGBA(from: canvasImage, x: 95, y: 60),
            sampleDisplayedRGBA(from: previewImage, x: 95, y: 60)
        )
    }

    func testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates() throws {
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "canvas-display-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [
                HandDrawingStroke(
                    brush: HandDrawingBrushStyle(
                        kind: .pen,
                        color: HandDrawingColor(red: 0.82, green: 0.16, blue: 0.18, alpha: 1),
                        baseSize: 12,
                        opacity: 1
                    ),
                    samplePoints: [
                        HandDrawingSamplePoint(
                            point: CGPoint(x: 24, y: 20),
                            force: 1,
                            timestamp: 0
                        ),
                        HandDrawingSamplePoint(
                            point: CGPoint(x: 60, y: 20),
                            force: 1,
                            timestamp: 0.1
                        ),
                        HandDrawingSamplePoint(
                            point: CGPoint(x: 96, y: 20),
                            force: 1,
                            timestamp: 0.2
                        )
                    ]
                )
            ]
        )
        let renderer = try HandDrawingCanvasRenderer(
            paperSize: document.paper.size
        )

        let image = try renderer.render(
            document: document,
            dirtyRegion: document.paperBounds
        )
        let topPixel = sampleDisplayedRGBA(from: image, x: 60, y: 20)
        let bottomPixel = sampleDisplayedRGBA(from: image, x: 60, y: 100)

        XCTAssertGreaterThan(topPixel.alpha, 0)
        XCTAssertLessThan(bottomPixel.alpha, 16)
    }

    func testHandDrawingCanvasRendererMatchesPreviewRendererForVisibleLayerOrder() throws {
        let baseLayer = makeHandDrawingTestLayer(
            name: "Base",
            strokes: [
                makeCanvasRendererLayeredTestStroke(
                    y: 60,
                    color: HandDrawingColor(red: 0.92, green: 0.12, blue: 0.1, alpha: 1)
                )
            ]
        )
        let visibleOverlayLayer = makeHandDrawingTestLayer(
            name: "Overlay",
            isVisible: true,
            strokes: [
                makeCanvasRendererLayeredTestStroke(
                    y: 60,
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
        let renderer = try HandDrawingCanvasRenderer(
            paperSize: visibleDocument.paper.size
        )

        let visibleCanvasImage = try renderer.render(
            document: visibleDocument,
            dirtyRegion: visibleDocument.paperBounds
        )
        let visiblePreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: visibleDocument,
            scale: 1
        )
        let hiddenCanvasImage = try renderer.render(
            document: hiddenDocument,
            dirtyRegion: hiddenDocument.paperBounds
        )
        let hiddenPreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: hiddenDocument,
            scale: 1
        )
        let visibleCanvasPixel = sampleDisplayedRGBA(from: visibleCanvasImage, x: 60, y: 60)
        let visiblePreviewPixel = sampleDisplayedRGBA(from: visiblePreviewImage, x: 60, y: 60)
        let hiddenCanvasPixel = sampleDisplayedRGBA(from: hiddenCanvasImage, x: 60, y: 60)
        let hiddenPreviewPixel = sampleDisplayedRGBA(from: hiddenPreviewImage, x: 60, y: 60)

        assertPixelsEqual(visibleCanvasPixel, visiblePreviewPixel)
        assertPixelsEqual(hiddenCanvasPixel, hiddenPreviewPixel)
        XCTAssertGreaterThan(visibleCanvasPixel.green, visibleCanvasPixel.red)
        XCTAssertGreaterThan(hiddenCanvasPixel.red, hiddenCanvasPixel.green)
    }

    func testHandDrawingCanvasRendererMatchesPreviewRendererForPressureDrivenStrokeWidths() throws {
        let lowPressureStroke = makeCanvasRendererLayeredTestStroke(
            y: 34,
            baseSize: 20,
            force: 0.35,
            color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
        )
        let highPressureStroke = makeCanvasRendererLayeredTestStroke(
            y: 86,
            baseSize: 20,
            force: 1,
            color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
        )
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "canvas-pressure-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [lowPressureStroke, highPressureStroke]
        )
        let renderer = try HandDrawingCanvasRenderer(
            paperSize: document.paper.size
        )

        let canvasImage = try renderer.render(
            document: document,
            dirtyRegion: document.paperBounds
        )
        let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: document,
            scale: 1
        )
        let lowCanvasCenterPixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 34)
        let lowPreviewCenterPixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 34)
        let lowCanvasEdgePixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 40)
        let lowPreviewEdgePixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 40)
        let highCanvasCenterPixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 86)
        let highPreviewCenterPixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 86)
        let highCanvasEdgePixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 92)
        let highPreviewEdgePixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 92)

        assertPixelsEqual(lowCanvasCenterPixel, lowPreviewCenterPixel)
        assertPixelsEqual(lowCanvasEdgePixel, lowPreviewEdgePixel)
        assertPixelsEqual(highCanvasCenterPixel, highPreviewCenterPixel)
        assertPixelsEqual(highCanvasEdgePixel, highPreviewEdgePixel)
        XCTAssertLessThan(lowCanvasEdgePixel.alpha, highCanvasEdgePixel.alpha)
    }

    private func assertPixelsEqual(
        _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.red, rhs.red, file: file, line: line)
        XCTAssertEqual(lhs.green, rhs.green, file: file, line: line)
        XCTAssertEqual(lhs.blue, rhs.blue, file: file, line: line)
        XCTAssertEqual(lhs.alpha, rhs.alpha, file: file, line: line)
    }
}

private func makeCanvasRendererLayeredTestStroke(
    y: CGFloat,
    baseSize: Double = 18,
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
