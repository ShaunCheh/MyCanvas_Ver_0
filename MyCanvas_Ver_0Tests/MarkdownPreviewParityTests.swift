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

private enum MarkdownPreviewParityTestRetainer {
    static var scenes: [CanvasScene] = []
    static var thumbnailRenderers: [BoardThumbnailRenderer] = []
}
