import CoreGraphics
import Foundation

struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        inlineEditState: CanvasInlineEditState? = nil
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        // Avoid turning an invalid zero-sized viewport into point-based culling.
        let visibleItems: [CanvasImageItem]
        if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
            visibleItems = scene.visibleItems(in: visibleWorldRect)
        } else {
            visibleItems = scene.orderedItems()
        }

        let renderItems = visibleItems.map { item in
            makeRenderItem(
                for: item,
                camera: camera,
                inlineEditState: inlineEditState
            )
        }

        let boardOverlay = boardState.map { boardState in
            CanvasBoardRenderOverlay(
                worldRect: boardState.worldRect,
                screenRect: camera.worldToViewport(boardState.worldRect)
            )
        }

        let selectionOverlay = makeSelectionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        )
        let cropOverlay = makeCropOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            selectionOverlay: selectionOverlay,
            cropOverlay: cropOverlay
        )
    }

    // Renderer is the single source of truth for selection geometry so drawing
    // and hit testing stay aligned without consulting platform layer state.
    private func makeSelectionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasSelectionRenderOverlay? {
        guard inlineEditState?.mode != .crop else {
            return nil
        }

        guard
            let selectedItemID = interactionState.selectedItemID,
            let selectedItem = scene.item(withID: selectedItemID)
        else {
            return nil
        }

        let worldQuad = selectedItem.worldQuad
        let worldFrame = worldQuad.boundingRect.standardized
        let screenQuad = camera.worldToViewport(worldQuad)
        let screenFrame = screenQuad.boundingRect.standardized

        return CanvasSelectionRenderOverlay(
            itemID: selectedItemID,
            worldFrame: worldFrame,
            worldQuad: worldQuad,
            screenFrame: screenFrame,
            screenQuad: screenQuad,
            handles: makeSelectionHandles(for: screenQuad)
        )
    }

    private func makeRenderItem(
        for item: CanvasImageItem,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasRenderItem {
        let isEditingCropItem =
            inlineEditState?.mode == .crop &&
            inlineEditState?.itemID == item.id
        let worldQuad = isEditingCropItem ? item.fullImageWorldQuad : item.worldQuad
        let renderCenter = isEditingCropItem
            ? item.worldPoint(fromLocal: CGPoint(
                x: item.fullImageLocalFrame.midX,
                y: item.fullImageLocalFrame.midY
            ))
            : item.center
        let renderSize = isEditingCropItem
            ? item.fullImageLocalFrame.size
            : item.size
        let contentsRect = isEditingCropItem
            ? CanvasImageCropRect.fullImage.cgRect
            : item.imageContentsRect
        let screenQuad = camera.worldToViewport(worldQuad)
        return CanvasRenderItem(
            id: item.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(renderCenter),
            screenBoundsSize: CGSize(
                width: renderSize.width * camera.zoomScale,
                height: renderSize.height * camera.zoomScale
            ),
            contentsRect: contentsRect,
            rotationRadians: item.rotationRadians,
            cgImage: item.cgImage,
            zIndex: item.zIndex
        )
    }

    private func makeCropOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasCropRenderOverlay? {
        guard
            let inlineEditState,
            inlineEditState.mode == .crop,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            return nil
        }

        let fullImageWorldQuad = item.fullImageWorldQuad
        let cropWorldQuad = item.worldQuad(forNormalizedCropRect: inlineEditState.draftCropRectNormalized)
        let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
        let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

        return CanvasCropRenderOverlay(
            itemID: item.id,
            mode: inlineEditState.mode,
            fullImageWorldQuad: fullImageWorldQuad,
            fullImageScreenQuad: fullImageScreenQuad,
            cropRectNormalized: inlineEditState.draftCropRectNormalized,
            cropWorldQuad: cropWorldQuad,
            cropScreenQuad: cropScreenQuad,
            handles: makeCropHandles(for: cropScreenQuad)
        )
    }

    private func makeSelectionHandles(for screenQuad: CanvasQuad) -> [CanvasSelectionHandleGeometry] {
        CanvasSelectionHandleRole.allCases.map { role in
            CanvasSelectionHandleGeometry(
                role: role,
                screenCenter: selectionHandleCenter(for: role, in: screenQuad)
            )
        }
    }

    private func makeCropHandles(for screenQuad: CanvasQuad) -> [CanvasCropHandleGeometry] {
        CanvasCropHandleRole.allCases.map { role in
            CanvasCropHandleGeometry(
                role: role,
                screenCenter: cropHandleCenter(for: role, in: screenQuad)
            )
        }
    }

    private func selectionHandleCenter(
        for role: CanvasSelectionHandleRole,
        in screenQuad: CanvasQuad
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return screenQuad.topLeading
        case .topTrailing:
            return screenQuad.topTrailing
        case .bottomLeading:
            return screenQuad.bottomLeading
        case .bottomTrailing:
            return screenQuad.bottomTrailing
        }
    }

    private func cropHandleCenter(
        for role: CanvasCropHandleRole,
        in screenQuad: CanvasQuad
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return screenQuad.topLeading
        case .topTrailing:
            return screenQuad.topTrailing
        case .bottomLeading:
            return screenQuad.bottomLeading
        case .bottomTrailing:
            return screenQuad.bottomTrailing
        }
    }
}
