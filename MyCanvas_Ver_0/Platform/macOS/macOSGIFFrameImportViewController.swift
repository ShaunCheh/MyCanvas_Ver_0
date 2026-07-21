#if os(macOS)
import AppKit
import ImageIO

final class macOSGIFFrameImportViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let summaryTopSpacing: CGFloat = 16
        static let collectionTopSpacing: CGFloat = 18
        static let minimumItemWidth: CGFloat = 84
        static let itemHeightExtra: CGFloat = 36
    }

    fileprivate enum ThumbnailState {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    private let editorContext: CanvasGIFFrameImportEditorContext
    private let onDidDismiss: (() -> Void)?
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let workerQueue = DispatchQueue(
        label: "MyCanvas.macOS.GIFFrameImportEditor",
        qos: .userInitiated
    )
    private lazy var imageSource: CGImageSource? = CanvasGIFFrameService.makeImageSource(
        from: editorContext.gifData
    )
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
    private let summaryLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 14)
        return label
    }()
    private let collectionViewLayout = NSCollectionViewFlowLayout()
    private lazy var collectionView: NSCollectionView = {
        let collectionView = NSCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.register(
            macOSGIFFrameImportCollectionItem.self,
            forItemWithIdentifier: macOSGIFFrameImportCollectionItem.reuseIdentifier
        )
        return collectionView
    }()
    private lazy var collectionScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        return scrollView
    }()

    private var selectedFrameIndices: Set<Int> = [] {
        didSet {
            updateSelectionSummary()
            updateImportButtonAppearance()
        }
    }
    private var thumbnailStates: [Int: ThumbnailState] = [:]
    private var thumbnailLoadWorkItems: [Int: DispatchWorkItem] = [:]
    private var isImporting = false {
        didSet {
            collectionView.alphaValue = isImporting ? 0.75 : 1
            cancelButton.isEnabled = isImporting == false
            updateImportButtonAppearance()
        }
    }

    init(
        editorContext: CanvasGIFFrameImportEditorContext,
        onDidDismiss: (() -> Void)? = nil,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.editorContext = editorContext
        self.onDidDismiss = onDidDismiss
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelAllThumbnailLoads()
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
        preferredContentSize = CGSize(width: 760, height: 620)
        view.wantsLayer = true
        updateAppearance()
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCollectionLayout()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancelAllThumbnailLoads()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDidDismiss?()
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

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(cancelButton)
        view.addSubview(importButton)
        view.addSubview(summaryLabel)
        view.addSubview(collectionScrollView)
    }

    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: Layout.titleTopInset
            ),
            titleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            cancelButton.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: Layout.horizontalInset
            ),

            importButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            importButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -Layout.horizontalInset
            ),

            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: cancelButton.trailingAnchor,
                constant: 12
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: importButton.leadingAnchor,
                constant: -12
            ),

            summaryLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: Layout.summaryTopSpacing
            ),
            summaryLabel.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            summaryLabel.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -Layout.horizontalInset
            ),

            collectionScrollView.topAnchor.constraint(
                equalTo: summaryLabel.bottomAnchor,
                constant: Layout.collectionTopSpacing
            ),
            collectionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        updateSelectionSummary()
        updateImportButtonAppearance()
        collectionView.reloadData()
    }

    private func updateSelectionSummary() {
        let selectedCount = selectedFrameIndices.count
        let totalCount = editorContext.frameCount
        if selectedCount == 0 {
            summaryLabel.stringValue =
                "\(totalCount) frames available. Click one or more frames to import.\n" +
                "Grid columns: \(editorContext.selectionGrid.columns)"
        } else {
            summaryLabel.stringValue =
                "Selected \(selectedCount) of \(totalCount) frames.\n" +
                "Imported frames will inherit size and crop, then be laid out below the GIF."
        }
    }

    private func updateImportButtonAppearance() {
        let selectedCount = selectedFrameIndices.count
        importButton.title =
            isImporting
            ? "Importing..."
            : (selectedCount == 0 ? "Import" : "Import (\(selectedCount))")
        importButton.isEnabled =
            selectedFrameIndices.isEmpty == false &&
            isImporting == false
    }

    private func updateCollectionLayout() {
        let selectionGrid = editorContext.selectionGrid
        let contentInsets = selectionGrid.contentInsets
        let sectionInset = NSEdgeInsets(
            top: contentInsets.top,
            left: contentInsets.leading,
            bottom: contentInsets.bottom,
            right: contentInsets.trailing
        )
        collectionViewLayout.sectionInset = sectionInset
        collectionViewLayout.minimumLineSpacing = selectionGrid.verticalSpacing
        collectionViewLayout.minimumInteritemSpacing = selectionGrid.horizontalSpacing

        let contentWidth = max(collectionScrollView.contentView.bounds.width, 360)
        let availableWidth = max(
            contentWidth - sectionInset.left - sectionInset.right,
            Layout.minimumItemWidth
        )
        let columns = max(selectionGrid.columns, 1)
        let totalSpacing = selectionGrid.horizontalSpacing * CGFloat(columns - 1)
        let itemWidth = floor(
            max(
                availableWidth - totalSpacing,
                Layout.minimumItemWidth * CGFloat(columns)
            ) / CGFloat(columns)
        )
        let itemHeight = itemWidth + Layout.itemHeightExtra
        collectionViewLayout.itemSize = NSSize(width: itemWidth, height: itemHeight)

        let rowCount: Int
        if editorContext.frameCount == 0 {
            rowCount = 0
        } else {
            rowCount = Int(
                ceil(Double(editorContext.frameCount) / Double(columns))
            )
        }

        let contentHeight: CGFloat
        if rowCount == 0 {
            contentHeight = collectionScrollView.contentView.bounds.height
        } else {
            contentHeight =
                sectionInset.top +
                sectionInset.bottom +
                (CGFloat(rowCount) * itemHeight) +
                (CGFloat(max(rowCount - 1, 0)) * selectionGrid.verticalSpacing)
        }

        collectionView.frame = CGRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: max(contentHeight, collectionScrollView.contentView.bounds.height)
        )
        collectionViewLayout.invalidateLayout()
    }

    private func scheduleThumbnailLoad(
        for frameIndex: Int
    ) {
        if let state = thumbnailStates[frameIndex] {
            switch state {
            case .idle, .failed:
                break
            case .loading, .loaded:
                return
            }
        }

        thumbnailStates[frameIndex] = .loading

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self, workItem?.isCancelled == false else {
                return
            }

            let resolvedImage: NSImage?
            if let imageSource = self.imageSource,
               let cgImage = CanvasGIFFrameService.decodeFrame(
                    at: frameIndex,
                    from: imageSource,
                    maxPixelSize: self.editorContext.thumbnailMaxPixelSize
               ) {
                resolvedImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(
                        width: cgImage.width,
                        height: cgImage.height
                    )
                )
            } else {
                resolvedImage = nil
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.thumbnailLoadWorkItems[frameIndex] = nil
                guard workItem?.isCancelled == false else {
                    self.thumbnailStates[frameIndex] = .idle
                    self.reloadFrameIfVisible(frameIndex)
                    return
                }

                if let resolvedImage {
                    self.thumbnailStates[frameIndex] = .loaded(resolvedImage)
                } else {
                    self.thumbnailStates[frameIndex] = .failed
                }
                self.reloadFrameIfVisible(frameIndex)
            }
        }
        thumbnailLoadWorkItems[frameIndex] = workItem
        workerQueue.async(execute: workItem!)
    }

    private func cancelThumbnailLoad(for frameIndex: Int) {
        guard let workItem = thumbnailLoadWorkItems.removeValue(forKey: frameIndex) else {
            return
        }

        workItem.cancel()
        if case .loading = thumbnailStates[frameIndex] {
            thumbnailStates[frameIndex] = .idle
        }
    }

    private func cancelAllThumbnailLoads() {
        let frameIndices = Array(thumbnailLoadWorkItems.keys)
        frameIndices.forEach(cancelThumbnailLoad(for:))
    }

    private func reloadFrameIfVisible(_ frameIndex: Int) {
        let indexPath = IndexPath(item: frameIndex, section: 0)
        guard collectionView.item(at: indexPath) != nil else {
            return
        }

        collectionView.reloadItems(at: Set([indexPath]))
    }

    private func toggleSelection(for frameIndex: Int) {
        guard isImporting == false else {
            return
        }

        if selectedFrameIndices.contains(frameIndex) {
            selectedFrameIndices.remove(frameIndex)
        } else {
            selectedFrameIndices.insert(frameIndex)
        }

        let indexPath = IndexPath(item: frameIndex, section: 0)
        if let item = collectionView.item(
            at: indexPath
        ) as? macOSGIFFrameImportCollectionItem {
            item.isFrameSelected = selectedFrameIndices.contains(frameIndex)
        } else {
            collectionView.reloadItems(at: Set([indexPath]))
        }
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

        let resolvedFrameIndices = selectedFrameIndices.sorted()
        isImporting = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            do {
                try self.onImportSelectedFrames(resolvedFrameIndices)
                self.dismiss(self)
            } catch {
                self.isImporting = false
                self.presentError(
                    title: "Unable to Import GIF Frames",
                    message: error.localizedDescription
                )
            }
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

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        editorContext.frameCount
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: macOSGIFFrameImportCollectionItem.reuseIdentifier,
            for: indexPath
        )

        guard let collectionItem = item as? macOSGIFFrameImportCollectionItem else {
            return item
        }

        let frameIndex = indexPath.item
        let thumbnailState = thumbnailStates[frameIndex] ?? .idle
        collectionItem.configure(
            frameIndex: frameIndex,
            thumbnailState: thumbnailState,
            isSelected: selectedFrameIndices.contains(frameIndex),
            onToggleSelection: { [weak self] frameIndex in
                self?.toggleSelection(for: frameIndex)
            },
            onPrepareForReuse: { [weak self] frameIndex in
                self?.cancelThumbnailLoad(for: frameIndex)
            }
        )
        if case .idle = thumbnailState {
            scheduleThumbnailLoad(for: frameIndex)
        }
        return collectionItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        cancelThumbnailLoad(for: indexPath.item)
    }
}

