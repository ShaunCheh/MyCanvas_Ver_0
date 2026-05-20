import CoreGraphics
import QuartzCore
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasMarkdownLayerTests: XCTestCase {
    func testItemLayerUsesLogicalBoundsAndCameraScaleTransform() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownItemLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            logicalSize: CGSize(width: 220, height: 120),
            scrollOffsetY: 0,
            cameraZoomScale: 1.5
        )
        let renderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            payload: payload,
            screenCenter: CGPoint(x: 180, y: 120),
            rotationRadians: .pi / 6,
            zIndex: 4
        )

        layer.update(
            with: renderItem,
            markdownPayload: payload,
            contentsScale: 2
        )

        let contentImage = try markdownContentImage(from: layer.contentLayer)
        let expectedLayout = makeExpectedMarkdownLayout(for: payload)
        let affineTransform = CATransform3DGetAffineTransform(layer.transform)

        XCTAssertEqual(layer.bounds.size, payload.logicalSize)
        XCTAssertEqual(layer.position, renderItem.screenCenter)
        XCTAssertEqual(layer.zPosition, 4)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertTrue(layer.contentLayer.superlayer === layer)
        XCTAssertEqual(layer.contentLayer.bounds.size, expectedLayout.contentSize)
        XCTAssertEqual(contentImage.width, Int(ceil(expectedLayout.contentSize.width * 3)))
        XCTAssertEqual(contentImage.height, Int(ceil(expectedLayout.contentSize.height * 3)))
        XCTAssertEqual(markdownLayerTransformScale(affineTransform), 1.5, accuracy: 0.001)
        XCTAssertEqual(markdownLayerTransformRotation(affineTransform), .pi / 6, accuracy: 0.001)
    }

    func testContentLayerReflowsWhenLogicalWidthChanges() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownItemLayer(itemID: itemID)
        let widePayload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            A long markdown paragraph that should wrap onto additional lines when the block becomes narrower.
            """,
            style: CanvasTextStyle(fontSize: 18),
            logicalSize: CGSize(width: 260, height: 140),
            scrollOffsetY: 0,
            cameraZoomScale: 1
        )
        let wideRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            payload: widePayload
        )
        layer.update(
            with: wideRenderItem,
            markdownPayload: widePayload,
            contentsScale: 2
        )
        let wideLayoutSize = layer.contentLayer.bounds.size

        let narrowPayload = CanvasMarkdownRenderPayload(
            markdownSource: widePayload.markdownSource,
            style: widePayload.style,
            logicalSize: CGSize(width: 140, height: 140),
            scrollOffsetY: 0,
            cameraZoomScale: 1
        )
        let narrowRenderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            payload: narrowPayload
        )
        layer.update(
            with: narrowRenderItem,
            markdownPayload: narrowPayload,
            contentsScale: 2
        )
        let narrowLayoutSize = layer.contentLayer.bounds.size
        let expectedNarrowLayout = makeExpectedMarkdownLayout(for: narrowPayload)

        XCTAssertEqual(layer.bounds.size, narrowPayload.logicalSize)
        XCTAssertEqual(wideLayoutSize.width, widePayload.logicalSize.width)
        XCTAssertEqual(narrowLayoutSize, expectedNarrowLayout.contentSize)
        XCTAssertGreaterThan(narrowLayoutSize.height, wideLayoutSize.height)
    }

    func testContentLayerKeepsLogicalLayoutSizeWhenOnlyHeightOrZoomChanges() throws {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownItemLayer(itemID: itemID)
        let compactPayload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            logicalSize: CGSize(width: 220, height: 80),
            scrollOffsetY: 0,
            cameraZoomScale: 1
        )
        let compactRenderItem = makeMarkdownLayerRenderItem(itemID: itemID, payload: compactPayload)
        layer.update(
            with: compactRenderItem,
            markdownPayload: compactPayload,
            contentsScale: 2
        )
        let expectedLayout = makeExpectedMarkdownLayout(for: compactPayload)
        let compactImage = try markdownContentImage(from: layer.contentLayer)

        let tallerPayload = CanvasMarkdownRenderPayload(
            markdownSource: compactPayload.markdownSource,
            style: compactPayload.style,
            logicalSize: CGSize(width: 220, height: 180),
            scrollOffsetY: 0,
            cameraZoomScale: 1
        )
        let tallerRenderItem = makeMarkdownLayerRenderItem(itemID: itemID, payload: tallerPayload)
        layer.update(
            with: tallerRenderItem,
            markdownPayload: tallerPayload,
            contentsScale: 2
        )
        let tallerImage = try markdownContentImage(from: layer.contentLayer)

        let zoomedPayload = CanvasMarkdownRenderPayload(
            markdownSource: compactPayload.markdownSource,
            style: compactPayload.style,
            logicalSize: tallerPayload.logicalSize,
            scrollOffsetY: 0,
            cameraZoomScale: 1.5
        )
        let zoomedRenderItem = makeMarkdownLayerRenderItem(itemID: itemID, payload: zoomedPayload)
        layer.update(
            with: zoomedRenderItem,
            markdownPayload: zoomedPayload,
            contentsScale: 2
        )
        let zoomedImage = try markdownContentImage(from: layer.contentLayer)

        XCTAssertEqual(layer.contentLayer.bounds.size, expectedLayout.contentSize)
        XCTAssertEqual(layer.bounds.size, tallerPayload.logicalSize)
        XCTAssertEqual(compactImage.width, Int(ceil(expectedLayout.contentSize.width * 2)))
        XCTAssertEqual(compactImage.height, Int(ceil(expectedLayout.contentSize.height * 2)))
        XCTAssertEqual(tallerImage.width, compactImage.width)
        XCTAssertEqual(tallerImage.height, compactImage.height)
        XCTAssertEqual(zoomedImage.width, Int(ceil(expectedLayout.contentSize.width * 3)))
        XCTAssertEqual(zoomedImage.height, Int(ceil(expectedLayout.contentSize.height * 3)))
    }

    func testContentLayerOffsetsBitmapByClampedScrollOffset() {
        let itemID = CanvasItemID()
        let layer = CanvasMarkdownItemLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Line 1

            Line 2

            Line 3

            Line 4
            """,
            style: CanvasTextStyle(fontSize: 18),
            logicalSize: CGSize(width: 220, height: 72),
            scrollOffsetY: 10_000,
            cameraZoomScale: 1
        )
        let renderItem = makeMarkdownLayerRenderItem(
            itemID: itemID,
            payload: payload
        )
        let expectedLayout = makeExpectedMarkdownLayout(for: payload)
        let expectedMaxScrollOffsetY = max(
            expectedLayout.contentSize.height - payload.logicalSize.height,
            0
        )

        layer.update(
            with: renderItem,
            markdownPayload: payload,
            contentsScale: 2
        )

        XCTAssertEqual(
            layer.contentLayer.position.y,
            -expectedMaxScrollOffsetY,
            accuracy: 0.0001
        )
    }

    func testContentLayerSkipsLayoutAndBitmapRefreshWithinSameRasterBucket() throws {
        let renderer = CanvasMarkdownBitmapRendererSpy()
        var layoutInvocationCount = 0
        let layer = CanvasMarkdownContentLayer(
            itemID: CanvasItemID(),
            bitmapRenderer: renderer,
            layoutProvider: { payload in
                layoutInvocationCount += 1
                return makeExpectedMarkdownLayout(for: payload)
            }
        )
        let firstPayload = makeMarkdownContentPayload(cameraZoomScale: 1.1)
        let secondPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)
        let expectedLayout = makeExpectedMarkdownLayout(for: firstPayload)

        layer.update(with: firstPayload, contentsScale: 1)
        let firstImage = try markdownContentImage(from: layer)

        layer.update(with: secondPayload, contentsScale: 1)
        let secondImage = try markdownContentImage(from: layer)

        XCTAssertEqual(layoutInvocationCount, 1)
        XCTAssertEqual(renderer.rasterScales, [1.5])
        XCTAssertEqual(layer.bounds.size, expectedLayout.contentSize)
        XCTAssertEqual(firstImage.width, secondImage.width)
        XCTAssertEqual(firstImage.height, secondImage.height)
    }

    func testContentLayerCrossingRasterBucketRerendersWithoutRelayout() throws {
        let renderer = CanvasMarkdownBitmapRendererSpy()
        var layoutInvocationCount = 0
        let layer = CanvasMarkdownContentLayer(
            itemID: CanvasItemID(),
            bitmapRenderer: renderer,
            layoutProvider: { payload in
                layoutInvocationCount += 1
                return makeExpectedMarkdownLayout(for: payload)
            }
        )
        let firstPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)
        let secondPayload = makeMarkdownContentPayload(cameraZoomScale: 1.6)
        let expectedLayout = makeExpectedMarkdownLayout(for: firstPayload)

        layer.update(with: firstPayload, contentsScale: 1)
        let firstImage = try markdownContentImage(from: layer)

        layer.update(with: secondPayload, contentsScale: 1)
        let secondImage = try markdownContentImage(from: layer)

        XCTAssertEqual(layoutInvocationCount, 1)
        XCTAssertEqual(renderer.rasterScales, [1.5, 2])
        XCTAssertEqual(layer.bounds.size, expectedLayout.contentSize)
        XCTAssertGreaterThan(secondImage.width, firstImage.width)
        XCTAssertGreaterThan(secondImage.height, firstImage.height)
    }

    func testContentLayerReusesCachedBitmapWhenReturningToPreviousRasterBucket() throws {
        let renderer = CanvasMarkdownBitmapRendererSpy()
        var layoutInvocationCount = 0
        let layer = CanvasMarkdownContentLayer(
            itemID: CanvasItemID(),
            bitmapRenderer: renderer,
            layoutProvider: { payload in
                layoutInvocationCount += 1
                return makeExpectedMarkdownLayout(for: payload)
            }
        )
        let initialPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)
        let higherBucketPayload = makeMarkdownContentPayload(cameraZoomScale: 1.6)
        let returnPayload = makeMarkdownContentPayload(cameraZoomScale: 1.3)

        layer.update(with: initialPayload, contentsScale: 1)
        let initialImage = try markdownContentImage(from: layer)

        layer.update(with: higherBucketPayload, contentsScale: 1)

        layer.update(with: returnPayload, contentsScale: 1)
        let returnedImage = try markdownContentImage(from: layer)

        XCTAssertEqual(layoutInvocationCount, 1)
        XCTAssertEqual(renderer.rasterScales, [1.5, 2])
        XCTAssertEqual(returnedImage.width, initialImage.width)
        XCTAssertEqual(returnedImage.height, initialImage.height)
    }
}

