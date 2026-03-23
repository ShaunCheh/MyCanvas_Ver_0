# 20260323_182903_boardlist_rename_phase3_controller_panel_lifecycle_record

## 记录范围

- 记录内容：
  1. 在 `iOS` / `macOS` 的 `BoardListViewController` 中接入 action panel overlay host、面板 state 和控制器级生命周期。
  2. 为刷新、切换显示模式、打开 board、选择文件夹、滚动列表等路径补齐 action panel dismiss 逻辑。
  3. 同步更新 BoardList rename 实施计划中的 `controller-panel-state` 状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md`
- 本记录不包含：
  - Grid/List cell 的三点按钮
  - 标题内联编辑 UI
  - rename 提交、回顶与显式滚动恢复
  - git commit / push

## 修改一：在 iOS BoardList controller 中接入 action panel overlay 与 state

### 修改前

- `iOSBoardListViewController` 还只有列表本身的状态：`availableBoards`、`selectedEntryID`、`hasSelectedFolder`、`storageErrorMessage`、`displayMode`。
- view 层级里没有 `actionPanelHostView`，`viewDidLoad()` / `viewDidLayoutSubviews()` 也没有任何 panel 展示或 layout 更新逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: 属性定义 / viewDidLoad() / viewDidLayoutSubviews() / setupViewHierarchy()
// 功能说明: 修改前 iOS BoardList controller 只管理列表与 header，没有 action panel overlay、editingBoardID 或 pendingRevealBoardID。
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

private let contentContainerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
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
```

### 修改后

- 新增 `actionPanelState`，并通过 `didSet` 驱动 `updateActionPanelPresentation()`。
- 新增 `editingBoardID`、`pendingRevealBoardID` 作为后续 Phase 4/5 要继续消费的控制器状态。
- 新增 `actionPanelHostView`，并在 `viewDidLoad()` 和 `viewDidLayoutSubviews()` 中接入 action panel 的初始化和 layout 更新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: 属性定义 / viewDidLoad() / viewDidLayoutSubviews() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 iOS BoardList controller 开始持有 action panel 的控制器级状态，并把全屏 host view 挂到根视图四边。
private let catalogLoader = BoardCatalogLoader()
private let previewProvider = BoardPreviewProvider()
private var availableBoards: [BoardCatalogItem] = []
private var selectedEntryID: BoardListEntryID?
private var actionPanelState: BoardListActionPanelState? {
    didSet {
        updateActionPanelPresentation()
    }
}
private var hasSelectedFolder = false
private var storageErrorMessage: String?
private var isSyncingSelection = false
private var editingBoardID: UUID?
private var pendingRevealBoardID: UUID?
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

private let contentContainerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let actionPanelHostView = BoardListActionPanelHostView()

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
        // ... 省略原有 header / collection constraints ...
        actionPanelHostView.topAnchor.constraint(equalTo: view.topAnchor),
        actionPanelHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        actionPanelHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        actionPanelHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}
```

## 修改二：为 iOS controller 新增 action panel 生命周期与 dismiss 时机

### 修改前

- iOS 侧没有 `presentRenameActionPanel(...)`、`dismissActionPanel()`、`performBoardAction(...)` 这些控制器级方法。
- `refreshBookmarkStatus()`、`performPrimaryAction(for:)`、`handleSelectFolderButtonTap()`、`handleDisplayModeChange()` 都不会考虑 action panel 的存在。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus() / performPrimaryAction(for:) / handleSelectFolderButtonTap() / handleDisplayModeChange()
// 功能说明: 修改前 iOS 侧没有 action panel 生命周期管理，因此刷新、打开 board、切换模式、选择文件夹时都不存在统一的 dismiss 路径。
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
        // ... 省略其余分支 ...
        reloadBoardList()
    } catch {
        // ... 省略其余分支 ...
        reloadBoardList()
    }
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
        // ... 省略回调 ...
    }
}

@objc
private func handleDisplayModeChange() {
    displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegmentIndex)
}
```

### 修改后

