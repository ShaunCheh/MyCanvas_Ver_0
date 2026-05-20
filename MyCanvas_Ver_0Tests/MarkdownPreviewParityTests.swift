import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class MarkdownPreviewParityTests: XCTestCase {
    func testCanvasMiniMapRendererUsesDedicatedMarkdownNodeKind() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: "## Title\n\nBody",
            center: CGPoint(x: 140, y: 90),
            size: CGSize(width: 220, height: 140),
            zIndex: 4
        )
        let textItem = CanvasTextItem(
            text: "Caption",
            center: CGPoint(x: 40, y: 30),
            size: CGSize(width: 100, height: 50),
            zIndex: 1
        )
        var scene = CanvasScene()
        scene.append(textItem)
        scene.append(markdownItem)
        MarkdownPreviewParityTestRetainer.scenes.append(scene)

        let snapshot = CanvasMiniMapRenderer().makeSnapshot(
            context: CanvasMiniMapRenderContext(
                scene: scene,
                camera: CanvasCamera(
                    center: .zero,
                    zoomScale: 1,
                    viewportSize: CGSize(width: 480, height: 320)
                )
            )
        )

        let markdownNode = try XCTUnwrap(
            snapshot.nodes.first(where: { $0.id == markdownItem.id })
        )
        let textNode = try XCTUnwrap(
            snapshot.nodes.first(where: { $0.id == textItem.id })
        )
        XCTAssertEqual(markdownNode.kind, .markdown)
        XCTAssertEqual(markdownNode.worldBounds, markdownItem.worldBounds)
        XCTAssertEqual(textNode.kind, .text)
    }

    func testBoardGeometryPreviewBuilderMarksMarkdownNodesAsMarkdown() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: "# Heading\n\n- Item one\n- Item two",
            center: CGPoint(x: 180, y: 120),
            size: CGSize(width: 240, height: 160),
            zIndex: 2
        )
        let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
        let document = BoardDocumentMapper.makeDocument(from: runtimeState)

        let previewSeed = BoardGeometryPreviewBuilder().makeSeed(from: document)
        let node = try XCTUnwrap(
            previewSeed.nodes.first(where: { $0.id == markdownItem.id })
        )
        XCTAssertEqual(node.kind, .markdown)
        XCTAssertEqual(node.worldBounds, markdownItem.worldBounds)
    }

    func testBoardThumbnailRendererRendersVisibleMarkdownThumbnail() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: """
            # Heading

            A longer markdown paragraph that should remain visible in board thumbnails.

            - First
            - Second
            """,
            center: CGPoint(x: 160, y: 120),
            size: CGSize(width: 260, height: 180),
            zIndex: 1
        )
        let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
        let renderer = BoardThumbnailRenderer()
        MarkdownPreviewParityTestRetainer.thumbnailRenderers.append(renderer)

        let renderedImage = try XCTUnwrap(
            renderer.renderPersistedThumbnail(
                for: runtimeState,
                maximumLongestSide: 256
            )
        )
        XCTAssertTrue(
            imageContainsVisiblePixels(renderedImage),
            "Expected markdown-only board thumbnail to contain visible pixels."
        )
    }

    func testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: """
            ```

            ```
            """,
            center: CGPoint(x: 160, y: 120),
            size: CGSize(width: 260, height: 180),
            zIndex: 1
        )
        let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
        let renderer = BoardThumbnailRenderer()
        MarkdownPreviewParityTestRetainer.thumbnailRenderers.append(renderer)

        let renderedImage = try XCTUnwrap(
            renderer.renderPersistedThumbnail(
                for: runtimeState,
                maximumLongestSide: 256
            )
        )
        XCTAssertTrue(
            imageContainsVisiblePixels(renderedImage),
            "Expected empty fenced code block to remain visible via markdown decorations in the thumbnail."
        )
    }

    func testBoardThumbnailRendererUsesWorldSpaceMarkdownLayoutWidth() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: """
            # Heading

            This thumbnail should reuse the markdown semantic layout width from the persisted world item instead of reflowing in preview space.
            """,
            center: CGPoint(x: 220, y: 160),
            size: CGSize(width: 420, height: 240),
            zIndex: 1
        )
        let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
        let bitmapRendererSpy = MarkdownPreviewBitmapRendererSpy()
        let renderer = BoardThumbnailRenderer(
            markdownBitmapRenderer: bitmapRendererSpy
        )
        MarkdownPreviewParityTestRetainer.thumbnailRenderers.append(renderer)

        let renderedImage = try XCTUnwrap(
            renderer.renderPersistedThumbnail(
                for: runtimeState,
                maximumLongestSide: 256
            )
        )
        let renderedLayout = try XCTUnwrap(bitmapRendererSpy.layouts.first)

        XCTAssertTrue(imageContainsVisiblePixels(renderedImage))
        XCTAssertEqual(
            renderedLayout.contentSize.width,
            markdownItem.size.width,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(bitmapRendererSpy.rasterScales.first ?? 0, 0)
    }
}

private func makeMarkdownPreviewTestItem(
    markdownSource: String,
    center: CGPoint,
    size: CGSize,
    zIndex: CGFloat
) -> CanvasMarkdownItem {
    CanvasMarkdownItem(
        markdownSource: markdownSource,
        style: CanvasTextStyle(fontSize: 22),
        center: center,
        size: size,
        zIndex: zIndex
    )
}

private func makeMarkdownPreviewRuntimeState(
    item: CanvasMarkdownItem
) -> BoardRuntimeState {
    var runtimeState = BoardRuntimeState.makeEmpty()
    runtimeState.items = [.markdown(item)]
    runtimeState.camera = CanvasCamera(
        center: item.center,
        zoomScale: 1,
        viewportSize: CGSize(width: 640, height: 480)
    )
    return runtimeState
}

private func imageContainsVisiblePixels(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
        return false
    }

    let bytesPerRow = width * 4
    var pixelBytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue

    let didRender = pixelBytes.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let baseAddress = buffer.baseAddress,
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else {
            return false
        }

        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return true
    }
    guard didRender else {
        return false
    }

    return stride(from: 3, to: pixelBytes.count, by: 4).contains {
        pixelBytes[$0] > 0
    }
}

private final class MarkdownPreviewBitmapRendererSpy: CanvasMarkdownBitmapRendering {
    private(set) var layouts: [CanvasMarkdownLayoutResult] = []
    private(set) var rasterScales: [CGFloat] = []

    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        layouts.append(layout)
        rasterScales.append(rasterScale)
        return makeMarkdownPreviewBitmapRendererSpyImage()
    }
}

private func makeMarkdownPreviewBitmapRendererSpyImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    return context.makeImage()
}

private enum MarkdownPreviewParityTestRetainer {
    static var scenes: [CanvasScene] = []
    static var thumbnailRenderers: [BoardThumbnailRenderer] = []
}