private func makeMarkdownLayerRenderItem(
    itemID: CanvasItemID,
    payload: CanvasMarkdownRenderPayload,
    screenCenter: CGPoint = CGPoint(x: 140, y: 90),
    rotationRadians: CGFloat = 0,
    zIndex: CGFloat = 0
) -> CanvasRenderItem {
    let screenSize = CGSize(
        width: payload.logicalSize.width * payload.cameraZoomScale,
        height: payload.logicalSize.height * payload.cameraZoomScale
    )
    let rect = CGRect(
        x: screenCenter.x - screenSize.width / 2,
        y: screenCenter.y - screenSize.height / 2,
        width: screenSize.width,
        height: screenSize.height
    )
    return CanvasRenderItem(
        id: itemID,
        screenFrame: rect,
        screenQuad: CanvasQuad(rect: rect),
        screenCenter: screenCenter,
        screenBoundsSize: screenSize,
        rotationRadians: rotationRadians,
        zIndex: zIndex,
        payload: .markdown(payload)
    )
}

private func makeExpectedMarkdownLayout(
    for payload: CanvasMarkdownRenderPayload
) -> CanvasMarkdownLayoutResult {
    CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: payload.markdownSource,
        style: payload.style,
        maxLayoutWidth: payload.logicalSize.width,
        scale: 1,
        includeCompatibilityCodeBlockBackgrounds: false
    )
}

