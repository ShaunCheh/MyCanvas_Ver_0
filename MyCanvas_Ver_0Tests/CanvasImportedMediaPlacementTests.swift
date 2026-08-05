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

    func testAutomaticGridCountsRemainCenteredAndNonOverlappingAcrossZoomLevels() throws {
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 60
        )
        let itemCounts = [1, 2, 4, 5, 8, 9]
        let zoomScales: [CGFloat] = [0.5, 1, 2.5]
        let importCenter = CGPoint(x: 135, y: -215)
        let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid
        var baselineCentersByItemCount: [Int: [CGPoint]] = [:]

        for zoomScale in zoomScales {
            for itemCount in itemCounts {
                let session = makeImportPlacementTestSession()
                session.camera = CanvasCamera(
                    center: importCenter,
                    zoomScale: zoomScale,
                    viewportSize: CGSize(width: 1200, height: 800)
                )

                let importedItems = session.appendImportedMedia(
                    Array(repeating: .image(image), count: itemCount)
                )

                XCTAssertEqual(importedItems.count, itemCount)
                let cellWidth = importedItems.map(\.size.width).max() ?? 0
                let cellHeight = importedItems.map(\.size.height).max() ?? 0
                let horizontalPitch =
                    cellWidth + gridConfiguration.horizontalSpacing
                let verticalPitch =
                    cellHeight + gridConfiguration.verticalSpacing
                let usedColumnCount = min(
                    gridConfiguration.columns,
                    itemCount
                )
                let rowCount =
                    ((itemCount - 1) / gridConfiguration.columns) + 1
                let expectedFirstCenter = CGPoint(
                    x: importCenter.x
                        - CGFloat(usedColumnCount - 1) * horizontalPitch / 2,
                    y: importCenter.y
                        - CGFloat(rowCount - 1) * verticalPitch / 2
                )

                for (index, importedItem) in importedItems.enumerated() {
                    XCTAssertEqual(
                        importedItem.center,
                        CGPoint(
                            x: expectedFirstCenter.x
                                + CGFloat(index % gridConfiguration.columns)
                                * horizontalPitch,
                            y: expectedFirstCenter.y
                                + CGFloat(index / gridConfiguration.columns)
                                * verticalPitch
                        )
                    )
                }
                assertImportPlacementItemsDoNotOverlap(importedItems)

                let centers = importedItems.map(\.center)
                if let baselineCenters = baselineCentersByItemCount[itemCount] {
                    XCTAssertEqual(centers, baselineCenters)
                } else {
                    baselineCentersByItemCount[itemCount] = centers
                }
            }
        }
    }

    func testExplicitDiagonalUsingDuplicateOffsetKeepsTwentyFourPointViewportStep() throws {
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 60
        )

        for zoomScale: CGFloat in [0.5, 1, 2.5, 4] {
            let session = makeImportPlacementTestSession()
            session.camera = CanvasCamera(
                center: CGPoint(x: 40, y: -60),
                zoomScale: zoomScale,
                viewportSize: CGSize(width: 1000, height: 700)
            )
            let diagonalStep = session.duplicateOffsetInWorld()

            let importedItems = session.appendImportedMedia(
                Array(repeating: .image(image), count: 3),
                layout: .diagonal(stepInWorld: diagonalStep)
            )
            let viewportCenters = importedItems.map {
                session.camera.worldToViewport($0.center)
            }

            XCTAssertEqual(importedItems.count, 3)
            XCTAssertEqual(
                viewportCenters[1].x - viewportCenters[0].x,
                24,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                viewportCenters[1].y - viewportCenters[0].y,
                24,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                viewportCenters[2].x - viewportCenters[1].x,
                24,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                viewportCenters[2].y - viewportCenters[1].y,
                24,
                accuracy: 0.0001
            )
        }
    }

    func testAppendImportedMediaAutomaticSingleItemUsesCameraCenter() throws {
        let session = makeImportPlacementTestSession()
        let cameraCenter = CGPoint(x: -240, y: 360)
        session.camera = CanvasCamera(
            center: cameraCenter,
            zoomScale: 2,
            viewportSize: CGSize(width: 900, height: 700)
        )
        let image = try makeImportPlacementTestResolvedImage(
            width: 120,
            height: 80
        )

        let importedItems = session.appendImportedMedia([.image(image)])

        XCTAssertEqual(importedItems.count, 1)
        XCTAssertEqual(importedItems[0].center, cameraCenter)
    }

    func testAppendImportedMediaAutomaticVideoBatchUsesCameraCenteredGrid() throws {
        let session = makeImportPlacementTestSession()
        let importCenter = CGPoint(x: 320, y: -180)
        session.camera = CanvasCamera(
            center: importCenter,
            zoomScale: 1.5,
            viewportSize: CGSize(width: 1200, height: 800)
        )
        let videos = try (0..<5).map { index in
            try makeImportPlacementTestVideo(
                width: 160,
                height: 90,
                filename: "video-\(index).mov",
                posterTimeSeconds: Double(index) + 0.25
            )
        }

        let importedItems = session.appendImportedMedia(
            videos.map(CanvasImportItem.video)
        )

        XCTAssertEqual(importedItems.count, videos.count)
        XCTAssertTrue(importedItems.allSatisfy(\.isVideo))
        XCTAssertEqual(
            importedItems.compactMap(\.sourceVideoFilename),
            videos.map(\.videoSource.sourceVideoFilename)
        )
        XCTAssertEqual(
            importedItems.compactMap(\.posterTimeSeconds),
            videos.map(\.posterTimeSeconds)
        )

        let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid
        let horizontalPitch =
            importedItems[0].size.width
            + gridConfiguration.horizontalSpacing
        let verticalPitch =
            importedItems[0].size.height
            + gridConfiguration.verticalSpacing
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

    func testAppendImportedMediaAutomaticMixedBatchPreservesOrderAndZIndexes() throws {
        let session = makeImportPlacementTestSession()
        let portraitImage = try makeImportPlacementTestResolvedImage(
            width: 60,
            height: 120
        )
        let squareImage = try makeImportPlacementTestResolvedImage(
            width: 100,
            height: 100
        )
        let firstVideo = try makeImportPlacementTestVideo(
            width: 160,
            height: 90,
            filename: "mixed-first.mov",
            posterTimeSeconds: 1.25
        )
        let secondVideo = try makeImportPlacementTestVideo(
            width: 90,
            height: 160,
            filename: "mixed-second.mov",
            posterTimeSeconds: 2.5
        )
        let importItems: [CanvasImportItem] = [
            .image(portraitImage),
            .video(firstVideo),
            .image(squareImage),
            .video(secondVideo),
            .image(portraitImage)
        ]
        let importCenter = CGPoint(x: 75, y: 125)

        let importedItems = session.appendImportedMedia(
            importItems,
            placement: .worldPoint(importCenter)
        )

        XCTAssertEqual(
            importedItems.map(\.isVideo),
            [false, true, false, true, false]
        )
        XCTAssertEqual(
            importedItems.compactMap(\.sourceVideoFilename),
            ["mixed-first.mov", "mixed-second.mov"]
        )
        XCTAssertEqual(
            importedItems.map(\.zIndex),
            [0, 1, 2, 3, 4]
        )
        XCTAssertEqual(
            session.scene.orderedItems().map(\.id),
            importedItems.map(\.id)
        )

        let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid
        let cellWidth = importedItems.map(\.size.width).max() ?? 0
        let cellHeight = importedItems.map(\.size.height).max() ?? 0
        let horizontalPitch = cellWidth + gridConfiguration.horizontalSpacing
        let verticalPitch = cellHeight + gridConfiguration.verticalSpacing
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
        assertImportPlacementItemsDoNotOverlap(importedItems)
    }

    func testAppendImportedMediaGridUsesRotatedBoundingSizeWithoutOverlap() throws {
        let session = makeImportPlacementTestSession()
        let image = try makeImportPlacementTestResolvedImage(
            width: 220,
            height: 100
        )
        let rotationRadians = CGFloat.pi / 4
        let spacing: CGFloat = 18
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: 220, height: 100),
            rotationPolicy: .fixed(rotationRadians)
        )

        let importedItems = session.appendImportedMedia(
            [.image(image), .image(image)],
            placement: .worldPoint(.zero),
            layout: .grid(
                columns: 2,
                horizontalSpacing: spacing,
                verticalSpacing: 0
            ),
            presentationTemplate: template
        )

        XCTAssertEqual(importedItems.count, 2)
        let expectedBoundingWidth =
            template.size.width * abs(cos(rotationRadians))
            + template.size.height * abs(sin(rotationRadians))
        XCTAssertEqual(
            importedItems[1].center.x - importedItems[0].center.x,
            expectedBoundingWidth + spacing,
            accuracy: 0.0001
        )
        assertImportPlacementItemsDoNotOverlap(importedItems)
    }

    func testAppendImportedMediaExpandsBoardToContainEntireGrid() throws {
        let session = makeImportPlacementTestSession()
        let initialBoardState = CanvasBoardState(
            baseSize: CGSize(width: 100, height: 100),
            centeredAt: .zero
        )
        session.boardState = initialBoardState
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 80
        )

        let importedItems = session.appendImportedMedia(
            Array(repeating: .image(image), count: 5),
            placement: .worldPoint(CGPoint(x: 500, y: -400))
        )

        let expandedBoardState = try XCTUnwrap(session.boardState)
        XCTAssertGreaterThan(
            expandedBoardState.worldRect.width,
            initialBoardState.worldRect.width
        )
        XCTAssertGreaterThan(
            expandedBoardState.worldRect.height,
            initialBoardState.worldRect.height
        )
        for item in importedItems {
            XCTAssertTrue(
                expandedBoardState.worldRect.contains(item.worldBounds)
            )
        }
    }

    func testAppendImportedMediaBatchUsesSingleUndoAndRedoHistoryStep() throws {
        let session = makeImportPlacementTestSession()
        session.resetHistory()
        let image = try makeImportPlacementTestResolvedImage(
            width: 80,
            height: 80
        )

        let importedItems = session.appendImportedMedia(
            Array(repeating: .image(image), count: 5),
            placement: .worldPoint(CGPoint(x: 100, y: 200))
        )
        let importedItemIDs = importedItems.map(\.id)
        XCTAssertEqual(session.scene.orderedItems().count, 5)

        let undoSnapshot = try XCTUnwrap(session.undoHistorySnapshot())
        session.applyBoardHistorySnapshot(undoSnapshot)
        XCTAssertTrue(session.scene.orderedItems().isEmpty)
        XCTAssertNil(session.undoHistorySnapshot())

        let redoSnapshot = try XCTUnwrap(session.redoHistorySnapshot())
        session.applyBoardHistorySnapshot(redoSnapshot)
        XCTAssertEqual(
            session.scene.orderedItems().map(\.id),
            importedItemIDs
        )
        XCTAssertNil(session.redoHistorySnapshot())
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

private func makeImportPlacementTestVideo(
    width: Int,
    height: Int,
    filename: String,
    posterTimeSeconds: Double
) throws -> CanvasImportedVideoAsset {
    let posterImage = try makeImportPlacementTestImage(
        width: width,
        height: height
    )
    return CanvasImportedVideoAsset(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: posterImage
        ),
        videoSource: CanvasVideoSource(
            assetReference: .persisted(filename: filename)
        ),
        posterTimeSeconds: posterTimeSeconds
    )
}

private func assertImportPlacementItemsDoNotOverlap(
    _ items: [CanvasImageItem],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for firstIndex in items.indices {
        for secondIndex in items.indices where secondIndex > firstIndex {
            XCTAssertFalse(
                items[firstIndex].worldBounds.intersects(
                    items[secondIndex].worldBounds
                ),
                "Items \(firstIndex) and \(secondIndex) overlap.",
                file: file,
                line: line
            )
        }
    }
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
