import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasTransferImportPipelineTests: XCTestCase {
    func testOrdinaryImageTransferDefaultsRemainAutomaticThroughSession() throws {
        let image = try makeTransferPipelineTestImage(
            width: 80,
            height: 80
        )
        let cameraCenter = CGPoint(x: 140, y: -220)

        for itemCount in [1, 5] {
            let sourceDescription = "ordinary platform batch \(itemCount)"
            let transferRequest = CanvasTransferRequest(
                images: Array(repeating: image, count: itemCount),
                sourceDescription: sourceDescription
            )

            XCTAssertEqual(transferRequest.placement, .cameraCenter)
            XCTAssertEqual(transferRequest.layout, .automatic)

            let importRequest = try XCTUnwrap(
                CanvasMediaImportService.makeImportRequest(
                    from: transferRequest
                )
            )
            XCTAssertEqual(importRequest.items.count, itemCount)
            XCTAssertEqual(importRequest.placement, .cameraCenter)
            XCTAssertEqual(importRequest.layout, .automatic)
            XCTAssertEqual(
                importRequest.sourceDescription,
                sourceDescription
            )

            let command = try XCTUnwrap(
                CanvasTransferCommandLowerer.loweredCommand(
                    for: importRequest
                )
            )
            guard case let .importMedia(loweredRequest) = command else {
                return XCTFail("Expected importMedia command.")
            }
            XCTAssertEqual(loweredRequest.items.count, itemCount)
            XCTAssertEqual(loweredRequest.placement, .cameraCenter)
            XCTAssertEqual(loweredRequest.layout, .automatic)
            XCTAssertEqual(
                loweredRequest.sourceDescription,
                sourceDescription
            )

            let session = makeTransferPipelineTestSession()
            session.camera = CanvasCamera(
                center: cameraCenter,
                zoomScale: 2,
                viewportSize: CGSize(width: 1000, height: 700)
            )
            let executor = CanvasCommandExecutor(session: session)
            CanvasTransferImportPipelineTestRetainer.executors.append(executor)

            XCTAssertNotNil(executor.execute(command))
            let importedItems = session.scene.orderedItems()
            XCTAssertEqual(importedItems.count, itemCount)
            XCTAssertTrue(importedItems.allSatisfy { $0.isVideo == false })

            if itemCount == 1 {
                XCTAssertEqual(importedItems[0].center, cameraCenter)
            } else {
                assertTransferPipelineFourColumnGrid(
                    importedItems,
                    centeredAt: cameraCenter
                )
            }
        }
    }

    func testProgrammaticDiagonalSurvivesTransferServiceAndCommandLane() throws {
        let image = try makeTransferPipelineTestImage(
            width: 120,
            height: 60
        )
        let placement = CGPoint(x: 45, y: 75)
        let step = CGPoint(x: -14, y: 22)
        let transferRequest = CanvasTransferRequest(
            images: Array(repeating: image, count: 3),
            placement: .worldPoint(placement),
            layout: .diagonal(stepInWorld: step),
            sourceDescription: "programmatic diagonal regression"
        )

        let importRequest = try XCTUnwrap(
            CanvasMediaImportService.makeImportRequest(
                from: transferRequest
            )
        )
        XCTAssertEqual(
            importRequest.layout,
            .diagonal(stepInWorld: step)
        )
        XCTAssertEqual(
            importRequest.placement,
            .worldPoint(placement)
        )

        let command = try XCTUnwrap(
            CanvasTransferCommandLowerer.loweredCommand(
                for: importRequest
            )
        )
        guard case let .importMedia(loweredRequest) = command else {
            return XCTFail("Expected importMedia command.")
        }
        XCTAssertEqual(
            loweredRequest.layout,
            .diagonal(stepInWorld: step)
        )
        XCTAssertEqual(
            loweredRequest.placement,
            .worldPoint(placement)
        )

        let session = makeTransferPipelineTestSession()
        let executor = CanvasCommandExecutor(session: session)
        CanvasTransferImportPipelineTestRetainer.executors.append(executor)
        XCTAssertNotNil(executor.execute(command))

        let importedItems = session.scene.orderedItems()
        XCTAssertEqual(importedItems.count, 3)
        XCTAssertEqual(importedItems[0].center, placement)
        XCTAssertEqual(
            importedItems[1].center,
            CGPoint(
                x: placement.x + step.x,
                y: placement.y + step.y
            )
        )
        XCTAssertEqual(
            importedItems[2].center,
            CGPoint(
                x: placement.x + 2 * step.x,
                y: placement.y + 2 * step.y
            )
        )
    }
}

private enum CanvasTransferImportPipelineTestError: Error {
    case invalidBitmapContext
}

private enum CanvasTransferImportPipelineTestRetainer {
    static var sessions: [CanvasEditorSession] = []
    static var executors: [CanvasCommandExecutor] = []
}

@MainActor
private func makeTransferPipelineTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasTransferImportPipelineTests",
        logPrefix: "[CanvasTransferImportPipelineTests]"
    )
    CanvasTransferImportPipelineTestRetainer.sessions.append(session)
    return session
}

private func makeTransferPipelineTestImage(
    width: Int,
    height: Int
) throws -> CanvasResolvedImportImage {
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
        throw CanvasTransferImportPipelineTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
    )
    guard let cgImage = context.makeImage() else {
        throw CanvasTransferImportPipelineTestError.invalidBitmapContext
    }

    return CanvasResolvedImportImage(cgImage: cgImage)
}

@MainActor
private func assertTransferPipelineFourColumnGrid(
    _ items: [CanvasImageItem],
    centeredAt expectedCenter: CGPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(items.count, 5, file: file, line: line)

    let configuration = CanvasBatchImportLayoutConfiguration.current.grid
    let cellWidth = items.map(\.size.width).max() ?? 0
    let cellHeight = items.map(\.size.height).max() ?? 0
    let horizontalPitch = cellWidth + configuration.horizontalSpacing
    let verticalPitch = cellHeight + configuration.verticalSpacing

    XCTAssertEqual(
        items[3].center,
        CGPoint(
            x: items[0].center.x + 3 * horizontalPitch,
            y: items[0].center.y
        ),
        file: file,
        line: line
    )
    XCTAssertEqual(
        items[4].center,
        CGPoint(
            x: items[0].center.x,
            y: items[0].center.y + verticalPitch
        ),
        file: file,
        line: line
    )
    XCTAssertEqual(
        (items[0].center.x + items[3].center.x) / 2,
        expectedCenter.x,
        file: file,
        line: line
    )
    XCTAssertEqual(
        (items[0].center.y + items[4].center.y) / 2,
        expectedCenter.y,
        file: file,
        line: line
    )
}
