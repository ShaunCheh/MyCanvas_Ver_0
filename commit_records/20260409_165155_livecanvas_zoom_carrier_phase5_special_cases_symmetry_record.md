# 20260409_165155_livecanvas_zoom_carrier_phase5_special_cases_symmetry_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 5` 的实施记录。
- 记录目标：补齐 placeholder、grid/list、`focusRect` 缺失时的 fallback 语义，并让 opening / closing 在 live carrier 上共享“`focusRect` 优先、`cardRect` 兜底”的一致模型。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_165155`
  - 当前工作树 `git status --short -- <Phase 5 相关文件>`
  - 当前工作树 `git diff -- <Phase 5 相关文件>`
  - 修改后的源码内容
  - `ReadLints` 校验结果
  - `xcodebuild` 编译结果
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 本记录不包含：
  - `Phase 4` 的 closing live carrier 主路径接线
  - `Phase 6` 的 trace / rollout / 默认切换
  - git commit

## 问题背景

- `Phase 4` 之后，iOS opening / closing 的 live carrier 主路径已经可以工作，但仍有两个语义缺口：
  - `iOSBoardCollectionViewCell.transitionFocusRect(...)` 仍然依赖 `previewView.isHidden` / `placeholderIconView.isHidden` 判断锚点来源，placeholder、list/grid 和重布局后的几何语义还不够正式。
  - `iOSLiveCanvasCarrier` 仍把 `focusRect` 当成 live 路径的硬前置条件；一旦 `focusRect` 临时缺失，即使 `cardRect` 仍然合法，也会直接放弃 live 路径。
- `Phase 5` 的目标就是把这层根因补齐：
  - BoardCell 明确给 board preview 与 placeholder icon 建立正式锚点语义。
  - BoardList 的 source / target 几何统一走归一化路径，而不是 visible cell 和 fallback 路径各自拼接。
  - Live carrier 统一消费 `preferredRect`，让“有 `focusRect` 用缩略图，没有时退 `cardRect`”成为 opening / closing 的共同契约。

## 修改一：`iOSBoardCollectionViewCell` 不再依赖 hidden 状态猜锚点

### 修改前

- `transitionGeometry(in:)` 直接取 `contentView.bounds` 作为 `cardRect`，没有显式做几何净化。
- `transitionFocusRect(in:)` 的判断方式是：
  - `previewView.isHidden == false` 时取 preview
  - `placeholderIconView.isHidden == false` 时取 placeholder icon
  - 否则返回 `nil`
- 这意味着锚点来源依赖视图隐藏状态，而不是依赖当前正式 presentation style；一旦遇到布局切换、placeholder 特殊呈现或局部视图状态不一致，`focusRect` 语义就不够稳。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: transitionGeometry(in:) / transitionFocusRect(in:)
// 功能说明: 修改前 cell 的 focusRect 依赖 previewView/placeholderIconView 的 hidden 状态来判断锚点来源，没有把当前 presentation style 作为正式几何语义。
func transitionGeometry(
    in coordinateSpaceView: UIView
) -> BoardListCanvasTransitionSourceGeometry {
    contentView.layoutIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        contentView.bounds,
        from: contentView
    )

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(in: coordinateSpaceView)
    )
}

private func transitionFocusRect(
    in coordinateSpaceView: UIView
) -> CGRect? {
    if previewView.isHidden == false {
        return coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    if placeholderIconView.isHidden == false {
        return coordinateSpaceView.convert(
            placeholderIconView.bounds,
            from: placeholderIconView
        )
    }

    return nil
}
```

### 修改后

- `cardRect` 先经过 `BoardListCanvasTransitionGeometry.sanitizedRect(...)` 净化。
- `transitionFocusRect(...)` 改成两层逻辑：
  - 先按 `currentPresentationStyle` 正式决定锚点视图，board 用 `previewView`，placeholder 用 `placeholderIconView`
  - 如果实际 anchor rect 暂时取不到，再回退到 `BoardListCanvasTransitionFocusRectResolver.focusRect(...)`
- 同时新增：
  - `transitionFocusAnchorRect(in:)`
  - `transitionDisplayMode`
  - `isPlaceholderPresentation`
