# 20260409_094439_boardlist_zoom_transition_phase3_approot_coordinator_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 3`，在 `AppRoot` 建立可替换 carrier 的转场协调器。
- 记录内容：把双端 `AppRoot` 从“直接删旧 VC、加新 VC”的 child 切换器，升级成显式的转场状态机骨架。
- 记录内容：新增平台侧 `TransitionCarrier` 抽象与 `TransitionSession`，为后续 `SnapshotShellCarrier -> LiveCanvasCarrier` 升级预留边界。
- 记录内容：当前阶段只搭状态机与协调器，不实现真正的 opening / closing 动画。
- 记录依据：本记录基于当前工作树的 `git status --short` 与本次相关文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift`
- 本记录不包含：`Phase 4` 的放大 opening 动画。
- 本记录不包含：`Phase 5` 的缩小 closing 动画。
- 本记录不包含：`LiveCanvasCarrier` 的真实实现。
- 本记录不包含：git commit。

## 修改一：`AppRoot` 从直接切页升级为显式转场状态机骨架

### 修改前

- `display(_:)` 仍然是“根据路由创建 VC -> 直接替换当前 child VC”。
- `handleCanvasOpenRequest(_:)` 直接 `display(.canvas(...))`。
- `handleCanvasReturnRequest(_:)` 虽然已经会向 `BoardList` 预取 `targetGeometry`，但仍然立即 `display(.boardList)`，容器层没有“opening / closing 中间态”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: display(_:) / makeViewController(for:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:) / setCurrentViewController(_:)
// 功能说明: 修改前 iOS AppRoot 仍是直接 child VC 切换器，opening/closing 都没有显式状态机和转场会话。
func display(_ destination: AppLaunchDestination) {
    let viewController = makeViewController(for: destination)
    setCurrentViewController(viewController)
}

private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        viewController.onReturnToBoardList = { [weak self] request in
            self?.handleCanvasReturnRequest(request)
        }
        return viewController
    }
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func setCurrentViewController(_ viewController: UIViewController) {
    if let currentViewController {
        currentViewController.willMove(toParent: nil)
        currentViewController.view.removeFromSuperview()
        currentViewController.removeFromParent()
    }

    addChild(viewController)
    viewController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(viewController.view)
    NSLayoutConstraint.activate([
        viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
        viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    viewController.didMove(toParent: self)
    currentViewController = viewController
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: display(_:) / makeViewController(for:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:) / setCurrentViewController(_:)
// 功能说明: 修改前 macOS AppRoot 与 iOS 同构，也还是直接切换 child VC 的容器。
func display(_ destination: AppLaunchDestination) {
    let viewController = makeViewController(for: destination)
    setCurrentViewController(viewController)
}

private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        viewController.onReturnToBoardList = { [weak self] request in
            self?.handleCanvasReturnRequest(request)
        }
        return viewController
    }
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func setCurrentViewController(_ viewController: NSViewController) {
    if let currentViewController {
        currentViewController.view.removeFromSuperview()
        currentViewController.removeFromParent()
    }

    addChild(viewController)
    viewController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(viewController.view)
    NSLayoutConstraint.activate([
        viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
        viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    currentViewController = viewController
}
```

### 修改后

- 双端 `AppRoot` 都新增：
  - `transitionPhase`
  - `activeTransitionSession`
  - `overlayHostView`
- `display(_:)` 现在只负责“立即展示稳定态页面”；真正的 opening/closing 则改为走 `beginOpeningTransition(...)` / `beginClosingTransition(...)`。
- 这样容器第一次具备了 `idle -> opening -> steadyCanvas -> closing -> steadyBoardList` 这条显式状态链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: transitionPhase / activeTransitionSession / overlayHostView / display(_:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:)
// 功能说明: 修改后 iOS AppRoot 从直接切页升级成显式转场状态机入口，opening/closing 不再走同一条立即切页路径。
private var transitionPhase: iOSBoardListCanvasTransitionPhase = .idle
private var activeTransitionSession: iOSBoardListCanvasTransitionSession?
private let overlayHostView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
}()

func display(_ destination: AppLaunchDestination) {
    discardActiveTransitionIfNeeded()
    let viewController = makeViewController(for: destination)
    setCurrentViewControllerImmediately(viewController)
    transitionPhase = steadyPhase(for: destination)
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    beginOpeningTransition(with: request)
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    beginClosingTransition(with: request)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: transitionPhase / activeTransitionSession / overlayHostView / display(_:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:)
// 功能说明: 修改后 macOS AppRoot 与 iOS 对齐，也通过显式状态机来驱动 opening/closing 容器时序。
private var transitionPhase: macOSBoardListCanvasTransitionPhase = .idle
private var activeTransitionSession: macOSBoardListCanvasTransitionSession?
private let overlayHostView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    return view
}()

