import CoreGraphics
import Foundation

struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        camera: CanvasCamera
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        let renderItems = scene.visibleItems(in: visibleWorldRect).map { item in
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
