import Foundation
import XCTest

final class CanvasPlatformImportSourceContractTests: XCTestCase {
    func testIOSPhotoPickerDropAndPasteRemainAutomaticMediaEntries() throws {
        let adapterSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift"
        )
        assertPlatformImportSource(
            adapterSource,
            contains: [
                "from results: [PHPickerResult]",
                "from pasteboard: UIPasteboard",
                "from dropSession: UIDropSession",
                "for itemProvider in itemProviders",
                "resolvedItems.append(resolvedItem)",
                "preferredVideoTypeIdentifier(from: itemProvider)",
                "return .video(resolvedVideo)",
                "CanvasResolvedImportImage(",
                "return .image(resolvedImage)"
            ]
        )
        XCTAssertEqual(
            platformImportOccurrenceCount(
                of: "layout: CanvasImportLayout = .automatic",
                in: adapterSource
            ),
            3
        )
        XCTAssertFalse(adapterSource.contains(".diagonal("))
        XCTAssertFalse(adapterSource.contains("layout:.grid("))

        let pasteResolverSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/iOS/iOSCanvasPasteboardPayloadResolver.swift"
        )
        assertPlatformImportSource(
            pasteResolverSource,
            contains: [
                "layout: CanvasImportLayout = .automatic",
                "iOSCanvasImportAdapter.transferRequest",
                "return .media(transferRequest)"
            ]
        )

        let controllerSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"
        )
        assertPlatformImportSource(
            controllerSource,
            contains: [
                "configuration.filter = .any(of: [.images, .videos])",
                "configuration.selectionLimit = 0",
                "iOSCanvasImportAdapter.transferRequest",
                "sourceDescription: \"photo picker\"",
                "sourceDescription: \"drag and drop\"",
                "iOSCanvasPasteboardPayloadResolver.resolvedPayload",
                "sourceDescription: \"pasteboard\"",
                "performTransferRequest(transferRequest)",
                "CanvasTransferCommandLowerer.loweredCommand",
                "CanvasMediaImportService.makeImportRequest"
            ]
        )
    }

    func testMacOSOpenPanelDropAndPasteRemainAutomaticMediaEntries() throws {
        let adapterSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift"
        )
        assertPlatformImportSource(
            adapterSource,
            contains: [
                "from urls: [URL]",
                "from pasteboard: NSPasteboard",
                "items: items",
                "placement: placement",
                "layout: layout"
            ]
        )
        XCTAssertEqual(
            platformImportOccurrenceCount(
                of: "layout: CanvasImportLayout = .automatic",
                in: adapterSource
            ),
            2
        )
        XCTAssertFalse(adapterSource.contains(".diagonal("))
        XCTAssertFalse(adapterSource.contains("layout:.grid("))

        let pasteResolverSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/macOS/macOSCanvasPasteboardPayloadResolver.swift"
        )
        assertPlatformImportSource(
            pasteResolverSource,
            contains: [
                "layout: CanvasImportLayout = .automatic",
                "macOSCanvasImportAdapter.transferRequest",
                "return .media(transferRequest)"
            ]
        )

        let controllerSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
        )
        assertPlatformImportSource(
            controllerSource,
            contains: [
                "openPanel.allowedContentTypes = [.image, .movie]",
                "openPanel.allowsMultipleSelection = true",
                "macOSCanvasImportAdapter.transferRequest",
                "sourceDescription: \"open panel\"",
                "sourceDescription: \"drag and drop\"",
                "macOSCanvasPasteboardPayloadResolver.resolvedPayload",
                "sourceDescription: \"pasteboard\"",
                "performTransferRequest(transferRequest)",
                "CanvasTransferCommandLowerer.loweredCommand",
                "CanvasMediaImportService.makeImportRequest"
            ]
        )
    }

    func testShareExtensionUsesAutomaticSharedImportPipeline() throws {
        let shareSource = try normalizedPlatformImportSource(
            at: "Add To Canvas/ShareImportViewModel.swift"
        )
        assertPlatformImportSourceInOrder(
            shareSource,
            markers: [
                "let transferRequest = CanvasTransferRequest(",
                "images: resolvedImages",
                "placement: .cameraCenter",
                "layout: .automatic",
                "CanvasMediaImportService.makeImportRequest(",
                "from: transferRequest",
                "session.appendImportedMedia(",
                "importRequest.items",
                "placement: importRequest.placement",
                "layout: importRequest.layout"
            ]
        )
        XCTAssertFalse(shareSource.contains(".diagonal("))
        XCTAssertFalse(shareSource.contains("layout:.grid("))
    }

    func testGIFFramesKeepExplicitGridSeparateFromOrdinaryImports() throws {
        let gifBuilderSource = try normalizedPlatformImportSource(
            at: "MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift"
        )
        assertPlatformImportSource(
            gifBuilderSource,
            contains: [
                "placement: .worldPoint(",
                "gridCenter(",
                "layout: .grid(",
                "CanvasImportLayoutSolver().resolve(",
                "requestedLayout: .grid("
            ]
        )

        let ordinarySources = try [
            normalizedPlatformImportSource(
                at: "MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift"
            ),
            normalizedPlatformImportSource(
                at: "MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift"
            ),
            normalizedPlatformImportSource(
                at: "Add To Canvas/ShareImportViewModel.swift"
            )
        ]
        for source in ordinarySources {
            XCTAssertFalse(source.contains("layout:.grid("))
        }
    }
}

private func normalizedPlatformImportSource(
    at relativePath: String
) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repositoryRootURL = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRootURL.appendingPathComponent(relativePath)
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    return normalizedPlatformImportFragment(source)
}

private func normalizedPlatformImportFragment(
    _ source: String
) -> String {
    source.replacingOccurrences(
        of: #"\s+"#,
        with: "",
        options: .regularExpression
    )
}

private func platformImportOccurrenceCount(
    of marker: String,
    in source: String
) -> Int {
    let normalizedMarker = normalizedPlatformImportFragment(marker)
    guard normalizedMarker.isEmpty == false else {
        return 0
    }

    return source.components(separatedBy: normalizedMarker).count - 1
}

private func assertPlatformImportSource(
    _ source: String,
    contains markers: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for marker in markers {
        let normalizedMarker = normalizedPlatformImportFragment(marker)
        XCTAssertTrue(
            source.contains(normalizedMarker),
            "Missing platform import source contract: \(marker)",
            file: file,
            line: line
        )
    }
}

private func assertPlatformImportSourceInOrder(
    _ source: String,
    markers: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var searchStartIndex = source.startIndex
    for marker in markers {
        let normalizedMarker = normalizedPlatformImportFragment(marker)
        guard
            let range = source.range(
                of: normalizedMarker,
                range: searchStartIndex..<source.endIndex
            )
        else {
            XCTFail(
                "Missing or out-of-order platform import source contract: \(marker)",
                file: file,
                line: line
            )
            return
        }
        searchStartIndex = range.upperBound
    }
}
