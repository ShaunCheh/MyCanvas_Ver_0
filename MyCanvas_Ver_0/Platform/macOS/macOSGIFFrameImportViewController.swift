#if os(macOS)
import AppKit

final class macOSGIFFrameImportViewController: NSViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Import GIF Frames")
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
    private let importButton: NSButton = {
        let button = NSButton(title: "Import", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()
    private let detailLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 14)
        return label
    }()

    private var selectedFrameIndices: [Int] = [] {
        didSet {
            updateImportButtonAppearance()
        }
    }
    private var isImporting = false {
        didSet {
            updateImportButtonAppearance()
        }
    }

    init(
        itemID: CanvasItemID,
        configuration: CanvasGIFFrameImportConfiguration = .current,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.itemID = itemID
        self.configuration = configuration
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 640, height: 320)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(cancelButton)
        view.addSubview(importButton)
        view.addSubview(detailLabel)
    }

    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: 20
            ),
            titleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            cancelButton.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 24
            ),

            importButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            importButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -24
            ),

            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: cancelButton.trailingAnchor,
                constant: 12
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: importButton.leadingAnchor,
                constant: -12
            ),

            detailLabel.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 32
            ),
            detailLabel.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -32
            ),
            detailLabel.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        ])
    }

    private func configureButtons() {
        cancelButton.target = self
        cancelButton.action = #selector(handleCancelButtonClick)
        importButton.target = self
        importButton.action = #selector(handleImportButtonClick)
        updateImportButtonAppearance()
    }

    private func applyInitialState() {
        detailLabel.stringValue =
            "GIF item: \(itemID.uuidString)\n\n" +
            "The \(configuration.selectionGrid.columns)-column multi-selection frame grid " +
            "and thumbnail loading UI will be added in the next phase."
        updateImportButtonAppearance()
    }

    private func updateImportButtonAppearance() {
        importButton.title = isImporting ? "Importing..." : "Import"
        importButton.isEnabled =
            selectedFrameIndices.isEmpty == false &&
            isImporting == false
    }

    @objc
    private func handleCancelButtonClick() {
        dismiss(self)
    }

    @objc
    private func handleImportButtonClick() {
        guard
            isImporting == false,
            selectedFrameIndices.isEmpty == false
        else {
            return
        }

        isImporting = true
        do {
            try onImportSelectedFrames(selectedFrameIndices)
            dismiss(self)
        } catch {
            isImporting = false
            presentError(
                title: "Unable to Import GIF Frames",
                message: error.localizedDescription
            )
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
#endif
