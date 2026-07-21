#if os(iOS)
import QuartzCore
import UIKit

final class iOSVideoTimelineView: UIView {
    var onPlayheadTimeChangeRequested: ((Double) -> Void)?
    var onInteractionStateChanged: ((Bool) -> Void)?
    var onStripRequestChanged: ((CanvasVideoTimelineStripRequest) -> Void)?

    var hasRenderableStrip: Bool {
        strip?.frames.isEmpty == false
    }

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.bounces = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let rulerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    private let trackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        return view
    }()
    private let playheadView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 1
        return view
    }()
    private let playheadHandleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 5
        return view
    }()
    private let timelineLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.isUserInteractionEnabled = false
        return indicator
    }()
    private let timelinePlaceholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
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
    private var pinchLastScale: CGFloat = 1
    private var lastKnownBoundsSize: CGSize = .zero
    private var lastEmittedLoadSignature: StripLoadSignature?
    private var reusableFrameLayers: [CALayer] = []
    private var placeholderState: CanvasVideoTimelinePlaceholderState = .loading(
        message: "Loading timeline..."
    )

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )
        gestureRecognizer.delegate = self
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()
    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap(_:))
        )
        gestureRecognizer.delegate = self
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()

    override init(frame: CGRect) {
        zoomScale = Self.defaultZoomScale
        super.init(frame: frame)
        setupViewHierarchy()
        setupConstraints()
        setupLayers()
        scrollView.delegate = self
        updatePlaceholderAppearance()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else {
            return
        }
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
        setNeedsLayout()
    }

    func setPlayheadTimeSeconds(
        _ playheadTimeSeconds: Double,
        animated: Bool
    ) {
        let clampedTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            playheadTimeSeconds,
            durationSeconds: durationSeconds
        )
        self.playheadTimeSeconds = clampedTimeSeconds
        guard isUserInteracting == false else {
            return
        }

        let geometryViewport = makeGeometryViewport()
        setProgrammaticScrollOffsetX(
            geometryViewport.contentX(forTimeSeconds: clampedTimeSeconds),
            animated: animated
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
        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(rulerView)
        contentView.addSubview(trackView)
        addSubview(playheadView)
        addSubview(playheadHandleView)
        addSubview(timelineLoadingIndicator)
        addSubview(timelinePlaceholderLabel)

        addGestureRecognizer(pinchGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        tapGestureRecognizer.require(toFail: pinchGestureRecognizer)
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
        trackView.layer.addSublayer(trackFrameLayer)
        rulerView.layer.addSublayer(rulerTickLayer)
        rulerView.layer.addSublayer(rulerLabelLayer)
        trackFrameLayer.contentsGravity = .resizeAspectFill
    }

    private func updateAppearance() {
        PlatformLayerAppearance.performWithoutAnimations {
            trackView.layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
                .separator,
                for: traitCollection
            )
        }
        renderRuler()
    }

    private func updateGeometry(recenterOnPlayhead: Bool) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let visibleWidth = bounds.width
        let trackWidth = CGFloat(makeGeometryViewport().contentWidth)
        let totalContentWidth = max(trackWidth + visibleWidth, visibleWidth)
        scrollView.contentSize = CGSize(width: totalContentWidth, height: bounds.height)
        contentView.frame = CGRect(
            x: 0,
            y: 0,
            width: totalContentWidth,
            height: bounds.height
        )

        let leadingPadding = visibleWidth / 2
        let rulerHeight: CGFloat = 22
        let trackHeight = max(bounds.height - rulerHeight - 10, 44)
        rulerView.frame = CGRect(
            x: leadingPadding,
            y: 6,
            width: trackWidth,
            height: rulerHeight
        )
        trackView.frame = CGRect(
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
            setProgrammaticScrollOffsetX(targetOffsetX, animated: false)
        } else {
            let clampedOffsetX = min(
                max(scrollView.contentOffset.x, 0),
                maximumScrollOffsetX
            )
            if scrollView.contentOffset.x != clampedOffsetX {
                setProgrammaticScrollOffsetX(Double(clampedOffsetX), animated: false)
            }
        }

        renderRuler()
        renderTrackFrames()
    }

    private var maximumScrollOffsetX: CGFloat {
        max(scrollView.contentSize.width - scrollView.bounds.width, 0)
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
            max(Double(scrollView.contentOffset.x), 0),
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
            frameLayer.contentsScale = frameContentsScale
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

    private var frameContentsScale: CGFloat {
        window?.screen.scale ?? UIScreen.main.scale
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
            timelineLoadingIndicator.stopAnimating()
            timelinePlaceholderLabel.isHidden = true
            timelinePlaceholderLabel.text = nil
        case let .loading(message):
            timelineLoadingIndicator.startAnimating()
            timelinePlaceholderLabel.text = message
            timelinePlaceholderLabel.isHidden = message.isEmpty
        case let .message(message):
            timelineLoadingIndicator.stopAnimating()
            timelinePlaceholderLabel.text = message
            timelinePlaceholderLabel.isHidden = false
        }
    }

    private func renderRuler() {
        let tickColor = PlatformLayerAppearance.resolvedCGColor(
            .separator,
            for: traitCollection
        )
        let labelColor = PlatformLayerAppearance.resolvedCGColor(
            .secondaryLabel,
            for: traitCollection
        )
        PlatformLayerAppearance.performWithoutAnimations {
            rulerTickLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            rulerLabelLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

            let geometryViewport = makeGeometryViewport()
            let tickStepSeconds = makeTickStepSeconds(
                secondsPerPoint: geometryViewport.displayedSecondsPerPoint
            )
            guard tickStepSeconds > 0 else {
                return
            }

            var tickTimeSeconds = 0.0
            let upperBoundTimeSeconds = geometryViewport.upperBoundTimeSeconds
            while tickTimeSeconds <= upperBoundTimeSeconds + 0.0001 {
                let tickX = geometryViewport.contentX(
                    forTimeSeconds: tickTimeSeconds
                )
                let tickLayer = CALayer()
                tickLayer.backgroundColor = tickColor
                tickLayer.frame = CGRect(
                    x: tickX.rounded(.down),
                    y: 14,
                    width: 1,
                    height: 6
                )
                rulerTickLayer.addSublayer(tickLayer)

                let labelLayer = CATextLayer()
                labelLayer.contentsScale = UIScreen.main.scale
                labelLayer.fontSize = 11
                labelLayer.foregroundColor = labelColor
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
        }
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

    private func setProgrammaticScrollOffsetX(
        _ targetOffsetX: Double,
        animated: Bool
    ) {
        let clampedOffsetX = CGFloat(
            min(max(targetOffsetX, 0), Double(maximumScrollOffsetX))
        )
        guard scrollView.contentOffset.x != clampedOffsetX else {
            return
        }

        isProgrammaticScroll = true
        scrollView.setContentOffset(
            CGPoint(x: clampedOffsetX, y: 0),
            animated: animated
        )
        if animated == false {
            isProgrammaticScroll = false
        }
    }

    private func updatePlayheadTimeFromScrollOffset(
        notify: Bool
    ) {
        let centeredTrackX = min(
            max(Double(scrollView.contentOffset.x), 0),
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

        isUserInteracting = true
        onInteractionStateChanged?(true)
    }

    private func endInteractionIfNeeded() {
        guard isUserInteracting else {
            return
        }

        isUserInteracting = false
        onInteractionStateChanged?(false)
    }

    @objc
    private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, bounds.width > 0 else {
            return
        }

        beginInteractionIfNeeded()
        let location = gestureRecognizer.location(in: self)
        let targetOffsetX = Double(scrollView.contentOffset.x + location.x - bounds.midX)
        setProgrammaticScrollOffsetX(targetOffsetX, animated: false)
        updatePlayheadTimeFromScrollOffset(notify: true)
        emitStripRequestIfNeeded()
        endInteractionIfNeeded()
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        guard bounds.width > 0 else {
            return
        }

        switch gestureRecognizer.state {
        case .began:
            pinchLastScale = max(gestureRecognizer.scale, 0.0001)
            beginInteractionIfNeeded()
        case .changed:
            let rawScale = max(gestureRecognizer.scale, 0.0001)
            let rawScaleDelta = rawScale / max(pinchLastScale, 0.0001)
            pinchLastScale = rawScale

            let anchorLocationX = gestureRecognizer.location(in: self).x
            let anchorTrackX = Double(scrollView.contentOffset.x + anchorLocationX - bounds.width / 2)
            let anchorTimeSeconds = makeGeometryViewport().timeSeconds(
                forContentX: anchorTrackX
            )
            zoomScale = zoomScale.withZoomScale(
                zoomScale.zoomScale * Double(rawScaleDelta)
            )
            updateGeometry(recenterOnPlayhead: false)

            let newAnchorTrackX = makeGeometryViewport().contentX(
                forTimeSeconds: anchorTimeSeconds
            )
            let targetOffsetX = newAnchorTrackX - Double(anchorLocationX - bounds.width / 2)
            setProgrammaticScrollOffsetX(targetOffsetX, animated: false)
            updatePlayheadTimeFromScrollOffset(notify: true)
            emitStripRequestIfNeeded()
        case .ended, .cancelled, .failed:
            pinchLastScale = 1
            endInteractionIfNeeded()
        default:
            break
        }
    }
}

extension iOSVideoTimelineView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        beginInteractionIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isProgrammaticScroll == false else {
            return
        }

        updatePlayheadTimeFromScrollOffset(notify: true)
        emitStripRequestIfNeeded()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if decelerate == false {
            endInteractionIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        endInteractionIfNeeded()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
    }
}

extension iOSVideoTimelineView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer == pinchGestureRecognizer ||
            otherGestureRecognizer == pinchGestureRecognizer
    }
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
        visibleWidthBucket = Self.bucket(request.visibleContentRange.upperBound - request.visibleContentRange.lowerBound)
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
