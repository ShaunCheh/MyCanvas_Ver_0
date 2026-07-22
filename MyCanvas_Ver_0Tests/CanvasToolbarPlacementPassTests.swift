import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasToolbarPlacementPassTests: XCTestCase {
    func testResolveReturnsTrailingHiddenFrameForEmptyToolbar() {
        let safeBounds = CGRect(x: 0, y: 0, width: 640, height: 420)
        let result = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: CanvasToolbarPlacement(
                preferredEdge: .trailing
            ),
            toolbarMeasuredSize: .zero,
            baseChromeBlockers: makeToolbarPlacementTestChromeBlockers(),
            scale: 2
        )

        XCTAssertEqual(result.toolbarFrame, .zero)
        XCTAssertEqual(result.hiddenToolbarFrame.minX, safeBounds.maxX)
        XCTAssertEqual(
            result.hiddenToolbarFrame.size,
            CanvasToolbarMeasurement.measuredContentSize(
                forMeasuredStackSize: CGSize(
                    width: CanvasToolbarChromeMetrics.buttonEdge,
                    height: CanvasToolbarChromeMetrics.buttonEdge
                )
            )
        )
    }

    func testResolveDerivesTrailingHiddenFrameFromVisibleToolbarFrame() throws {
        let safeBounds = CGRect(x: 0, y: 0, width: 640, height: 420)
        let result = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: CanvasToolbarPlacement(
                preferredEdge: .trailing
            ),
            toolbarMeasuredSize: makeToolbarPlacementTestVerticalToolbarSize(
                buttonCount: 6
            ),
            baseChromeBlockers: makeToolbarPlacementTestChromeBlockers(),
            scale: 2
        )

        let visibleFrame = try XCTUnwrap(
            CanvasChromeLayoutGeometry.sanitizedRect(result.toolbarFrame)
        )

        XCTAssertEqual(result.hiddenToolbarFrame.minX, safeBounds.maxX)
        XCTAssertEqual(result.hiddenToolbarFrame.minY, visibleFrame.minY)
        XCTAssertEqual(result.hiddenToolbarFrame.width, visibleFrame.width)
        XCTAssertEqual(result.hiddenToolbarFrame.height, visibleFrame.width)
    }

    func testCollapsedFrameUsesShortEdgeForHorizontalToolbar() {
        let visibleFrame = CGRect(x: 20, y: 720, width: 350, height: 64)

        let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
            from: visibleFrame
        )

        XCTAssertEqual(collapsedFrame.origin, visibleFrame.origin)
        XCTAssertEqual(collapsedFrame.width, visibleFrame.height)
        XCTAssertEqual(collapsedFrame.height, visibleFrame.height)
    }

    func testResolveDerivesBottomHiddenFrameFromVisibleToolbarFrame() throws {
        let safeBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let result = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: CanvasToolbarPlacement(
                preferredEdge: .bottom
            ),
            toolbarMeasuredSize: CGSize(width: 350, height: 64),
            baseChromeBlockers: [],
            scale: 3
        )

        let visibleFrame = try XCTUnwrap(
            CanvasChromeLayoutGeometry.sanitizedRect(result.toolbarFrame)
        )

        XCTAssertEqual(result.hiddenToolbarFrame.minX, visibleFrame.minX)
        XCTAssertEqual(result.hiddenToolbarFrame.minY, safeBounds.maxY)
        XCTAssertEqual(result.hiddenToolbarFrame.width, visibleFrame.height)
        XCTAssertEqual(result.hiddenToolbarFrame.height, visibleFrame.height)
    }
}

private func makeToolbarPlacementTestChromeBlockers() -> [CanvasChromeBlocker] {
    [
        CanvasChromeBlocker(
            kind: .backButton,
            rect: CGRect(x: 20, y: 17, width: 44, height: 49)
        ),
        CanvasChromeBlocker(
            kind: .modeToggle,
            rect: CGRect(x: 576, y: 17.5, width: 44.5, height: 48)
        )
    ]
}

private func makeToolbarPlacementTestVerticalToolbarSize(
    buttonCount: Int
) -> CGSize {
    let clampedButtonCount = max(buttonCount, 0)
    let stackedLength = (CGFloat(clampedButtonCount) * CanvasToolbarChromeMetrics.buttonEdge)
        + (CGFloat(max(clampedButtonCount - 1, 0)) * CanvasToolbarChromeMetrics.spacing)
    return CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: CGSize(
            width: CanvasToolbarChromeMetrics.buttonEdge,
            height: stackedLength
        )
    )
}
