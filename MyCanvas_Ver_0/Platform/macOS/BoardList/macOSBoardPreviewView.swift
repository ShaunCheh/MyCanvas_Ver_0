#if os(macOS)
import AppKit

final class macOSBoardPreviewView: NSView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var seed: BoardPreviewSeed = .empty

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        performWithoutLayerActions {
            updateLayerFrames()
            refreshPreview()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func apply(seed: BoardPreviewSeed) {
        self.seed = seed
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(boardLayer)
        layer?.addSublayer(occupancyLayer)

        boardLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        boardLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75).cgColor
        boardLayer.lineWidth = Self.boardLineWidth

        occupancyLayer.fillColor = NSColor.systemGray.cgColor
        occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
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
        backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
        layer?.borderWidth = Self.borderWidth
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
