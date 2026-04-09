# 20260409_142646_closing_delay_root_fix_phase6_closing_trace_guardrails_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 6` 实施记录。
- 记录目标：在不改变当前 closing 主路径行为的前提下，补齐回归验证所需的 closing trace 摘要指标，并增加后续排查/回归时可直接观测的性能护栏日志。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_142646`
  - 当前工作树 `git status --short`
  - 当前工作树 `git diff -- MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
  - 修改后的源码内容
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 本记录不包含：
  - 新的业务逻辑修复
  - 新的 UI 行为改动
  - git commit

## Phase 6 目标

- 让 closing 日志直接给出这三段关键区间，而不是依赖人工做时间差：
  - `backButtonTap -> carrierAnimateBegin`
  - `requestTargetGeometry -> targetGeometryResolved`
  - `revealPendingBoardEnqueued -> revealBoardBegin`
- 给后续回归增加护栏，确保以下问题一旦重新出现，会在日志里直接暴露：
  - closing 期间双 `refreshBookmarkStatus()`
  - target-ready 期间全量 `reloadData()`
  - trace 本身重新触发 source-image 读取

## 修改一：为 AppRoot closing trace 补齐可直接读取的摘要指标

### 修改前

- `iOSBoardListCanvasTransitionSession` 只记录了 `closingTargetGeometryRequestedAt` 和 `closingAnimationStartedAt`。
- `iOSAppRootViewController` 在 closing 路径里虽然有 `targetGeometryResolved`、`carrierAnimateBegin`、`completeClosingTransition` 这些日志点，但：
  - 没有保存“target geometry resolved 时刻”
  - `carrierAnimateBegin` 只输出 `hasCardRect`
  - `completeClosingTransition` 只输出动画本身的 `localDuration`
- 结果是：后续分析时仍需要人工对照多条日志做减法，不能从单条摘要日志直接读出关键区间。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionSession
// 功能说明: 修改前 session 只记录 target 请求时刻和动画开始时刻，没有 resolved 时刻，无法在 AppRoot 层稳定汇总 target-ready 区间。
final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?
    let debugTrace: BoardListCanvasTransitionDebugTrace?
    var closingTargetGeometryRequestedAt: TimeInterval?
    var closingAnimationStartedAt: TimeInterval?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / completeClosingTransition(sessionID:)
// 功能说明: 修改前 AppRoot 只记录 targetGeometryResolved 的局部时长，carrierAnimateBegin 与 completeClosingTransition 还没有回归摘要指标。
if let trace = session.debugTrace {
    let targetResolutionDuration = session.closingTargetGeometryRequestedAt.map {
        BoardListCanvasTransitionDebugLogger.now() - $0
    }
    logClosingTransitionTrace(
        trace,
        phase: "targetGeometryResolved",
        localDuration: targetResolutionDuration,
        extra:
            "hasCardRect=\(geometry.cardRect != nil) " +
            "expectedBoardID=\(expectedBoardID?.uuidString ?? "nil")"
    )
}

session.closingAnimationStartedAt = BoardListCanvasTransitionDebugLogger.now()
if let trace = session.debugTrace {
    logClosingTransitionTrace(
        trace,
        phase: "carrierAnimateBegin",
        extra: "hasCardRect=\(geometry.cardRect != nil)"
    )
}

