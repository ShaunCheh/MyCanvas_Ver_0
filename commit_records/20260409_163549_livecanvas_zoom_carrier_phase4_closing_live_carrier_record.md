# 20260409_163549_livecanvas_zoom_carrier_phase4_closing_live_carrier_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 4` 的实施记录。
- 记录目标：在不推翻现有 `AppRoot` closing 编排与 target-ready 链的前提下，让 iOS closing 从“整页 snapshot 缩回”升级为“真实 canvas live 内容缩回目标 `focusRect`”。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_163549`
  - 当前工作树 `git status --short -- <Phase 4 相关文件>`
  - 当前工作树 `git diff -- <Phase 4 相关文件>`
  - 修改后的源码内容
  - `ReadLints` 校验结果
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 依赖但本轮未改动的现有链路：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：
  - `Phase 3` 的 opening live carrier 主路径
  - `Phase 5` 的特殊场景补齐
  - git commit

## 问题背景

- `Phase 3` 已经让 opening 能够使用 `iOSLiveCanvasCarrier`，从 boardlist 的 `focusRect` 放大到真实 canvas。
- 但 closing 仍然停留在“live 边界已接好，实际行为仍回退 snapshot”的状态：
  - return request 还没有显式切到 `.liveCanvas`
  - `iOSLiveCanvasCarrier` 内部仍把 `.closing` 记成 `closingLiveNotImplemented`
  - 虽然 `AppRoot.beginClosingTransition(with:) -> prepareTransitionTargetGeometry(...) -> handleResolvedClosingTargetGeometry(...)` 这条 target-ready 链已经能返回 `focusRect`，但 carrier 并没有真的消费它来缩回 live canvas
- `Phase 4` 的目标是：
  - 保留现有 closing trace / target-ready / guardrail 主干
  - 只把 carrier 的 closing 实现换成 live canvas 缩回目标 `focusRect`
  - 一旦 target `focusRect` 缺失或 live 内容不可用，再显式退回 `snapshotShell`

## 修改一：返回 boardlist 的 request 显式切到 `.liveCanvas`

### 修改前

- `iOSViewController.makeReturnToBoardListRequest(...)` 构造 closing request 时没有显式指定 `preferredCarrierKind`。
- 因此 return request 仍沿用默认值 `.snapshotShell`，closing 不会进入 live carrier 主路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makeReturnToBoardListRequest(debugTrace:)
// 功能说明: 修改前 closing request 仍沿用默认 carrier，返回 boardlist 时不会显式偏向 .liveCanvas。
private func makeReturnToBoardListRequest(
    debugTrace: BoardListCanvasTransitionDebugTrace? = nil
) -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext,
        debugTrace: debugTrace
    )
}
```

### 修改后

- return request 现在显式带上 `preferredCarrierKind: .liveCanvas`。
- 这样在 `AppRoot.beginClosingTransition(with:)` 中，carrier factory 会优先创建 `iOSLiveCanvasCarrier`，closing live 路径才有机会真正被命中。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makeReturnToBoardListRequest(debugTrace:)
// 功能说明: 修改后 iOS closing request 会明确请求 .liveCanvas，使返回 boardlist 时优先进入 live closing 主路径。
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
```

## 修改二：`iOSLiveCanvasCarrier` 的策略从 opening-only 扩成 opening + closing

### 修改前

- `iOSLiveCanvasCarrier.Strategy` 只有：
  - `.liveOpening`
  - `.snapshotFallback`
- `prepareTransition(...)` 在 `.closing` 分支里不会做任何 live 准备，只会直接打印 `closingLiveNotImplemented` 后回退到 `snapshotFallbackCarrier`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier.Strategy / prepareTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改前 live carrier 只实现 opening live；closing 分支仍明确标记为未实现并回退 snapshot。
final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private enum Strategy {
        case liveOpening
        case snapshotFallback
    }

    private static let openingPreviewCornerRadius: CGFloat = 10

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        cleanupLiveOpeningArtifacts(
            restoreCanvasToHost: true,
            restoreChromeVisibility: true
        )
        snapshotFallbackCarrier.cancelTransition()

        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        liveStrategy = .snapshotFallback

        switch context.direction {
        case .opening:
            // ... opening live 准备 ...
            liveStrategy = .liveOpening
        case .closing:
            logLiveOpeningFallback(reason: "closingLiveNotImplemented")
            snapshotFallbackCarrier.prepareTransition(
                with: context,
                sourceViewController: sourceViewController,
                destinationViewController: destinationViewController
            )
        }
    }
}
```

### 修改后

