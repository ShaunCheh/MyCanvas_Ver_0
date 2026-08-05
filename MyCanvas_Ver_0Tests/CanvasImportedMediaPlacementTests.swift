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

    func testAppendImportedMediaGridCentersUsingMaxResolvedItemSizeForCellSpacing() throws {
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
        let expectedHorizontalPitch = expectedCellWidth + 24
        let expectedVerticalPitch = expectedCellHeight + 16
        let expectedFirstCenter = CGPoint(
            x: 10 - expectedHorizontalPitch / 2,
            y: 20 - expectedVerticalPitch / 2
        )

        XCTAssertEqual(importedItems[0].center, expectedFirstCenter)
        XCTAssertEqual(
            importedItems[1].center,
            CGPoint(
                x: expectedFirstCenter.x + expectedHorizontalPitch,
                y: expectedFirstCenter.y
            )
        )
        XCTAssertEqual(
            importedItems[2].center,
            CGPoint(
                x: expectedFirstCenter.x,
                y: expectedFirstCenter.y + expectedVerticalPitch
            )
        )
    }

    func testAppendImportedMediaAutomaticUsesConfiguredFourColumnGrid() throws {
        let session = makeImportPlacementTestSession()
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 80
        )
        let importCenter = CGPoint(x: 100, y: 200)

        let importedItems = session.appendImportedMedia(
            Array(repeating: .image(image), count: 5),
            placement: .worldPoint(importCenter)
        )

        XCTAssertEqual(importedItems.count, 5)

        let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid
        let horizontalPitch =
            importedItems[0].size.width
            + gridConfiguration.horizontalSpacing
        let verticalPitch =
            importedItems[0].size.height
            + gridConfiguration.verticalSpacing

        XCTAssertEqual(
            importedItems[1].center,
            CGPoint(
                x: importedItems[0].center.x + horizontalPitch,
                y: importedItems[0].center.y
            )
        )
        XCTAssertEqual(
            importedItems[3].center,
            CGPoint(
                x: importedItems[0].center.x + 3 * horizontalPitch,
                y: importedItems[0].center.y
            )
        )
        XCTAssertEqual(
            importedItems[4].center,
            CGPoint(
                x: importedItems[0].center.x,
                y: importedItems[0].center.y + verticalPitch
            )
        )
        XCTAssertEqual(
            (importedItems[0].center.x + importedItems[3].center.x) / 2,
            importCenter.x
        )
        XCTAssertEqual(
            (importedItems[0].center.y + importedItems[4].center.y) / 2,
            importCenter.y
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
