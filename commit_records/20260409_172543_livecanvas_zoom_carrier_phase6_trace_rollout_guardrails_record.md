# 20260409_172543_livecanvas_zoom_carrier_phase6_trace_rollout_guardrails_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 6` 的实施记录。
- 记录目标：在不直接改动 `BoardListCanvasOpenRequest` / `BoardListCanvasReturnRequest` 默认值的前提下，把 iOS request 层的 live rollout、opening/closing 统一 trace、carrier 选择日志、live reparent / handoff / restore 护栏补齐。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_172543`
  - 当前工作树 `git status --short -- <Phase 6 相关文件>`
  - 当前工作树 `git diff -- <Phase 6 相关文件>`
  - 修改后的源码内容
  - `ReadLints` 校验结果
  - `xcodebuild` 编译结果
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 本记录不包含：
  - 把 `BoardListCanvasOpenRequest` / `BoardListCanvasReturnRequest` 默认值直接切成 `.liveCanvas`
  - 手动视觉回归或性能回归结果
  - git commit

## 问题背景

- `Phase 5` 已经把 live carrier 的几何语义收敛成“`focusRect` 优先、`cardRect` 兜底”，opening / closing 主路径也都能跑通。
- 但 `Phase 5` 结束时仍缺三层 guardrail：
  - rollout 仍然是 request 构造处硬编码 `.liveCanvas`，还没有抽成可以灰度切换的统一入口。
  - closing 侧已有 trace，但 opening 侧还没有形成同级别的 request -> AppRoot -> carrier 全链路可观测性。
  - live carrier 内部虽然已有 `print` 事件，但还没有接入 `BoardListCanvasTransitionDebugTrace`，无法在统一 trace ID 下看到 `reparent`、`handoff`、`restore`、`fallback` 的细节。
- `Phase 6` 目标就是把这三层补齐：
  - request 构造层加 rollout override
  - opening / closing 都带 `debugTrace`
  - AppRoot 与 live carrier 都接入统一 `BoardListCanvasTransitionDebugLogger`
  - cancel / fallback / handoff 都记录 restore outcome

## 修改一：共享状态层新增 rollout override 与 opening `debugTrace`

### 修改前

- `BoardListCanvasOpenRequest` 只有：
  - `launchContext`
  - `source`
  - `preferredCarrierKind`
- 也就是说 opening request 没有 `debugTrace` 字段，opening 端无法像 closing 那样把 trace ID 从点击一路传到 AppRoot 和 carrier。
- 同时共享状态层也没有 rollout 抽象；如果 iOS 想灰度切换 live / snapshot，只能在各个 request 构造点里各自硬编码。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift
// 函数名/符号名: BoardListCanvasOpenRequest / existingBoard(...) / newBoardPlaceholder(...)
// 功能说明: 修改前 opening request 只有 preferredCarrierKind，没有 debugTrace；共享状态层也没有 request 级 rollout 入口。
struct BoardListCanvasOpenRequest: Hashable, Sendable {
    var launchContext: CanvasLaunchContext
    var source: BoardListCanvasOpenSource
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind

    static func existingBoard(
        boardID: UUID,
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .existing(boardID: boardID),
            source: BoardListCanvasOpenSource(
                kind: .existingBoardCard,
                entryID: .board(boardID),
                boardID: boardID,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind
        )
    }

    static func newBoardPlaceholder(
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .newBoard,
            source: BoardListCanvasOpenSource(
                kind: .newBoardPlaceholder,
                entryID: .newBoard,
                boardID: nil,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind
        )
    }
}
```

### 修改后

- 新增 `BoardListCanvasTransitionRollout`：
  - 默认值仍然保留在 request 工厂的参数签名里
  - 但 iOS request 构造现在统一从 `BoardListCanvasTransitionRollout.iOSRequestPreferredCarrierKind` 读取当前 override
- `BoardListCanvasOpenRequest` 新增 `debugTrace`
- `existingBoard(...)` / `newBoardPlaceholder(...)` 都支持把 trace 从 BoardList 点击一路带到 AppRoot 和 carrier
- 这满足了 `Phase 6` 的“先在 request 构造处做灰度，再决定未来是否切默认值”的要求。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift
// 函数名/符号名: BoardListCanvasTransitionRollout / BoardListCanvasOpenRequest
// 功能说明: 修改后共享状态层提供 request 级 rollout override；opening request 也能携带 debugTrace，和 closing 走统一 trace 体系。
enum BoardListCanvasTransitionRollout {
    static let liveCanvasRequestOverrideEnabled = true

    static var iOSRequestPreferredCarrierKind: BoardListCanvasTransitionCarrierKind {
        liveCanvasRequestOverrideEnabled ? .liveCanvas : .snapshotShell
    }
}

struct BoardListCanvasOpenRequest: Hashable, Sendable {
    var launchContext: CanvasLaunchContext
    var source: BoardListCanvasOpenSource
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind
    var debugTrace: BoardListCanvasTransitionDebugTrace?

