#if os(macOS)
import AppKit

final class macOSCanvasTextEditorOverlayView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 10
        static let controlsSpacing: CGFloat = 10
        static let controlsBottomSpacing: CGFloat = 8
        static let fontButtonMinimumWidth: CGFloat = 48
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: NSView = {
        let view = NSView()
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

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }()

    let textView: NSTextView = {
        let textView = NSTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.lineFragmentPadding = 0
        return textView
    }()

    private let fontSizeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    private let decreaseFontSizeButton = macOSCanvasTextEditorOverlayView.makeFontSizeButton(
        title: "A-",
        accessibilityLabel: "Decrease font size"
    )

    private let increaseFontSizeButton = macOSCanvasTextEditorOverlayView.makeFontSizeButton(
        title: "A+",
        accessibilityLabel: "Increase font size"
    )

    private lazy var fontSizeControlStackView: NSStackView = {
        let stackView = NSStackView(views: [
            decreaseFontSizeButton,
            fontSizeLabel,
            increaseFontSizeButton
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = Layout.controlsSpacing
        return stackView
    }()

    var onDecreaseFontSize: (() -> Void)?
    var onIncreaseFontSize: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true
        addSubview(backgroundView)
        addSubview(fontSizeControlStackView)
        addSubview(scrollView)
        scrollView.documentView = textView
        decreaseFontSizeButton.target = self
        decreaseFontSizeButton.action = #selector(handleDecreaseFontSizeClick)
        increaseFontSizeButton.target = self
        increaseFontSizeButton.action = #selector(handleIncreaseFontSizeClick)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            decreaseFontSizeButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.fontButtonMinimumWidth
            ),
            increaseFontSizeButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.fontButtonMinimumWidth
            ),
            fontSizeControlStackView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Layout.verticalInset
            ),
            fontSizeControlStackView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Layout.horizontalInset
            ),
            fontSizeControlStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            scrollView.topAnchor.constraint(
                equalTo: fontSizeControlStackView.bottomAnchor,
                constant: Layout.controlsBottomSpacing
            ),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset)
        ])
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    func apply(
        text: String,
        style: CanvasTextStyle,
        canDecreaseFontSize: Bool,
        canIncreaseFontSize: Bool
    ) {
        if textView.string != text {
            textView.string = text
        }
        textView.font = platformFont(for: style)
        fontSizeLabel.stringValue = fontSizeDescription(for: style.fontSize)
        decreaseFontSizeButton.isEnabled = canDecreaseFontSize
        increaseFontSizeButton.isEnabled = canIncreaseFontSize
    }

    private func updateAppearance() {
        let appearance = effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            backgroundView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.controlBackgroundColor.withAlphaComponent(0.96),
                for: appearance
            )
            backgroundView.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                NSColor.separatorColor.withAlphaComponent(0.35),
                for: appearance
            )
        }
    }

    private static func makeFontSizeButton(
        title: String,
        accessibilityLabel: String
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.toolTip = accessibilityLabel
        return button
    }

    @objc
    private func handleDecreaseFontSizeClick() {
        onDecreaseFontSize?()
    }

    @objc
    private func handleIncreaseFontSizeClick() {
        onIncreaseFontSize?()
    }

    private func platformFont(for style: CanvasTextStyle) -> NSFont {
        NSFont(name: style.fontName, size: style.fontSize)
            ?? .systemFont(ofSize: style.fontSize)
    }

    private func fontSizeDescription(for fontSize: CGFloat) -> String {
        let roundedFontSize = fontSize.rounded()
        if abs(fontSize - roundedFontSize) < 0.05 {
            return "\(Int(roundedFontSize)) pt"
        }

        return String(format: "%.1f pt", Double(fontSize))
    }
}
#endif
