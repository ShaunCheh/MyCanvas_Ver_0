import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasSelectionTransformStateTests: XCTestCase {
    func testTranslatedMemberGeometriesApplySharedWorldDelta() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 10, y: 20),
                    size: CGSize(width: 40, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 70, y: 50),
                    size: CGSize(width: 30, height: 10),
                    rotationRadians: .pi / 6
                )
            ],
            selectionBounds: CGRect(x: -10, y: 10, width: 95, height: 50)
        )

        let translated = snapshot.translatedMemberGeometries(
            by: CGPoint(x: 15, y: -8)
        )
        let firstGeometry = try XCTUnwrap(
            translated.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            translated.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center, CGPoint(x: 25, y: 12))
        XCTAssertEqual(secondGeometry.center, CGPoint(x: 85, y: 42))
        XCTAssertEqual(secondGeometry.rotationRadians, .pi / 6, accuracy: 0.0001)
    }

    func testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 25, y: 25),
                    size: CGSize(width: 20, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 75, y: 75),
                    size: CGSize(width: 40, height: 20),
                    rotationRadians: .pi / 4
                )
            ],
            selectionBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let resized = snapshot.resizedMemberGeometries(
            handleRole: .bottomTrailing,
            draggedWorldCorner: CGPoint(x: 150, y: 150),
            minimumScale: 0.1
        )
        let firstGeometry = try XCTUnwrap(
            resized?.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            resized?.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center, CGPoint(x: 37.5, y: 37.5))
        XCTAssertEqual(secondGeometry.center, CGPoint(x: 112.5, y: 112.5))
        XCTAssertEqual(firstGeometry.size, CGSize(width: 30, height: 30))
        XCTAssertEqual(secondGeometry.size, CGSize(width: 60, height: 30))
    }

    func testRotatedMemberGeometriesRotateCentersAndItemAnglesAroundSelectionCenter() throws {
        let firstID = CanvasItemID()
        let secondID = CanvasItemID()
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: secondID,
            memberGeometries: [
                CanvasBoardItemGeometry(
                    itemID: firstID,
                    center: CGPoint(x: 50, y: 0),
                    size: CGSize(width: 20, height: 20),
                    rotationRadians: 0
                ),
                CanvasBoardItemGeometry(
                    itemID: secondID,
                    center: CGPoint(x: 100, y: 50),
                    size: CGSize(width: 30, height: 10),
                    rotationRadians: .pi / 6
                )
            ],
            selectionBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let rotated = snapshot.rotatedMemberGeometries(by: .pi / 2)
        let firstGeometry = try XCTUnwrap(
            rotated.first(where: { $0.itemID == firstID })
        )
        let secondGeometry = try XCTUnwrap(
            rotated.first(where: { $0.itemID == secondID })
        )

        XCTAssertEqual(firstGeometry.center.x, 100, accuracy: 0.0001)
        XCTAssertEqual(firstGeometry.center.y, 50, accuracy: 0.0001)
        XCTAssertEqual(secondGeometry.center.x, 50, accuracy: 0.0001)
        XCTAssertEqual(secondGeometry.center.y, 100, accuracy: 0.0001)
        XCTAssertEqual(firstGeometry.rotationRadians, .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(
            secondGeometry.rotationRadians,
            (.pi / 6) + (.pi / 2),
            accuracy: 0.0001
        )
    }

    func testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize() throws {
        let textStyle = CanvasTextStyle(fontSize: 20)
        let textItem = CanvasTextItem(
            text: "Scale me",
            style: textStyle,
            center: CGPoint(x: 25, y: 25),
            size: CanvasTextLayoutMeasurer.intrinsicItemSize(
                for: "Scale me",
                style: textStyle
            )
        )
        let imageItem = try makeSelectionTransformTestImageItem(
            center: CGPoint(x: 75, y: 75),
            size: CGSize(width: 40, height: 20)
        )
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: imageItem.id,
            memberItems: [
                .text(textItem),
                .image(imageItem)
            ],
            selectionBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let resizedItems = try XCTUnwrap(
            snapshot.resizedMemberItems(
                handleRole: .bottomTrailing,
                draggedWorldCorner: CGPoint(x: 150, y: 150),
                minimumScale: 0.1
            )
        )
        let resizedTextItem = try XCTUnwrap(
            resizedItems.first(where: { $0.id == textItem.id })?.textItem
        )
        let resizedImageItem = try XCTUnwrap(
            resizedItems.first(where: { $0.id == imageItem.id })?.imageItem
        )
        let expectedTextStyle = CanvasTextStyle(
            fontName: textStyle.fontName,
            fontSize: 30,
            color: textStyle.color
        )

        XCTAssertEqual(resizedTextItem.center, CGPoint(x: 37.5, y: 37.5))
        XCTAssertEqual(resizedTextItem.style, expectedTextStyle)
        XCTAssertEqual(
            resizedTextItem.size,
            CanvasTextLayoutMeasurer.intrinsicItemSize(
                for: textItem.text,
                style: expectedTextStyle
            )
        )
        XCTAssertEqual(resizedImageItem.center, CGPoint(x: 112.5, y: 112.5))
        XCTAssertEqual(resizedImageItem.size, CGSize(width: 60, height: 30))
    }

    func testResizedMemberItemsNormalizeHandDrawingBackToPaperAspectRatio() throws {
        let handDrawingID = CanvasItemID()
        let handDrawingItem = CanvasHandDrawingItem(
            id: handDrawingID,
            paper: .square,
            previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
                for: handDrawingID,
                cgImage: try makeSelectionTransformTestCGImage()
            ),
            isEmpty: true,
            center: CGPoint(x: 30, y: 20),
            size: CGSize(width: 60, height: 40),
            zIndex: 0,
            rotationRadians: 0
        )
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: handDrawingID,
            memberItems: [.handDrawing(handDrawingItem)],
            selectionBounds: CGRect(x: 0, y: 0, width: 60, height: 40)
        )

        let resizedItems = try XCTUnwrap(
            snapshot.resizedMemberItems(
                handleRole: .bottomTrailing,
                draggedWorldCorner: CGPoint(x: 120, y: 80),
                minimumScale: 0.1
            )
        )
        let resizedHandDrawingItem = try XCTUnwrap(
            resizedItems.first?.handDrawingItem
        )

        XCTAssertEqual(resizedHandDrawingItem.center, CGPoint(x: 60, y: 40))
        XCTAssertEqual(resizedHandDrawingItem.size, CGSize(width: 120, height: 120))
        XCTAssertEqual(
            resizedHandDrawingItem.size.width / resizedHandDrawingItem.size.height,
            1,
            accuracy: 0.0001
        )
    }

    func testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry() throws {
        let markdownStyle = CanvasTextStyle(fontSize: 20)
        let markdownItem = CanvasMarkdownItem(
            markdownSource: "## Title\n\nBody",
            style: markdownStyle,
            center: CGPoint(x: 40, y: 30),
            size: CGSize(width: 80, height: 60)
        )
        let snapshot = CanvasSelectionTransformSnapshot(
            primaryItemID: markdownItem.id,
            memberItems: [.markdown(markdownItem)],
            selectionBounds: CGRect(x: 0, y: 0, width: 80, height: 60)
        )

        let resizedItems = try XCTUnwrap(
            snapshot.resizedMemberItems(
                handleRole: .bottomTrailing,
                draggedWorldCorner: CGPoint(x: 160, y: 90),
                minimumScale: 0.1
            )
        )
        let resizedMarkdownItem = try XCTUnwrap(
            resizedItems.first?.markdownItem
        )

        XCTAssertEqual(resizedMarkdownItem.center, CGPoint(x: 80, y: 45))
        XCTAssertEqual(resizedMarkdownItem.size, CGSize(width: 160, height: 90))
        XCTAssertEqual(resizedMarkdownItem.style, markdownItem.style)
        XCTAssertEqual(
            resizedMarkdownItem.markdownSource,
            markdownItem.markdownSource
        )
    }
}

private func makeSelectionTransformTestImageItem(
    center: CGPoint,
    size: CGSize
) throws -> CanvasImageItem {
    CanvasImageItem(
        asset: .transientStaticImage(
            cgImage: try makeSelectionTransformTestCGImage()
        ),
        center: center,
        size: size
    )
}

private func makeSelectionTransformTestCGImage() throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 2 * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw CanvasSelectionTransformTestImageError.failedToCreateBitmapContext
    }

    context.setFillColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage() else {
        throw CanvasSelectionTransformTestImageError.failedToCreateImage
    }
    return image
}

private enum CanvasSelectionTransformTestImageError: Error {
    case failedToCreateBitmapContext
    case failedToCreateImage
}
