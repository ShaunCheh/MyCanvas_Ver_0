#if os(macOS)
import AppKit
import QuartzCore

final class macOSVideoTimelineView: NSView {
    var onPlayheadTimeChangeRequested: ((Double) -> Void)?
    var onInteractionStateChanged: ((Bool) -> Void)?
    var onStripRequestChanged: ((CanvasVideoTimelineStripRequest) -> Void)?

    var hasRenderableStrip: Bool {
        strip?.frames.isEmpty == false
    }

    override var isFlipped: Bool {
        true
    }

    private let scrollView: macOSVideoTimelineScrollView = {
        let scrollView = macOSVideoTimelineScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        return scrollView
    }()
    private let contentContainerView: macOSVideoTimelineFlippedView = {
        let view = macOSVideoTimelineFlippedView()
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()
    private let rulerView: macOSVideoTimelineFlippedView = {
        let view = macOSVideoTimelineFlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }()
    private let trackView: macOSVideoTimelineFlippedView = {
        let view = macOSVideoTimelineFlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        return view
    }()
    private let playheadView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        view.layer?.cornerRadius = 1
        return view
    }()
    private let playheadHandleView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        view.layer?.cornerRadius = 5
        return view
    }()
    private let timelineLoadingIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()
    private let timelinePlaceholderLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        return label
    }()

    private let trackFrameLayer = CALayer()
    private let rulerTickLayer = CALayer()
    private let rulerLabelLayer = CALayer()

    private let thumbnailWidth: Double = 52
    private let maxPixelSize = 180
    private let overscanWidthMultiplier = 0.75
    private static let defaultZoomScale = CanvasVideoTimelineScale(
        zoomScale: 4,
        basePointsPerSecond: 18,
        minZoomScale: 1,
        maxZoomScale: 32
    )

    private var durationSeconds: Double = 0
    private var playheadTimeSeconds: Double = 0
    private var zoomScale: CanvasVideoTimelineScale
    private var strip: CanvasVideoTimelineStrip?
    private var isUserInteracting = false
    private var isProgrammaticScroll = false
    private var lastKnownBoundsSize: CGSize = .zero
    private var lastEmittedLoadSignature: StripLoadSignature?
    private var dragState: DragState?
    private var lastMagnificationValue: CGFloat = 0
    private var scrollInteractionEndWorkItem: DispatchWorkItem?
    private var reusableFrameLayers: [CALayer] = []
    private var placeholderState: CanvasVideoTimelinePlaceholderState = .loading(
        message: "Loading timeline..."
    )

    override init(frame frameRect: NSRect) {
        zoomScale = Self.defaultZoomScale
        super.init(frame: frameRect)
        setupViewHierarchy()
        setupConstraints()
        setupLayers()
        setupInteractionCallbacks()
        observeClipViewBounds()
        updatePlaceholderAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        scrollInteractionEndWorkItem?.cancel()
    }

    override func layout() {
        super.layout()
        let boundsSizeChanged = lastKnownBoundsSize != bounds.size
        lastKnownBoundsSize = bounds.size
        updateGeometry(recenterOnPlayhead: boundsSizeChanged)
        if boundsSizeChanged {
            emitStripRequestIfNeeded()
        }
    }

    func configure(
        durationSeconds: Double,
        playheadTimeSeconds: Double,
        zoomScale: CanvasVideoTimelineScale? = nil
    ) {
        self.durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
            durationSeconds
        )
        self.zoomScale = zoomScale ?? Self.defaultZoomScale
        self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            playheadTimeSeconds,
            durationSeconds: self.durationSeconds
        )
        setPlaceholderState(.loading(message: "Loading timeline..."))
        applyStrip(nil)
        needsLayout = true
    }

    func setPlayheadTimeSeconds(
        _ playheadTimeSeconds: Double,
        animated: Bool
    ) {
        _ = animated
        let clampedTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            playheadTimeSeconds,
            durationSeconds: durationSeconds
        )
        self.playheadTimeSeconds = clampedTimeSeconds
        guard isUserInteracting == false else {
            return
        }

        let geometryViewport = makeGeometryViewport()
        setProgrammaticContentOffsetX(
            geometryViewport.contentX(forTimeSeconds: clampedTimeSeconds)
        )
        emitStripRequestIfNeeded()
    }

    func applyStrip(_ strip: CanvasVideoTimelineStrip?) {
        self.strip = strip
        if strip == nil {
            lastEmittedLoadSignature = nil
        } else if strip?.frames.isEmpty == true {
            setPlaceholderState(.message("No timeline frames available."))
        } else {
            setPlaceholderState(.hidden)
        }
        renderTrackFrames()
        emitStripRequestIfNeeded()
    }

    func setPlaceholderState(_ state: CanvasVideoTimelinePlaceholderState) {
        placeholderState = state
        updatePlaceholderAppearance()
    }

    private func setupViewHierarchy() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        scrollView.documentView = contentContainerView
        addSubview(scrollView)
        contentContainerView.addSubview(rulerView)
        contentContainerView.addSubview(trackView)
        addSubview(playheadView)
        addSubview(playheadHandleView)
        addSubview(timelineLoadingIndicator)
        addSubview(timelinePlaceholderLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playheadView.widthAnchor.constraint(equalToConstant: 2),
            playheadView.centerXAnchor.constraint(equalTo: centerXAnchor),
            playheadView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            playheadView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            playheadHandleView.centerXAnchor.constraint(equalTo: playheadView.centerXAnchor),
            playheadHandleView.centerYAnchor.constraint(equalTo: playheadView.topAnchor),
            playheadHandleView.widthAnchor.constraint(equalToConstant: 10),
            playheadHandleView.heightAnchor.constraint(equalToConstant: 10),
            timelineLoadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            timelineLoadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            timelinePlaceholderLabel.topAnchor.constraint(
                equalTo: timelineLoadingIndicator.bottomAnchor,
                constant: 8
            ),
            timelinePlaceholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timelinePlaceholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 12
            ),
            timelinePlaceholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -12
            ),
            timelinePlaceholderLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor,
                constant: -12
            )
        ])
    }

    private func setupLayers() {
        trackView.layer?.addSublayer(trackFrameLayer)
        rulerView.layer?.addSublayer(rulerTickLayer)
        rulerView.layer?.addSublayer(rulerLabelLayer)
        trackFrameLayer.contentsGravity = .resizeAspectFill
    }

    private func setupInteractionCallbacks() {
        scrollView.onPointerBegan = { [weak self] location in
            self?.handlePointerBegan(at: location)
        }
        scrollView.onPointerDragged = { [weak self] location in
            self?.handlePointerDragged(at: location)
        }
        scrollView.onPointerEnded = { [weak self] location in
            self?.handlePointerEnded(at: location)
        }
        scrollView.onMagnificationChanged = { [weak self] magnification, location, state in
            self?.handleMagnification(
                magnification,
                at: location,
                state: state
            )
        }
    }

    private func observeClipViewBounds() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func updateGeometry(recenterOnPlayhead: Bool) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let visibleWidth = bounds.width
        let trackWidth = CGFloat(makeGeometryViewport().contentWidth)
        let totalContentWidth = max(trackWidth + visibleWidth, visibleWidth)
        contentContainerView.frame = NSRect(
            x: 0,
            y: 0,
            width: totalContentWidth,
            height: bounds.height
        )

        let leadingPadding = visibleWidth / 2
        let rulerHeight: CGFloat = 22
        let trackHeight = max(bounds.height - rulerHeight - 10, 44)
        rulerView.frame = NSRect(
            x: leadingPadding,
            y: 6,
            width: trackWidth,
            height: rulerHeight
        )
        trackView.frame = NSRect(
            x: leadingPadding,
            y: rulerView.frame.maxY + 6,
            width: trackWidth,
            height: trackHeight
        )
        trackFrameLayer.frame = trackView.bounds
        rulerTickLayer.frame = rulerView.bounds
        rulerLabelLayer.frame = rulerView.bounds

        if recenterOnPlayhead, isUserInteracting == false {
            let targetOffsetX = makeGeometryViewport().contentX(
                forTimeSeconds: playheadTimeSeconds
            )
            setProgrammaticContentOffsetX(targetOffsetX)
        } else {
            let clampedOffsetX = min(
                max(currentContentOffsetX, 0),
                maximumContentOffsetX
            )
            if currentContentOffsetX != clampedOffsetX {
                setProgrammaticContentOffsetX(Double(clampedOffsetX))
            }
        }

        renderRuler()
        renderTrackFrames()
    }

    private var currentContentOffsetX: CGFloat {
        scrollView.contentView.bounds.origin.x
    }

    private var maximumContentOffsetX: CGFloat {
        max(contentContainerView.frame.width - scrollView.contentView.bounds.width, 0)
    }

    private var layerContentsScale: CGFloat {
        CGFloat(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    private func makeGeometryViewport() -> CanvasVideoTimelineViewport {
        CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds,
            playheadTimeSeconds: playheadTimeSeconds,
            zoomScale: zoomScale,
            visibleWidth: 1,
            contentOffsetX: 0,
            minimumContentWidth: 1
        )
    }

    private func makeVisibleStripRequest() -> CanvasVideoTimelineStripRequest? {
        guard bounds.width > 0 else {
            return nil
        }

        let geometryViewport = makeGeometryViewport()
        let centeredTrackX = min(
            max(Double(currentContentOffsetX), 0),
            geometryViewport.contentWidth
        )
        let leftVisibleTrackX = max(centeredTrackX - Double(bounds.width / 2), 0)
        let rightVisibleTrackX = min(
            centeredTrackX + Double(bounds.width / 2),
            geometryViewport.contentWidth
        )
        let visibleTrackWidth = max(rightVisibleTrackX - leftVisibleTrackX, 1)
        let visibleViewport = CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds,
            playheadTimeSeconds: geometryViewport.timeSeconds(
                forContentX: centeredTrackX
            ),
            zoomScale: zoomScale,
            visibleWidth: visibleTrackWidth,
            contentOffsetX: leftVisibleTrackX,
            minimumContentWidth: 1
        )
        return CanvasVideoTimelineStripRequest(
            viewport: visibleViewport,
            thumbnailWidth: thumbnailWidth,
            maxPixelSize: maxPixelSize,
            overscanWidth: visibleTrackWidth * overscanWidthMultiplier
        )
    }

    private func renderTrackFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let strip, strip.frames.isEmpty == false else {
            hideReusableFrameLayers(startingAt: 0)
            CATransaction.commit()
            return
        }

        for index in strip.frames.indices {
            let frame = strip.frames[index]
            let leftEdge: Double
            if index == strip.frames.startIndex {
                leftEdge = strip.request.requestedContentRange.lowerBound
            } else {
                leftEdge = (strip.frames[index - 1].contentX + frame.contentX) / 2
            }
            let rightEdge: Double
            if index == strip.frames.index(before: strip.frames.endIndex) {
                rightEdge = strip.request.requestedContentRange.upperBound
            } else {
                rightEdge = (frame.contentX + strip.frames[index + 1].contentX) / 2
            }

            let frameLayer = reusableFrameLayer(at: index)
            frameLayer.contents = frame.cgImage
            frameLayer.contentsGravity = .resizeAspectFill
            frameLayer.contentsScale = layerContentsScale
            frameLayer.masksToBounds = true
            frameLayer.frame = CGRect(
                x: leftEdge,
                y: 0,
                width: max(rightEdge - leftEdge, 1),
                height: trackView.bounds.height
            )
            frameLayer.isHidden = false
        }
        hideReusableFrameLayers(startingAt: strip.frames.count)
        CATransaction.commit()
    }

    private func reusableFrameLayer(at index: Int) -> CALayer {
        while reusableFrameLayers.count <= index {
            let frameLayer = CALayer()
            frameLayer.contentsGravity = .resizeAspectFill
            frameLayer.masksToBounds = true
            trackFrameLayer.addSublayer(frameLayer)
            reusableFrameLayers.append(frameLayer)
        }
        return reusableFrameLayers[index]
    }

    private func hideReusableFrameLayers(startingAt index: Int) {
        guard index < reusableFrameLayers.count else {
            return
        }
        for frameLayer in reusableFrameLayers[index...] {
            frameLayer.contents = nil
            frameLayer.isHidden = true
        }
    }

    private func updatePlaceholderAppearance() {
        switch placeholderState {
        case .hidden:
            timelineLoadingIndicator.stopAnimation(nil)
            timelinePlaceholderLabel.stringValue = ""
            timelinePlaceholderLabel.isHidden = true
        case let .loading(message):
            timelineLoadingIndicator.startAnimation(nil)
            timelinePlaceholderLabel.stringValue = message
            timelinePlaceholderLabel.isHidden = message.isEmpty
        case let .message(message):
            timelineLoadingIndicator.stopAnimation(nil)
            timelinePlaceholderLabel.stringValue = message
            timelinePlaceholderLabel.isHidden = false
        }
    }

    private func renderRuler() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rulerTickLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rulerLabelLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let geometryViewport = makeGeometryViewport()
        let tickStepSeconds = makeTickStepSeconds(
            secondsPerPoint: geometryViewport.displayedSecondsPerPoint
        )
        guard tickStepSeconds > 0 else {
            CATransaction.commit()
            return
        }

        var tickTimeSeconds = 0.0
        let upperBoundTimeSeconds = geometryViewport.upperBoundTimeSeconds
        while tickTimeSeconds <= upperBoundTimeSeconds + 0.0001 {
            let tickX = geometryViewport.contentX(forTimeSeconds: tickTimeSeconds)
            let tickLayer = CALayer()
            tickLayer.backgroundColor = NSColor.separatorColor.cgColor
            tickLayer.frame = CGRect(
                x: tickX.rounded(.down),
                y: 14,
                width: 1,
                height: 6
            )
            rulerTickLayer.addSublayer(tickLayer)

            let labelLayer = CATextLayer()
            labelLayer.contentsScale = layerContentsScale
            labelLayer.fontSize = 11
            labelLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
            labelLayer.alignmentMode = .left
            labelLayer.string = formatTimelineTickTime(tickTimeSeconds)
            labelLayer.frame = CGRect(
                x: tickX + 4,
                y: 0,
                width: 72,
                height: 14
            )
            rulerLabelLayer.addSublayer(labelLayer)

            tickTimeSeconds += tickStepSeconds
        }

        CATransaction.commit()
    }

    private func makeTickStepSeconds(secondsPerPoint: Double) -> Double {
        guard secondsPerPoint > 0 else {
            return 0
        }

        let desiredStepSeconds = secondsPerPoint * 80
        let supportedSteps = [
            0.1, 0.25, 0.5,
            1.0, 2.0, 5.0,
            10.0, 15.0, 30.0,
            60.0, 120.0, 300.0
        ]
        return supportedSteps.first { $0 >= desiredStepSeconds }
            ?? supportedSteps.last!
    }

    private func setProgrammaticContentOffsetX(_ targetOffsetX: Double) {
        let clampedOffsetX = CGFloat(
            min(max(targetOffsetX, 0), Double(maximumContentOffsetX))
        )
        guard currentContentOffsetX != clampedOffsetX else {
            return
        }

        isProgrammaticScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: clampedOffsetX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isProgrammaticScroll = false
    }

    private func updatePlayheadTimeFromContentOffset(notify: Bool) {
        let centeredTrackX = min(
            max(Double(currentContentOffsetX), 0),
            makeGeometryViewport().contentWidth
        )
        playheadTimeSeconds = makeGeometryViewport().timeSeconds(
            forContentX: centeredTrackX
        )
        if notify {
            onPlayheadTimeChangeRequested?(playheadTimeSeconds)
        }
    }

    private func emitStripRequestIfNeeded() {
        guard let request = makeVisibleStripRequest() else {
            return
        }
        guard shouldRequestStrip(for: request) else {
            return
        }

        let loadSignature = StripLoadSignature(request: request)
        guard loadSignature != lastEmittedLoadSignature else {
            return
        }

        lastEmittedLoadSignature = loadSignature
        onStripRequestChanged?(request)
    }

    private func shouldRequestStrip(
        for request: CanvasVideoTimelineStripRequest
    ) -> Bool {
        guard let strip else {
            return true
        }

        guard
            strip.request.viewport.durationSeconds == request.viewport.durationSeconds,
            strip.request.viewport.zoomScale == request.viewport.zoomScale,
            strip.request.thumbnailWidth == request.thumbnailWidth,
            strip.request.maxPixelSize == request.maxPixelSize
        else {
            return true
        }

        return strip.request.requestedContentRange.contains(
            request.visibleContentRange.lowerBound
        ) == false || strip.request.requestedContentRange.contains(
            request.visibleContentRange.upperBound
        ) == false
    }

    private func beginInteractionIfNeeded() {
        guard isUserInteracting == false else {
            return
        }

        scrollInteractionEndWorkItem?.cancel()
        isUserInteracting = true
        onInteractionStateChanged?(true)
    }

    private func endInteractionIfNeeded() {
        guard isUserInteracting else {
            return
        }

        scrollInteractionEndWorkItem?.cancel()
        isUserInteracting = false
        onInteractionStateChanged?(false)
    }

    private func scheduleScrollInteractionEnd() {
        scrollInteractionEndWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.endInteractionIfNeeded()
        }
        scrollInteractionEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func handlePointerBegan(at location: CGPoint) {
        scrollInteractionEndWorkItem?.cancel()
        beginInteractionIfNeeded()
        dragState = DragState(
            startLocationX: location.x,
            startContentOffsetX: currentContentOffsetX
        )
    }

    private func handlePointerDragged(at location: CGPoint) {
        guard var dragState else {
            return
        }

        let deltaX = dragState.startLocationX - location.x
        if abs(deltaX) > 0.5 {
            dragState.hasMoved = true
        }
        self.dragState = dragState

        let targetOffsetX = dragState.startContentOffsetX + deltaX
        setProgrammaticContentOffsetX(Double(targetOffsetX))
        updatePlayheadTimeFromContentOffset(notify: true)
        emitStripRequestIfNeeded()
    }

    private func handlePointerEnded(at location: CGPoint) {
        if let dragState, dragState.hasMoved == false {
            let targetOffsetX = Double(
                currentContentOffsetX + location.x - bounds.midX
            )
            setProgrammaticContentOffsetX(targetOffsetX)
            updatePlayheadTimeFromContentOffset(notify: true)
            emitStripRequestIfNeeded()
        }

        dragState = nil
        endInteractionIfNeeded()
    }

    private func handleMagnification(
        _ magnification: CGFloat,
        at location: CGPoint,
        state: NSGestureRecognizer.State
    ) {
        guard bounds.width > 0 else {
            return
        }

        switch state {
        case .began:
            scrollInteractionEndWorkItem?.cancel()
            lastMagnificationValue = magnification
            beginInteractionIfNeeded()
        case .changed:
            let magnificationDelta = magnification - lastMagnificationValue
            lastMagnificationValue = magnification
            let scaleDelta = 1 + magnificationDelta
            guard scaleDelta.isFinite, scaleDelta > 0 else {
                return
            }

            let anchorTrackX = Double(
                currentContentOffsetX + location.x - bounds.width / 2
            )
            let anchorTimeSeconds = makeGeometryViewport().timeSeconds(
                forContentX: anchorTrackX
            )
            zoomScale = zoomScale.withZoomScale(
                zoomScale.zoomScale * Double(scaleDelta)
            )
            updateGeometry(recenterOnPlayhead: false)

            let newAnchorTrackX = makeGeometryViewport().contentX(
                forTimeSeconds: anchorTimeSeconds
            )
            let targetOffsetX = newAnchorTrackX
                - Double(location.x - bounds.width / 2)
            setProgrammaticContentOffsetX(targetOffsetX)
            updatePlayheadTimeFromContentOffset(notify: true)
            emitStripRequestIfNeeded()
        case .ended, .cancelled, .failed:
            lastMagnificationValue = 0
            endInteractionIfNeeded()
        default:
            break
        }
    }

    @objc
    private func handleClipViewBoundsDidChange() {
        guard isProgrammaticScroll == false else {
            return
        }

        beginInteractionIfNeeded()
        scheduleScrollInteractionEnd()
        updatePlayheadTimeFromContentOffset(notify: true)
        emitStripRequestIfNeeded()
    }
}

