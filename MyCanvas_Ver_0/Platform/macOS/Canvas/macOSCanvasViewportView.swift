#if os(macOS)
import AppKit

final class macOSCanvasViewportView: NSView {
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
    private static let selectionHandleSize: CGFloat = 10
    private static let cropMaskFillColor = CGColor(gray: 0, alpha: 0.4)
    private static let cropOutlineStrokeColor = CGColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0,
        alpha: 1
    )
    private static let cropHandleFillColor = CGColor(gray: 1, alpha: 1)
    private static let cropOutlineLineWidth: CGFloat = 2
    private static let cropHandleLineWidth: CGFloat = 2
    private static let cropHandleSize: CGFloat = 10

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
    private var snapshot: CanvasRenderSnapshot = .empty
    private var lastPrimaryPointerLocation: CGPoint?
    var onPointerDown: ((CGPoint) -> Void)?
    var onPointerMove: ((CGPoint, CGPoint) -> Void)?
    var onPointerUp: ((CGPoint) -> Void)?
    var onPointerCancel: (() -> Void)?
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?

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
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundAppearance()
        performWithoutLayerActions {
            refreshImageLayers()
            refreshBoardHighlight()
            refreshSelectionOverlay()
            refreshCropOverlay()
        }
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
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(itemsLayer)
        layer?.addSublayer(overlayLayer)
        overlayLayer.addSublayer(boardHighlightLayer)
        overlayLayer.addSublayer(selectionOutlineLayer)
        overlayLayer.addSublayer(cropMaskLayer)
        overlayLayer.addSublayer(cropOutlineLayer)

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

        if cropMaskLayer.frame != bounds {
            cropMaskLayer.frame = bounds
        }

        if cropOutlineLayer.frame != bounds {
            cropOutlineLayer.frame = bounds
        }
    }

    private func updateBackgroundAppearance() {
        backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    private func refreshImageLayers() {
        let incomingIDs = Set(snapshot.items.map(\.id))
        let existingIDs = Set(imageLayers.keys)

        for removedID in existingIDs.subtracting(incomingIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
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
            boardHighlightLayer.frame = .zero
            boardHighlightLayer.isHidden = true
            return
        }

        // Use the same frame-based placement semantics as image layers.
        let boardFrame = boardOverlay.screenRect.standardized
        boardHighlightLayer.frame = boardFrame
        boardHighlightLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: boardFrame.size),
            transform: nil
        )
        boardHighlightLayer.isHidden = false
        boardHighlightLayer.contentsScale = currentContentsScale
    }

    private func refreshSelectionOverlay() {
        guard let selectionOverlay = snapshot.selectionOverlay else {
            hideSelectionOverlay()
            return
        }

        // The viewport owns selection presentation details; it only consumes the
        // renderer's neutral geometry and applies macOS-specific visuals here.
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
        let path = CGMutablePath()
        path.move(to: quad.topLeading)
        path.addLine(to: quad.topTrailing)
        path.addLine(to: quad.bottomTrailing)
        path.addLine(to: quad.bottomLeading)
        path.closeSubpath()
        return path
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

    private func imageLayer(for itemID: CanvasImageItemID) -> CanvasImageLayer {
        if let imageLayer = imageLayers[itemID] {
            return imageLayer
        }

        let imageLayer = CanvasImageLayer(itemID: itemID)
        itemsLayer.addSublayer(imageLayer)
        imageLayers[itemID] = imageLayer
        return imageLayer
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        lastPrimaryPointerLocation = location
        onPointerDown?(location)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        let previousLocation = lastPrimaryPointerLocation ?? currentLocation
        lastPrimaryPointerLocation = currentLocation
        guard currentLocation != previousLocation else {
            return
        }

        onPointerMove?(currentLocation, previousLocation)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        lastPrimaryPointerLocation = nil
        onPointerUp?(location)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        guard delta != .zero else {
            super.scrollWheel(with: event)
            return
        }

        onPan?(delta)
    }

    override func magnify(with event: NSEvent) {
        let scaleDelta = max(0.01, 1 + event.magnification)
        let anchor = convert(event.locationInWindow, from: nil)
        onZoom?(scaleDelta, anchor)
    }
}
#endif
