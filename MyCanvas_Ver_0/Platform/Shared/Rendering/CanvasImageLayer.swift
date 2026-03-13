import CoreGraphics
import QuartzCore

final class CanvasImageLayer: CALayer {
    private static let selectionBorderColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    private static let selectionBorderWidth: CGFloat = 2

    let itemID: CanvasImageItemID
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedIsSelected: Bool?

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        lastAppliedFrame = .null
        lastAppliedImage = nil
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedIsSelected = nil
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
            lastAppliedIsSelected = imageLayer.lastAppliedIsSelected
        } else {
            itemID = UUID()
            lastAppliedFrame = .null
            lastAppliedImage = nil
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedIsSelected = nil
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

        if lastAppliedIsSelected != item.isSelected {
            borderWidth = item.isSelected ? Self.selectionBorderWidth : 0
            borderColor = item.isSelected ? Self.selectionBorderColor : nil
            lastAppliedIsSelected = item.isSelected
        }

        CATransaction.commit()
    }

    private func configureLayer() {
        contentsGravity = .resize
        masksToBounds = true
        borderWidth = 0
        borderColor = nil
    }

    private func isDisplayingImage(_ cgImage: CGImage) -> Bool {
        guard let lastAppliedImage else {
            return false
        }

        return lastAppliedImage === cgImage
    }
}
