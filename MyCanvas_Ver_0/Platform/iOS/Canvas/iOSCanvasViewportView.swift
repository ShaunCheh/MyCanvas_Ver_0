#if canImport(UIKit) && !os(watchOS)
import UIKit

final class iOSCanvasViewportView: UIView, UIGestureRecognizerDelegate {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var lastReportedViewportSize: CGSize?
    private var snapshot: CanvasRenderSnapshot = .empty
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onViewportSizeChange: ((CGSize) -> Void)?

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gestureRecognizer.delegate = self
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
        updateLayerFrames()
        reportViewportSizeIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBackgroundAppearance()
        refreshImageLayers()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBackgroundAppearance()
    }

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        updateLayerFrames()
        refreshImageLayers()
    }

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)

        updateBackgroundAppearance()
    }

    private func updateLayerFrames() {
        backgroundLayer.frame = bounds
        itemsLayer.frame = bounds
        overlayLayer.frame = bounds
    }

    private func reportViewportSizeIfNeeded() {
        let viewportSize = bounds.size
        guard viewportSize != lastReportedViewportSize else {
            return
        }

        lastReportedViewportSize = viewportSize
        onViewportSizeChange?(viewportSize)
    }

    private func updateBackgroundAppearance() {
        backgroundLayer.backgroundColor = UIColor.systemBackground.cgColor
    }

    private func refreshImageLayers() {
        let incomingIDs = Set(snapshot.items.map(\.id))
        let existingIDs = Set(imageLayers.keys)

        for removedID in existingIDs.subtracting(incomingIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        let contentsScale = window?.screen.scale ?? UIScreen.main.scale
        for item in snapshot.items {
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(with: item, contentsScale: contentsScale)
        }
    }

    private func imageLayer(for itemID: CanvasImageItemID) -> CanvasImageLayer {
        if let imageLayer = imageLayers[itemID] {
            return imageLayer
        }

        let imageLayer = CanvasImageLayer(itemID: itemID)
        itemsLayer.addSublayer(imageLayer)
        imageLayers[itemID] = imageLayer
        return imageLayer
    }

    @objc
    private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            let translation = gestureRecognizer.translation(in: self)
            guard translation != .zero else {
                return
            }

            onPan?(translation)
            gestureRecognizer.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            let scaleDelta = gestureRecognizer.scale
            guard scaleDelta.isFinite, scaleDelta > 0 else {
                return
            }

            onZoom?(scaleDelta, gestureRecognizer.location(in: self))
            gestureRecognizer.scale = 1
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
