#if os(macOS)
import AppKit
import QuartzCore

final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        view.layer?.cornerRadius = Layout.cornerRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
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

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
    }

    required init?(coder: NSCoder) {
        return nil
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

    func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
        let shouldAnimate = shouldAnimateTransitionChanges
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

    private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
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
            return
        }

        if animated {
            animator().setFrameOrigin(targetFrame.origin)
            animator().setFrameSize(targetFrame.size)
        } else {
            frame = targetFrame
        }
    }

    private func clearTransitionAnimations() {
        layer?.removeAllAnimations()
        backgroundView.layer?.removeAllAnimations()
        contentClipView.layer?.removeAllAnimations()
        buttonsStackView.layer?.removeAllAnimations()
    }

    private func applyAppearance(
        _ itemState: CanvasToolbarItemState,
        to button: NSButton
    ) {
        let preservesVisualRole = itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
        let foregroundColor: NSColor = preservesVisualRole ? .white : .secondaryLabelColor
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
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.24).cgColor
        button.layer?.backgroundColor = (preservesVisualRole
            ? backgroundColor(for: itemState.visualRole)
            : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
        ).cgColor
        button.contentTintColor = foregroundColor
        button.toolTip = accessibilityDescription
        button.image = NSImage(
            systemSymbolName: itemState.systemImageName,
            accessibilityDescription: accessibilityDescription
        )
        button.isEnabled = itemState.isEnabled
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
}
#endif