func display(_ destination: AppLaunchDestination) {
    discardActiveTransitionIfNeeded()
    let viewController = makeViewController(for: destination)
    setCurrentViewControllerImmediately(viewController)
    transitionPhase = steadyPhase(for: destination)
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    beginOpeningTransition(with: request)
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    beginClosingTransition(with: request)
}
```

## 修改二：新增平台侧 `TransitionCarrier` 抽象，明确 `snapshot shell` 与未来 `live canvas` 的升级边界

### 修改前

- 平台侧还没有专门的 `TransitionCarrier` 文件。
- `AppRoot` 不具备通过统一 carrier 接口来承接转场展示层的能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: 无
// 功能说明: 修改前 iOS 平台侧不存在转场 carrier 抽象文件。
// 修改前不存在
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: 无
// 功能说明: 修改前 macOS 平台侧也不存在转场 carrier 抽象文件。
// 修改前不存在
```

### 修改后

- 双端各自新增 carrier 协议：
  - `install(in:)`
  - `beginTransition(...)`
  - `updateTransitionContext(_:)`
  - `completeTransition()`
  - `cancelTransition()`
- 新增 `CarrierFactory`，当前：
  - `.snapshotShell` -> 真正返回 snapshot shell carrier
  - `.liveCanvas` -> 先显式保留边界，但暂时仍回退到 snapshot shell carrier
- 当前 `SnapshotShellCarrier` 只负责安装/显示一个透明 shell view，不做真实动画，属于 Phase 3 的占位实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrying / iOSBoardListCanvasTransitionCarrierFactory / iOSSnapshotShellCarrier
// 功能说明: 新增 iOS 平台侧转场 carrier 抽象，并用 snapshot shell 作为当前唯一落地实现，同时保留 live canvas 升级边界。
protocol iOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: UIView)
    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    )
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
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

final class iOSSnapshotShellCarrier: iOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: UIView?
    private var shellView: UIView?

    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        shellView?.isHidden = false
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: macOSBoardListCanvasTransitionCarrying / macOSBoardListCanvasTransitionCarrierFactory / macOSSnapshotShellCarrier
// 功能说明: 新增 macOS 平台侧转场 carrier 抽象，并以 snapshot shell 作为当前占位实现。
protocol macOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: NSView)
    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    )
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
}

enum macOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind
    ) -> any macOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return macOSSnapshotShellCarrier()
        case .liveCanvas:
            // Phase 3 keeps the live carrier boundary explicit while
            // still routing through the snapshot shell implementation.
            return macOSSnapshotShellCarrier()
        }
    }
}

final class macOSSnapshotShellCarrier: macOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: NSView?
    private var shellView: NSView?

    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        shellView?.isHidden = false
    }
}
```

## 修改三：新增平台侧 `TransitionSession` / `TransitionPhase`，把容器状态与 carrier 上下文显式建模

### 修改前

- 平台侧没有单独的 transition coordinator/session 文件。
- `AppRoot` 也没有单独建模“当前在哪个转场阶段”“这一轮转场绑定了哪个 carrier / 哪两个 VC / 哪份 context”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: 无
// 功能说明: 修改前 iOS 平台侧不存在 transition phase / transition session 模型文件。
// 修改前不存在
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: 无
// 功能说明: 修改前 macOS 平台侧也不存在 transition phase / transition session 模型文件。
// 修改前不存在
```

### 修改后

- 双端新增 `TransitionPhase` 枚举：
  - `idle`
  - `opening`
  - `steadyCanvas`
  - `closing`
  - `steadyBoardList`
- 双端新增 `TransitionSession`，显式持有：
  - `context`
  - `carrier`
  - `sourceViewController`
  - `destinationViewController`
- 这样 `AppRoot` 后续推进 opening/closing 时，不需要再把这些信息散落在多个局部变量里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionPhase / iOSBoardListCanvasTransitionSession
// 功能说明: 为 iOS 容器转场引入显式 phase 与 session 模型，统一保存当前转场所需的上下文与参与者。
enum iOSBoardListCanvasTransitionPhase: String {
    case idle
    case opening
    case steadyCanvas
    case closing
    case steadyBoardList
}

final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: macOSBoardListCanvasTransitionPhase / macOSBoardListCanvasTransitionSession
// 功能说明: 为 macOS 容器转场引入同构的 phase 与 session 模型。
enum macOSBoardListCanvasTransitionPhase: String {
    case idle
    case opening
    case steadyCanvas
    case closing
    case steadyBoardList
}