    static func existingBoard(
        boardID: UUID,
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .existing(boardID: boardID),
            source: BoardListCanvasOpenSource(
                kind: .existingBoardCard,
                entryID: .board(boardID),
                boardID: boardID,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    }

    static func newBoardPlaceholder(
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .newBoard,
            source: BoardListCanvasOpenSource(
                kind: .newBoardPlaceholder,
                entryID: .newBoard,
                boardID: nil,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    }
}
```

## 修改二：iOS opening / closing request 构造统一接入 rollout 与 trace

### 修改前

- `iOSBoardListViewController.performPrimaryAction(for:)` 直接 `onOpenCanvas?(makeOpenRequest(for: entry))`，opening 点击侧没有专门 trace。
- `iOSBoardListViewController.makeOpenRequest(for:)` 里硬编码 `preferredCarrierKind: .liveCanvas`。
- `iOSViewController.makeReturnToBoardListRequest(...)` 也同样硬编码 `.liveCanvas`。
- closing trace 里 `returnRequestBuilt` 也没有打印 `preferredCarrierKind`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: performPrimaryAction(for:) / makeOpenRequest(for:)
// 功能说明: 修改前 opening 点击侧没有 transition debug trace，request 也直接硬编码为 .liveCanvas。
private func performPrimaryAction(for entry: BoardListEntry) {
    // ... guard ...
    onOpenCanvas?(makeOpenRequest(for: entry))
}

private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    let sourceGeometry = transitionSourceGeometry(for: entry.id)
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder(
            geometry: sourceGeometry,
            preferredCarrierKind: .liveCanvas
        )
    case let .board(item):
        return .existingBoard(
            boardID: item.boardID,
            geometry: sourceGeometry,
            preferredCarrierKind: .liveCanvas
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makeReturnToBoardListRequest(debugTrace:) / requestReturnToBoardList(trace:)
// 功能说明: 修改前 closing request 仍然硬编码 .liveCanvas，并且 returnRequestBuilt 日志不记录 preferredCarrierKind。
private func makeReturnToBoardListRequest(
    debugTrace: BoardListCanvasTransitionDebugTrace? = nil
) -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext,
        preferredCarrierKind: .liveCanvas,
        debugTrace: debugTrace
    )
}

private func requestReturnToBoardList(
    trace: BoardListCanvasTransitionDebugTrace
) {
    let request = makeReturnToBoardListRequest(debugTrace: trace)
    logClosingTransitionTrace(
        trace,
        phase: "returnRequestBuilt",
        extra:
            "boardID=\(request.boardID?.uuidString ?? "nil") " +
            "requiresPersistence=\(request.requiresBoardPersistence)"
    )
    // ...
}
```

### 修改后

- opening 点击侧新增 `BoardListCanvasTransitionDebugTrace()`，并串起：
  - `primaryActionTap`
  - `openRequestBuilt`
  - `emitOpenRequest`
- `makeOpenRequest(...)` / `makeReturnToBoardListRequest(...)` 都统一从 `BoardListCanvasTransitionRollout.iOSRequestPreferredCarrierKind` 读取当前请求级 carrier。
- closing trace 的 `returnRequestBuilt` 现在会打印 `preferredCarrierKind`，opening / closing 两边都能从日志里直接看出这次请求到底是 live 还是 snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: logOpeningTransitionTrace(_:phase:localDuration:extra:) / performPrimaryAction(for:) / makeOpenRequest(for:debugTrace:)
// 功能说明: 修改后 opening 点击侧会生成独立 debug trace，并把 rollout 决定出的 preferredCarrierKind 与 source geometry 一起记录到 request 日志里。
private func logOpeningTransitionTrace(
    _ trace: BoardListCanvasTransitionDebugTrace,
    phase: String,
    localDuration: TimeInterval? = nil,
    extra: String = ""
) {
    BoardListCanvasTransitionDebugLogger.log(
        platform: "iOS",
        component: "BoardList",
        trace: trace,
        phase: phase,
        localDuration: localDuration,
        extra: extra
    )
}

private func performPrimaryAction(for entry: BoardListEntry) {
    // ... guard ...
    let trace = BoardListCanvasTransitionDebugTrace()
    logOpeningTransitionTrace(
        trace,
        phase: "primaryActionTap",
        extra:
            "entryID=\(describeRenameTraceEntryID(entry.id)) " +
            "isPlaceholder=\(entry.isPlaceholder)"
    )
    let request = makeOpenRequest(for: entry, debugTrace: trace)
    logOpeningTransitionTrace(
        trace,
        phase: "openRequestBuilt",
        extra:
            "entryID=\(describeRenameTraceEntryID(entry.id)) " +
            "preferredCarrierKind=\(String(describing: request.preferredCarrierKind)) " +
            "hasCardRect=\(request.source.geometry.cardRect != nil) " +
            "hasFocusRect=\(request.source.geometry.focusRect != nil)"
    )
    logOpeningTransitionTrace(
        trace,
        phase: "emitOpenRequest",
        extra:
            "entryID=\(describeRenameTraceEntryID(entry.id)) " +
            "preferredCarrierKind=\(String(describing: request.preferredCarrierKind))"
    )
    onOpenCanvas?(request)
}

private func makeOpenRequest(
    for entry: BoardListEntry,
    debugTrace: BoardListCanvasTransitionDebugTrace? = nil
) -> BoardListCanvasOpenRequest {
    let sourceGeometry = transitionSourceGeometry(for: entry.id)
    let preferredCarrierKind = BoardListCanvasTransitionRollout
        .iOSRequestPreferredCarrierKind
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder(
            geometry: sourceGeometry,
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    case let .board(item):
        return .existingBoard(
            boardID: item.boardID,
            geometry: sourceGeometry,
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makeReturnToBoardListRequest(debugTrace:) / requestReturnToBoardList(trace:)
// 功能说明: 修改后 closing request 和 opening 一样走 rollout override；returnRequestBuilt 也显式打印 preferredCarrierKind。
private func makeReturnToBoardListRequest(
    debugTrace: BoardListCanvasTransitionDebugTrace? = nil
) -> BoardListCanvasReturnRequest {
    let preferredCarrierKind = BoardListCanvasTransitionRollout
        .iOSRequestPreferredCarrierKind
    return .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext,
        preferredCarrierKind: preferredCarrierKind,
        debugTrace: debugTrace
    )
}

private func requestReturnToBoardList(
    trace: BoardListCanvasTransitionDebugTrace
) {
    let request = makeReturnToBoardListRequest(debugTrace: trace)
    logClosingTransitionTrace(
        trace,
        phase: "returnRequestBuilt",
        extra:
            "boardID=\(request.boardID?.uuidString ?? "nil") " +
            "preferredCarrierKind=\(String(describing: request.preferredCarrierKind)) " +
            "requiresPersistence=\(request.requiresBoardPersistence)"
    )
    // ...
}
```

## 修改三：`iOSBoardListCanvasTransitionSession` 补 opening 动画时序字段

### 修改前

- session 里只有 closing 相关时间点：
  - `closingTargetGeometryRequestedAt`
  - `closingTargetGeometryResolvedAt`
  - `closingAnimationStartedAt`
- opening 没有对应字段，因此 AppRoot 只能知道“进入 opening transition”，但不能在 `completeOpeningTransition(...)` 时统计 opening 动画耗时。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionSession
// 功能说明: 修改前 session 只追踪 closing 动画时间点，没有 openingAnimationStartedAt。
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

### 修改后

- session 新增 `openingAnimationStartedAt`
- 这样 AppRoot opening 侧也可以在：
  - `carrierAnimateBegin`
  - `completeOpeningTransition`
 之间计算动画耗时，并用统一 trace 打出来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionSession
// 功能说明: 修改后 session 会记录 openingAnimationStartedAt，供 AppRoot 在 opening 完成时输出动画耗时。
final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?
    let debugTrace: BoardListCanvasTransitionDebugTrace?
    var openingAnimationStartedAt: TimeInterval?
    var closingTargetGeometryRequestedAt: TimeInterval?
    var closingTargetGeometryResolvedAt: TimeInterval?
    var closingAnimationStartedAt: TimeInterval?
}
```

## 修改四：`iOSAppRootViewController` 补齐 opening trace、carrier 选择日志与 requirements 护栏

### 修改前

- AppRoot 侧原来主要只有 closing trace：
  - `handleCanvasReturnRequest`
  - `beginClosingTransition`
  - `carrierPrepareFinished`
  - `requestTargetGeometry`
  - `targetGeometryResolved`
  - `carrierAnimateBegin`
  - `completeClosingTransition`
- opening 侧没有对应链路。
- carrier factory 也只接 `preferredKind + liveCanvasRequirements`，不会把 trace 传给 carrier。
- requirements 解析失败时虽然有 `print("[BoardListCanvasTransition][iOS][AppRoot] phase=liveCanvasCarrierFallback ...")`，但不会进入统一 debug trace。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / resolveLiveCanvasCarrierRequirements(from:preferredKind:transitionPhase:providerRole:)
// 功能说明: 修改前 opening 缺少统一 trace，carrier 选择结果也不会进入 debug trace；requirements fallback 只有 print，没有 trace 节点。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    let liveCanvasRequirements = resolveLiveCanvasCarrierRequirements(
        from: destinationViewController,
        preferredKind: request.preferredCarrierKind,
        transitionPhase: "opening",
        providerRole: "destination"
    )
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind,
        liveCanvasRequirements: liveCanvasRequirements
    )
    // ... 直接 prepare / animate，没有 opening trace ...
}

private func resolveLiveCanvasCarrierRequirements(
    from viewController: UIViewController?,
    preferredKind: BoardListCanvasTransitionCarrierKind,
    transitionPhase: String,
    providerRole: String
) -> iOSLiveCanvasCarrierRequirements? {
    guard let viewController else {
        logLiveCanvasCarrierFallbackIfNeeded(
            preferredKind: preferredKind,
            transitionPhase: transitionPhase,
            reason: "\(providerRole)ViewControllerMissing"
        )
        return nil
    }

    guard let provider = viewController as? CanvasTransitionLiveContentProviding else {
        logLiveCanvasCarrierFallbackIfNeeded(
            preferredKind: preferredKind,
            transitionPhase: transitionPhase,
            reason: "\(providerRole)ProviderMissing"
        )
        return nil
    }

    return iOSLiveCanvasCarrierRequirements(
        canvasViewProvider: { [weak provider] in
            provider?.transitionCanvasViewportView
        },
        canvasContainerViewProvider: { [weak provider] in
            provider?.transitionCanvasHostView
        },
        isTransitionChromeHidden: { [weak provider] in
            provider?.isTransitionChromeHidden ?? false
        },
        setTransitionChromeHidden: { [weak provider] isHidden in
            provider?.setTransitionChromeHidden(isHidden)
        }
    )
}
```

### 修改后

- opening 现在也有完整 AppRoot trace：
  - `handleCanvasOpenRequest`
  - `beginOpeningTransition`
  - `carrierPrepareFinished`
  - `carrierAnimateBegin`
  - `completeOpeningTransition`
- `resolveLiveCanvasCarrierRequirements(...)` 现在接收 `debugTrace`，并在 requirements 就绪时输出 `liveRequirementsReady`
- requirements fallback 现在除了原有 `print`，还会统一打 `liveFallbackTriggered`
- carrier factory 也接入 `debugTrace`
- 新增 `logCarrierSelectionTraceIfNeeded(...)`，会统一记录：
  - `requestedKind`
  - `resolvedKind`
  - `hasLiveCanvasRequirements`
- `discardActiveTransitionIfNeeded()` 也会输出 `discardActiveTransition`，确保中断链路在 trace 中可见。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleCanvasOpenRequest(_:) / beginOpeningTransition(with:) / completeOpeningTransition(sessionID:)
// 功能说明: 修改后 opening 和 closing 一样拥有 AppRoot 级 trace；carrier prepare/animate/complete 都会带统一 trace ID 输出。
private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    if let trace = request.debugTrace {
        logOpeningTransitionTrace(
            trace,
            phase: "handleCanvasOpenRequest",
            extra:
                "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil") " +
                "preferredCarrierKind=\(describeCarrierKind(request.preferredCarrierKind))"
        )
    }
    beginOpeningTransition(with: request)
}

private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    if let trace = request.debugTrace {
        logOpeningTransitionTrace(
            trace,
            phase: "beginOpeningTransition",
            extra:
                "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil") " +
                "preferredCarrierKind=\(describeCarrierKind(request.preferredCarrierKind))"
        )
    }

    let liveCanvasRequirements = resolveLiveCanvasCarrierRequirements(
        from: destinationViewController,
        preferredKind: request.preferredCarrierKind,
        transitionPhase: "opening",
        providerRole: "destination",
        debugTrace: request.debugTrace
    )
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind,
        liveCanvasRequirements: liveCanvasRequirements,
        debugTrace: request.debugTrace
    )
    logCarrierSelectionTraceIfNeeded(
        request.debugTrace,
        transitionPhase: "opening",
        requestedKind: request.preferredCarrierKind,
        resolvedKind: carrier.kind,
        hasLiveCanvasRequirements: liveCanvasRequirements != nil
    )
    let session = iOSBoardListCanvasTransitionSession(
        context: request.transitionContext,
        carrier: carrier,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController,
        debugTrace: request.debugTrace
    )

    let carrierPreparationStart = BoardListCanvasTransitionDebugLogger.now()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    if let trace = session.debugTrace {
        logOpeningTransitionTrace(
            trace,
            phase: "carrierPrepareFinished",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - carrierPreparationStart,
            extra: "carrierKind=\(describeCarrierKind(carrier.kind))"
        )
    }
    session.openingAnimationStartedAt = BoardListCanvasTransitionDebugLogger.now()
    if let trace = session.debugTrace {
        logOpeningTransitionTrace(
            trace,
            phase: "carrierAnimateBegin",
            extra: "carrierKind=\(describeCarrierKind(carrier.kind))"
        )
    }
    carrier.animateTransition { [weak self] in
        self?.completeOpeningTransition(sessionID: session.id)
    }
}

private func completeOpeningTransition(sessionID: UUID) {
    // ...
    session.carrier.completeTransition()
    if let trace = session.debugTrace {
        let animationDuration = session.openingAnimationStartedAt.map {
            BoardListCanvasTransitionDebugLogger.now() - $0
        }
        let animationDurationSummary = animationDuration.map {
            BoardListCanvasTransitionDebugLogger.durationString($0)
        } ?? "nil"
        logOpeningTransitionTrace(
            trace,
            phase: "completeOpeningTransition",
            localDuration: animationDuration,
            extra:
                "carrierKind=\(describeCarrierKind(session.carrier.kind)) " +
                "animationDuration=\(animationDurationSummary)"
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: resolveLiveCanvasCarrierRequirements(from:preferredKind:transitionPhase:providerRole:debugTrace:) / logCarrierSelectionTraceIfNeeded(...) / discardActiveTransitionIfNeeded()
// 功能说明: 修改后 AppRoot 会把 requirements 就绪、requirements fallback、carrier 最终选择结果和中断销毁都纳入统一 transition debug trace。
private func resolveLiveCanvasCarrierRequirements(
    from viewController: UIViewController?,
    preferredKind: BoardListCanvasTransitionCarrierKind,
    transitionPhase: String,
    providerRole: String,
    debugTrace: BoardListCanvasTransitionDebugTrace?
) -> iOSLiveCanvasCarrierRequirements? {
    guard let viewController else {
        logLiveCanvasCarrierFallbackIfNeeded(
            preferredKind: preferredKind,
            transitionPhase: transitionPhase,
            reason: "\(providerRole)ViewControllerMissing",
            debugTrace: debugTrace
        )
        return nil
    }

    guard let provider = viewController as? CanvasTransitionLiveContentProviding else {
        logLiveCanvasCarrierFallbackIfNeeded(
            preferredKind: preferredKind,
            transitionPhase: transitionPhase,
            reason: "\(providerRole)ProviderMissing",
            debugTrace: debugTrace
        )
        return nil
    }

    if preferredKind == .liveCanvas, let debugTrace {
        logTransitionTrace(
            debugTrace,
            phase: "liveRequirementsReady",
            extra:
                "transitionPhase=\(transitionPhase) " +
                "providerRole=\(providerRole)"
        )
    }

    return iOSLiveCanvasCarrierRequirements(
        canvasViewProvider: { [weak provider] in
            provider?.transitionCanvasViewportView
        },
        canvasContainerViewProvider: { [weak provider] in
            provider?.transitionCanvasHostView
        },
        isTransitionChromeHidden: { [weak provider] in
            provider?.isTransitionChromeHidden ?? false
        },
        setTransitionChromeHidden: { [weak provider] isHidden in
            provider?.setTransitionChromeHidden(isHidden)
        }
    )
}

private func logCarrierSelectionTraceIfNeeded(
    _ trace: BoardListCanvasTransitionDebugTrace?,
    transitionPhase: String,
    requestedKind: BoardListCanvasTransitionCarrierKind,
    resolvedKind: BoardListCanvasTransitionCarrierKind,
    hasLiveCanvasRequirements: Bool
) {
    guard let trace else {
        return
    }

    logTransitionTrace(
        trace,
        phase: "carrierSelected",
        extra:
            "transitionPhase=\(transitionPhase) " +
            "requestedKind=\(describeCarrierKind(requestedKind)) " +
            "resolvedKind=\(describeCarrierKind(resolvedKind)) " +
            "hasLiveCanvasRequirements=\(hasLiveCanvasRequirements)"
    )
}

private func discardActiveTransitionIfNeeded() {
    guard let session = activeTransitionSession else {
        return
    }

    if let trace = session.debugTrace {
        logTransitionTrace(
            trace,
            phase: "discardActiveTransition",
            extra:
                "transitionPhase=\(transitionPhase.rawValue) " +
                "carrierKind=\(describeCarrierKind(session.carrier.kind))"
        )
    }
    session.carrier.cancelTransition()
    // ...
}
```

## 修改五：`iOSLiveCanvasCarrier` 接入统一 trace，并量化 reparent / handoff / restore

### 修改前

- carrier factory 只把 `requirements` 传给 `iOSLiveCanvasCarrier`，不会传 trace。
- `iOSLiveCanvasCarrier` 自己只有 `print("[BoardListCanvasTransition][iOS][LiveCarrier] ...")` 形式的日志，不会进入 `BoardListCanvasTransitionDebugLogger`。
- `restoreLiveCanvasToHostIfNeeded()` 是 `Void`，只能“做事”，不能表达：
  - 真正 restored
  - 没有 mounted，无需 restore
  - 丢失 `liveCanvasView`
  - 丢失 `liveCanvasHostView`
- `cleanupLiveTransitionArtifacts(...)` 也只负责清理，不会输出 restore outcome。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...) / iOSLiveCanvasCarrier.restoreLiveCanvasToHostIfNeeded() / cleanupLiveTransitionArtifacts(...)
// 功能说明: 修改前 live carrier 没有接入统一 debug trace；restore 也没有结构化 outcome，无法量化取消/回退/交接时到底是否成功还回 host。
enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind,
        liveCanvasRequirements: iOSLiveCanvasCarrierRequirements? = nil
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            guard let liveCanvasRequirements else {
                return iOSSnapshotShellCarrier()
            }
            return iOSLiveCanvasCarrier(
                requirements: liveCanvasRequirements
            )
        }
    }
}