- `Strategy` 新增 `.liveClosing`。
- `openingPreviewCornerRadius` 统一改名为 `previewCornerRadius`，让同一套视觉常量可同时服务 opening / closing。
- `prepareTransition(...)` 在 closing 分支现在会尝试 `prepareClosingLiveTransition(...)`，失败时才退回 `prepareSnapshotFallback(...)`。
- `animateTransition(...)`、`updateTransitionContext(...)`、`completeTransition()`、`cancelTransition()` 也同步扩展到 closing live 场景。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier.Strategy / prepareTransition(with:sourceViewController:destinationViewController:) / animateTransition(completion:)
// 功能说明: 修改后 iOSLiveCanvasCarrier 具备 liveOpening + liveClosing 双分支，并在 prepare / animate / complete / cancel 上统一管理两条 live 路径。
final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private enum Strategy {
        case liveOpening
        case liveClosing
        case snapshotFallback
    }

    private static let previewCornerRadius: CGFloat = 10

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        cleanupLiveTransitionArtifacts(
            restoreCanvasToHost: true,
            restoreChromeVisibility: true,
            removeLiveCanvasFromHierarchy: false,
            clearContext: true
        )
        snapshotFallbackCarrier.cancelTransition()

        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        liveStrategy = .snapshotFallback

        switch context.direction {
        case .opening:
            guard
                prepareOpeningLiveTransition(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
            else {
                prepareSnapshotFallback(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

            liveStrategy = .liveOpening
        case .closing:
            guard
                prepareClosingLiveTransition(
                    with: context,
                    sourceViewController: sourceViewController
                )
            else {
                prepareSnapshotFallback(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

            liveStrategy = .liveClosing
        }
    }

    func animateTransition(completion: @escaping () -> Void) {
        guard let context = currentContext else {
            completion()
            return
        }

        switch (context.direction, liveStrategy) {
        case (.opening, .liveOpening):
            animateLiveOpeningTransition(completion: completion)
        case (.closing, .liveClosing):
            animateLiveClosingTransition(completion: completion)
        case (.opening, .snapshotFallback), (.closing, .snapshotFallback):
            snapshotFallbackCarrier.animateTransition(completion: completion)
        default:
            completion()
        }
    }
}
```

## 修改三：closing 预处理阶段把 source live canvas 提升到 overlay

### 修改前

- closing 不会创建 live 容器，也不会把 source `canvasViewportView` 从 `canvasHostView` 提升到 overlay。
- 因此即便 target-ready 最终返回了 `focusRect`，carrier 也没有一个 live 内容主体可以去做缩回动画。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改前 closing 分支不会准备 source live canvas，也不会把它提到 overlay。
switch context.direction {
case .opening:
    // ... opening live 准备 ...
    liveStrategy = .liveOpening
case .closing:
    logLiveOpeningFallback(reason: "closingLiveNotImplemented")
    snapshotFallbackCarrier.prepareTransition(
        with: context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}
```

### 修改后

- 新增 `prepareClosingLiveTransition(with:sourceViewController:)`。
- 这个阶段会：
  - 校验 `overlayHostView`
  - 校验 source controller
  - 校验 source `canvasViewportView` 与 `canvasHostView`
  - 校验 `liveCanvasView` 当前确实仍挂在 `liveCanvasHostView` 下
  - 计算 source host 转到 overlay 后的 `sourceFrame`
  - 先把 source chrome 隐藏
  - 创建 fullscreen live container
  - 把 source 真实 `canvasViewportView` reparent 到 overlay live container
  - 预先尝试解一次 `liveTargetFrame = resolveLiveClosingTargetFrame(using:)`
- 注意：此时 target-ready 可能尚未完成，因此 `liveTargetFrame` 可以暂时为空；后续会通过 `updateTransitionContext(_:)` 再写回。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareClosingLiveTransition(with:sourceViewController:)
// 功能说明: 修改后 closing 预处理阶段会把 source 的真实 canvasViewportView 提到 overlay，为后续缩回目标 focusRect 做准备。
private func prepareClosingLiveTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?
) -> Bool {
    guard let overlayHostView else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "overlayHostViewMissing"
        )
        return false
    }
    guard let sourceViewController else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "sourceViewControllerMissing"
        )
        return false
    }
    guard let liveCanvasView = requirements.canvasViewProvider() else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "sourceCanvasViewMissing"
        )
        return false
    }
    guard let liveCanvasHostView = requirements.canvasContainerViewProvider() else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "sourceCanvasHostViewMissing"
        )
        return false
    }
    guard liveCanvasView.isDescendant(of: liveCanvasHostView) else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "sourceCanvasViewNotHosted"
        )
        return false
    }

    overlayHostView.layoutIfNeeded()
    sourceViewController.view.layoutIfNeeded()
    liveCanvasHostView.layoutIfNeeded()

    let sourceFrame = overlayHostView.convert(
        liveCanvasHostView.bounds,
        from: liveCanvasHostView
    ).standardized
    guard sourceFrame.isEmpty == false else {
        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: "sourceFrameInvalid"
        )
        return false
    }

    originalChromeHiddenState = requirements.isTransitionChromeHidden()
    requirements.setTransitionChromeHidden(true)

    let liveContainerView = UIView(frame: sourceFrame)
    liveContainerView.backgroundColor = .clear
    liveContainerView.isUserInteractionEnabled = false
    liveContainerView.clipsToBounds = true
    liveContainerView.layer.cornerRadius = 0

    attachLiveCanvasViewToContainer(
        liveCanvasView,
        containerView: liveContainerView
    )
    overlayHostView.addSubview(liveContainerView)

    self.liveCanvasView = liveCanvasView
    self.liveCanvasHostView = liveCanvasHostView
    self.liveContainerView = liveContainerView
    self.liveTargetFrame = resolveLiveClosingTargetFrame(using: context)
    isCanvasMountedInOverlay = true

    logLiveCarrierEvent(
        phase: "closingPrepareFinished",
        extra: "sourceFrame=\(describe(rect: sourceFrame))"
    )
    return true
}
```

## 修改四：closing 动画现在消费 target-ready 的 `focusRect`

### 修改前

- `updateTransitionContext(_:)` 只会把 context 继续传给 snapshot fallback。
- `.closing` 分支没有 live 动画，也没有消费 target-ready 回写后的 `context.targetGeometry.focusRect`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: updateTransitionContext(_:) / animateTransition(completion:)
// 功能说明: 修改前 closing 不会消费 target-ready focusRect，carrier 只把 context 继续转发给 snapshot fallback。
func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
    snapshotFallbackCarrier.updateTransitionContext(context)
}

func animateTransition(completion: @escaping () -> Void) {
    snapshotFallbackCarrier.animateTransition(completion: completion)
}
```

