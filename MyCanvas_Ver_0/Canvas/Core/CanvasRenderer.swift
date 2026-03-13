import CoreGraphics
import Foundation

struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        camera: CanvasCamera
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

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            items: renderItems
        )
    }
}