private func restoreLiveCanvasToHostIfNeeded() {
    guard
        isCanvasMountedInOverlay,
        let liveCanvasView,
        let liveCanvasHostView
    else {
        return
    }

    liveCanvasView.removeFromSuperview()
    liveCanvasView.translatesAutoresizingMaskIntoConstraints = false
    liveCanvasView.autoresizingMask = []
    liveCanvasHostView.addSubview(liveCanvasView)
    NSLayoutConstraint.activate([
        liveCanvasView.topAnchor.constraint(equalTo: liveCanvasHostView.topAnchor),
        liveCanvasView.leadingAnchor.constraint(equalTo: liveCanvasHostView.leadingAnchor),
        liveCanvasView.trailingAnchor.constraint(equalTo: liveCanvasHostView.trailingAnchor),
        liveCanvasView.bottomAnchor.constraint(equalTo: liveCanvasHostView.bottomAnchor)
    ])
    liveCanvasHostView.layoutIfNeeded()
    isCanvasMountedInOverlay = false
}
```

### 修改后

- carrier factory 增加 `debugTrace` 注入
- `iOSLiveCanvasCarrier` 新增：
  - `debugTrace`
  - `LiveCanvasRestoreOutcome`
  - `logLiveCarrierTrace(...)`
  - `logLiveRestoreFinished(...)`
- `restoreLiveCanvasToHostIfNeeded()` 现在会返回结构化 outcome
- `cleanupLiveTransitionArtifacts(...)` 增加：
  - `restoreTransitionPhase`
  - `restoreTrigger`
  用来把 cancel / fallback / 其他清理链上的 restore 结果统一打点
- 这样“取消/异常路径不会把 canvas 留在 overlay”的要求，终于可以通过 trace 明确观察。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...) / LiveCanvasRestoreOutcome / logLiveCarrierTrace(...) / logLiveRestoreFinished(...)
// 功能说明: 修改后 live carrier 能拿到统一 debugTrace，并把 fallback、restore、reparent、handoff 等内部细节写入统一 transition trace。
enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind,
        liveCanvasRequirements: iOSLiveCanvasCarrierRequirements? = nil,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            guard let liveCanvasRequirements else {
                return iOSSnapshotShellCarrier()
            }
            return iOSLiveCanvasCarrier(
                requirements: liveCanvasRequirements,
                debugTrace: debugTrace
            )
        }
    }
}

private enum LiveCanvasRestoreOutcome: String {
    case restored
    case skippedNotMounted
    case failedMissingCanvasView
    case failedMissingHostView
    case notRequired
}

private let debugTrace: BoardListCanvasTransitionDebugTrace?

private func logLiveCarrierTrace(
    phase: String,
    localDuration: TimeInterval? = nil,
    extra: String = ""
) {
    guard let debugTrace else {
        return
    }

    BoardListCanvasTransitionDebugLogger.log(
        platform: "iOS",
        component: "LiveCarrier",
        trace: debugTrace,
        phase: phase,
        localDuration: localDuration,
        extra: extra
    )
}

private func logLiveRestoreFinished(
    transitionPhase: String,
    trigger: String,
    outcome: LiveCanvasRestoreOutcome,
    localDuration: TimeInterval?
) {
    logLiveCarrierTrace(
        phase: "liveRestoreFinished",
        localDuration: localDuration,
        extra:
            "transitionPhase=\(transitionPhase) " +
            "trigger=\(trigger) " +
            "outcome=\(outcome.rawValue)"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: restoreLiveCanvasToHostIfNeeded() / cleanupLiveTransitionArtifacts(...)
// 功能说明: 修改后 restore 会返回结构化结果；cleanup 可以把 cancel/fallback 的 restore 结果作为统一 trace 节点输出。
private func restoreLiveCanvasToHostIfNeeded() -> LiveCanvasRestoreOutcome {
    guard isCanvasMountedInOverlay else {
        return .skippedNotMounted
    }
    guard let liveCanvasView else {
        return .failedMissingCanvasView
    }
    guard let liveCanvasHostView else {
        return .failedMissingHostView
    }

    liveCanvasView.removeFromSuperview()
    liveCanvasView.translatesAutoresizingMaskIntoConstraints = false
    liveCanvasView.autoresizingMask = []
    liveCanvasHostView.addSubview(liveCanvasView)
    NSLayoutConstraint.activate([
        liveCanvasView.topAnchor.constraint(equalTo: liveCanvasHostView.topAnchor),
        liveCanvasView.leadingAnchor.constraint(equalTo: liveCanvasHostView.leadingAnchor),
        liveCanvasView.trailingAnchor.constraint(equalTo: liveCanvasHostView.trailingAnchor),
        liveCanvasView.bottomAnchor.constraint(equalTo: liveCanvasHostView.bottomAnchor)
    ])
    liveCanvasHostView.layoutIfNeeded()
    isCanvasMountedInOverlay = false
    return .restored
}

private func cleanupLiveTransitionArtifacts(
    restoreCanvasToHost: Bool,
    restoreChromeVisibility: Bool,
    removeLiveCanvasFromHierarchy: Bool,
    clearContext: Bool,
    restoreTransitionPhase: String?,
    restoreTrigger: String?
) {
    if restoreCanvasToHost {
        let restoreStart = BoardListCanvasTransitionDebugLogger.now()
        let restoreOutcome = restoreLiveCanvasToHostIfNeeded()
        if let restoreTransitionPhase, let restoreTrigger {
            logLiveRestoreFinished(
                transitionPhase: restoreTransitionPhase,
                trigger: restoreTrigger,
                outcome: restoreOutcome,
                localDuration: BoardListCanvasTransitionDebugLogger.now() - restoreStart
            )
        }
    } else if removeLiveCanvasFromHierarchy {
        liveCanvasView?.removeFromSuperview()
    }

    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    liveTargetRectSource = nil
    // ...
}
```