- 这样 list / grid / placeholder 都不再依赖“某个 view 当前刚好 hidden / visible”，而是依赖当前 cell 真实 presentation style。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: transitionGeometry(in:) / transitionFocusRect(in:cardRect:) / transitionFocusAnchorRect(in:)
// 功能说明: 修改后 cell 会按当前 presentation style 正式解析转场锚点；拿不到实际锚点视图几何时，再回退到 shared focusRect resolver。
func transitionGeometry(
    in coordinateSpaceView: UIView
) -> BoardListCanvasTransitionSourceGeometry {
    contentView.layoutIfNeeded()
    let cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
        coordinateSpaceView.convert(
            contentView.bounds,
            from: contentView
        )
    )

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(
            in: coordinateSpaceView,
            cardRect: cardRect
        )
    )
}

private func transitionFocusRect(
    in coordinateSpaceView: UIView,
    cardRect: CGRect? = nil
) -> CGRect? {
    if let anchorRect = transitionFocusAnchorRect(in: coordinateSpaceView) {
        return anchorRect
    }

    return BoardListCanvasTransitionFocusRectResolver.focusRect(
        in: cardRect,
        displayMode: transitionDisplayMode,
        isPlaceholder: isPlaceholderPresentation
    )
}

private func transitionFocusAnchorRect(
    in coordinateSpaceView: UIView
) -> CGRect? {
    let anchorView: UIView
    switch currentPresentationStyle {
    case .boardGrid, .boardList:
        anchorView = previewView
    case .placeholderGrid, .placeholderList:
        anchorView = placeholderIconView
    }

    return BoardListCanvasTransitionGeometry.sanitizedRect(
        coordinateSpaceView.convert(
            anchorView.bounds,
            from: anchorView
        )
    )
}

private var transitionDisplayMode: BoardListDisplayMode {
    switch currentPresentationStyle {
    case .boardGrid, .placeholderGrid:
        return .grid
    case .boardList, .placeholderList:
        return .list
    }
}

private var isPlaceholderPresentation: Bool {
    switch currentPresentationStyle {
    case .boardGrid, .boardList:
        return false
    case .placeholderGrid, .placeholderList:
        return true
    }
}
```

## 修改二：`iOSBoardListViewController` 统一 source / target 几何归一化

### 修改前

- source 端分两条路：
  - visible cell 时直接返回 `cell.transitionGeometry(in:)`
  - cell 不可见时，自己重新拼 `cardRect + transitionFocusRect(...)`
- target 端也是分两条路：
  - visible cell 时直接把 `cellGeometry.cardRect / cellGeometry.focusRect` 填回去，并把 `usedFallbackGeometry = false`
  - cell 不可见时才走 fallback
- 这会导致一个语义问题：
  - 即使 visible cell 的 `focusRect` 实际是通过 fallback / resolver 算出来的，日志和 guardrail 仍然会把它当成“非 fallback 主路径”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(at:) / resolveTransitionTargetGeometry(for:)
// 功能说明: 修改前 source/target 几何在 visible cell 与 fallback 场景下分别走不同分支，usedFallbackGeometry 只看 cell 是否可见，不看 focusRect 是否其实已经退回 resolver。
private func transitionSourceGeometry(
    at indexPath: IndexPath
) -> BoardListCanvasTransitionSourceGeometry {
    collectionView.layoutIfNeeded()
    if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
        return cell.transitionGeometry(in: view)
    }

    let cardRect = transitionCardRect(at: indexPath)
    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(
            at: indexPath,
            cardRect: cardRect
        )
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
        let cellGeometry = cell.transitionGeometry(in: view)
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cellGeometry.cardRect,
            focusRect: cellGeometry.focusRect
        )
        usedFallbackGeometry = false
    } else {
        let cardRect = transitionCardRect(at: resolvedIndexPath)
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cardRect,
            focusRect: transitionFocusRect(
                at: resolvedIndexPath,
                cardRect: cardRect
            )
        )
        usedFallbackGeometry = true
    }

    return BoardListClosingTargetPreparationResult(
        boardID: boardID,
        resolvedIndexPath: resolvedIndexPath,
        geometry: geometry,
        usedFallbackGeometry: usedFallbackGeometry
    )
}
```

### 修改后

- 新增三层归一化辅助：
  - `normalizedTransitionSourceGeometry(...)`
  - `normalizedTransitionTargetGeometry(...)`
  - `normalizedTransitionFocusRect(...)`
- source 端现在无论 cell 是否可见，最终都收敛到一条统一几何归一化路径。
- target 端也统一归一化，并把 fallback 语义收紧为：
  - 只要本次 target geometry 没有直接带来显式 `focusRect`，就记为 `usedFallbackFocusRect = true`
  - 这样 visible cell 但 `focusRect` 其实依赖 resolver 的情况，也会如实落在 fallback 语义里
