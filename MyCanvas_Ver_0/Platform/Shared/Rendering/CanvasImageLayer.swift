import CoreGraphics
import QuartzCore

final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        super.init()
        contentsGravity = .resize
        masksToBounds = true
    }

    override init(layer: Any) {
        if let imageLayer = layer as? CanvasImageLayer {
            itemID = imageLayer.itemID
        } else {
            itemID = UUID()
        }

        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        frame = item.screenFrame
        contents = item.cgImage
        zPosition = item.zIndex
        self.contentsScale = contentsScale
    }
}
