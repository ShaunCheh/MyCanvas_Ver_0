#if canImport(UIKit) && !os(watchOS)
import UIKit

final class iOSCanvasMiniMapView: UIView {
    private static let contentInset: CGFloat = 8
    private static let cornerRadius: CGFloat = 12
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5
    private static let viewportLineWidth: CGFloat = 2

    private let backgroundLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private let viewportLayer = CAShapeLayer()
    private var snapshot: CanvasMiniMapSnapshot = .empty
    private var geometry: CanvasMiniMapViewGeometry?
    var onNavigate: ((CGPoint) -> Void)?

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap(_:))
        )
        return gestureRecognizer
    }()

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:))
        )
        return gestureRecognizer
    }()

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
            refreshMiniMap()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAppearance()
        performWithoutLayerActions {
            refreshMiniMap()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    func apply(_ snapshot: CanvasMiniMapSnapshot) {
        self.snapshot = snapshot
        performWithoutLayerActions {
            refreshMiniMap()
        }
    }

    func worldPoint(atMiniMapPoint point: CGPoint) -> CGPoint? {
        guard let geometry else {
            return nil
        }

        return geometry.miniMapToWorld(
            geometry.clampedMiniMapPoint(point)
        )
    }

    var currentContentRect: CGRect {
        geometry?.contentRect ?? .zero
    }

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = true
        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = true
        layer.addSublayer(backgroundLayer)
        layer.addSublayer(boardLayer)
        layer.addSublayer(occupancyLayer)
        layer.addSublayer(viewportLayer)
        tapGestureRecognizer.require(toFail: panGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(panGestureRecognizer)

        boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
        boardLayer.strokeColor = nil
        boardLayer.lineWidth = Self.boardLineWidth

        occupancyLayer.fillColor = UIColor.systemGray.cgColor
        occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
        occupancyLayer.lineWidth = 1

        viewportLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        viewportLayer.strokeColor = UIColor.systemBlue.cgColor
        viewportLayer.lineWidth = Self.viewportLineWidth

        updateAppearance()
    }

    private func updateLayerFrames() {
        let roundedBounds = bounds.integral
        if backgroundLayer.frame != roundedBounds {
            backgroundLayer.frame = roundedBounds
        }

        if boardLayer.frame != roundedBounds {
            boardLayer.frame = roundedBounds
        }

        if occupancyLayer.frame != roundedBounds {
            occupancyLayer.frame = roundedBounds
        }

        if viewportLayer.frame != roundedBounds {
            viewportLayer.frame = roundedBounds
        }
    }

    private func updateAppearance() {
        backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
        layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
        layer.borderWidth = Self.borderWidth
    }

    private func refreshMiniMap() {
        geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: bounds,
            contentInset: Self.contentInset
        )
        guard let geometry else {
            hideAllContentLayers()
            return
        }

        let contentsScale = currentContentsScale
        refreshBoardLayer(using: geometry, contentsScale: contentsScale)
        refreshOccupancyLayer(using: geometry, contentsScale: contentsScale)
        refreshViewportLayer(using: geometry, contentsScale: contentsScale)
    }

    private func refreshBoardLayer(
        using geometry: CanvasMiniMapViewGeometry,
        contentsScale: CGFloat
    ) {
        let boardRect = geometry.worldToMiniMap(snapshot.boardWorldRect)
        guard boardRect.width > 0, boardRect.height > 0 else {
            boardLayer.path = nil
            boardLayer.isHidden = true
            return
        }

        boardLayer.path = CGPath(rect: boardRect, transform: nil)
        boardLayer.isHidden = false
        boardLayer.contentsScale = contentsScale
    }

    private func refreshOccupancyLayer(
        using geometry: CanvasMiniMapViewGeometry,
        contentsScale: CGFloat
    ) {
        guard snapshot.nodes.isEmpty == false else {
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
            return
        }

        let path = CGMutablePath()
        for node in snapshot.nodes {
            path.addPath(
                geometry.worldToMiniMap(node.worldQuad).cgPath
            )
        }

        occupancyLayer.path = path
        occupancyLayer.isHidden = false
        occupancyLayer.contentsScale = contentsScale
    }

    private func refreshViewportLayer(
        using geometry: CanvasMiniMapViewGeometry,
        contentsScale: CGFloat
    ) {
        let viewportRect = geometry.worldToMiniMap(snapshot.visibleWorldRect)
        guard viewportRect.width > 0, viewportRect.height > 0 else {
            viewportLayer.path = nil
            viewportLayer.isHidden = true
            return
        }

        viewportLayer.path = CGPath(rect: viewportRect, transform: nil)
        viewportLayer.isHidden = false
        viewportLayer.contentsScale = contentsScale
    }

    private func hideAllContentLayers() {
        boardLayer.path = nil
        boardLayer.isHidden = true
        occupancyLayer.path = nil
        occupancyLayer.isHidden = true
        viewportLayer.path = nil
        viewportLayer.isHidden = true
    }

    @objc
    private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else {
            return
        }

        onNavigate?(gestureRecognizer.location(in: self))
    }

    @objc
    private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            onNavigate?(gestureRecognizer.location(in: self))
        default:
            break
        }
    }

    private var currentContentsScale: CGFloat {
        window?.screen.scale ?? UIScreen.main.scale
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
