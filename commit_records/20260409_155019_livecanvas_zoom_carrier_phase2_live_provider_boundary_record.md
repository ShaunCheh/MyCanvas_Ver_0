# 20260409_155019_livecanvas_zoom_carrier_phase2_live_provider_boundary_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 2` 的实施记录。
- 记录目标：在 `iOSViewController`、`AppRoot` 与 carrier factory 之间建立 live canvas 内容提供者边界，并让 `.liveCanvas` 请求不再直接硬编码回 snapshot carrier。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_155019`
  - 当前工作树 `git status --short -- <Phase 2 相关文件>`
  - 当前工作树 `git diff -- <Phase 2 相关文件>`
  - 修改后的源码内容
  - `ReadLints` 校验结果
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 本记录不包含：
  - `Phase 3` 的 opening live reparent / handoff
  - `Phase 4` 的 closing live zoom back
  - 对 `.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md` 的再编辑
  - git commit

## 问题背景

- `Phase 1` 已经把几何语义统一成 `focusRect + cardRect`，但 `.liveCanvas` 在 iOS 侧仍然只是一个“语义占位”：
  - `iOSViewController` 还没有对外暴露 live 转场真正需要的画布宿主与 chrome 控制能力。
  - `iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...)` 虽然能收到 `.liveCanvas`，但实际上仍然直接返回 `iOSSnapshotShellCarrier()`。
  - `iOSAppRootViewController` 的 opening / closing 编排也没有去解析 source / destination controller 上的 live provider。
- 这意味着当前架构还不能把 `canvasViewportView` 视为一个可被 future live carrier 接管的正式转场主体。
- `Phase 2` 的目标不是马上做 live reparent，而是先把：
  - provider 协议
  - requirements 注入容器
  - AppRoot 两端接线
  - `.liveCanvas` 的独立 carrier 实例
  这四个边界补齐。

## 修改一：`iOSViewController` 正式暴露 live canvas provider 边界

### 修改前

- `iOSViewController` 内部已经存在天然分层：
  - `canvasViewportView`
  - `canvasHostView`
  - `chromeOverlayView`
- 但这些能力都只是 controller 内部实现细节，没有一个对 AppRoot / carrier 公开的窄接口。
- 因此 AppRoot 无法“类型安全”地拿到 live canvas view、host view 与 chrome 显隐控制能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: iOSViewController / canvasHostView / chromeOverlayView / canvasViewportView
// 功能说明: 修改前这些 live 转场真正需要的视图都只作为 iOSViewController 的内部实现细节存在，对外没有 provider 协议。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate, iOSBoardListCanvasTransitionInteractionControlling {
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let chromeOverlayView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let canvasViewportView = iOSCanvasViewportView()
}
```

### 修改后

- 新增 `CanvasTransitionLiveContentProviding` 协议。
- `iOSViewController` 正式实现该协议，对外暴露：
  - `transitionCanvasViewportView`
  - `transitionCanvasHostView`
  - `isTransitionChromeHidden`
  - `setTransitionChromeHidden(_:)`
- 同时新增 `transitionChromeHidden` 状态与 `applyTransitionChromeVisibility()`，把 chrome 显隐从“未来 live carrier 需要临时管控的内部行为”升级为正式能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: CanvasTransitionLiveContentProviding / iOSViewController
// 功能说明: 修改后 iOSViewController 通过 provider 协议把 live 转场真正需要的 viewport、host 与 chrome 控制能力对外暴露。
protocol CanvasTransitionLiveContentProviding: AnyObject {
    var transitionCanvasViewportView: UIView { get }
    var transitionCanvasHostView: UIView { get }
    var isTransitionChromeHidden: Bool { get }

    func setTransitionChromeHidden(_ isHidden: Bool)
}

