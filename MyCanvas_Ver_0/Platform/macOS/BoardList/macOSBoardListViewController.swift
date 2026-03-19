#if os(macOS)
import AppKit

final class macOSBoardListViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 220
        static let sectionHorizontalInset: CGFloat = 24
        static let sectionBottomInset: CGFloat = 24
        static let sectionTopInset: CGFloat = 0
        static let itemSpacing: CGFloat = 16
    }

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

    private var sectionInset: NSEdgeInsets {
        NSEdgeInsets(
            top: Layout.sectionTopInset,
            left: Layout.sectionHorizontalInset,
            bottom: Layout.sectionBottomInset,
            right: Layout.sectionHorizontalInset
        )
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

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Board List")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }()

    private let subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: BoardListCopy.subtitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    private let selectFolderButton: NSButton = {
        let button = NSButton(title: "Select Folder", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        return button
    }()

    private lazy var displayModeControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: BoardListDisplayMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegment = displayMode.segmentIndex
        control.isEnabled = false
        return control
    }()

    private let actionStackView: NSStackView = {
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 12
        return stackView
    }()

    private let contentContainerView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let bookmarkTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        return label
    }()

    private let bookmarkDetailLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }()

    private let collectionViewLayout = NSCollectionViewFlowLayout()

    private lazy var collectionView: NSCollectionView = {
        let collectionView = NSCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.autoresizingMask = [.width]
        collectionView.register(
            macOSBoardCollectionItem.self,
            forItemWithIdentifier: macOSBoardCollectionItem.reuseIdentifier
        )

        let doubleClickGestureRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleCollectionViewDoubleClick(_:))
        )
        doubleClickGestureRecognizer.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClickGestureRecognizer)
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

    private let emptyStateLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.isHidden = true
        return label
    }()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        refreshBookmarkStatus()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCollectionLayout()
    }

    func prepareForDisplay() {
        guard isViewLoaded else {
            return
        }

        refreshBookmarkStatus()
    }

    private func setupViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        actionStackView.addArrangedSubview(selectFolderButton)
        actionStackView.addArrangedSubview(displayModeControl)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(actionStackView)
        view.addSubview(bookmarkTitleLabel)
        view.addSubview(bookmarkDetailLabel)
        view.addSubview(contentContainerView)

        contentContainerView.addSubview(collectionScrollView)
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
            collectionScrollView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            collectionScrollView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            collectionScrollView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            collectionScrollView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -24),
            emptyStateLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor)
        ])
    }

    private func setupActions() {
        selectFolderButton.target = self
        selectFolderButton.action = #selector(handleSelectFolderButtonClick)
        displayModeControl.target = self
        displayModeControl.action = #selector(handleDisplayModeChange)
    }

    private func applyHeaderState(_ headerState: BoardListHeaderState) {
        bookmarkTitleLabel.stringValue = headerState.title
        bookmarkDetailLabel.stringValue = headerState.detail
        bookmarkTitleLabel.toolTip = headerState.fullPath
        bookmarkDetailLabel.toolTip = headerState.fullPath
        bookmarkDetailLabel.textColor = headerState.isError
            ? .systemRed
            : .secondaryLabelColor
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
        collectionScrollView.isHidden = !shouldShowCollection
        emptyStateLabel.isHidden = shouldShowCollection

        if let storageErrorMessage {
            emptyStateLabel.stringValue = BoardListCopy.storageUnavailableMessage(storageErrorMessage)
            return
        }

        emptyStateLabel.stringValue = BoardListCopy.selectFolderMessage
    }

    private func updateCollectionLayout() {
        collectionViewLayout.sectionInset = sectionInset
        collectionViewLayout.minimumLineSpacing = Layout.itemSpacing
        collectionViewLayout.minimumInteritemSpacing = Layout.itemSpacing

        let contentWidth = max(collectionScrollView.contentView.bounds.width, 320)
        let availableWidth = max(
            contentWidth - sectionInset.left - sectionInset.right,
            Layout.minimumGridItemWidth
        )

        let columns: Int
        let itemHeight: CGFloat
        switch displayMode {
        case .list:
            columns = 1
            itemHeight = Layout.listItemHeight
            collectionViewLayout.itemSize = NSSize(width: availableWidth, height: itemHeight)
        case .grid:
            let estimatedColumns = Int(
                floor((availableWidth + Layout.itemSpacing) / (Layout.minimumGridItemWidth + Layout.itemSpacing))
            )
            columns = max(estimatedColumns, 1)
            let totalSpacing = Layout.itemSpacing * CGFloat(columns - 1)
            let itemWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
            itemHeight = Layout.gridItemHeight
            collectionViewLayout.itemSize = NSSize(width: itemWidth, height: itemHeight)
        }

        let rowCount: Int
        if entries.isEmpty {
            rowCount = 0
        } else {
            rowCount = Int(ceil(Double(entries.count) / Double(columns)))
        }

        let contentHeight: CGFloat
        if rowCount == 0 {
            contentHeight = collectionScrollView.contentView.bounds.height
        } else {
            contentHeight =
                sectionInset.top +
                sectionInset.bottom +
                (CGFloat(rowCount) * itemHeight) +
                (CGFloat(max(rowCount - 1, 0)) * Layout.itemSpacing)
        }

        collectionView.frame = CGRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: max(contentHeight, collectionScrollView.contentView.bounds.height)
        )
        collectionViewLayout.invalidateLayout()
    }

    private func syncCollectionSelection() {
        guard
            let selectedEntryID,
            let index = entries.firstIndex(where: { $0.id == selectedEntryID })
        else {
            isSyncingSelection = true
            collectionView.deselectAll(nil)
            isSyncingSelection = false
            return
        }

        isSyncingSelection = true
        collectionView.selectItems(
            at: Set([IndexPath(item: index, section: 0)]),
            scrollPosition: []
        )
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
    private func handleSelectFolderButtonClick() {
        do {
            guard let bookmarkData = try FilePickerManager.selectFolder() else {
                return
            }

            FolderBookmarkStore.save(bookmarkData)
            print("[FolderBookmark][macOS] Saved bookmark data bytes=\(bookmarkData.count)")
            refreshBookmarkStatus()
        } catch {
            print("[FolderBookmark][macOS] Failed to create bookmark: \(error)")
            presentSelectionError(error)
        }
    }

    @objc
    private func handleDisplayModeChange() {
        displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegment)
    }

    @objc
    private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        guard
            gestureRecognizer.state == .ended
        else {
            return
        }

        let location = gestureRecognizer.location(in: collectionView)
        guard
            let indexPath = collectionView.indexPathForItem(at: location),
            let entry = entry(at: indexPath),
            entry.isPlaceholder == false
        else {
            return
        }

        selectedEntryID = entry.id
        isSyncingSelection = true
        collectionView.selectItems(
            at: Set([indexPath]),
            scrollPosition: []
        )
        isSyncingSelection = false
        performPrimaryAction(for: entry)
    }

    private func presentSelectionError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Save Folder Bookmark"
        alert.informativeText = error.localizedDescription
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
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard
            let item = collectionView.makeItem(
                withIdentifier: macOSBoardCollectionItem.reuseIdentifier,
                for: indexPath
            ) as? macOSBoardCollectionItem,
            let entry = entry(at: indexPath)
        else {
            return NSCollectionViewItem()
        }

        let previewContent: BoardPreviewContent
        if entry.canRequestPreview,
           let catalogItem = entry.catalogItem {
            let targetPixelSize = item.targetThumbnailPixelSize(for: displayMode)
            previewContent = previewProvider.immediatePreview(
                for: catalogItem,
                targetPixelSize: targetPixelSize
            )
        } else {
            previewContent = .empty
        }

        item.configure(
            with: entry,
            previewContent: previewContent,
            displayMode: displayMode
        )

        if entry.canRequestPreview,
           let catalogItem = entry.catalogItem,
           previewContent.isThumbnail == false {
            item.requestThumbnail(
                using: previewProvider,
                for: catalogItem,
                displayMode: displayMode
            )
        }
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard
            isSyncingSelection == false,
            let indexPath = indexPaths.first,
            let entry = entry(at: indexPath)
        else {
            return
        }

        selectedEntryID = entry.id
        if entry.isPlaceholder {
            performPrimaryAction(for: entry)
            clearPlaceholderSelectionAfterAction()
        }
    }
}
#endif
