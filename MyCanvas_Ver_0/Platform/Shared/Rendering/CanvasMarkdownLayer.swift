import CoreGraphics
import QuartzCore

final class CanvasMarkdownLayer: CATextLayer {
    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedRotationRadians: CGFloat
    private var lastAppliedMarkdownSource: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedZoomScale: CGFloat
    private var lastAppliedLayoutWidth: CGFloat

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedRotationRadians = .nan
        lastAppliedMarkdownSource = ""
        lastAppliedStyle = nil
        lastAppliedZoomScale = .nan
        lastAppliedLayoutWidth = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let markdownLayer = layer as? CanvasMarkdownLayer {
            itemID = markdownLayer.itemID
            lastAppliedPosition = markdownLayer.lastAppliedPosition
            lastAppliedBoundsSize = markdownLayer.lastAppliedBoundsSize
            lastAppliedZIndex = markdownLayer.lastAppliedZIndex
            lastAppliedContentsScale = markdownLayer.lastAppliedContentsScale
            lastAppliedRotationRadians = markdownLayer.lastAppliedRotationRadians
            lastAppliedMarkdownSource = markdownLayer.lastAppliedMarkdownSource
            lastAppliedStyle = markdownLayer.lastAppliedStyle
            lastAppliedZoomScale = markdownLayer.lastAppliedZoomScale
            lastAppliedLayoutWidth = markdownLayer.lastAppliedLayoutWidth
        } else {
            itemID = UUID()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedRotationRadians = .nan
            lastAppliedMarkdownSource = ""
            lastAppliedStyle = nil
            lastAppliedZoomScale = .nan
            lastAppliedLayoutWidth = .nan
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
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

        if shouldRefreshAttributedText(
            markdownPayload: markdownPayload,
            layoutWidth: item.screenBoundsSize.width
        ) {
            let layout = CanvasMarkdownLayoutMeasurer.layout(
                markdownSource: markdownPayload.markdownSource,
                style: markdownPayload.style,
                maxLayoutWidth: item.screenBoundsSize.width,
                scale: markdownPayload.zoomScale
            )
            string = layout.attributedText
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedZoomScale = markdownPayload.zoomScale
            lastAppliedLayoutWidth = item.screenBoundsSize.width
        }

        CATransaction.commit()
    }

    private func configureLayer() {
        alignmentMode = .left
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        isWrapped = true
        truncationMode = .none
        masksToBounds = true
    }

    private func shouldRefreshAttributedText(
        markdownPayload: CanvasMarkdownRenderPayload,
        layoutWidth: CGFloat
    ) -> Bool {
        lastAppliedMarkdownSource != markdownPayload.markdownSource ||
        lastAppliedStyle != markdownPayload.style ||
        lastAppliedZoomScale != markdownPayload.zoomScale ||
        lastAppliedLayoutWidth != layoutWidth
    }
}
