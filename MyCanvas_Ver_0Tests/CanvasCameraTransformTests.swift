import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasCameraTransformTests: XCTestCase {
    func testTransformWithPureTranslationMovesPreviousAnchorToCurrentAnchor() {
        var camera = makeTransformTestCamera()
        let previousAnchor = CGPoint(x: 110, y: 90)
        let currentAnchor = CGPoint(x: 146, y: 128)
        let worldUnderPreviousAnchor = camera.viewportToWorld(previousAnchor)

        camera.transform(
            by: 1,
            around: currentAnchor,
            translatingBy: CGPoint(
                x: currentAnchor.x - previousAnchor.x,
                y: currentAnchor.y - previousAnchor.y
            )
        )

        XCTAssertEqual(camera.zoomScale, 2, accuracy: 0.0001)
        assertPointEqual(
            camera.worldToViewport(worldUnderPreviousAnchor),
            currentAnchor
        )
    }

    func testTransformWithTranslationAndScaleKeepsPreviousAnchorUnderCurrentAnchor() {
        var camera = makeTransformTestCamera()
        let previousAnchor = CGPoint(x: 120, y: 104)
        let currentAnchor = CGPoint(x: 168, y: 126)
        let worldUnderPreviousAnchor = camera.viewportToWorld(previousAnchor)

        camera.transform(
            by: 1.5,
            around: currentAnchor,
            translatingBy: CGPoint(
                x: currentAnchor.x - previousAnchor.x,
                y: currentAnchor.y - previousAnchor.y
            )
        )

        XCTAssertEqual(camera.zoomScale, 3, accuracy: 0.0001)
        assertPointEqual(
            camera.worldToViewport(worldUnderPreviousAnchor),
            currentAnchor
        )
    }

    func testTransformWithInvalidScaleFallsBackToPanOnly() {
        var camera = makeTransformTestCamera()
        let previousAnchor = CGPoint(x: 132, y: 112)
        let currentAnchor = CGPoint(x: 172, y: 150)
        let worldUnderPreviousAnchor = camera.viewportToWorld(previousAnchor)

        camera.transform(
            by: 0,
            around: currentAnchor,
            translatingBy: CGPoint(
                x: currentAnchor.x - previousAnchor.x,
                y: currentAnchor.y - previousAnchor.y
            )
        )

        XCTAssertEqual(camera.zoomScale, 2, accuracy: 0.0001)
        assertPointEqual(
            camera.worldToViewport(worldUnderPreviousAnchor),
            currentAnchor
        )
    }
}

private func makeTransformTestCamera() -> CanvasCamera {
    CanvasCamera(
        center: CGPoint(x: 24, y: -18),
        zoomScale: 2,
        viewportSize: CGSize(width: 400, height: 300)
    )
}

private func assertPointEqual(
    _ actual: CGPoint,
    _ expected: CGPoint,
    accuracy: CGFloat = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
}
