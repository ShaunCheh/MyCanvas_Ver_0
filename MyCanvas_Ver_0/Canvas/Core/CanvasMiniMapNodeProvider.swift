import Foundation

struct CanvasMiniMapNodeProviderContext {
    let scene: CanvasScene
    let inlineEditState: CanvasInlineEditState?
    let rotationPreviewState: CanvasRotationPreviewState?
}

struct CanvasMiniMapRenderContext {
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let nodeProviderContext: CanvasMiniMapNodeProviderContext

    init(
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        nodeProviderContext: CanvasMiniMapNodeProviderContext
    ) {
        self.boardState = boardState
        self.camera = camera
        self.nodeProviderContext = nodeProviderContext
    }

    init(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
    ) {
        self.init(
            boardState: boardState,
            camera: camera,
            nodeProviderContext: CanvasMiniMapNodeProviderContext(
                scene: scene,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        )
    }
}

protocol CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode]
}

// Renderer stays provider-driven so future text/sticker/shape support can add
// new node providers without rewriting snapshot/layout/platform minimap views.
struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.inlineEditState,
                rotationPreviewState: context.rotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}

struct CanvasMiniMapTextNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
            guard let item = boardItem.textItem else {
                return nil
            }

            return CanvasMiniMapNode(
                id: item.id,
                kind: .text,
                worldQuad: item.worldQuad,
                zIndex: item.zIndex,
                isPreviewActive: context.inlineEditState?.mode == .text &&
                    context.inlineEditState?.itemID == item.id
            )
        }
    }
}
