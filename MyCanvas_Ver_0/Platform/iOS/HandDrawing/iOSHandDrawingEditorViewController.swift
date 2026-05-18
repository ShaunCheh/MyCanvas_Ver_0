#if os(iOS)
import PencilKit
import UIKit

private enum iOSHandDrawingEditorFlowError: LocalizedError {
    case invalidDrawingData(itemID: CanvasItemID)
    case failedToRenderPreview(itemID: CanvasItemID)

    var errorDescription: String? {
        switch self {
        case let .invalidDrawingData(itemID):
            return "Unable to open the hand drawing source for item \(itemID.uuidString)."
        case let .failedToRenderPreview(itemID):
            return "Unable to render a preview image for item \(itemID.uuidString)."
        }
    }
}

final class iOSHandDrawingEditorViewController: UIViewController, PKCanvasViewDelegate {
    private enum Layout {
        static let topInset: CGFloat = 18
        static let horizontalInset: CGFloat = 20
        static let chromeSpacing: CGFloat = 12
        static let paperCornerRadius: CGFloat = 24
    }

    private let editorContext: CanvasHandDrawingEditorContext
    private let onCommitSubmission: (CanvasHandDrawingEditSubmission) throws -> Void
    private let initialDrawing: PKDrawing
    private let toolPicker = PKToolPicker()
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
        label.text = "Draw with Apple Pencil. Use fingers to pan and zoom."
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
    private let canvasView: PKCanvasView = {
        let view = PKCanvasView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.paperCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = true
        view.bouncesZoom = true
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()

    private var hasConfiguredInitialZoomScale = false
    private var isFinishing = false {
        didSet {
            updateChromeConfiguration()
        }
    }

    init(
        editorContext: CanvasHandDrawingEditorContext,
        onCommitSubmission: @escaping (CanvasHandDrawingEditSubmission) throws -> Void
    ) throws {
        self.editorContext = editorContext
        self.onCommitSubmission = onCommitSubmission
        initialDrawing = try Self.makeInitialDrawing(from: editorContext)
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
        configureCanvasView()
        setupViewHierarchy()
        setupConstraints()
        updateChromeConfiguration()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.removeObserver(canvasView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCanvasZoomMetricsIfNeeded()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateCanvasContentInset()
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

    private func configureCanvasView() {
        canvasView.delegate = self
        canvasView.drawing = initialDrawing
        canvasView.drawingPolicy = .pencilOnly
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 6)
        canvasView.contentSize = editorContext.paper.size
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(hintLabel)
        view.addSubview(closeButton)
        view.addSubview(doneButton)
        view.addSubview(canvasView)
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
            canvasView.topAnchor.constraint(
                equalTo: hintLabel.bottomAnchor,
                constant: 20
            ),
            canvasView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            canvasView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            canvasView.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.horizontalInset
            )
        ])
    }

    private func updateCanvasZoomMetricsIfNeeded() {
        guard canvasView.bounds.isEmpty == false else {
            return
        }

        let paperSize = editorContext.paper.size
        let widthScale = canvasView.bounds.width / max(paperSize.width, 1)
        let heightScale = canvasView.bounds.height / max(paperSize.height, 1)
        let fitScale = max(min(widthScale, heightScale), 0.1)
        canvasView.minimumZoomScale = max(fitScale * 0.5, 0.1)
        canvasView.maximumZoomScale = max(fitScale * 4, fitScale)
        if hasConfiguredInitialZoomScale == false {
            canvasView.zoomScale = fitScale
            hasConfiguredInitialZoomScale = true
        } else {
            canvasView.zoomScale = min(
                max(canvasView.zoomScale, canvasView.minimumZoomScale),
                canvasView.maximumZoomScale
            )
        }
        updateCanvasContentInset()
    }

    private func updateCanvasContentInset() {
        let paperSize = editorContext.paper.size
        let scaledWidth = paperSize.width * canvasView.zoomScale
        let scaledHeight = paperSize.height * canvasView.zoomScale
        let horizontalInset = max((canvasView.bounds.width - scaledWidth) / 2, 0)
        let verticalInset = max((canvasView.bounds.height - scaledHeight) / 2, 0)
        canvasView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
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
            let drawing = canvasView.drawing
            let isEmpty = drawing.strokes.isEmpty
            if shouldCommit(drawing: drawing, isEmpty: isEmpty) {
                let drawingData = drawing.dataRepresentation()
                let previewCGImage = try makePreviewCGImage(
                    for: drawing,
                    isEmpty: isEmpty
                )
                try onCommitSubmission(
                    CanvasHandDrawingEditSubmission(
                        drawingData: drawingData,
                        previewCGImage: previewCGImage,
                        isEmpty: isEmpty,
                        contentRevision: UUID()
                    )
                )
            }
            dismiss(animated: true)
        } catch {
            isFinishing = false
            presentCommitError(message: error.localizedDescription)
        }
    }

    private func shouldCommit(
        drawing: PKDrawing,
        isEmpty: Bool
    ) -> Bool {
        let currentDrawingData = drawing.dataRepresentation()
        if editorContext.drawingData == currentDrawingData,
           editorContext.isEmpty == isEmpty
        {
            return false
        }

        return !(editorContext.drawingData.isEmpty
            && editorContext.isEmpty
            && isEmpty
            && drawing.strokes.isEmpty)
    }

    private func makePreviewCGImage(
        for drawing: PKDrawing,
        isEmpty: Bool
    ) throws -> CGImage {
        if isEmpty {
            return try CanvasHandDrawingPreviewAssetFactory.makeTransparentPreview(
                for: editorContext.paper
            )
        }

        let paperBounds = CGRect(origin: .zero, size: editorContext.paper.size)
        let previewImage = drawing.image(from: paperBounds, scale: 1)
        if let cgImage = previewImage.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: editorContext.paper.size,
            format: format
        )
        let rasterizedImage = renderer.image { _ in
            previewImage.draw(at: .zero)
        }
        guard let cgImage = rasterizedImage.cgImage else {
            throw iOSHandDrawingEditorFlowError.failedToRenderPreview(
                itemID: editorContext.itemID
            )
        }
        return cgImage
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

    private static func makeInitialDrawing(
        from editorContext: CanvasHandDrawingEditorContext
    ) throws -> PKDrawing {
        guard editorContext.drawingData.isEmpty == false else {
            return PKDrawing()
        }

        do {
            return try PKDrawing(data: editorContext.drawingData)
        } catch {
            throw iOSHandDrawingEditorFlowError.invalidDrawingData(
                itemID: editorContext.itemID
            )
        }
    }
}
#endif
