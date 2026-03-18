#if os(iOS)
import UIKit

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 176
        static let sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 24)
        static let itemSpacing: CGFloat = 16
    }

    private let folderPicker = FolderPicker()
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?

    private let catalogLoader = BoardCatalogLoader()
    private let previewProvider = BoardPreviewProvider()
    private var availableBoards: [BoardCatalogItem] = []
    private var selectedBoardID: UUID?
    private var hasSelectedFolder = false
    private var storageErrorMessage: String?
    private var displayMode: BoardListDisplayMode = .grid {
        didSet {
            guard oldValue != displayMode else {
                return
            }

            updateCollectionLayout()
            collectionView.reloadData()
            syncCollectionSelection()
        }
    }

    private var selectedBoard: BoardCatalogItem? {
        if let selectedBoardID {
            return availableBoards.first { $0.boardID == selectedBoardID }
        }

        return availableBoards.first
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Board List"
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Select a storage folder, then open the canvas."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let selectFolderButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Select Folder"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        return button
    }()

    private lazy var displayModeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: BoardListDisplayMode.allCases.map(\.title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = displayMode.segmentIndex
        control.isEnabled = false
        return control
    }()

    private let openCanvasButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Select Folder First"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.isEnabled = false
        return button
    }()

    private let bookmarkTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private let bookmarkDetailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let actionStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalCentering
        stackView.spacing = 12
        return stackView
    }()

    private let contentContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let collectionViewLayout = UICollectionViewFlowLayout()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.register(
            iOSBoardCollectionViewCell.self,
            forCellWithReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier
        )
        return collectionView
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        refreshBookmarkStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionLayout()
    }

    private func setupViewHierarchy() {
        view.backgroundColor = .systemBackground

        actionStackView.addArrangedSubview(selectFolderButton)
        actionStackView.addArrangedSubview(displayModeControl)
        actionStackView.addArrangedSubview(openCanvasButton)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(actionStackView)
        view.addSubview(bookmarkTitleLabel)
        view.addSubview(bookmarkDetailLabel)
        view.addSubview(contentContainerView)

        contentContainerView.addSubview(collectionView)
        contentContainerView.addSubview(emptyStateLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            actionStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            actionStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bookmarkTitleLabel.topAnchor.constraint(equalTo: actionStackView.bottomAnchor, constant: 12),
            bookmarkTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bookmarkTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            bookmarkDetailLabel.topAnchor.constraint(equalTo: bookmarkTitleLabel.bottomAnchor, constant: 4),
            bookmarkDetailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bookmarkDetailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            contentContainerView.topAnchor.constraint(equalTo: bookmarkDetailLabel.bottomAnchor, constant: 16),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -24),
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor)
        ])
    }

    private func setupActions() {
        selectFolderButton.addTarget(self, action: #selector(handleSelectFolderButtonTap), for: .touchUpInside)
        displayModeControl.addTarget(self, action: #selector(handleDisplayModeChange), for: .valueChanged)
        openCanvasButton.addTarget(self, action: #selector(handleOpenCanvasButtonTap), for: .touchUpInside)
    }

    private func applyHeaderState(_ headerState: BoardListHeaderState) {
        bookmarkTitleLabel.text = headerState.title
        bookmarkDetailLabel.text = headerState.detail
        bookmarkTitleLabel.accessibilityHint = headerState.fullPath
        bookmarkDetailLabel.accessibilityHint = headerState.fullPath
        bookmarkDetailLabel.textColor = headerState.isError
            ? .systemRed
            : .secondaryLabel
    }

    private func refreshBookmarkStatus() {
        let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
        do {
            let boards = try catalogLoader.loadCatalog()
            availableBoards = boards
            hasSelectedFolder = true
            storageErrorMessage = nil
            ensureValidSelection()
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus,
                    boardCount: boards.count
                )
            )
            reloadBoardList()
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            selectedBoardID = nil
            hasSelectedFolder = false
            storageErrorMessage = nil
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus
                )
            )
            reloadBoardList()
        } catch {
            availableBoards = []
            selectedBoardID = nil
            hasSelectedFolder = bookmarkStatus.hasSelectedFolder
            storageErrorMessage = error.localizedDescription
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus,
                    storageErrorDescription: error.localizedDescription
                )
            )
            reloadBoardList()
        }
    }

    private func ensureValidSelection() {
        guard !availableBoards.isEmpty else {
            selectedBoardID = nil
            return
        }

        if let selectedBoardID,
           availableBoards.contains(where: { $0.boardID == selectedBoardID }) {
            return
        }

        selectedBoardID = availableBoards.first?.boardID
    }

    private func reloadBoardList() {
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateOpenCanvasButtonState()
        updateCollectionLayout()
        syncCollectionSelection()
    }

    private func updateOpenCanvasButtonState() {
        var configuration = openCanvasButton.configuration ?? UIButton.Configuration.tinted()
        if !hasSelectedFolder {
            configuration.title = "Select Folder First"
            openCanvasButton.isEnabled = false
        } else if storageErrorMessage != nil {
            configuration.title = "Storage Unavailable"
            openCanvasButton.isEnabled = false
        } else {
            configuration.title = availableBoards.isEmpty
                ? "Create Board"
                : "Open Board"
            openCanvasButton.isEnabled = true
        }
        openCanvasButton.configuration = configuration
    }

    private func updateDisplayModeControlState() {
        displayModeControl.isEnabled =
            hasSelectedFolder &&
            storageErrorMessage == nil &&
            !availableBoards.isEmpty
    }

    private func updateCollectionVisibility() {
        let shouldShowCollection =
            hasSelectedFolder &&
            storageErrorMessage == nil &&
            !availableBoards.isEmpty
        collectionView.isHidden = !shouldShowCollection
        emptyStateLabel.isHidden = shouldShowCollection

        if let storageErrorMessage {
            emptyStateLabel.text = "Storage unavailable: \(storageErrorMessage)"
            return
        }

        emptyStateLabel.text = hasSelectedFolder
            ? "No boards yet. Create one to get started."
            : "Select a storage folder to load boards."
    }

    private func updateCollectionLayout() {
        collectionViewLayout.sectionInset = Layout.sectionInset
        collectionViewLayout.minimumLineSpacing = Layout.itemSpacing
        collectionViewLayout.minimumInteritemSpacing = Layout.itemSpacing

        let contentWidth = max(collectionView.bounds.width, 320)
        let availableWidth = max(
            contentWidth - Layout.sectionInset.left - Layout.sectionInset.right,
            Layout.minimumGridItemWidth
        )

        switch displayMode {
        case .list:
            collectionViewLayout.itemSize = CGSize(
                width: availableWidth,
                height: Layout.listItemHeight
            )
        case .grid:
            let estimatedColumns = Int(
                floor((availableWidth + Layout.itemSpacing) / (Layout.minimumGridItemWidth + Layout.itemSpacing))
            )
            let columns = max(estimatedColumns, 1)
            let totalSpacing = Layout.itemSpacing * CGFloat(columns - 1)
            let itemWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
            collectionViewLayout.itemSize = CGSize(
                width: itemWidth,
                height: Layout.gridItemHeight
            )
        }

        collectionViewLayout.invalidateLayout()
    }

    private func syncCollectionSelection() {
        guard
            let selectedBoardID,
            let index = availableBoards.firstIndex(where: { $0.boardID == selectedBoardID })
        else {
            clearCollectionSelection()
            return
        }

        collectionView.selectItem(
            at: IndexPath(item: index, section: 0),
            animated: false,
            scrollPosition: []
        )
    }

    private func clearCollectionSelection() {
        collectionView.indexPathsForSelectedItems?.forEach { indexPath in
            collectionView.deselectItem(at: indexPath, animated: false)
        }
    }

    private func openSelectedBoardIfNeeded() {
        guard hasSelectedFolder else {
            return
        }

        guard let selectedBoard else {
            onCreateBoard?()
            return
        }

        onOpenBoard?(selectedBoard.boardID)
    }

    @objc
    private func handleSelectFolderButtonTap() {
        folderPicker.present(from: self) { [weak self] result in
            switch result {
            case let .success(bookmarkData):
                FolderBookmarkStore.save(bookmarkData)
                print("[FolderBookmark][iOS] Saved bookmark data bytes=\(bookmarkData.count)")
                self?.refreshBookmarkStatus()
            case let .failure(error):
                print("[FolderBookmark][iOS] Failed to create bookmark: \(error)")
                self?.presentSelectionError(error)
            }
        }
    }

    @objc
    private func handleDisplayModeChange() {
        displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegmentIndex)
    }

    @objc
    private func handleOpenCanvasButtonTap() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if availableBoards.isEmpty {
            onCreateBoard?()
        } else {
            openSelectedBoardIfNeeded()
        }
    }

    private func presentSelectionError(_ error: Error) {
        let alertController = UIAlertController(
            title: "Unable to Save Folder Bookmark",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        availableBoards.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let catalogItem = availableBoards[indexPath.item]
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? iOSBoardCollectionViewCell
        else {
            return UICollectionViewCell()
        }

        let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
        let previewContent = previewProvider.immediatePreview(
            for: catalogItem,
            targetPixelSize: targetPixelSize
        )
        cell.configure(
            with: catalogItem,
            previewContent: previewContent,
            displayMode: displayMode
        )
        if previewContent.isThumbnail == false {
            cell.requestThumbnail(
                using: previewProvider,
                for: catalogItem,
                displayMode: displayMode
            )
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedBoardID = availableBoards[indexPath.item].boardID
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? iOSBoardCollectionViewCell)?.cancelThumbnailRequest()
    }
}
#endif
