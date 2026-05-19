import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class SelectionAccessoryLayoutSolverTests: XCTestCase {
    func testMarkdownAccessoryStateOrdersEditDecreaseIncrease() {
        let state = SelectionAccessoryState.markdown(
            itemID: UUID(),
            anchorRect: CGRect(x: 120, y: 140, width: 80, height: 60),
            editDescriptor: CanvasCommandDescriptor(
                id: .beginMarkdownEdit,
                title: "Edit Markdown",
                systemImageName: "pencil",
                isEnabled: true,
                isActive: false
            ),
            decreaseDescriptor: CanvasCommandDescriptor(
                id: .decreaseMarkdownContentSize,
                title: "Smaller Markdown",
                systemImageName: "minus",
                isEnabled: true,
                isActive: false
            ),
            increaseDescriptor: CanvasCommandDescriptor(
                id: .increaseMarkdownContentSize,
                title: "Larger Markdown",
                systemImageName: "plus",
                isEnabled: true,
                isActive: false
            )
        )

        XCTAssertEqual(
            state.actionStates.map(\.commandID),
            [
                .beginMarkdownEdit,
                .decreaseMarkdownContentSize,
                .increaseMarkdownContentSize
            ]
        )
        XCTAssertFalse(state.isEmpty)
    }

    func testResolveAccessoryFramePrefersAboveAnchorWhenSpaceAvailable() throws {
        let solver = SelectionAccessoryLayoutSolver()
        let anchorRect = CGRect(x: 150, y: 180, width: 100, height: 80)
        let frame = try XCTUnwrap(
            solver.resolveAccessoryFrame(
                anchorRect: anchorRect,
                preferredSize: CGSize(width: 180, height: 44),
                layoutContext: makeSelectionAccessoryLayoutContext()
            )
        )

        XCTAssertLessThan(frame.maxY, anchorRect.minY)
        XCTAssertEqual(frame.maxY, anchorRect.minY - 10, accuracy: 0.0001)
    }

    func testResolveAccessoryFrameFallsBelowWhenAbovePlacementWouldOverlapAnchor() throws {
        let solver = SelectionAccessoryLayoutSolver()
        let anchorRect = CGRect(x: 150, y: 20, width: 100, height: 60)
        let frame = try XCTUnwrap(
            solver.resolveAccessoryFrame(
                anchorRect: anchorRect,
                preferredSize: CGSize(width: 180, height: 44),
                layoutContext: makeSelectionAccessoryLayoutContext()
            )
        )

        XCTAssertGreaterThan(frame.minY, anchorRect.maxY)
        XCTAssertEqual(frame.minY, anchorRect.maxY + 10, accuracy: 0.0001)
    }

    func testResolveAccessoryFrameAvoidsChromeBlockerAboveAnchor() throws {
        let solver = SelectionAccessoryLayoutSolver()
        let anchorRect = CGRect(x: 150, y: 180, width: 100, height: 80)
        let layoutContext = makeSelectionAccessoryLayoutContext(
            chromeBlockers: [
                CanvasChromeBlocker(
                    kind: .toolbar,
                    rect: CGRect(x: 80, y: 110, width: 240, height: 60)
                )
            ]
        )
        let frame = try XCTUnwrap(
            solver.resolveAccessoryFrame(
                anchorRect: anchorRect,
                preferredSize: CGSize(width: 180, height: 44),
                layoutContext: layoutContext
            )
        )

        XCTAssertGreaterThan(frame.minY, anchorRect.maxY)
    }
}

private func makeSelectionAccessoryLayoutContext(
    chromeBlockers: [CanvasChromeBlocker] = []
) -> CanvasChromeLayoutContext {
    CanvasChromeLayoutContext(
        safeBounds: CGRect(x: 0, y: 0, width: 500, height: 400),
        toolbarPreferredPlacement: CanvasToolbarPlacement(dockEdge: .bottom),
        toolbarMeasuredSize: .zero,
        chromeBlockers: chromeBlockers
    )
}
