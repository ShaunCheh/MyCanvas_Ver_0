import CoreGraphics
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

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