## 修改六：live reparent / prepare / zoom / handoff / fallback 现在都有统一 trace 节点

### 修改前

- opening / closing live 路径虽然会 `print`：
  - `openingPrepareFinished`
  - `closingPrepareFinished`
  - `openingHandoffFinished`
  - `closingHandoffFinished`
  - `openingLiveFallback`
  - `closingLiveFallback`
- 但这些都不在 `BoardListCanvasTransitionDebugTrace` 的同一个 trace ID 下，也没有局部耗时。
- 特别是：
  - reparent 用了多久
  - handoff 用了多久
  - restore 成功还是失败
  - fallback 是 AppRoot requirements 触发，还是 carrier 内部触发
 这些都没法和 closing timing / opening timing 一起看。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningLiveTransition(...) / prepareClosingLiveTransition(...) / logLiveCarrierFallback(phase:reason:)
// 功能说明: 修改前 live carrier 只会打印文本事件，无法在统一 debug trace 里量化 reparent、zoom、handoff、fallback 与 restore。
let reparentStart = BoardListCanvasTransitionDebugLogger.now()
attachLiveCanvasViewToContainer(
    liveCanvasView,
    containerView: liveContainerView
)
overlayHostView.addSubview(liveContainerView)
let reparentDuration = BoardListCanvasTransitionDebugLogger.now() - reparentStart