final class macOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any macOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: NSViewController?
    weak var destinationViewController: NSViewController?
}
```

## 修改四：`AppRoot` 现在能“保留旧页、隐藏挂载新页、等待目标 ready 再完成切换”

### 修改前

- 容器只有 `setCurrentViewController(...)` 这一条替换路径。
- 旧页会在新页挂上之前立即被移除。
- 返回时虽然能先向 `BoardList` 请求 `targetGeometry`，但容器本身不具备“先保留真实 Canvas，等目标 ready 后再完成切换”的时序能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:) / setCurrentViewController(_:)
// 功能说明: 修改前 iOS 容器没有 opening/closing 的中间态，只能立即替换当前页面。
private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func setCurrentViewController(_ viewController: UIViewController) {
    if let currentViewController {
        currentViewController.willMove(toParent: nil)
        currentViewController.view.removeFromSuperview()
        currentViewController.removeFromParent()
    }
    // ... 省略其余 addChild/约束代码 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:) / setCurrentViewController(_:)
// 功能说明: 修改前 macOS 容器同样没有“先挂新页、暂不接管展示、等待目标 ready”的能力。
private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    let targetBoardID = request.transitionContext.targetBoardID
    boardListViewController.prepareTransitionTargetGeometry(
        for: targetBoardID
    ) { [weak self] geometry in
        self?.updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: targetBoardID
        )
    }
    display(.boardList)
}

private func setCurrentViewController(_ viewController: NSViewController) {
    if let currentViewController {
        currentViewController.view.removeFromSuperview()
        currentViewController.removeFromParent()
    }
    // ... 省略其余 addChild/约束代码 ...
}
```

### 修改后

- opening 流程：
  - 创建 `TransitionSession`
  - 通过 factory 取 carrier
  - 安装 `overlayHostView`
  - 隐藏挂载真实 `CanvasVC`
  - `carrier.beginTransition(...)`
  - 当前阶段先用异步回调立刻完成 `completeOpeningTransition(...)`
- closing 流程：
  - 保留当前 `CanvasVC`
  - 隐藏挂载 `BoardListVC`
  - 先 `prepareForDisplay()`
  - 等 `prepareTransitionTargetGeometry(...)` 返回目标几何
  - 更新 session/context 后再 `completeClosingTransition(...)`
- 同时新增：
  - `mountViewController(...)`
  - `unmountViewController(...)`
  - `discardActiveTransitionIfNeeded()`
  - `steadyPhase(...)`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / completeOpeningTransition(sessionID:) / beginClosingTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / completeClosingTransition(sessionID:)
