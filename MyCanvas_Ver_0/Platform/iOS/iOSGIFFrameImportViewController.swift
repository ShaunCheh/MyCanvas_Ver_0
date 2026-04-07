#if os(iOS)
import UIKit

final class iOSGIFFrameImportViewController: UIViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.text = "Import GIF Frames"
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
    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        return label
    }()

    private var selectedFrameIndices: [Int] = [] {
        didSet {
            updateImportButtonConfiguration()
        }
    }
    private var isImporting = false {
        didSet {
            updateImportButtonConfiguration()
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
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
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
        cancelButton.addTarget(
            self,
            action: #selector(handleCancelButtonTap),
            for: .touchUpInside
        )
        importButton.addTarget(
            self,
            action: #selector(handleImportButtonTap),
            for: .touchUpInside
        )
        updateImportButtonConfiguration()
    }

    private func applyInitialState() {
        detailLabel.text =
            "GIF item: \(itemID.uuidString)\n\n" +
            "The \(configuration.selectionGrid.columns)-column multi-selection frame grid " +
            "and thumbnail loading UI will be added in the next phase."
        updateImportButtonConfiguration()
    }

    private func updateImportButtonConfiguration() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = isImporting ? "Importing..." : "Import"
        importButton.configuration = configuration
        importButton.isEnabled =
            selectedFrameIndices.isEmpty == false &&
            isImporting == false
    }

    @objc
    private func handleCancelButtonTap() {
        dismiss(animated: true)
    }

    @objc
    private func handleImportButtonTap() {
        guard
            isImporting == false,
            selectedFrameIndices.isEmpty == false
        else {
            return
        }

        isImporting = true
        do {
            try onImportSelectedFrames(selectedFrameIndices)
            dismiss(animated: true)
        } catch {
            isImporting = false
            presentError(
                title: "Unable to Import GIF Frames",
                message: error.localizedDescription
            )
        }
    }

    private func presentError(title: String, message: String) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "OK", style: .default)
        )
        present(alertController, animated: true)
    }
}
#endif
