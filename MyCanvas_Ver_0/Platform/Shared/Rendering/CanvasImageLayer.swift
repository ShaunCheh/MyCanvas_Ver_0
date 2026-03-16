import CoreGraphics
import QuartzCore

// Image layers only render image content. Selection visuals live in viewport
// overlays so shared render items stay free of platform-specific chrome.
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        lastAppliedFrame = .null
        lastAppliedImage = nil
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let imageLayer = layer as? CanvasImageLayer {
            itemID = imageLayer.itemID
            lastAppliedFrame = imageLayer.lastAppliedFrame
            lastAppliedImage = imageLayer.lastAppliedImage
            lastAppliedZIndex = imageLayer.lastAppliedZIndex
            lastAppliedContentsScale = imageLayer.lastAppliedContentsScale
        } else {
            itemID = UUID()
            lastAppliedFrame = .null
            lastAppliedImage = nil
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedFrame != item.screenFrame {
            frame = item.screenFrame
            lastAppliedFrame = item.screenFrame
        }

        if !isDisplayingImage(item.cgImage) {
            contents = item.cgImage
            lastAppliedImage = item.cgImage
        }

        if lastAppliedZIndex != item.zIndex {
            zPosition = item.zIndex
            lastAppliedZIndex = item.zIndex
        }

        if lastAppliedContentsScale != contentsScale {
            self.contentsScale = contentsScale
            lastAppliedContentsScale = contentsScale
        }

        CATransaction.commit()
    }

    private func configureLayer() {
        contentsGravity = .resize
        masksToBounds = true
    }

    private func isDisplayingImage(_ cgImage: CGImage) -> Bool {
        guard let lastAppliedImage else {
            return false
        }

        return lastAppliedImage === cgImage
    }
}
