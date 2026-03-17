#if os(macOS)
import AppKit

final class macOSCanvasMiniMapView: NSView {
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

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

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
            refreshMiniMap()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
        performWithoutLayerActions {
            refreshMiniMap()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
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
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(boardLayer)
        layer?.addSublayer(occupancyLayer)
        layer?.addSublayer(viewportLayer)

        boardLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        boardLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75).cgColor
        boardLayer.lineWidth = Self.boardLineWidth

        occupancyLayer.fillColor = NSColor.systemGray.cgColor
        occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
        occupancyLayer.lineWidth = 1

        viewportLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
        viewportLayer.strokeColor = NSColor.systemBlue.cgColor
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
        backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
        layer?.borderWidth = Self.borderWidth
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

    override func mouseDown(with event: NSEvent) {
        onNavigate?(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        onNavigate?(convert(event.locationInWindow, from: nil))
    }

    private var currentContentsScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
