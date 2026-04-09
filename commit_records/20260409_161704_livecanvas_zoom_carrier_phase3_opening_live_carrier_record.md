# 20260409_161704_livecanvas_zoom_carrier_phase3_opening_live_carrier_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 3` 的实施记录。
- 记录目标：把 iOS opening 路径从“`.liveCanvas` 只是枚举占位”推进到“真正由 `iOSLiveCanvasCarrier` 驱动 opening live zoom 主路径”，同时保留可观测的 snapshot fallback。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_161704`
  - 当前工作树 `git status --short -- <Phase 3 相关文件>`
  - 当前工作树 `git diff -- <Phase 3 相关文件>`
  - 修改后的源码内容
  - `ReadLints` 校验结果
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 本记录不包含：
  - `Phase 2` 的 provider boundary 与 AppRoot 接线
  - `Phase 4` 的 closing live carrier
  - git commit

## 问题背景

- `Phase 2` 之后，iOS 侧已经具备：
  - `CanvasTransitionLiveContentProviding`
  - `iOSLiveCanvasCarrierRequirements`
  - `AppRoot` 两端 provider 解析
  - `.liveCanvas` 对应的独立 carrier 类型
- 但当时的 `iOSLiveCanvasCarrier` 仍然只是薄桥接层：
  - `prepareTransition(...)` 只会触达 provider 闭包
  - 然后继续把真正的 opening / closing 行为委托给 `iOSSnapshotShellCarrier`
- 结果是：
  - opening 请求即使理论上可以走 `.liveCanvas`
  - 实际视觉主体仍然是 snapshot shell，而不是 destination 的真实 `canvasViewportView`
- `Phase 3` 的目标就是只把 opening 这条路径单独跑通：
  - source 仍从 boardlist 的 `focusRect` 起跳
  - destination 改为真实 `canvasViewportView`
  - handoff 后把 live view 归还给 `canvasHostView`
  - closing 暂时保持 snapshot fallback，不在这一阶段一起改。

## 修改一：opening request 明确切到 `.liveCanvas`

### 修改前

- `iOSBoardListViewController.makeOpenRequest(for:)` 构造 request 时仍然沿用默认值。
- 也就是说，无论 existing board 还是 new board placeholder，opening 请求都还是默认走 `.snapshotShell`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: 修改前 opening request 只带 sourceGeometry，不会显式把 preferredCarrierKind 切到 .liveCanvas。
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
```

### 修改后

- existing board 与 new board placeholder 两类 opening request 都显式改成了 `.liveCanvas`。
- 这意味着 `AppRoot.beginOpeningTransition(with:)` 在当前阶段会优先创建 `iOSLiveCanvasCarrier`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: makeOpenRequest(for:)
// 功能说明: 修改后 iOS opening request 会明确偏向 .liveCanvas，让 existing board 与新建占位都优先进入 live opening 主路径。
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

## 修改二：`iOSLiveCanvasCarrier` 从“薄桥接层”升级为有状态的 opening live carrier

### 修改前

- `iOSLiveCanvasCarrier` 只有：
  - `requirements`
  - `snapshotFallbackCarrier`
