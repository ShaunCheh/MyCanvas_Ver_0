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

    func installButtons(_ buttons: [NSButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
            ensureSquareSize(for: button)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    private func updateDockEdgeLayout() {
        buttonsStackView.orientation = dockEdge.prefersHorizontalButtonLayout
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
            ? .centerY
            : .trailing
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
