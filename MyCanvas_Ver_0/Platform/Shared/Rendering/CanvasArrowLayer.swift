import CoreGraphics
import Foundation
import QuartzCore

final class CanvasArrowLayer: CAShapeLayer {
    private static let fillColorValue = CGColor(
        red: 0.12,
        green: 0.12,
        blue: 0.12,
        alpha: 1
    )

    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedRotationRadians: CGFloat

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedRotationRadians = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let arrowLayer = layer as? CanvasArrowLayer {
            itemID = arrowLayer.itemID
            lastAppliedPosition = arrowLayer.lastAppliedPosition
            lastAppliedBoundsSize = arrowLayer.lastAppliedBoundsSize
            lastAppliedZIndex = arrowLayer.lastAppliedZIndex
            lastAppliedContentsScale = arrowLayer.lastAppliedContentsScale
            lastAppliedRotationRadians = arrowLayer.lastAppliedRotationRadians
        } else {
            itemID = UUID()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedRotationRadians = .nan
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        with item: CanvasRenderItem,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            path = canvasArrowPath(in: bounds)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
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
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fillColor = Self.fillColorValue
        strokeColor = nil
        lineWidth = 0
        masksToBounds = false
    }
}
