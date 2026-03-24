#if os(macOS)
import AppKit

final class macOSCanvasViewportView: NSView {
    private static let workspaceBackgroundColor = CanvasWorkspacePalette.backgroundColor
    private static let workspaceMinorGridStrokeColor = CanvasWorkspacePalette.minorGridStrokeColor
    private static let workspaceMajorGridStrokeColor = CanvasWorkspacePalette.majorGridStrokeColor
    private static let workspaceMinorGridLineWidth: CGFloat = 1
    private static let workspaceMajorGridLineWidth: CGFloat = 1
    private static let boardSurfaceFillColor = CanvasWorkspacePalette.boardSurfaceFillColor
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
    private static let rotateGuideLineWidth: CGFloat = 2
    private static let rotateHandleLineWidth: CGFloat = 2
    private static let rotateHandleSize: CGFloat = 12
    private static let rotationTextFontSize: CGFloat = 12
    private static let rotationTextHorizontalPadding: CGFloat = 8
    private static let rotationTextVerticalPadding: CGFloat = 4
    private static let rotationTextCornerRadius: CGFloat = 8
    private static let importDragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .tiff
    ]

    private let backgroundLayer = CALayer()
    private let workspaceGridLayer = CALayer()
    private let workspaceMinorGridLayer = CAShapeLayer()
    private let workspaceMajorGridLayer = CAShapeLayer()
    private let boardSurfaceLayer = CAShapeLayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private let selectionOutlineLayer = CAShapeLayer()
    private let interactionOverlayLayer = CALayer()
    private let rotationRingLayer = CAShapeLayer()
    private let rotationTickLayer = CAShapeLayer()
    private let rotationPointerLayer = CAShapeLayer()
    private let rotationTextBackgroundLayer = CAShapeLayer()
    private let rotationTextLayer = CATextLayer()
    private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
    private let cropMaskLayer = CAShapeLayer()
    private let cropOutlineLayer = CAShapeLayer()
    private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
    private let rotateGuideLayer = CAShapeLayer()
    private let rotateHandleLayer = CAShapeLayer()
    private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
    private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]
    private var lastReportedViewportSize: CGSize?
    private var snapshot: CanvasRenderSnapshot = .empty
    private var lastPrimaryPointerLocation: CGPoint?
    private lazy var animatedPlaybackRegistry = CanvasGIFPlaybackRegistry { [weak self] assetReference in
        self?.resolveAnimatedImagePlaybackSource?(assetReference)
    }
    private var animatedPlaybackObservers: [NSObjectProtocol] = []
    private var isApplicationPlaybackActive = NSApplication.shared.isActive
    var onPointerDown: ((CGPoint) -> Void)?
    var onPointerMove: ((CGPoint, CGPoint) -> Void)?
    var onPointerUp: ((CGPoint) -> Void)?
    var onPointerCancel: (() -> Void)?
    var onSecondaryClick: ((CGPoint) -> Void)?
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onViewportSizeChange: ((CGSize) -> Void)?
    var onImportDragOperation: ((CGPoint, NSPasteboard) -> NSDragOperation)?
    var onImportDrop: ((CGPoint, NSPasteboard) -> Bool)?
    var resolveAnimatedImagePlaybackSource: ((CanvasImageAssetReference) -> CanvasAnimatedImagePlaybackSource?)?
    var shouldAutoplayAnimatedImages = true {
        didSet {
            updateAnimatedPlaybackState()
        }
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupAnimatedPlaybackLifecycle()
        registerForDraggedTypes(Self.importDragTypes)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        removeAnimatedPlaybackObservers()
        animatedPlaybackRegistry.invalidate()
    }

    override func layout() {
        super.layout()
        print(
            "[Canvas macOS][ViewportLifecycle] " +
            "action=layout " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame)) " +
            "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
        )
        performWithoutLayerActions {
            updateLayerFrames()
        }
        reportViewportSizeIfNeeded()
        updateAnimatedPlaybackState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        print(
            "[Canvas macOS][ViewportLifecycle] " +
            "action=viewDidMoveToWindow " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame)) " +
            "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
        )
        updateBackgroundAppearance()
        performWithoutLayerActions {
            refreshItemLayers()
            refreshWorkspaceChrome()
            refreshEditOverlay()
            refreshInteractionOverlay()
        }
    }

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        print(
            "[Canvas macOS][ViewportApply] " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame)) " +
            "snapshotViewportBounds=\(macOSViewportDescribe(snapshot.viewportBounds)) " +
            "snapshotVisibleWorldRect=\(macOSViewportDescribe(snapshot.visibleWorldRect)) " +
            "snapshotItems=\(snapshot.items.count) " +
            "editOverlay=\(macOSViewportDescribe(snapshot.editOverlay))"
        )
        performWithoutLayerActions {
            updateLayerFrames()
            refreshItemLayers()
            refreshWorkspaceChrome()
            refreshEditOverlay()
            refreshInteractionOverlay()
        }
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(workspaceGridLayer)
        workspaceGridLayer.addSublayer(workspaceMinorGridLayer)
        workspaceGridLayer.addSublayer(workspaceMajorGridLayer)
        layer?.addSublayer(boardSurfaceLayer)
        layer?.addSublayer(itemsLayer)
        layer?.addSublayer(overlayLayer)
        overlayLayer.addSublayer(selectionOutlineLayer)
        overlayLayer.addSublayer(interactionOverlayLayer)
        overlayLayer.addSublayer(cropMaskLayer)
        overlayLayer.addSublayer(cropOutlineLayer)
        overlayLayer.addSublayer(rotateGuideLayer)
        overlayLayer.addSublayer(rotateHandleLayer)
        interactionOverlayLayer.addSublayer(rotationRingLayer)
        interactionOverlayLayer.addSublayer(rotationTickLayer)
        interactionOverlayLayer.addSublayer(rotationPointerLayer)
        interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
        interactionOverlayLayer.addSublayer(rotationTextLayer)

        configureWorkspaceGridLayers()
        configureBoardSurfaceLayer()
        configureSelectionOutlineLayer()
        configureInteractionOverlayLayer()
        configureRotationRingLayer()
        configureRotationTickLayer()
        configureRotationPointerLayer()
        configureRotationTextBackgroundLayer()
        configureRotationTextLayer()
        configureSelectionHandleLayers()
        configureCropMaskLayer()
        configureCropOutlineLayer()
        configureCropHandleLayers()
        configureRotateGuideLayer()
        configureRotateHandleLayer()
        updateBackgroundAppearance()
    }

    private func updateLayerFrames() {
        if backgroundLayer.frame != bounds {
            backgroundLayer.frame = bounds
        }

        if workspaceGridLayer.frame != bounds {
            workspaceGridLayer.frame = bounds
        }

        if workspaceMinorGridLayer.frame != bounds {
            workspaceMinorGridLayer.frame = bounds
        }

        if workspaceMajorGridLayer.frame != bounds {
            workspaceMajorGridLayer.frame = bounds
        }

        if boardSurfaceLayer.frame != bounds {
            boardSurfaceLayer.frame = bounds
        }

        if itemsLayer.frame != bounds {
            itemsLayer.frame = bounds
        }

        if overlayLayer.frame != bounds {
            overlayLayer.frame = bounds
        }

        if selectionOutlineLayer.frame != bounds {
            selectionOutlineLayer.frame = bounds
        }

        if interactionOverlayLayer.frame != bounds {
            interactionOverlayLayer.frame = bounds
        }

        if cropMaskLayer.frame != bounds {
            cropMaskLayer.frame = bounds
        }

        if cropOutlineLayer.frame != bounds {
            cropOutlineLayer.frame = bounds
        }

        if rotateGuideLayer.frame != bounds {
            rotateGuideLayer.frame = bounds
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
        backgroundLayer.backgroundColor = Self.workspaceBackgroundColor
    }

    private func refreshItemLayers() {
        let incomingImageIDs = Set(
            snapshot.items.compactMap { item in
                if case .image = item.payload {
                    return item.id
                }

                return nil
            }
        )
        let incomingTextIDs = Set(
            snapshot.items.compactMap { item in
                if case .text = item.payload {
                    return item.id
                }

                return nil
            }
        )
        let existingImageIDs = Set(imageLayers.keys)
        let existingTextIDs = Set(textLayers.keys)

        for removedID in existingImageIDs.subtracting(incomingImageIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        for removedID in existingTextIDs.subtracting(incomingTextIDs) {
            textLayers[removedID]?.removeFromSuperlayer()
            textLayers[removedID] = nil
        }

        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var animatedBindings: [CanvasAnimatedImagePlaybackBinding] = []
        for item in snapshot.items {
            switch item.payload {
            case let .image(imagePayload):
                let imageLayer = imageLayer(for: item.id)
                refreshImageLayer(
                    imageLayer,
                    with: item,
                    imagePayload: imagePayload,
                    contentsScale: contentsScale
                )
                if imagePayload.displayContract.isAnimatedAsset {
                    animatedBindings.append(
                        CanvasAnimatedImagePlaybackBinding(
                            itemID: item.id,
                            displayContract: imagePayload.displayContract,
                            layer: imageLayer
                        )
                    )
                }
            case let .text(textPayload):
                let textLayer = textLayer(for: item.id)
                textLayer.update(
                    with: item,
                    textPayload: textPayload,
                    contentsScale: contentsScale
                )
            }
        }

        animatedPlaybackRegistry.reconcileVisibleBindings(animatedBindings)
        updateAnimatedPlaybackState()
    }

    private func refreshImageLayer(
        _ imageLayer: CanvasImageLayer,
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        if imagePayload.displayContract.isAnimatedAsset {
            refreshAnimatedImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        } else {
            refreshStaticImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        }
    }

    private func refreshStaticImageLayer(
        _ imageLayer: CanvasImageLayer,
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        imageLayer.updateStaticPresentation(
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    }

    private func refreshAnimatedImageLayer(
        _ imageLayer: CanvasImageLayer,
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        // Stage 4 splits animated-image reconciliation away from static-image
        // poster drawing so a later playback controller can own frame updates
        // without forcing the viewport to rebuild its item refresh flow.
        imageLayer.updateAnimatedPresentation(
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    }

    private func configureWorkspaceGridLayers() {
        workspaceGridLayer.masksToBounds = true

        workspaceMinorGridLayer.fillColor = nil
        workspaceMinorGridLayer.strokeColor = Self.workspaceMinorGridStrokeColor
        workspaceMinorGridLayer.lineWidth = Self.workspaceMinorGridLineWidth
        workspaceMinorGridLayer.isHidden = true

        workspaceMajorGridLayer.fillColor = nil
        workspaceMajorGridLayer.strokeColor = Self.workspaceMajorGridStrokeColor
        workspaceMajorGridLayer.lineWidth = Self.workspaceMajorGridLineWidth
        workspaceMajorGridLayer.isHidden = true
    }

    private func configureBoardSurfaceLayer() {
        boardSurfaceLayer.fillColor = Self.boardSurfaceFillColor
        boardSurfaceLayer.strokeColor = nil
        boardSurfaceLayer.isHidden = true
    }

    private func configureSelectionOutlineLayer() {
        selectionOutlineLayer.fillColor = nil
        selectionOutlineLayer.strokeColor = Self.selectionStrokeColor
        selectionOutlineLayer.lineWidth = Self.selectionOutlineLineWidth
        selectionOutlineLayer.isHidden = true
    }

    private func configureInteractionOverlayLayer() {
        interactionOverlayLayer.isHidden = true
    }

    private func configureRotationRingLayer() {
        rotationRingLayer.fillColor = nil
        rotationRingLayer.strokeColor = Self.selectionStrokeColor
        rotationRingLayer.lineWidth = Self.selectionOutlineLineWidth
        rotationRingLayer.isHidden = true
    }

    private func configureRotationTickLayer() {
        rotationTickLayer.fillColor = nil
        rotationTickLayer.strokeColor = Self.selectionStrokeColor
        rotationTickLayer.lineWidth = Self.rotateGuideLineWidth
        rotationTickLayer.lineCap = .round
        rotationTickLayer.isHidden = true
    }

    private func configureRotationPointerLayer() {
        rotationPointerLayer.fillColor = nil
        rotationPointerLayer.strokeColor = Self.selectionStrokeColor
        rotationPointerLayer.lineWidth = Self.rotateGuideLineWidth
        rotationPointerLayer.lineCap = .round
        rotationPointerLayer.isHidden = true
    }

    private func configureRotationTextBackgroundLayer() {
        rotationTextBackgroundLayer.fillColor = Self.selectionHandleFillColor
        rotationTextBackgroundLayer.strokeColor = Self.selectionStrokeColor
        rotationTextBackgroundLayer.lineWidth = Self.selectionHandleLineWidth
        rotationTextBackgroundLayer.isHidden = true
    }

    private func configureRotationTextLayer() {
        rotationTextLayer.alignmentMode = .center
        rotationTextLayer.contentsScale = currentContentsScale
        rotationTextLayer.isWrapped = false
        rotationTextLayer.isHidden = true
        rotationTextLayer.truncationMode = .none
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

    private func configureRotateGuideLayer() {
        rotateGuideLayer.fillColor = nil
        rotateGuideLayer.strokeColor = Self.selectionStrokeColor
        rotateGuideLayer.lineWidth = Self.rotateGuideLineWidth
        rotateGuideLayer.lineCap = .round
        rotateGuideLayer.isHidden = true
    }

    private func configureRotateHandleLayer() {
        rotateHandleLayer.fillColor = Self.selectionHandleFillColor
        rotateHandleLayer.strokeColor = Self.selectionStrokeColor
        rotateHandleLayer.lineWidth = Self.rotateHandleLineWidth
        rotateHandleLayer.isHidden = true
    }

    private func refreshWorkspaceChrome() {
        guard let workspaceOverlay = snapshot.workspaceOverlay else {
            hideWorkspaceChrome()
            return
        }

        let boardSurfaceRect = workspaceOverlay.boardSurfaceScreenRect.standardized
        if boardSurfaceRect.width > 0, boardSurfaceRect.height > 0 {
            boardSurfaceLayer.path = CGPath(
                rect: boardSurfaceRect,
                transform: nil
            )
            boardSurfaceLayer.isHidden = false
            boardSurfaceLayer.contentsScale = currentContentsScale
        } else {
            boardSurfaceLayer.path = nil
            boardSurfaceLayer.isHidden = true
        }

        if workspaceOverlay.minorGridSegments.isEmpty {
            workspaceMinorGridLayer.path = nil
            workspaceMinorGridLayer.isHidden = true
        } else {
            workspaceMinorGridLayer.path = Self.workspaceGridPath(
                workspaceOverlay.minorGridSegments
            )
            workspaceMinorGridLayer.isHidden = false
            workspaceMinorGridLayer.contentsScale = currentContentsScale
        }

        if workspaceOverlay.majorGridSegments.isEmpty {
            workspaceMajorGridLayer.path = nil
            workspaceMajorGridLayer.isHidden = true
        } else {
            workspaceMajorGridLayer.path = Self.workspaceGridPath(
                workspaceOverlay.majorGridSegments
            )
            workspaceMajorGridLayer.isHidden = false
            workspaceMajorGridLayer.contentsScale = currentContentsScale
        }

        workspaceGridLayer.isHidden = workspaceOverlay.minorGridSegments.isEmpty &&
            workspaceOverlay.majorGridSegments.isEmpty
    }

    private func hideWorkspaceChrome() {
        workspaceGridLayer.isHidden = true

        workspaceMinorGridLayer.path = nil
        workspaceMinorGridLayer.isHidden = true

        workspaceMajorGridLayer.path = nil
        workspaceMajorGridLayer.isHidden = true

        boardSurfaceLayer.path = nil
        boardSurfaceLayer.isHidden = true
    }

    private static func workspaceGridPath(
        _ segments: [CanvasWorkspaceGridLineSegment]
    ) -> CGPath {
        let path = CGMutablePath()

        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }

        return path
    }

    private static func lineSegmentsPath(
        _ segments: [CanvasInteractionLineSegment]
    ) -> CGPath {
        let path = CGMutablePath()

        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }

        return path
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

    private static func rotationAttributedText(
        for payload: CanvasRotationInteractionOverlayPayload
    ) -> NSAttributedString {
        let degrees = Int(payload.displayDegrees0To360.rounded())
        let displayDegrees = degrees == 360 ? 360 : max(0, degrees)
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: rotationTextFontSize,
            weight: .semibold
        )
        let textColor = NSColor(cgColor: selectionStrokeColor) ?? .controlAccentColor

        return NSAttributedString(
            string: "\(displayDegrees)\u{00B0}",
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
    }

    private func refreshEditOverlay() {
        guard let editOverlay = snapshot.editOverlay else {
            hideEditOverlay()
            return
        }

        switch editOverlay.kind {
        case .selection:
            refreshSelectionChrome(from: editOverlay)
            hideCropOverlay()
        case .crop:
            hideSelectionOverlay()
            refreshCropChrome(from: editOverlay)
        }
    }

    private func refreshInteractionOverlay() {
        guard let interactionOverlay = snapshot.interactionOverlay else {
            hideInteractionOverlay()
            return
        }

        switch interactionOverlay.kind {
        case .rotation:
            refreshRotationInteractionOverlay(from: interactionOverlay)
        }
    }

    private func refreshCropChrome(
        from editOverlay: CanvasEditRenderOverlay
    ) {
        guard case let .crop(payload) = editOverlay.payload else {
            hideCropOverlay()
            return
        }

        // Crop now shares the same editOverlay entry point as selection/rotate;
        // the viewport still owns mask styling, handle size, and layer setup.
        let maskPath = CGMutablePath()
        maskPath.addPath(Self.quadPath(for: payload.fullImageScreenQuad))
        maskPath.addPath(Self.quadPath(for: payload.cropScreenQuad))
        cropMaskLayer.path = maskPath
        cropMaskLayer.isHidden = false
        cropMaskLayer.contentsScale = currentContentsScale

        cropOutlineLayer.path = Self.quadPath(for: payload.cropScreenQuad)
        cropOutlineLayer.isHidden = false
        cropOutlineLayer.contentsScale = currentContentsScale

        for role in CanvasCropHandleRole.allCases {
            guard
                let handleLayer = cropHandleLayers[role],
                let handle = editOverlay.handles.first(where: {
                    $0.role == role.editHandleRole
                })
            else {
                cropHandleLayers[role]?.path = nil
                cropHandleLayers[role]?.frame = .zero
                cropHandleLayers[role]?.isHidden = true
                continue
            }

            handleLayer.frame = bounds
            handleLayer.path = Self.cropHandlePath(
                centeredAt: handle.screenCenter,
                rotationRadians: handle.screenRotationRadians
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }
    }

    private func refreshSelectionChrome(
        from editOverlay: CanvasEditRenderOverlay
    ) {
        guard case let .selection(payload) = editOverlay.payload else {
            hideSelectionOverlay()
            return
        }

        // Selection owns both the outline/resize handles and the rotate
        // affordance so the viewport can keep one coherent blue chrome.
        selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
        selectionOutlineLayer.isHidden = false
        selectionOutlineLayer.contentsScale = currentContentsScale

        for role in CanvasSelectionHandleRole.allCases {
            guard
                let handleLayer = selectionHandleLayers[role],
                let handle = editOverlay.handles.first(where: {
                    $0.role == role.editHandleRole
                })
            else {
                selectionHandleLayers[role]?.path = nil
                selectionHandleLayers[role]?.frame = .zero
                selectionHandleLayers[role]?.isHidden = true
                continue
            }

            handleLayer.frame = bounds
            handleLayer.path = Self.selectionHandlePath(
                centeredAt: handle.screenCenter,
                rotationRadians: handle.screenRotationRadians
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }

        refreshRotateAffordance(payload.rotateAffordance)
    }

    private func refreshRotateAffordance(
        _ rotateAffordance: CanvasEditRotateOverlayPayload
    ) {
        let guidePath = CGMutablePath()
        guidePath.move(to: rotateAffordance.guideScreenStart)
        guidePath.addLine(to: rotateAffordance.guideScreenEnd)
        rotateGuideLayer.path = guidePath
        rotateGuideLayer.isHidden = false
        rotateGuideLayer.contentsScale = currentContentsScale

        let handleRect = Self.rotateHandleRect(centeredAt: rotateAffordance.handle.screenCenter)
        rotateHandleLayer.frame = handleRect
        rotateHandleLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        rotateHandleLayer.isHidden = false
        rotateHandleLayer.contentsScale = currentContentsScale
    }

    private func refreshRotationInteractionOverlay(
        from interactionOverlay: CanvasInteractionRenderOverlay
    ) {
        guard case let .rotation(payload) = interactionOverlay.payload else {
            hideInteractionOverlay()
            return
        }

        interactionOverlayLayer.isHidden = !payload.isActive

        rotationRingLayer.frame = bounds
        rotationRingLayer.path = CGPath(
            ellipseIn: payload.ringScreenRect,
            transform: nil
        )
        rotationRingLayer.isHidden = !payload.isActive
        rotationRingLayer.contentsScale = currentContentsScale

        rotationTickLayer.frame = bounds
        rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
        rotationTickLayer.isHidden = !payload.isActive
        rotationTickLayer.contentsScale = currentContentsScale

        rotationPointerLayer.frame = bounds
        rotationPointerLayer.path = Self.lineSegmentsPath([
            payload.zeroReferenceSegment,
            payload.currentAngleSegment
        ])
        rotationPointerLayer.isHidden = !payload.isActive
        rotationPointerLayer.contentsScale = currentContentsScale

        let attributedText = Self.rotationAttributedText(for: payload)
        let textFrame = Self.rotationTextFrame(
            for: attributedText,
            anchoredAt: payload.textScreenAnchor
        )
        let textBackgroundFrame = Self.rotationTextBackgroundFrame(
            for: textFrame
        )

        rotationTextBackgroundLayer.frame = bounds
        rotationTextBackgroundLayer.path = CGPath(
            roundedRect: textBackgroundFrame,
            cornerWidth: Self.rotationTextCornerRadius,
            cornerHeight: Self.rotationTextCornerRadius,
            transform: nil
        )
        rotationTextBackgroundLayer.isHidden = !payload.isActive
        rotationTextBackgroundLayer.contentsScale = currentContentsScale

        rotationTextLayer.frame = textFrame
        rotationTextLayer.string = attributedText
        rotationTextLayer.isHidden = !payload.isActive
        rotationTextLayer.contentsScale = currentContentsScale
    }

    private func hideEditOverlay() {
        hideSelectionOverlay()
        hideCropOverlay()
    }

    private func hideInteractionOverlay() {
        interactionOverlayLayer.isHidden = true

        rotationRingLayer.path = nil
        rotationRingLayer.frame = bounds
        rotationRingLayer.isHidden = true

        rotationTickLayer.path = nil
        rotationTickLayer.frame = bounds
        rotationTickLayer.isHidden = true

        rotationPointerLayer.path = nil
        rotationPointerLayer.frame = bounds
        rotationPointerLayer.isHidden = true

        rotationTextBackgroundLayer.path = nil
        rotationTextBackgroundLayer.frame = .zero
        rotationTextBackgroundLayer.isHidden = true

        rotationTextLayer.frame = .zero
        rotationTextLayer.string = nil
        rotationTextLayer.isHidden = true
    }

    private func hideSelectionOverlay() {
        selectionOutlineLayer.path = nil
        selectionOutlineLayer.isHidden = true

        for handleLayer in selectionHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }

        rotateGuideLayer.path = nil
        rotateGuideLayer.isHidden = true
        rotateHandleLayer.path = nil
        rotateHandleLayer.frame = .zero
        rotateHandleLayer.isHidden = true
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

    private static func rotateHandleRect(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - rotateHandleSize / 2,
            y: center.y - rotateHandleSize / 2,
            width: rotateHandleSize,
            height: rotateHandleSize
        ).standardized
    }

    private static func cropHandlePath(
        centeredAt center: CGPoint,
        rotationRadians: CGFloat
    ) -> CGPath {
        squareHandlePath(
            centeredAt: center,
            size: cropHandleSize,
            rotationRadians: rotationRadians
        )
    }

    private static func selectionHandlePath(
        centeredAt center: CGPoint,
        rotationRadians: CGFloat
    ) -> CGPath {
        squareHandlePath(
            centeredAt: center,
            size: selectionHandleSize,
            rotationRadians: rotationRadians
        )
    }

    private static func squareHandlePath(
        centeredAt center: CGPoint,
        size: CGFloat,
        rotationRadians: CGFloat
    ) -> CGPath {
        let halfSize = size / 2
        let cosine = cos(rotationRadians)
        let sine = sin(rotationRadians)
        let localCorners = [
            CGPoint(x: -halfSize, y: -halfSize),
            CGPoint(x: halfSize, y: -halfSize),
            CGPoint(x: halfSize, y: halfSize),
            CGPoint(x: -halfSize, y: halfSize)
        ]
        let path = CGMutablePath()

        for (index, localCorner) in localCorners.enumerated() {
            let rotatedCorner = CGPoint(
                x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
                y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
            )
            if index == 0 {
                path.move(to: rotatedCorner)
            } else {
                path.addLine(to: rotatedCorner)
            }
        }

        path.closeSubpath()
        return path
    }

    private static func rotationTextFrame(
        for attributedText: NSAttributedString,
        anchoredAt anchor: CGPoint
    ) -> CGRect {
        let textBounds = attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        ).integral

        return CGRect(
            x: anchor.x - (textBounds.width / 2),
            y: anchor.y - (textBounds.height / 2),
            width: textBounds.width,
            height: textBounds.height
        ).integral
    }

    private static func rotationTextBackgroundFrame(
        for textFrame: CGRect
    ) -> CGRect {
        textFrame.insetBy(
            dx: -rotationTextHorizontalPadding,
            dy: -rotationTextVerticalPadding
        ).integral
    }

    private var currentContentsScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func setupAnimatedPlaybackLifecycle() {
        let notificationCenter = NotificationCenter.default
        animatedPlaybackObservers = [
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isApplicationPlaybackActive = true
                self?.updateAnimatedPlaybackState()
            },
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isApplicationPlaybackActive = false
                self?.updateAnimatedPlaybackState()
            }
        ]
    }

    private func removeAnimatedPlaybackObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in animatedPlaybackObservers {
            notificationCenter.removeObserver(observer)
        }
        animatedPlaybackObservers.removeAll()
    }

    private func updateAnimatedPlaybackState() {
        animatedPlaybackRegistry.setPlaybackEnabled(
            shouldAutoplayAnimatedImages &&
                isApplicationPlaybackActive &&
                window != nil &&
                bounds.isEmpty == false
        )
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private func imageLayer(for itemID: CanvasItemID) -> CanvasImageLayer {
        if let imageLayer = imageLayers[itemID] {
            return imageLayer
        }

        let imageLayer = CanvasImageLayer(itemID: itemID)
        itemsLayer.addSublayer(imageLayer)
        imageLayers[itemID] = imageLayer
        return imageLayer
    }

    private func textLayer(for itemID: CanvasItemID) -> CanvasTextLayer {
        if let textLayer = textLayers[itemID] {
            return textLayer
        }

        let textLayer = CanvasTextLayer(itemID: itemID)
        itemsLayer.addSublayer(textLayer)
        textLayers[itemID] = textLayer
        return textLayer
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

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        print(
            "[Canvas macOS][SecondaryClickEvent] " +
            "windowLocation=\(macOSViewportDescribe(event.locationInWindow)) " +
            "viewportLocation=\(macOSViewportDescribe(location)) " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame))"
        )
        onSecondaryClick?(location)
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        resolvedImportDragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        resolvedImportDragOperation(for: sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        resolvedImportDragOperation(for: sender) != []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        return onImportDrop?(location, sender.draggingPasteboard) ?? false
    }

    private func resolvedImportDragOperation(
        for sender: NSDraggingInfo
    ) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        return onImportDragOperation?(location, sender.draggingPasteboard) ?? []
    }
}

private func macOSViewportDescribe(_ point: CGPoint) -> String {
    "{\(macOSViewportFormat(point.x)), \(macOSViewportFormat(point.y))}"
}

private func macOSViewportDescribe(_ rect: CGRect) -> String {
    "{{\(macOSViewportFormat(rect.origin.x)), \(macOSViewportFormat(rect.origin.y))}, {\(macOSViewportFormat(rect.size.width)), \(macOSViewportFormat(rect.size.height))}}"
}

private func macOSViewportDescribe(_ overlay: CanvasEditRenderOverlay?) -> String {
    guard let overlay else {
        return "nil"
    }

    return "itemID=\(overlay.itemID.uuidString) kind=\(String(describing: overlay.kind)) activeScreenQuad=\(macOSViewportDescribe(overlay.activeScreenQuad.boundingRect.standardized))"
}

private func macOSViewportFormat(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
#endif
