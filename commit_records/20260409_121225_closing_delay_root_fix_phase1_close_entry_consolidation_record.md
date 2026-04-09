# 20260409_121225_closing_delay_root_fix_phase1_close_entry_consolidation_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 1` 实施记录。
- 记录目标：先从时序入口上消掉 iOS closing 链里的双 `refreshBookmarkStatus()`，并把 `BoardList` 的同步入口统一收口。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift` 与修改后的源码内容整理。
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：`Phase 2` 的单板 catalog 读取能力。
- 本记录不包含：`Phase 3` 之后的 targeted upsert / target-ready 快路径。
- 本记录不包含：git commit。

## 问题背景

- 在本次修改前，iOS closing 链的实际前置顺序是：
  1. `AppRoot.beginClosingTransition(with:)` 挂载 `boardListViewController`
  2. 立即调用 `destinationViewController.prepareForDisplay()`
  3. 随后再调用 `destinationViewController.prepareTransitionTargetGeometry(...)`
- 由于 `prepareForDisplay()` 和 `prepareTransitionTargetGeometry(...)` 最终都会落到 `iOSBoardListViewController.refreshBookmarkStatus()`，一次返回会形成两轮列表同步。
- Phase 1 的目标不是立刻把 closing 改成单板同步，而是先确保 closing 期间只有一个同步入口，为后续 `Phase 2 ~ Phase 4` 的 targeted 路径预留稳定边界。

## 修改一：AppRoot 不再在 closing 前置阶段主动调用 `prepareForDisplay()`

### 修改前

- `beginClosingTransition(with:)` 在挂载 `BoardList` 后，先打 `prepareForDisplay` 的耗时日志，再主动执行一次 `prepareForDisplay()`。
- 这会让 closing 在真正请求 target geometry 之前，先跑完一轮完整的 `BoardList` 刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginClosingTransition(with:)
// 功能说明: 修改前 closing 在挂载 BoardList 后，先主动触发 prepareForDisplay()，导致后续 prepareTransitionTargetGeometry(...) 又走一轮列表同步。
private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    // ... 省略 session / freeze / overlay / mount 逻辑 ...
    destinationViewController.setClosingTransitionTimingTrace(session.debugTrace)

    if let trace = session.debugTrace {
        logClosingTransitionTrace(
            trace,
            phase: "beginClosingTransition",
            extra: "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil")"
        )
    }

    let prepareForDisplayStart = BoardListCanvasTransitionDebugLogger.now()
    destinationViewController.prepareForDisplay()
    if let trace = session.debugTrace {
        logClosingTransitionTrace(
            trace,
            phase: "boardListPrepareForDisplayFinished",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - prepareForDisplayStart
        )
    }

    let carrierPreparationStart = BoardListCanvasTransitionDebugLogger.now()
    view.layoutIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    let targetBoardID = request.transitionContext.targetBoardID
    destinationViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.handleResolvedClosingTargetGeometry(
            geometry,
            sessionID: session.id,
            expectedBoardID: targetBoardID
        )
    }
}
```

### 修改后

- `beginClosingTransition(with:)` 不再在 closing 前置阶段主动调用 `prepareForDisplay()`。
- closing 现在只保留 `prepareTransitionTargetGeometry(...)` 这一条前置同步入口。
- `boardListPrepareForDisplayFinished` 这段 closing 专用耗时日志也随之移除，避免继续暗示 closing 仍依赖这条旧路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginClosingTransition(with:)
// 功能说明: 修改后 closing 挂载 BoardList 后直接进入 carrier 准备与 target geometry 请求，不再额外走 prepareForDisplay()。
private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    // ... 省略 session / freeze / overlay / mount 逻辑 ...
    destinationViewController.setClosingTransitionTimingTrace(session.debugTrace)

    if let trace = session.debugTrace {
        logClosingTransitionTrace(
            trace,
            phase: "beginClosingTransition",
            extra: "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil")"
        )
    }

    let carrierPreparationStart = BoardListCanvasTransitionDebugLogger.now()
    view.layoutIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    if let trace = session.debugTrace {
        logClosingTransitionTrace(
            trace,
            phase: "carrierPrepareFinished",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - carrierPreparationStart
        )
    }

    let targetBoardID = request.transitionContext.targetBoardID
    session.closingTargetGeometryRequestedAt = BoardListCanvasTransitionDebugLogger.now()
    destinationViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.handleResolvedClosingTargetGeometry(
            geometry,
            sessionID: session.id,
            expectedBoardID: targetBoardID
        )
    }
}
```

## 修改二：BoardList 新增 `BoardListPreparationMode` 与统一同步入口 `performBoardListSync(mode:)`

### 修改前

- `viewDidLoad()`、`prepareForDisplay()` 和 `prepareTransitionTargetGeometry(...)` 都是各自直接调用 `refreshBookmarkStatus()`。
- 这意味着调用方虽然语义不同，但都会直接打到同一个“全量刷新”实现上，时序入口是散的。
- `prepareForDisplay()` 里还带着一段专门给 closing trace 用的分支逻辑，但本质上仍然是在调用同一轮 `refreshBookmarkStatus()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: viewDidLoad() / prepareForDisplay() / prepareTransitionTargetGeometry(for:completion:)
// 功能说明: 修改前 BoardList 的全量刷新入口分散在多个调用点；closing 和 full display 虽然语义不同，但都直接落到 refreshBookmarkStatus()。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    setupActionPanelHostView()
    refreshBookmarkStatus()
    applyTransitionInteractionFreeze()
}