- 这让 closing target-ready 的日志与 guardrail 更接近真实情况。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(at:) / resolveTransitionTargetGeometry(for:) / normalizedTransitionTargetGeometry(at:cardRect:focusRect:)
// 功能说明: 修改后 BoardList source/target 几何统一经过归一化路径，visible cell、placeholder、list/grid 与 resolver fallback 共享同一套契约。
private func transitionSourceGeometry(
    at indexPath: IndexPath
) -> BoardListCanvasTransitionSourceGeometry {
    collectionView.layoutIfNeeded()
    if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
        let cellGeometry = cell.transitionGeometry(in: view)
        return normalizedTransitionSourceGeometry(
            at: indexPath,
            cardRect: cellGeometry.cardRect,
            focusRect: cellGeometry.focusRect
        )
    }

    return normalizedTransitionSourceGeometry(
        at: indexPath,
        cardRect: transitionCardRect(at: indexPath),
        focusRect: nil
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
        let cellGeometry = cell.transitionGeometry(in: view)
        let normalizedGeometry = normalizedTransitionTargetGeometry(
            at: resolvedIndexPath,
            cardRect: cellGeometry.cardRect,
            focusRect: cellGeometry.focusRect
        )
        geometry = normalizedGeometry.geometry
        usedFallbackGeometry = normalizedGeometry.usedFallbackFocusRect
    } else {
        let normalizedGeometry = normalizedTransitionTargetGeometry(
            at: resolvedIndexPath,
            cardRect: transitionCardRect(at: resolvedIndexPath),
            focusRect: nil
        )
        geometry = normalizedGeometry.geometry
        usedFallbackGeometry = true
    }

    return BoardListClosingTargetPreparationResult(
        boardID: boardID,
        resolvedIndexPath: resolvedIndexPath,
        geometry: geometry,
        usedFallbackGeometry: usedFallbackGeometry
    )
}

private func normalizedTransitionTargetGeometry(
    at indexPath: IndexPath,
    cardRect: CGRect?,
    focusRect: CGRect?
) -> (
    geometry: BoardListCanvasTransitionTargetGeometry,
    usedFallbackFocusRect: Bool
) {
    let sanitizedCardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
        cardRect
    )
    let explicitFocusRect = BoardListCanvasTransitionGeometry.sanitizedRect(
        focusRect
    )
    let resolvedFocusRect = normalizedTransitionFocusRect(
        at: indexPath,
        focusRect: explicitFocusRect,
        cardRect: sanitizedCardRect
    )
    return (
        BoardListCanvasTransitionTargetGeometry(
            cardRect: sanitizedCardRect,
            focusRect: resolvedFocusRect
        ),
        explicitFocusRect == nil
    )
}
```

## 修改三：`iOSLiveCanvasCarrier` 从“必须有 `focusRect`”改成消费 `preferredRect`

### 修改前

- `prepareOpeningLiveTransition(...)` 里，opening live 路径必须拿到 `context.sourceGeometry.focusRect`，否则直接 fallback。
- `resolveLiveClosingTargetFrame(using:)` 里，closing live 路径必须拿到 `context.targetGeometry.focusRect`，否则拿不到目标 frame。
- `animateLiveClosingTransition(...)` 里也把 “没有 `focusRect`” 当成专门的 fallback reason。
- 这和 `Phase 5` 要求不一致：计划要求的是 “只要有合法 `focusRect` 就用它，没有时退 `cardRect`”，而不是“没有 `focusRect` 就直接放弃 live”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningLiveTransition(with:sourceViewController:destinationViewController:) / resolveLiveClosingTargetFrame(using:)
// 功能说明: 修改前 live carrier 把 focusRect 当成硬前置条件；source/target 任何一端 focusRect 缺失都会阻断 live 主路径。
private func prepareOpeningLiveTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?,
    destinationViewController: UIViewController?
) -> Bool {
    guard let overlayHostView else { return false }
    guard let sourceViewController else { return false }
    guard let destinationViewController else { return false }
    guard let sourceFocusRect = context.sourceGeometry.focusRect else {
        logLiveCarrierFallback(
            phase: "openingLiveFallback",
            reason: "sourceFocusRectMissing"
        )
        return false
    }
    // ...
    let sourceFrame = overlayHostView.convert(
        sourceFocusRect,
        from: sourceViewController.view
    ).standardized
    // ...
}

private func resolveLiveClosingTargetFrame(
    using context: BoardListCanvasTransitionContext
) -> CGRect? {
    guard
        let overlayHostView,
        let destinationView = destinationViewController?.view,
        let targetFocusRect = context.targetGeometry.focusRect
    else {
        return nil
    }

    let convertedTargetRect = overlayHostView.convert(
        targetFocusRect,
        from: destinationView
    ).standardized
    guard convertedTargetRect.isEmpty == false else {
        return nil
    }

    return convertedTargetRect
}
```

