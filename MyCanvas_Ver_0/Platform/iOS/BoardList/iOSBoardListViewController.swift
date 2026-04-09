#if os(iOS)
import UIKit

private func iOSBoardListRenameTraceTimestamp() -> String {
    String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 176
        static let sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 24)
        static let itemSpacing: CGFloat = 16
    }

    private let folderPicker = FolderPicker()
    var onOpenCanvas: ((BoardListCanvasOpenRequest) -> Void)?

    private let catalogLoader = BoardCatalogLoader()
    private let previewProvider = BoardPreviewProvider()
    private var availableBoards: [BoardCatalogItem] = []
    private var selectedEntryID: BoardListEntryID?
    private var actionPanelState: BoardListActionPanelState? {
        didSet {
            logRenameTrace(
                "actionPanelStateChanged",
                extra:
                    "oldBoardID=\(oldValue?.boardID.uuidString ?? "nil") " +
                    "newBoardID=\(actionPanelState?.boardID.uuidString ?? "nil")"
            )
            updateActionPanelPresentation()
        }
    }
    private var hasSelectedFolder = false
    private var storageErrorMessage: String?
    private var isSyncingSelection = false
    private var editingBoardID: UUID? {
        didSet {
            logRenameTrace(
                "editingBoardIDChanged",
                extra:
                    "oldValue=\(oldValue?.uuidString ?? "nil") " +
                    "newValue=\(editingBoardID?.uuidString ?? "nil")"
            )
        }
    }
    private var pendingRevealBoardID: UUID? {
        didSet {
            logRenameTrace(
                "pendingRevealBoardIDChanged",
                extra:
                    "oldValue=\(oldValue?.uuidString ?? "nil") " +
                    "newValue=\(pendingRevealBoardID?.uuidString ?? "nil")"
            )
        }
    }
    private var displayMode: BoardListDisplayMode = .grid {
        didSet {
            guard oldValue != displayMode else {
                return
            }

            reloadBoardList()
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
    private let actionPanelHostView = BoardListActionPanelHostView()

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
        setupActionPanelHostView()
        refreshBookmarkStatus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionLayout()
        updateActionPanelLayout()
    }

    func prepareForDisplay() {
        guard isViewLoaded else {
            return
        }

        refreshBookmarkStatus()
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
        view.addSubview(actionPanelHostView)

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
            actionPanelHostView.topAnchor.constraint(equalTo: view.topAnchor),
            actionPanelHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionPanelHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionPanelHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    private func setupActionPanelHostView() {
        actionPanelHostView.onDismissRequested = { [weak self] in
            self?.dismissActionPanel()
        }
        actionPanelHostView.onActionSelected = { [weak self] actionID in
            self?.performBoardAction(actionID)
        }
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

    private func logRenameTrace(_ phase: String, extra: String = "") {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardList][iOS][RenameTrace] " +
                "t=\(iOSBoardListRenameTraceTimestamp()) " +
                "phase=\(phase) " +
                "editingBoardID=\(editingBoardID?.uuidString ?? "nil") " +
                "pendingRevealBoardID=\(pendingRevealBoardID?.uuidString ?? "nil") " +
                "selectedEntryID=\(describeRenameTraceEntryID(selectedEntryID)) " +
                "actionPanelBoardID=\(actionPanelState?.boardID.uuidString ?? "nil")" +
                extraSuffix
        )
    }

    private func describeRenameTraceEntryID(_ entryID: BoardListEntryID?) -> String {
        guard let entryID else {
            return "nil"
        }

        switch entryID {
        case .newBoard:
            return "newBoard"
        case let .board(boardID):
            return "board(\(boardID.uuidString))"
        }
    }

    private func refreshBookmarkStatus() {
        logRenameTrace("refreshBookmarkStatusBegin")
        dismissActionPanel()
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
        logRenameTrace("refreshBookmarkStatusEnd", extra: "boardCount=\(availableBoards.count)")
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
        logRenameTrace("reloadBoardListBegin", extra: "entryCount=\(entries.count)")
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateCollectionLayout()
        syncCollectionSelection()
        revealPendingBoardIfNeeded()
        focusTitleEditorIfNeeded()
        logRenameTrace("reloadBoardListEnd", extra: "entryCount=\(entries.count)")
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

    private func indexPath(for boardID: UUID) -> IndexPath? {
        guard let index = entries.firstIndex(where: { $0.boardID == boardID }) else {
            return nil
        }

        return IndexPath(item: index, section: 0)
    }

    private func boardTitle(for boardID: UUID) -> String? {
        availableBoards.first(where: { $0.boardID == boardID })?.title
    }

    private func normalizedBoardTitle(_ title: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.isEmpty == false else {
            return BoardDocument.defaultTitle
        }

        return normalizedTitle
    }

    private func performPrimaryAction(for entry: BoardListEntry) {
        dismissActionPanel()
        guard
            hasSelectedFolder,
            storageErrorMessage == nil,
            editingBoardID == nil
        else {
            logRenameTrace(
                "performPrimaryActionBlocked",
                extra:
                    "entryID=\(describeRenameTraceEntryID(entry.id)) " +
                    "hasSelectedFolder=\(hasSelectedFolder) " +
                    "hasStorageError=\(storageErrorMessage != nil)"
            )
            return
        }

        onOpenCanvas?(makeOpenRequest(for: entry))
    }

    private func makeOpenRequest(
        for entry: BoardListEntry
    ) -> BoardListCanvasOpenRequest {
        switch entry {
        case .newBoardPlaceholder:
            return .newBoardPlaceholder()
        case let .board(item):
            return .existingBoard(boardID: item.boardID)
        }
    }

    @objc
    private func handleSelectFolderButtonTap() {
        dismissActionPanel()
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
        dismissActionPanel()
        displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegmentIndex)
    }

    private func presentRenameActionPanel(
        for boardID: UUID,
        anchorRect: CGRect,
        from sourceView: UIView
    ) {
        logRenameTrace(
            "presentRenameActionPanel",
            extra:
                "boardID=\(boardID.uuidString) " +
                "anchorMaxX=\(String(format: "%.1f", anchorRect.maxX)) " +
                "anchorMaxY=\(String(format: "%.1f", anchorRect.maxY))"
        )
        let anchorPoint = actionPanelHostView.convert(
            CGPoint(
                x: anchorRect.maxX,
                y: anchorRect.maxY
            ),
            from: sourceView
        )
        selectedEntryID = .board(boardID)
        syncCollectionSelection()
        actionPanelState = .renameMenu(
            boardID: boardID,
            anchorPoint: anchorPoint
        )
    }

    private func dismissActionPanel() {
        logRenameTrace("dismissActionPanel")
        actionPanelState = nil
    }

    private func updateActionPanelPresentation() {
        guard isViewLoaded else {
            return
        }

        actionPanelHostView.apply(
            state: actionPanelState,
            layoutContext: makeActionPanelLayoutContext()
        )
    }

    private func updateActionPanelLayout() {
        guard actionPanelState != nil else {
            return
        }

        actionPanelHostView.updateLayout(
            layoutContext: makeActionPanelLayoutContext()
        )
    }

    private func makeActionPanelLayoutContext() -> BoardListActionPanelLayoutContext {
        BoardListActionPanelLayoutContext(
            safeBounds: view.safeAreaLayoutGuide.layoutFrame,
            occupiedRects: actionPanelOccupiedRects()
        )
    }

    private func actionPanelOccupiedRects() -> [CGRect] {
        var occupiedRects: [CGRect] = [
            titleLabel.frame,
            subtitleLabel.frame,
            actionStackView.frame,
            bookmarkTitleLabel.frame,
            bookmarkDetailLabel.frame
        ].filter { $0.isEmpty == false }

        if emptyStateLabel.isHidden == false {
            occupiedRects.append(
                view.convert(
                    emptyStateLabel.frame,
                    from: contentContainerView
                ).standardized
            )
        }

        return occupiedRects
    }

    private func performBoardAction(_ actionID: BoardListActionID) {
        let boardID = actionPanelState?.boardID
        logRenameTrace(
            "performBoardAction",
            extra:
                "actionID=\(actionID.rawValue) " +
                "boardID=\(boardID?.uuidString ?? "nil")"
        )
        dismissActionPanel()

        switch actionID {
        case .rename:
            guard let boardID else {
                return
            }

            selectedEntryID = .board(boardID)
            pendingRevealBoardID = nil
            editingBoardID = boardID
            reloadBoardList()
        }
    }

    private func commitRename(boardID: UUID, title: String) {
        guard editingBoardID == boardID else {
            logRenameTrace(
                "commitRenameIgnored",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "rawTitle=\"\(title)\""
            )
            return
        }

        let normalizedTitle = normalizedBoardTitle(title)
        logRenameTrace(
            "commitRenameBegin",
            extra:
                "boardID=\(boardID.uuidString) " +
                "rawTitle=\"\(title)\" " +
                "normalizedTitle=\"\(normalizedTitle)\" " +
                "existingTitle=\"\(boardTitle(for: boardID) ?? "")\""
        )
        if boardTitle(for: boardID) == normalizedTitle {
            logRenameTrace("commitRenameNoop", extra: "boardID=\(boardID.uuidString)")
            editingBoardID = nil
            pendingRevealBoardID = nil
            reloadBoardList()
            return
        }

        do {
            try BoardStore.renameBoard(id: boardID, title: normalizedTitle)
            editingBoardID = nil
            selectedEntryID = .board(boardID)
            pendingRevealBoardID = boardID
            refreshBookmarkStatus()
        } catch {
            logRenameTrace(
                "commitRenameFailed",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "error=\"\(error.localizedDescription)\""
            )
            presentRenameError(error)
        }
    }

    private func focusTitleEditorIfNeeded() {
        guard let editingBoardID else {
            return
        }

        logRenameTrace("focusTitleEditorIfNeeded", extra: "boardID=\(editingBoardID.uuidString)")

        guard let indexPath = indexPath(for: editingBoardID) else {
            logRenameTrace(
                "focusTitleEditorMissingIndexPath",
                extra: "boardID=\(editingBoardID.uuidString)"
            )
            self.editingBoardID = nil
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.focusTitleEditor(
                at: indexPath,
                boardID: editingBoardID
            )
        }
    }

    private func focusTitleEditor(
        at indexPath: IndexPath,
        boardID: UUID
    ) {
        guard editingBoardID == boardID else {
            logRenameTrace(
                "focusTitleEditorAborted",
                extra: "boardID=\(boardID.uuidString)"
            )
            return
        }

        logRenameTrace(
            "focusTitleEditorBegin",
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )

        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: indexPath,
            at: .centeredVertically,
            animated: false
        )
        collectionView.layoutIfNeeded()

        guard
            let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell
        else {
            logRenameTrace(
                "focusTitleEditorMissingCell",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
            )
            return
        }

        logRenameTrace("focusTitleEditorBeginEditing", extra: "boardID=\(boardID.uuidString)")
        cell.beginTitleEditing()
    }

    private func revealPendingBoardIfNeeded() {
        guard let pendingRevealBoardID else {
            return
        }

        logRenameTrace(
            "revealPendingBoardIfNeeded",
            extra: "boardID=\(pendingRevealBoardID.uuidString)"
        )

        guard let indexPath = indexPath(for: pendingRevealBoardID) else {
            logRenameTrace(
                "revealPendingBoardMissingIndexPath",
                extra: "boardID=\(pendingRevealBoardID.uuidString)"
            )
            self.pendingRevealBoardID = nil
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.revealBoard(
                at: indexPath,
                boardID: pendingRevealBoardID
            )
        }
    }

    private func revealBoard(
        at indexPath: IndexPath,
        boardID: UUID
    ) {
        guard pendingRevealBoardID == boardID else {
            logRenameTrace("revealBoardAborted", extra: "boardID=\(boardID.uuidString)")
            return
        }

        logRenameTrace(
            "revealBoard",
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )

        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: indexPath,
            at: .top,
            animated: false
        )
        pendingRevealBoardID = nil
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

    private func presentRenameError(_ error: Error) {
        let alertController = UIAlertController(
            title: "Unable to Rename Board",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.focusTitleEditorIfNeeded()
            }
        )
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

        let moreActionsHandler: iOSBoardCollectionViewCell.MoreActionsHandler?
        if editingBoardID == nil {
            moreActionsHandler = { [weak self] boardID, anchorRect, sourceView in
                self?.presentRenameActionPanel(
                    for: boardID,
                    anchorRect: anchorRect,
                    from: sourceView
                )
            }
        } else {
            moreActionsHandler = nil
        }

        if entry.boardID == editingBoardID {
            logRenameTrace(
                "configureEditingCell",
                extra:
                    "boardID=\(entry.boardID?.uuidString ?? "nil") " +
                    "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
            )
        }

        cell.configure(
            with: entry,
            previewContent: previewContent,
            displayMode: displayMode,
            isEditingTitle: entry.boardID.map { $0 == editingBoardID } ?? false,
            onMoreActionsRequested: moreActionsHandler,
            onRenameSubmitted: { [weak self] boardID, title in
                self?.commitRename(
                    boardID: boardID,
                    title: title
                )
            }
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
        logRenameTrace(
            "didSelectItemAt",
            extra:
                "entryID=\(describeRenameTraceEntryID(entry.id)) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )
        performPrimaryAction(for: entry)
        if entry.isPlaceholder {
            clearPlaceholderSelectionAfterAction()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard
            scrollView === collectionView,
            actionPanelState != nil,
            scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
        else {
            return
        }

        dismissActionPanel()
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
