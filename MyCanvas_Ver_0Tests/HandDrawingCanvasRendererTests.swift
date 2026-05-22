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

    func testHandDrawingCanvasRendererMatchesPreviewRendererForTiltAwareStampOrientation() throws {
        let horizontalTiltStroke = makeCanvasRendererLayeredTestStroke(
            y: 60,
            baseSize: 20,
            force: 0.5,
            samplePoints: [CGPoint(x: 36, y: 60)],
            azimuthRadians: [0],
            altitudeRadians: [0],
            tiltSizeInfluence: 1,
            color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
        )
        let verticalTiltStroke = makeCanvasRendererLayeredTestStroke(
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
                id: "canvas-tilt-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [horizontalTiltStroke, verticalTiltStroke]
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

        let horizontalCanvasRight = sampleDisplayedRGBA(from: canvasImage, x: 44, y: 60)
        let horizontalPreviewRight = sampleDisplayedRGBA(from: previewImage, x: 44, y: 60)
        let horizontalCanvasDown = sampleDisplayedRGBA(from: canvasImage, x: 36, y: 68)
        let horizontalPreviewDown = sampleDisplayedRGBA(from: previewImage, x: 36, y: 68)
        let verticalCanvasRight = sampleDisplayedRGBA(from: canvasImage, x: 92, y: 60)
        let verticalPreviewRight = sampleDisplayedRGBA(from: previewImage, x: 92, y: 60)
        let verticalCanvasDown = sampleDisplayedRGBA(from: canvasImage, x: 84, y: 68)
        let verticalPreviewDown = sampleDisplayedRGBA(from: previewImage, x: 84, y: 68)

        assertPixelsEqual(horizontalCanvasRight, horizontalPreviewRight)
        assertPixelsEqual(horizontalCanvasDown, horizontalPreviewDown)
        assertPixelsEqual(verticalCanvasRight, verticalPreviewRight)
        assertPixelsEqual(verticalCanvasDown, verticalPreviewDown)
        XCTAssertGreaterThan(horizontalCanvasRight.alpha, 48)
        XCTAssertLessThan(horizontalCanvasDown.alpha, 16)
        XCTAssertLessThan(verticalCanvasRight.alpha, 16)
        XCTAssertGreaterThan(verticalCanvasDown.alpha, 48)
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
            "Canvas renderer test azimuth samples must align with sample points."
        )
    }
    if let altitudeRadians {
        precondition(
            altitudeRadians.count == resolvedSamplePoints.count,
            "Canvas renderer test altitude samples must align with sample points."
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