if let trace = session.debugTrace {
    let animationDuration = session.closingAnimationStartedAt.map {
        BoardListCanvasTransitionDebugLogger.now() - $0
    }
    logClosingTransitionTrace(
        trace,
        phase: "completeClosingTransition",
        localDuration: animationDuration
    )
}
```

### 修改后

- `session` 新增 `closingTargetGeometryResolvedAt`，把 target-ready 的 resolved 时刻显式保存下来。
- `handleResolvedClosingTargetGeometry(...)` 使用单一 `geometryResolvedAt`：
  - 先写回 session
  - 再复用该时刻计算 `targetGeometryResolved` 的 `localDuration`
  - 再基于 trace 起点和 request/resolved 区间构造回归摘要
- `carrierAnimateBegin` 现在直接输出：
  - `backButtonToCarrierAnimate`
  - `requestTargetGeometryToResolved`
- `completeClosingTransition` 现在直接输出：
  - `backButtonToCarrierAnimate`
  - `requestTargetGeometryToResolved`
  - `animationDuration`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionSession
// 功能说明: 修改后 session 补充 resolved 时刻，为 AppRoot 层统一输出 closing 回归摘要指标提供稳定状态来源。
final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?
    let debugTrace: BoardListCanvasTransitionDebugTrace?
    var closingTargetGeometryRequestedAt: TimeInterval?
    var closingTargetGeometryResolvedAt: TimeInterval?
    var closingAnimationStartedAt: TimeInterval?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / completeClosingTransition(sessionID:)
// 功能说明: 修改后 AppRoot 在 carrierAnimateBegin 和 completeClosingTransition 两个关键点直接输出 closing 回归摘要，不再依赖人工减时间差。
let geometryResolvedAt = BoardListCanvasTransitionDebugLogger.now()
session.closingTargetGeometryResolvedAt = geometryResolvedAt

if let trace = session.debugTrace {
    let targetResolutionDuration = session.closingTargetGeometryRequestedAt.map {
        geometryResolvedAt - $0
    }
    logClosingTransitionTrace(
        trace,
        phase: "targetGeometryResolved",
        localDuration: targetResolutionDuration,
        extra:
            "hasCardRect=\(geometry.cardRect != nil) " +
            "expectedBoardID=\(expectedBoardID?.uuidString ?? "nil")"
    )
}

session.closingAnimationStartedAt = BoardListCanvasTransitionDebugLogger.now()
if let trace = session.debugTrace {
    let backButtonToCarrierAnimate = session.closingAnimationStartedAt.map {
        $0 - trace.startedAtUptime
    }
    let requestTargetGeometryToResolved: TimeInterval? = {
        guard
            let requestedAt = session.closingTargetGeometryRequestedAt,
            let resolvedAt = session.closingTargetGeometryResolvedAt
        else {
            return nil
        }

        return resolvedAt - requestedAt
    }()
    let backButtonToCarrierAnimateSummary = backButtonToCarrierAnimate.map {
        BoardListCanvasTransitionDebugLogger.durationString($0)
    } ?? "nil"
    let requestTargetGeometryToResolvedSummary = requestTargetGeometryToResolved.map {
        BoardListCanvasTransitionDebugLogger.durationString($0)
    } ?? "nil"
    logClosingTransitionTrace(
        trace,
        phase: "carrierAnimateBegin",
        extra:
            "hasCardRect=\(geometry.cardRect != nil) " +
            "backButtonToCarrierAnimate=\(backButtonToCarrierAnimateSummary) " +
            "requestTargetGeometryToResolved=\(requestTargetGeometryToResolvedSummary)"
    )
}

if let trace = session.debugTrace {
    let animationDuration = session.closingAnimationStartedAt.map {
        BoardListCanvasTransitionDebugLogger.now() - $0
    }
    let backButtonToCarrierAnimate = session.closingAnimationStartedAt.map {
        $0 - trace.startedAtUptime
    }
    let requestTargetGeometryToResolved: TimeInterval? = {
        guard
            let requestedAt = session.closingTargetGeometryRequestedAt,
            let resolvedAt = session.closingTargetGeometryResolvedAt
        else {
            return nil
        }

        return resolvedAt - requestedAt
    }()
    let backButtonToCarrierAnimateSummary = backButtonToCarrierAnimate.map {
        BoardListCanvasTransitionDebugLogger.durationString($0)
    } ?? "nil"
    let requestTargetGeometryToResolvedSummary = requestTargetGeometryToResolved.map {
        BoardListCanvasTransitionDebugLogger.durationString($0)
    } ?? "nil"
    let animationDurationSummary = animationDuration.map {
        BoardListCanvasTransitionDebugLogger.durationString($0)
    } ?? "nil"
    logClosingTransitionTrace(
        trace,
        phase: "completeClosingTransition",
        localDuration: animationDuration,
        extra:
            "backButtonToCarrierAnimate=\(backButtonToCarrierAnimateSummary) " +
            "requestTargetGeometryToResolved=\(requestTargetGeometryToResolvedSummary) " +
            "animationDuration=\(animationDurationSummary)"
    )
}
```