logLiveCarrierEvent(
    phase: "openingPrepareFinished",
    extra:
        "sourceRectSource=\(sourceRectResolution.source.rawValue) " +
        "sourceFrame=\(describe(rect: sourceFrame)) " +
        "targetFrame=\(describe(rect: targetFrame))"
)

private func logLiveCarrierFallback(
    phase: String,
    reason: String
) {
    print(
        "[BoardListCanvasTransition][iOS][LiveCarrier] " +
            "phase=\(phase) " +
            "reason=\(reason)"
    )
}
```

### 修改后

- opening / closing live 路径新增统一 trace：
  - `liveReparentFinished`
  - `livePrepareFinished`
  - `liveZoomBegin`
  - `liveHandoffFinished`
  - `liveFallbackTriggered`
  - `liveRestoreFinished`
- opening fallback 时会输出：
  - `openingLiveFallback`
  - `liveFallbackTriggered`
  - `liveRestoreFinished`
- closing fallback 时会输出：
  - `closingLiveFallback`
  - `liveFallbackTriggered`
  - `liveRestoreFinished`
- reparent、handoff、restore 都带 `localDuration`
- handoff / restore 还会标记 `transitionPhase`、`trigger`、`outcome`，方便直接判断“有没有把 canvas 留在 overlay 上”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningLiveTransition(...) / prepareClosingLiveTransition(...) / animateLiveOpeningTransition(completion:) / animateLiveClosingTransition(completion:)
// 功能说明: 修改后 live carrier 会把 reparent、prepare、zoom 开始等关键节点写入统一 trace，opening/closing 两条 live 路径都能量化耗时与锚点来源。
let reparentStart = BoardListCanvasTransitionDebugLogger.now()
attachLiveCanvasViewToContainer(
    liveCanvasView,
    containerView: liveContainerView
)
overlayHostView.addSubview(liveContainerView)
let reparentDuration = BoardListCanvasTransitionDebugLogger.now() - reparentStart

logLiveCarrierTrace(
    phase: "liveReparentFinished",
    localDuration: reparentDuration,
    extra:
        "transitionPhase=opening " +
        "sourceRectSource=\(sourceRectResolution.source.rawValue)"
)
logLiveCarrierTrace(
    phase: "livePrepareFinished",
    extra:
        "transitionPhase=opening " +
        "sourceRectSource=\(sourceRectResolution.source.rawValue)"
)

logLiveCarrierTrace(
    phase: "liveReparentFinished",
    localDuration: reparentDuration,
    extra:
        "transitionPhase=closing " +
        "targetRectSource=\(targetFrameResolution?.source.rawValue ?? "pending")"
)
logLiveCarrierTrace(
    phase: "livePrepareFinished",
    extra:
        "transitionPhase=closing " +
        "targetRectSource=\(targetFrameResolution?.source.rawValue ?? "pending")"
)

logLiveCarrierTrace(
    phase: "liveZoomBegin",
    extra:
        "transitionPhase=opening " +
        "targetFrame=\(describe(rect: liveTargetFrame))"
)

logLiveCarrierTrace(
    phase: "liveZoomBegin",
    extra:
        "transitionPhase=closing " +
        "targetRectSource=\(targetFrameResolution.source.rawValue) " +
        "targetFrame=\(describe(rect: targetFrameResolution.rect))"
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: performLiveOpeningHandoff(completion:) / performLiveClosingHandoff(completion:) / fallbackToSnapshotClosing(reason:completion:)
// 功能说明: 修改后 live handoff 与 snapshot fallback 都会记录 restore outcome 和 handoff/fallback 耗时，保证取消/中断路径和完成路径一样可观测。
private func performLiveOpeningHandoff(completion: @escaping () -> Void) {
    let handoffStart = BoardListCanvasTransitionDebugLogger.now()
    // ...
    let restoreStart = BoardListCanvasTransitionDebugLogger.now()
    let restoreOutcome = restoreLiveCanvasToHostIfNeeded()
    let restoreDuration = BoardListCanvasTransitionDebugLogger.now() - restoreStart
    logLiveRestoreFinished(
        transitionPhase: "opening",
        trigger: "openingHandoff",
        outcome: restoreOutcome,
        localDuration: restoreDuration
    )
    // ...
    restoreChromeVisibilityIfNeeded(animated: true) { [weak self] in
        self?.logLiveCarrierTrace(
            phase: "liveHandoffFinished",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - handoffStart,
            extra:
                "transitionPhase=opening " +
                "restoreOutcome=\(restoreOutcome.rawValue)"
        )
        completion()
    }
}

private func performLiveClosingHandoff(completion: @escaping () -> Void) {
    let handoffStart = BoardListCanvasTransitionDebugLogger.now()
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    liveTargetRectSource = nil
    isCanvasMountedInOverlay = false
    logLiveRestoreFinished(
        transitionPhase: "closing",
        trigger: "closingHandoff",
        outcome: .notRequired,
        localDuration: nil
    )
    logLiveCarrierTrace(
        phase: "liveHandoffFinished",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - handoffStart,
        extra: "transitionPhase=closing restoreOutcome=notRequired"
    )
    completion()
}

private func fallbackToSnapshotClosing(
    reason: String,
    completion: @escaping () -> Void
) {
    guard let context = currentContext else {
        completion()
        return
    }

    logLiveCarrierFallback(
        phase: "closingLiveFallback",
        reason: reason
    )
    cleanupLiveTransitionArtifacts(
        restoreCanvasToHost: true,
        restoreChromeVisibility: true,
        removeLiveCanvasFromHierarchy: false,
        clearContext: false,
        restoreTransitionPhase: "closing",
        restoreTrigger: "snapshotFallback"
    )
    prepareSnapshotFallback(
        with: context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    snapshotFallbackCarrier.animateTransition(completion: completion)
}
```

