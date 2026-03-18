#if os(iOS)
import UIKit

final class iOSBoardPreviewView: UIView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var seed: BoardPreviewSeed = .empty

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
        updateAppearance()
    }

    func apply(seed: BoardPreviewSeed) {
        self.seed = seed
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
        layer.addSublayer(occupancyLayer)

        boardLayer.fillColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55).cgColor
        boardLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.75).cgColor
        boardLayer.lineWidth = Self.boardLineWidth

        occupancyLayer.fillColor = UIColor.systemGray.cgColor
        occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
        occupancyLayer.lineWidth = 1

        updateAppearance()
    }

    private func updateLayerFrames() {
        let roundedBounds = bounds.integral
        backgroundLayer.frame = roundedBounds
        boardLayer.frame = roundedBounds
        occupancyLayer.frame = roundedBounds
    }

    private func updateAppearance() {
        backgroundLayer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92).cgColor
        layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
        layer.borderWidth = Self.borderWidth
    }

    private func refreshPreview() {
        let layout = BoardGeometryPreviewLayout(
            seed: seed,
            viewBounds: bounds,
            contentInset: Self.contentInset
        )

        if let boardRect = layout.boardRect {
            boardLayer.path = CGPath(rect: boardRect, transform: nil)
            boardLayer.isHidden = false
        } else {
            boardLayer.path = nil
            boardLayer.isHidden = true
        }

        if layout.nodePaths.isEmpty {
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
            return
        }

        let path = CGMutablePath()
        for nodePath in layout.nodePaths {
            path.addPath(nodePath)
        }
        occupancyLayer.path = path
        occupancyLayer.isHidden = false
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
