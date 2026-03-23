#if os(iOS)
import UIKit

final class iOSCanvasToolbarHostView: UIView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let buttonEdge: CGFloat = 44
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
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Layout.shadowOpacity
        view.layer.shadowRadius = Layout.shadowRadius
        view.layer.shadowOffset = Layout.shadowOffset
        return view
    }()

    private let buttonsStackView: iOSCanvasChromeStackView = {
        let stackView = iOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = Layout.spacing
        return stackView
    }()

    private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var lastLoggedRenderSignature: String?
    private var lastLoggedLayoutSignature: String?

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        addSubview(buttonsStackView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonsStackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            buttonsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            buttonsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            buttonsStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset)
        ])
        updateDockEdgeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        logLayoutIfNeeded(reason: "layoutSubviews")
    }

    func registerButtons(_ buttons: [CanvasToolbarItemID: UIButton]) {
        registeredButtons = buttons
        buttons.values.forEach { button in
            ensureSquareSize(for: button)
        }
    }

    func render(_ state: CanvasToolbarState) {
        preferredAxisOverride = state.preferredAxis
        dockEdge = state.placement.preferredEdge
        backgroundView.isHidden = state.showsBackground == false
        isHidden = state.items.isEmpty
        syncButtons(with: state.items)
        logRenderIfNeeded(state)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
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
    }

    private func updateDockEdgeLayout() {
        let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
        buttonsStackView.axis = preferredAxis == .horizontal
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = preferredAxis == .horizontal
            ? .center
            : .trailing
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
            ? .white
            : .secondaryLabel
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.accessibilityLabel = itemState.accessibilityLabel
        button.accessibilityValue = itemState.accessibilityValue
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
        case .importImage:
            return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        case .crop, .text:
            return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        }
    }

    private func ensureSquareSize(for button: UIButton) {
        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: Layout.buttonEdge)
            widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
            widthConstraint.isActive = true
        }

        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
            let heightConstraint = button.heightAnchor.constraint(equalToConstant: Layout.buttonEdge)
            heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
            heightConstraint.isActive = true
        }
    }

    private func logRenderIfNeeded(_ state: CanvasToolbarState) {
        let signature = [
            dockEdge.rawValue,
            state.preferredAxis.rawValue,
            axisDescription,
            describe(bounds),
            state.items.map { $0.id.rawValue + ":" + $0.systemImageName }.joined(separator: ",")
        ].joined(separator: "|")
        guard signature != lastLoggedRenderSignature else {
            return
        }

        lastLoggedRenderSignature = signature
        let itemSummary = state.items.map { itemState in
            "\(itemState.id.rawValue):image=\(itemState.systemImageName):enabled=\(itemState.isEnabled):active=\(itemState.isActive)"
        }.joined(separator: ", ")
        print(
            "[Canvas Toolbar Debug][iOS][Render] " +
            "dockEdge=\(dockEdge.rawValue) " +
            "preferredAxis=\(state.preferredAxis.rawValue) " +
            "stackAxis=\(axisDescription) " +
            "hostBounds=\(describe(bounds)) " +
            "items=[\(itemSummary)]"
        )
    }

    private func logLayoutIfNeeded(reason: String) {
        let buttonSummary = buttonsStackView.arrangedSubviews.compactMap { arrangedSubview in
            guard let button = arrangedSubview as? UIButton else {
                return nil
            }

            return buttonDebugSummary(button)
        }.joined(separator: ", ")
        let signature = [
            axisDescription,
            describe(bounds),
            describe(buttonsStackView.frame),
            buttonSummary
        ].joined(separator: "|")
        guard signature != lastLoggedLayoutSignature else {
            return
        }

        lastLoggedLayoutSignature = signature
        print(
            "[Canvas Toolbar Debug][iOS][Layout] " +
            "reason=\(reason) " +
            "stackAxis=\(axisDescription) " +
            "stackAlignment=\(String(describing: buttonsStackView.alignment)) " +
            "stackDistribution=\(String(describing: buttonsStackView.distribution)) " +
            "hostBounds=\(describe(bounds)) " +
            "stackFrame=\(describe(buttonsStackView.frame)) " +
            "buttons=[\(buttonSummary)]"
        )
    }

    private func buttonDebugSummary(_ button: UIButton) -> String {
        let widthConstraint = button.constraints.first {
            $0.identifier == "canvasToolbarHost.buttonWidth"
        }?.constant ?? -1
        let heightConstraint = button.constraints.first {
            $0.identifier == "canvasToolbarHost.buttonHeight"
        }?.constant ?? -1
        let itemID = registeredButtons.first { _, registeredButton in
            registeredButton === button
        }?.key.rawValue ?? "unknown"
        let configurationTitle = button.configuration?.title ?? "nil"
        return
            "\(itemID):frame=\(describe(button.frame)):" +
            "bounds=\(describe(button.bounds)):" +
            "intrinsic=\(describe(button.intrinsicContentSize)):" +
            "configTitle=\(configurationTitle):" +
            "widthC=\(format(widthConstraint)):" +
            "heightC=\(format(heightConstraint))"
    }

    private var axisDescription: String {
        buttonsStackView.axis == .horizontal ? "horizontal" : "vertical"
    }

    private func describe(_ rect: CGRect) -> String {
        "{x=\(format(rect.origin.x)), y=\(format(rect.origin.y)), w=\(format(rect.size.width)), h=\(format(rect.size.height))}"
    }

    private func describe(_ size: CGSize) -> String {
        "{w=\(format(size.width)), h=\(format(size.height))}"
    }

    private func format(_ value: CGFloat) -> String {
        guard value.isFinite else {
            return String(describing: value)
        }

        return String(format: "%.1f", Double(value))
    }
}
#endif
