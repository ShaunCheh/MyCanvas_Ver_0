#if os(macOS)
import AppKit

final class macOSCanvasViewportView: NSView {
    private static let workspaceBackgroundColor = CanvasWorkspacePalette.backgroundColor
    private static let workspaceMinorGridStrokeColor = CanvasWorkspacePalette.minorGridStrokeColor
    private static let workspaceMajorGridStrokeColor = CanvasWorkspacePalette.majorGridStrokeColor
    private static let workspaceMinorGridLineWidth: CGFloat = 1
    private static let workspaceMajorGridLineWidth: CGFloat = 1
    private static let boardSurfaceFillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    private static let groupFrameFillColor = CGColor(gray: 0.55, alpha: 0.18)
    private static let groupFrameStrokeColor = CGColor(gray: 0.45, alpha: 0.32)
    private static let groupFrameCornerRadius: CGFloat = 14
    private static let selectionStrokeColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    private static let selectionHighlightStrokeColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 0.35
    )
    private static let selectionHandleFillColor = CGColor(gray: 1, alpha: 1)
    private static let selectionHighlightLineWidth: CGFloat = 1.5
    private static let selectionOutlineLineWidth: CGFloat = 2
    private static let selectionHandleLineWidth: CGFloat = 2
    private static let selectionHandleSize: CGFloat = 10
    private static let selectionEdgeHandleLength: CGFloat = 24
    private static let selectionEdgeHandleThickness: CGFloat = 8
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
    private static let alignmentGuideLineWidth: CGFloat = 2
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
    private let groupFramesLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private let selectionHighlightsLayer = CAShapeLayer()
    private let selectionOutlineLayer = CAShapeLayer()
    private let interactionOverlayLayer = CALayer()
    private let alignmentGuideLayer = CAShapeLayer()
    private let rotationRingLayer = CAShapeLayer()
    private let rotationTickLayer = CAShapeLayer()
    private let rotationPointerLayer = CAShapeLayer()
    private let rotationTextBackgroundLayer = CAShapeLayer()
    private let rotationTextLayer = CATextLayer()
    private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
    private var arrowEndpointHandleLayers: [CanvasArrowEndpointRole: CAShapeLayer] = [:]
    private let cropMaskLayer = CAShapeLayer()
    private let cropOutlineLayer = CAShapeLayer()
    private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
    private let rotateGuideLayer = CAShapeLayer()
    private let rotateHandleLayer = CAShapeLayer()
    private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
    private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
    private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]
    private var markdownLayers: [CanvasItemID: CanvasMarkdownItemLayer] = [:]
    private var arrowLayers: [CanvasItemID: CanvasArrowLayer] = [:]
    private var groupFrameLayers: [CanvasItemGroupID: CAShapeLayer] = [:]
    private var lastReportedViewportSize: CGSize?
    private var snapshot: CanvasRenderSnapshot = .empty
    private var lastPrimaryPointerLocation: CGPoint?
    private lazy var animatedPlaybackRegistry = CanvasGIFPlaybackRegistry { [weak self] assetReference in
        self?.resolveAnimatedImagePlaybackSource?(assetReference)
    }
    private var animatedPlaybackObservers: [NSObjectProtocol] = []
    private var isApplicationPlaybackActive = NSApplication.shared.isActive
    var onPointerDown: ((CGPoint, CanvasPointerModifiers) -> Void)?
    var onPointerMove: ((CGPoint, CGPoint) -> Void)?
    var onPointerUp: ((CGPoint, CanvasPointerModifiers) -> Void)?
    var onPointerCancel: (() -> Void)?
    var onSecondaryClick: ((CGPoint) -> Void)?
    var onPan: ((CGPoint, CGPoint) -> Void)?
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
        // Temporarily muted: ViewportLifecycle noise.
        #if false
        print(
            "[Canvas macOS][ViewportLifecycle] " +
            "action=layout " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame)) " +
            "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
        )
        #endif
        performWithoutLayerActions {
            updateLayerFrames()
        }
        reportViewportSizeIfNeeded()
        updateAnimatedPlaybackState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Temporarily muted: ViewportLifecycle noise.
        #if false
        print(
            "[Canvas macOS][ViewportLifecycle] " +
            "action=viewDidMoveToWindow " +
            "viewBounds=\(macOSViewportDescribe(bounds)) " +
            "viewFrame=\(macOSViewportDescribe(frame)) " +
            "windowFrame=\(window.map { macOSViewportDescribe($0.frame) } ?? "nil")"
        )
        #endif
        updateBackgroundAppearance()
        performWithoutLayerActions {
            refreshGroupFrameLayers()
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
            refreshGroupFrameLayers()
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
        layer?.addSublayer(groupFramesLayer)
        layer?.addSublayer(itemsLayer)
        layer?.addSublayer(overlayLayer)
        overlayLayer.addSublayer(selectionHighlightsLayer)
        overlayLayer.addSublayer(selectionOutlineLayer)
        overlayLayer.addSublayer(interactionOverlayLayer)
        overlayLayer.addSublayer(cropMaskLayer)
        overlayLayer.addSublayer(cropOutlineLayer)
        overlayLayer.addSublayer(rotateGuideLayer)
        overlayLayer.addSublayer(rotateHandleLayer)
        interactionOverlayLayer.addSublayer(alignmentGuideLayer)
        interactionOverlayLayer.addSublayer(rotationRingLayer)
        interactionOverlayLayer.addSublayer(rotationTickLayer)
        interactionOverlayLayer.addSublayer(rotationPointerLayer)
        interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
        interactionOverlayLayer.addSublayer(rotationTextLayer)

        configureWorkspaceGridLayers()
        configureBoardSurfaceLayer()
        configureSelectionHighlightsLayer()
        configureSelectionOutlineLayer()
        configureInteractionOverlayLayer()
        configureAlignmentGuideLayer()
        configureRotationRingLayer()
        configureRotationTickLayer()
        configureRotationPointerLayer()
        configureRotationTextBackgroundLayer()
        configureRotationTextLayer()
        configureSelectionHandleLayers()
        configureArrowEndpointHandleLayers()
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

        if groupFramesLayer.frame != bounds {
            groupFramesLayer.frame = bounds
        }

        if itemsLayer.frame != bounds {
            itemsLayer.frame = bounds
        }

        if overlayLayer.frame != bounds {
            overlayLayer.frame = bounds
        }

        if selectionHighlightsLayer.frame != bounds {
            selectionHighlightsLayer.frame = bounds
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

    private func refreshGroupFrameLayers() {
        let incomingGroupIDs = Set(snapshot.groups.map(\.id))
        let existingGroupIDs = Set(groupFrameLayers.keys)

        for removedID in existingGroupIDs.subtracting(incomingGroupIDs) {
            groupFrameLayers[removedID]?.removeFromSuperlayer()
            groupFrameLayers[removedID] = nil
        }

        let contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        for group in snapshot.groups {
            let layer = groupFrameLayer(for: group.id)
            layer.frame = group.screenFrame
            layer.path = CGPath(
                roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
                cornerWidth: Self.groupFrameCornerRadius,
                cornerHeight: Self.groupFrameCornerRadius,
                transform: nil
            )
            layer.lineWidth = 1 / max(contentsScale, 1)
            layer.contentsScale = contentsScale
        }
    }

    private func groupFrameLayer(
        for groupID: CanvasItemGroupID
    ) -> CAShapeLayer {
        if let layer = groupFrameLayers[groupID] {
            return layer
        }

        let layer = CAShapeLayer()
        layer.fillColor = Self.groupFrameFillColor
        layer.strokeColor = Self.groupFrameStrokeColor
        layer.lineJoin = .round
        groupFramesLayer.addSublayer(layer)
        groupFrameLayers[groupID] = layer
        return layer
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
        let incomingHandDrawingIDs = Set(
            snapshot.items.compactMap { item in
                if case .handDrawing = item.payload {
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
        let incomingMarkdownIDs = Set(
            snapshot.items.compactMap { item in
                if case .markdown = item.payload {
                    return item.id
                }

                return nil
            }
        )
        let incomingArrowIDs = Set(
            snapshot.items.compactMap { item in
                if case .arrow = item.payload {
                    return item.id
                }

                return nil
            }
        )
        let existingImageIDs = Set(imageLayers.keys)
        let existingHandDrawingIDs = Set(handDrawingLayers.keys)
        let existingTextIDs = Set(textLayers.keys)
        let existingMarkdownIDs = Set(markdownLayers.keys)
        let existingArrowIDs = Set(arrowLayers.keys)

        for removedID in existingImageIDs.subtracting(incomingImageIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        for removedID in existingHandDrawingIDs.subtracting(incomingHandDrawingIDs) {
            handDrawingLayers[removedID]?.removeFromSuperlayer()
            handDrawingLayers[removedID] = nil
        }

        for removedID in existingTextIDs.subtracting(incomingTextIDs) {
            textLayers[removedID]?.removeFromSuperlayer()
            textLayers[removedID] = nil
        }

        for removedID in existingMarkdownIDs.subtracting(incomingMarkdownIDs) {
            markdownLayers[removedID]?.removeFromSuperlayer()
            markdownLayers[removedID] = nil
        }

        for removedID in existingArrowIDs.subtracting(incomingArrowIDs) {
            arrowLayers[removedID]?.removeFromSuperlayer()
            arrowLayers[removedID] = nil
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
            case let .handDrawing(handDrawingPayload):
                let handDrawingLayer = handDrawingLayer(for: item.id)
                refreshHandDrawingLayer(
                    handDrawingLayer,
                    with: item,
                    handDrawingPayload: handDrawingPayload,
                    contentsScale: contentsScale
                )
            case let .text(textPayload):
                let textLayer = textLayer(for: item.id)
                textLayer.update(
                    with: item,
                    textPayload: textPayload,
                    contentsScale: contentsScale
                )
            case let .markdown(markdownPayload):
                let markdownLayer = markdownLayer(for: item.id)
                markdownLayer.update(
                    with: item,
                    markdownPayload: markdownPayload,
                    contentsScale: contentsScale
                )
            case .arrow:
                let arrowLayer = arrowLayer(for: item.id)
                arrowLayer.update(
                    with: item,
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

    private func refreshHandDrawingLayer(
        _ handDrawingLayer: CanvasImageLayer,
        with item: CanvasRenderItem,
        handDrawingPayload: CanvasHandDrawingRenderPayload,
        contentsScale: CGFloat
    ) {
        handDrawingLayer.updateStaticPresentation(
            with: item,
            imagePayload: CanvasImageRenderPayload(
                displayContract: CanvasImageDisplayContract(
                    assetReference: handDrawingPayload.previewAssetReference,
                    posterCGImage: handDrawingPayload.previewCGImage,
                    allowsAnimatedPlayback: false
                ),
                contentsRect: CanvasImageCropRect.fullImage.cgRect
            ),
            contentsScale: contentsScale
        )
        applyHandDrawingAppearance(
            to: handDrawingLayer,
            isEmpty: handDrawingPayload.isEmpty,
            contentsScale: contentsScale
        )
    }

    private func applyHandDrawingAppearance(
        to handDrawingLayer: CanvasImageLayer,
        isEmpty: Bool,
        contentsScale: CGFloat
    ) {
        handDrawingLayer.backgroundColor =
            CanvasHandDrawingPreviewAppearance.paperFillColor
        handDrawingLayer.borderColor =
            CanvasHandDrawingPreviewAppearance.resolvedBorderColor(isEmpty: isEmpty)
        handDrawingLayer.borderWidth =
            CanvasHandDrawingPreviewAppearance.borderLineWidth / max(contentsScale, 1)
        handDrawingLayer.cornerRadius =
            CanvasHandDrawingPreviewAppearance.cornerRadius
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

    private func configureSelectionHighlightsLayer() {
        selectionHighlightsLayer.fillColor = nil
        selectionHighlightsLayer.strokeColor = Self.selectionHighlightStrokeColor
        selectionHighlightsLayer.lineWidth = Self.selectionHighlightLineWidth
        selectionHighlightsLayer.lineJoin = .round
        selectionHighlightsLayer.lineCap = .round
        selectionHighlightsLayer.isHidden = true
    }

    private func configureInteractionOverlayLayer() {
        interactionOverlayLayer.isHidden = true
    }

    private func configureAlignmentGuideLayer() {
        alignmentGuideLayer.fillColor = nil
        alignmentGuideLayer.strokeColor = Self.selectionStrokeColor
        alignmentGuideLayer.lineWidth = Self.alignmentGuideLineWidth
        alignmentGuideLayer.lineCap = .round
        alignmentGuideLayer.lineJoin = .round
        alignmentGuideLayer.isHidden = true
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

    private func configureArrowEndpointHandleLayers() {
        for role in CanvasArrowEndpointRole.allCases {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = Self.selectionHandleFillColor
            handleLayer.strokeColor = Self.selectionStrokeColor
            handleLayer.lineWidth = Self.selectionHandleLineWidth
            handleLayer.isHidden = true
            overlayLayer.addSublayer(handleLayer)
            arrowEndpointHandleLayers[role] = handleLayer
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
        if let groupEditOverlay = snapshot.groupEditOverlay {
            refreshGroupEditOverlay(from: groupEditOverlay)
            hideCropOverlay()
            return
        }

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

    private func refreshGroupEditOverlay(
        from groupEditOverlay: CanvasGroupEditOverlay
    ) {
        selectionHighlightsLayer.path = nil
        selectionHighlightsLayer.isHidden = true

        selectionOutlineLayer.path = Self.groupEditOverlayPath(
            for: groupEditOverlay.screenFrame
        )
        selectionOutlineLayer.isHidden = false
        selectionOutlineLayer.contentsScale = currentContentsScale

        for role in CanvasSelectionHandleRole.allCases {
            guard
                let handleLayer = selectionHandleLayers[role],
                let handle = groupEditOverlay.handles.first(where: {
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
                for: role,
                centeredAt: handle.screenCenter,
                rotationRadians: handle.screenRotationRadians
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }

        for handleLayer in arrowEndpointHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }

        hideRotateAffordance()
    }

    private func refreshInteractionOverlay() {
        guard let interactionOverlay = snapshot.interactionOverlay else {
            hideInteractionOverlay()
            return
        }

        switch interactionOverlay.kind {
        case .rotation:
            refreshRotationInteractionOverlay(from: interactionOverlay)
        case .alignment:
            refreshAlignmentInteractionOverlay(from: interactionOverlay)
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
        refreshSelectionHighlights()

        // Selection owns both the outline/resize handles and the rotate
        // affordance so the viewport can keep one coherent blue chrome.
        selectionOutlineLayer.path = payload.outlineScreenPath
            ?? Self.quadPath(for: editOverlay.activeScreenQuad)
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
                for: role,
                centeredAt: handle.screenCenter,
                rotationRadians: handle.screenRotationRadians
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }

        for role in CanvasArrowEndpointRole.allCases {
            guard
                let handleLayer = arrowEndpointHandleLayers[role],
                let handle = editOverlay.handles.first(where: {
                    $0.role.arrowEndpointRole == role
                })
            else {
                arrowEndpointHandleLayers[role]?.path = nil
                arrowEndpointHandleLayers[role]?.frame = .zero
                arrowEndpointHandleLayers[role]?.isHidden = true
                continue
            }

            handleLayer.frame = bounds
            handleLayer.path = Self.arrowEndpointHandlePath(
                centeredAt: handle.screenCenter
            )
            handleLayer.isHidden = false
            handleLayer.contentsScale = currentContentsScale
        }

        if let rotateAffordance = payload.rotateAffordance {
            refreshRotateAffordance(rotateAffordance)
        } else {
            hideRotateAffordance()
        }
    }

    private func refreshSelectionHighlights() {
        guard snapshot.selectionHighlights.isEmpty == false else {
            selectionHighlightsLayer.path = nil
            selectionHighlightsLayer.isHidden = true
            return
        }

        let path = CGMutablePath()
        for highlight in snapshot.selectionHighlights {
            path.addPath(Self.quadPath(for: highlight.screenQuad))
        }
        selectionHighlightsLayer.frame = bounds
        selectionHighlightsLayer.path = path
        selectionHighlightsLayer.isHidden = false
        selectionHighlightsLayer.contentsScale = currentContentsScale
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

    private func hideRotateAffordance() {
        rotateGuideLayer.path = nil
        rotateGuideLayer.isHidden = true
        rotateHandleLayer.path = nil
        rotateHandleLayer.frame = .zero
        rotateHandleLayer.isHidden = true
    }

    private func refreshRotationInteractionOverlay(
        from interactionOverlay: CanvasInteractionRenderOverlay
    ) {
        guard case let .rotation(payload) = interactionOverlay.payload else {
            hideInteractionOverlay()
            return
        }

        guard payload.isActive else {
            hideInteractionOverlay()
            return
        }

        interactionOverlayLayer.isHidden = false
        hideAlignmentInteractionOverlayLayer()

        rotationRingLayer.frame = bounds
        rotationRingLayer.path = CGPath(
            ellipseIn: payload.ringScreenRect,
            transform: nil
        )
        rotationRingLayer.isHidden = false
        rotationRingLayer.contentsScale = currentContentsScale

        rotationTickLayer.frame = bounds
        rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
        rotationTickLayer.isHidden = false
        rotationTickLayer.contentsScale = currentContentsScale

        rotationPointerLayer.frame = bounds
        rotationPointerLayer.path = Self.lineSegmentsPath([
            payload.zeroReferenceSegment,
            payload.currentAngleSegment
        ])
        rotationPointerLayer.isHidden = false
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
        rotationTextBackgroundLayer.isHidden = false
        rotationTextBackgroundLayer.contentsScale = currentContentsScale

        rotationTextLayer.frame = textFrame
        rotationTextLayer.string = attributedText
        rotationTextLayer.isHidden = false
        rotationTextLayer.contentsScale = currentContentsScale
    }

    private func refreshAlignmentInteractionOverlay(
        from interactionOverlay: CanvasInteractionRenderOverlay
    ) {
        guard case let .alignment(payload) = interactionOverlay.payload else {
            hideInteractionOverlay()
            return
        }

        guard payload.isActive else {
            hideInteractionOverlay()
            return
        }

        interactionOverlayLayer.isHidden = false
        hideRotationInteractionOverlayLayers()

        alignmentGuideLayer.frame = bounds
        alignmentGuideLayer.path = payload.guideSegments.isEmpty
            ? nil
            : Self.lineSegmentsPath(payload.guideSegments)
        alignmentGuideLayer.isHidden = payload.guideSegments.isEmpty
        alignmentGuideLayer.contentsScale = currentContentsScale
    }

    private func hideEditOverlay() {
        hideSelectionOverlay()
        hideCropOverlay()
    }

    private func hideInteractionOverlay() {
        interactionOverlayLayer.isHidden = true
        hideAlignmentInteractionOverlayLayer()
        hideRotationInteractionOverlayLayers()
    }

    private func hideAlignmentInteractionOverlayLayer() {
        alignmentGuideLayer.path = nil
        alignmentGuideLayer.frame = bounds
        alignmentGuideLayer.isHidden = true
    }

    private func hideRotationInteractionOverlayLayers() {
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
        selectionHighlightsLayer.path = nil
        selectionHighlightsLayer.isHidden = true
        selectionOutlineLayer.path = nil
        selectionOutlineLayer.isHidden = true

        for handleLayer in selectionHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }

        for handleLayer in arrowEndpointHandleLayers.values {
            handleLayer.path = nil
            handleLayer.frame = .zero
            handleLayer.isHidden = true
        }

        hideRotateAffordance()
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

    private static func arrowEndpointHandlePath(
        centeredAt center: CGPoint
    ) -> CGPath {
        let handleRect = CGRect(
            x: center.x - selectionHandleSize / 2,
            y: center.y - selectionHandleSize / 2,
            width: selectionHandleSize,
            height: selectionHandleSize
        )
        return CGPath(ellipseIn: handleRect, transform: nil)
    }

    private static func selectionHandlePath(
        for role: CanvasSelectionHandleRole,
        centeredAt center: CGPoint,
        rotationRadians: CGFloat
    ) -> CGPath {
        switch role {
        case .leading, .trailing:
            return edgeHandlePath(
                centeredAt: center,
                length: selectionEdgeHandleLength,
                thickness: selectionEdgeHandleThickness,
                rotationRadians: rotationRadians,
                isHorizontal: false
            )
        case .top, .bottom:
            return edgeHandlePath(
                centeredAt: center,
                length: selectionEdgeHandleLength,
                thickness: selectionEdgeHandleThickness,
                rotationRadians: rotationRadians,
                isHorizontal: true
            )
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            break
        }
        return squareHandlePath(
            centeredAt: center,
            size: selectionHandleSize,
            rotationRadians: rotationRadians
        )
    }

    private static func edgeHandlePath(
        centeredAt center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        rotationRadians: CGFloat,
        isHorizontal: Bool
    ) -> CGPath {
        let localRect = CGRect(
            x: isHorizontal ? -length / 2 : -thickness / 2,
            y: isHorizontal ? -thickness / 2 : -length / 2,
            width: isHorizontal ? length : thickness,
            height: isHorizontal ? thickness : length
        )
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: rotationRadians)
        let localPath = CGPath(
            roundedRect: localRect,
            cornerWidth: thickness / 2,
            cornerHeight: thickness / 2,
            transform: nil
        )
        return localPath.copy(using: &transform) ?? localPath
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

    private static func groupEditOverlayPath(for screenFrame: CGRect) -> CGPath {
        let frame = screenFrame.standardized
        let cornerRadius = min(
            groupFrameCornerRadius,
            min(frame.width, frame.height) / 2
        )
        return CGPath(
            roundedRect: frame,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
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

    private func handDrawingLayer(for itemID: CanvasItemID) -> CanvasImageLayer {
        if let handDrawingLayer = handDrawingLayers[itemID] {
            return handDrawingLayer
        }

        let handDrawingLayer = CanvasImageLayer(itemID: itemID)
        itemsLayer.addSublayer(handDrawingLayer)
        handDrawingLayers[itemID] = handDrawingLayer
        return handDrawingLayer
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

    private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownItemLayer {
        if let markdownLayer = markdownLayers[itemID] {
            return markdownLayer
        }

        let markdownLayer = CanvasMarkdownItemLayer(itemID: itemID)
        itemsLayer.addSublayer(markdownLayer)
        markdownLayers[itemID] = markdownLayer
        return markdownLayer
    }

    private func arrowLayer(for itemID: CanvasItemID) -> CanvasArrowLayer {
        if let arrowLayer = arrowLayers[itemID] {
            return arrowLayer
        }

        let arrowLayer = CanvasArrowLayer(itemID: itemID)
        itemsLayer.addSublayer(arrowLayer)
        arrowLayers[itemID] = arrowLayer
        return arrowLayer
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        lastPrimaryPointerLocation = location
        onPointerDown?(location, pointerModifiers(for: event.modifierFlags))
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
        onPointerUp?(location, pointerModifiers(for: event.modifierFlags))
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

    private func pointerModifiers(
        for modifierFlags: NSEvent.ModifierFlags
    ) -> CanvasPointerModifiers {
        let normalizedFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return CanvasPointerModifiers(
            isCommandPressed: normalizedFlags.contains(.command),
            isShiftPressed: normalizedFlags.contains(.shift),
            isOptionPressed: normalizedFlags.contains(.option),
            isControlPressed: normalizedFlags.contains(.control)
        )
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        guard delta != .zero else {
            super.scrollWheel(with: event)
            return
        }

        onPan?(delta, convert(event.locationInWindow, from: nil))
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
