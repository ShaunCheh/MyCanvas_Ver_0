#if os(iOS)
import UIKit

final class HandDrawingCanvasSurfaceView: UIView, UIScrollViewDelegate {
    private enum Layout {
        static let paperCornerRadius: CGFloat = 24
    }

    var onPencilStrokeBegan: ((HandDrawingInputSample) -> Void)?
    var onPencilStrokeMoved: (([HandDrawingInputSample]) -> Void)?
    var onPencilStrokeEnded: (([HandDrawingInputSample]) -> Void)?
    var onPencilStrokeCancelled: (() -> Void)?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        return scrollView
    }()
    private let pageView = HandDrawingCanvasPageView()
    private var paperWidthConstraint: NSLayoutConstraint?
    private var paperHeightConstraint: NSLayoutConstraint?
    private var hasConfiguredInitialZoomScale = false
    private var currentPaperSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .tertiarySystemGroupedBackground
        layer.cornerRadius = Layout.paperCornerRadius
        layer.cornerCurve = .continuous
        setupViewHierarchy()
        setupConstraints()
        configureScrollView()
        bindPageView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateZoomMetricsIfNeeded()
    }

    func apply(state: HandDrawingCanvasSurfaceState) {
        if currentPaperSize != state.paperSize {
            currentPaperSize = state.paperSize
            updatePaperSize(state.paperSize)
        }
        pageView.apply(state: state)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        pageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInset()
    }

    private func setupViewHierarchy() {
        addSubview(scrollView)
        scrollView.addSubview(pageView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])
        let widthConstraint = pageView.widthAnchor.constraint(equalToConstant: 1)
        let heightConstraint = pageView.heightAnchor.constraint(equalToConstant: 1)
        widthConstraint.isActive = true
        heightConstraint.isActive = true
        paperWidthConstraint = widthConstraint
        paperHeightConstraint = heightConstraint
    }

    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
    }

    private func bindPageView() {
        pageView.onPencilStrokeBegan = { [weak self] sample in
            self?.onPencilStrokeBegan?(sample)
        }
        pageView.onPencilStrokeMoved = { [weak self] samples in
            self?.onPencilStrokeMoved?(samples)
        }
        pageView.onPencilStrokeEnded = { [weak self] samples in
            self?.onPencilStrokeEnded?(samples)
        }
        pageView.onPencilStrokeCancelled = { [weak self] in
            self?.onPencilStrokeCancelled?()
        }
    }

    private func updatePaperSize(_ paperSize: CGSize) {
        paperWidthConstraint?.constant = max(paperSize.width, 1)
        paperHeightConstraint?.constant = max(paperSize.height, 1)
        hasConfiguredInitialZoomScale = false
        setNeedsLayout()
    }

    private func updateZoomMetricsIfNeeded() {
        guard bounds.isEmpty == false, currentPaperSize != .zero else {
            return
        }

        let widthScale = bounds.width / max(currentPaperSize.width, 1)
        let heightScale = bounds.height / max(currentPaperSize.height, 1)
        let fitScale = max(min(widthScale, heightScale), 0.1)
        scrollView.minimumZoomScale = max(fitScale * 0.5, 0.1)
        scrollView.maximumZoomScale = max(fitScale * 4, fitScale)
        if hasConfiguredInitialZoomScale == false {
            scrollView.zoomScale = fitScale
            hasConfiguredInitialZoomScale = true
        } else {
            scrollView.zoomScale = min(
                max(scrollView.zoomScale, scrollView.minimumZoomScale),
                scrollView.maximumZoomScale
            )
        }
        updateContentInset()
    }

    private func updateContentInset() {
        guard currentPaperSize != .zero else {
            return
        }
        let scaledWidth = currentPaperSize.width * scrollView.zoomScale
        let scaledHeight = currentPaperSize.height * scrollView.zoomScale
        let horizontalInset = max((bounds.width - scaledWidth) / 2, 0)
        let verticalInset = max((bounds.height - scaledHeight) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}

private final class HandDrawingCanvasPageView: UIView {
    var onPencilStrokeBegan: ((HandDrawingInputSample) -> Void)?
    var onPencilStrokeMoved: (([HandDrawingInputSample]) -> Void)?
    var onPencilStrokeEnded: (([HandDrawingInputSample]) -> Void)?
    var onPencilStrokeCancelled: (() -> Void)?

    private let committedImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        return imageView
    }()
    private let draftOverlayView = HandDrawingCanvasDraftOverlayView()
    private var activePencilTouchID: ObjectIdentifier?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        clipsToBounds = true
        isMultipleTouchEnabled = true
        addSubview(committedImageView)
        addSubview(draftOverlayView)
        NSLayoutConstraint.activate([
            committedImageView.topAnchor.constraint(equalTo: topAnchor),
            committedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            committedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            committedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            draftOverlayView.topAnchor.constraint(equalTo: topAnchor),
            draftOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            draftOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            draftOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: HandDrawingCanvasSurfaceState) {
        if let committedImage = state.committedImage {
            committedImageView.image = UIImage(cgImage: committedImage)
        } else {
            committedImageView.image = nil
        }
        draftOverlayView.draftStroke = state.draftStroke
        draftOverlayView.lassoPathPoints = state.lassoPathPoints
        draftOverlayView.selectedStrokeBounds = state.selectedStrokeBounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard
            activePencilTouchID == nil,
            let touch = firstPencilTouch(in: touches)
        else {
            return
        }
        activePencilTouchID = ObjectIdentifier(touch)
        if let sample = makeSample(from: touch) {
            onPencilStrokeBegan?(sample)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = matchingActivePencilTouch(in: touches) else {
            return
        }
        let samples = makeSamples(from: touch, event: event)
        guard samples.isEmpty == false else {
            return
        }
        onPencilStrokeMoved?(samples)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = matchingActivePencilTouch(in: touches) else {
            return
        }
        activePencilTouchID = nil
        onPencilStrokeEnded?(makeSamples(from: touch, event: event))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if matchingActivePencilTouch(in: touches) != nil {
            activePencilTouchID = nil
            onPencilStrokeCancelled?()
        }
    }

    private func firstPencilTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .pencil }
    }

    private func matchingActivePencilTouch(in touches: Set<UITouch>) -> UITouch? {
        guard let activePencilTouchID else {
            return nil
        }
        return touches.first { ObjectIdentifier($0) == activePencilTouchID }
    }

    private func makeSamples(
        from touch: UITouch,
        event: UIEvent?
    ) -> [HandDrawingInputSample] {
        let touches = event?.coalescedTouches(for: touch) ?? [touch]
        return touches.compactMap(makeSample(from:))
    }

    private func makeSample(from touch: UITouch) -> HandDrawingInputSample? {
        guard touch.type == .pencil else {
            return nil
        }
        let maximumPossibleForce = max(touch.maximumPossibleForce, 1)
        return HandDrawingInputSample(
            location: touch.location(in: self),
            force: max(touch.force / maximumPossibleForce, 0.05),
            timestamp: touch.timestamp,
            azimuthRadians: touch.azimuthAngle(in: self),
            altitudeRadians: touch.altitudeAngle
        )
    }
}

