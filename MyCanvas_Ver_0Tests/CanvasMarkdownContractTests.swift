import CoreGraphics
import CoreText
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

    func testUpdateMarkdownItemContentKeepsExplicitViewportHeightAndClampsScrollOffset() throws {
        let session = makeMarkdownContractTestSession()
        let originalItem = CanvasMarkdownItem(
            markdownSource: "Seed",
            style: CanvasTextStyle(fontSize: 18),
            center: CGPoint(x: 40, y: 24),
            size: CGSize(width: 210, height: 48),
            scrollOffsetY: 30,
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
        let expectedContentHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: updatedSource,
            style: updatedStyle,
            maxLayoutWidth: originalItem.size.width
        )
        let expectedScrollOffset = min(
            max(originalItem.scrollOffsetY, 0),
            max(expectedContentHeight - originalItem.size.height, 0)
        )

        XCTAssertEqual(updatedItem.center, originalItem.center)
        XCTAssertEqual(updatedItem.rotationRadians, originalItem.rotationRadians)
        XCTAssertEqual(updatedItem.zIndex, originalItem.zIndex)
        XCTAssertEqual(updatedItem.size.width, originalItem.size.width)
        XCTAssertEqual(updatedItem.size.height, originalItem.size.height, accuracy: 0.0001)
        XCTAssertEqual(updatedItem.scrollOffsetY, expectedScrollOffset, accuracy: 0.0001)
    }

    func testUpdateMarkdownItemScrollOffsetClampsIntoOverflowRange() throws {
        let session = makeMarkdownContractTestSession()
        let item = CanvasMarkdownItem(
            markdownSource: """
            ## Scroll

            Line 1

            Line 2

            Line 3

            Line 4
            """,
            style: CanvasTextStyle(fontSize: 18),
            center: CGPoint(x: 10, y: 20),
            size: CGSize(width: 180, height: 52),
            zIndex: 1
        )
        session.scene.append(item)

        let updatedItem = try XCTUnwrap(
            session.updateMarkdownItemScrollOffset(
                withID: item.id,
                scrollOffsetY: 10_000
            )
        )
        let expectedContentHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: item.markdownSource,
            style: item.style,
            maxLayoutWidth: item.size.width
        )

        XCTAssertEqual(updatedItem.size, item.size)
        XCTAssertEqual(
            updatedItem.scrollOffsetY,
            max(expectedContentHeight - item.size.height, 0),
            accuracy: 0.0001
        )
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
        XCTAssertEqual(payload.logicalSize, item.size)
        XCTAssertEqual(payload.scrollOffsetY, item.scrollOffsetY)
        XCTAssertEqual(payload.cameraZoomScale, session.camera.zoomScale)
    }

    func testMeasuredMarkdownHeightKeepsTrailingParagraphVisibleInCoreTextFrame() {
        let source = """
        # Event Loop

        # React Scheduler

        Summary.

        ```swift
        func workLoop() {
            while hasWork {
                if shouldYieldToHost() {
                    break
                }
                performUnitOfWork()
            }
        }
        ```

        Yield note.

        ```javascript
        function shouldYieldToHost() {
            return performance.now() >= deadline
        }
        ```

        More details around cooperative scheduling and host yielding continue here.

        ```typescript
        export function scheduleWork() {
            requestHostCallback(flushWork)
        }
        ```

        Continue reading.

        React Scheduler 源码里也能看到类似逻辑：Scheduler 会周期性 yield，让主线程有机会处理用户事件等工作；`shouldYieldToHost` 会根据当前任务占用主线程的时间判断是否让出。

        Test

        Line 2
        """
        let style = CanvasTextStyle(fontSize: 22)
        let layoutWidth: CGFloat = 1197.67
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: source,
            style: style,
            maxLayoutWidth: layoutWidth,
            scale: 1,
            includeCompatibilityCodeBlockBackgrounds: false
        )
        let suggestedSize = coreTextSuggestedSize(
            for: layout.attributedText,
            maxLayoutWidth: layoutWidth
        )
        let visibleRange = coreTextVisibleRange(
            for: layout.attributedText,
            size: layout.contentSize
        )
        let legacyBoundingRectHeight = layout.attributedText.boundingRect(
            with: CGSize(
                width: layoutWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        ).height

        XCTAssertEqual(
            visibleRange.location + visibleRange.length,
            layout.attributedText.length,
            "Expected measured markdown height to keep the trailing paragraph visible."
        )
        XCTAssertGreaterThanOrEqual(
            layout.contentSize.height,
            ceil(suggestedSize.height)
        )
        XCTAssertGreaterThan(
            suggestedSize.height - legacyBoundingRectHeight,
            0.5,
            "Regression fixture should stay sensitive to the old boundingRect under-measurement."
        )
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

private func coreTextSuggestedSize(
    for attributedText: NSAttributedString,
    maxLayoutWidth: CGFloat
) -> CGSize {
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    return CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        nil,
        CGSize(
            width: maxLayoutWidth,
            height: CGFloat.greatestFiniteMagnitude
        ),
        nil
    )
}

private func coreTextVisibleRange(
    for attributedText: NSAttributedString,
    size: CGSize
) -> CFRange {
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
        nil
    )
    return CTFrameGetVisibleStringRange(frame)
}
