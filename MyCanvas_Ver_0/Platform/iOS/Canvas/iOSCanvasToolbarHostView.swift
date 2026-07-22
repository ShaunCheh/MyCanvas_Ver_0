#if os(iOS)
import UIKit

final class iOSCanvasToolbarHostView: UIView, UIScrollViewDelegate {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.92)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Layout.shadowOpacity
        view.layer.shadowRadius = Layout.shadowRadius
        view.layer.shadowOffset = Layout.shadowOffset
        return view
    }()

    // Clip toolbar content during collapse without squeezing button constraints.
    private let contentClipView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()

    private let contentScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        return scrollView
    }()

    private let buttonsStackView: iOSCanvasChromeStackView = {
        let stackView = iOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = CanvasToolbarChromeMetrics.spacing
        return stackView
    }()

    private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var isTransitionRendering = false
    private var transitionInteractivity = true
    private var horizontalStackHeightConstraint: NSLayoutConstraint?
    private var verticalStackWidthConstraint: NSLayoutConstraint?
    private var rememberedHorizontalContentOffset: CGFloat = 0
    private var rememberedVerticalContentOffset: CGFloat = 0
    private var isProgrammaticallyRestoringContentOffset = false
    private var shouldRestoreRememberedContentOffset = false

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        addSubview(contentClipView)
        contentClipView.addSubview(contentScrollView)
        contentScrollView.addSubview(buttonsStackView)
        contentScrollView.delegate = self

        let horizontalStackHeightConstraint = buttonsStackView.heightAnchor.constraint(
            equalTo: contentScrollView.frameLayoutGuide.heightAnchor,
            constant: -(CanvasToolbarChromeMetrics.verticalInset * 2)
        )
        let verticalStackWidthConstraint = buttonsStackView.widthAnchor.constraint(
            equalTo: contentScrollView.frameLayoutGuide.widthAnchor,
            constant: -(CanvasToolbarChromeMetrics.horizontalInset * 2)
        )
        self.horizontalStackHeightConstraint = horizontalStackHeightConstraint
        self.verticalStackWidthConstraint = verticalStackWidthConstraint

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentClipView.topAnchor.constraint(equalTo: topAnchor),
            contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentScrollView.topAnchor.constraint(equalTo: contentClipView.topAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: contentClipView.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: contentClipView.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: contentClipView.bottomAnchor),
            buttonsStackView.topAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.topAnchor,
                constant: CanvasToolbarChromeMetrics.verticalInset
            ),
            buttonsStackView.leadingAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.leadingAnchor,
                constant: CanvasToolbarChromeMetrics.horizontalInset
            ),
            buttonsStackView.trailingAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.trailingAnchor,
                constant: -CanvasToolbarChromeMetrics.horizontalInset
            ),
            buttonsStackView.bottomAnchor.constraint(
                equalTo: contentScrollView.contentLayoutGuide.bottomAnchor,
                constant: -CanvasToolbarChromeMetrics.verticalInset
            )
        ])
        updateDockEdgeLayout()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    func registerButtons(_ buttons: [CanvasToolbarItemID: UIButton]) {
        registeredButtons = buttons
        buttons.values.forEach { button in
            ensureSquareSize(for: button)
        }
    }

    func render(_ state: CanvasToolbarState) {
        isTransitionRendering = false
        preferredAxisOverride = state.preferredAxis
        dockEdge = state.placement.preferredEdge
        transitionInteractivity = true
        backgroundView.isHidden = state.showsBackground == false
        applyContentTransitionAppearance(alpha: 1, scale: 1)
        isHidden = state.items.isEmpty
        syncButtons(with: state.items)
    }

    func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
        isTransitionRendering = true
        transitionInteractivity = presentation.isInteractive
        backgroundView.isHidden = presentation.showsBackground == false
        if frame != presentation.frame {
            frame = presentation.frame
        }
        syncButtons(with: presentation.itemStates)
        applyContentTransitionAppearance(
            alpha: presentation.contentAlpha,
            scale: presentation.contentScale
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

        let stackSize = buttonsStackView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: stackSize
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard transitionInteractivity else {
            return nil
        }
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        restoreRememberedContentOffsetIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard
            isProgrammaticallyRestoringContentOffset == false,
            shouldRestoreRememberedContentOffset == false
        else {
            return
        }

        rememberCurrentContentOffset()
    }

    private func updateAppearance() {
        PlatformLayerAppearance.performWithoutAnimations {
            backgroundView.layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
                UIColor.separator.withAlphaComponent(0.24),
                for: traitCollection
            )
        }
    }

    private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
        rememberCurrentContentOffsetIfStable()
        shouldRestoreRememberedContentOffset = true

        let orderedButtons: [UIButton] = itemStates.compactMap { itemState in
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
        setNeedsLayout()
    }

    private func updateDockEdgeLayout() {
        rememberCurrentContentOffsetIfStable()

        let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
        let isHorizontal = preferredAxis == .horizontal
        buttonsStackView.axis = preferredAxis == .horizontal
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = preferredAxis == .horizontal
            ? .center
            : .trailing
        horizontalStackHeightConstraint?.isActive = isHorizontal
        verticalStackWidthConstraint?.isActive = isHorizontal == false
        contentScrollView.alwaysBounceHorizontal = isHorizontal
        contentScrollView.alwaysBounceVertical = isHorizontal == false
        contentScrollView.showsHorizontalScrollIndicator = isHorizontal
        contentScrollView.showsVerticalScrollIndicator = isHorizontal == false

        shouldRestoreRememberedContentOffset = true
        setNeedsLayout()
    }

    private func rememberCurrentContentOffsetIfStable() {
        guard shouldRestoreRememberedContentOffset == false else {
            return
        }

        rememberCurrentContentOffset()
    }

    private func rememberCurrentContentOffset() {
        guard contentScrollView.bounds.isEmpty == false else {
            return
        }

        let currentOffset = contentScrollView.contentOffset
        if currentOffset.x.isFinite {
            rememberedHorizontalContentOffset = max(currentOffset.x, 0)
        }
        if currentOffset.y.isFinite {
            rememberedVerticalContentOffset = max(currentOffset.y, 0)
        }
    }

    private func restoreRememberedContentOffsetIfNeeded() {
        guard shouldRestoreRememberedContentOffset else {
            return
        }

        let contentSize = contentScrollView.contentSize
        let visibleSize = contentScrollView.bounds.size
        guard
            contentSize.width.isFinite,
            contentSize.height.isFinite,
            visibleSize.width.isFinite,
            visibleSize.height.isFinite,
            visibleSize.width > 0,
            visibleSize.height > 0
        else {
            return
        }

        let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
        let maxOffsetX = max(contentSize.width - visibleSize.width, 0)
        let maxOffsetY = max(contentSize.height - visibleSize.height, 0)
        let restoredOffset: CGPoint

        switch preferredAxis {
        case .horizontal:
            restoredOffset = CGPoint(
                x: min(rememberedHorizontalContentOffset, maxOffsetX),
                y: 0
            )
        case .vertical:
            restoredOffset = CGPoint(
                x: 0,
                y: min(rememberedVerticalContentOffset, maxOffsetY)
            )
        }

        shouldRestoreRememberedContentOffset = false
        guard contentScrollView.contentOffset != restoredOffset else {
            return
        }

        isProgrammaticallyRestoringContentOffset = true
        contentScrollView.setContentOffset(restoredOffset, animated: false)
        isProgrammaticallyRestoringContentOffset = false
    }

    private func applyContentTransitionAppearance(
        alpha: CGFloat,
        scale: CGFloat
    ) {
        let clampedAlpha = min(max(alpha, 0), 1)
        let clampedScale = max(scale, 0)
        buttonsStackView.alpha = clampedAlpha
        buttonsStackView.transform = CGAffineTransform(
            scaleX: clampedScale,
            y: clampedScale
        )
    }

    private func applyAppearance(
        _ itemState: CanvasToolbarItemState,
        to button: UIButton
    ) {
        let preservesVisualRole = itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
        button.isEnabled = itemState.isEnabled

        var configuration = button.configuration ?? UIButton.Configuration.filled()
        configuration.preferredSymbolConfigurationForImage = symbolConfiguration(
            for: itemState.id
        )
        configuration.image = UIImage(systemName: itemState.systemImageName)
        configuration.title = nil
        configuration.imagePadding = 0
        configuration.baseBackgroundColor = preservesVisualRole
            ? backgroundColor(for: itemState.visualRole)
            : .systemGray3
        configuration.baseForegroundColor = preservesVisualRole
            ? foregroundColor(for: itemState.visualRole)
            : .secondaryLabel
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.accessibilityLabel = itemState.accessibilityLabel
        button.accessibilityValue = itemState.accessibilityValue
    }

    private func foregroundColor(
        for visualRole: CanvasToolbarItemVisualRole
    ) -> UIColor {
        switch visualRole {
        case .neutral:
            return .label
        case .accent,
             .success,
             .warning,
             .danger:
            return .white
        }
    }

    private func backgroundColor(
        for visualRole: CanvasToolbarItemVisualRole
    ) -> UIColor {
        switch visualRole {
        case .neutral:
            return .secondarySystemBackground
        case .accent:
            return .systemBlue
        case .success:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .danger:
            return .systemRed
        }
    }

    private func symbolConfiguration(
        for itemID: CanvasToolbarItemID
    ) -> UIImage.SymbolConfiguration {
        switch itemID {
        case .save, .undo, .redo:
            return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        case .importMedia:
            return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        case .crop, .multiSelect, .deleteSelection, .text, .markdown, .handDrawing, .arrow:
            return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        }
    }

    private func ensureSquareSize(for button: UIButton) {
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
