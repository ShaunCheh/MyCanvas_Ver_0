import CoreGraphics
import Foundation

enum BoardDocumentMapper {
    static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
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
            workspaceMode: runtimeState.workspaceMode,
            items: runtimeState.items.map(makeItemRecord)
        )
    }

    static func makeRuntimeState(
        from document: BoardDocument,
        imageLoader: (BoardImageItemRecord) throws -> CGImage
    ) throws -> BoardRuntimeState {
        let items = try document.items.map { itemRecord in
            switch itemRecord {
            case let .image(imageRecord):
                return CanvasBoardItem.image(
                    CanvasImageItem(
                        id: imageRecord.id,
                        asset: CanvasImageAsset.persistedImage(
                            kind: imageRecord.assetReference.kind,
                            filename: imageRecord.assetReference.stableAssetFilename,
                            cgImage: try imageLoader(imageRecord)
                        ),
                        videoSource: imageRecord.videoSource,
                        posterTimeSeconds: imageRecord.posterTimeSeconds,
                        center: imageRecord.center.cgPoint,
                        size: imageRecord.size.cgSize,
                        zIndex: CGFloat(imageRecord.zIndex),
                        cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
                        rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
                    )
                )
            case let .text(textRecord):
                return CanvasBoardItem.text(
                    CanvasTextItem(
                        id: textRecord.id,
                        text: textRecord.text,
                        style: textRecord.style.canvasTextStyle,
                        center: textRecord.center.cgPoint,
                        size: textRecord.size.cgSize,
                        zIndex: CGFloat(textRecord.zIndex),
                        rotationRadians: CGFloat(textRecord.rotationRadians ?? 0)
                    )
                )
            }
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
            ),
            workspaceMode: document.workspaceMode ?? .editing
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

    private static func makeItemRecord(from item: CanvasBoardItem) -> BoardItemRecord {
        switch item {
        case let .image(imageItem):
            return .image(makeImageRecord(from: imageItem))
        case let .text(textItem):
            return .text(makeTextRecord(from: textItem))
        }
    }

    private static func makeImageRecord(from item: CanvasImageItem) -> BoardImageItemRecord {
        BoardImageItemRecord(
            id: item.id,
            center: BoardPointRecord(item.center),
            size: BoardSizeRecord(item.size),
            zIndex: Double(item.zIndex),
            assetFilename: item.assetReference.stableAssetFilename,
            assetKind: item.assetKind,
            posterImageFilename: item.assetReference.stableAssetFilename,
            sourceVideoFilename: item.videoSource?.sourceVideoFilename,
            posterTimeSeconds: item.posterTimeSeconds,
            cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
            rotationRadians: Double(item.rotationRadians)
        )
    }

    private static func makeTextRecord(from item: CanvasTextItem) -> BoardTextItemRecord {
        BoardTextItemRecord(
            id: item.id,
            center: BoardPointRecord(item.center),
            size: BoardSizeRecord(item.size),
            zIndex: Double(item.zIndex),
            text: item.text,
            style: BoardTextStyleRecord(item.style),
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
