import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasImportedMediaPlacementTests: XCTestCase {
    func testAppendImportedMediaAppliesPresentationTemplateGeometry() throws {
        let session = makeImportPlacementTestSession()
        let image = try makeImportPlacementTestResolvedImage(
            width: 120,
            height: 60
        )
        let cropRect = CanvasImageCropRect(
            CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        )
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: 210, height: 130),
            cropRectNormalized: cropRect,
            rotationPolicy: .fixed(0.45)
        )

        let importedItems = session.appendImportedMedia(
            [.image(image)],
            placement: .worldPoint(CGPoint(x: 40, y: 90)),
            layout: .stacked,
            presentationTemplate: template
        )

        let importedItem = try XCTUnwrap(importedItems.first)
        XCTAssertEqual(importedItems.count, 1)
        XCTAssertEqual(importedItem.center, CGPoint(x: 40, y: 90))
        XCTAssertEqual(importedItem.size, template.size)
        XCTAssertEqual(importedItem.cropRectNormalized, cropRect)
        XCTAssertEqual(importedItem.rotationRadians, 0.45, accuracy: 0.0001)
    }

    func testAppendImportedMediaGridUsesMaxResolvedItemSizeForCellSpacing() throws {
        let session = makeImportPlacementTestSession()
        let portraitImage = try makeImportPlacementTestResolvedImage(
            width: 50,
            height: 100
        )
        let landscapeImage = try makeImportPlacementTestResolvedImage(
            width: 100,
            height: 50
        )

        let importedItems = session.appendImportedMedia(
            [
                .image(portraitImage),
                .image(landscapeImage),
                .image(portraitImage)
            ],
            placement: .worldPoint(CGPoint(x: 10, y: 20)),
            layout: .grid(
                columns: 2,
                horizontalSpacing: 24,
                verticalSpacing: 16
            )
        )

        XCTAssertEqual(importedItems.count, 3)

        let expectedCellWidth = importedItems.map(\.size.width).max() ?? 0
        let expectedCellHeight = importedItems.map(\.size.height).max() ?? 0

        XCTAssertEqual(importedItems[0].center, CGPoint(x: 10, y: 20))
        XCTAssertEqual(
            importedItems[1].center,
            CGPoint(x: 10 + expectedCellWidth + 24, y: 20)
        )
        XCTAssertEqual(
            importedItems[2].center,
            CGPoint(x: 10, y: 20 + expectedCellHeight + 16)
        )
    }

    func testCommandExecutorForwardsPresentationTemplateFromImportRequest() throws {
        let session = makeImportPlacementTestSession()
        let executor = CanvasCommandExecutor(session: session)
        CanvasImportedMediaPlacementTestRetainer.executors.append(executor)
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 80
        )
        let cropRect = CanvasImageCropRect(
            CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.7)
        )
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: 180, height: 120),
            cropRectNormalized: cropRect,
            rotationPolicy: .fixed(0.3)
        )
        let request = CanvasImportRequest(
            images: [image],
            placement: .worldPoint(CGPoint(x: 12, y: 34)),
            layout: .stacked,
            presentationTemplate: template,
            sourceDescription: "placement test"
        )

        let result = executor.execute(.importMedia(request))

        XCTAssertNotNil(result)
        let importedItem = try XCTUnwrap(session.scene.orderedItems().first)
        XCTAssertEqual(importedItem.center, CGPoint(x: 12, y: 34))
        XCTAssertEqual(importedItem.size, template.size)
        XCTAssertEqual(importedItem.cropRectNormalized, cropRect)
        XCTAssertEqual(importedItem.rotationRadians, 0.3, accuracy: 0.0001)
    }
}

private enum CanvasImportedMediaPlacementTestError: Error {
    case invalidBitmapContext
}

private enum CanvasImportedMediaPlacementTestRetainer {
    static var sessions: [CanvasEditorSession] = []
    static var executors: [CanvasCommandExecutor] = []
}

private func makeImportPlacementTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasImportedMediaPlacementTests",
        logPrefix: "[CanvasImportedMediaPlacementTests]"
    )
    CanvasImportedMediaPlacementTestRetainer.sessions.append(session)
    return session
}

private func makeImportPlacementTestImage(
    width: Int,
    height: Int
) throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasImportedMediaPlacementTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.4, green: 0.7, blue: 0.2, alpha: 1)
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
    )

    guard let image = context.makeImage() else {
        throw CanvasImportedMediaPlacementTestError.invalidBitmapContext
    }
    return image
}

private func makeImportPlacementTestResolvedImage(
    width: Int,
    height: Int
) throws -> CanvasResolvedImportImage {
    let pngData = try makeImportPlacementTestPNGData(
        width: width,
        height: height
    )
    guard let image = CanvasResolvedImportImage(
        data: pngData,
        typeIdentifier: UTType.png.identifier,
        filenameHint: "placement-test.png"
    ) else {
        throw CanvasImportedMediaPlacementTestError.invalidBitmapContext
    }
    return image
}

private func makeImportPlacementTestPNGData(
    width: Int,
    height: Int
) throws -> Data {
    let image = try makeImportPlacementTestImage(
        width: width,
        height: height
    )
    let data = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CanvasImportedMediaPlacementTestError.invalidBitmapContext
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CanvasImportedMediaPlacementTestError.invalidBitmapContext
    }
    return data as Data
}
