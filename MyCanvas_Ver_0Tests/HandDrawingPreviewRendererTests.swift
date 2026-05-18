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
}