### 修改后

- `updateTransitionContext(_:)` 在 `liveClosing` 分支下会实时刷新 `liveTargetFrame`。
- 新增 `resolveLiveClosingTargetFrame(using:)`，专门把 `context.targetGeometry.focusRect` 转成 overlay 坐标系中的 closing 目标 frame。
- 新增 `animateLiveClosingTransition(completion:)`，当 target-ready 已经返回 `focusRect` 时：
  - 让 destination BoardList 先显示在底层
  - 让 overlay 上的 live canvas 从 fullscreen/sourceFrame 缩回到 target `focusRect`
  - 动画完成后走 `performLiveClosingHandoff(completion:)`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: updateTransitionContext(_:) / resolveLiveClosingTargetFrame(using:) / animateLiveClosingTransition(completion:)
// 功能说明: 修改后 closing live 会消费 target-ready 回写的 focusRect，把当前 canvas live 内容直接缩回目标缩略图区域。
func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
    currentContext = context
    switch liveStrategy {
    case .liveClosing:
        liveTargetFrame = resolveLiveClosingTargetFrame(using: context)
    case .snapshotFallback:
        snapshotFallbackCarrier.updateTransitionContext(context)
    case .liveOpening:
        break
    }
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

private func animateLiveClosingTransition(completion: @escaping () -> Void) {
    guard let destinationView = destinationViewController?.view else {
        fallbackToSnapshotClosing(
            reason: "destinationViewMissing",
            completion: completion
        )
        return
    }
    destinationView.isHidden = false
    destinationView.alpha = 1
    destinationView.superview?.layoutIfNeeded()

    guard let liveContainerView else {
        fallbackToSnapshotClosing(
            reason: "liveContainerUnavailable",
            completion: completion
        )
        return
    }
    let targetFrame = liveTargetFrame ?? {
        guard let currentContext else {
            return nil
        }
        return resolveLiveClosingTargetFrame(using: currentContext)
    }()
    guard let targetFrame else {
        let fallbackReason =
            currentContext?.targetGeometry.focusRect == nil
            ? "targetFocusRectMissing"
            : "targetFrameInvalid"
        fallbackToSnapshotClosing(
            reason: fallbackReason,
            completion: completion
        )
        return
    }

    logLiveCarrierEvent(
        phase: "closingAnimateBegin",
        extra: "targetFrame=\(describe(rect: targetFrame))"
    )
    UIView.animate(
        withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
        delay: 0,
        options: [
            .beginFromCurrentState,
            Self.animationOptions(
                for: BoardListCanvasTransitionConfiguration.closingAnimation.curve
            )
        ]
    ) {
        liveContainerView.frame = targetFrame
        liveContainerView.layer.cornerRadius = self.previewCornerRadius(
            for: targetFrame
        )
    } completion: { [weak self] _ in
        self?.performLiveClosingHandoff(completion: completion)
    }
}
```

## 修改五：closing fallback、handoff 与清理改为对称收口

### 修改前

- 只有 opening live 才有自己的 handoff / cleanup 逻辑。
- closing 一旦 live 不可用，既没有统一 fallback reason，也没有“恢复 source canvas / 恢复 chrome / 切回 snapshot”这一条封装好的对称收口链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: performLiveOpeningHandoff(completion:) / cleanupLiveOpeningArtifacts(...)
// 功能说明: 修改前只有 opening live 路径有 handoff 与清理函数，closing 没有对称的 live 收口逻辑。
private func performLiveOpeningHandoff(completion: @escaping () -> Void) {
    destinationViewController?.view.isHidden = false
    destinationViewController?.view.alpha = 1
    destinationViewController?.view.superview?.layoutIfNeeded()

    restoreLiveCanvasToHostIfNeeded()
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil

    logLiveOpeningEvent(phase: "handoffBegin")
    restoreChromeVisibilityIfNeeded(animated: true) { [weak self] in
        self?.logLiveOpeningEvent(phase: "handoffFinished")
        completion()
    }
}
```

