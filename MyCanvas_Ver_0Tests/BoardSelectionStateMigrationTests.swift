import CoreGraphics
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class BoardSelectionStateMigrationTests: XCTestCase {
    func testCanvasInteractionStateAppendsMissingPrimarySelection() {
        let firstItemID = UUID()
        let secondItemID = UUID()

        let interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItemID],
            primarySelectedItemID: secondItemID
        )

        XCTAssertEqual(
            interactionState.selectedItemIDs,
            [firstItemID, secondItemID]
        )
        XCTAssertEqual(
            interactionState.primarySelectedItemID,
            secondItemID
        )
        XCTAssertNil(interactionState.singleSelectedItemID)
    }

    func testBoardDocumentDecodesLegacySelectedItemIDIntoSelectionSet() throws {
        let legacySelectedItemID = UUID()
        let document = makeBoardDocument(
            selectedItemIDs: [],
            primarySelectedItemID: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedDocument = try encoder.encode(document)
        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDocument) as? [String: Any]
        )
        legacyPayload["formatVersion"] = 4
        legacyPayload["selectedItemID"] = legacySelectedItemID.uuidString
        legacyPayload.removeValue(forKey: "selectedItemIDs")
        legacyPayload.removeValue(forKey: "primarySelectedItemID")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyDocument = try decoder.decode(
            BoardDocument.self,
            from: JSONSerialization.data(withJSONObject: legacyPayload)
        )

        XCTAssertEqual(legacyDocument.selectedItemIDs, [legacySelectedItemID])
        XCTAssertEqual(
            legacyDocument.primarySelectedItemID,
            legacySelectedItemID
        )
        XCTAssertEqual(legacyDocument.selectedItemID, legacySelectedItemID)
    }

    func testBoardDocumentMapperRoundTripsMultiSelectionViewState() throws {
        let firstItem = CanvasTextItem(
            text: "First",
            center: CGPoint(x: 40, y: 20),
            size: CGSize(width: 120, height: 44),
            zIndex: 0
        )
        let secondItem = CanvasTextItem(
            text: "Second",
            center: CGPoint(x: 180, y: 80),
            size: CGSize(width: 120, height: 44),
            zIndex: 1
        )
        let runtimeState = BoardRuntimeState(
            boardID: UUID(),
            title: "Selection Mapper",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            items: [.text(firstItem), .text(secondItem)],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState(
                selectedItemIDs: [firstItem.id, secondItem.id],
                primarySelectedItemID: secondItem.id
            ),
            workspaceMode: .editing
        )

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        XCTAssertEqual(document.selectedItemIDs, [firstItem.id, secondItem.id])
        XCTAssertEqual(document.primarySelectedItemID, secondItem.id)

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )

        XCTAssertEqual(
            roundTrippedState.interactionState.selectedItemIDs,
            [firstItem.id, secondItem.id]
        )
        XCTAssertEqual(
            roundTrippedState.interactionState.primarySelectedItemID,
            secondItem.id
        )
    }

    func testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad() throws {
        let legacyStyle = CanvasTextStyle(fontSize: 28)
        let legacyTextRecord = BoardTextItemRecord(
            id: UUID(),
            center: BoardPointRecord(CGPoint(x: 40, y: 30)),
            size: BoardSizeRecord(CGSize(width: 64, height: 24)),
            zIndex: 2,
            text: "Legacy text should expand",
            style: BoardTextStyleRecord(legacyStyle),
            rotationRadians: 0
        )
        let document = makeBoardDocument(
            selectedItemIDs: [legacyTextRecord.id],
            primarySelectedItemID: legacyTextRecord.id,
            boardBaseSize: CGSize(width: 64, height: 64),
            boardRect: CGRect(x: 0, y: 0, width: 64, height: 64),
            items: [.text(legacyTextRecord)]
        )

        let runtimeState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )
        let textItem = try XCTUnwrap(runtimeState.textItems.first)
        let boardState = try XCTUnwrap(runtimeState.boardState)
        let expectedSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: legacyTextRecord.text,
            style: legacyStyle
        )

        XCTAssertEqual(textItem.id, legacyTextRecord.id)
        XCTAssertEqual(textItem.style, legacyStyle)
        XCTAssertEqual(textItem.center, legacyTextRecord.center.cgPoint)
        XCTAssertEqual(textItem.size, expectedSize)
        XCTAssertNotEqual(textItem.size, legacyTextRecord.size.cgSize)
        XCTAssertTrue(boardState.worldRect.contains(textItem.worldBounds))
    }

    func testBoardDocumentMapperRoundTripsHandDrawingItem() throws {
        let itemID = UUID()
        let documentID = UUID()
        let contentRevision = UUID()
        let previewImage = try makeSolidColorPreviewImage(
            red: 0.1,
            green: 0.2,
            blue: 0.9
        )
        let item = CanvasHandDrawingItem(
            id: itemID,
            documentID: documentID,
            paper: .square,
            previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
                for: documentID,
                cgImage: previewImage
            ),
            isEmpty: false,
            contentRevision: contentRevision,
            center: CGPoint(x: 160, y: 90),
            size: CGSize(width: 320, height: 320),
            zIndex: 3,
            rotationRadians: .pi / 8
        )
        let runtimeState = BoardRuntimeState(
            boardID: UUID(),
            title: "Hand Drawing Mapper",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            items: [.handDrawing(item)],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState(
                selectedItemIDs: [itemID],
                primarySelectedItemID: itemID
            ),
            workspaceMode: .editing
        )

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let handDrawingRecord = try XCTUnwrap(document.handDrawingItemRecords.first)
        XCTAssertEqual(handDrawingRecord.id, itemID)
        XCTAssertEqual(handDrawingRecord.documentID, documentID)
        XCTAssertEqual(handDrawingRecord.paper.canvasPaperSpec, .square)
        XCTAssertEqual(handDrawingRecord.contentRevision, contentRevision)
        XCTAssertEqual(handDrawingRecord.storage, .bundle)
        XCTAssertEqual(
            handDrawingRecord.previewImageFilename,
            HandDrawingBundleLocator(documentID: documentID).previewImageRelativePath
        )

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { imageRecord in
                XCTAssertEqual(
                    imageRecord.assetFilename,
                    handDrawingRecord.previewImageFilename
                )
                return previewImage
            }
        )
        let roundTrippedItem = try XCTUnwrap(roundTrippedState.handDrawingItems.first)

        XCTAssertEqual(roundTrippedItem.id, item.id)
        XCTAssertEqual(roundTrippedItem.documentID, item.documentID)
        XCTAssertEqual(roundTrippedItem.paper, item.paper)
        XCTAssertEqual(roundTrippedItem.isEmpty, item.isEmpty)
        XCTAssertEqual(roundTrippedItem.contentRevision, item.contentRevision)
        XCTAssertEqual(roundTrippedItem.center, item.center)
        XCTAssertEqual(roundTrippedItem.size, item.size)
        XCTAssertEqual(roundTrippedItem.zIndex, item.zIndex)
        XCTAssertEqual(roundTrippedItem.rotationRadians, item.rotationRadians)
        XCTAssertEqual(
            roundTrippedItem.previewAsset.reference.stableAssetFilename,
            item.previewImageFilename
        )
    }

    func testBoardDocumentMapperRoundTripsArrowItem() throws {
        let item = CanvasArrowItem(
            id: UUID(),
            startPoint: CGPoint(x: 40, y: 20),
            endPoint: CGPoint(x: 260, y: 120),
            shaftThickness: 28,
            zIndex: 4
        )
        let runtimeState = BoardRuntimeState(
            boardID: UUID(),
            title: "Arrow Mapper",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            items: [.arrow(item)],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState(
                selectedItemIDs: [item.id],
                primarySelectedItemID: item.id
            ),
            workspaceMode: .editing
        )

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        XCTAssertEqual(document.formatVersion, BoardDocument.currentFormatVersion)
        let arrowRecord = try XCTUnwrap(document.arrowItemRecords.first)
        XCTAssertEqual(arrowRecord.id, item.id)
        XCTAssertEqual(arrowRecord.startPoint.cgPoint, item.startPoint)
        XCTAssertEqual(arrowRecord.endPoint.cgPoint, item.endPoint)
        XCTAssertEqual(arrowRecord.shaftThickness, Double(item.shaftThickness))
        XCTAssertEqual(arrowRecord.zIndex, Double(item.zIndex))

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )
        let roundTrippedItem = try XCTUnwrap(roundTrippedState.arrowItems.first)

        XCTAssertEqual(roundTrippedItem.id, item.id)
        XCTAssertEqual(roundTrippedItem.startPoint, item.startPoint)
        XCTAssertEqual(roundTrippedItem.endPoint, item.endPoint)
        XCTAssertEqual(roundTrippedItem.shaftThickness, item.shaftThickness)
        XCTAssertEqual(roundTrippedItem.zIndex, item.zIndex)
    }

    func testBoardDocumentDecodesLegacyArrowGeometryIntoEndpointModel() throws {
        let arrowID = UUID()
        let currentRecord = BoardArrowItemRecord(
            id: arrowID,
            startPoint: BoardPointRecord(CGPoint(x: 20, y: 20)),
            endPoint: BoardPointRecord(CGPoint(x: 60, y: 20)),
            shaftThickness: 16,
            zIndex: 2
        )
        let document = makeBoardDocument(
            selectedItemIDs: [arrowID],
            primarySelectedItemID: arrowID,
            items: [.arrow(currentRecord)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedDocument = try encoder.encode(document)
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDocument) as? [String: Any]
        )
        var itemPayloads = try XCTUnwrap(payload["items"] as? [[String: Any]])
        var firstItemPayload = try XCTUnwrap(itemPayloads.first)
        var legacyArrowPayload = try XCTUnwrap(
            firstItemPayload["arrow"] as? [String: Any]
        )
        legacyArrowPayload.removeValue(forKey: "startPoint")
        legacyArrowPayload.removeValue(forKey: "endPoint")
        legacyArrowPayload.removeValue(forKey: "shaftThickness")
        legacyArrowPayload["center"] = ["x": 120.0, "y": 90.0]
        legacyArrowPayload["size"] = ["width": 220.0, "height": 80.0]
        legacyArrowPayload["rotationRadians"] = Double.pi / 8
        firstItemPayload["arrow"] = legacyArrowPayload
        itemPayloads[0] = firstItemPayload
        payload["items"] = itemPayloads
        payload["formatVersion"] = 10

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyDocument = try decoder.decode(
            BoardDocument.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        let runtimeState = try BoardDocumentMapper.makeRuntimeState(
            from: legacyDocument,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )
        let arrowItem = try XCTUnwrap(runtimeState.arrowItems.first)
        let expectedItem = CanvasArrowItem(
            id: arrowID,
            center: CGPoint(x: 120, y: 90),
            size: CGSize(width: 220, height: 80),
            zIndex: 2,
            rotationRadians: .pi / 8
        )

        XCTAssertEqual(arrowItem.startPoint.x, expectedItem.startPoint.x, accuracy: 0.0001)
        XCTAssertEqual(arrowItem.startPoint.y, expectedItem.startPoint.y, accuracy: 0.0001)
        XCTAssertEqual(arrowItem.endPoint.x, expectedItem.endPoint.x, accuracy: 0.0001)
        XCTAssertEqual(arrowItem.endPoint.y, expectedItem.endPoint.y, accuracy: 0.0001)
        XCTAssertEqual(arrowItem.shaftThickness, expectedItem.shaftThickness, accuracy: 0.0001)
        XCTAssertEqual(legacyDocument.formatVersion, 10)
    }

    func testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize() throws {
        let item = CanvasMarkdownItem(
            id: UUID(),
            markdownSource: "## Title\n\nBody",
            style: CanvasTextStyle(fontSize: 20),
            center: CGPoint(x: 140, y: 90),
            size: CGSize(width: 320, height: 180),
            scrollOffsetY: 36,
            zIndex: 2,
            rotationRadians: .pi / 12
        )
        let runtimeState = BoardRuntimeState(
            boardID: UUID(),
            title: "Markdown Mapper",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            items: [.markdown(item)],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState(
                selectedItemIDs: [item.id],
                primarySelectedItemID: item.id
            ),
            workspaceMode: .editing
        )

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        XCTAssertEqual(document.formatVersion, BoardDocument.currentFormatVersion)
        let markdownRecord = try XCTUnwrap(document.markdownItemRecords.first)
        XCTAssertEqual(markdownRecord.id, item.id)
        XCTAssertEqual(markdownRecord.markdownSource, item.markdownSource)
        XCTAssertEqual(markdownRecord.style, BoardTextStyleRecord(item.style))
        XCTAssertEqual(markdownRecord.center.cgPoint, item.center)
        XCTAssertEqual(markdownRecord.size.cgSize, item.size)
        XCTAssertEqual(markdownRecord.rotationRadians, Double(item.rotationRadians))
        XCTAssertEqual(markdownRecord.scrollOffsetY, Double(item.scrollOffsetY))

        let roundTrippedState = try BoardDocumentMapper.makeRuntimeState(
            from: document,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )
        let roundTrippedItem = try XCTUnwrap(roundTrippedState.markdownItems.first)

        XCTAssertEqual(roundTrippedItem.id, item.id)
        XCTAssertEqual(roundTrippedItem.markdownSource, item.markdownSource)
        XCTAssertEqual(roundTrippedItem.style, item.style)
        XCTAssertEqual(roundTrippedItem.center, item.center)
        XCTAssertEqual(roundTrippedItem.size, item.size)
        XCTAssertEqual(roundTrippedItem.rotationRadians, item.rotationRadians)
        XCTAssertEqual(roundTrippedItem.scrollOffsetY, item.scrollOffsetY)
        XCTAssertEqual(roundTrippedItem.zIndex, item.zIndex)
        XCTAssertNil(roundTrippedState.boardState)
    }

    func testBoardDocumentCodableRoundTripsMarkdownItemRecords() throws {
        let markdownRecord = BoardMarkdownItemRecord(
            id: UUID(),
            center: BoardPointRecord(CGPoint(x: 160, y: 96)),
            size: BoardSizeRecord(CGSize(width: 280, height: 180)),
            zIndex: 3,
            markdownSource: "## Title\n\nBody",
            style: BoardTextStyleRecord(CanvasTextStyle(fontSize: 22)),
            rotationRadians: Double.pi / 10,
            scrollOffsetY: 24
        )
        let document = makeBoardDocument(
            selectedItemIDs: [markdownRecord.id],
            primarySelectedItemID: markdownRecord.id,
            items: [.markdown(markdownRecord)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedDocument = try encoder.encode(document)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDocument) as? [String: Any]
        )
        let itemPayload = try XCTUnwrap(
            (payload["items"] as? [[String: Any]])?.first
        )

        XCTAssertEqual(itemPayload["type"] as? String, "markdown")
        XCTAssertNotNil(itemPayload["markdown"])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedDocument = try decoder.decode(
            BoardDocument.self,
            from: encodedDocument
        )
        let decodedRecord = try XCTUnwrap(decodedDocument.markdownItemRecords.first)

        XCTAssertEqual(decodedDocument.formatVersion, BoardDocument.currentFormatVersion)
        XCTAssertEqual(decodedDocument.selectedItemIDs, [markdownRecord.id])
        XCTAssertEqual(decodedDocument.primarySelectedItemID, markdownRecord.id)
        XCTAssertEqual(decodedRecord, markdownRecord)
    }

    func testBoardDocumentMapperLoadsLegacyBoardWithoutMarkdownItems() throws {
        let legacyTextRecord = BoardTextItemRecord(
            id: UUID(),
            center: BoardPointRecord(CGPoint(x: 72, y: 40)),
            size: BoardSizeRecord(CGSize(width: 160, height: 48)),
            zIndex: 1,
            text: "Legacy board",
            style: BoardTextStyleRecord(CanvasTextStyle(fontSize: 20)),
            rotationRadians: 0
        )
        let legacyDocument = BoardDocument(
            formatVersion: 8,
            boardID: UUID(),
            title: "Legacy Without Markdown",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            boardBaseSize: nil,
            boardRect: nil,
            cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 18)),
            cameraZoomScale: 1,
            selectedItemIDs: [legacyTextRecord.id],
            primarySelectedItemID: legacyTextRecord.id,
            workspaceMode: .editing,
            items: [.text(legacyTextRecord)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedDocument = try encoder.encode(legacyDocument)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedDocument = try decoder.decode(
            BoardDocument.self,
            from: encodedDocument
        )
        let runtimeState = try BoardDocumentMapper.makeRuntimeState(
            from: decodedDocument,
            imageLoader: { _ in
                throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
            }
        )

        XCTAssertEqual(decodedDocument.formatVersion, 8)
        XCTAssertTrue(decodedDocument.markdownItemRecords.isEmpty)
        XCTAssertEqual(runtimeState.textItems.map(\.id), [legacyTextRecord.id])
        XCTAssertTrue(runtimeState.markdownItems.isEmpty)
        XCTAssertEqual(
            runtimeState.interactionState.primarySelectedItemID,
            legacyTextRecord.id
        )
    }

    func testBoardHandDrawingItemRecordDecodesLegacyAssetIdentityFromItemID() throws {
        let itemID = UUID()
        let contentRevision = UUID()
        let legacyPayload: [String: Any] = [
            "id": itemID.uuidString,
            "center": ["x": 48, "y": 72],
            "size": ["width": 240, "height": 180],
            "zIndex": 2,
            "paper": [
                "id": "square",
                "size": ["width": 1_024, "height": 1_024]
            ],
            "isEmpty": true,
            "contentRevision": contentRevision.uuidString,
            "rotationRadians": Double.pi / 6
        ]
        let decoder = JSONDecoder()
        let record = try decoder.decode(
            BoardHandDrawingItemRecord.self,
            from: try JSONSerialization.data(withJSONObject: legacyPayload)
        )

        XCTAssertEqual(record.id, itemID)
        XCTAssertEqual(record.documentID, itemID)
        XCTAssertEqual(record.storage, .legacyFlatAssetPair)
        XCTAssertEqual(
            record.previewImageFilename,
            CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
        )
        XCTAssertEqual(
            record.sourceDrawingFilename,
            CanvasHandDrawingItem.defaultSourceDrawingFilename(for: itemID)
        )
    }
}

private enum BoardSelectionStateMigrationTestError: Error {
    case unexpectedImageDecode
}

private func makeBoardDocument(
    selectedItemIDs: [UUID],
    primarySelectedItemID: UUID?,
    boardBaseSize: CGSize? = nil,
    boardRect: CGRect? = nil,
    items: [BoardItemRecord] = []
) -> BoardDocument {
    BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: UUID(),
        title: "Legacy Selection",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        boardBaseSize: boardBaseSize.map(BoardSizeRecord.init),
        boardRect: boardRect.map(BoardRectRecord.init),
        cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 34)),
        cameraZoomScale: 1.5,
        selectedItemIDs: selectedItemIDs,
        primarySelectedItemID: primarySelectedItemID,
        workspaceMode: .editing,
        items: items
    )
}

private func makeSolidColorPreviewImage(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat
) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
    }

    context.setFillColor(
        red: red,
        green: green,
        blue: blue,
        alpha: 1
    )
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return try XCTUnwrap(context.makeImage())
}
