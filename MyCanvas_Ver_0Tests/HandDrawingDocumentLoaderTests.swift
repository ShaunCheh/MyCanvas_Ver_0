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
}
