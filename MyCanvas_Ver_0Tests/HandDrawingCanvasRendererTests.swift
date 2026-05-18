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
            sampleRGBA(from: canvasImage, x: 60, y: 60),
            sampleRGBA(from: previewImage, x: 60, y: 60)
        )
        assertPixelsEqual(
            sampleRGBA(from: canvasImage, x: 35, y: 60),
            sampleRGBA(from: previewImage, x: 35, y: 60)
        )
        assertPixelsEqual(
            sampleRGBA(from: canvasImage, x: 95, y: 60),
            sampleRGBA(from: previewImage, x: 95, y: 60)
        )
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
