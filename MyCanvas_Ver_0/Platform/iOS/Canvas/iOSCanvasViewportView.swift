#if canImport(UIKit) && !os(watchOS)
import UIKit

final class iOSCanvasViewportView: UIView {
    private static let boardStrokeColor = CGColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0,
        alpha: 0.9
    )
    private static let selectionStrokeColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    private static let selectionHandleFillColor = CGColor(gray: 1, alpha: 1)
    private static let selectionOutlineLineWidth: CGFloat = 2
    private static let selectionHandleLineWidth: CGFloat = 2
    private static let selectionHandleSize: CGFloat = 12
    private static let cropMaskFillColor = UIColor.black.withAlphaComponent(0.4).cgColor
    private static let cropOutlineStrokeColor = CGColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0,
        alpha: 1
    )
    private static let cropHandleFillColor = CGColor(gray: 1, alpha: 1)
    private static let cropOutlineLineWidth: CGFloat = 2
    private static let cropHandleLineWidth: CGFloat = 2
    private static let cropHandleSize: CGFloat = 12

    private enum TouchInteractionState {
        case idle
        case trackingPrimaryPointer(trackedTouch: UITouch, lastLocation: CGPoint)
        case awaitingPinch
        case pinching
    }

    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private let boardHighlightLayer = CAShapeLayer()
    private let selectionOutlineLayer = CAShapeLayer()
    private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
    private let cropMaskLayer = CAShapeLayer()
    private let cropOutlineLayer = CAShapeLayer()
    private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var lastReportedViewportSize: CGSize?
    private var snapshot: CanvasRenderSnapshot = .empty
    private var interactionState: TouchInteractionState = .idle
    private var activeTouchesByID: [ObjectIdentifier: UITouch] = [:]
    var onPointerDown: ((CGPoint) -> Void)?
    var onPointerMove: ((CGPoint, CGPoint) -> Void)?
    var onPointerUp: ((CGPoint) -> Void)?
    var onPointerCancel: (() -> Void)?
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
            cancelPrimaryPointerIfNeeded()
            interactionState = .pinching
            return
        }

        switch interactionState {
        case let .trackingPrimaryPointer(trackedTouch, lastLocation):
            guard activeTouchCount == 1 else {
                cancelPrimaryPointerIfNeeded()
                interactionState = .awaitingPinch
                return
            }

            guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
                return
            }

            let currentLocation = currentTouch.location(in: self)
            interactionState = .trackingPrimaryPointer(
                trackedTouch: trackedTouch,
                lastLocation: currentLocation
            )

            guard currentLocation != lastLocation else {
                return
            }

            onPointerMove?(currentLocation, lastLocation)
        case .idle, .awaitingPinch, .pinching:
            reconcileTouchInteractionState()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let pointerUpLocation = trackedPointerLocation(in: touches)
        unregisterActiveTouches(touches)

        guard !isPinchGestureActive else {
            interactionState = .pinching
            return
        }

        if let pointerUpLocation {
            onPointerUp?(pointerUpLocation)
        }

        reconcileTouchInteractionState()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        cancelPrimaryPointerIfNeeded()
        activeTouchesByID.removeAll()
        interactionState = .idle
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBackgroundAppearance()
        performWithoutLayerActions {
            refreshImageLayers()
            refreshBoardHighlight()
            refreshSelectionOverlay()
            refreshCropOverlay()
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
            refreshBoardHighlight()
            refreshSelectionOverlay()
            refreshCropOverlay()
        }
    }

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true
        isMultipleTouchEnabled = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)
        overlayLayer.addSublayer(boardHighlightLayer)
        overlayLayer.addSublayer(selectionOutlineLayer)
        overlayLayer.addSublayer(cropMaskLayer)
        overlayLayer.addSublayer(cropOutlineLayer)
        addGestureRecognizer(pinchGestureRecognizer)

        configureBoardHighlightLayer()
        configureSelectionOutlineLayer()
        configureSelectionHandleLayers()
        configureCropMaskLayer()
        configureCropOutlineLayer()
        configureCropHandleLayers()
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

        if boardHighlightLayer.frame != bounds {
            boardHighlightLayer.frame = bounds
        }

        if cropMaskLayer.frame != bounds {
            cropMaskLayer.frame = bounds
        }

        if cropOutlineLayer.frame != bounds {
            cropOutlineLayer.frame = bounds
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

    private func configureBoardHighlightLayer() {
        boardHighlightLayer.fillColor = nil
        boardHighlightLayer.strokeColor = Self.boardStrokeColor
        boardHighlightLayer.lineWidth = 2
        boardHighlightLayer.lineDashPattern = [10, 6]
        boardHighlightLayer.isHidden = true
    }

    private func configureSelectionOutlineLayer() {
        selectionOutlineLayer.fillColor = nil
        selectionOutlineLayer.strokeColor = Self.selectionStrokeColor
        selectionOutlineLayer.lineWidth = Self.selectionOutlineLineWidth
        selectionOutlineLayer.isHidden = true
    }

    private func configureSelectionHandleLayers() {
        for role in CanvasSelectionHandleRole.allCases {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = Self.selectionHandleFillColor
            handleLayer.strokeColor = Self.selectionStrokeColor
            handleLayer.lineWidth = Self.selectionHandleLineWidth
            handleLayer.isHidden = true
            overlayLayer.addSublayer(handleLayer)
            selectionHandleLayers[role] = handleLayer
        }
    }

    private func configureCropMaskLayer() {
        cropMaskLayer.fillColor = Self.cropMaskFillColor
        cropMaskLayer.fillRule = .evenOdd
        cropMaskLayer.isHidden = true
    }

    private func configureCropOutlineLayer() {
        cropOutlineLayer.fillColor = nil
        cropOutlineLayer.strokeColor = Self.cropOutlineStrokeColor
        cropOutlineLayer.lineWidth = Self.cropOutlineLineWidth
        cropOutlineLayer.isHidden = true
    }

    private func configureCropHandleLayers() {
        for role in CanvasCropHandleRole.allCases {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = Self.cropHandleFillColor
            handleLayer.strokeColor = Self.cropOutlineStrokeColor
            handleLayer.lineWidth = Self.cropHandleLineWidth
            handleLayer.isHidden = true
            overlayLayer.addSublayer(handleLayer)
            cropHandleLayers[role] = handleLayer
        }
    }

    private func refreshBoardHighlight() {
        guard let boardOverlay = snapshot.boardOverlay else {
            boardHighlightLayer.path = nil
            boardHighlightLayer.isHidden = true
            return
        }

        boardHighlightLayer.path = CGPath(rect: boardOverlay.screenRect, transform: nil)
        boardHighlightLayer.isHidden = false
        boardHighlightLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
    }

    private func refreshSelectionOverlay() {
        guard let selectionOverlay = snapshot.selectionOverlay else {
            hideSelectionOverlay()
            return
        }

        // The viewport owns selection presentation details; it only consumes the
        // renderer's neutral geometry and applies iOS-specific visuals here.
        let selectionFrame = selectionOverlay.screenFrame.standardized
        selectionOutlineLayer.frame = selectionFrame
        selectionOutlineLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: selectionFrame.size),
            transform: nil
        )
        selectionOutlineLayer.isHidden = false
        selectionOutlineLayer.contentsScale = currentContentsScale

        for role in CanvasSelectionHandleRole.allCases {
            guard
                let handleLayer = selectionHandleLayers[role],
                let handle = selectionOverlay.handles.first(where: { $0.role == role })
            else {
                selectionHandleLayers[role]?.path = nil
                selectionHandleLayers[role]?.frame = .zero
                selectionHandleLayers[role]?.isHidden = true
                continue
            }

            let handleRect = Self.selectionHandleRect(centeredAt: handle.screenCenter)
            handleLayer.frame = handleRect
            handleLayer.path = CGPath(
                rect: CGRect(origin: .zero, size: handleRect.size),
                transform: nil
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }
    }

    private func refreshCropOverlay() {
        guard let cropOverlay = snapshot.cropOverlay else {
            hideCropOverlay()
            return
        }

        // Crop chrome stays platform-owned; shared renderer only provides the
        // full-image and crop quads needed to dim, outline, and hit-test here.
        let maskPath = CGMutablePath()
        maskPath.addPath(Self.quadPath(for: cropOverlay.fullImageScreenQuad))
        maskPath.addPath(Self.quadPath(for: cropOverlay.cropScreenQuad))
        cropMaskLayer.path = maskPath
        cropMaskLayer.isHidden = false
        cropMaskLayer.contentsScale = currentContentsScale

        cropOutlineLayer.path = Self.quadPath(for: cropOverlay.cropScreenQuad)
        cropOutlineLayer.isHidden = false
        cropOutlineLayer.contentsScale = currentContentsScale

        for role in CanvasCropHandleRole.allCases {
            guard
                let handleLayer = cropHandleLayers[role],
                let handle = cropOverlay.handles.first(where: { $0.role == role })
            else {
                cropHandleLayers[role]?.path = nil
                cropHandleLayers[role]?.frame = .zero
                cropHandleLayers[role]?.isHidden = true
                continue
            }

            let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
            handleLayer.frame = handleRect
            handleLayer.path = CGPath(
                rect: CGRect(origin: .zero, size: handleRect.size),
                transform: nil
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }
    }

    private func hideSelectionOverlay() {
        selectionOutlineLayer.path = nil
        selectionOutlineLayer.frame = .zero
        selectionOutlineLayer.isHidden = true

        for handleLayer in selectionHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }
    }

    private func hideCropOverlay() {
        cropMaskLayer.path = nil
        cropMaskLayer.isHidden = true
        cropOutlineLayer.path = nil
        cropOutlineLayer.isHidden = true

        for handleLayer in cropHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }
    }

    private static func selectionHandleRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - selectionHandleSize / 2,
            y: center.y - selectionHandleSize / 2,
            width: selectionHandleSize,
            height: selectionHandleSize
        ).standardized
    }

    private static func cropHandleRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - cropHandleSize / 2,
            y: center.y - cropHandleSize / 2,
            width: cropHandleSize,
            height: cropHandleSize
        ).standardized
    }

    private static func quadPath(for quad: CanvasQuad) -> CGPath {
        let path = UIBezierPath()
        path.move(to: quad.topLeading)
        path.addLine(to: quad.topTrailing)
        path.addLine(to: quad.bottomTrailing)
        path.addLine(to: quad.bottomLeading)
        path.close()
        return path.cgPath
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
            cancelPrimaryPointerIfNeeded()
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

            if case let .trackingPrimaryPointer(trackedTouch, _) = interactionState, trackedTouch === touch {
                return
            }

            beginPrimaryPointerTracking(with: touch)
        default:
            cancelPrimaryPointerIfNeeded()
            interactionState = .awaitingPinch
        }
    }

    private func beginPrimaryPointerTracking(with touch: UITouch) {
        let location = touch.location(in: self)
        interactionState = .trackingPrimaryPointer(
            trackedTouch: touch,
            lastLocation: location
        )
        onPointerDown?(location)
    }

    private func touchMatching(_ trackedTouch: UITouch, in touches: Set<UITouch>) -> UITouch? {
        touches.first(where: { $0 === trackedTouch })
    }

    private func trackedPointerLocation(in touches: Set<UITouch>) -> CGPoint? {
        guard
            case let .trackingPrimaryPointer(trackedTouch, _) = interactionState,
            let touch = touchMatching(trackedTouch, in: touches)
        else {
            return nil
        }

        return touch.location(in: self)
    }

    private func cancelPrimaryPointerIfNeeded() {
        guard case .trackingPrimaryPointer = interactionState else {
            return
        }

        onPointerCancel?()
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
            cancelPrimaryPointerIfNeeded()
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
