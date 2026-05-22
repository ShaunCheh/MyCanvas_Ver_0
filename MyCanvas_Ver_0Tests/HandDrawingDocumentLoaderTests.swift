import CoreGraphics
import PencilKit
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingDocumentLoaderTests: XCTestCase {
    func testHandDrawingDocumentLoaderLoadsTypedDocumentData() throws {
        let baseLayer = makeHandDrawingTestLayer(
            name: "Sketch",
            strokes: [
                makeHandDrawingTestStroke(id: UUID())
            ]
        )
        let detailLayer = makeHandDrawingTestLayer(
            name: "Ink",
            strokes: [
                makeHandDrawingTestStroke(
                    id: UUID(),
                    includeEraseMask: true,
                    transform: HandDrawingStrokeTransform(translationY: 20)
                )
            ]
        )
        let document = makeHandDrawingLayeredTestDocument(
            layers: [baseLayer, detailLayer],
            activeLayerID: detailLayer.id
        )
        let documentData = try HandDrawingDocumentCodec.makeDocumentData(
            for: document
        )

        let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
            from: documentData,
            paper: document.paper.canvasPaperSpec
        )

        XCTAssertEqual(loadedDocument, document)
    }

    func testHandDrawingDocumentLoaderBuildsDefaultLayeredDocumentForEmptyData() throws {
        let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
            from: Data(),
            paper: .square
        )
        let loadedLayer = try XCTUnwrap(loadedDocument.layers.first)

        XCTAssertEqual(loadedDocument.paper, HandDrawingPaper(.square))
        XCTAssertEqual(loadedDocument.layers.count, 1)
        XCTAssertEqual(loadedDocument.activeLayerID, loadedLayer.id)
        XCTAssertEqual(loadedLayer.name, "Layer 1")
        XCTAssertTrue(loadedLayer.strokes.isEmpty)
        XCTAssertTrue(loadedDocument.strokes.isEmpty)
    }

    func testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing() throws {
        let legacyDrawing = makeLegacyDrawing()

        let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
            from: legacyDrawing.dataRepresentation(),
            paper: .square
        )

        XCTAssertEqual(loadedDocument.paper, HandDrawingPaper(.square))
        XCTAssertEqual(loadedDocument.layers.count, 1)
        XCTAssertEqual(loadedDocument.activeLayerID, loadedDocument.layers[0].id)
        XCTAssertEqual(loadedDocument.layers[0].name, "Layer 1")
        XCTAssertEqual(loadedDocument.strokes.count, 1)
        let stroke = try XCTUnwrap(loadedDocument.strokes.first)
        XCTAssertGreaterThan(stroke.samplePoints.count, 2)
        XCTAssertFalse(loadedDocument.isEmpty)

        let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: loadedDocument,
            scale: 1
        )
        let sampledPixel = sampleDisplayedRGBA(from: previewImage, x: 54, y: 54)
        XCTAssertGreaterThan(sampledPixel.alpha, 0)
    }

    func testHandDrawingDocumentLoaderNormalizesLegacyPencilKitDrawingPreservingRawInputs() throws {
        let legacyDrawing = makeLegacyTiltDrawing()

        let normalizedData = try HandDrawingDocumentLoader.normalizeDocumentData(
            from: legacyDrawing.dataRepresentation(),
            paper: .square
        )
        let normalizedDocument = try HandDrawingDocumentCodec.decodeDocument(
            from: normalizedData
        )
        let normalizedStroke = try XCTUnwrap(normalizedDocument.strokes.first)
        let normalizedSample = try XCTUnwrap(normalizedStroke.samplePoints.first)
        let tiltSizeInfluence = try XCTUnwrap(normalizedStroke.brush.tiltSizeInfluence)
        let tiltOpacityInfluence = try XCTUnwrap(
            normalizedStroke.brush.tiltOpacityInfluence
        )
        let azimuthRadians = try XCTUnwrap(normalizedSample.azimuthRadians)
        let altitudeRadians = try XCTUnwrap(normalizedSample.altitudeRadians)

        XCTAssertEqual(normalizedDocument.paper, HandDrawingPaper(.square))
        XCTAssertEqual(normalizedDocument.strokes.count, 1)
        XCTAssertEqual(
            tiltSizeInfluence,
            HandDrawingBrushStyle.defaultPresetTiltSizeInfluence,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tiltOpacityInfluence,
            HandDrawingBrushStyle.defaultPresetTiltOpacityInfluence,
            accuracy: 0.001
        )
        XCTAssertEqual(normalizedSample.force, 0.35, accuracy: 0.001)
        XCTAssertEqual(azimuthRadians, 0.75, accuracy: 0.001)
        XCTAssertEqual(altitudeRadians, .pi / 4, accuracy: 0.001)

        let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: normalizedDocument,
            scale: 1
        )
        let sampledPixel = sampleDisplayedRGBA(from: previewImage, x: 36, y: 36)
        XCTAssertGreaterThan(sampledPixel.alpha, 0)
    }

    private func makeLegacyDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 18, y: 18),
                timeOffset: 0,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 54, y: 54),
                timeOffset: 0.02,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 92, y: 92),
                timeOffset: 0.04,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        let path = PKStrokePath(
            controlPoints: points,
            creationDate: Date()
        )
        let stroke = PKStroke(
            ink: PKInk(.pen, color: HandDrawingPlatformColor.red),
            path: path
        )
        return PKDrawing(strokes: [stroke])
    }

    private func makeLegacyTiltDrawing() -> PKDrawing {
        let point = PKStrokePoint(
            location: CGPoint(x: 36, y: 36),
            timeOffset: 0.12,
            size: CGSize(width: 10, height: 10),
            opacity: 0.7,
            force: 0.35,
            azimuth: 0.75,
            altitude: .pi / 4
        )
        let path = PKStrokePath(
            controlPoints: [point],
            creationDate: Date()
        )
        let stroke = PKStroke(
            ink: PKInk(.marker, color: HandDrawingPlatformColor.blue),
            path: path
        )
        return PKDrawing(strokes: [stroke])
    }
}
