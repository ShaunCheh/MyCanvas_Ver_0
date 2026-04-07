import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasImportRequestModelTests: XCTestCase {
    func testGridLayoutExposesSanitizedGridConfiguration() throws {
        let layout = CanvasImportLayout.grid(
            columns: 0,
            horizontalSpacing: -12,
            verticalSpacing: -24
        )

        let gridConfiguration = try XCTUnwrap(layout.gridConfiguration)
        XCTAssertEqual(gridConfiguration.columns, 1)
        XCTAssertEqual(gridConfiguration.horizontalSpacing, 0)
        XCTAssertEqual(gridConfiguration.verticalSpacing, 0)
    }

    func testPresentationTemplateSanitizesSizeAndResolvesRotationPolicy() {
        let cropRect = CanvasImageCropRect(
            CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        )
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: -40, height: CGFloat.nan),
            cropRectNormalized: cropRect,
            rotationPolicy: .fixed(.pi / 4)
        )
        let assetDefaultTemplate = CanvasImportPresentationTemplate(
            size: CGSize(width: 320, height: 180),
            rotationPolicy: .useAssetDefault
        )

        XCTAssertEqual(template.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(template.cropRectNormalized, cropRect)
        XCTAssertEqual(
            template.resolvedRotationRadians(assetDefaultRadians: 0),
            .pi / 4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            assetDefaultTemplate.resolvedRotationRadians(
                assetDefaultRadians: 0.35
            ),
            0.35,
            accuracy: 0.0001
        )
    }

    func testImportRequestStoresPresentationTemplateAndGridLayout() throws {
        let image = CanvasResolvedImportImage(
            cgImage: try makeSolidColorImage()
        )
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: 320, height: 180),
            cropRectNormalized: CanvasImageCropRect(
                CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)
            ),
            rotationPolicy: .fixed(0)
        )
        let request = CanvasImportRequest(
            images: [image],
            placement: .worldPoint(CGPoint(x: 120, y: 240)),
            layout: .grid(
                columns: 4,
                horizontalSpacing: 24,
                verticalSpacing: 32
            ),
            presentationTemplate: template,
            sourceDescription: "gif-derived frames"
        )

        XCTAssertEqual(request.itemCount, 1)
        XCTAssertEqual(request.presentationTemplate, template)
        XCTAssertEqual(request.sourceDescription, "gif-derived frames")

        let gridConfiguration = try XCTUnwrap(request.layout.gridConfiguration)
        XCTAssertEqual(gridConfiguration.columns, 4)
        XCTAssertEqual(gridConfiguration.horizontalSpacing, 24)
        XCTAssertEqual(gridConfiguration.verticalSpacing, 32)
    }
}

private enum CanvasImportRequestModelTestError: Error {
    case invalidBitmapContext
}

private func makeSolidColorImage() throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasImportRequestModelTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    )
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))

    guard let image = context.makeImage() else {
        throw CanvasImportRequestModelTestError.invalidBitmapContext
    }
    return image
}
