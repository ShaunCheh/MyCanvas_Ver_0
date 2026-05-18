#if os(iOS)
import UIKit

private enum iOSHandDrawingEditorFlowError: LocalizedError {
    case invalidDocumentData(itemID: CanvasItemID)

    var errorDescription: String? {
        switch self {
        case let .invalidDocumentData(itemID):
            return "Unable to open the hand drawing document for item \(itemID.uuidString)."
        }
    }
}

final class iOSHandDrawingEditorViewController: UIViewController {
    private enum Layout {
        static let topInset: CGFloat = 18
        static let horizontalInset: CGFloat = 20
        static let chromeSpacing: CGFloat = 12
    }

    private let onCommitSubmission: (CanvasHandDrawingEditSubmission) throws -> Void
    private let coordinator: HandDrawingEditorCoordinator
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.text = "Hand Drawing"
        return label
    }()
    private let hintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = "Draw or lasso with Apple Pencil. Use fingers to pan and zoom."
        return label
    }()
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Close"
        button.configuration = configuration
        return button
    }()
    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let paletteView = HandDrawingToolPaletteView()
    private let surfaceView = HandDrawingCanvasSurfaceView()

    private var isFinishing = false {
        didSet {
            updateChromeConfiguration()
        }
    }

    init(
        editorContext: CanvasHandDrawingEditorContext,
        onCommitSubmission: @escaping (CanvasHandDrawingEditSubmission) throws -> Void
    ) throws {
        self.onCommitSubmission = onCommitSubmission
        do {
            coordinator = try HandDrawingEditorCoordinator(editorContext: editorContext)
        } catch {
            throw iOSHandDrawingEditorFlowError.invalidDocumentData(
                itemID: editorContext.itemID
            )
        }
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
        view.backgroundColor = .systemGroupedBackground
        configureButtons()
        configureCoordinator()
        configurePaletteView()
        configureSurfaceView()
        setupViewHierarchy()
        setupConstraints()
        updateChromeConfiguration()
        coordinator.activate()
    }

    private func configureButtons() {
        closeButton.addTarget(
            self,
            action: #selector(handleCloseButtonTap),
            for: .touchUpInside
        )
        doneButton.addTarget(
            self,
            action: #selector(handleDoneButtonTap),
            for: .touchUpInside
        )
    }

    private func configureCoordinator() {
        coordinator.onSurfaceStateChange = { [weak self] state in
            self?.surfaceView.apply(state: state)
        }
        coordinator.onPaletteStateChange = { [weak self] state in
            self?.paletteView.apply(state: state)
        }
        coordinator.onErrorMessage = { [weak self] message in
            self?.presentCommitError(message: message)
        }
    }

    private func configurePaletteView() {
        paletteView.onSelectTool = { [weak self] tool in
            self?.coordinator.selectTool(tool)
        }
        paletteView.onSelectColor = { [weak self] color in
            self?.coordinator.selectColor(color)
        }
        paletteView.onSelectLineWidth = { [weak self] lineWidth in
            self?.coordinator.selectLineWidth(lineWidth)
        }
        paletteView.onUndo = { [weak self] in
            self?.coordinator.undo()
        }
        paletteView.onRedo = { [weak self] in
            self?.coordinator.redo()
        }
        paletteView.onDeselectSelection = { [weak self] in
            self?.coordinator.deselectSelection()
        }
    }

    private func configureSurfaceView() {
        surfaceView.onPencilStrokeBegan = { [weak self] sample in
            self?.coordinator.handlePencilStrokeBegan(sample)
        }
        surfaceView.onPencilStrokeMoved = { [weak self] samples in
            self?.coordinator.handlePencilStrokeMoved(samples)
        }
        surfaceView.onPencilStrokeEnded = { [weak self] samples in
            self?.coordinator.handlePencilStrokeEnded(samples)
        }
        surfaceView.onPencilStrokeCancelled = { [weak self] in
            self?.coordinator.handlePencilStrokeCancelled()
        }
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(hintLabel)
        view.addSubview(closeButton)
        view.addSubview(doneButton)
        view.addSubview(paletteView)
        view.addSubview(surfaceView)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            closeButton.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.topInset
            ),
            doneButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            doneButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            titleLabel.topAnchor.constraint(
                equalTo: closeButton.bottomAnchor,
                constant: Layout.chromeSpacing
            ),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            hintLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 8
            ),
            paletteView.topAnchor.constraint(
                equalTo: hintLabel.bottomAnchor,
                constant: 16
            ),
            paletteView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            paletteView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            surfaceView.topAnchor.constraint(
                equalTo: paletteView.bottomAnchor,
                constant: 16
            ),
            surfaceView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            surfaceView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            surfaceView.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.horizontalInset
            )
        ])
    }

    private func updateChromeConfiguration() {
        closeButton.isEnabled = isFinishing == false
        doneButton.isEnabled = isFinishing == false
        var configuration = doneButton.configuration ?? UIButton.Configuration.filled()
        configuration.title = isFinishing ? "Saving..." : "Done"
        doneButton.configuration = configuration
    }

    @objc
    private func handleCloseButtonTap() {
        finishEditingAndDismiss()
    }

    @objc
    private func handleDoneButtonTap() {
        finishEditingAndDismiss()
    }

    private func finishEditingAndDismiss() {
        guard isFinishing == false else {
            return
        }

        isFinishing = true
        do {
            if let submission = try coordinator.makeCommitSubmissionIfNeeded() {
                try onCommitSubmission(submission)
            }
            dismiss(animated: true)
        } catch {
            isFinishing = false
            presentCommitError(message: error.localizedDescription)
        }
    }

    private func presentCommitError(message: String) {
        let alertController = UIAlertController(
            title: "Unable to Save Hand Drawing",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
#endif