## 本轮结果

- iOS opening / closing request 都不再直接硬编码 `.liveCanvas`，而是统一走 `BoardListCanvasTransitionRollout.iOSRequestPreferredCarrierKind`。
- `BoardListCanvasOpenRequest` 现在也和 closing 一样支持 `debugTrace`，opening/closing 的 trace 粒度终于对齐。
- AppRoot 现在能明确输出：
  - `liveRequirementsReady`
  - `carrierSelected`
  - `discardActiveTransition`
  - opening `handleCanvasOpenRequest -> beginOpeningTransition -> carrierPrepareFinished -> carrierAnimateBegin -> completeOpeningTransition`
- live carrier 现在能明确输出：
  - `liveReparentFinished`
  - `livePrepareFinished`
  - `liveZoomBegin`
  - `liveHandoffFinished`
  - `liveFallbackTriggered`
  - `liveRestoreFinished`
- cancel / fallback / handoff 路径的 restore 结果现在是结构化可见的：
  - `restored`
  - `skippedNotMounted`
  - `failedMissingCanvasView`
  - `failedMissingHostView`
  - `notRequired`
- 这满足了 `Phase 6` 的核心目标：
  - rollout 可控
  - fallback 原因可见
  - restore 成功与否可见
  - opening / closing 都能在统一 trace ID 下回放

## 校验情况

- 当前工作树中，`Phase 6` 相关文件状态与本记录一致：
  - `MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 已对上述文件执行 `ReadLints`，结果为无 lint 错误。
- 已执行编译校验：
  - 命令：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
  - 结果：`BUILD SUCCEEDED`
- 本轮未执行手动视觉回归，也未执行真实设备上的 opening/closing trace 回放，所以“warm opening/closing 默认走 live 路径的运行时比例”和“fallback 率是否符合预期”仍需运行时验证。

## 备注

- 这份记录只覆盖 `Phase 6` 的 rollout、trace 与 guardrail 接线；没有把共享状态层的默认 carrier 值直接切成 `.liveCanvas`。
