#if os(iOS)
import UIKit

private func iOSBoardListRenameTraceTimestamp() -> String {
    String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
}

private enum BoardListPreparationMode {
    case fullDisplay
    case closingTarget(boardID: UUID)
}

private enum BoardListCatalogMutationChangeKind: String {
    case inserted
    case updated
    case moved
    case unchanged
}

private struct BoardListCatalogMutationResult {
    let resolvedIndexPath: IndexPath
    let previousIndexPath: IndexPath?
    let changeKind: BoardListCatalogMutationChangeKind
}

private enum BoardListPreviewWorkPolicy: Equatable {
    case normal
    case geometryOnly
}

private struct BoardListClosingTargetPreparationResult {
    let boardID: UUID
    let resolvedIndexPath: IndexPath
    let geometry: BoardListCanvasTransitionTargetGeometry
    let usedFallbackGeometry: Bool
}

final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 176
        static let sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 24)
        static let itemSpacing: CGFloat = 16
    }

    private typealias TransitionTargetGeometryHandler = (BoardListCanvasTransitionTargetGeometry) -> Void

    private struct PendingTransitionTargetResolution {
        let boardID: UUID
        let completion: TransitionTargetGeometryHandler
    }

    private struct ClosingTransitionTimingState {
        let trace: BoardListCanvasTransitionDebugTrace
        var targetGeometryRequestedAt: TimeInterval?
        var revealDispatchEnqueuedAt: TimeInterval?
        var revealDispatchDelay: TimeInterval?
        var refreshInvocationCount: Int = 0
        var reloadInvocationCount: Int = 0
        var reloadDuringTargetResolutionCount: Int = 0
    }

    private let folderPicker = FolderPicker()
    var onOpenCanvas: ((BoardListCanvasOpenRequest) -> Void)?

    private let catalogLoader = BoardCatalogLoader()
    private let previewProvider = BoardPreviewProvider()
    private var availableBoards: [BoardCatalogItem] = [] {
        didSet {
            rebuildAvailableBoardIndexByID()
        }
    }
    private var availableBoardIndexByID: [UUID: Int] = [:]
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
    private var pendingTransitionTargetResolution: PendingTransitionTargetResolution?
    private var closingTransitionTimingState: ClosingTransitionTimingState?
    private var previewWorkPolicy: BoardListPreviewWorkPolicy = .normal
    private var isTransitionInteractionFrozen = false
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
    private let transitionInteractionShieldView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
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
        setupActionPanelHostView()
        performBoardListSync(mode: .fullDisplay)
        applyTransitionInteractionFreeze()
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

        performBoardListSync(mode: .fullDisplay)
    }

    func setClosingTransitionTimingTrace(
        _ trace: BoardListCanvasTransitionDebugTrace?
    ) {
        guard let trace else {
            closingTransitionTimingState = nil
            return
        }

        closingTransitionTimingState = ClosingTransitionTimingState(trace: trace)
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
        restoreNormalPreviewWorkPolicy()

        if boardID == nil {
            logClosingTransitionTiming(
                phase: "prepareTransitionTargetGeometryMissingBoardID"
            )
        } else {
            let requestStart = BoardListCanvasTransitionDebugLogger.now()
            updateClosingTransitionTimingState { state in
                state.targetGeometryRequestedAt = requestStart
                state.revealDispatchEnqueuedAt = nil
            }
            logClosingTransitionTiming(
                phase: "prepareTransitionTargetGeometryBegin",
                extra: "boardID=\(boardID?.uuidString ?? "nil")"
            )
        }

        guard let boardID else {
            pendingRevealBoardID = nil
            completion(.init())
            closingTransitionTimingState = nil
            return
        }

        pendingRevealBoardID = boardID
        pendingTransitionTargetResolution = PendingTransitionTargetResolution(
            boardID: boardID,
            completion: completion
        )
        previewWorkPolicy = .geometryOnly

        guard isViewLoaded, view.window != nil else {
            logClosingTransitionTiming(
                phase: "prepareTransitionTargetGeometryWaitingForWindow",
                extra: "boardID=\(boardID.uuidString)"
            )
            return
        }

        performBoardListSync(mode: .closingTarget(boardID: boardID))
    }

    private func performBoardListSync(
        mode: BoardListPreparationMode
    ) {
        switch mode {
        case .fullDisplay:
            restoreNormalPreviewWorkPolicy()
            refreshBookmarkStatus()
        case let .closingTarget(boardID):
            syncClosingTargetBoard(boardID: boardID)
        }
    }

    private func syncClosingTargetBoard(
        boardID: UUID
    ) {
        logClosingTransitionTiming(
            phase: "performBoardListSync",
            extra:
                "mode=closingTarget " +
                "boardID=\(boardID.uuidString)"
        )
        dismissActionPanel()
        let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()

        do {
            let loadCatalogItemStart = BoardListCanvasTransitionDebugLogger.now()
            guard let boardItem = try catalogLoader.loadCatalogItem(boardID: boardID) else {
                restoreNormalPreviewWorkPolicy()
                logClosingTransitionTiming(
                    phase: "loadCatalogItemMissing",
                    extra: "boardID=\(boardID.uuidString)"
                )
                refreshBookmarkStatus()
                return
            }

            logClosingTransitionTiming(
                phase: "loadCatalogItemSuccess",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - loadCatalogItemStart,
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "boardCount=\(availableBoards.count)"
            )

            let mutationResult = upsertBoardCatalogItem(boardItem)
            let previousIndexPathDescription = mutationResult.previousIndexPath.map {
                "[section=\($0.section),item=\($0.item)]"
            } ?? "nil"
            let resolvedIndexPathDescription =
                "[section=\(mutationResult.resolvedIndexPath.section),item=\(mutationResult.resolvedIndexPath.item)]"
            logClosingTransitionTiming(
                phase: "upsertBoardCatalogItem",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "changeKind=\(mutationResult.changeKind.rawValue) " +
                    "previousIndexPath=\(previousIndexPathDescription) " +
                    "resolvedIndexPath=\(resolvedIndexPathDescription)"
            )

            hasSelectedFolder = true
            storageErrorMessage = nil
            selectedEntryID = .board(boardID)
            ensureValidSelection()
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus,
                    boardCount: availableBoards.count
                )
            )
            applyClosingTargetCollectionMutation(
                mutationResult,
                boardID: boardID
            )
        } catch FolderBookmarkStoreError.missingBookmarkData {
            restoreNormalPreviewWorkPolicy()
            replaceAvailableBoards(with: [])
            selectedEntryID = nil
            hasSelectedFolder = false
            storageErrorMessage = nil
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus
                )
            )
            let reloadStart = BoardListCanvasTransitionDebugLogger.now()
            reloadBoardList()
            logClosingTransitionTiming(
                phase: "reloadBoardListAfterClosingTargetMissingBookmark",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart
            )
        } catch {
            restoreNormalPreviewWorkPolicy()
            logClosingTransitionTiming(
                phase: "loadCatalogItemFailed",
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "error=\"\(error.localizedDescription)\""
            )
            refreshBookmarkStatus()
        }
    }

    private func applyClosingTargetCollectionMutation(
        _ mutationResult: BoardListCatalogMutationResult,
        boardID: UUID
    ) {
        let updateStart = BoardListCanvasTransitionDebugLogger.now()
        let previousIndexPathDescription = mutationResult.previousIndexPath.map {
            "[section=\($0.section),item=\($0.item)]"
        } ?? "nil"
        let resolvedIndexPathDescription =
            "[section=\(mutationResult.resolvedIndexPath.section),item=\(mutationResult.resolvedIndexPath.item)]"
        logClosingTransitionTiming(
            phase: "applyClosingTargetCollectionMutationBegin",
            extra:
                "boardID=\(boardID.uuidString) " +
                "changeKind=\(mutationResult.changeKind.rawValue) " +
                "previousIndexPath=\(previousIndexPathDescription) " +
                "resolvedIndexPath=\(resolvedIndexPathDescription)"
        )

        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateCollectionLayout()
        view.layoutIfNeeded()

        let finishMutation: () -> Void = { [weak self] in
            guard let self else {
                return
            }

            self.syncCollectionSelection()
            self.view.layoutIfNeeded()
            self.collectionView.layoutIfNeeded()
            self.logClosingTransitionTiming(
                phase: "applyClosingTargetCollectionMutationEnd",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - updateStart,
                extra:
                    "boardID=\(boardID.uuidString) " +
                    "changeKind=\(mutationResult.changeKind.rawValue) " +
                    "resolvedIndexPath=\(resolvedIndexPathDescription)"
            )
            self.revealPendingBoardIfNeeded()
        }

        switch mutationResult.changeKind {
        case .unchanged:
            finishMutation()
        case .updated:
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates({
                    self.collectionView.reloadItems(
                        at: [mutationResult.resolvedIndexPath]
                    )
                }, completion: { _ in
                    finishMutation()
                })
            }
        case .inserted:
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates({
                    self.collectionView.insertItems(
                        at: [mutationResult.resolvedIndexPath]
                    )
                }, completion: { _ in
                    finishMutation()
                })
            }
        case .moved:
            guard let previousIndexPath = mutationResult.previousIndexPath else {
                UIView.performWithoutAnimation {
                    self.collectionView.performBatchUpdates({
                        self.collectionView.reloadItems(
                            at: [mutationResult.resolvedIndexPath]
                        )
                    }, completion: { _ in
                        finishMutation()
                    })
                }
                return
            }

            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [previousIndexPath])
                    self.collectionView.insertItems(
                        at: [mutationResult.resolvedIndexPath]
                    )
                }, completion: { _ in
                    finishMutation()
                })
            }
        }
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
        view.addSubview(transitionInteractionShieldView)

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
            transitionInteractionShieldView.topAnchor.constraint(equalTo: view.topAnchor),
            transitionInteractionShieldView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transitionInteractionShieldView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transitionInteractionShieldView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    private func updateClosingTransitionTimingState(
        _ update: (inout ClosingTransitionTimingState) -> Void
    ) {
        guard var state = closingTransitionTimingState else {
            return
        }

        update(&state)
        closingTransitionTimingState = state
    }

    private func logClosingTransitionTiming(
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        guard let trace = closingTransitionTimingState?.trace else {
            return
        }

        BoardListCanvasTransitionDebugLogger.log(
            platform: "iOS",
            component: "BoardList",
            trace: trace,
            phase: phase,
            localDuration: localDuration,
            extra: extra
        )
    }

    private func currentPreviewWorkPolicy() -> BoardListPreviewWorkPolicy {
        previewWorkPolicy
    }

    private func restoreNormalPreviewWorkPolicy() {
        previewWorkPolicy = .normal
    }

    private func describePreviewWorkPolicy(
        _ policy: BoardListPreviewWorkPolicy
    ) -> String {
        switch policy {
        case .normal:
            return "normal"
        case .geometryOnly:
            return "geometryOnly"
        }
    }

    private func logClosingGuardSummary(
        boardID: UUID,
        hasCardRect: Bool,
        usedFallbackGeometry: Bool? = nil
    ) {
        guard let state = closingTransitionTimingState else {
            return
        }

        let revealDispatchDelaySummary = state.revealDispatchDelay.map {
            BoardListCanvasTransitionDebugLogger.durationString($0)
        } ?? "nil"
        let fallbackSuffix = usedFallbackGeometry.map {
            " usedFallbackGeometry=\($0)"
        } ?? ""
        logClosingTransitionTiming(
            phase: "closingTargetReadySummary",
            extra:
                "boardID=\(boardID.uuidString) " +
                "refreshCount=\(state.refreshInvocationCount) " +
                "reloadCount=\(state.reloadInvocationCount) " +
                "targetReadyReloadCount=\(state.reloadDuringTargetResolutionCount) " +
                "revealDispatchDelay=\(revealDispatchDelaySummary) " +
                "hasCardRect=\(hasCardRect)" +
                fallbackSuffix
        )
    }

    private func scheduleVisibleBoardThumbnailRefreshIfNeeded() {
        guard currentPreviewWorkPolicy() == .normal else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.requestVisibleBoardThumbnailsIfNeeded()
        }
    }

    private func requestVisibleBoardThumbnailsIfNeeded() {
        guard
            currentPreviewWorkPolicy() == .normal,
            isViewLoaded,
            view.window != nil
        else {
            return
        }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted {
            if $0.section == $1.section {
                return $0.item < $1.item
            }

            return $0.section < $1.section
        }
        for indexPath in visibleIndexPaths {
            guard
                let entry = entry(at: indexPath),
                let catalogItem = entry.catalogItem,
                let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell,
                cell.isShowingThumbnailPreview == false
            else {
                continue
            }

            cell.requestThumbnail(
                using: previewProvider,
                for: catalogItem,
                displayMode: displayMode
            )
        }
    }

    private func replaceAvailableBoards(
        with boards: [BoardCatalogItem]
    ) {
        availableBoards = Self.orderedBoardCatalogItems(boards)
    }

    private func upsertBoardCatalogItem(
        _ item: BoardCatalogItem
    ) -> BoardListCatalogMutationResult {
        let previousBoardIndex = availableBoardIndexByID[item.boardID]
        let previousItem = previousBoardIndex.flatMap { boardIndex in
            guard availableBoards.indices.contains(boardIndex) else {
                return nil
            }
            return availableBoards[boardIndex]
        }

        if let previousBoardIndex,
           availableBoards.indices.contains(previousBoardIndex) {
            availableBoards.remove(at: previousBoardIndex)
        }

        let resolvedBoardIndex = insertionIndexForBoardCatalogItem(item)
        availableBoards.insert(item, at: resolvedBoardIndex)

        let resolvedIndexPath = catalogEntryIndexPath(
            forBoardIndex: resolvedBoardIndex
        )
        let previousIndexPath = previousBoardIndex.map {
            catalogEntryIndexPath(forBoardIndex: $0)
        }
        let changeKind: BoardListCatalogMutationChangeKind
        if let previousItem,
           let previousBoardIndex {
            if previousBoardIndex == resolvedBoardIndex {
                changeKind =
                    previousItem.revisionToken == item.revisionToken
                    ? .unchanged
                    : .updated
            } else {
                changeKind = .moved
            }
        } else {
            changeKind = .inserted
        }

        return BoardListCatalogMutationResult(
            resolvedIndexPath: resolvedIndexPath,
            previousIndexPath: previousIndexPath,
            changeKind: changeKind
        )
    }

    private func rebuildAvailableBoardIndexByID() {
        availableBoardIndexByID = Dictionary(
            uniqueKeysWithValues: availableBoards.enumerated().map { index, item in
                (item.boardID, index)
            }
        )
    }

    private static func orderedBoardCatalogItems(
        _ boards: [BoardCatalogItem]
    ) -> [BoardCatalogItem] {
        boards.sorted(by: Self.boardCatalogItemSortsBefore)
    }

    private func insertionIndexForBoardCatalogItem(
        _ item: BoardCatalogItem
    ) -> Int {
        availableBoards.firstIndex(where: { existingItem in
            Self.boardCatalogItemSortsBefore(item, existingItem)
        }) ?? availableBoards.count
    }

    private static func boardCatalogItemSortsBefore(
        _ lhs: BoardCatalogItem,
        _ rhs: BoardCatalogItem
    ) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.boardID.uuidString < rhs.boardID.uuidString
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func refreshBookmarkStatus() {
        logRenameTrace("refreshBookmarkStatusBegin")
        var refreshInvocationCount: Int?
        updateClosingTransitionTimingState { state in
            state.refreshInvocationCount += 1
            refreshInvocationCount = state.refreshInvocationCount
        }
        let refreshStart = BoardListCanvasTransitionDebugLogger.now()
        logClosingTransitionTiming(phase: "refreshBookmarkStatusBegin")
        if let refreshInvocationCount,
           refreshInvocationCount > 1 {
            logClosingTransitionTiming(
                phase: "guardDoubleRefreshDetected",
                extra:
                    "count=\(refreshInvocationCount) " +
                    "pendingBoardID=\(pendingTransitionTargetResolution?.boardID.uuidString ?? "nil")"
            )
        }
        dismissActionPanel()
        let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
        do {
            let loadCatalogStart = BoardListCanvasTransitionDebugLogger.now()
            let boards = try catalogLoader.loadCatalog()
            logClosingTransitionTiming(
                phase: "loadCatalogSuccess",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - loadCatalogStart,
                extra: "boardCount=\(boards.count)"
            )
            replaceAvailableBoards(with: boards)
            hasSelectedFolder = true
            storageErrorMessage = nil
            ensureValidSelection()
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus,
                    boardCount: boards.count
                )
            )
            let reloadStart = BoardListCanvasTransitionDebugLogger.now()
            reloadBoardList()
            logClosingTransitionTiming(
                phase: "reloadBoardListAfterCatalogSuccess",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart,
                extra: "entryCount=\(entries.count)"
            )
        } catch FolderBookmarkStoreError.missingBookmarkData {
            replaceAvailableBoards(with: [])
            selectedEntryID = nil
            hasSelectedFolder = false
            storageErrorMessage = nil
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus
                )
            )
            let reloadStart = BoardListCanvasTransitionDebugLogger.now()
            reloadBoardList()
            logClosingTransitionTiming(
                phase: "reloadBoardListAfterMissingBookmark",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart
            )
        } catch {
            logClosingTransitionTiming(
                phase: "loadCatalogFailed",
                extra: "error=\"\(error.localizedDescription)\""
            )
            replaceAvailableBoards(with: [])
            selectedEntryID = nil
            hasSelectedFolder = bookmarkStatus.hasSelectedFolder
            storageErrorMessage = error.localizedDescription
            applyHeaderState(
                BoardListHeaderStateBuilder.make(
                    bookmarkStatus: bookmarkStatus,
                    storageErrorDescription: error.localizedDescription
                )
            )
            let reloadStart = BoardListCanvasTransitionDebugLogger.now()
            reloadBoardList()
            logClosingTransitionTiming(
                phase: "reloadBoardListAfterCatalogFailure",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart
            )
        }
        logRenameTrace("refreshBookmarkStatusEnd", extra: "boardCount=\(availableBoards.count)")
        logClosingTransitionTiming(
            phase: "refreshBookmarkStatusEnd",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - refreshStart,
            extra:
                "boardCount=\(availableBoards.count) " +
                "hasSelectedFolder=\(hasSelectedFolder) " +
                "hasStorageError=\(storageErrorMessage != nil)"
        )
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
        let triggeredDuringTargetResolution =
            pendingTransitionTargetResolution != nil ||
            currentPreviewWorkPolicy() == .geometryOnly
        var reloadInvocationCount: Int?
        var reloadDuringTargetResolutionCount: Int?
        updateClosingTransitionTimingState { state in
            state.reloadInvocationCount += 1
            reloadInvocationCount = state.reloadInvocationCount
            if triggeredDuringTargetResolution {
                state.reloadDuringTargetResolutionCount += 1
                reloadDuringTargetResolutionCount = state.reloadDuringTargetResolutionCount
            }
        }
        let reloadStart = BoardListCanvasTransitionDebugLogger.now()
        logClosingTransitionTiming(
            phase: "reloadBoardListBegin",
            extra: "entryCount=\(entries.count)"
        )
        if let reloadInvocationCount {
            logClosingTransitionTiming(
                phase: "guardReloadDataObserved",
                extra:
                    "count=\(reloadInvocationCount) " +
                    "duringTargetResolution=\(triggeredDuringTargetResolution) " +
                    "previewWorkPolicy=\(describePreviewWorkPolicy(currentPreviewWorkPolicy()))"
            )
        }
        if let reloadDuringTargetResolutionCount {
            logClosingTransitionTiming(
                phase: "guardTargetReadyReloadDataDetected",
                extra:
                    "count=\(reloadDuringTargetResolutionCount) " +
                    "boardID=\(pendingTransitionTargetResolution?.boardID.uuidString ?? "nil") " +
                    "entryCount=\(entries.count)"
            )
        }
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateCollectionLayout()
        syncCollectionSelection()
        revealPendingBoardIfNeeded()
        focusTitleEditorIfNeeded()
        logRenameTrace("reloadBoardListEnd", extra: "entryCount=\(entries.count)")
        logClosingTransitionTiming(
            phase: "reloadBoardListEnd",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart,
            extra: "entryCount=\(entries.count)"
        )
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
        collectionView.isScrollEnabled = isTransitionInteractionFrozen == false
        if isTransitionInteractionFrozen {
            dismissActionPanel()
        }
        updateDisplayModeControlState()
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
        collectionView.layoutIfNeeded()
        if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
            return cell.transitionGeometry(in: view)
        }

        return BoardListCanvasTransitionSourceGeometry(
            cardRect: transitionCardRect(at: indexPath)
        )
    }

    private func resolveTransitionTargetGeometry(
        for boardID: UUID
    ) -> BoardListClosingTargetPreparationResult? {
        guard let resolvedIndexPath = indexPath(for: boardID) else {
            return nil
        }

        let geometry: BoardListCanvasTransitionTargetGeometry
        let usedFallbackGeometry: Bool
        if let cell = collectionView.cellForItem(
            at: resolvedIndexPath
        ) as? iOSBoardCollectionViewCell {
            geometry = BoardListCanvasTransitionTargetGeometry(
                cardRect: cell.transitionGeometry(in: view).cardRect
            )
            usedFallbackGeometry = false
        } else {
            geometry = BoardListCanvasTransitionTargetGeometry(
                cardRect: transitionCardRect(at: resolvedIndexPath)
            )
            usedFallbackGeometry = true
        }

        logClosingTransitionTiming(
            phase: "resolveTransitionTargetGeometry",
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(resolvedIndexPath.section),item=\(resolvedIndexPath.item)] " +
                "usedFallbackGeometry=\(usedFallbackGeometry) " +
                "hasCardRect=\(geometry.cardRect != nil)"
        )
        return BoardListClosingTargetPreparationResult(
            boardID: boardID,
            resolvedIndexPath: resolvedIndexPath,
            geometry: geometry,
            usedFallbackGeometry: usedFallbackGeometry
        )
    }

    private func transitionCardRect(at indexPath: IndexPath) -> CGRect? {
        collectionView.layoutIfNeeded()
        guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
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

        let resolutionDuration = closingTransitionTimingState?.targetGeometryRequestedAt.map {
            BoardListCanvasTransitionDebugLogger.now() - $0
        }
        logClosingTransitionTiming(
            phase: "finishPendingTransitionTargetResolution",
            localDuration: resolutionDuration,
            extra:
                "boardID=\(boardID.uuidString) " +
                "hasCardRect=\(geometry.cardRect != nil)"
        )
        logClosingGuardSummary(
            boardID: boardID,
            hasCardRect: geometry.cardRect != nil
        )
        let completion = pendingTransitionTargetResolution?.completion
        pendingTransitionTargetResolution = nil
        closingTransitionTimingState = nil
        restoreNormalPreviewWorkPolicy()
        completion?(geometry)
        scheduleVisibleBoardThumbnailRefreshIfNeeded()
    }

    private func finishPendingTransitionTargetResolution(
        _ preparationResult: BoardListClosingTargetPreparationResult
    ) {
        guard pendingTransitionTargetResolution?.boardID == preparationResult.boardID else {
            return
        }

        let resolutionDuration = closingTransitionTimingState?.targetGeometryRequestedAt.map {
            BoardListCanvasTransitionDebugLogger.now() - $0
        }
        logClosingTransitionTiming(
            phase: "finishPendingTransitionTargetResolution",
            localDuration: resolutionDuration,
            extra:
                "boardID=\(preparationResult.boardID.uuidString) " +
                "indexPath=[section=\(preparationResult.resolvedIndexPath.section),item=\(preparationResult.resolvedIndexPath.item)] " +
                "usedFallbackGeometry=\(preparationResult.usedFallbackGeometry) " +
                "hasCardRect=\(preparationResult.geometry.cardRect != nil)"
        )
        logClosingGuardSummary(
            boardID: preparationResult.boardID,
            hasCardRect: preparationResult.geometry.cardRect != nil,
            usedFallbackGeometry: preparationResult.usedFallbackGeometry
        )
        let completion = pendingTransitionTargetResolution?.completion
        pendingTransitionTargetResolution = nil
        closingTransitionTimingState = nil
        restoreNormalPreviewWorkPolicy()
        completion?(preparationResult.geometry)
        scheduleVisibleBoardThumbnailRefreshIfNeeded()
    }

    private func catalogEntryIndexPath(
        forBoardIndex boardIndex: Int
    ) -> IndexPath {
        IndexPath(item: boardIndex + 1, section: 0)
    }

    private func indexPath(for boardID: UUID) -> IndexPath? {
        guard
            hasSelectedFolder,
            storageErrorMessage == nil,
            let boardIndex = availableBoardIndexByID[boardID]
        else {
            return nil
        }

        return catalogEntryIndexPath(forBoardIndex: boardIndex)
    }

    private func boardTitle(for boardID: UUID) -> String? {
        guard
            let boardIndex = availableBoardIndexByID[boardID],
            availableBoards.indices.contains(boardIndex)
        else {
            return nil
        }

        return availableBoards[boardIndex].title
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
    private func handleSelectFolderButtonTap() {
        guard isTransitionInteractionFrozen == false else {
            return
        }

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
        guard isTransitionInteractionFrozen == false else {
            return
        }

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
            if let catalogItem = try catalogLoader.loadCatalogItem(boardID: boardID) {
                let mutationResult = upsertBoardCatalogItem(catalogItem)
                let previousIndexPathDescription = mutationResult.previousIndexPath.map {
                    "[section=\($0.section),item=\($0.item)]"
                } ?? "nil"
                let resolvedIndexPathDescription =
                    "[section=\(mutationResult.resolvedIndexPath.section),item=\(mutationResult.resolvedIndexPath.item)]"
                hasSelectedFolder = true
                storageErrorMessage = nil
                ensureValidSelection()
                applyHeaderState(
                    BoardListHeaderStateBuilder.make(
                        bookmarkStatus: FolderBookmarkStore.bookmarkStatus(),
                        boardCount: availableBoards.count
                    )
                )
                logRenameTrace(
                    "commitRenameAppliedCatalogMutation",
                    extra:
                        "boardID=\(boardID.uuidString) " +
                        "changeKind=\(mutationResult.changeKind.rawValue) " +
                        "previousIndexPath=\(previousIndexPathDescription) " +
                        "resolvedIndexPath=\(resolvedIndexPathDescription)"
                )
                reloadBoardList()
            } else {
                logRenameTrace(
                    "commitRenameCatalogItemMissing",
                    extra: "boardID=\(boardID.uuidString)"
                )
                refreshBookmarkStatus()
            }
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

        logClosingTransitionTiming(
            phase: "revealPendingBoardIfNeeded",
            extra: "boardID=\(pendingRevealBoardID.uuidString)"
        )
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
            closingTransitionTimingState = nil
            return
        }

        let enqueueTime = BoardListCanvasTransitionDebugLogger.now()
        updateClosingTransitionTimingState { state in
            state.revealDispatchEnqueuedAt = enqueueTime
        }
        logClosingTransitionTiming(
            phase: "revealPendingBoardEnqueued",
            extra: "boardID=\(pendingRevealBoardID.uuidString)"
        )
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

        let revealStart = BoardListCanvasTransitionDebugLogger.now()
        let dispatchDelay = closingTransitionTimingState?.revealDispatchEnqueuedAt.map {
            revealStart - $0
        }
        updateClosingTransitionTimingState { state in
            state.revealDispatchDelay = dispatchDelay
        }
        logClosingTransitionTiming(
            phase: "revealBoardBegin",
            localDuration: dispatchDelay,
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
        )
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
        collectionView.layoutIfNeeded()
        let preparationResult = resolveTransitionTargetGeometry(for: boardID)
        logClosingTransitionTiming(
            phase: "revealBoardEnd",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - revealStart,
            extra:
                "boardID=\(boardID.uuidString) " +
                "indexPath=[section=\(preparationResult?.resolvedIndexPath.section ?? indexPath.section),item=\(preparationResult?.resolvedIndexPath.item ?? indexPath.item)] " +
                "usedFallbackGeometry=\(preparationResult?.usedFallbackGeometry ?? true) " +
                "hasCardRect=\(preparationResult?.geometry.cardRect != nil)"
        )
        if let preparationResult {
            finishPendingTransitionTargetResolution(preparationResult)
        } else {
            finishPendingTransitionTargetResolution(
                for: boardID,
                geometry: .init()
            )
        }
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
            switch currentPreviewWorkPolicy() {
            case .normal:
                let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
                previewContent = previewProvider.immediatePreview(
                    for: catalogItem,
                    targetPixelSize: targetPixelSize
                )
            case .geometryOnly:
                previewContent = .geometry(catalogItem.previewSeed)
            }
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
           previewContent.isThumbnail == false,
           currentPreviewWorkPolicy() == .normal {
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
            isTransitionInteractionFrozen == false,
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
