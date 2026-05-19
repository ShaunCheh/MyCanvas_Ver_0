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

    func testLayoutProducesDecorationForFencedCodeBlock() throws {
        let width: CGFloat = 260
        let codeText = """
        let value = 1
        print(value)
        """
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            Intro

            ```
            \(codeText)
            ```

            Outro
            """,
            style: CanvasTextStyle(fontSize: 18),
            maxLayoutWidth: width
        )
        let decoration = try XCTUnwrap(layout.decorations.first)
        let usedRect = try markdownCodeBlockUsedRect(
            in: layout.attributedText,
            codeText: codeText,
            width: width
        )

        XCTAssertEqual(layout.decorations.count, 1)
        XCTAssertEqual(decoration.kind, .codeBlockPanel)
        XCTAssertLessThan(decoration.rect.width, width)
        XCTAssertGreaterThanOrEqual(usedRect.minX, decoration.rect.minX)
        XCTAssertLessThanOrEqual(usedRect.maxX, decoration.rect.maxX)
        XCTAssertGreaterThanOrEqual(usedRect.minY, decoration.rect.minY)
        XCTAssertLessThanOrEqual(usedRect.maxY, decoration.rect.maxY)
        XCTAssertGreaterThanOrEqual(decoration.rect.minX, 0)
        XCTAssertGreaterThanOrEqual(decoration.rect.minY, 0)
        XCTAssertLessThanOrEqual(decoration.rect.maxX, layout.contentSize.width + 0.0001)
        XCTAssertLessThanOrEqual(decoration.rect.maxY, layout.contentSize.height + 0.0001)
        XCTAssertEqual(decoration.fillColor.alpha, 0.08, accuracy: 0.0001)
        XCTAssertGreaterThan(decoration.cornerRadius, 0)
    }

    func testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds() throws {
        let width: CGFloat = 280
        let codeText = "let value = 1"
        let source = """
        Intro

        ```
        \(codeText)
        ```

        Outro
        """

        let smallLayout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: source,
            style: CanvasTextStyle(fontSize: 8),
            maxLayoutWidth: width
        )
        let smallDecoration = try XCTUnwrap(smallLayout.decorations.first)
        let smallUsedRect = try markdownCodeBlockUsedRect(
            in: smallLayout.attributedText,
            codeText: codeText,
            width: width
        )
        let smallInsets = markdownDecorationInsets(
            decorationRect: smallDecoration.rect,
            usedRect: smallUsedRect
        )

        XCTAssertEqual(smallInsets.left, 4, accuracy: 1)
        XCTAssertEqual(smallInsets.right, 4, accuracy: 1)
        XCTAssertEqual(smallInsets.top, 2, accuracy: 1)
        XCTAssertEqual(smallInsets.bottom, 2, accuracy: 1)
        XCTAssertEqual(smallDecoration.cornerRadius, 4, accuracy: 1)

        let largeLayout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: source,
            style: CanvasTextStyle(fontSize: 80),
            maxLayoutWidth: width
        )
        let largeDecoration = try XCTUnwrap(largeLayout.decorations.first)
        let largeUsedRect = try markdownCodeBlockUsedRect(
            in: largeLayout.attributedText,
            codeText: codeText,
            width: width
        )
        let largeInsets = markdownDecorationInsets(
            decorationRect: largeDecoration.rect,
            usedRect: largeUsedRect
        )

        XCTAssertEqual(largeInsets.left, 12, accuracy: 1)
        XCTAssertEqual(largeInsets.right, 12, accuracy: 1)
        XCTAssertEqual(largeInsets.top, 6, accuracy: 1)
        XCTAssertEqual(largeInsets.bottom, 6, accuracy: 1)
        XCTAssertEqual(largeDecoration.cornerRadius, 10, accuracy: 1)
    }
}

private enum CanvasMarkdownLayoutMeasurerTestError: Error {
    case missingCodeRange
    case missingUsedRect
}

private func markdownCodeBlockUsedRect(
    in attributedText: NSAttributedString,
    codeText: String,
    width: CGFloat
) throws -> CGRect {
    let rendered = attributedText.string as NSString
    let range = rendered.range(of: codeText)
    guard range.location != NSNotFound else {
        throw CanvasMarkdownLayoutMeasurerTestError.missingCodeRange
    }

    let textStorage = NSTextStorage(attributedString: attributedText)
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(
        size: CGSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
    )
    textContainer.lineFragmentPadding = 0
    textContainer.maximumNumberOfLines = 0
    textContainer.lineBreakMode = .byWordWrapping
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    _ = layoutManager.glyphRange(for: textContainer)

    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: range,
        actualCharacterRange: nil
    )
    var usedRect: CGRect?
    layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
        _,
        lineUsedRect,
        _,
        lineGlyphRange,
        _
    in
        guard NSIntersectionRange(lineGlyphRange, glyphRange).length > 0 else {
            return
        }
        usedRect = usedRect.map { $0.union(lineUsedRect) } ?? lineUsedRect
    }

    guard let usedRect else {
        throw CanvasMarkdownLayoutMeasurerTestError.missingUsedRect
    }
    return usedRect
}

private func markdownDecorationInsets(
    decorationRect: CGRect,
    usedRect: CGRect
) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
    (
        left: usedRect.minX - decorationRect.minX,
        right: decorationRect.maxX - usedRect.maxX,
        top: usedRect.minY - decorationRect.minY,
        bottom: decorationRect.maxY - usedRect.maxY
    )
}
