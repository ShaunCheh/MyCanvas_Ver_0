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
    private var selectedEntryID: BoardListEntryID?
    private var hasSelectedFolder = false
    private var storageErrorMessage: String?
    private var isSyncingSelection = false
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

    private var entries: [BoardListEntry] {
        guard hasSelectedFolder, storageErrorMessage == nil else {
            return []
        }

        return [.newBoardPlaceholder] + availableBoards.map { .board($0) }
    }

    private var hasRealBoards: Bool {
        availableBoards.isEmpty == false
    }

    private var firstRealBoardEntryID: BoardListEntryID? {
        entries.first(where: { $0.isPlaceholder == false })?.id
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
        label.text = BoardListCopy.subtitle
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
            selectedEntryID = nil
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
            selectedEntryID = nil
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
        guard !entries.isEmpty else {
            selectedEntryID = nil
            return
        }

        if let selectedEntryID,
           entries.contains(where: { $0.id == selectedEntryID }) {
            switch selectedEntryID {
            case .newBoard:
                if hasRealBoards == false {
                    return
                }
            case .board:
                return
            }
        }

        selectedEntryID = firstRealBoardEntryID
    }

    private func reloadBoardList() {
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateCollectionLayout()
        syncCollectionSelection()
    }

    private func updateDisplayModeControlState() {
        displayModeControl.isEnabled =
            hasSelectedFolder &&
            storageErrorMessage == nil
    }

    private func updateCollectionVisibility() {
        let shouldShowCollection =
            hasSelectedFolder &&
            storageErrorMessage == nil
        collectionView.isHidden = !shouldShowCollection
        emptyStateLabel.isHidden = shouldShowCollection

        if let storageErrorMessage {
            emptyStateLabel.text = BoardListCopy.storageUnavailableMessage(storageErrorMessage)
            return
        }

        emptyStateLabel.text = BoardListCopy.selectFolderMessage
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
            let selectedEntryID,
            let index = entries.firstIndex(where: { $0.id == selectedEntryID })
        else {
            clearCollectionSelection()
            return
        }

        isSyncingSelection = true
        collectionView.selectItem(
            at: IndexPath(item: index, section: 0),
            animated: false,
            scrollPosition: []
        )
        isSyncingSelection = false
    }

    private func clearCollectionSelection() {
        isSyncingSelection = true
        collectionView.indexPathsForSelectedItems?.forEach { indexPath in
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        isSyncingSelection = false
    }

    private func clearPlaceholderSelectionAfterAction() {
        selectedEntryID = firstRealBoardEntryID
        syncCollectionSelection()
    }

    private func entry(at indexPath: IndexPath) -> BoardListEntry? {
        guard entries.indices.contains(indexPath.item) else {
            return nil
        }

        return entries[indexPath.item]
    }

    private func performPrimaryAction(for entry: BoardListEntry) {
        guard hasSelectedFolder, storageErrorMessage == nil else {
            return
        }

        switch entry {
        case .newBoardPlaceholder:
            onCreateBoard?()
        case let .board(item):
            onOpenBoard?(item.boardID)
        }
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
        entries.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier,
                for: indexPath
            ) as? iOSBoardCollectionViewCell,
            let entry = entry(at: indexPath)
        else {
            return UICollectionViewCell()
        }

        let previewContent: BoardPreviewContent
        if entry.canRequestPreview,
           let catalogItem = entry.catalogItem {
            let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
            previewContent = previewProvider.immediatePreview(
                for: catalogItem,
                targetPixelSize: targetPixelSize
            )
        } else {
            previewContent = .empty
        }

        cell.configure(
            with: entry,
            previewContent: previewContent,
            displayMode: displayMode
        )

        if entry.canRequestPreview,
           let catalogItem = entry.catalogItem,
           previewContent.isThumbnail == false {
            cell.requestThumbnail(
                using: previewProvider,
                for: catalogItem,
                displayMode: displayMode
            )
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard
            isSyncingSelection == false,
            let entry = entry(at: indexPath)
        else {
            return
        }

        selectedEntryID = entry.id
        performPrimaryAction(for: entry)
        if entry.isPlaceholder {
            clearPlaceholderSelectionAfterAction()
        }
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