### 修改后

- 新增：
  - `PreferredRectSource`
  - `PreferredRectResolution`
  - `preferredRectResolution(from:)` 的 source / target 两个重载
- opening 现在先解析 `context.sourceGeometry` 的 preferred rect：
  - 有 `focusRect` 用 `focusRect`
  - 没有则退到 `cardRect`
- closing 也同样把 `targetGeometry` 统一解成 preferred rect，并把来源记到日志里。
- 同时新增 `liveTargetRectSource` 状态，方便在 closing target-ready 更新后继续知道当前目标是对齐 `focusRect` 还是已经退化到 `cardRect`。
- fallback reason 也从 `targetFocusRectMissing` 升级为 `targetPreferredRectMissing`，与新的统一语义对齐。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: PreferredRectSource / preferredRectResolution(from:) / prepareOpeningLiveTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改后 live carrier 不再强依赖 focusRect，而是统一消费 preferredRect，让 opening/closing 在缺少 focusRect 时自动退到 cardRect。
private enum PreferredRectSource: String {
    case focusRect
    case cardRect
}

private struct PreferredRectResolution {
    let rect: CGRect
    let source: PreferredRectSource
}

private func preferredRectResolution(
    from geometry: BoardListCanvasTransitionSourceGeometry
) -> PreferredRectResolution? {
    if let focusRect = geometry.focusRect {
        return PreferredRectResolution(
            rect: focusRect,
            source: .focusRect
        )
    }
    if let cardRect = geometry.cardRect {
        return PreferredRectResolution(
            rect: cardRect,
            source: .cardRect
        )
    }
    return nil
}

private func prepareOpeningLiveTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?,
    destinationViewController: UIViewController?
) -> Bool {
    guard let overlayHostView else { return false }
    guard let sourceViewController else { return false }
    guard
        let sourceRectResolution = preferredRectResolution(
            from: context.sourceGeometry
        )
    else {
        logLiveCarrierFallback(
            phase: "openingLiveFallback",
            reason: "sourcePreferredRectMissing"
        )
        return false
    }
    guard let destinationViewController else { return false }

    let sourceFrame = overlayHostView.convert(
        sourceRectResolution.rect,
        from: sourceViewController.view
    ).standardized
    // ...

    logLiveCarrierEvent(
        phase: "openingPrepareFinished",
        extra:
            "sourceRectSource=\(sourceRectResolution.source.rawValue) " +
            "sourceFrame=\(describe(rect: sourceFrame)) " +
            "targetFrame=\(describe(rect: targetFrame))"
    )
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: updateTransitionContext(_:) / resolveLiveClosingTargetFrame(using:) / animateLiveClosingTransition(completion:)
// 功能说明: 修改后 closing live 会记录 targetRect 的来源，并在 focusRect 缺失时优先退到 cardRect；只有 preferredRect 整体缺失时才真正 fallback 到 snapshot。
func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
    currentContext = context
    switch liveStrategy {
    case .liveClosing:
        let targetFrameResolution = resolveLiveClosingTargetFrame(using: context)
        liveTargetFrame = targetFrameResolution?.rect
        liveTargetRectSource = targetFrameResolution?.source
    case .snapshotFallback:
        snapshotFallbackCarrier.updateTransitionContext(context)
    case .liveOpening:
        break
    }
}

private func resolveLiveClosingTargetFrame(
    using context: BoardListCanvasTransitionContext
) -> PreferredRectResolution? {
    guard
        let overlayHostView,
        let destinationView = destinationViewController?.view,
        let targetRectResolution = preferredRectResolution(
            from: context.targetGeometry
        )
    else {
        return nil
    }

    let convertedTargetRect = overlayHostView.convert(
        targetRectResolution.rect,
        from: destinationView
    ).standardized
    guard convertedTargetRect.isEmpty == false else {
        return nil
    }

    return PreferredRectResolution(
        rect: convertedTargetRect,
        source: targetRectResolution.source
    )
}