## 修改二：扩展 BoardList closing timing state，使护栏统计有稳定落点

### 修改前

- `ClosingTransitionTimingState` 只保留了 trace 本身、target request 时刻和 reveal dispatch 入队时刻。
- 这意味着：
  - 无法在 state 内累计 refresh / reload 调用次数
  - 无法在 summary 阶段直接拿到 `revealDispatchDelay`
  - 无法在 target-ready 完成前统一输出一条 closing 护栏摘要

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: ClosingTransitionTimingState
// 功能说明: 修改前 timing state 只保存最基础的时序字段，没有为回归护栏预留计数与 reveal 排队时长。
private struct ClosingTransitionTimingState {
    let trace: BoardListCanvasTransitionDebugTrace
    var targetGeometryRequestedAt: TimeInterval?
    var revealDispatchEnqueuedAt: TimeInterval?
}
```

### 修改后

- `ClosingTransitionTimingState` 新增：
  - `revealDispatchDelay`
  - `refreshInvocationCount`
  - `reloadInvocationCount`
  - `reloadDuringTargetResolutionCount`
- 同时新增两个 helper：
  - `describePreviewWorkPolicy(_:)`
  - `logClosingGuardSummary(boardID:hasCardRect:usedFallbackGeometry:)`
- `logClosingGuardSummary(...)` 会在 target-ready 完成前，把本轮 closing 关键护栏状态汇总到单条日志里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: ClosingTransitionTimingState / describePreviewWorkPolicy(_:) / logClosingGuardSummary(boardID:hasCardRect:usedFallbackGeometry:)
// 功能说明: 修改后 BoardList 有了可累计的护栏 state，并能在 target-ready 完成前输出统一 closing 摘要。
private struct ClosingTransitionTimingState {
    let trace: BoardListCanvasTransitionDebugTrace
    var targetGeometryRequestedAt: TimeInterval?
    var revealDispatchEnqueuedAt: TimeInterval?
    var revealDispatchDelay: TimeInterval?
    var refreshInvocationCount: Int = 0
    var reloadInvocationCount: Int = 0
    var reloadDuringTargetResolutionCount: Int = 0
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
```

## 修改三：把 BoardList 护栏统计接入 refresh / reload / reveal / target-ready 收口

### 修改前

- `refreshBookmarkStatus()` 只记录原有 begin/end timing，没有统计调用次数，也不会在重复触发时输出告警。
- `reloadBoardList()` 只记录 begin/end timing，没有区分“普通 reload”与“target-ready 期间 reloadData”。
- `finishPendingTransitionTargetResolution(...)` 在清理 state 之前不会输出本轮 closing 护栏摘要。
- `revealBoard(...)` 虽然计算了 `dispatchDelay`，但没有把它持久写回 state，因此 summary 无法复用这段信息。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: refreshBookmarkStatus() / reloadBoardList()
// 功能说明: 修改前 refresh/reload 只保留原始 timing 日志，无法观测双 refresh 或 target-ready 期间的 reloadData。
private func refreshBookmarkStatus() {
    logRenameTrace("refreshBookmarkStatusBegin")
    let refreshStart = BoardListCanvasTransitionDebugLogger.now()
    logClosingTransitionTiming(phase: "refreshBookmarkStatusBegin")
    dismissActionPanel()
    let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
    // ... 省略与本次修改无关的 catalog/load 逻辑 ...
}