final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate, iOSBoardListCanvasTransitionInteractionControlling, CanvasTransitionLiveContentProviding {
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let chromeOverlayView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var transitionChromeHidden = false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: applyTransitionInteractionFreeze() / applyTransitionChromeVisibility() / extension iOSViewController
// 功能说明: 修改后 chrome 显隐由 transitionChromeHidden 统一控制，供 future live carrier 在 reparent 前后进行显式切换。
private func applyTransitionInteractionFreeze() {
    transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
    textEditorOverlayView.isUserInteractionEnabled = isTransitionInteractionFrozen == false
    if isTransitionInteractionFrozen {
        dismissContextMenu()
        handlePrimaryPointerCancel()
    }
    applyTransitionChromeVisibility()
}

private func applyTransitionChromeVisibility() {
    chromeOverlayView.alpha = transitionChromeHidden ? 0 : 1
    chromeOverlayView.isUserInteractionEnabled =
        transitionChromeHidden == false &&
        isTransitionInteractionFrozen == false
}

extension iOSViewController {
    var transitionCanvasViewportView: UIView {
        canvasViewportView
    }

    var transitionCanvasHostView: UIView {
        canvasHostView
    }

    var isTransitionChromeHidden: Bool {
        transitionChromeHidden
    }

    func setTransitionChromeHidden(_ isHidden: Bool) {
        guard transitionChromeHidden != isHidden else {
            return
        }

        transitionChromeHidden = isHidden
        guard isViewLoaded else {
            return
        }

        applyTransitionChromeVisibility()
    }
}
```

## 修改二：`iOSLiveCanvasCarrierRequirements` 与 factory 从占位升级为正式注入点

### 修改前

- `iOSLiveCanvasCarrierRequirements` 只有两个 provider：
  - `canvasViewProvider`
  - `canvasContainerViewProvider`
- 但它没有 chrome 显隐控制，也没有被真正接入到 factory。
- factory 在收到 `.liveCanvas` 时，仍然直接返回 `iOSSnapshotShellCarrier()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrierRequirements / iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...)
// 功能说明: 修改前 live requirements 还不完整，而且 .liveCanvas 请求仍会直接退回 snapshotShell。
struct iOSLiveCanvasCarrierRequirements {
    let canvasViewProvider: () -> UIView?
    let canvasContainerViewProvider: () -> UIView?
}

enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            // Phase 3 keeps the live carrier boundary explicit while
            // still routing through the snapshot shell implementation.
            return iOSSnapshotShellCarrier()
        }
    }
}
```

### 修改后

- `iOSLiveCanvasCarrierRequirements` 补齐 chrome 控制能力：
  - `isTransitionChromeHidden`
  - `setTransitionChromeHidden`
- `makeCarrier(...)` 新增 `liveCanvasRequirements` 参数。
- 当 `preferredKind == .liveCanvas` 且 requirements 存在时，factory 会返回独立的 `iOSLiveCanvasCarrier` 实例。
- 若 requirements 缺失，则仍然会显式退回 `iOSSnapshotShellCarrier()`，为后续 rollout 保留 fallback。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrierRequirements / iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...)
// 功能说明: 修改后 factory 不再把 .liveCanvas 硬编码回 snapshotShell；requirements 也补齐了 chrome 控制闭环。
struct iOSLiveCanvasCarrierRequirements {
    let canvasViewProvider: () -> UIView?
    let canvasContainerViewProvider: () -> UIView?
    let isTransitionChromeHidden: () -> Bool
    let setTransitionChromeHidden: (Bool) -> Void
}

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
```

## 修改三：新增独立 `iOSLiveCanvasCarrier`，但 `Phase 2` 仍先桥接 snapshot fallback

### 修改前

- iOS 侧没有独立的 `iOSLiveCanvasCarrier` 类型。
- `.liveCanvas` 的所有请求在 factory 层就已经被吸回 `iOSSnapshotShellCarrier()`，无法证明 live 路径的依赖边界已经成立。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(...)
// 功能说明: 修改前 iOS 侧不存在真正独立的 live carrier 类型，.liveCanvas 只是一个枚举值占位。
enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            return iOSSnapshotShellCarrier()
        }
    }
}
```

### 修改后

- 新增独立类型 `iOSLiveCanvasCarrier`。
- 当前阶段它还不会真正做 live reparent，而是：
  - 持有 `iOSLiveCanvasCarrierRequirements`
  - 在 `prepareTransition(...)` 时先触达 provider 闭包，确认边界已可用
  - 再桥接到 `snapshotFallbackCarrier`
- 这样 `Phase 2` 已经把“独立 carrier 类型”和“live 依赖注入边界”建立起来，但没有提前引入 `Phase 3/4` 的动画复杂度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSLiveCanvasCarrier
// 功能说明: 修改后 iOS 有了独立的 live carrier 类型；Phase 2 先通过 snapshot fallback 保持行为稳定，同时让 requirements 与 provider 真正参与编排。
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

## 修改四：`AppRoot` opening / closing 两端都开始解析 live provider

### 修改前

- `beginOpeningTransition(with:)` 只负责：
  - 创建 destination canvas
  - 创建 carrier
  - mount hidden destination
  - `prepareTransition(...)`
- `beginClosingTransition(with:)` 也只是：
  - 选取当前 canvas 作为 source
  - 选取 boardlist 作为 destination
  - 创建 carrier
  - mount hidden boardlist
  - `prepareTransition(...)`
- 两端都没有显式解析 live provider，也没有把 requirements 传给 factory。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / beginClosingTransition(with:)
// 功能说明: 修改前 AppRoot 的 opening/closing 编排里还没有解析 provider，也没有把 live requirements 传给 carrier factory。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    let sourceViewController = currentViewController ?? boardListViewController
    let destinationViewController = makeCanvasViewController(
        for: request.launchContext
    )
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    // ...
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    view.layoutIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    let sourceViewController = currentViewController
    let destinationViewController = boardListViewController
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    // ...
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    destinationViewController.setClosingTransitionTimingTrace(session.debugTrace)
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}
```

