#if os(iOS)
import ImageIO
import UIKit

final class iOSGIFFrameImportViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let summaryTopSpacing: CGFloat = 16
        static let collectionTopSpacing: CGFloat = 18
        static let minimumItemWidth: CGFloat = 56
        static let itemHeightExtra: CGFloat = 34
    }

    fileprivate enum ThumbnailState {
        case idle
        case loading
        case loaded(UIImage)
        case failed
    }

    private let editorContext: CanvasGIFFrameImportEditorContext
    private let onDidDismiss: (() -> Void)?
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let workerQueue = DispatchQueue(
        label: "MyCanvas.iOS.GIFFrameImportEditor",
        qos: .userInitiated
    )
    private lazy var imageSource: CGImageSource? = CanvasGIFFrameService.makeImageSource(
        from: editorContext.gifData
    )
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
    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        return label
    }()
    private let collectionViewLayout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: collectionViewLayout
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            iOSGIFFrameImportCollectionViewCell.self,
            forCellWithReuseIdentifier: iOSGIFFrameImportCollectionViewCell.reuseIdentifier
        )
        return collectionView
    }()

    private var selectedFrameIndices: Set<Int> = [] {
        didSet {
            updateSelectionSummary()
            updateImportButtonConfiguration()
        }
    }
    private var thumbnailStates: [Int: ThumbnailState] = [:]
    private var thumbnailLoadWorkItems: [Int: DispatchWorkItem] = [:]
    private var isImporting = false {
        didSet {
            collectionView.isUserInteractionEnabled = isImporting == false
            collectionView.alpha = isImporting ? 0.75 : 1
            cancelButton.isEnabled = isImporting == false
            updateImportButtonConfiguration()
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
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelAllThumbnailLoads()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelAllThumbnailLoads()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDismiss?()
    }

    private func setupViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(cancelButton)
        view.addSubview(importButton)
        view.addSubview(summaryLabel)
        view.addSubview(collectionView)
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

            collectionView.topAnchor.constraint(
                equalTo: summaryLabel.bottomAnchor,
                constant: Layout.collectionTopSpacing
            ),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        updateSelectionSummary()
        updateImportButtonConfiguration()
        collectionView.reloadData()
    }

    private func updateSelectionSummary() {
        let selectedCount = selectedFrameIndices.count
        let totalCount = editorContext.frameCount
        if selectedCount == 0 {
            summaryLabel.text =
                "\(totalCount) frames available. Tap one or more frames to import.\n" +
                "Grid columns: \(editorContext.selectionGrid.columns)"
        } else {
            summaryLabel.text =
                "Selected \(selectedCount) of \(totalCount) frames.\n" +
                "Imported frames will inherit size and crop, then be laid out below the GIF."
        }
    }

    private func updateImportButtonConfiguration() {
        let selectedCount = selectedFrameIndices.count
        var configuration = UIButton.Configuration.filled()
        configuration.title =
            selectedCount == 0
            ? "Import"
            : "Import (\(selectedCount))"
        configuration.showsActivityIndicator = isImporting
        importButton.configuration = configuration
        importButton.isEnabled =
            selectedFrameIndices.isEmpty == false &&
            isImporting == false
    }

    private func updateCollectionLayout() {
        let selectionGrid = editorContext.selectionGrid
        let safeAreaInsets = view.safeAreaInsets
        collectionViewLayout.scrollDirection = .vertical
        collectionViewLayout.sectionInset = UIEdgeInsets(
            top: selectionGrid.contentInsets.top,
            left: selectionGrid.contentInsets.leading,
            bottom: selectionGrid.contentInsets.bottom + safeAreaInsets.bottom,
            right: selectionGrid.contentInsets.trailing
        )
        collectionViewLayout.minimumInteritemSpacing =
            selectionGrid.horizontalSpacing
        collectionViewLayout.minimumLineSpacing =
            selectionGrid.verticalSpacing

        let availableWidth = max(
            collectionView.bounds.width
                - collectionViewLayout.sectionInset.left
                - collectionViewLayout.sectionInset.right,
            Layout.minimumItemWidth
        )
        let columns = max(selectionGrid.columns, 1)
        let totalSpacing = selectionGrid.horizontalSpacing * CGFloat(columns - 1)
        let resolvedItemWidth = floor(
            max(
                availableWidth - totalSpacing,
                Layout.minimumItemWidth * CGFloat(columns)
            ) / CGFloat(columns)
        )
        collectionViewLayout.itemSize = CGSize(
            width: resolvedItemWidth,
            height: resolvedItemWidth + Layout.itemHeightExtra
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

            let resolvedImage: UIImage?
            if let imageSource = self.imageSource,
               let cgImage = CanvasGIFFrameService.decodeFrame(
                    at: frameIndex,
                    from: imageSource,
                    maxPixelSize: self.editorContext.thumbnailMaxPixelSize
               ) {
                resolvedImage = UIImage(cgImage: cgImage)
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
        let pendingFrameIndices = Array(thumbnailLoadWorkItems.keys)
        pendingFrameIndices.forEach(cancelThumbnailLoad(for:))
    }

    private func reloadFrameIfVisible(_ frameIndex: Int) {
        let indexPath = IndexPath(item: frameIndex, section: 0)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath) else {
            return
        }

        collectionView.reloadItems(at: [indexPath])
    }

    private func updateSelection(
        isSelected: Bool,
        at indexPath: IndexPath
    ) {
        if isSelected {
            selectedFrameIndices.insert(indexPath.item)
        } else {
            selectedFrameIndices.remove(indexPath.item)
        }

        if let cell = collectionView.cellForItem(
            at: indexPath
        ) as? iOSGIFFrameImportCollectionViewCell {
            cell.isSelected = isSelected
        }
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

        let resolvedFrameIndices = selectedFrameIndices.sorted()
        isImporting = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            do {
                try self.onImportSelectedFrames(resolvedFrameIndices)
                self.dismiss(animated: true)
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

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        editorContext.frameCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: iOSGIFFrameImportCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? iOSGIFFrameImportCollectionViewCell else {
            return UICollectionViewCell()
        }

        let frameIndex = indexPath.item
        let thumbnailState = thumbnailStates[frameIndex] ?? .idle
        cell.apply(
            frameIndex: frameIndex,
            thumbnailState: thumbnailState
        )
        cell.isSelected = selectedFrameIndices.contains(frameIndex)
        if case .idle = thumbnailState {
            scheduleThumbnailLoad(for: frameIndex)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        guard isImporting == false else {
            return false
        }

        if selectedFrameIndices.contains(indexPath.item) {
            collectionView.deselectItem(at: indexPath, animated: true)
            updateSelection(
                isSelected: false,
                at: indexPath
            )
            return false
        }

        return true
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard isImporting == false else {
            return
        }

        updateSelection(
            isSelected: true,
            at: indexPath
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didDeselectItemAt indexPath: IndexPath
    ) {
        updateSelection(
            isSelected: false,
            at: indexPath
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        cancelThumbnailLoad(for: indexPath.item)
    }
}

private final class iOSGIFFrameImportCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSGIFFrameImportCollectionViewCell"

    private let previewContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        return view
    }()
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }()
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    private let activityIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
    }()
    private let frameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    private let selectionBadgeView: UIImageView = {
        let imageView = UIImageView(
            image: UIImage(systemName: "checkmark.circle.fill")
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemBlue
        imageView.isHidden = true
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
        updateSelectionAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSelectionAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(
            comparedTo: traitCollection
        ) != false else {
            return
        }
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        placeholderLabel.text = nil
        placeholderLabel.isHidden = false
        activityIndicatorView.stopAnimating()
        frameLabel.text = nil
        isSelected = false
    }

    func apply(
        frameIndex: Int,
        thumbnailState: iOSGIFFrameImportViewController.ThumbnailState
    ) {
        frameLabel.text = "Frame \(frameIndex + 1)"

        switch thumbnailState {
        case .idle, .loading:
            imageView.image = nil
            placeholderLabel.text = "Loading..."
            placeholderLabel.isHidden = false
            activityIndicatorView.startAnimating()
        case let .loaded(image):
            imageView.image = image
            placeholderLabel.text = nil
            placeholderLabel.isHidden = true
            activityIndicatorView.stopAnimating()
        case .failed:
            imageView.image = nil
            placeholderLabel.text = "Unable to load"
            placeholderLabel.isHidden = false
            activityIndicatorView.stopAnimating()
        }
    }

    private func setupView() {
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 2
        contentView.backgroundColor = .tertiarySystemBackground

        contentView.addSubview(previewContainerView)
        contentView.addSubview(frameLabel)
        contentView.addSubview(selectionBadgeView)
        previewContainerView.addSubview(imageView)
        previewContainerView.addSubview(placeholderLabel)
        previewContainerView.addSubview(activityIndicatorView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            previewContainerView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 8
            ),
            previewContainerView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 8
            ),
            previewContainerView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -8
            ),
            previewContainerView.heightAnchor.constraint(
                equalTo: previewContainerView.widthAnchor
            ),

            imageView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

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

            activityIndicatorView.centerXAnchor.constraint(
                equalTo: previewContainerView.centerXAnchor
            ),
            activityIndicatorView.centerYAnchor.constraint(
                equalTo: previewContainerView.centerYAnchor
            ),

            frameLabel.topAnchor.constraint(
                equalTo: previewContainerView.bottomAnchor,
                constant: 8
            ),
            frameLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 4
            ),
            frameLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -4
            ),
            frameLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -8
            ),

            selectionBadgeView.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 6
            ),
            selectionBadgeView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -6
            ),
            selectionBadgeView.widthAnchor.constraint(equalToConstant: 22),
            selectionBadgeView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func updateSelectionAppearance() {
        let borderColor: UIColor = isSelected
            ? .systemBlue
            : .separator
        contentView.backgroundColor = isSelected
            ? UIColor.systemBlue.withAlphaComponent(0.12)
            : UIColor.tertiarySystemBackground
        selectionBadgeView.isHidden = isSelected == false
        PlatformLayerAppearance.performWithoutAnimations {
            contentView.layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
                borderColor,
                for: traitCollection
            )
        }
    }
}
#endif
