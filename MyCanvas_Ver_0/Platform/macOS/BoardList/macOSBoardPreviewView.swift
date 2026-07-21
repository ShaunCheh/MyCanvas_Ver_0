#if os(macOS)
import AppKit

final class macOSBoardPreviewView: NSView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var content: BoardPreviewContent = .empty

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

    func apply(content: BoardPreviewContent) {
        self.content = content
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
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(occupancyLayer)

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
        let appearance = effectiveAppearance
        performWithoutLayerActions {
            backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
            layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.separatorColor.withAlphaComponent(0.75),
                for: appearance
            )
            layer?.borderWidth = Self.borderWidth
            occupancyLayer.fillColor = PlatformLayerAppearance.resolvedCGColor(
                .systemGray,
                for: appearance
            )
            occupancyLayer.strokeColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.systemGray.withAlphaComponent(0.85),
                for: appearance
            )
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
        PlatformLayerAppearance.performWithoutAnimations(updates)
    }
}
#endif
