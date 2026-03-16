import CoreGraphics
import QuartzCore

// Image layers only render image content. Selection visuals live in viewport
// overlays so shared render items stay free of platform-specific chrome.
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedContentsRect: CGRect
    private var lastAppliedRotationRadians: CGFloat

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedImage = nil
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedContentsRect = .null
        lastAppliedRotationRadians = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let imageLayer = layer as? CanvasImageLayer {
            itemID = imageLayer.itemID
            lastAppliedPosition = imageLayer.lastAppliedPosition
            lastAppliedBoundsSize = imageLayer.lastAppliedBoundsSize
            lastAppliedImage = imageLayer.lastAppliedImage
            lastAppliedZIndex = imageLayer.lastAppliedZIndex
            lastAppliedContentsScale = imageLayer.lastAppliedContentsScale
            lastAppliedContentsRect = imageLayer.lastAppliedContentsRect
            lastAppliedRotationRadians = imageLayer.lastAppliedRotationRadians
        } else {
            itemID = UUID()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedImage = nil
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedContentsRect = .null
            lastAppliedRotationRadians = .nan
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

        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if !isDisplayingImage(item.cgImage) {
            contents = item.cgImage
            lastAppliedImage = item.cgImage
        }

        if lastAppliedContentsRect != item.contentsRect {
            contentsRect = item.contentsRect
            lastAppliedContentsRect = item.contentsRect
        }

        if lastAppliedRotationRadians != item.rotationRadians {
            transform = CATransform3DMakeRotation(item.rotationRadians, 0, 0, 1)
            lastAppliedRotationRadians = item.rotationRadians
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
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
    }

    private func isDisplayingImage(_ cgImage: CGImage) -> Bool {
        guard let lastAppliedImage else {
            return false
        }

        return lastAppliedImage === cgImage
    }
}
