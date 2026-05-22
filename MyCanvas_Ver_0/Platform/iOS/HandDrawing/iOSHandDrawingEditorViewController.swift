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
    private let layersButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Layers"
        configuration.image = UIImage(systemName: "square.3.layers.3d")
        configuration.imagePadding = 6
        configuration.cornerStyle = .medium
        button.configuration = configuration
        return button
    }()
    private let paletteView = HandDrawingToolPaletteView()
    private let layerPanelBackdropView: UIControl = {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = .clear
        control.isHidden = true
        return control
    }()
    private let layerPanelView = HandDrawingLayerPanelView()
    private let surfaceView = HandDrawingCanvasSurfaceView()
    private var latestLayerPanelState: HandDrawingLayerPanelState?
    private var isLayerPanelVisible = false {
        didSet {
            guard oldValue != isLayerPanelVisible else {
                return
            }
            updateLayerPanelVisibility()
        }
    }

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
        configureLayerPanelView()
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
        layersButton.addTarget(
            self,
            action: #selector(handleLayersButtonTap),
            for: .touchUpInside
        )
        layerPanelBackdropView.addTarget(
            self,
            action: #selector(handleLayerPanelBackdropTap),
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
        coordinator.onLayerPanelStateChange = { [weak self] state in
            self?.applyLayerPanelState(state)
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
        paletteView.onSelectBrushOpacity = { [weak self] opacity in
            self?.coordinator.selectBrushOpacity(opacity)
        }
        paletteView.onSelectBrushPreset = { [weak self] presetID in
            self?.coordinator.selectBrushPreset(presetID)
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

    private func configureLayerPanelView() {
        layerPanelView.isHidden = true
        layerPanelView.alpha = 0
        layerPanelView.onAddLayer = { [weak self] in
            self?.coordinator.addLayer()
        }
        layerPanelView.onSelectLayer = { [weak self] layerID in
            self?.coordinator.selectLayer(withID: layerID)
        }
        layerPanelView.onRequestRenameLayer = { [weak self] rowState in
            self?.presentRenameLayerPrompt(for: rowState)
        }
        layerPanelView.onMoveLayerUp = { [weak self] layerID in
            self?.coordinator.moveLayerUp(withID: layerID)
        }
        layerPanelView.onMoveLayerDown = { [weak self] layerID in
            self?.coordinator.moveLayerDown(withID: layerID)
        }
        layerPanelView.onToggleVisibility = { [weak self] layerID in
            self?.coordinator.toggleLayerVisibility(withID: layerID)
        }
        layerPanelView.onToggleLock = { [weak self] layerID in
            self?.coordinator.toggleLayerLock(withID: layerID)
        }
        layerPanelView.onDeleteLayer = { [weak self] layerID in
            self?.coordinator.deleteLayer(withID: layerID)
        }
    }

    private func configureSurfaceView() {
        surfaceView.onPencilStrokeBegan = { [weak self] sample in
            self?.coordinator.handlePencilStrokeBegan(sample)
        }
        surfaceView.onPencilStrokeMoved = { [weak self] batch in
            self?.coordinator.handlePencilStrokeMoved(batch)
        }
        surfaceView.onPencilStrokeEnded = { [weak self] batch in
            self?.coordinator.handlePencilStrokeEnded(batch)
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
        view.addSubview(layersButton)
        view.addSubview(paletteView)
        view.addSubview(surfaceView)
        view.addSubview(layerPanelBackdropView)
        view.addSubview(layerPanelView)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = view.safeAreaLayoutGuide
        let preferredLayerPanelWidth = layerPanelView.widthAnchor.constraint(
            equalToConstant: 380
        )
        preferredLayerPanelWidth.priority = .defaultHigh
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
            layersButton.trailingAnchor.constraint(
                equalTo: doneButton.leadingAnchor,
                constant: -12
            ),
            layersButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
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
            ),
            layerPanelBackdropView.topAnchor.constraint(
                equalTo: closeButton.bottomAnchor,
                constant: 8
            ),
            layerPanelBackdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layerPanelBackdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layerPanelBackdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layerPanelView.topAnchor.constraint(
                equalTo: closeButton.bottomAnchor,
                constant: 12
            ),
            layerPanelView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            layerPanelView.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            preferredLayerPanelWidth
        ])
    }

    private func updateChromeConfiguration() {
        closeButton.isEnabled = isFinishing == false
        doneButton.isEnabled = isFinishing == false
        layersButton.isEnabled = isFinishing == false
        var configuration = doneButton.configuration ?? UIButton.Configuration.filled()
        configuration.title = isFinishing ? "Saving..." : "Done"
        doneButton.configuration = configuration
        if isFinishing {
            isLayerPanelVisible = false
        }
    }

    @objc
    private func handleCloseButtonTap() {
        finishEditingAndDismiss()
    }

    @objc
    private func handleDoneButtonTap() {
        finishEditingAndDismiss()
    }

    @objc
    private func handleLayersButtonTap() {
        guard latestLayerPanelState != nil else {
            return
        }
        isLayerPanelVisible.toggle()
    }

    @objc
    private func handleLayerPanelBackdropTap() {
        isLayerPanelVisible = false
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

    private func applyLayerPanelState(_ state: HandDrawingLayerPanelState) {
        latestLayerPanelState = state
        layerPanelView.apply(state: state)
        updateLayerButtonConfiguration()
    }

    private func updateLayerButtonConfiguration() {
        var configuration = layersButton.configuration ?? UIButton.Configuration.tinted()
        configuration.title = latestLayerPanelState?.buttonTitle ?? "Layers"
        configuration.subtitle = latestLayerPanelState?.buttonSubtitle
        configuration.image = UIImage(
            systemName: isLayerPanelVisible
                ? "square.3.layers.3d.down.right.fill"
                : "square.3.layers.3d"
        )
        configuration.imagePadding = 6
        configuration.cornerStyle = .medium
        layersButton.configuration = configuration
    }

    private func updateLayerPanelVisibility() {
        let shouldShowPanel = isLayerPanelVisible && latestLayerPanelState != nil
        layerPanelBackdropView.isHidden = shouldShowPanel == false
        layerPanelView.isHidden = shouldShowPanel == false
        layerPanelBackdropView.alpha = shouldShowPanel ? 1 : 0
        layerPanelView.alpha = shouldShowPanel ? 1 : 0
        updateLayerButtonConfiguration()
    }

    private func presentRenameLayerPrompt(
        for rowState: HandDrawingLayerPanelRowState
    ) {
        let alertController = UIAlertController(
            title: "Rename Layer",
            message: nil,
            preferredStyle: .alert
        )
        alertController.addTextField { textField in
            textField.placeholder = "Layer name"
            textField.text = rowState.name
            textField.clearButtonMode = .whileEditing
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.addAction(
            UIAlertAction(title: "Save", style: .default) { [weak self, weak alertController] _ in
                guard
                    let proposedName = alertController?.textFields?.first?.text
                else {
                    return
                }
                self?.coordinator.renameLayer(
                    withID: rowState.id,
                    to: proposedName
                )
            }
        )
        present(alertController, animated: true)
    }
}
#endif
