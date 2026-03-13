#if canImport(UIKit) && !os(watchOS)
import UIKit

final class iOSCanvasViewportView: UIView {
    private enum TouchInteractionState {
        case idle
        case singleFingerPan(trackedTouch: UITouch, lastLocation: CGPoint)
        case awaitingPinch
        case pinching
    }

    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var lastReportedViewportSize: CGSize?
    private var snapshot: CanvasRenderSnapshot = .empty
    private var interactionState: TouchInteractionState = .idle
    private var activeTouchesByID: [ObjectIdentifier: UITouch] = [:]
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onViewportSizeChange: ((CGSize) -> Void)?

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gestureRecognizer.cancelsTouchesInView = false
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
        }
        reportViewportSizeIfNeeded()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        registerActiveTouches(touches)
        reconcileTouchInteractionState()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        registerActiveTouches(touches)

        guard !isPinchGestureActive else {
            interactionState = .pinching
            return
        }

        switch interactionState {
        case let .singleFingerPan(trackedTouch, lastLocation):
            guard activeTouchCount == 1 else {
                interactionState = .awaitingPinch
                return
            }

            guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
                return
            }

            let currentLocation = currentTouch.location(in: self)
            interactionState = .singleFingerPan(
                trackedTouch: trackedTouch,
                lastLocation: currentLocation
            )

            let translation = CGPoint(
                x: currentLocation.x - lastLocation.x,
                y: currentLocation.y - lastLocation.y
            )
            guard translation != .zero else {
                return
            }

            onPan?(translation)
        case .idle, .awaitingPinch, .pinching:
            reconcileTouchInteractionState()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        unregisterActiveTouches(touches)

        guard !isPinchGestureActive else {
            interactionState = .pinching
            return
        }

        reconcileTouchInteractionState()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        activeTouchesByID.removeAll()
        interactionState = .idle
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBackgroundAppearance()
        performWithoutLayerActions {
            refreshImageLayers()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBackgroundAppearance()
    }

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        performWithoutLayerActions {
            updateLayerFrames()
            refreshImageLayers()
        }
    }

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true
        isMultipleTouchEnabled = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)
        addGestureRecognizer(pinchGestureRecognizer)

        updateBackgroundAppearance()
    }

    private func updateLayerFrames() {
        if backgroundLayer.frame != bounds {
            backgroundLayer.frame = bounds
        }

        if itemsLayer.frame != bounds {
            itemsLayer.frame = bounds
        }

        if overlayLayer.frame != bounds {
            overlayLayer.frame = bounds
        }
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

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
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

    private func registerActiveTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            activeTouchesByID[ObjectIdentifier(touch)] = touch
        }
    }

    private func unregisterActiveTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            activeTouchesByID.removeValue(forKey: ObjectIdentifier(touch))
        }
    }

    private func reconcileTouchInteractionState() {
        guard !isPinchGestureActive else {
            interactionState = .pinching
            return
        }

        switch activeTouchCount {
        case 0:
            interactionState = .idle
        case 1:
            guard let touch = soleActiveTouch else {
                interactionState = .idle
                return
            }

            beginSingleFingerPan(with: touch)
        default:
            interactionState = .awaitingPinch
        }
    }

    private func beginSingleFingerPan(with touch: UITouch) {
        interactionState = .singleFingerPan(
            trackedTouch: touch,
            lastLocation: touch.location(in: self)
        )
    }

    private func touchMatching(_ trackedTouch: UITouch, in touches: Set<UITouch>) -> UITouch? {
        touches.first(where: { $0 === trackedTouch })
    }

    private var activeTouchCount: Int {
        activeTouchesByID.count
    }

    private var soleActiveTouch: UITouch? {
        guard activeTouchesByID.count == 1 else {
            return nil
        }

        return activeTouchesByID.values.first
    }

    private var isPinchGestureActive: Bool {
        switch pinchGestureRecognizer.state {
        case .began, .changed:
            true
        default:
            false
        }
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            interactionState = .pinching

            let scaleDelta = gestureRecognizer.scale
            guard scaleDelta.isFinite, scaleDelta > 0 else {
                return
            }

            onZoom?(scaleDelta, gestureRecognizer.location(in: self))
            gestureRecognizer.scale = 1
        case .ended, .cancelled, .failed:
            reconcileTouchInteractionState()
        default:
            break
        }
    }
}
#endif
