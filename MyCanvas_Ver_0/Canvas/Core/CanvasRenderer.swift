import CoreGraphics
import Foundation

struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState()
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
            makeRenderItem(for: item, camera: camera)
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
            interactionState: interactionState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            selectionOverlay: selectionOverlay
        )
    }

    // Renderer is the single source of truth for selection geometry so drawing
    // and hit testing stay aligned without consulting platform layer state.
    private func makeSelectionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState
    ) -> CanvasSelectionRenderOverlay? {
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
        camera: CanvasCamera
    ) -> CanvasRenderItem {
        let screenQuad = camera.worldToViewport(item.worldQuad)
        return CanvasRenderItem(
            id: item.id,
            screenFrame: screenQuad.boundingRect.standardized,
            screenQuad: screenQuad,
            screenCenter: camera.worldToViewport(item.center),
            screenBoundsSize: CGSize(
                width: item.size.width * camera.zoomScale,
                height: item.size.height * camera.zoomScale
            ),
            contentsRect: item.imageContentsRect,
            rotationRadians: item.rotationRadians,
            cgImage: item.cgImage,
            zIndex: item.zIndex
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
}
