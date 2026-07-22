#if os(macOS)
import AppKit
import QuartzCore

final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
        // AppRoot can force an early layout pass before the controller computes
        // the real toolbar frame. Bootstrap with a legal non-zero size so the
        // internal chrome insets do not conflict against a transient width == 0.
        static let minimumBootstrapSize = CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: CGSize(
                width: CanvasToolbarChromeMetrics.buttonEdge,
                height: CanvasToolbarChromeMetrics.buttonEdge
            )
        )
    }
    private static let isTransitionFrameDiagnosticLoggingEnabled = true

    private let backgroundView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = Layout.cornerRadius
        view.layer?.borderWidth = 1
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = Layout.shadowOpacity
        view.layer?.shadowRadius = Layout.shadowRadius
        view.layer?.shadowOffset = Layout.shadowOffset
        return view
    }()

    // Clip toolbar content during collapse without squeezing button constraints.
    private let contentClipView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.masksToBounds = true
        return view
    }()

    private let buttonsStackView: macOSCanvasChromeStackView = {
        let stackView = macOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.wantsLayer = true
        stackView.orientation = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = CanvasToolbarChromeMetrics.spacing
        return stackView
    }()

    private var registeredButtons: [CanvasToolbarItemID: NSButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var isTransitionRendering = false
    private var transitionInteractivity = true
    private var latestItemStates: [CanvasToolbarItemState] = []
    private var transitionFrameDiagnosticWorkItems: [DispatchWorkItem] = []

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: Self.bootstrapFrame(from: frameRect))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        addSubview(backgroundView)
        addSubview(contentClipView)
        contentClipView.addSubview(buttonsStackView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentClipView.topAnchor.constraint(equalTo: topAnchor),
            contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonsStackView.topAnchor.constraint(
                equalTo: contentClipView.topAnchor,
                constant: CanvasToolbarChromeMetrics.verticalInset
            ),
            buttonsStackView.leadingAnchor.constraint(
                equalTo: contentClipView.leadingAnchor,
                constant: CanvasToolbarChromeMetrics.horizontalInset
            ),
            buttonsStackView.trailingAnchor.constraint(
                equalTo: contentClipView.trailingAnchor,
                constant: -CanvasToolbarChromeMetrics.horizontalInset
            )
        ])
        updateDockEdgeLayout()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private static func bootstrapFrame(from frameRect: CGRect) -> CGRect {
        CGRect(
            origin: frameRect.origin,
            size: CGSize(
                width: max(frameRect.width, Layout.minimumBootstrapSize.width),
                height: max(frameRect.height, Layout.minimumBootstrapSize.height)
            )
        )
    }

    func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
        registeredButtons = buttons
        buttons.values.forEach { button in
            ensureSquareSize(for: button)
        }
    }

    func render(_ state: CanvasToolbarState) {
        clearTransitionAnimations()
        isTransitionRendering = false
        preferredAxisOverride = state.preferredAxis
        dockEdge = state.placement.preferredEdge
        transitionInteractivity = true
        backgroundView.isHidden = state.showsBackground == false
        applyContentTransitionAppearance(alpha: 1, scale: 1, animated: false)
        isHidden = state.items.isEmpty
        syncButtons(with: state.items)
    }

    func renderTransition(
        _ presentation: CanvasToolbarTransitionPresentation,
        animated explicitAnimated: Bool? = nil
    ) {
        let shouldAnimate = explicitAnimated ?? shouldAnimateTransitionChanges
        if shouldAnimate == false {
            clearTransitionAnimations()
        }
        logTransitionRenderRequest(
            presentation: presentation,
            animated: shouldAnimate
        )
        isTransitionRendering = true
        transitionInteractivity = presentation.isInteractive
        backgroundView.isHidden = presentation.showsBackground == false
        applyTransitionFrame(presentation.frame, animated: shouldAnimate)
        syncButtons(with: presentation.itemStates)
        applyContentTransitionAppearance(
            alpha: presentation.contentAlpha,
            scale: presentation.contentScale,
            animated: shouldAnimate
        )
        isHidden = presentation.keepsHostVisible == false
    }

    func applyTransitionImmediately(
        _ presentation: CanvasToolbarTransitionPresentation
    ) {
        clearTransitionAnimations()
        logTransitionRenderRequest(
            presentation: presentation,
            animated: false
        )
        isTransitionRendering = true
        transitionInteractivity = presentation.isInteractive
        backgroundView.isHidden = presentation.showsBackground == false
        applyTransitionFrameImmediately(presentation.frame)
        syncButtons(with: presentation.itemStates)
        applyContentTransitionAppearance(
            alpha: presentation.contentAlpha,
            scale: presentation.contentScale,
            animated: false
        )
        isHidden = presentation.keepsHostVisible == false
    }

    func completeTransition(applying state: CanvasToolbarState) {
        isTransitionRendering = false
        render(state)
    }

    func cancelTransition(applying state: CanvasToolbarState) {
        isTransitionRendering = false
        render(state)
    }

    func measuredContentSize() -> CGSize {
        guard buttonsStackView.arrangedSubviews.isEmpty == false else {
            return .zero
        }

        let stackSize = buttonsStackView.fittingSize
        return CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: stackSize
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard transitionInteractivity else {
            return nil
        }
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    private func updateAppearance() {
        let appearance = effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            backgroundView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.controlBackgroundColor.withAlphaComponent(0.92),
                for: appearance
            )
            backgroundView.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.separatorColor.withAlphaComponent(0.35),
                for: appearance
            )
            for itemState in latestItemStates {
                guard let button = registeredButtons[itemState.id] else {
                    continue
                }
                updateLayerAppearance(
                    itemState,
                    on: button,
                    for: appearance
                )
            }
        }
    }

    private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
        latestItemStates = itemStates
        let orderedButtons: [NSButton] = itemStates.compactMap { itemState in
            guard let button = registeredButtons[itemState.id] else {
                return nil
            }
            applyAppearance(itemState, to: button)
            return button
        }

        buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
            buttonsStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        orderedButtons.forEach { button in
            buttonsStackView.addArrangedSubview(button)
        }
    }

    private func updateDockEdgeLayout() {
        let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
        buttonsStackView.orientation = preferredAxis == .horizontal
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = preferredAxis == .horizontal
            ? .centerY
            : .trailing
    }

    private func applyContentTransitionAppearance(
        alpha: CGFloat,
        scale: CGFloat,
        animated: Bool
    ) {
        let clampedAlpha = min(max(alpha, 0), 1)
        let clampedScale = max(scale, 0)
        if animated {
            buttonsStackView.animator().alphaValue = clampedAlpha
        } else {
            buttonsStackView.alphaValue = clampedAlpha
        }

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(NSAnimationContext.current.duration)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeInEaseOut)
            )
        } else {
            CATransaction.setDisableActions(true)
        }
        buttonsStackView.layer?.setAffineTransform(
            CGAffineTransform(scaleX: clampedScale, y: clampedScale)
        )
        CATransaction.commit()
    }

    private var shouldAnimateTransitionChanges: Bool {
        NSAnimationContext.current.duration > 0
    }

    private func applyTransitionFrame(
        _ targetFrame: CGRect,
        animated: Bool
    ) {
        guard frame != targetFrame else {
            logTransitionFrameRequest(
                event: "applyTransitionFrame.noop",
                targetFrame: targetFrame,
                animated: animated
            )
            return
        }

        logTransitionFrameRequest(
            event: "applyTransitionFrame.begin",
            targetFrame: targetFrame,
            animated: animated
        )

        if animated {
            scheduleTransitionFrameDiagnostics(
                sourceFrame: frame,
                targetFrame: targetFrame,
                duration: NSAnimationContext.current.duration
            )
            animator().setFrameOrigin(targetFrame.origin)
            animator().setFrameSize(targetFrame.size)
        } else {
            cancelTransitionFrameDiagnostics()
            frame = targetFrame
            logTransitionFrameSample(
                label: "immediate",
                sourceFrame: frame,
                targetFrame: targetFrame
            )
        }
    }

    private func applyTransitionFrameImmediately(_ targetFrame: CGRect) {
        guard frame != targetFrame else {
            logTransitionFrameRequest(
                event: "applyTransitionFrameImmediately.noop",
                targetFrame: targetFrame,
                animated: false
            )
            return
        }

        let sourceFrame = frame
        logTransitionFrameRequest(
            event: "applyTransitionFrameImmediately.begin",
            targetFrame: targetFrame,
            animated: false
        )

        cancelTransitionFrameDiagnostics()
        frame = targetFrame
        logTransitionFrameSample(
            label: "immediate",
            sourceFrame: sourceFrame,
            targetFrame: targetFrame
        )
    }

    private func clearTransitionAnimations() {
        cancelTransitionFrameDiagnostics()
        layer?.removeAllAnimations()
        backgroundView.layer?.removeAllAnimations()
        contentClipView.layer?.removeAllAnimations()
        buttonsStackView.layer?.removeAllAnimations()
    }

    private func scheduleTransitionFrameDiagnostics(
        sourceFrame: CGRect,
        targetFrame: CGRect,
        duration: TimeInterval
    ) {
        guard Self.isTransitionFrameDiagnosticLoggingEnabled else {
            return
        }

        cancelTransitionFrameDiagnostics()

        let sanitizedDuration = max(duration, 0)
        let samplePoints: [(label: String, delay: TimeInterval)] = [
            ("t0", 0),
            ("t25", sanitizedDuration * 0.25),
            ("t50", sanitizedDuration * 0.50),
            ("t75", sanitizedDuration * 0.75),
            ("t100", sanitizedDuration)
        ]

        transitionFrameDiagnosticWorkItems = samplePoints.map { samplePoint in
            let workItem = DispatchWorkItem { [weak self] in
                self?.logTransitionFrameSample(
                    label: samplePoint.label,
                    sourceFrame: sourceFrame,
                    targetFrame: targetFrame
                )
            }

            if samplePoint.delay <= 0 {
                DispatchQueue.main.async(execute: workItem)
            } else {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + samplePoint.delay,
                    execute: workItem
                )
            }
            return workItem
        }
    }

    private func cancelTransitionFrameDiagnostics() {
        transitionFrameDiagnosticWorkItems.forEach { workItem in
            workItem.cancel()
        }
        transitionFrameDiagnosticWorkItems.removeAll()
    }

    private func logTransitionFrameRequest(
        event: String,
        targetFrame: CGRect,
        animated: Bool
    ) {
        guard Self.isTransitionFrameDiagnosticLoggingEnabled else {
            return
        }

        let currentFrame = frame
        let originDelta = CGPoint(
            x: targetFrame.minX - currentFrame.minX,
            y: targetFrame.minY - currentFrame.minY
        )
        let sizeDelta = CGSize(
            width: targetFrame.width - currentFrame.width,
            height: targetFrame.height - currentFrame.height
        )

        print(
            "[Canvas macOS][ToolbarFrameDiagnostics] " +
            "event=\(event) " +
            "animated=\(animated) " +
            "hostIsFlipped=\(isFlipped) " +
            "superviewIsFlipped=\(superview?.isFlipped ?? false) " +
            "currentFrame=\(describe(rect: currentFrame)) " +
            "targetFrame=\(describe(rect: targetFrame)) " +
            "originDelta=\(describe(point: originDelta)) " +
            "sizeDelta=\(describe(size: sizeDelta))"
        )
    }

    private func logTransitionFrameSample(
        label: String,
        sourceFrame: CGRect,
        targetFrame: CGRect
    ) {
        guard Self.isTransitionFrameDiagnosticLoggingEnabled else {
            return
        }

        let modelFrame = frame
        let presentationFrame = layer?.presentation()?.frame
        let presentationDescription = presentationFrame.map(describe(rect:)) ?? "nil"
        let modelDeltaFromSource = CGPoint(
            x: modelFrame.minX - sourceFrame.minX,
            y: modelFrame.minY - sourceFrame.minY
        )
        let presentationDeltaFromSource = presentationFrame.map { frame in
            CGPoint(
                x: frame.minX - sourceFrame.minX,
                y: frame.minY - sourceFrame.minY
            )
        }
        let presentationDeltaDescription = presentationDeltaFromSource
            .map(describe(point:)) ?? "nil"
        let targetDeltaFromSource = CGPoint(
            x: targetFrame.minX - sourceFrame.minX,
            y: targetFrame.minY - sourceFrame.minY
        )

        print(
            "[Canvas macOS][ToolbarFrameDiagnostics] " +
            "event=animationSample " +
            "sample=\(label) " +
            "sourceFrame=\(describe(rect: sourceFrame)) " +
            "targetFrame=\(describe(rect: targetFrame)) " +
            "modelFrame=\(describe(rect: modelFrame)) " +
            "presentationFrame=\(presentationDescription) " +
            "targetDeltaFromSource=\(describe(point: targetDeltaFromSource)) " +
            "modelDeltaFromSource=\(describe(point: modelDeltaFromSource)) " +
            "presentationDeltaFromSource=\(presentationDeltaDescription)"
        )
    }

    private func logTransitionRenderRequest(
        presentation: CanvasToolbarTransitionPresentation,
        animated: Bool
    ) {
        let targetOriginDelta = CGPoint(
            x: presentation.frame.origin.x - frame.origin.x,
            y: presentation.frame.origin.y - frame.origin.y
        )
        let targetSizeDelta = CGSize(
            width: presentation.frame.size.width - frame.size.width,
            height: presentation.frame.size.height - frame.size.height
        )

        print(
            "[Canvas macOS][ToolbarHostTransition] " +
            "animated=\(animated) " +
            "dockEdge=\(dockEdge.rawValue) " +
            "hostIsFlipped=\(isFlipped) " +
            "superviewIsFlipped=\(superview?.isFlipped ?? false) " +
            "currentFrame=\(describe(rect: frame)) " +
            "targetFrame=\(describe(rect: presentation.frame)) " +
            "originDelta=\(describe(point: targetOriginDelta)) " +
            "sizeDelta=\(describe(size: targetSizeDelta)) " +
            "contentAlpha=\(formatCoordinate(presentation.contentAlpha)) " +
            "contentScale=\(formatCoordinate(presentation.contentScale)) " +
            "keepsHostVisible=\(presentation.keepsHostVisible)"
        )
    }

    private func applyAppearance(
        _ itemState: CanvasToolbarItemState,
        to button: NSButton
    ) {
        let preservesVisualRole = itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
        let foregroundColor: NSColor = preservesVisualRole
            ? foregroundColor(for: itemState.visualRole)
            : .secondaryLabelColor
        let accessibilityDescription: String
        if let accessibilityValue = itemState.accessibilityValue {
            accessibilityDescription = "\(itemState.accessibilityLabel) (\(accessibilityValue))"
        } else {
            accessibilityDescription = itemState.accessibilityLabel
        }

        button.title = ""
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.borderWidth = 1
        PlatformLayerAppearance.performWithoutAnimations {
            updateLayerAppearance(
                itemState,
                on: button,
                for: effectiveAppearance
            )
        }
        button.contentTintColor = foregroundColor
        button.toolTip = accessibilityDescription
        button.image = NSImage(
            systemSymbolName: itemState.systemImageName,
            accessibilityDescription: accessibilityDescription
        )
        button.isEnabled = itemState.isEnabled
    }

    private func updateLayerAppearance(
        _ itemState: CanvasToolbarItemState,
        on button: NSButton,
        for appearance: NSAppearance
    ) {
        let preservesVisualRole =
            itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
        let resolvedBackgroundColor = preservesVisualRole
            ? backgroundColor(for: itemState.visualRole)
            : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
        button.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.24),
            for: appearance
        )
        button.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            resolvedBackgroundColor,
            for: appearance
        )
    }

    private func foregroundColor(
        for visualRole: CanvasToolbarItemVisualRole
    ) -> NSColor {
        switch visualRole {
        case .neutral:
            return .labelColor
        case .accent,
             .success,
             .warning,
             .danger:
            return .white
        }
    }

    private func backgroundColor(
        for visualRole: CanvasToolbarItemVisualRole
    ) -> NSColor {
        switch visualRole {
        case .neutral:
            return .controlBackgroundColor
        case .accent:
            return .controlAccentColor
        case .success:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .danger:
            return .systemRed
        }
    }

    private func ensureSquareSize(for button: NSButton) {
        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
            widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
            widthConstraint.isActive = true
        }

        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
            let heightConstraint = button.heightAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
            heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
            heightConstraint.isActive = true
        }
    }

    private func describe(point: CGPoint) -> String {
        "{\(formatCoordinate(point.x)), \(formatCoordinate(point.y))}"
    }

    private func describe(size: CGSize) -> String {
        "{\(formatCoordinate(size.width)), \(formatCoordinate(size.height))}"
    }

    private func describe(rect: CGRect) -> String {
        "{{\(formatCoordinate(rect.origin.x)), \(formatCoordinate(rect.origin.y))}, {\(formatCoordinate(rect.size.width)), \(formatCoordinate(rect.size.height))}}"
    }

    private func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
#endif
