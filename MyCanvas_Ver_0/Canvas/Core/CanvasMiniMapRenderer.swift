import CoreGraphics
import Foundation

struct CanvasMiniMapRenderer {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(camera.visibleWorldRect) ?? .zero
        let nodes = scene.orderedItems().map { item in
            makeNode(
                for: item,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        }

        let boardWorldRect = resolveBoardWorldRect(
            boardState: boardState,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )
        let displayWorldRect = resolveDisplayWorldRect(
            boardWorldRect: boardWorldRect,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )

        return CanvasMiniMapSnapshot(
            boardWorldRect: boardWorldRect,
            displayWorldRect: displayWorldRect,
            visibleWorldRect: visibleWorldRect,
            nodes: nodes
        )
    }

    private func makeNode(
        for item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasMiniMapNode {
        let presentation = presentationResolver.resolve(
            item: item,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        return CanvasMiniMapNode(
            id: presentation.itemID,
            kind: .image,
            worldQuad: presentation.visibleWorldQuad,
            zIndex: presentation.zIndex,
            isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
        )
    }

    private func resolveBoardWorldRect(
        boardState: CanvasBoardState?,
        nodes: [CanvasMiniMapNode],
        fallbackVisibleWorldRect: CGRect
    ) -> CGRect {
        if let boardWorldRect = boardState.flatMap({ sanitizedWorldRect($0.worldRect) }) {
            return boardWorldRect
        }

        if let nodeBounds = combinedWorldBounds(of: nodes) {
            return nodeBounds
        }

        return fallbackVisibleWorldRect
    }

    private func resolveDisplayWorldRect(
        boardWorldRect: CGRect,
        nodes: [CanvasMiniMapNode],
        fallbackVisibleWorldRect: CGRect
    ) -> CGRect {
        guard let previewWorldBounds = combinedWorldBounds(
            of: nodes.filter(\.isPreviewActive)
        ) else {
            return sanitizedWorldRect(boardWorldRect) ?? fallbackVisibleWorldRect
        }

        guard let sanitizedBoardWorldRect = sanitizedWorldRect(boardWorldRect) else {
            return previewWorldBounds
        }

        return sanitizedBoardWorldRect.union(previewWorldBounds).standardized
    }

    private func combinedWorldBounds(of nodes: [CanvasMiniMapNode]) -> CGRect? {
        var combinedBounds: CGRect?

        for node in nodes {
            let nodeBounds = node.worldBounds
            guard let sanitizedNodeBounds = sanitizedWorldRect(nodeBounds) else {
                continue
            }

            if let existingBounds = combinedBounds {
                combinedBounds = existingBounds.union(sanitizedNodeBounds).standardized
            } else {
                combinedBounds = sanitizedNodeBounds
            }
        }

        return combinedBounds
    }

    private func sanitizedWorldRect(_ rect: CGRect) -> CGRect? {
        guard rect.isNull == false, rect.isInfinite == false else {
            return nil
        }

        let standardizedRect = rect.standardized
        guard
            standardizedRect.width > 0,
            standardizedRect.height > 0
        else {
            return nil
        }

        return standardizedRect
    }
}
