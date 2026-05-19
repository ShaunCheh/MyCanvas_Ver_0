import CoreGraphics
import XCTest
#if os(macOS)
import AppKit
private typealias MarkdownTestFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias MarkdownTestFont = UIFont
#endif
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownLayoutMeasurerTests: XCTestCase {
    func testMeasuredContentHeightGrowsWhenWidthShrinks() {
        let source = """
        ## Title

        - A long markdown list item that needs wrapping.
        - Another long markdown list item that also needs wrapping.
        """
        let style = CanvasTextStyle(fontSize: 18)

        let wideHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: 320
        )
        let narrowHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: 160
        )

        XCTAssertGreaterThan(narrowHeight, wideHeight)
    }

    func testLayoutConvertsBasicBlocksIntoDisplayText() {
        let source = """
        # Title

        - item
        > quote

        `code`
        """
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: source,
            style: CanvasTextStyle(fontSize: 18),
            maxLayoutWidth: 240
        )

        XCTAssertTrue(layout.attributedText.string.contains("Title"))
        XCTAssertTrue(layout.attributedText.string.contains("• item"))
        XCTAssertTrue(layout.attributedText.string.contains("▌ quote"))
        XCTAssertTrue(layout.attributedText.string.contains("code"))
        XCTAssertTrue(layout.attributedText.string.contains("\n\n"))
    }

    func testHeadingUsesLargerFontThanBody() throws {
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            # Title

            Body
            """,
            style: CanvasTextStyle(fontSize: 20),
            maxLayoutWidth: 240
        )
        let rendered = layout.attributedText.string as NSString
        let titleFont = try XCTUnwrap(
            layout.attributedText.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? MarkdownTestFont
        )
        let bodyRange = rendered.range(of: "Body")
        XCTAssertNotEqual(bodyRange.location, NSNotFound)
        let bodyFont = try XCTUnwrap(
            layout.attributedText.attribute(
                .font,
                at: bodyRange.location,
                effectiveRange: nil
            ) as? MarkdownTestFont
        )

        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
    }
}