- 新增 `setupActionPanelHostView()`，把 host 的 dismiss / action 回调接到 controller。
- 新增 `presentRenameActionPanel(...)`、`dismissActionPanel()`、`updateActionPanelPresentation()`、`updateActionPanelLayout()`、`makeActionPanelLayoutContext()`、`actionPanelOccupiedRects()`、`performBoardAction(...)`。
- 在刷新、打开 board、选择文件夹、切换显示模式时统一调用 `dismissActionPanel()`。
- 额外新增 `scrollViewDidScroll(_:)`，让 iOS 列表滚动时也会收起面板。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: setupActionPanelHostView() / presentRenameActionPanel(...) / dismissActionPanel() / updateActionPanelPresentation()
// 功能说明: 修改后 iOS controller 拥有完整的 action panel 控制器入口；后续 cell 三点按钮只要回调这里即可打开 rename 面板。
private func setupActionPanelHostView() {
    actionPanelHostView.onDismissRequested = { [weak self] in
        self?.dismissActionPanel()
    }
    actionPanelHostView.onActionSelected = { [weak self] actionID in
        self?.performBoardAction(actionID)
    }
}

private func presentRenameActionPanel(
    for boardID: UUID,
    anchorRect: CGRect,
    from sourceView: UIView
) {
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus() / performPrimaryAction(for:) / handleSelectFolderButtonTap() / handleDisplayModeChange() / scrollViewDidScroll(_:)
// 功能说明: 修改后 iOS 侧把 refresh、打开 board、切换模式、选择文件夹、滚动列表都纳入 action panel 的 dismiss 生命周期。
private func refreshBookmarkStatus() {
    dismissActionPanel()
    let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
    // ... 省略其余加载逻辑 ...
}

private func performPrimaryAction(for entry: BoardListEntry) {
    dismissActionPanel()
    guard
        hasSelectedFolder,
        storageErrorMessage == nil,
        editingBoardID == nil
    else {
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
    dismissActionPanel()
    folderPicker.present(from: self) { [weak self] result in
        // ... 省略回调 ...
    }
}

@objc
private func handleDisplayModeChange() {
    dismissActionPanel()
    displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegmentIndex)
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
```

## 修改三：在 macOS BoardList controller 中接入 overlay host、scroll 观察和 panel 生命周期

### 修改前

- `macOSBoardListViewController` 只有 selection trace 和列表自身的状态，没有 `actionPanelState`、`editingBoardID`、`pendingRevealBoardID`、`scrollBoundsObserver`。
- view 层级里也没有 `actionPanelHostView`，滚动列表时没有任何 panel dismiss 观察逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: 属性定义 / deinit / viewDidLoad() / setupViewHierarchy()
// 功能说明: 修改前 macOS BoardList controller 还没有 action panel 的任何接线；deinit 只清理鼠标监视器，view 层级中也没有 overlay host。
private let catalogLoader = BoardCatalogLoader()
private let previewProvider = BoardPreviewProvider()
private var availableBoards: [BoardCatalogItem] = []
private var selectedEntryID: BoardListEntryID?
private var hasSelectedFolder = false
private var storageErrorMessage: String?
private var isSyncingSelection = false
private var leftMouseEventMonitor: Any?
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

deinit {
    if let leftMouseEventMonitor {
        NSEvent.removeMonitor(leftMouseEventMonitor)
    }
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    setupMouseEventLogging()
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
```

### 修改后

- 新增 `actionPanelState`、`scrollBoundsObserver`、`editingBoardID`、`pendingRevealBoardID`、`actionPanelHostView`。
- `deinit` 现在会同时移除 scroll observer。
- `viewDidLoad()` 中接入 `setupActionPanelHostView()` 和 `setupCollectionScrollObservation()`。
- `setupViewHierarchy()` / `setupConstraints()` 中将 `actionPanelHostView` 挂到根视图四边。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: 属性定义 / deinit / viewDidLoad() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 macOS controller 持有 panel state、scroll observer 和 overlay host，并把 host 作为全屏层挂进根视图。
private let catalogLoader = BoardCatalogLoader()
private let previewProvider = BoardPreviewProvider()
private var availableBoards: [BoardCatalogItem] = []
private var selectedEntryID: BoardListEntryID?
private var actionPanelState: BoardListActionPanelState? {
    didSet {
        updateActionPanelPresentation()
    }
}
private var hasSelectedFolder = false
private var storageErrorMessage: String?
private var isSyncingSelection = false
private var leftMouseEventMonitor: Any?
private var scrollBoundsObserver: NSObjectProtocol?
private var editingBoardID: UUID?
private var pendingRevealBoardID: UUID?
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

private let contentContainerView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let actionPanelHostView = BoardListActionPanelHostView()

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

    contentContainerView.addSubview(collectionScrollView)
    contentContainerView.addSubview(emptyStateLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        // ... 省略原有 header / collection constraints ...
        actionPanelHostView.topAnchor.constraint(equalTo: view.topAnchor),
        actionPanelHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        actionPanelHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        actionPanelHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}
```

- macOS 侧还新增了 `setupCollectionScrollObservation()` 和 `handleCollectionScrollBoundsDidChange()`，把 `NSScrollView` 的滚动也纳入 panel dismiss 生命周期。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: setupActionPanelHostView() / setupCollectionScrollObservation() / handleCollectionScrollBoundsDidChange()
// 功能说明: 修改后 macOS controller 会在 panel 展示期间监听 scroll view 的 bounds 变化，一旦列表滚动就立即收起面板。
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

private func handleCollectionScrollBoundsDidChange() {
    guard actionPanelState != nil else {
        return
    }

    dismissActionPanel()
}
```

- 与 iOS 对齐，macOS 侧也新增了 `presentRenameActionPanel(...)`、`dismissActionPanel()`、`updateActionPanelPresentation()`、`updateActionPanelLayout()`、`makeActionPanelLayoutContext()`、`actionPanelOccupiedRects()`、`performBoardAction(...)`，并在 refresh / open / select folder / display mode change 时统一做 dismiss。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: presentRenameActionPanel(...) / performPrimaryAction(for:) / handleSelectFolderButtonClick() / handleDisplayModeChange() / performBoardAction(_:)
// 功能说明: 修改后 macOS controller 拥有和 iOS 对等的 action panel 展示入口与 dismiss 时机；未来 cell 的三点按钮可以直接把 anchor rect 回调到这里。
private func presentRenameActionPanel(
    for boardID: UUID,
    anchorRect: CGRect,
    from sourceView: NSView
) {
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

private func performPrimaryAction(for entry: BoardListEntry) {
    dismissActionPanel()
    guard
        hasSelectedFolder,
        storageErrorMessage == nil,
        editingBoardID == nil
    else {
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
    dismissActionPanel()
    do {
        guard let bookmarkData = try FilePickerManager.selectFolder() else {
            return
        }
        // ... 省略其余保存 bookmark 逻辑 ...
    } catch {
        // ... 省略错误处理 ...
    }
}

@objc
private func handleDisplayModeChange() {
    dismissActionPanel()
    let requestedDisplayMode = BoardListDisplayMode(
        segmentIndex: displayModeControl.selectedSegment
    )
    displayMode = requestedDisplayMode
}

private func performBoardAction(_ actionID: BoardListActionID) {
    let boardID = actionPanelState?.boardID
    dismissActionPanel()

    switch actionID {
    case .rename:
        editingBoardID = boardID
        reloadBoardList()
    }
}
```

## 修改四：同步计划文件中的 Phase 3 完成状态

### 修改前

- BoardList rename 计划里，`controller-panel-state` 仍是 `pending`。
- 这会让“controller 层接线已经落地”和“计划状态尚未完成”之间出现偏差。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改前，Phase 3 的 controller-panel-state 任务仍标记为 pending。
todos:
  - id: controller-panel-state
    content: 在 iOS/macOS BoardListViewController 中接入 panel state、editingBoardID、pendingRevealBoardID 和面板生命周期
    status: pending
```

### 修改后

- 将 `controller-panel-state` 标记为 `completed`。
- 这只属于实施进度同步，不改变产品运行逻辑。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改后，Phase 3 的 controller-panel-state 任务已与当前代码实现同步为 completed。
todos:
  - id: controller-panel-state
    content: 在 iOS/macOS BoardListViewController 中接入 panel state、editingBoardID、pendingRevealBoardID 和面板生命周期
    status: completed
```

## 当前边界说明

- 本次 Phase 3 已经把 panel 的控制器承载层接通，但还没有任何 cell 三点按钮来调用 `presentRenameActionPanel(...)`。
- `editingBoardID` 与 `pendingRevealBoardID` 已进入 controller 状态，但本阶段还没有标题编辑 UI 或滚动回顶逻辑来消费它们。
- 因此当前产品行为仍不会显示新的三点菜单；本次改动主要是为 Phase 4 / Phase 5 提前铺好 controller 层骨架。

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift` 无新增 linter 问题。
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift` 无新增 linter 问题。
- 类型检查：
  - 已执行 `xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift`
  - 结果通过。

## 当前阶段结论

- Phase 3 已完成：BoardList controller 现在已经具备 action panel 的 overlay host、展示/收起入口和生命周期管理。
- 下一阶段可以直接实施 Phase 4，把 Grid/List cell 的三点按钮和 anchor rect 回调接到这些 controller 方法上。