private final class HandDrawingCanvasDraftOverlayView: UIView {
    var draftStroke: HandDrawingStroke? {
        didSet {
            setNeedsDisplay()
        }
    }
    var lassoPathPoints: [CGPoint] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    var selectedStrokeBounds: CGRect? {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        if let draftStroke {
            HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
        }
        drawSelectedStrokeBoundsIfNeeded(in: context)
        drawLassoPathIfNeeded(in: context)
        context.restoreGState()
    }

    private func drawSelectedStrokeBoundsIfNeeded(
        in context: CGContext
    ) {
        guard
            let selectedStrokeBounds,
            selectedStrokeBounds.isNull == false,
            selectedStrokeBounds.isEmpty == false
        else {
            return
        }

        let path = UIBezierPath(
            roundedRect: selectedStrokeBounds.insetBy(dx: -6, dy: -6),
            cornerRadius: 12
        )
        context.saveGState()
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [8, 6])
        context.addPath(path.cgPath)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private func drawLassoPathIfNeeded(
        in context: CGContext
    ) {
        guard lassoPathPoints.count >= 2 else {
            return
        }

        let path = UIBezierPath()
        path.move(to: lassoPathPoints[0])
        for point in lassoPathPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.saveGState()
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: [8, 6])
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }
}
#endif