private final class macOSVideoTimelineScrollView: NSScrollView {
    var onPointerBegan: ((CGPoint) -> Void)?
    var onPointerDragged: ((CGPoint) -> Void)?
    var onPointerEnded: ((CGPoint) -> Void)?
    var onMagnificationChanged: ((CGFloat, CGPoint, NSGestureRecognizer.State) -> Void)?

    private lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
        let gestureRecognizer = NSMagnificationGestureRecognizer(
            target: self,
            action: #selector(handleMagnification(_:))
        )
        return gestureRecognizer
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView.copiesOnScroll = false
        addGestureRecognizer(magnificationGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onPointerBegan?(convert(event.locationInWindow, from: nil))

        guard let window else {
            onPointerEnded?(convert(event.locationInWindow, from: nil))
            return
        }

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                onPointerDragged?(convert(nextEvent.locationInWindow, from: nil))
            case .leftMouseUp:
                onPointerEnded?(convert(nextEvent.locationInWindow, from: nil))
                return
            default:
                break
            }
        }
    }

    @objc
    private func handleMagnification(
        _ gestureRecognizer: NSMagnificationGestureRecognizer
    ) {
        onMagnificationChanged?(
            gestureRecognizer.magnification,
            gestureRecognizer.location(in: self),
            gestureRecognizer.state
        )
    }
}