- 它没有保存 overlay/source/destination/live view 的任何状态。
- `prepareTransition(...)`、`animateTransition(...)`、`completeTransition()`、`cancelTransition()` 都只是简单转发给 `snapshotFallbackCarrier`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier
// 功能说明: 修改前 live carrier 只是 requirements 的薄桥接层，本身不持有 opening live 需要的 overlay / live view / handoff 状态。
final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private let requirements: iOSLiveCanvasCarrierRequirements
    private let snapshotFallbackCarrier: iOSSnapshotShellCarrier

    init(
        requirements: iOSLiveCanvasCarrierRequirements,
        snapshotFallbackCarrier: iOSSnapshotShellCarrier = iOSSnapshotShellCarrier()
    ) {
        self.requirements = requirements
        self.snapshotFallbackCarrier = snapshotFallbackCarrier
    }

    var kind: BoardListCanvasTransitionCarrierKind {
        .liveCanvas
    }

    func install(in overlayHostView: UIView) {
        snapshotFallbackCarrier.install(in: overlayHostView)
    }

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        let _ = requirements.canvasViewProvider()
        let _ = requirements.canvasContainerViewProvider()
        let _ = requirements.isTransitionChromeHidden()
        snapshotFallbackCarrier.prepareTransition(
            with: context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
    }

    func animateTransition(completion: @escaping () -> Void) {
        snapshotFallbackCarrier.animateTransition(completion: completion)
    }

    func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
        snapshotFallbackCarrier.updateTransitionContext(context)
    }

    func completeTransition() {
        snapshotFallbackCarrier.completeTransition()
    }

    func cancelTransition() {
        snapshotFallbackCarrier.cancelTransition()
    }
}
```

### 修改后

- `iOSLiveCanvasCarrier` 增加了真正的 opening live 状态模型：
  - `Strategy.liveOpening / .snapshotFallback`
  - overlay/source/destination/live host 引用
  - `liveCanvasView`、`liveContainerView`
  - `liveTargetFrame`
  - `originalChromeHiddenState`
  - `isCanvasMountedInOverlay`
- `prepareTransition(...)` 也从单纯桥接，升级为：
  - 先清理上一次 live opening 状态
  - 若是 `.opening`，优先尝试 `prepareOpeningLiveTransition(...)`
  - 失败则显式退回 `snapshotFallbackCarrier`
  - 若是 `.closing`，当前阶段直接打印 `closingLiveNotImplemented` 后回退

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier / prepareTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改后 iOSLiveCanvasCarrier 会优先建立 opening live 状态；只有条件不满足时才退回 snapshot shell。
final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private enum Strategy {
        case liveOpening
        case snapshotFallback
    }

    private static let openingPreviewCornerRadius: CGFloat = 10

    private let requirements: iOSLiveCanvasCarrierRequirements
    private let snapshotFallbackCarrier: iOSSnapshotShellCarrier

    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private weak var liveCanvasHostView: UIView?

    private var currentContext: BoardListCanvasTransitionContext?
    private var liveCanvasView: UIView?
    private var liveContainerView: UIView?
    private var liveTargetFrame: CGRect?
    private var liveStrategy: Strategy = .snapshotFallback
    private var originalChromeHiddenState: Bool?
    private var isCanvasMountedInOverlay = false

    func install(in overlayHostView: UIView) {
        self.overlayHostView = overlayHostView
        snapshotFallbackCarrier.install(in: overlayHostView)
    }

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
            guard
                prepareOpeningLiveTransition(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
            else {
                snapshotFallbackCarrier.prepareTransition(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

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

## 修改三：opening 预处理阶段真正把 `canvasViewportView` 放进 overlay live 容器

### 修改前

- opening 预处理阶段不会创建 live 容器，也不会触碰 destination `canvasViewportView`。
- destination 的真实画布始终留在 `canvasHostView` 中，opening 看到的仍然只是 snapshot shell。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier.prepareTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改前 opening 不会解析 source focusRect / destination host frame，也不会 reparent canvasViewportView。
func prepareTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?,
    destinationViewController: UIViewController?
) {
    let _ = requirements.canvasViewProvider()
    let _ = requirements.canvasContainerViewProvider()
    let _ = requirements.isTransitionChromeHidden()
    snapshotFallbackCarrier.prepareTransition(
        with: context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}
```

### 修改后

- 新增 `prepareOpeningLiveTransition(...)`，在 opening 预处理阶段完成：
  - 校验 `overlayHostView`
  - 校验 `sourceViewController`
  - 校验 `destinationViewController`
  - 校验 `context.sourceGeometry.focusRect`
  - 校验 `canvasViewportView` / `canvasHostView`
  - 校验 `liveCanvasView` 当前确实挂在 `liveCanvasHostView` 下
  - 计算 source `focusRect` 转到 overlay 后的 `sourceFrame`
  - 计算 destination host 转到 overlay 后的 `targetFrame`
  - 隐藏 destination chrome
  - 创建 overlay 上的 `liveContainerView`
  - 把真实 `canvasViewportView` reparent 进 live container