// 功能说明: 修改后 iOS 容器已经具备 opening/closing 的显式时序，能先保留旧页、隐藏挂载新页，并在 closing 时等待 BoardList 目标几何 ready。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    guard activeTransitionSession == nil else {
        display(.canvas(request.launchContext))
        return
    }

    let sourceViewController = currentViewController ?? boardListViewController
    let destinationViewController = makeCanvasViewController(
        for: request.launchContext
    )
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    let session = iOSBoardListCanvasTransitionSession(
        context: request.transitionContext,
        carrier: carrier,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    activeTransitionSession = session
    transitionPhase = .opening
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    carrier.beginTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    DispatchQueue.main.async { [weak self] in
        self?.completeOpeningTransition(
            sessionID: session.id
        )
    }
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    guard activeTransitionSession == nil else {
        display(.boardList)
        return
    }

    let sourceViewController = currentViewController
    let destinationViewController = boardListViewController
    let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    let session = iOSBoardListCanvasTransitionSession(
        context: request.transitionContext,
        carrier: carrier,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    activeTransitionSession = session
    transitionPhase = .closing
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    destinationViewController.prepareForDisplay()

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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: setupTransitionInfrastructure() / setCurrentViewControllerImmediately(_:) / mountViewController(_:hidden:) / unmountViewController(_:) / discardActiveTransitionIfNeeded()
// 功能说明: iOS 容器新增 overlay host 与 child 挂载/卸载辅助方法，支持转场期保留旧页并隐藏挂载新页。
private func setupTransitionInfrastructure() {
    view.addSubview(overlayHostView)
    NSLayoutConstraint.activate([
        overlayHostView.topAnchor.constraint(equalTo: view.topAnchor),
        overlayHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        overlayHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        overlayHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}

private func setCurrentViewControllerImmediately(
    _ viewController: UIViewController
) {
    if let currentViewController,
       currentViewController !== viewController {
        unmountViewController(currentViewController)
    }

    mountViewController(viewController, hidden: false)
    currentViewController = viewController
}

private func discardActiveTransitionIfNeeded() {
    guard let session = activeTransitionSession else {
        return
    }

    session.carrier.cancelTransition()
    if let destinationViewController = session.destinationViewController,
       destinationViewController !== currentViewController {
        unmountViewController(destinationViewController)
    }
    currentViewController?.view.isHidden = false
    activeTransitionSession = nil
    transitionPhase = steadyPhase(for: currentViewController)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / completeOpeningTransition(sessionID:) / beginClosingTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / completeClosingTransition(sessionID:)
// 功能说明: macOS 容器对齐 iOS，也具备了 opening/closing 的显式时序与目标 ready 等待能力。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    guard activeTransitionSession == nil else {
        display(.canvas(request.launchContext))
        return
    }

    let sourceViewController = currentViewController ?? boardListViewController
    let destinationViewController = makeCanvasViewController(
        for: request.launchContext
    )
    let carrier = macOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    let session = macOSBoardListCanvasTransitionSession(
        context: request.transitionContext,
        carrier: carrier,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    activeTransitionSession = session
    transitionPhase = .opening
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    carrier.beginTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    DispatchQueue.main.async { [weak self] in
        self?.completeOpeningTransition(
            sessionID: session.id
        )
    }
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    guard activeTransitionSession == nil else {
        display(.boardList)
        return
    }

    let sourceViewController = currentViewController
    let destinationViewController = boardListViewController
    let carrier = macOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
        preferredKind: request.preferredCarrierKind
    )
    let session = macOSBoardListCanvasTransitionSession(
        context: request.transitionContext,
        carrier: carrier,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )

    activeTransitionSession = session
    transitionPhase = .closing
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    destinationViewController.prepareForDisplay()

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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: setupTransitionInfrastructure() / setCurrentViewControllerImmediately(_:) / mountViewController(_:hidden:) / unmountViewController(_:) / discardActiveTransitionIfNeeded()
// 功能说明: macOS 容器新增 overlay host 与 child 挂载/卸载辅助方法，为后续 carrier 动画接管提供容器基础设施。
private func setupTransitionInfrastructure() {
    view.addSubview(overlayHostView)
    NSLayoutConstraint.activate([
        overlayHostView.topAnchor.constraint(equalTo: view.topAnchor),
        overlayHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        overlayHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        overlayHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}

private func setCurrentViewControllerImmediately(
    _ viewController: NSViewController
) {
    if let currentViewController,
       currentViewController !== viewController {
        unmountViewController(currentViewController)
    }

    mountViewController(viewController, hidden: false)
    currentViewController = viewController
}

private func discardActiveTransitionIfNeeded() {
    guard let session = activeTransitionSession else {
        return
    }

    session.carrier.cancelTransition()
    if let destinationViewController = session.destinationViewController,
       destinationViewController !== currentViewController {
        unmountViewController(destinationViewController)
    }
    currentViewController?.view.isHidden = false
    activeTransitionSession = nil
    transitionPhase = steadyPhase(for: currentViewController)
}
```

## 行为结果

- `AppRoot` 现在已经不再是单纯的 child VC 替换器，而是具备了显式的转场状态机骨架。
- opening 时，容器已经能做到“保留 `BoardList`、隐藏挂载真实 `Canvas`、再完成切换”。
- closing 时，容器已经能做到“保留真实 `Canvas`、隐藏挂载 `BoardList`、等待 `targetGeometry` ready 后再完成切换”。
- `TransitionCarrier` 的平台边界已经显式建好，后续 `LiveCanvasCarrier` 只需要替换 carrier 层和对应上下文要求，不需要重做 `BoardList` source/target provider，也不需要推翻 `AppRoot` 状态机。
- 当前 `SnapshotShellCarrier` 仍是占位实现：它只负责安装/显示 shell view，不承担真正动画，这与 `Phase 3`“先搭协调器，不做动画”的目标一致。

## 校验结果

- 当前工作树在记录前的相关变更为：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift`
- 已通过 `ReadLints` 检查以下目录，未发现新的 lint 错误：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot`
- 已执行并通过以下语法解析命令：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift" "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift" "MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift" "MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"`
- iOS 侧本轮仍以 IDE lint 结果为主，没有额外执行完整 iOS SDK 编译解析。

## 后续衔接

- `Phase 4` 可以直接在当前 `SnapshotShellCarrier.beginTransition(...)` / `updateTransitionContext(...)` 上接 opening 放大动画。
- `Phase 5` 可以直接复用当前 closing 时序，把 `targetGeometry` 真正用于缩回目标卡片。
- 如果未来升级到 `LiveCanvasCarrier`，当前 `TransitionPhase`、`TransitionSession`、`overlayHostView`、`mount/unmount` 辅助方法都可以继续复用。
