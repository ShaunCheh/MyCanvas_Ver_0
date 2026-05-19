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
