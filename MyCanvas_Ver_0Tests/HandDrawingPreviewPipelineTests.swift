import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingPreviewPipelineTests: XCTestCase {
    func testBoardGeometryPreviewBuilderMarksHandDrawingSeedNodeKind() {
        let itemID = UUID()
        let boardRect = CGRect(x: 0, y: 0, width: 120, height: 120)
        let handDrawingRecord = BoardHandDrawingItemRecord(
            id: itemID,
            center: BoardPointRecord(CGPoint(x: 60, y: 60)),
            size: BoardSizeRecord(CGSize(width: 80, height: 80)),
            zIndex: 2,
            paper: BoardHandDrawingPaperRecord(.square),
            isEmpty: true,
            contentRevision: UUID(),
            rotationRadians: Double.pi / 8
        )
        let document = makeHandDrawingPreviewTestDocument(
            boardID: UUID(),
            boardRect: boardRect,
            items: [.handDrawing(handDrawingRecord)]
        )

        let seed = BoardGeometryPreviewBuilder().makeSeed(from: document)
        XCTAssertEqual(seed.nodes.count, 1)

        guard let node = seed.nodes.first else {
            XCTFail("Expected a hand drawing preview node.")
            return
        }
        XCTAssertEqual(node.id, handDrawingRecord.id)
        switch node.kind {
        case .handDrawing:
            break
        default:
            XCTFail("Expected handDrawing node kind, got \(node.kind).")
        }
    }

    func testBoardGeometryPreviewBuilderMakesMiniMapSnapshotWithHandDrawingNode() {
        let boardRect = CGRect(x: 20, y: 10, width: 160, height: 120)
        let handDrawingRecord = BoardHandDrawingItemRecord(
            id: UUID(),
            center: BoardPointRecord(CGPoint(x: 100, y: 70)),
            size: BoardSizeRecord(CGSize(width: 80, height: 80)),
            zIndex: 1,
            paper: BoardHandDrawingPaperRecord(.square),
            isEmpty: false,
            contentRevision: UUID(),
            rotationRadians: 0
        )
        let document = makeHandDrawingPreviewTestDocument(
            boardID: UUID(),
            boardRect: boardRect,
            items: [.handDrawing(handDrawingRecord)]
        )
        let builder = BoardGeometryPreviewBuilder()

        let seed = builder.makeSeed(from: document)
        let snapshot = builder.makeSnapshot(from: seed)

        XCTAssertEqual(snapshot.boardWorldRect, boardRect)
        XCTAssertEqual(snapshot.displayWorldRect, boardRect)
        XCTAssertEqual(snapshot.nodes.count, 1)
        switch snapshot.nodes[0].kind {
        case .handDrawing:
            break
        default:
            XCTFail("Expected minimap snapshot to keep handDrawing node kind.")
        }
    }
}

private func makeHandDrawingPreviewTestDocument(
    boardID: UUID,
    boardRect: CGRect,
    items: [BoardItemRecord]
) -> BoardDocument {
    let now = Date(timeIntervalSince1970: 1_720_001_000)
    return BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: boardID,
        title: "Preview Test",
        createdAt: now,
        contentUpdatedAt: now,
        viewStateUpdatedAt: now,
        boardBaseSize: BoardSizeRecord(boardRect.size),
        boardRect: BoardRectRecord(boardRect),
        cameraCenter: BoardPointRecord(
            CGPoint(x: boardRect.midX, y: boardRect.midY)
        ),
        cameraZoomScale: 1,
        workspaceMode: .editing,
        items: items
    )
}