private final class macOSGIFFrameImportCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier(
        "macOSGIFFrameImportCollectionItem"
    )

    private let previewContainerView: NSView = {
        let view = macOSGIFFrameImportPreviewContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let imageViewContainer: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()
    private let placeholderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        return label
    }()
    private let progressIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()
    private let frameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 1
        return label
    }()
    private let selectionBadgeView: NSImageView = {
        let image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Selected"
        )
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = .controlAccentColor
        imageView.isHidden = true
        return imageView
    }()
    private var frameIndex: Int?
    private var onToggleSelection: ((Int) -> Void)?
    private var onPrepareForReuse: ((Int) -> Void)?
    var isFrameSelected = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func loadView() {
        let rootView = macOSAppearanceAwareView()
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateSelectionAppearance()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupConstraints()
        updateSelectionAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let frameIndex {
            onPrepareForReuse?(frameIndex)
        }
        self.frameIndex = nil
        onToggleSelection = nil
        onPrepareForReuse = nil
        imageViewContainer.image = nil
        placeholderLabel.stringValue = ""
        placeholderLabel.isHidden = false
        progressIndicator.stopAnimation(nil)
        frameLabel.stringValue = ""
        isFrameSelected = false
    }

    func configure(
        frameIndex: Int,
        thumbnailState: macOSGIFFrameImportViewController.ThumbnailState,
        isSelected: Bool,
        onToggleSelection: @escaping (Int) -> Void,
        onPrepareForReuse: @escaping (Int) -> Void
    ) {
        self.frameIndex = frameIndex
        self.onToggleSelection = onToggleSelection
        self.onPrepareForReuse = onPrepareForReuse
        frameLabel.stringValue = "Frame \(frameIndex + 1)"
        isFrameSelected = isSelected

        switch thumbnailState {
        case .idle, .loading:
            imageViewContainer.image = nil
            placeholderLabel.stringValue = "Loading..."
            placeholderLabel.isHidden = false
            progressIndicator.startAnimation(nil)
        case let .loaded(image):
            imageViewContainer.image = image
            placeholderLabel.stringValue = ""
            placeholderLabel.isHidden = true
            progressIndicator.stopAnimation(nil)
        case .failed:
            imageViewContainer.image = nil
            placeholderLabel.stringValue = "Unable to load"
            placeholderLabel.isHidden = false
            progressIndicator.stopAnimation(nil)
        }
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 2

        let clickGestureRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleClick(_:))
        )
        clickGestureRecognizer.numberOfClicksRequired = 1
        view.addGestureRecognizer(clickGestureRecognizer)

        view.addSubview(previewContainerView)
        view.addSubview(frameLabel)
        view.addSubview(selectionBadgeView)
        previewContainerView.addSubview(imageViewContainer)
        previewContainerView.addSubview(placeholderLabel)
        previewContainerView.addSubview(progressIndicator)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            previewContainerView.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: 8
            ),
            previewContainerView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 8
            ),
            previewContainerView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -8
            ),
            previewContainerView.heightAnchor.constraint(
                equalTo: previewContainerView.widthAnchor
            ),

            imageViewContainer.topAnchor.constraint(
                equalTo: previewContainerView.topAnchor
            ),
            imageViewContainer.leadingAnchor.constraint(
                equalTo: previewContainerView.leadingAnchor
            ),
            imageViewContainer.trailingAnchor.constraint(
                equalTo: previewContainerView.trailingAnchor
            ),
            imageViewContainer.bottomAnchor.constraint(
                equalTo: previewContainerView.bottomAnchor
            ),

            placeholderLabel.centerXAnchor.constraint(
                equalTo: previewContainerView.centerXAnchor
            ),
            placeholderLabel.centerYAnchor.constraint(
                equalTo: previewContainerView.centerYAnchor
            ),
            placeholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: previewContainerView.leadingAnchor,
                constant: 8
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: previewContainerView.trailingAnchor,
                constant: -8
            ),

            progressIndicator.centerXAnchor.constraint(
                equalTo: previewContainerView.centerXAnchor
            ),
            progressIndicator.centerYAnchor.constraint(
                equalTo: previewContainerView.centerYAnchor
            ),

            frameLabel.topAnchor.constraint(
                equalTo: previewContainerView.bottomAnchor,
                constant: 8
            ),
            frameLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 4
            ),
            frameLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -4
            ),
            frameLabel.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -8
            ),

            selectionBadgeView.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: 6
            ),
            selectionBadgeView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -6
            ),
            selectionBadgeView.widthAnchor.constraint(equalToConstant: 22),
            selectionBadgeView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc
    private func handleClick(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended, let frameIndex else {
            return
        }

        onToggleSelection?(frameIndex)
    }

    private func updateSelectionAppearance() {
        let borderColor: NSColor = isFrameSelected
            ? .controlAccentColor
            : .separatorColor
        let backgroundColor: NSColor = isFrameSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : .controlBackgroundColor
        let appearance = view.effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            view.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
                borderColor,
                for: appearance
            )
            view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                backgroundColor,
                for: appearance
            )
            selectionBadgeView.isHidden = isFrameSelected == false
        }
    }
}

private final class macOSGIFFrameImportPreviewContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let appearance = effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .controlBackgroundColor,
                for: appearance
            )
        }
    }
}
#endif
