import CoreGraphics
import QuartzCore
import XCTest
#if os(macOS)
import AppKit
private typealias MarkdownLayerTestFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias MarkdownLayerTestFont = UIFont
#endif
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownLayerTests: XCTestCase {
    func testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            zoomScale: 1.5
        )
        let renderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 220, height: 120),
            payload: payload
        )

        layer.update(
            with: renderItem,
            markdownPayload: payload,
            contentsScale: 2
        )

        let attributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let rendered = attributedText.string as NSString
        let titleFont = try XCTUnwrap(
            attributedText.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? MarkdownLayerTestFont
        )
        let bodyRange = rendered.range(of: "Body")
        XCTAssertNotEqual(bodyRange.location, NSNotFound)
        let bodyFont = try XCTUnwrap(
            attributedText.attribute(
                .font,
                at: bodyRange.location,
                effectiveRange: nil
            ) as? MarkdownLayerTestFont
        )

        XCTAssertTrue(rendered.contains("Title"))
        XCTAssertTrue(rendered.contains("code"))
        XCTAssertEqual(layer.bounds.size, CGSize(width: 220, height: 120))
        XCTAssertGreaterThan(
            bodyFont.pointSize,
            payload.style.fontSize
        )
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
    }

    func testUpdateReflowsAttributedMarkdownWhenLayoutWidthChanges() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            A long markdown paragraph that should wrap onto additional lines when the block becomes narrower.
            """,
            style: CanvasTextStyle(fontSize: 18),
            zoomScale: 1
        )
        let wideRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 260, height: 120),
            payload: payload
        )
        layer.update(
            with: wideRenderItem,
            markdownPayload: payload,
            contentsScale: 2
        )
        let wideAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let wideRenderedHeight = measureMarkdownAttributedTextHeight(
            wideAttributedText,
            width: wideRenderItem.screenBoundsSize.width
        )

        let narrowRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 140, height: 120),
            payload: payload
        )
        layer.update(
            with: narrowRenderItem,
            markdownPayload: payload,
            contentsScale: 2
        )
        let narrowAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let narrowRenderedHeight = measureMarkdownAttributedTextHeight(
            narrowAttributedText,
            width: narrowRenderItem.screenBoundsSize.width
        )
        let expectedNarrowHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: payload.markdownSource,
            style: payload.style,
            maxLayoutWidth: narrowRenderItem.screenBoundsSize.width,
            scale: payload.zoomScale
        )

        XCTAssertEqual(layer.bounds.size, narrowRenderItem.screenBoundsSize)
        XCTAssertGreaterThan(narrowRenderedHeight, wideRenderedHeight)
        XCTAssertEqual(
            narrowRenderedHeight,
            expectedNarrowHeight,
            accuracy: 1
        )
    }

    func testUpdateKeepsMarkdownFontSizesWhenOnlyHeightChanges() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            zoomScale: 1.25
        )
        let compactRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 220, height: 80),
            payload: payload
        )
        layer.update(
            with: compactRenderItem,
            markdownPayload: payload,
            contentsScale: 2
        )
        let compactAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let compactFonts = try markdownLayerTestFonts(in: compactAttributedText)

        let tallerRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 220, height: 180),
            payload: payload
        )
        layer.update(
            with: tallerRenderItem,
            markdownPayload: payload,
            contentsScale: 2
        )
        let tallerAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let tallerFonts = try markdownLayerTestFonts(in: tallerAttributedText)

        XCTAssertEqual(layer.bounds.size, tallerRenderItem.screenBoundsSize)
        XCTAssertEqual(tallerFonts.title.pointSize, compactFonts.title.pointSize)
        XCTAssertEqual(tallerFonts.body.pointSize, compactFonts.body.pointSize)
    }
}

private func makeMarkdownLayerRenderItem(
    itemID: CanvasItemID,
    size: CGSize,
    payload: CanvasMarkdownRenderPayload
) -> CanvasRenderItem {
    let rect = CGRect(origin: .zero, size: size)
    return CanvasRenderItem(
        id: itemID,
        screenFrame: rect,
        screenQuad: CanvasQuad(rect: rect),
        screenCenter: CGPoint(x: rect.midX, y: rect.midY),
        screenBoundsSize: size,
        rotationRadians: 0,
        zIndex: 0,
        payload: .markdown(payload)
    )
}

private func markdownLayerTestFonts(
    in attributedText: NSAttributedString
) throws -> (title: MarkdownLayerTestFont, body: MarkdownLayerTestFont) {
    let rendered = attributedText.string as NSString
    let titleFont = try XCTUnwrap(
        attributedText.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? MarkdownLayerTestFont
    )
    let bodyRange = rendered.range(of: "Body")
    XCTAssertNotEqual(bodyRange.location, NSNotFound)
    let bodyFont = try XCTUnwrap(
        attributedText.attribute(
            .font,
            at: bodyRange.location,
            effectiveRange: nil
        ) as? MarkdownLayerTestFont
    )
    return (title: titleFont, body: bodyFont)
}

private func measureMarkdownAttributedTextHeight(
    _ attributedText: NSAttributedString,
    width: CGFloat
) -> CGFloat {
    attributedText.boundingRect(
        with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    ).height
}
