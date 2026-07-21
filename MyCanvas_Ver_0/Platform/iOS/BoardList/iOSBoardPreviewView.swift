#if os(iOS)
import UIKit

final class iOSBoardPreviewView: UIView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var content: BoardPreviewContent = .empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        performWithoutLayerActions {
            updateLayerFrames()
            refreshPreview()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAppearance()
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else {
            return
        }
        updateAppearance()
    }

    func apply(content: BoardPreviewContent) {
        self.content = content
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func setupLayers() {
        backgroundColor = .clear
        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = true
        layer.addSublayer(backgroundLayer)
        layer.addSublayer(boardLayer)
        layer.addSublayer(imageLayer)
        layer.addSublayer(occupancyLayer)

        imageLayer.contentsGravity = .resizeAspectFill

        boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
        boardLayer.strokeColor = nil
        boardLayer.lineWidth = Self.boardLineWidth

        occupancyLayer.lineWidth = 1

        updateAppearance()
    }

    private func updateLayerFrames() {
        let roundedBounds = bounds.integral
        backgroundLayer.frame = roundedBounds
    }

    private func updateAppearance() {
        PlatformLayerAppearance.performWithoutAnimations {
            backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
            occupancyLayer.fillColor = PlatformLayerAppearance.resolvedCGColor(
                .systemGray,
                for: traitCollection
            )
            occupancyLayer.strokeColor = PlatformLayerAppearance.resolvedCGColor(
                .systemGray2,
                for: traitCollection
            )
            layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
                UIColor.separator.withAlphaComponent(0.75),
                for: traitCollection
            )
            layer.borderWidth = Self.borderWidth
        }
    }

    private func refreshPreview() {
        BoardPreviewRenderer.render(
            content: content,
            viewBounds: bounds,
            contentInset: Self.contentInset,
            imageLayer: imageLayer,
            boardLayer: boardLayer,
            occupancyLayer: occupancyLayer
        )
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