### 修改后

- opening 改成：
  - 先 mount hidden destination canvas
  - `view.layoutIfNeeded()`
  - 从 destination controller 解析 live requirements
  - 把 requirements 交给 factory
- closing 改成：
  - 先 mount hidden boardlist
  - `view.layoutIfNeeded()`
  - 从 source canvas controller 解析 live requirements
  - 把 requirements 交给 factory
- 这与计划中的语义一致：
  - opening 需要 destination provider
  - closing 需要 source provider

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / beginClosingTransition(with:)
// 功能说明: 修改后 AppRoot 会在 opening/closing 两端分别解析 destination/source 的 live provider，并把 requirements 传入 carrier factory。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    let sourceViewController = currentViewController ?? boardListViewController
    let destinationViewController = makeCanvasViewController(
        for: request.launchContext
    )
    mountViewController(destinationViewController, hidden: true)
    view.layoutIfNeeded()
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
    // ...
    carrier.install(in: overlayHostView)
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    let sourceViewController = currentViewController
    let destinationViewController = boardListViewController
    mountViewController(destinationViewController, hidden: true)
    view.layoutIfNeeded()
    let liveCanvasRequirements = resolveLiveCanvasCarrierRequirements(
        from: sourceViewController,
        preferredKind: request.preferredCarrierKind,
        transitionPhase: "closing",
        providerRole: "source"
    )
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind,
        liveCanvasRequirements: liveCanvasRequirements
    )
    // ...
    carrier.install(in: overlayHostView)
    destinationViewController.setClosingTransitionTimingTrace(session.debugTrace)
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}
```

## 修改五：新增 requirements 解析与 fallback 日志

### 修改前

- `AppRoot` 没有一个统一的 requirements 解析函数。
- 如果未来 `.liveCanvas` 发生 provider 缺失，也没有明确的 fallback reason 输出点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: （修改前不存在对应函数）
// 功能说明: 修改前 AppRoot 没有集中式 live requirements 解析，也没有 liveCanvas fallback reason 日志。
// 无
```

### 修改后

- 新增 `resolveLiveCanvasCarrierRequirements(...)`，统一负责：
  - `loadViewIfNeeded()`
  - `layoutIfNeeded()`
  - provider 类型校验
  - requirements 闭包封装
- 新增 `logLiveCanvasCarrierFallbackIfNeeded(...)`，当请求 `.liveCanvas` 但：
  - viewController 缺失
  - provider 缺失
  时，会直接打印明确 reason。
- 这样 `Phase 2` 虽然还没有真正开始 live 动画，但 fallback 行为已经具备可观测性。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: resolveLiveCanvasCarrierRequirements(from:preferredKind:transitionPhase:providerRole:) / logLiveCanvasCarrierFallbackIfNeeded(preferredKind:transitionPhase:reason:)
// 功能说明: 修改后 AppRoot 统一负责 provider 解析、requirements 封装与 fallback reason 输出，为后续 live carrier rollout 提供稳定入口。
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

    viewController.loadViewIfNeeded()
    viewController.view.layoutIfNeeded()

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

private func logLiveCanvasCarrierFallbackIfNeeded(
    preferredKind: BoardListCanvasTransitionCarrierKind,
    transitionPhase: String,
    reason: String
) {
    guard preferredKind == .liveCanvas else {
        return
    }

    print(
        "[BoardListCanvasTransition][iOS][AppRoot] " +
            "phase=liveCanvasCarrierFallback " +
            "transitionPhase=\(transitionPhase) " +
            "reason=\(reason)"
    )
}
```

## 本轮结果

- `iOSViewController` 已经具备正式的 live provider 边界。
- `AppRoot` opening / closing 两端都已经知道该从哪里取 live provider。
- `.liveCanvas` 在 iOS 侧终于有了独立的 carrier 类型与 requirements 注入容器。
- provider 缺失时会有明确 fallback reason，而不是静默退回 snapshot。
- 但这一轮仍然**没有**实现真正的 live reparent / handoff；`iOSLiveCanvasCarrier` 目前仍桥接到 snapshot fallback，这是 `Phase 2` 的刻意边界。

## 校验情况

- 当前工作树中，`Phase 2` 相关文件状态与本记录一致：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 已对上述 3 个文件执行 `ReadLints`，结果为无 lint 错误。
- 本轮主要是边界接线与依赖注入改造，未执行真机 / 模拟器上的 opening / closing live 视觉回归。

## 备注

- 这份记录只覆盖 `Phase 2` 的 provider boundary、requirements 与 AppRoot 接线，不包含 `Phase 3` 的 opening live 动画主路径。
