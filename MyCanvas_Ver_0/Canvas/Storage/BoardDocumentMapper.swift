import CoreGraphics
import Foundation

enum BoardDocumentMapper {
    static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
        let imageItems = runtimeState.imageItems
        assert(
            imageItems.count == runtimeState.items.count,
            "BoardDocument v2 can only persist image items before T-2."
        )

        return BoardDocument(
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
            items: imageItems.map(makeImageRecord)
        )
    }

    static func makeRuntimeState(
        from document: BoardDocument,
        imageLoader: (BoardImageItemRecord) throws -> CGImage
    ) throws -> BoardRuntimeState {
        let items = try document.items.map { itemRecord in
            CanvasBoardItem.image(
                CanvasImageItem(
                    id: itemRecord.id,
                    cgImage: try imageLoader(itemRecord),
                    center: itemRecord.center.cgPoint,
                    size: itemRecord.size.cgSize,
                    zIndex: CGFloat(itemRecord.zIndex),
                    cropRectNormalized: itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
                    rotationRadians: CGFloat(itemRecord.rotationRadians ?? 0)
                )
            )
        }

        let runtimeState = BoardRuntimeState(
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
        print(
            "[BoardStore][Mapper] " +
            "action=makeRuntimeState " +
            "boardID=\(document.boardID.uuidString) " +
            "title=\(document.title) " +
            "items=\(items.count) " +
            "cameraCenter=\(describeBoardMapperPoint(runtimeState.camera.center)) " +
            "cameraZoomScale=\(formatBoardMapperValue(runtimeState.camera.zoomScale)) " +
            "cameraViewportSize=\(describeBoardMapperSize(runtimeState.camera.viewportSize)) " +
            "selectedItemID=\(describeBoardMapperItemID(runtimeState.interactionState.selectedItemID))"
        )
        return runtimeState
    }

    private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
        BoardImageItemRecord(
            id: item.id,
            center: BoardPointRecord(item.center),
            size: BoardSizeRecord(item.size),
            zIndex: Double(item.zIndex),
            assetFilename: "\(item.id.uuidString).png",
            cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
            rotationRadians: Double(item.rotationRadians)
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

private func describeBoardMapperPoint(_ point: CGPoint) -> String {
    "{\(formatBoardMapperValue(point.x)), \(formatBoardMapperValue(point.y))}"
}

private func describeBoardMapperSize(_ size: CGSize) -> String {
    "{\(formatBoardMapperValue(size.width)), \(formatBoardMapperValue(size.height))}"
}

private func describeBoardMapperItemID(_ itemID: UUID?) -> String {
    itemID?.uuidString ?? "nil"
}

private func formatBoardMapperValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