private final class macOSVideoTimelineFlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private struct DragState {
    let startLocationX: CGFloat
    let startContentOffsetX: CGFloat
    var hasMoved = false
}

private struct StripLoadSignature: Equatable {
    let durationBucket: Int
    let contentOffsetBucket: Int
    let visibleWidthBucket: Int
    let zoomBucket: Int
    let overscanBucket: Int
    let thumbnailWidthBucket: Int
    let maxPixelSize: Int

    init(request: CanvasVideoTimelineStripRequest) {
        durationBucket = Self.bucket(request.viewport.durationSeconds)
        contentOffsetBucket = Self.bucket(request.visibleContentRange.lowerBound)
        visibleWidthBucket = Self.bucket(
            request.visibleContentRange.upperBound
                - request.visibleContentRange.lowerBound
        )
        zoomBucket = Self.bucket(request.viewport.zoomScale.zoomScale)
        overscanBucket = Self.bucket(request.overscanWidth)
        thumbnailWidthBucket = Self.bucket(request.thumbnailWidth)
        maxPixelSize = request.maxPixelSize
    }

    private static func bucket(_ value: Double) -> Int {
        guard value.isFinite else {
            return 0
        }

        return Int((value * 1_000).rounded())
    }
}

private func formatTimelineTickTime(_ timeSeconds: Double) -> String {
    let clampedTimeSeconds = max(timeSeconds, 0)
    let totalSeconds = Int(clampedTimeSeconds.rounded(.towardZero))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let fractionalPart = clampedTimeSeconds - Double(totalSeconds)
    if minutes > 0 {
        return String(format: "%d:%02d", minutes, seconds)
    }
    if fractionalPart > 0.001 {
        return String(format: "%.1fs", clampedTimeSeconds)
    }
    return String(format: "%ds", seconds)
}
#endif