- 如果任一前置条件不满足，会输出明确 fallback reason。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningLiveTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改后 opening 预处理阶段会把 destination 的真实 canvasViewportView 放进 overlay live 容器，并以 source focusRect 为起点准备放大。
private func prepareOpeningLiveTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?,
    destinationViewController: UIViewController?
) -> Bool {
    guard let overlayHostView else {
        logLiveOpeningFallback(reason: "overlayHostViewMissing")
        return false
    }
    guard let sourceViewController else {
        logLiveOpeningFallback(reason: "sourceViewControllerMissing")
        return false
    }
    guard let destinationViewController else {
        logLiveOpeningFallback(reason: "destinationViewControllerMissing")
        return false
    }
    guard let sourceFocusRect = context.sourceGeometry.focusRect else {
        logLiveOpeningFallback(reason: "sourceFocusRectMissing")
        return false
    }
    guard let liveCanvasView = requirements.canvasViewProvider() else {
        logLiveOpeningFallback(reason: "destinationCanvasViewMissing")
        return false
    }
    guard let liveCanvasHostView = requirements.canvasContainerViewProvider() else {
        logLiveOpeningFallback(reason: "destinationCanvasHostViewMissing")
        return false
    }
    guard liveCanvasView.isDescendant(of: liveCanvasHostView) else {
        logLiveOpeningFallback(reason: "destinationCanvasViewNotHosted")
        return false
    }

    overlayHostView.layoutIfNeeded()
    sourceViewController.view.layoutIfNeeded()
    destinationViewController.loadViewIfNeeded()
    destinationViewController.view.layoutIfNeeded()
    liveCanvasHostView.layoutIfNeeded()

    let sourceFrame = overlayHostView.convert(
        sourceFocusRect,
        from: sourceViewController.view
    ).standardized
    let targetFrame = overlayHostView.convert(
        liveCanvasHostView.bounds,
        from: liveCanvasHostView
    ).standardized
    guard sourceFrame.isEmpty == false else {
        logLiveOpeningFallback(reason: "sourceFrameInvalid")
        return false
    }
    guard targetFrame.isEmpty == false else {
        logLiveOpeningFallback(reason: "targetFrameInvalid")
        return false
    }

    originalChromeHiddenState = requirements.isTransitionChromeHidden()
    requirements.setTransitionChromeHidden(true)

    let liveContainerView = UIView(frame: targetFrame)
    liveContainerView.backgroundColor = .clear
    liveContainerView.isUserInteractionEnabled = false
    liveContainerView.clipsToBounds = true
    liveContainerView.layer.cornerRadius = openingCornerRadius(
        for: sourceFrame
    )
    liveContainerView.center = CGPoint(
        x: sourceFrame.midX,
        y: sourceFrame.midY
    )
    liveContainerView.transform = openingScaleTransform(
        sourceFrame: sourceFrame,
        targetFrame: targetFrame
    )

    attachLiveCanvasViewToOverlay(
        liveCanvasView,
        containerView: liveContainerView
    )
    overlayHostView.addSubview(liveContainerView)

    self.liveCanvasView = liveCanvasView
    self.liveCanvasHostView = liveCanvasHostView
    self.liveContainerView = liveContainerView
    self.liveTargetFrame = targetFrame
    isCanvasMountedInOverlay = true

    logLiveOpeningEvent(
        phase: "prepareFinished",
        extra:
            "sourceFrame=\(describe(rect: sourceFrame)) " +
            "targetFrame=\(describe(rect: targetFrame))"
    )
    return true
}
```

## 修改四：opening 动画与 handoff 现在真正围绕 live canvas 展开

### 修改前

- `animateTransition(completion:)` 无条件桥接到 `snapshotFallbackCarrier.animateTransition(...)`。
- opening 动画结束后也不存在：
  - 把 live canvas 还回 `canvasHostView`
  - 恢复 destination chrome
  - 移除 overlay live 容器
  这些 handoff 收口动作。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateTransition(completion:) / completeTransition() / cancelTransition()
// 功能说明: 修改前 live carrier 的动画、完成和取消都只是继续调用 snapshot fallback，本身没有 live handoff 过程。
func animateTransition(completion: @escaping () -> Void) {
    snapshotFallbackCarrier.animateTransition(completion: completion)
}

func completeTransition() {
    snapshotFallbackCarrier.completeTransition()
}

func cancelTransition() {
    snapshotFallbackCarrier.cancelTransition()
}
```

### 修改后

- `animateTransition(completion:)` 只在 `(.opening, .liveOpening)` 时走 live opening 主路径。
- 新增：
  - `animateLiveOpeningTransition(completion:)`
  - `performLiveOpeningHandoff(completion:)`
  - `attachLiveCanvasViewToOverlay(...)`
  - `restoreLiveCanvasToHostIfNeeded()`
  - `restoreChromeVisibilityIfNeeded(animated:completion:)`
  - `cleanupLiveOpeningArtifacts(...)`
- 这条链保证：
  - 动画主体是 destination 的真实 `canvasViewportView`
  - 动画结束后视图必须回到 `canvasHostView`
  - chrome 必须恢复
  - 取消 / 完成两条路径都要清理状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateTransition(completion:) / animateLiveOpeningTransition(completion:) / performLiveOpeningHandoff(completion:)
// 功能说明: 修改后 opening live 动画从 source focusRect 放大到 destination host 区域，结束后再把真实 canvas 归还给 canvasHostView。
func animateTransition(completion: @escaping () -> Void) {
    guard let context = currentContext else {
        completion()
        return
    }

    switch (context.direction, liveStrategy) {
    case (.opening, .liveOpening):
        animateLiveOpeningTransition(completion: completion)
    case (.opening, .snapshotFallback), (.closing, _):
        snapshotFallbackCarrier.animateTransition(completion: completion)
    }
}