private func animateLiveClosingTransition(completion: @escaping () -> Void) {
    // ...
    let targetFrameResolution = liveTargetFrame.map { frame in
        PreferredRectResolution(
            rect: frame,
            source: liveTargetRectSource ?? .focusRect
        )
    } ?? {
        guard let currentContext else {
            return nil
        }
        return resolveLiveClosingTargetFrame(using: currentContext)
    }()
    guard let targetFrameResolution else {
        let fallbackReason = currentContext.flatMap {
            preferredRectResolution(from: $0.targetGeometry)
        } == nil
            ? "targetPreferredRectMissing"
            : "targetFrameInvalid"
        fallbackToSnapshotClosing(
            reason: fallbackReason,
            completion: completion
        )
        return
    }

    logLiveCarrierEvent(
        phase: "closingAnimateBegin",
        extra:
            "targetRectSource=\(targetFrameResolution.source.rawValue) " +
            "targetFrame=\(describe(rect: targetFrameResolution.rect))"
    )
    // ...
}
```

## 修改四：live carrier 的状态清理补齐 `targetRectSource`

### 修改前

- `liveTargetFrame` 会在 closing handoff / cleanup 时被清掉，但 `target rect` 的来源并没有额外状态记录。
- 这会让日志只能看目标 frame 数值，无法知道本次 closing 实际对齐的是 `focusRect` 还是 `cardRect`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: performLiveClosingHandoff(completion:) / cleanupLiveTransitionArtifacts(...)
// 功能说明: 修改前 closing handoff 和 cleanup 只清理 liveTargetFrame，不保存也不清理 targetRectSource 这一层语义状态。
private func performLiveClosingHandoff(completion: @escaping () -> Void) {
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    isCanvasMountedInOverlay = false
    logLiveCarrierEvent(phase: "closingHandoffFinished")
    completion()
}

private func cleanupLiveTransitionArtifacts(
    restoreCanvasToHost: Bool,
    restoreChromeVisibility: Bool,
    removeLiveCanvasFromHierarchy: Bool,
    clearContext: Bool
) {
    // ...
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    // ...
}
```

### 修改后

- 新增 `liveTargetRectSource` 状态，并在：
  - `updateTransitionContext(_:)`
  - `prepareClosingLiveTransition(...)`
  - `performLiveClosingHandoff(...)`
  - `cleanupLiveTransitionArtifacts(...)`
 里同步维护。
- 这样 closing trace 即使最后 fallback 到 `cardRect`，日志里也能直接看到 `targetRectSource=cardRect`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: liveTargetRectSource / performLiveClosingHandoff(completion:) / cleanupLiveTransitionArtifacts(...)
// 功能说明: 修改后 closing live 除了 frame 本身，还会显式记录 targetRect 的来源，并在 handoff / cleanup 时对称清理。
private var liveTargetFrame: CGRect?
private var liveTargetRectSource: PreferredRectSource?

private func performLiveClosingHandoff(completion: @escaping () -> Void) {
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    liveTargetRectSource = nil
    isCanvasMountedInOverlay = false
    logLiveCarrierEvent(phase: "closingHandoffFinished")
    completion()
}

private func cleanupLiveTransitionArtifacts(
    restoreCanvasToHost: Bool,
    restoreChromeVisibility: Bool,
    removeLiveCanvasFromHierarchy: Bool,
    clearContext: Bool
) {
    if restoreCanvasToHost {
        restoreLiveCanvasToHostIfNeeded()
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

## 本轮结果

- placeholder、board preview、grid/list 四类入口现在都通过正式几何语义参与转场锚点解析。
- source / target geometry 统一走归一化路径，visible cell 与 fallback 路径不再各自维护一套分支。
- live carrier 已经从“必须拿到 `focusRect` 才能工作”升级为“统一消费 `preferredRect`”：
  - 有 `focusRect` 时，对齐缩略图区域
  - 没有 `focusRect` 但仍有 `cardRect` 时，live 路径仍可继续
  - 只有 `preferredRect` 整体缺失时才真正 fallback 到 `snapshotShell`
- opening / closing 的视觉语义因此更接近 `Phase 5` 目标：先追求“缩略图内容放大 / 缩回”，缺失时再按同一契约退回整卡，而不是一边退卡、一边直接放弃 live。

## 校验情况

- 当前工作树中，`Phase 5` 相关文件状态与本记录一致：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 已对上述 3 个文件执行 `ReadLints`，结果为无 lint 错误。
- 已执行编译校验：
  - 命令：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
  - 结果：`BUILD SUCCEEDED`
- 本轮没有执行手动视觉回归；因此 grid/list、placeholder、新建板返回等场景的最终视觉一致性仍需在模拟器或真机上进一步确认。

## 备注

- 这份记录只覆盖 `Phase 5` 的特殊场景与视觉对称性补齐，不包含 `Phase 6` 的 trace 扩展、灰度切换与默认 carrier 切换。
