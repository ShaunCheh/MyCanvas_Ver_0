#if os(macOS)
import AppKit
import QuartzCore

enum macOSCanvasToolbarChromeMetrics {
    static let scale: CGFloat = 0.5
    static let spacing = CanvasToolbarChromeMetrics.spacing * scale
    static let horizontalInset = CanvasToolbarChromeMetrics.horizontalInset * scale
    static let verticalInset = CanvasToolbarChromeMetrics.verticalInset * scale
    static let buttonEdge = CanvasToolbarChromeMetrics.buttonEdge * scale

    static func measuredContentSize(
        forMeasuredStackSize stackSize: CGSize
    ) -> CGSize {
        CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: stackSize.width + (horizontalInset * 2),
                height: stackSize.height + (verticalInset * 2)
            )
        )
    }
}

private final class macOSCanvasToolbarButtonSlotView: NSView {
    let button: NSButton

    init(button: NSButton) {
        self.button = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // Keep AppKit's NSButton alignment rect out of stack geometry. The slot
        // owns the visible chrome, while the button fills the exact slot frame
        // only for image drawing and event delivery.
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        button.frame = bounds
    }
}

final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18 * macOSCanvasToolbarChromeMetrics.scale
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10 * macOSCanvasToolbarChromeMetrics.scale
        static let shadowOffset = CGSize(
            width: 0,
            height: 4 * macOSCanvasToolbarChromeMetrics.scale
        )
        static let buttonCornerRadius: CGFloat = 12 * macOSCanvasToolbarChromeMetrics.scale
        // AppRoot can force an early layout pass before the controller computes
        // the real toolbar frame. Bootstrap with a legal non-zero size so the
        // internal chrome insets do not conflict against a transient width == 0.
        static let minimumBootstrapSize = macOSCanvasToolbarChromeMetrics.measuredContentSize(
            forMeasuredStackSize: CGSize(
                width: macOSCanvasToolbarChromeMetrics.buttonEdge,
                height: macOSCanvasToolbarChromeMetrics.buttonEdge
            )
        )
    }
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
        stackView.spacing = macOSCanvasToolbarChromeMetrics.spacing
        return stackView
    }()

    private var registeredButtons: [CanvasToolbarItemID: NSButton] = [:]
    private var registeredButtonSlots: [CanvasToolbarItemID: macOSCanvasToolbarButtonSlotView] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var isTransitionRendering = false
    private var transitionInteractivity = true
    private var latestItemStates: [CanvasToolbarItemState] = []

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
                constant: macOSCanvasToolbarChromeMetrics.verticalInset
            ),
            buttonsStackView.leadingAnchor.constraint(
                equalTo: contentClipView.leadingAnchor,
                constant: macOSCanvasToolbarChromeMetrics.horizontalInset
            ),
            buttonsStackView.trailingAnchor.constraint(
                equalTo: contentClipView.trailingAnchor,
                constant: -macOSCanvasToolbarChromeMetrics.horizontalInset
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
        registeredButtonSlots = buttons.mapValues { button in
            let slot = macOSCanvasToolbarButtonSlotView(button: button)
            ensureSquareSize(for: slot)
            return slot
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
        return macOSCanvasToolbarChromeMetrics.measuredContentSize(
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
                guard let slot = registeredButtonSlots[itemState.id] else {
                    continue
                }
                updateLayerAppearance(
                    itemState,
                    on: slot,
                    for: appearance
                )
            }
        }
    }

    private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
        latestItemStates = itemStates
        let orderedButtonSlots: [macOSCanvasToolbarButtonSlotView] = itemStates.compactMap { itemState in
            guard
                let button = registeredButtons[itemState.id],
                let slot = registeredButtonSlots[itemState.id]
            else {
                return nil
            }
            applyAppearance(itemState, to: button, in: slot)
            return slot
        }

        buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
            buttonsStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        orderedButtonSlots.forEach { slot in
            buttonsStackView.addArrangedSubview(slot)
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
            return
        }

        if animated {
            animator().setFrameOrigin(targetFrame.origin)
            animator().setFrameSize(targetFrame.size)
        } else {
            frame = targetFrame
        }
    }

    private func applyTransitionFrameImmediately(_ targetFrame: CGRect) {
        guard frame != targetFrame else {
            return
        }

        frame = targetFrame
    }

    private func clearTransitionAnimations() {
        layer?.removeAllAnimations()
        backgroundView.layer?.removeAllAnimations()
        contentClipView.layer?.removeAllAnimations()
        buttonsStackView.layer?.removeAllAnimations()
    }

    private func applyAppearance(
        _ itemState: CanvasToolbarItemState,
        to button: NSButton,
        in slot: macOSCanvasToolbarButtonSlotView
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
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        slot.layer?.cornerRadius = Layout.buttonCornerRadius
        slot.layer?.borderWidth = 1
        PlatformLayerAppearance.performWithoutAnimations {
            updateLayerAppearance(
                itemState,
                on: slot,
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
        on slot: macOSCanvasToolbarButtonSlotView,
        for appearance: NSAppearance
    ) {
        let preservesVisualRole =
            itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
        let resolvedBackgroundColor = preservesVisualRole
            ? backgroundColor(for: itemState.visualRole)
            : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
        slot.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.24),
            for: appearance
        )
        slot.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
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

    private func ensureSquareSize(for slot: macOSCanvasToolbarButtonSlotView) {
        if slot.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
            let widthConstraint = slot.widthAnchor.constraint(equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge)
            widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
            widthConstraint.isActive = true
        }

        if slot.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
            let heightConstraint = slot.heightAnchor.constraint(equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge)
            heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
            heightConstraint.isActive = true
        }
    }

}
#endif