private func makeMarkdownContentPayload(
    markdownSource: String = """
    ## Title

    Body with `code`
    """,
    logicalWidth: CGFloat = 220,
    logicalHeight: CGFloat = 120,
    scrollOffsetY: CGFloat = 0,
    cameraZoomScale: CGFloat
) -> CanvasMarkdownRenderPayload {
    CanvasMarkdownRenderPayload(
        markdownSource: markdownSource,
        style: CanvasTextStyle(fontSize: 18),
        logicalSize: CGSize(width: logicalWidth, height: logicalHeight),
        scrollOffsetY: scrollOffsetY,
        cameraZoomScale: cameraZoomScale
    )
}

private func markdownLayerTransformScale(
    _ transform: CGAffineTransform
) -> CGFloat {
    hypot(transform.a, transform.c)
}

private func markdownLayerTransformRotation(
    _ transform: CGAffineTransform
) -> CGFloat {
    atan2(transform.b, transform.a)
}

private func markdownContentImage(
    from layer: CanvasMarkdownContentLayer
) throws -> CGImage {
    let contents = try XCTUnwrap(layer.contents)
    return contents as! CGImage
}

private final class CanvasMarkdownBitmapRendererSpy: CanvasMarkdownBitmapRendering {
    private(set) var rasterScales: [CGFloat] = []
    private(set) var images: [CGImage] = []

    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        rasterScales.append(rasterScale)
        let image = makeMarkdownLayerTestImage(
            pixelWidth: Int(ceil(layout.contentSize.width * rasterScale)),
            pixelHeight: Int(ceil(layout.contentSize.height * rasterScale))
        )
        if let image {
            images.append(image)
        }
        return image
    }
}

private func makeMarkdownLayerTestImage(
    pixelWidth: Int,
    pixelHeight: Int
) -> CGImage? {
    guard
        pixelWidth > 0,
        pixelHeight > 0,
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        return nil
    }

    context.setFillColor(
        CGColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: pixelWidth,
            height: pixelHeight
        )
    )
    return context.makeImage()
}