private func reloadBoardList() {
    logRenameTrace("reloadBoardListBegin", extra: "entryCount=\(entries.count)")
    let reloadStart = BoardListCanvasTransitionDebugLogger.now()
    logClosingTransitionTiming(
        phase: "reloadBoardListBegin",
        extra: "entryCount=\(entries.count)"
    )
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
    revealPendingBoardIfNeeded()
    focusTitleEditorIfNeeded()
    logClosingTransitionTiming(
        phase: "reloadBoardListEnd",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - reloadStart,
        extra: "entryCount=\(entries.count)"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: finishPendingTransitionTargetResolution(for:geometry:) / finishPendingTransitionTargetResolution(_:) / revealBoard(at:boardID:)
// 功能说明: 修改前 target-ready 收口点不会输出统一护栏摘要，reveal 排队时长也没有写回 timing state。
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
let completion = pendingTransitionTargetResolution?.completion
pendingTransitionTargetResolution = nil
closingTransitionTimingState = nil

let revealStart = BoardListCanvasTransitionDebugLogger.now()
let dispatchDelay = closingTransitionTimingState?.revealDispatchEnqueuedAt.map {
    revealStart - $0
}
logClosingTransitionTiming(
    phase: "revealBoardBegin",
    localDuration: dispatchDelay,
    extra:
        "boardID=\(boardID.uuidString) " +
        "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
)
```

### 修改后

- `refreshBookmarkStatus()`：
  - 在 closing trace 存在时累加 `refreshInvocationCount`
  - 第二次及以上调用会额外打出 `guardDoubleRefreshDetected`
- `reloadBoardList()`：
  - 每次调用都累加 `reloadInvocationCount`
  - 若调用发生在 `pendingTransitionTargetResolution != nil` 或 `previewWorkPolicy == .geometryOnly` 期间，则额外累加 `reloadDuringTargetResolutionCount`
  - 输出 `guardReloadDataObserved`
  - target-ready 期间额外输出 `guardTargetReadyReloadDataDetected`
- `revealBoard(...)`：
  - 把 `dispatchDelay` 写回 `state.revealDispatchDelay`
- 两个 `finishPendingTransitionTargetResolution(...)`：
  - 都会在清理 state 前调用 `logClosingGuardSummary(...)`
  - 确保 summary 不会因为后续 `closingTransitionTimingState = nil` 而丢失

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: refreshBookmarkStatus() / reloadBoardList()
// 功能说明: 修改后 refresh/reload 会持续累加护栏统计，并在重复 refresh 或 target-ready 内 reloadData 时直接输出警示日志。
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
    // ... 省略与本次修改无关的 catalog/load 逻辑 ...
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
    // ... 省略其余 UI 更新逻辑 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: finishPendingTransitionTargetResolution(for:geometry:) / finishPendingTransitionTargetResolution(_:) / revealBoard(at:boardID:)
// 功能说明: 修改后 reveal 排队时长会回写 state，target-ready 收口点会在清理状态前输出 closingTargetReadySummary。
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
```

## 修改四：为 Preview trace policy 增加“是否会读源图”的显式护栏输出

### 修改前

- `metadataOnly` 下的 cache-hit 元数据日志不会明确说明“本次没有做 image region sampling / source image read”。
- `verbose` 下真正进入 `logBoardPreviewProviderSourceImagesIfNeeded(...)` 时，也没有单独的 guard 日志提醒“接下来会读源图”。
- 结果是：即便 Phase 5 已经把默认策略收敛为 `metadataOnly`，后续分析日志时仍不容易一眼分辨“当前 trace 是否会放大 IO 成本”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderCacheHitMetadata(...) / logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改前 metadata-only 日志没有显式声明 sourceImageReads=false，verbose 路径开始读源图前也没有 guard 提示。
private func logBoardPreviewProviderCacheHitMetadata(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    tracePolicy: BoardPreviewTracePolicy
) {
    print(
        "[BoardList][ThumbnailTrace][CacheHit] " +
            "phase=\(phase) " +
            "boardID=\(item.boardID.uuidString) " +
            "tracePolicy=\(tracePolicy.rawValue) " +
            "targetPixelSize=\(describeBoardPreviewProviderSize(targetPixelSize)) " +
            "cachedPixels={\(cachedImage.width), \(cachedImage.height)} " +
            "imageItemCount=\(item.document.imageItemRecords.count) " +
            "textItemCount=\(item.document.textItemRecords.count)"
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    tracePolicy: BoardPreviewTracePolicy,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    guard tracePolicy == .verbose else {
        return
    }

    let imageItemRecords = item.document.imageItemRecords
    // ... 省略后续源图读取逻辑 ...
}
```

### 修改后

- `metadataOnly` 的 cache-hit 日志现在会显式输出：
  - `imageRegionSampling=false`
  - `sourceImageReads=false`
- `logBoardPreviewProviderSourceImagesIfNeeded(...)` 在 `tracePolicy == .verbose` 且真正准备走 source-image 诊断前，先输出：
  - `[BoardList][ThumbnailTrace][Guard]`
  - `tracePolicy=verbose`
  - `sourceImageReads=true`
- 这样后续即使只是看日志，也能明确区分：
  - 当前 trace 是否只做轻量元数据观测
  - 当前 trace 是否已经进入会改变 IO 成本模型的 verbose 诊断

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/符号名: logBoardPreviewProviderCacheHitMetadata(...) / logBoardPreviewProviderSourceImagesIfNeeded(...)
// 功能说明: 修改后 metadata-only 与 verbose 两种 trace 成本模型都能从日志里直接读出来。
private func logBoardPreviewProviderCacheHitMetadata(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    tracePolicy: BoardPreviewTracePolicy
) {
    print(
        "[BoardList][ThumbnailTrace][CacheHit] " +
            "phase=\(phase) " +
            "boardID=\(item.boardID.uuidString) " +
            "tracePolicy=\(tracePolicy.rawValue) " +
            "targetPixelSize=\(describeBoardPreviewProviderSize(targetPixelSize)) " +
            "cachedPixels={\(cachedImage.width), \(cachedImage.height)} " +
            "imageRegionSampling=false " +
            "sourceImageReads=false " +
            "imageItemCount=\(item.document.imageItemRecords.count) " +
            "textItemCount=\(item.document.textItemRecords.count)"
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    tracePolicy: BoardPreviewTracePolicy,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    userDefaults: UserDefaults,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    guard tracePolicy == .verbose else {
        return
    }

    print(
        "[BoardList][ThumbnailTrace][Guard] " +
            "phase=\(phase) " +
            "boardID=\(item.boardID.uuidString) " +
            "tracePolicy=\(tracePolicy.rawValue) " +
            "sourceImageReads=true"
    )

    let imageItemRecords = item.document.imageItemRecords
    // ... 省略后续源图读取逻辑 ...
}
```

## 本轮结果

- `AppRoot` 已经能直接输出 closing 回归摘要指标：
  - `backButtonToCarrierAnimate`
  - `requestTargetGeometryToResolved`
  - `animationDuration`
- `BoardList` 已经能在 target-ready 收口前输出 `closingTargetReadySummary`，并在异常路径出现时输出：
  - `guardDoubleRefreshDetected`
  - `guardReloadDataObserved`
  - `guardTargetReadyReloadDataDetected`
- `BoardPreviewProvider` 已经能在日志中显式区分：
  - `metadata-only` 不做额外 image sampling / source-image read
  - `verbose` 将触发 source-image 读取

## 校验情况

- 本轮工作树变更文件与本记录一致：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 已对上述 4 个文件执行 lint 检查，结果为无 lint 错误。
- 本轮未执行完整 iOS 运行时回归；`Phase 6` 的最终验收仍需要人工重新抓一轮 closing trace，重点确认：
  - `carrierAnimateBegin` 是否继续前移
  - `requestTargetGeometryToResolved` 是否维持在“单板读取 + reveal”级别
  - happy path 下是否不再出现 `guardDoubleRefreshDetected`
  - happy path 下是否不再出现 `guardTargetReadyReloadDataDetected`

## 备注

- 本记录只如实描述本轮已经落地的代码改动，不把 `Phase 6` 之后可能继续演进的异步一致性刷新或更深层 mutation sink 重构混入本次记录。
