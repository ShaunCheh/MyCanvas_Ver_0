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
            from: document
        ) { _ in
            throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
        }

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
            from: document
        ) { _ in
            throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
        }
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
