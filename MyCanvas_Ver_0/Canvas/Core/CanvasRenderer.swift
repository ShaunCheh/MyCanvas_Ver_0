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
            CanvasRenderItem(
                id: item.id,
                screenFrame: camera.worldToViewport(item.worldFrame),
                cgImage: item.cgImage,
                zIndex: item.zIndex
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

        let worldFrame = selectedItem.worldFrame.standardized
        let screenFrame = camera.worldToViewport(worldFrame).standardized

        return CanvasSelectionRenderOverlay(
            itemID: selectedItemID,
            worldFrame: worldFrame,
            screenFrame: screenFrame,
            handles: makeSelectionHandles(for: screenFrame)
        )
    }

    private func makeSelectionHandles(for screenFrame: CGRect) -> [CanvasSelectionHandleGeometry] {
        CanvasSelectionHandleRole.allCases.map { role in
            CanvasSelectionHandleGeometry(
                role: role,
                screenCenter: selectionHandleCenter(for: role, in: screenFrame)
            )
        }
    }

    private func selectionHandleCenter(
        for role: CanvasSelectionHandleRole,
        in screenFrame: CGRect
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return CGPoint(x: screenFrame.minX, y: screenFrame.minY)
        case .topTrailing:
            return CGPoint(x: screenFrame.maxX, y: screenFrame.minY)
        case .bottomLeading:
            return CGPoint(x: screenFrame.minX, y: screenFrame.maxY)
        case .bottomTrailing:
            return CGPoint(x: screenFrame.maxX, y: screenFrame.maxY)
        }
    }
}
