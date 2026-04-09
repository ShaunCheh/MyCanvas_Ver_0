#if os(macOS)
import AppKit

final class macOSBoardListViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 220
        static let sectionHorizontalInset: CGFloat = 24
        static let sectionBottomInset: CGFloat = 24
        static let sectionTopInset: CGFloat = 0
        static let itemSpacing: CGFloat = 16
    }

    private typealias TransitionTargetGeometryHandler = (BoardListCanvasTransitionTargetGeometry) -> Void

    private struct PendingTransitionTargetResolution {
        let boardID: UUID
        let completion: TransitionTargetGeometryHandler
    }

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
    private var leftMouseEventMonitor: Any?
    private var scrollBoundsObserver: NSObjectProtocol?
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
    private var pendingTransitionTargetResolution: PendingTransitionTargetResolution?
    private var isTransitionInteractionFrozen = false
    private var displayMode: BoardListDisplayMode = .grid {
        didSet {
            guard oldValue != displayMode else {
                return
            }

            reloadBoardList()
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
    private let actionPanelHostView = BoardListActionPanelHostView()
    private let transitionInteractionShieldView = macOSTransitionInteractionShieldView()

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
        // Keep single-click selection responsive while still recognizing double-click open.
        doubleClickGestureRecognizer.delaysPrimaryMouseButtonEvents = false
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

    deinit {
        if let leftMouseEventMonitor {
            NSEvent.removeMonitor(leftMouseEventMonitor)
        }
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        setupActionPanelHostView()
        setupCollectionScrollObservation()
        setupMouseEventLogging()
        refreshBookmarkStatus()
        applyTransitionInteractionFreeze()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCollectionLayout()
        updateActionPanelLayout()
    }

    func prepareForDisplay() {
        guard isViewLoaded else {
            return
        }

        refreshBookmarkStatus()
    }

    func setTransitionInteractionFrozen(_ isFrozen: Bool) {
        guard isTransitionInteractionFrozen != isFrozen else {
            return
        }

        isTransitionInteractionFrozen = isFrozen
        guard isViewLoaded else {
            return
        }

        applyTransitionInteractionFreeze()
    }

    func transitionSourceGeometry(
        for entryID: BoardListEntryID
    ) -> BoardListCanvasTransitionSourceGeometry {
        guard let indexPath = indexPath(for: entryID) else {
            return .init()
        }

        return transitionSourceGeometry(at: indexPath)
    }

    func prepareTransitionTargetGeometry(
        for boardID: UUID?,
        completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
    ) {
        pendingTransitionTargetResolution = nil

        guard let boardID else {
            pendingRevealBoardID = nil
            completion(.init())
            return
        }

        pendingRevealBoardID = boardID
        pendingTransitionTargetResolution = PendingTransitionTargetResolution(
            boardID: boardID,
            completion: completion
        )

        guard isViewLoaded, view.window != nil else {
            return
        }

        refreshBookmarkStatus()
    }

    private func logSelectionTrace(_ phase: String, extra: String = "") {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardList][macOS][SelectionTrace] " +
                "t=\(selectionTraceTimestamp()) " +
                "phase=\(phase) " +
                "displayMode=\(displayMode.title) " +
                "selectedEntryID=\(describeSelectionTraceEntryID(selectedEntryID)) " +
                "collectionSelection=\(describeSelectionTraceIndexPaths(collectionView.selectionIndexPaths))" +
                extraSuffix
        )
    }

    private func selectionTraceTimestamp() -> String {
        String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
    }

    private func logRenameTrace(_ phase: String, extra: String = "") {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardList][macOS][RenameTrace] " +
                "t=\(selectionTraceTimestamp()) " +
                "phase=\(phase) " +
                "editingBoardID=\(editingBoardID?.uuidString ?? "nil") " +
                "pendingRevealBoardID=\(pendingRevealBoardID?.uuidString ?? "nil") " +
                "selectedEntryID=\(describeSelectionTraceEntryID(selectedEntryID)) " +
                "actionPanelBoardID=\(actionPanelState?.boardID.uuidString ?? "nil")" +
                extraSuffix
        )
    }

    private func describeSelectionTraceEntryID(_ entryID: BoardListEntryID?) -> String {
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

    private func describeSelectionTraceEntry(_ entry: BoardListEntry?) -> String {
        guard let entry else {
            return "nil"
        }

        return "id=\(describeSelectionTraceEntryID(entry.id)) title=\"\(entry.title)\" placeholder=\(entry.isPlaceholder)"
    }

    private func describeSelectionTraceIndexPath(_ indexPath: IndexPath) -> String {
        "[section=\(indexPath.section),item=\(indexPath.item)]"
    }

    private func describeSelectionTracePoint(_ point: CGPoint) -> String {
        String(format: "(x=%.1f,y=%.1f)", point.x, point.y)
    }

    private func logThumbnailTrace(
        phase: String,
        boardID: UUID,
        revisionToken: String,
        targetPixelSize: CGSize,
        previewContent: BoardPreviewContent,
        indexPath: IndexPath,
        reason: String?
    ) {
        var message =
            "[BoardList][macOS][ThumbnailTrace][Controller] " +
            "t=\(selectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "boardID=\(boardID.uuidString) " +
            "revision=\(revisionToken) " +
            "displayMode=\(displayMode.title) " +
            "indexPath=\(describeSelectionTraceIndexPath(indexPath)) " +
            "targetPixelSize=\(describeBoardListThumbnailSize(targetPixelSize)) " +
            "previewContent=\(describeBoardListPreviewContent(previewContent))"
        if let reason {
            message += " reason=\(reason)"
        }
        print(message)
    }

    private func describeBoardListPreviewContent(
        _ previewContent: BoardPreviewContent
    ) -> String {
        switch previewContent {
        case .empty:
            return "empty"
        case .geometry:
            return "geometry"
        case let .thumbnail(image, _):
            return "thumbnail(\(image.width)x\(image.height))"
        }
    }

    private func describeBoardListThumbnailSize(_ size: CGSize) -> String {
        "{\(String(format: "%.2f", Double(size.width))), \(String(format: "%.2f", Double(size.height)))}"
    }

    private func describeSelectionTraceIndexPaths(_ indexPaths: Set<IndexPath>) -> String {
        guard indexPaths.isEmpty == false else {
            return "[]"
        }

        return "[" + indexPaths
            .sorted {
                if $0.section == $1.section {
                    return $0.item < $1.item
                }

                return $0.section < $1.section
            }
            .map(describeSelectionTraceIndexPath)
            .joined(separator: ",") + "]"
    }

    private func describeSelectionTraceItems(at indexPaths: Set<IndexPath>) -> String {
        guard indexPaths.isEmpty == false else {
            return "items=[]"
        }

        return "items=[" + indexPaths
            .sorted {
                if $0.section == $1.section {
                    return $0.item < $1.item
                }

                return $0.section < $1.section
            }
            .map { indexPath in
                "{indexPath=\(describeSelectionTraceIndexPath(indexPath)) entry=\(describeSelectionTraceEntry(entry(at: indexPath)))}"
            }
            .joined(separator: ", ") + "]"
    }

    private func describeSelectionTraceHighlightState(
        _ highlightState: NSCollectionViewItem.HighlightState
    ) -> String {
        switch highlightState {
        case .none:
            return "none"
        case .forSelection:
            return "forSelection"
        case .forDeselection:
            return "forDeselection"
        case .asDropTarget:
            return "asDropTarget"
        @unknown default:
            return "unknown"
        }
    }

    private func setupMouseEventLogging() {
        guard leftMouseEventMonitor == nil else {
            return
        }

        leftMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.logLeftMouseEventTrace(event)
            return event
        }
    }

    private func logLeftMouseEventTrace(_ event: NSEvent) {
        guard
            event.window === view.window,
            view.isHiddenOrHasHiddenAncestor == false,
            collectionView.window != nil
        else {
            return
        }

        let locationInCollectionView = collectionView.convert(
            event.locationInWindow,
            from: nil
        )
        guard collectionView.bounds.contains(locationInCollectionView) else {
            return
        }

        let indexPath = collectionView.indexPathForItem(at: locationInCollectionView)
        let entry = indexPath.flatMap(entry(at:))
        let phase: String
        switch event.type {
        case .leftMouseDown:
            phase = "leftMouseDown"
        case .leftMouseUp:
            phase = "leftMouseUp"
        default:
            phase = "leftMouseEvent"
        }

        logSelectionTrace(
            phase,
            extra:
                "clickCount=\(event.clickCount) " +
                "location=\(describeSelectionTracePoint(locationInCollectionView)) " +
                "hitIndexPath=\(indexPath.map(describeSelectionTraceIndexPath) ?? "nil") " +
                "hitEntry=\(describeSelectionTraceEntry(entry))"
        )
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
        view.addSubview(actionPanelHostView)
        view.addSubview(transitionInteractionShieldView)

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
            actionPanelHostView.topAnchor.constraint(equalTo: view.topAnchor),
            actionPanelHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionPanelHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionPanelHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            transitionInteractionShieldView.topAnchor.constraint(equalTo: view.topAnchor),
            transitionInteractionShieldView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transitionInteractionShieldView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transitionInteractionShieldView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    private func setupActionPanelHostView() {
        actionPanelHostView.onDismissRequested = { [weak self] in
            self?.dismissActionPanel()
        }
        actionPanelHostView.onActionSelected = { [weak self] actionID in
            self?.performBoardAction(actionID)
        }
    }

    private func setupCollectionScrollObservation() {
        guard scrollBoundsObserver == nil else {
            return
        }

        collectionScrollView.contentView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: collectionScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleCollectionScrollBoundsDidChange()
        }
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
        logSelectionTrace(
            "reloadBoardListBegin",
            extra: "entries=\(entries.count)"
        )
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateCollectionLayout()
        syncCollectionSelection()
        revealPendingBoardIfNeeded()
        focusTitleEditorIfNeeded()
        logSelectionTrace(
            "reloadBoardListEnd",
            extra: "entries=\(entries.count)"
        )
        logRenameTrace("reloadBoardListEnd", extra: "entryCount=\(entries.count)")
    }

    private func updateDisplayModeControlState() {
        displayModeControl.isEnabled =
            hasSelectedFolder &&
            storageErrorMessage == nil &&
            isTransitionInteractionFrozen == false
    }

    private func applyTransitionInteractionFreeze() {
        transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
        selectFolderButton.isEnabled = isTransitionInteractionFrozen == false
        collectionView.isSelectable = isTransitionInteractionFrozen == false
        if isTransitionInteractionFrozen {
            dismissActionPanel()
        }
        updateDisplayModeControlState()
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
            logSelectionTrace(
                "syncCollectionSelectionClear",
                extra: "reason=no_selected_entry"
            )
            isSyncingSelection = true
            collectionView.deselectAll(nil)
            isSyncingSelection = false
            logSelectionTrace("syncCollectionSelectionCleared")
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        logSelectionTrace(
            "syncCollectionSelectionApply",
            extra: "targetIndexPath=\(describeSelectionTraceIndexPath(indexPath))"
        )
        isSyncingSelection = true
        collectionView.selectItems(
            at: Set([indexPath]),
            scrollPosition: []
        )
        isSyncingSelection = false
        logSelectionTrace(
            "syncCollectionSelectionApplied",
            extra: "targetIndexPath=\(describeSelectionTraceIndexPath(indexPath))"
        )
    }

    private func clearPlaceholderSelectionAfterAction() {
        selectedEntryID = firstRealBoardEntryID
        syncCollectionSelection()
    }

    private func indexPath(for entryID: BoardListEntryID) -> IndexPath? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }

        return IndexPath(item: index, section: 0)
    }

    private func entry(at indexPath: IndexPath) -> BoardListEntry? {
        guard entries.indices.contains(indexPath.item) else {
            return nil
        }

        return entries[indexPath.item]
    }

    private func transitionSourceGeometry(
        at indexPath: IndexPath
    ) -> BoardListCanvasTransitionSourceGeometry {
        collectionView.layoutSubtreeIfNeeded()
        if let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem {
            return item.transitionGeometry(in: view)
        }

        return BoardListCanvasTransitionSourceGeometry(
            cardRect: transitionCardRect(at: indexPath)
        )
    }

    private func transitionTargetGeometry(
        for boardID: UUID
    ) -> BoardListCanvasTransitionTargetGeometry {
        guard let indexPath = indexPath(for: boardID) else {
            return .init()
        }

        if let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem {
            return BoardListCanvasTransitionTargetGeometry(
                cardRect: item.transitionGeometry(in: view).cardRect
            )
        }

        return BoardListCanvasTransitionTargetGeometry(
            cardRect: transitionCardRect(at: indexPath)
        )
    }

    private func transitionCardRect(at indexPath: IndexPath) -> CGRect? {
        collectionView.layoutSubtreeIfNeeded()
        guard let layoutAttributes = collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: indexPath) else {
            return nil
        }

        return view.convert(
            layoutAttributes.frame,
            from: collectionView
        )
    }

    private func finishPendingTransitionTargetResolution(
        for boardID: UUID,
        geometry: BoardListCanvasTransitionTargetGeometry
    ) {
        guard pendingTransitionTargetResolution?.boardID == boardID else {
            return
        }

        let completion = pendingTransitionTargetResolution?.completion
        pendingTransitionTargetResolution = nil
        completion?(geometry)
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
        guard isTransitionInteractionFrozen == false else {
            return
        }

        dismissActionPanel()
        guard
            hasSelectedFolder,
            storageErrorMessage == nil,
            editingBoardID == nil
        else {
            logRenameTrace(
                "performPrimaryActionBlocked",
                extra:
                    "entryID=\(describeSelectionTraceEntryID(entry.id)) " +
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
        let sourceGeometry = transitionSourceGeometry(for: entry.id)
        switch entry {
        case .newBoardPlaceholder:
            return .newBoardPlaceholder(geometry: sourceGeometry)
        case let .board(item):
            return .existingBoard(
                boardID: item.boardID,
                geometry: sourceGeometry
            )
        }
    }

    @objc
    private func handleSelectFolderButtonClick() {
        guard isTransitionInteractionFrozen == false else {
            return
        }

        dismissActionPanel()
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
        guard isTransitionInteractionFrozen == false else {
            return
        }

        dismissActionPanel()
        let requestedDisplayMode = BoardListDisplayMode(
            segmentIndex: displayModeControl.selectedSegment
        )
        logSelectionTrace(
            "displayModeChangeRequested",
            extra: "requestedDisplayMode=\(requestedDisplayMode.title)"
        )
        displayMode = requestedDisplayMode
    }

    private func presentRenameActionPanel(
        for boardID: UUID,
        anchorRect: CGRect,
        from sourceView: NSView
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
            safeBounds: CGRect(
                x: view.bounds.minX + view.safeAreaInsets.left,
                y: view.bounds.minY + view.safeAreaInsets.top,
                width: max(
                    view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
                    0
                ),
                height: max(
                    view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom,
                    0
                )
            ).standardized,
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
        guard isTransitionInteractionFrozen == false else {
            return
        }

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

    private func cancelRename(boardID: UUID) {
        guard editingBoardID == boardID else {
            logRenameTrace("cancelRenameIgnored", extra: "boardID=\(boardID.uuidString)")
            return
        }

        logRenameTrace("cancelRename", extra: "boardID=\(boardID.uuidString)")
        editingBoardID = nil
        pendingRevealBoardID = nil
        reloadBoardList()
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
            logRenameTrace("focusTitleEditorAborted", extra: "boardID=\(boardID.uuidString)")
            return
        }

        logRenameTrace(
            "focusTitleEditorBegin",
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )

        collectionView.layoutSubtreeIfNeeded()
        collectionView.scrollToItems(
            at: Set([indexPath]),
            scrollPosition: .nearestVerticalEdge
        )
        collectionScrollView.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()

        guard let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem else {
            logRenameTrace(
                "focusTitleEditorMissingItem",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
            )
            return
        }

        logRenameTrace("focusTitleEditorBeginEditing", extra: "boardID=\(boardID.uuidString)")
        item.beginTitleEditing()
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
            finishPendingTransitionTargetResolution(
                for: pendingRevealBoardID,
                geometry: .init()
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

        collectionView.layoutSubtreeIfNeeded()
        collectionView.scrollToItems(
            at: Set([indexPath]),
            scrollPosition: .nearestVerticalEdge
        )
        collectionView.layoutSubtreeIfNeeded()
        finishPendingTransitionTargetResolution(
            for: boardID,
            geometry: transitionTargetGeometry(for: boardID)
        )
        pendingRevealBoardID = nil
    }

    private func handleCollectionScrollBoundsDidChange() {
        guard actionPanelState != nil else {
            return
        }

        dismissActionPanel()
    }

    @objc
    private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        guard
            isTransitionInteractionFrozen == false,
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

        logSelectionTrace(
            "doubleClickRecognized",
            extra:
                "indexPath=\(describeSelectionTraceIndexPath(indexPath)) " +
                "entry=\(describeSelectionTraceEntry(entry))"
        )
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

    private func presentRenameError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Rename Board"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.focusTitleEditorIfNeeded()
            }
        } else {
            alert.runModal()
            focusTitleEditorIfNeeded()
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
            logThumbnailTrace(
                phase: "configureItemImmediatePreview",
                boardID: catalogItem.boardID,
                revisionToken: catalogItem.revisionToken,
                targetPixelSize: targetPixelSize,
                previewContent: previewContent,
                indexPath: indexPath,
                reason: nil
            )
        } else {
            previewContent = .empty
        }

        let moreActionsHandler: macOSBoardCollectionItem.MoreActionsHandler?
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
                "configureEditingItem",
                extra:
                    "boardID=\(entry.boardID?.uuidString ?? "nil") " +
                    "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
            )
        }

        item.configure(
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
            },
            onRenameCancelled: { [weak self] boardID in
                self?.cancelRename(boardID: boardID)
            }
        )

        if entry.canRequestPreview,
           let catalogItem = entry.catalogItem,
           previewContent.isThumbnail == false {
            logThumbnailTrace(
                phase: "configureItemAsyncRequest",
                boardID: catalogItem.boardID,
                revisionToken: catalogItem.revisionToken,
                targetPixelSize: item.targetThumbnailPixelSize(for: displayMode),
                previewContent: previewContent,
                indexPath: indexPath,
                reason: "immediate-preview-not-thumbnail"
            )
            item.requestThumbnail(
                using: previewProvider,
                for: catalogItem,
                displayMode: displayMode
            )
        } else if entry.canRequestPreview,
                  let catalogItem = entry.catalogItem {
            logThumbnailTrace(
                phase: "configureItemAsyncRequestSkipped",
                boardID: catalogItem.boardID,
                revisionToken: catalogItem.revisionToken,
                targetPixelSize: item.targetThumbnailPixelSize(for: displayMode),
                previewContent: previewContent,
                indexPath: indexPath,
                reason: "immediate-preview-already-thumbnail"
            )
        }
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        shouldSelectItemsAt indexPaths: Set<IndexPath>
    ) -> Set<IndexPath> {
        logSelectionTrace(
            "shouldSelectItems",
            extra: describeSelectionTraceItems(at: indexPaths)
        )
        return indexPaths
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didChangeItemsAt indexPaths: Set<IndexPath>,
        to highlightState: NSCollectionViewItem.HighlightState
    ) {
        logSelectionTrace(
            "didChangeHighlightState",
            extra:
                "highlightState=\(describeSelectionTraceHighlightState(highlightState)) " +
                describeSelectionTraceItems(at: indexPaths)
        )
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard
            isTransitionInteractionFrozen == false,
            isSyncingSelection == false,
            let indexPath = indexPaths.first,
            let entry = entry(at: indexPath)
        else {
            return
        }

        logSelectionTrace(
            "didSelectItems",
            extra:
                "syncing=\(isSyncingSelection) " +
                describeSelectionTraceItems(at: indexPaths)
        )
        selectedEntryID = entry.id
        logRenameTrace(
            "didSelectItemsAt",
            extra:
                "entryID=\(describeSelectionTraceEntryID(entry.id)) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )
        if entry.isPlaceholder {
            performPrimaryAction(for: entry)
            clearPlaceholderSelectionAfterAction()
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
        let shouldClearSelectedEntryID =
            isSyncingSelection == false &&
            collectionView.selectionIndexPaths.isEmpty
        if shouldClearSelectedEntryID {
            selectedEntryID = nil
        }
        logSelectionTrace(
            "didDeselectItems",
            extra:
                "syncing=\(isSyncingSelection) " +
                "clearedSelectedEntryID=\(shouldClearSelectedEntryID) " +
                describeSelectionTraceItems(at: indexPaths)
        )
    }
}
#endif
