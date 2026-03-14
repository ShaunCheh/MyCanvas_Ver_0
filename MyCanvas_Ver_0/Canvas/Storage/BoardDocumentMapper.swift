import CoreGraphics
import Foundation

enum BoardDocumentMapper {
    static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
        BoardDocument(
            formatVersion: BoardDocument.currentFormatVersion,
            boardID: runtimeState.boardID,
            title: runtimeState.title,
            createdAt: runtimeState.createdAt,
            updatedAt: runtimeState.updatedAt,
            boardBaseSize: runtimeState.boardState.map { BoardSizeRecord($0.baseSize) },
            boardRect: runtimeState.boardState.map { BoardRectRecord($0.worldRect) },
            cameraCenter: BoardPointRecord(runtimeState.camera.center),
            cameraZoomScale: Double(runtimeState.camera.zoomScale),
            selectedItemID: runtimeState.interactionState.selectedItemID,
            items: runtimeState.items.map(makeImageRecord)
        )
    }

    static func makeRuntimeState(
        from document: BoardDocument,
        imageLoader: (BoardImageItemRecord) throws -> CGImage
    ) throws -> BoardRuntimeState {
        let items = try document.items.map { itemRecord in
            CanvasImageItem(
                id: itemRecord.id,
                cgImage: try imageLoader(itemRecord),
                center: itemRecord.center.cgPoint,
                size: itemRecord.size.cgSize,
                zIndex: CGFloat(itemRecord.zIndex)
            )
        }

        return BoardRuntimeState(
            boardID: document.boardID,
            title: document.title,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            items: items,
            boardState: makeBoardState(
                boardBaseSize: document.boardBaseSize,
                boardRect: document.boardRect
            ),
            camera: CanvasCamera(
                center: document.cameraCenter.cgPoint,
                zoomScale: CGFloat(document.cameraZoomScale),
                viewportSize: .zero
            ),
            interactionState: CanvasInteractionState(
                selectedItemID: document.selectedItemID
            )
        )
    }

    private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
        BoardImageItemRecord(
            id: item.id,
            center: BoardPointRecord(item.center),
            size: BoardSizeRecord(item.size),
            zIndex: Double(item.zIndex),
            assetFilename: "\(item.id.uuidString).png"
        )
    }

    private static func makeBoardState(
        boardBaseSize: BoardSizeRecord?,
        boardRect: BoardRectRecord?
    ) -> CanvasBoardState? {
        guard let boardRect else {
            return nil
        }

        let baseSize = boardBaseSize?.cgSize ?? boardRect.size.cgSize
        return CanvasBoardState(
            baseSize: baseSize,
            worldRect: boardRect.cgRect
        )
    }
}
