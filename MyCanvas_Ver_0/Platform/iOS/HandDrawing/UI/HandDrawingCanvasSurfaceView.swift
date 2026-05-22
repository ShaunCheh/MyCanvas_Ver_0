#if os(iOS)
import UIKit
#if canImport(MetalKit)
import MetalKit
#endif

final class HandDrawingCanvasSurfaceView: UIView, UIScrollViewDelegate {
    private enum Layout {
        static let paperCornerRadius: CGFloat = 24
    }

    var onPencilStrokeBegan: ((HandDrawingInputSample) -> Void)?
    var onPencilStrokeMoved: ((HandDrawingLiveInputBatch) -> Void)?
    var onPencilStrokeEnded: ((HandDrawingLiveInputBatch) -> Void)?
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
        pageView.onPencilStrokeMoved = { [weak self] batch in
            self?.onPencilStrokeMoved?(batch)
        }
        pageView.onPencilStrokeEnded = { [weak self] batch in
            self?.onPencilStrokeEnded?(batch)
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
    var onPencilStrokeMoved: ((HandDrawingLiveInputBatch) -> Void)?
    var onPencilStrokeEnded: ((HandDrawingLiveInputBatch) -> Void)?
    var onPencilStrokeCancelled: (() -> Void)?

    private let liveInputConfiguration = HandDrawingLiveInputConfiguration
        .interactiveDraft
    private let committedCanvasHostView = HandDrawingCommittedCanvasHostView()
    private let realtimeDraftHostView = HandDrawingRealtimeDraftHostView()
    private let interactionOverlayView = HandDrawingCanvasInteractionOverlayView()
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
        addSubview(committedCanvasHostView)
        addSubview(realtimeDraftHostView)
        addSubview(interactionOverlayView)
        NSLayoutConstraint.activate([
            committedCanvasHostView.topAnchor.constraint(equalTo: topAnchor),
            committedCanvasHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            committedCanvasHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            committedCanvasHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            realtimeDraftHostView.topAnchor.constraint(equalTo: topAnchor),
            realtimeDraftHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            realtimeDraftHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            realtimeDraftHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            interactionOverlayView.topAnchor.constraint(equalTo: topAnchor),
            interactionOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            interactionOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            interactionOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: HandDrawingCanvasSurfaceState) {
        committedCanvasHostView.apply(state: state.committedHost)
        realtimeDraftHostView.apply(state: state.realtimeDraftHost)
        interactionOverlayView.apply(state: state.interactionOverlay)
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
        let inputBatch = makeInputBatch(
            from: touch,
            event: event,
            includePredictedTouches: liveInputConfiguration.includesPredictedTouches
        )
        guard
            inputBatch.committedSamples.isEmpty == false
                || inputBatch.predictedSamples.isEmpty == false
        else {
            return
        }
        onPencilStrokeMoved?(inputBatch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = matchingActivePencilTouch(in: touches) else {
            return
        }
        activePencilTouchID = nil
        let inputBatch = makeInputBatch(
            from: touch,
            event: event,
            includePredictedTouches: false
        )
        onPencilStrokeEnded?(inputBatch)
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

    private func makeInputBatch(
        from touch: UITouch,
        event: UIEvent?,
        includePredictedTouches: Bool
    ) -> HandDrawingLiveInputBatch {
        let committedSamples = (event?.coalescedTouches(for: touch) ?? [touch])
            .compactMap(makeSample(from:))
        let predictedSamples: [HandDrawingInputSample]
        if
            includePredictedTouches,
            let predictedTouches = event?.predictedTouches(for: touch)
        {
            predictedSamples = predictedTouches
                .prefix(liveInputConfiguration.maximumPredictedSampleCount)
                .compactMap(makeSample(from:))
        } else {
            predictedSamples = []
        }
        return HandDrawingLiveInputBatch(
            committedSamples: committedSamples,
            predictedSamples: predictedSamples
        )
    }

    private func makeSample(from touch: UITouch) -> HandDrawingInputSample? {
        guard touch.type == .pencil else {
            return nil
        }
        let maximumPossibleForce = max(touch.maximumPossibleForce, 1)
        return HandDrawingInputSample(
            location: touch.location(in: self),
            force: touch.force / maximumPossibleForce,
            timestamp: touch.timestamp,
            azimuthRadians: touch.azimuthAngle(in: self),
            altitudeRadians: touch.altitudeAngle
        )
    }

}

private final class HandDrawingCommittedCanvasHostView: UIView {
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: HandDrawingCommittedCanvasHostState) {
        if let committedImage = state.output.image {
            imageView.image = UIImage(cgImage: committedImage)
        } else {
            imageView.image = nil
        }
    }
}

private protocol HandDrawingRealtimeDraftRendererHosting: AnyObject {
    var view: UIView { get }

    func apply(state: HandDrawingRealtimeDraftHostState)
}

private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting
    private var routingState: HandDrawingRealtimeDraftHostRoutingState

    init(
        rendererHost: HandDrawingRealtimeDraftRendererHosting = HandDrawingCPURealtimeDraftRendererView()
    ) {
        self.rendererHost = rendererHost
        let initialBackend = Self.installedBackend(for: rendererHost)
        routingState = HandDrawingRealtimeDraftHostRoutingState(
            installedRendererBackend: initialBackend,
            satisfiedResolvedBackend: initialBackend
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        installRendererHost(rendererHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRendererHost(_ rendererHost: HandDrawingRealtimeDraftRendererHosting) {
        guard rendererHost !== self.rendererHost else {
            return
        }
        self.rendererHost.view.removeFromSuperview()
        self.rendererHost = rendererHost
        installRendererHost(rendererHost)
    }

    func apply(state: HandDrawingRealtimeDraftHostState) {
        installPreferredRendererIfNeeded(for: state.preferredBackend)
        rendererHost.apply(state: state)
    }

    private func installPreferredRendererIfNeeded(
        for preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) {
        let resolvedBackend = Self.resolveBackend(from: preferredBackend)
        switch resolvedBackend {
        case .cpu:
            let switchAction = routingState.resolveSwitchAction(for: .cpu)
            if switchAction == .installCPU {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            }
        case .gpuPreferred:
            #if canImport(MetalKit)
            guard routingState.satisfiedResolvedBackend != .gpuPreferred else {
                return
            }
            let gpuRendererHost = HandDrawingGPURealtimeDraftRendererView
                .makeIfSupported()
            let switchAction = routingState.resolveSwitchAction(
                for: .gpuPreferred,
                gpuRendererCreationSucceeded: gpuRendererHost != nil
            )
            switch switchAction {
            case .none:
                break
            case .installCPU:
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            case .installGPU:
                guard let gpuRendererHost else {
                    return
                }
                setRendererHost(gpuRendererHost)
            }
            #else
            let switchAction = routingState.resolveSwitchAction(for: .cpu)
            if switchAction == .installCPU {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            }
            #endif
        }
    }

    private static func resolveBackend(
        from preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) -> HandDrawingRealtimeDraftBackendPreference {
        switch preferredBackend {
        case .cpu:
            return .cpu
        case .gpuPreferred:
            #if canImport(MetalKit)
            return HandDrawingGPURealtimeDraftRendererView.isSupported
                ? .gpuPreferred
                : .cpu
            #else
            return .cpu
            #endif
        }
    }

    private static func installedBackend(
        for rendererHost: HandDrawingRealtimeDraftRendererHosting
    ) -> HandDrawingRealtimeDraftBackendPreference {
        #if canImport(MetalKit)
        if rendererHost is HandDrawingGPURealtimeDraftRendererView {
            return .gpuPreferred
        }
        #endif
        return .cpu
    }

    private func installRendererHost(
        _ rendererHost: HandDrawingRealtimeDraftRendererHosting
    ) {
        let hostedView = rendererHost.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private final class HandDrawingCPURealtimeDraftRendererView: UIView, HandDrawingRealtimeDraftRendererHosting {
    var view: UIView { self }

    private let renderer = HandDrawingCPURealtimeBrushRenderer()
    private var lastAppliedRevision: UInt64?
    private var renderOutput: HandDrawingRealtimeDraftRenderOutput = .none {
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

    func apply(state: HandDrawingRealtimeDraftHostState) {
        guard lastAppliedRevision != state.revision else {
            return
        }
        lastAppliedRevision = state.revision
        renderOutput = renderer.apply(packet: state.packet)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        if let resolvedState = renderOutput.resolvedState {
            for snapshot in resolvedState.renderSnapshots {
                HandDrawingStrokeRasterizer.draw(snapshot, in: context)
            }
        }
        context.restoreGState()
    }
}

#if canImport(MetalKit)
private struct HandDrawingRealtimeDraftMetalStampInstance {
    var center: SIMD2<Float>
    var radii: SIMD2<Float>
    var rotationSinCos: SIMD2<Float>
    var padding0: SIMD2<Float> = .zero
    var color: SIMD4<Float>
    var opacity: Float
    var padding1: SIMD3<Float> = .zero
}

private enum HandDrawingGPURealtimeDraftRendererSetupError: Error {
    case commandQueueUnavailable
    case pipelineFunctionMissing
}

private final class HandDrawingGPURealtimeDraftRendererView: MTKView, HandDrawingRealtimeDraftRendererHosting, MTKViewDelegate {
    var view: UIView { self }

    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    private let accumulator = HandDrawingRealtimeDraftPacketAccumulator()
    private let metalCommandQueue: MTLCommandQueue
    private let renderPipelineState: MTLRenderPipelineState
    private var lastAppliedRevision: UInt64?
    private var renderState: HandDrawingRealtimeDraftRenderState?
    private var stampInstanceBuffer: MTLBuffer?
    private var stampInstanceCount = 0

    static func makeIfSupported() -> HandDrawingGPURealtimeDraftRendererView? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        do {
            return try HandDrawingGPURealtimeDraftRendererView(device: device)
        } catch {
            #if DEBUG
            print(
                "[HandDrawingDraftRender][GPUSetup] " +
                "failedToCreateRenderer error=\(error)"
            )
            #endif
            return nil
        }
    }

    private init(device: MTLDevice) throws {
        guard let metalCommandQueue = device.makeCommandQueue() else {
            throw HandDrawingGPURealtimeDraftRendererSetupError.commandQueueUnavailable
        }
        self.metalCommandQueue = metalCommandQueue
        renderPipelineState = try Self.makeRenderPipelineState(device: device)
        super.init(frame: .zero, device: device)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        colorPixelFormat = .bgra8Unorm
        enableSetNeedsDisplay = true
        isPaused = true
        isOpaque = false
        isUserInteractionEnabled = false
        framebufferOnly = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let resolvedScale = max(window?.screen.scale ?? UIScreen.main.scale, 1)
        contentScaleFactor = resolvedScale
        drawableSize = CGSize(
            width: max(bounds.width * resolvedScale, 1),
            height: max(bounds.height * resolvedScale, 1)
        )
    }

    func apply(state: HandDrawingRealtimeDraftHostState) {
        guard lastAppliedRevision != state.revision else {
            return
        }
        lastAppliedRevision = state.revision
        renderState = accumulator.apply(packet: state.packet)
        rebuildStampInstanceBuffer()
        setNeedsDisplay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // MTKView 已自动处理 drawable 尺寸同步，这里不需要额外逻辑。
    }

    func draw(in view: MTKView) {
        guard
            let currentDrawable,
            let renderPassDescriptor = currentRenderPassDescriptor,
            let commandBuffer = metalCommandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            return
        }

        renderEncoder.setRenderPipelineState(renderPipelineState)
        if
            let stampInstanceBuffer,
            stampInstanceCount > 0
        {
            var canvasSize = SIMD2<Float>(
                Float(max(bounds.width, 1)),
                Float(max(bounds.height, 1))
            )
            renderEncoder.setVertexBuffer(stampInstanceBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(
                &canvasSize,
                length: MemoryLayout<SIMD2<Float>>.stride,
                index: 1
            )
            renderEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: stampInstanceCount
            )
        }
        renderEncoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    private func rebuildStampInstanceBuffer() {
        let stampInstances = Self.makeStampInstances(from: renderState)
        stampInstanceCount = stampInstances.count
        guard
            stampInstances.isEmpty == false,
            let device
        else {
            stampInstanceBuffer = nil
            return
        }

        stampInstances.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                stampInstanceBuffer = nil
                return
            }
            stampInstanceBuffer = device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
    }

    private static func makeStampInstances(
        from renderState: HandDrawingRealtimeDraftRenderState?
    ) -> [HandDrawingRealtimeDraftMetalStampInstance] {
        guard let renderState else {
            return []
        }
        return renderState.renderSnapshots.flatMap { snapshot in
            snapshot.resolvedStamps.map { stamp in
                HandDrawingRealtimeDraftMetalStampInstance(
                    center: SIMD2<Float>(
                        Float(stamp.point.x),
                        Float(stamp.point.y)
                    ),
                    radii: SIMD2<Float>(
                        Float(stamp.majorRadius),
                        Float(stamp.minorRadius)
                    ),
                    rotationSinCos: SIMD2<Float>(
                        Float(sin(stamp.rotationRadians)),
                        Float(cos(stamp.rotationRadians))
                    ),
                    color: SIMD4<Float>(
                        Float(snapshot.color.red),
                        Float(snapshot.color.green),
                        Float(snapshot.color.blue),
                        Float(snapshot.color.alpha)
                    ),
                    opacity: Float(stamp.opacity)
                )
            }
        }
    }

    private static func makeRenderPipelineState(
        device: MTLDevice
    ) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        guard
            let vertexFunction = library.makeFunction(
                name: "handDrawingDraftVertex"
            ),
            let fragmentFunction = library.makeFunction(
                name: "handDrawingDraftFragment"
            )
        else {
            throw HandDrawingGPURealtimeDraftRendererSetupError
                .pipelineFunctionMissing
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct StampInstance {
        float2 center;
        float2 radii;
        float2 rotationSinCos;
        float2 padding0;
        float4 color;
        float opacity;
        float3 padding1;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 unitPosition;
        float4 color;
        float opacity;
    };

    vertex VertexOut handDrawingDraftVertex(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant StampInstance *instances [[buffer(0)]],
        constant float2 &canvasSize [[buffer(1)]]
    ) {
        constant float2 unitQuad[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };

        StampInstance instance = instances[instanceID];
        float2 unitPosition = unitQuad[vertexID];
        float sinTheta = instance.rotationSinCos.x;
        float cosTheta = instance.rotationSinCos.y;
        float2 localPosition = float2(
            unitPosition.x * instance.radii.x,
            unitPosition.y * instance.radii.y
        );
        float2 rotatedPosition = float2(
            (localPosition.x * cosTheta) - (localPosition.y * sinTheta),
            (localPosition.x * sinTheta) + (localPosition.y * cosTheta)
        );
        float2 worldPosition = rotatedPosition + instance.center;
        float2 clipPosition = float2(
            ((worldPosition.x / canvasSize.x) * 2.0) - 1.0,
            1.0 - ((worldPosition.y / canvasSize.y) * 2.0)
        );

        VertexOut out;
        out.position = float4(clipPosition, 0.0, 1.0);
        out.unitPosition = unitPosition;
        out.color = instance.color;
        out.opacity = instance.opacity;
        return out;
    }

    fragment half4 handDrawingDraftFragment(VertexOut in [[stage_in]]) {
        float radialDistance = length(in.unitPosition);
        float feather = max(fwidth(radialDistance), 0.001);
        float coverage = 1.0 - smoothstep(
            1.0 - feather,
            1.0 + feather,
            radialDistance
        );
        if (coverage <= 0.0) {
            discard_fragment();
        }

        return half4(
            half3(in.color.rgb),
            half(in.color.a * in.opacity * coverage)
        );
    }
    """
}
#endif

private final class HandDrawingCanvasInteractionOverlayView: UIView {
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

    func apply(state: HandDrawingCanvasInteractionOverlayState) {
        lassoPathPoints = state.lassoPathPoints
        selectedStrokeBounds = state.selectedStrokeBounds
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
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
