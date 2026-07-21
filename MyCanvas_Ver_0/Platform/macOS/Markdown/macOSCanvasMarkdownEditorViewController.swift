#if os(macOS)
import AppKit

final class macOSCanvasMarkdownEditorViewController: NSViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let onDidDismiss: (() -> Void)?
    private let onDismissAfterSuccessfulCommit: (() -> Void)?
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Edit Markdown")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        return label
    }()
    private let cancelButton: NSButton = {
        let button = NSButton(title: "Cancel", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\u{1b}"
        return button
    }()
    private let doneButton: NSButton = {
        let button = NSButton(title: "Done", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()
    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        return scrollView
    }()
    private let textView: NSTextView = {
        let textView = NSTextView()
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = CGSize(width: 12, height: 14)
        textView.minSize = .zero
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        return textView
    }()
    private var isCommitting = false {
        didSet {
            updateDoneButtonAppearance()
        }
    }
    private var shouldNotifyDismissAfterSuccessfulCommit = false

    init(
        markdownSource: String,
        onCommitMarkdownSource: @escaping (String) -> Bool,
        onDidDismiss: (() -> Void)? = nil,
        onDismissAfterSuccessfulCommit: (() -> Void)? = nil
    ) {
        self.initialMarkdownSource = markdownSource
        self.onCommitMarkdownSource = onCommitMarkdownSource
        self.onDidDismiss = onDidDismiss
        self.onDismissAfterSuccessfulCommit = onDismissAfterSuccessfulCommit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = macOSAppearanceAwareView()
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 720, height: 540)
        view.wantsLayer = true
        updateAppearance()
        configureButtons()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if view.window?.firstResponder !== textView {
            view.window?.makeFirstResponder(textView)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDidDismiss?()
        guard shouldNotifyDismissAfterSuccessfulCommit else {
            return
        }
        shouldNotifyDismissAfterSuccessfulCommit = false
        onDismissAfterSuccessfulCommit?()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    private func updateAppearance() {
        guard isViewLoaded else {
            return
        }

        let appearance = view.effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
        }
    }

    private func configureButtons() {
        cancelButton.target = self
        cancelButton.action = #selector(handleCancelButtonClick)
        doneButton.target = self
        doneButton.action = #selector(handleDoneButtonClick)
        updateDoneButtonAppearance()
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(cancelButton)
        view.addSubview(doneButton)
        view.addSubview(scrollView)
        scrollView.documentView = textView
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])
    }

    private func applyInitialState() {
        textView.string = initialMarkdownSource
    }

    private func updateDoneButtonAppearance() {
        doneButton.isEnabled = isCommitting == false
        doneButton.title = isCommitting ? "Saving..." : "Done"
    }

    @objc
    private func handleCancelButtonClick() {
        dismiss(self)
    }

    @objc
    private func handleDoneButtonClick() {
        guard isCommitting == false else {
            return
        }

        isCommitting = true
        let didCommit = onCommitMarkdownSource(textView.string)
        isCommitting = false
        guard didCommit else {
            return
        }

        // Delay accessory restoration until the sheet is fully dismissed, so the
        // parent no longer reports an active presented overlay editor.
        shouldNotifyDismissAfterSuccessfulCommit = true
        dismiss(self)
    }
}
#endif
