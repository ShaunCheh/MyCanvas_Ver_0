import CoreGraphics
import QuartzCore
import XCTest
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import MyCanvas_Ver_0

final class CanvasTextLayerTests: XCTestCase {
    func testUpdateUsesAuthoritativeFontSizeEvenWhenBoundsAreSmall() throws {
        let itemID = CanvasItemID()
        let layer = CanvasTextLayer(itemID: itemID)
        let textPayload = CanvasTextRenderPayload(
            text: "A very long line of text",
            style: CanvasTextStyle(fontSize: 32),
            zoomScale: 1.5
        )
        let renderItem = makeTextLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 24, height: 12),
            textPayload: textPayload
        )

        layer.update(
            with: renderItem,
            textPayload: textPayload,
            contentsScale: 2
        )

        let attributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let font = try XCTUnwrap(
            attributedText.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? PlatformTestFont
        )

        XCTAssertEqual(
            font.pointSize,
            CanvasTextLayoutMeasurer.renderFontSize(
                for: textPayload.style,
                scale: textPayload.zoomScale
            ),
            accuracy: 0.0001
        )
    }
}

#if os(macOS)
private typealias PlatformTestFont = NSFont
#elseif canImport(UIKit)
private typealias PlatformTestFont = UIFont
#endif

private func makeTextLayerRenderItem(
    itemID: CanvasItemID,
    size: CGSize,
    textPayload: CanvasTextRenderPayload
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
        payload: .text(textPayload)
    )
}
