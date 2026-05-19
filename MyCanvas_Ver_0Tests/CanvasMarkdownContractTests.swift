import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownContractTests: XCTestCase {
    func testMarkdownItemKeepsExplicitContainerHeightEvenWhenIntrinsicHeightDiffers() {
        let source = """
        ## Title

        A long markdown paragraph that intentionally wraps across multiple lines
        so the measured intrinsic height is much taller than the stored
        container height.
        """
        let style = CanvasTextStyle(fontSize: 18)
        let item = CanvasMarkdownItem(
            markdownSource: source,
            style: style,
            center: CGPoint(x: 120, y: -40),
            size: CGSize(width: 180, height: 44),
            zIndex: 2,
            rotationRadians: .pi / 5
        )
        let measuredHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: item.size.width
        )

        XCTAssertGreaterThan(measuredHeight, item.size.height)
        XCTAssertEqual(
            item.localFrame,
            CGRect(x: -90, y: -22, width: 180, height: 44)
        )
        XCTAssertEqual(
            item.worldFrame,
            CGRect(x: 30, y: -62, width: 180, height: 44)
        )
        XCTAssertEqual(item.localQuad.boundingRect.standardized.size, item.size)
        XCTAssertEqual(item.worldQuad.center, item.center)
    }

    func testUpdateMarkdownItemContentKeepsCurrentWidthAndRemeasuresHeight() throws {
        let session = makeMarkdownContractTestSession()
        let originalItem = CanvasMarkdownItem(
            markdownSource: "Seed",
            style: CanvasTextStyle(fontSize: 18),
            center: CGPoint(x: 40, y: 24),
            size: CGSize(width: 210, height: 48),
            zIndex: 1,
            rotationRadians: .pi / 9
        )
        session.scene.append(originalItem)

        let updatedSource = """
        ## Updated

        A much longer markdown paragraph that must reflow using the current
        container width instead of inventing a new width during editing.
        """
        let updatedStyle = CanvasTextStyle(fontSize: 22)
        let updatedItem = try XCTUnwrap(
            session.updateMarkdownItemContent(
                withID: originalItem.id,
                markdownSource: updatedSource,
                style: updatedStyle
            )
        )
        let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: updatedSource,
            style: updatedStyle,
            maxLayoutWidth: originalItem.size.width
        )

        XCTAssertEqual(updatedItem.center, originalItem.center)
        XCTAssertEqual(updatedItem.rotationRadians, originalItem.rotationRadians)
        XCTAssertEqual(updatedItem.zIndex, originalItem.zIndex)
        XCTAssertEqual(updatedItem.size.width, originalItem.size.width)
        XCTAssertEqual(updatedItem.size.height, expectedHeight, accuracy: 0.0001)
    }

    func testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract() throws {
        let session = makeMarkdownContractTestSession()
        session.camera = CanvasCamera(
            center: CGPoint(x: 100, y: -20),
            zoomScale: 1.5,
            viewportSize: CGSize(width: 400, height: 300)
        )

        let source = """
        ## Snapshot

        A wrapped paragraph that keeps the stored markdown container height
        smaller than the measured intrinsic height.
        """
        let style = CanvasTextStyle(fontSize: 18)
        let item = CanvasMarkdownItem(
            markdownSource: source,
            style: style,
            center: CGPoint(x: 160, y: 40),
            size: CGSize(width: 180, height: 48),
            zIndex: 3,
            rotationRadians: .pi / 6
        )
        let intrinsicHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: item.size.width
        )
        XCTAssertGreaterThan(intrinsicHeight, item.size.height)

        session.scene.append(item)

        let snapshot = session.makeCanvasSnapshot()
        let renderItem = try XCTUnwrap(
            snapshot.items.first(where: { $0.id == item.id })
        )
        let expectedQuad = session.camera.worldToViewport(item.worldQuad)
        let expectedCenter = session.camera.worldToViewport(item.center)
        let expectedBoundsSize = CGSize(
            width: item.size.width * session.camera.zoomScale,
            height: item.size.height * session.camera.zoomScale
        )

        XCTAssertEqual(renderItem.screenQuad, expectedQuad)
        XCTAssertEqual(renderItem.screenFrame, expectedQuad.boundingRect.standardized)
        XCTAssertEqual(renderItem.screenCenter, expectedCenter)
        XCTAssertEqual(renderItem.screenBoundsSize, expectedBoundsSize)
        XCTAssertEqual(renderItem.rotationRadians, item.rotationRadians)
        XCTAssertEqual(renderItem.zIndex, item.zIndex)

        guard case let .markdown(payload) = renderItem.payload else {
            XCTFail("Expected markdown render payload.")
            return
        }

        XCTAssertEqual(payload.markdownSource, item.markdownSource)
        XCTAssertEqual(payload.style, item.style)
        XCTAssertEqual(payload.zoomScale, session.camera.zoomScale)
    }
}

private enum CanvasMarkdownContractTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeMarkdownContractTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasMarkdownContractTests",
        logPrefix: "[CanvasMarkdownContractTests]"
    )
    CanvasMarkdownContractTestRetainer.sessions.append(session)
    return session
}
