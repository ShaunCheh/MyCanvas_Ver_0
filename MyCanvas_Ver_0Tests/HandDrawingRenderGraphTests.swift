import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class HandDrawingRenderGraphTests: XCTestCase {
    func testHandDrawingRenderGraphBuilderPreservesVisibleLayerOrderAndFiltersSnapshotsByRenderRegion() {
        let baseStroke = makeHandDrawingTestStroke(
            id: UUID(),
            samplePoints: [
                CGPoint(x: 25, y: 60),
                CGPoint(x: 60, y: 60),
                CGPoint(x: 95, y: 60)
            ]
        )
        let outsideStroke = makeHandDrawingTestStroke(
            id: UUID(),
            samplePoints: [
                CGPoint(x: 25, y: 24),
                CGPoint(x: 60, y: 24),
                CGPoint(x: 95, y: 24)
            ]
        )
        let overlayStroke = makeHandDrawingTestStroke(
            id: UUID(),
            color: HandDrawingColor(red: 0.8, green: 0.18, blue: 0.14, alpha: 1),
            samplePoints: [
                CGPoint(x: 25, y: 60),
                CGPoint(x: 60, y: 60),
                CGPoint(x: 95, y: 60)
            ]
        )
        let document = makeHandDrawingLayeredTestDocument(
            layers: [
                makeHandDrawingTestLayer(name: "Base", strokes: [baseStroke]),
                makeHandDrawingTestLayer(name: "Outside", strokes: [outsideStroke]),
                makeHandDrawingTestLayer(name: "Overlay", strokes: [overlayStroke])
            ]
        )

        let graph = HandDrawingRenderGraphBuilder.graph(
            for: document,
            renderRegion: CGRect(x: 0, y: 48, width: 120, height: 24)
        )

        XCTAssertEqual(graph.layers.count, 3)
        XCTAssertEqual(graph.layers[0].strokeSnapshots.map(\.strokeID), [baseStroke.id])
        XCTAssertTrue(graph.layers[1].strokeSnapshots.isEmpty)
        XCTAssertEqual(graph.layers[2].strokeSnapshots.map(\.strokeID), [overlayStroke.id])
        XCTAssertEqual(
            graph.renderedStrokeSnapshotsInOrder.map(\.strokeID),
            [baseStroke.id, overlayStroke.id]
        )
    }

    func testHandDrawingRenderGraphBuilderResolvesEraseMaskIntoDocumentSpace() throws {
        let stroke = HandDrawingStroke(
            brush: .defaultPen,
            samplePoints: [
                HandDrawingSamplePoint(
                    point: CGPoint(x: 20, y: 20),
                    force: 1,
                    timestamp: 0
                ),
                HandDrawingSamplePoint(
                    point: CGPoint(x: 80, y: 20),
                    force: 1,
                    timestamp: 0.1
                )
            ],
            transform: HandDrawingStrokeTransform(
                translationX: 12,
                translationY: 8
            ),
            eraseMask: [
                HandDrawingErasePath(
                    samplePoints: [
                        HandDrawingEraseSamplePoint(
                            point: CGPoint(x: 40, y: 20),
                            radius: 6,
                            opacity: 0.4
                        )
                    ]
                )
            ]
        )

        let snapshot = HandDrawingRenderGraphBuilder.strokeSnapshot(for: stroke)
        let eraseSample = try XCTUnwrap(
            snapshot.resolvedErasePaths.first?.samples.first
        )

        XCTAssertEqual(eraseSample.point, CGPoint(x: 52, y: 28))
        XCTAssertEqual(eraseSample.radius, 6)
        XCTAssertEqual(eraseSample.opacity, 0.4, accuracy: 0.001)
    }
}
