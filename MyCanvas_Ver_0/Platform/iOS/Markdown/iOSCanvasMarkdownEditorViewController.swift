#if os(iOS)
import UIKit

final class iOSCanvasMarkdownEditorViewController: UIViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let onDidDismiss: (() -> Void)?
    private let onDismissAfterSuccessfulCommit: (() -> Void)?
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.text = "Edit Markdown"
        return label
    }()
    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Cancel"
        button.configuration = configuration
        return button
    }()
    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let textContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        return view
    }()
    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textColor = .label
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(
            top: 16,
            left: 12,
            bottom: 16,
            right: 12
        )
        return textView
    }()
    private var isCommitting = false {
        didSet {
            updateDoneButtonConfiguration()
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
        modalPresentationStyle = .formSheet
        modalTransitionStyle = .coverVertical
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureButtons()
        configureSheetPresentation()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if textView.isFirstResponder == false {
            textView.becomeFirstResponder()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDismiss?()
        guard shouldNotifyDismissAfterSuccessfulCommit else {
            return
        }
        shouldNotifyDismissAfterSuccessfulCommit = false
        onDismissAfterSuccessfulCommit?()
    }

    private func configureButtons() {
        cancelButton.addTarget(
            self,
            action: #selector(handleCancelButtonTap),
            for: .touchUpInside
        )
        doneButton.addTarget(
            self,
            action: #selector(handleDoneButtonTap),
            for: .touchUpInside
        )
        updateDoneButtonConfiguration()
    }

    private func configureSheetPresentation() {
        if let sheetPresentationController {
            sheetPresentationController.detents = [
                .medium(),
                .large()
            ]
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.preferredCornerRadius = 24
        }
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(cancelButton)
        view.addSubview(doneButton)
        view.addSubview(textContainerView)
        textContainerView.addSubview(textView)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = view.safeAreaLayoutGuide
        let keyboardLayoutGuide = view.keyboardLayoutGuide
        keyboardLayoutGuide.followsUndockedKeyboard = true
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 20
            ),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            doneButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -20
            ),
            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: 20
            ),
            titleLabel.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: cancelButton.trailingAnchor,
                constant: 12
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: doneButton.leadingAnchor,
                constant: -12
            ),
            textContainerView.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 20
            ),
            textContainerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 20
            ),
            textContainerView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -20
            ),
            textContainerView.bottomAnchor.constraint(
                equalTo: keyboardLayoutGuide.topAnchor,
                constant: -20
            ),
            textView.topAnchor.constraint(equalTo: textContainerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor)
        ])
    }

    private func applyInitialState() {
        textView.text = initialMarkdownSource
    }

    private func updateDoneButtonConfiguration() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = isCommitting ? "Saving..." : "Done"
        configuration.cornerStyle = .capsule
        doneButton.configuration = configuration
        doneButton.isEnabled = isCommitting == false
    }

    @objc
    private func handleCancelButtonTap() {
        dismiss(animated: true)
    }

    @objc
    private func handleDoneButtonTap() {
        guard isCommitting == false else {
            return
        }

        isCommitting = true
        let didCommit = onCommitMarkdownSource(textView.text)
        isCommitting = false
        guard didCommit else {
            return
        }

        // Restore markdown accessory only after the editor is fully dismissed,
        // so the parent no longer treats the overlay editor as presented.
        shouldNotifyDismissAfterSuccessfulCommit = true
        dismiss(animated: true)
    }
}
#endif
