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
}

private enum BoardSelectionStateMigrationTestError: Error {
    case unexpectedImageDecode
}

private func makeBoardDocument(
    selectedItemIDs: [UUID],
    primarySelectedItemID: UUID?
) -> BoardDocument {
    BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: UUID(),
        title: "Legacy Selection",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        boardBaseSize: nil,
        boardRect: nil,
        cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 34)),
        cameraZoomScale: 1.5,
        selectedItemIDs: selectedItemIDs,
        primarySelectedItemID: primarySelectedItemID,
        workspaceMode: .editing,
        items: []
    )
}