func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    if closingTransitionTimingState != nil {
        let prepareStart = BoardListCanvasTransitionDebugLogger.now()
        logClosingTransitionTiming(phase: "prepareForDisplayBegin")
        refreshBookmarkStatus()
        logClosingTransitionTiming(
            phase: "prepareForDisplayEnd",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - prepareStart,
            extra: "boardCount=\(availableBoards.count)"
        )
        return
    }

    refreshBookmarkStatus()
}

func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    // ... 省略 pendingTransitionTargetResolution / boardID / window guard ...
    refreshBookmarkStatus()
}
```

### 修改后

- 新增 `BoardListPreparationMode`，先把 `BoardList` 的同步语义明确拆成：
  - `.fullDisplay`
  - `.closingTarget(boardID: UUID)`
- 新增 `performBoardListSync(mode:)` 作为统一同步入口。
- `viewDidLoad()` 和 `prepareForDisplay()` 改成统一走 `.fullDisplay`。
- `prepareTransitionTargetGeometry(...)` 改成统一走 `.closingTarget(boardID:)`。
- 需要强调的是：**Phase 1 里 `.closingTarget` 仍然暂时复用 `refreshBookmarkStatus()`**。这次只是先把入口收口，后续 `Phase 2` 才会把这个分支替换成单板 catalog 读取，`Phase 4` 才会进一步替换成真正的 target-ready 快路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: BoardListPreparationMode / viewDidLoad() / prepareForDisplay() / prepareTransitionTargetGeometry(for:completion:) / performBoardListSync(mode:)
// 功能说明: 修改后 BoardList 先把“全量显示同步”和“closing target 同步”收口到同一个入口；Phase 1 先统一入口，不在这一轮改变 closingTarget 分支的底层刷新实现。
private enum BoardListPreparationMode {
    case fullDisplay
    case closingTarget(boardID: UUID)
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    setupActionPanelHostView()
    performBoardListSync(mode: .fullDisplay)
    applyTransitionInteractionFreeze()
}

func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    performBoardListSync(mode: .fullDisplay)
}

func prepareTransitionTargetGeometry(
    for boardID: UUID?,
    completion: @escaping (BoardListCanvasTransitionTargetGeometry) -> Void
) {
    // ... 省略 pendingTransitionTargetResolution / boardID / window guard ...
    performBoardListSync(mode: .closingTarget(boardID: boardID))
}

private func performBoardListSync(
    mode: BoardListPreparationMode
) {
    switch mode {
    case .fullDisplay:
        refreshBookmarkStatus()
    case let .closingTarget(boardID):
        // Phase 1 keeps closing target prep on the existing refresh path.
        // Later phases will swap this branch to targeted single-board sync.
        logClosingTransitionTiming(
            phase: "performBoardListSync",
            extra:
                "mode=closingTarget " +
                "boardID=\(boardID.uuidString)"
        )
        refreshBookmarkStatus()
    }
}
```

## 行为变化说明

- 这次修改后，iOS closing 链在进入 `prepareTransitionTargetGeometry(...)` 之前，不会再额外执行一轮 `prepareForDisplay()` 驱动的全量刷新。
- `BoardList` 侧的 `fullDisplay` 与 `closingTarget` 已经有了明确语义边界，但当前底层刷新能力仍然是同一套 `refreshBookmarkStatus()`。
- 因此这次修改属于“先收口入口、消掉重复路径”，不是“已经切成单板同步”。

## 对后续阶段的影响

- `Phase 2` 可以直接把 `performBoardListSync(mode: .closingTarget(...))` 从全量 `refreshBookmarkStatus()` 替换成单板 `loadBoardDocumentEntry(id:) -> loadCatalogItem(boardID:)` 路径。
- `Phase 3` 可以继续围绕这个统一入口给 `availableBoards` 补 `upsertBoardCatalogItem(_:)` 和 mutation 结果。
- `Phase 4` 可以在不改 `AppRoot` contract 的前提下，把 `prepareTransitionTargetGeometry(...)` 内部替换成真正的 target-ready 快路径。

## 验证

- 已确认当前工作树中关于本次修改的 `git diff` 只涉及以上两个 iOS 文件。
- 已用 IDE 诊断检查：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 结果：`No linter errors found`
- 本次未执行完整 iOS 编译，也未运行真机 / 模拟器返回链回归。