private func animateLiveOpeningTransition(completion: @escaping () -> Void) {
    guard
        let liveContainerView,
        let liveTargetFrame
    else {
        logLiveOpeningFallback(reason: "liveContainerUnavailable")
        destinationViewController?.view.isHidden = false
        destinationViewController?.view.alpha = 1
        restoreLiveCanvasToHostIfNeeded()
        restoreChromeVisibilityIfNeeded(animated: false) {
            completion()
        }
        return
    }

    UIView.animate(
        withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
        delay: 0,
        usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
        initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
        options: [
            .beginFromCurrentState,
            Self.animationOptions(
                for: BoardListCanvasTransitionConfiguration.openingAnimation.curve
            )
        ]
    ) {
        liveContainerView.center = CGPoint(
            x: liveTargetFrame.midX,
            y: liveTargetFrame.midY
        )
        liveContainerView.transform = .identity
        liveContainerView.layer.cornerRadius = 0
    } completion: { [weak self] _ in
        self?.performLiveOpeningHandoff(completion: completion)
    }
}

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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: attachLiveCanvasViewToOverlay(_:containerView:) / restoreLiveCanvasToHostIfNeeded() / cleanupLiveOpeningArtifacts(restoreCanvasToHost:restoreChromeVisibility:)
// 功能说明: 修改后 live canvas 的 reparent、归位与状态清理都有了对称收口，避免把真实 canvas 悬挂在 overlay 上。
private func attachLiveCanvasViewToOverlay(
    _ liveCanvasView: UIView,
    containerView: UIView
) {
    liveCanvasView.removeFromSuperview()
    liveCanvasView.translatesAutoresizingMaskIntoConstraints = true
    liveCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    liveCanvasView.frame = containerView.bounds
    containerView.addSubview(liveCanvasView)
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

private func cleanupLiveOpeningArtifacts(
    restoreCanvasToHost: Bool,
    restoreChromeVisibility: Bool
) {
    if restoreCanvasToHost {
        restoreLiveCanvasToHostIfNeeded()
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
    currentContext = nil
    sourceViewController = nil
    destinationViewController = nil
    liveStrategy = .snapshotFallback
    isCanvasMountedInOverlay = false
}
```

## 修改五：opening fallback 不再只是隐式退回，而是有明确 reason

### 修改前

- `iOSLiveCanvasCarrier` 的 live 不可用场景没有细分日志。
- `.liveCanvas` 请求实质上会一路静默桥接到 snapshot fallback。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier
// 功能说明: 修改前 live carrier 不会把 overlay/source/destination/focusRect/provider 等失败原因拆成可读日志。
final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        snapshotFallbackCarrier.prepareTransition(
            with: context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
    }
}
```

### 修改后

- opening live 不可用时，现在会针对不同失败点打印 `openingLiveFallback` reason，例如：
  - `overlayHostViewMissing`
  - `sourceViewControllerMissing`
  - `destinationViewControllerMissing`
  - `sourceFocusRectMissing`
  - `destinationCanvasViewMissing`
  - `destinationCanvasHostViewMissing`
  - `destinationCanvasViewNotHosted`
  - `sourceFrameInvalid`
  - `targetFrameInvalid`
  - `liveContainerUnavailable`
- 同时增加了 `prepareFinished`、`handoffBegin`、`handoffFinished` 等 live opening 事件日志。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: logLiveOpeningFallback(reason:) / logLiveOpeningEvent(phase:extra:)
// 功能说明: 修改后 opening live 路径有了可读的 fallback reason 和阶段日志，便于后续回归与灰度观察。
private func logLiveOpeningFallback(reason: String) {
    print(
        "[BoardListCanvasTransition][iOS][LiveCarrier] " +
            "phase=openingLiveFallback " +
            "reason=\(reason)"
    )
}

private func logLiveOpeningEvent(
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

- iOS opening request 已明确切到 `.liveCanvas`。
- `iOSLiveCanvasCarrier` 已不再只是桥接层，而是具备了真正的 opening live 主路径。
- opening 现在会直接动画 destination 的真实 `canvasViewportView`，而不是继续只看 snapshot shell。
- handoff 已具备对称收口：
  - 还回 `canvasHostView`
  - 恢复 chrome
  - 清理 overlay live container
- closing 在这一阶段仍未实现 live，代码里明确记录为 `closingLiveNotImplemented` 并继续回退 snapshot shell。

## 校验情况

- 当前工作树中，`Phase 3` 相关文件状态与本记录一致：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 已对以下文件执行 `ReadLints`，结果为无 lint 错误：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本轮未执行真机 / 模拟器上的 opening 视觉回归，因此“视觉主体是否已经完全达到预期的缩略图内容放大效果”仍需运行时验证。

## 备注

- 这份记录只覆盖 `Phase 3` 的 opening live carrier 主路径，不包含 `Phase 4` 的 closing live zoom back。
