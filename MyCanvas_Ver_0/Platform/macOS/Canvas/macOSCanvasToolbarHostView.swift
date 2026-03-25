#if os(macOS)
import AppKit

final class macOSCanvasToolbarHostView: NSView {
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

    private let buttonsStackView: macOSCanvasChromeStackView = {
        let stackView = macOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = Layout.spacing
        return stackView
    }()

    private var registeredButtons: [CanvasToolbarItemID: NSButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        preferredAxisOverride = state.preferredAxis
        dockEdge = state.placement.preferredEdge
        backgroundView.isHidden = state.showsBackground == false
        isHidden = state.items.isEmpty
        syncButtons(with: state.items)
    }

    func measuredContentSize() -> CGSize {
        guard buttonsStackView.arrangedSubviews.isEmpty == false else {
            return .zero
        }

        let stackSize = buttonsStackView.fittingSize
        return CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: stackSize.width + (Layout.horizontalInset * 2),
                height: stackSize.height + (Layout.verticalInset * 2)
            )
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
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
}
#endif
