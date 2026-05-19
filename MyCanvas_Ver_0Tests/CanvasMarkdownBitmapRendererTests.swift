import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownBitmapRendererTests: XCTestCase {
    func testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize() throws {
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            # Title

            Body
            """,
            style: CanvasTextStyle(fontSize: 18),
            maxLayoutWidth: 160
        )
        let renderer = CanvasMarkdownBitmapRenderer()
        CanvasMarkdownBitmapRendererTestRetainer.renderers.append(renderer)
        CanvasMarkdownBitmapRendererTestRetainer.layouts.append(layout)
        let rasterScale: CGFloat = 2

        let image = try XCTUnwrap(
            renderer.render(
                layout: layout,
                rasterScale: rasterScale
            )
        )
        CanvasMarkdownBitmapRendererTestRetainer.images.append(image)

        XCTAssertEqual(image.width, Int(ceil(layout.contentSize.width * rasterScale)))
        XCTAssertEqual(image.height, Int(ceil(layout.contentSize.height * rasterScale)))
    }

    func testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled() throws {
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            ```

            ```
            """,
            style: CanvasTextStyle(fontSize: 20),
            maxLayoutWidth: 180,
            includeCompatibilityCodeBlockBackgrounds: false
        )
        let decoration = try XCTUnwrap(layout.decorations.first)
        let renderer = CanvasMarkdownBitmapRenderer()
        CanvasMarkdownBitmapRendererTestRetainer.renderers.append(renderer)
        CanvasMarkdownBitmapRendererTestRetainer.layouts.append(layout)
        let image = try XCTUnwrap(
            renderer.render(
                layout: layout,
                rasterScale: 1
            )
        )
        CanvasMarkdownBitmapRendererTestRetainer.images.append(image)

        let centerPixel = try XCTUnwrap(
            rgbaAtTopLeftPixel(
                x: min(max(Int(decoration.rect.midX.rounded(.down)), 0), image.width - 1),
                y: min(max(Int(decoration.rect.midY.rounded(.down)), 0), image.height - 1),
                in: image
            )
        )
        let outsidePixel = try XCTUnwrap(
            rgbaAtTopLeftPixel(
                x: max(image.width - 1, 0),
                y: max(image.height - 1, 0),
                in: image
            )
        )

        XCTAssertGreaterThan(centerPixel.a, 0)
        XCTAssertGreaterThan(centerPixel.a, outsidePixel.a)
    }
}

private enum CanvasMarkdownBitmapRendererTestRetainer {
    static var renderers: [CanvasMarkdownBitmapRenderer] = []
    static var layouts: [CanvasMarkdownLayoutResult] = []
    static var images: [CGImage] = []
}

private func rgbaAtTopLeftPixel(
    x: Int,
    y: Int,
    in image: CGImage
) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    guard
        x >= 0,
        y >= 0,
        x < image.width,
        y < image.height
    else {
        return nil
    }

    let bytesPerRow = image.width * 4
    var pixelBytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue

    let didRender = pixelBytes.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let baseAddress = buffer.baseAddress,
            let context = CGContext(
                data: baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else {
            return false
        }

        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: image.width,
                height: image.height
            )
        )
        return true
    }
    guard didRender else {
        return nil
    }

    let pixelStart = (y * bytesPerRow) + (x * 4)
    return (
        r: pixelBytes[pixelStart],
        g: pixelBytes[pixelStart + 1],
        b: pixelBytes[pixelStart + 2],
        a: pixelBytes[pixelStart + 3]
    )
}