### 修改后

- opening / closing 共用一套更通用的 live 清理函数 `cleanupLiveTransitionArtifacts(...)`。
- 新增：
  - `performLiveClosingHandoff(completion:)`
  - `prepareSnapshotFallback(...)`
  - `fallbackToSnapshotClosing(reason:completion:)`
  - `logLiveCarrierFallback(phase:reason:)`
  - `logLiveCarrierEvent(phase:extra:)`
- closing live 不可用时，现在会：
  1. 打印明确 fallback reason
  2. 把 canvas 还回 host
  3. 恢复 chrome
  4. 重新准备 snapshot fallback
  5. 继续执行现有 snapshot closing 动画
- closing live 正常完成时，则会直接移除 overlay live container，并把 source 真实 canvas 从层级中清掉，等待 `AppRoot.completeClosingTransition(sessionID:)` 卸载 source controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: performLiveClosingHandoff(completion:) / fallbackToSnapshotClosing(reason:completion:) / cleanupLiveTransitionArtifacts(...)
// 功能说明: 修改后 closing live 与 opening 一样有了对称的 handoff、fallback 和状态清理收口。
private func performLiveClosingHandoff(completion: @escaping () -> Void) {
    liveContainerView?.removeFromSuperview()
    liveContainerView = nil
    liveTargetFrame = nil
    isCanvasMountedInOverlay = false
    logLiveCarrierEvent(phase: "closingHandoffFinished")
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
        clearContext: false
    )
    sourceViewController?.view.layoutIfNeeded()
    destinationViewController?.view.layoutIfNeeded()
    prepareSnapshotFallback(
        with: context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    snapshotFallbackCarrier.animateTransition(completion: completion)
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

    if restoreChromeVisibility {
        restoreChromeVisibilityIfNeeded(animated: false) {}
    } else {
        originalChromeHiddenState = nil
    }

    liveCanvasView = nil
    liveCanvasHostView = nil
    liveStrategy = .snapshotFallback
    isCanvasMountedInOverlay = false

    if clearContext {
        currentContext = nil
        sourceViewController = nil
        destinationViewController = nil
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: logLiveCarrierFallback(phase:reason:) / logLiveCarrierEvent(phase:extra:)
// 功能说明: 修改后 opening 与 closing 统一使用同一套 live 日志出口，便于 Phase 6 再接入更系统的回归护栏。
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

private func logLiveCarrierEvent(
    phase: String,
    extra: String = ""
) {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    print(
        "[BoardListCanvasTransition][iOS][LiveCarrier] " +
            "phase=\(phase)" +
            extraSuffix
    )
}
```

## 本轮结果

- iOS 返回 boardlist 的 request 已明确切到 `.liveCanvas`。
- `iOSLiveCanvasCarrier` 现在不再只是 opening live，它已具备 closing live 主路径。
- closing 会继续复用现有 `AppRoot` 的：
  - `prepareTransitionTargetGeometry(for:completion:)`
  - `handleResolvedClosingTargetGeometry(...)`
  - closing trace / target-ready 主干
- 但在真正动画时，carrier 已经改成消费 live canvas + target `focusRect`，而不是继续缩整页 snapshot。
- target `focusRect` 缺失、source live view 不可用、target frame 无法解析等场景下，仍会明确 fallback 到现有 snapshot shell。

## 校验情况

- 当前工作树中，`Phase 4` 相关文件状态与本记录一致：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 已对以下文件执行 `ReadLints`，结果为无 lint 错误：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本轮未执行真机 / 模拟器上的 closing 视觉回归；因此“是否已经完全呈现为 live canvas 缩回目标缩略图”的最终效果仍需要运行时验证。

## 备注

- 这份记录只覆盖 `Phase 4` 的 closing live carrier 主路径，不包含 `Phase 5` 的特殊场景补齐与视觉对称性复核。
