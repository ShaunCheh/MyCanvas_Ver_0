# 20260409_104208_boardlist_zoom_transition_phase6_input_freeze_shared_config_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 6`，补齐转场期间的输入冻结。
- 记录内容：新增共享 `transition configuration`，把 opening / closing / handoff 的时长、曲线、圆角、阴影和 fallback scale 统一收口。
- 记录内容：让 `AppRoot` 在 opening / closing / discard 生命周期里统一驱动 `BoardList` 与 `Canvas` 的冻结和恢复。
- 记录内容：让双端 `BoardList` 与 `Canvas` 自己感知冻结状态，而不是只依赖顶层 overlay 遮罩。
- 记录内容：新增 macOS 专用的透明交互屏蔽层，用来吞掉鼠标、滚轮、缩放与 swipe 事件。
- 记录依据：本记录基于当前工作树的 `git status --short`、本次相关文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionConfiguration.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSTransitionInteractionShieldView.swift`
- 本记录复用但未改动的链路：`BoardList` source / target geometry 解析链。
- 本记录复用但未改动的链路：`AppRoot` 的 opening / closing 状态机基本结构。
- 本记录复用但未改动的链路：`Canvas` 返回 `BoardList` 时的新建板持久化链。
- 本记录不包含：`LiveCanvasCarrier` 的真实实现。
- 本记录不包含：方案 B 的“真实 Canvas 一直保留到 target ready 再缩回”的容器时序实现。
- 本记录不包含：git commit。

## 修改一：把转场常量和曲线收口为共享配置，并补出可复用的冻结协议

### 修改前

- `iOS` / `macOS` 的 `SnapshotShellCarrier` 各自维护一套私有常量。
- `AppRoot` 的 coordinator 只有 `phase + session`，还没有向 `BoardList` / `Canvas` 下发“转场期冻结输入”的协议边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSSnapshotShellCarrier
// 功能说明: 修改前 iOS carrier 把 opening / closing / handoff 时长、圆角、阴影和 fallback scale 全都写死在本地静态常量里。
final class iOSSnapshotShellCarrier: iOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: UIView?
    private var shellContentView: UIView?
    private static let openingDuration: TimeInterval = 0.38
    private static let closingDuration: TimeInterval = 0.32
    private static let handoffDuration: TimeInterval = 0.14
    private static let shellCornerRadius: CGFloat = 12
    private static let shellShadowOpacity: Float = 0.08
    private static let shellShadowRadius: CGFloat = 16
    private static let shellShadowOffset = CGSize(width: 0, height: 8)
    private static let fallbackClosingScale: CGFloat = 0.82
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionPhase / iOSBoardListCanvasTransitionSession
// 功能说明: 修改前 coordinator 只描述转场 phase 和 session，本身还没有暴露输入冻结协议。
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

### 修改后

- 新增共享 `BoardListCanvasTransitionConfiguration`，将双端 snapshot shell 动画参数统一收口。
- 新增 `iOSBoardListCanvasTransitionInteractionControlling` / `macOSBoardListCanvasTransitionInteractionControlling`，为 `AppRoot -> BoardList / Canvas` 的冻结下发提供稳定边界。
- 双端 carrier 已改为消费共享配置，不再各写一套时间与视觉常量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionConfiguration.swift
// 函数名/符号名: BoardListCanvasTransitionTimingCurve / BoardListCanvasTransitionAnimationConfiguration / BoardListCanvasTransitionConfiguration
// 功能说明: 新增共享转场配置，把时长、曲线、圆角、阴影与 fallback scale 统一收口，供 iOS / macOS carrier 共同消费。
import CoreGraphics
import Foundation

enum BoardListCanvasTransitionTimingCurve: Hashable {
    case easeInOut
    case easeOut
}

struct BoardListCanvasTransitionAnimationConfiguration: Hashable {
    var duration: TimeInterval
    var curve: BoardListCanvasTransitionTimingCurve
    var springDampingRatio: CGFloat?
    var springInitialVelocity: CGFloat?
}

enum BoardListCanvasTransitionConfiguration {
    static let openingAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.38,
        curve: .easeInOut,
        springDampingRatio: 0.94,
        springInitialVelocity: 0
    )
    static let closingAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.32,
        curve: .easeInOut
    )
    static let handoffAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.14,
        curve: .easeOut
    )
    static let shellCornerRadius: CGFloat = 12
    static let shellShadowOpacity: Float = 0.08
    static let shellShadowRadius: CGFloat = 16
    static let iOSShellShadowOffset = CGSize(width: 0, height: 8)
    static let macOSShellShadowOffset = CGSize(width: 0, height: -8)
    static let fallbackClosingScale: CGFloat = 0.82
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: iOSBoardListCanvasTransitionInteractionControlling
// 功能说明: iOS coordinator 现在明确要求参与方实现冻结接口，AppRoot 可以统一下发 freeze / unfreeze。
protocol iOSBoardListCanvasTransitionInteractionControlling: AnyObject {
    func setTransitionInteractionFrozen(_ isFrozen: Bool)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift
// 函数名/符号名: macOSBoardListCanvasTransitionInteractionControlling
// 功能说明: macOS coordinator 与 iOS 同构，后续方案 B 继续复用这一层协议边界即可。
protocol macOSBoardListCanvasTransitionInteractionControlling: AnyObject {
    func setTransitionInteractionFrozen(_ isFrozen: Bool)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateOpeningTransition(completion:) / animateClosingTransition(completion:) / configureShadow(for:opacity:) / animationOptions(for:)
// 功能说明: 修改后 iOS carrier 直接消费共享配置，不再引用本地私有常量；curve 到 AnimationOptions 的映射也集中在一个 helper 里。
private func animateOpeningTransition(completion: @escaping () -> Void) {
    // ... 省略前置 guard ...
    UIView.animate(
        withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
        delay: 0,
        usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
        initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
        options: [.beginFromCurrentState, animationOptions(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)]
    ) {
        shellShadowView.frame = targetFrame
        shellContentView.layer.cornerRadius = 0
        shellShadowView.layer.shadowOpacity = 0
    }
}

private func configureShadow(
    for shadowView: UIView,
    opacity: Float
) {
    shadowView.layer.shadowOpacity = opacity
    shadowView.layer.shadowRadius = BoardListCanvasTransitionConfiguration.shellShadowRadius
    shadowView.layer.shadowOffset = BoardListCanvasTransitionConfiguration.iOSShellShadowOffset
}

private func animationOptions(
    for curve: BoardListCanvasTransitionTimingCurve
) -> UIView.AnimationOptions {
    switch curve {
    case .easeInOut:
        return .curveEaseInOut
    case .easeOut:
        return .curveEaseOut
    }
}
```

## 修改二：AppRoot 不再只管理 overlay，而是在 opening / closing / discard 生命周期统一驱动冻结

### 修改前

- `AppRoot` 只负责 `overlayHostView`、`carrier.install(...)`、`mount/unmount` 与 `phase` 切换。
- opening / closing 期间，`sourceViewController` 与 `destinationViewController` 没有收到任何冻结通知。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / completeOpeningTransition(sessionID:) / beginClosingTransition(with:) / discardActiveTransitionIfNeeded()
// 功能说明: 修改前 iOS AppRoot 只切换 overlay 与 view controller，不会主动通知 BoardList / Canvas 冻结输入。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .opening
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
}

private func completeOpeningTransition(sessionID: UUID) {
    // ... 省略 guard 与 source 卸载逻辑 ...
    destinationViewController.view.isHidden = false
    currentViewController = destinationViewController
    session.carrier.completeTransition()
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .closing
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
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
}
```

### 修改后

- `beginOpeningTransition` / `beginClosingTransition` 一开始就冻结 source 与 destination。
- `completeOpeningTransition` / `completeClosingTransition` / `discardActiveTransitionIfNeeded` 都会显式恢复冻结状态。
- `setCurrentViewControllerImmediately` 也会把直接展示路径上的控制器恢复成非冻结态，避免 fallback `display(...)` 后残留冻结。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / completeOpeningTransition(sessionID:) / beginClosingTransition(with:) / discardActiveTransitionIfNeeded() / setTransitionInteractionFrozen(_:for:)
// 功能说明: 修改后 iOS AppRoot 在 opening / closing / discard 全链路统一驱动 freeze / unfreeze，输入管理不再只依赖顶层 overlay。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .opening
    setTransitionInteractionFrozen(true, for: sourceViewController)
    setTransitionInteractionFrozen(true, for: destinationViewController)
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
}

private func completeOpeningTransition(sessionID: UUID) {
    // ... 省略 guard 与 source 卸载逻辑 ...
    destinationViewController.view.isHidden = false
    setTransitionInteractionFrozen(false, for: session.sourceViewController)
    setTransitionInteractionFrozen(false, for: destinationViewController)
    currentViewController = destinationViewController
    session.carrier.completeTransition()
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .closing
    setTransitionInteractionFrozen(true, for: sourceViewController)
    setTransitionInteractionFrozen(true, for: destinationViewController)
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
}

private func discardActiveTransitionIfNeeded() {
    guard let session = activeTransitionSession else {
        return
    }

    session.carrier.cancelTransition()
    setTransitionInteractionFrozen(false, for: session.sourceViewController)
    setTransitionInteractionFrozen(false, for: session.destinationViewController)
    // ... 省略 destination cleanup ...
}

private func setTransitionInteractionFrozen(
    _ isFrozen: Bool,
    for viewController: UIViewController?
) {
    (viewController as? any iOSBoardListCanvasTransitionInteractionControlling)?
        .setTransitionInteractionFrozen(isFrozen)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / beginClosingTransition(with:) / setTransitionInteractionFrozen(_:for:)
// 功能说明: macOS AppRoot 与 iOS 同构，也在 opening / closing 入口显式冻结 source / destination。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .opening
    setTransitionInteractionFrozen(true, for: sourceViewController)
    setTransitionInteractionFrozen(true, for: destinationViewController)
    activateTransitionOverlay()
}

private func beginClosingTransition(
    with request: BoardListCanvasReturnRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .closing
    setTransitionInteractionFrozen(true, for: sourceViewController)
    setTransitionInteractionFrozen(true, for: destinationViewController)
    activateTransitionOverlay()
}

private func setTransitionInteractionFrozen(
    _ isFrozen: Bool,
    for viewController: NSViewController?
) {
    (viewController as? any macOSBoardListCanvasTransitionInteractionControlling)?
        .setTransitionInteractionFrozen(isFrozen)
}
```

## 修改三：BoardList 把“列表输入冻结”内化到控制器自身

### 修改前

- `BoardList` 只根据文件夹选择状态和存储错误控制 UI，可在转场中继续点击卡片、打开占位板、切换列表/网格、打开重命名面板。
- macOS 的双击打开与选中回调也不感知转场中间态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: updateDisplayModeControlState() / performPrimaryAction(for:) / handleSelectFolderButtonTap() / handleDisplayModeChange()
// 功能说明: 修改前 iOS BoardList 既没有冻结状态，也没有任何 guard；只要 view 还在层级里，就还能继续响应列表输入。
private func updateDisplayModeControlState() {
    displayModeControl.isEnabled =
        hasSelectedFolder &&
        storageErrorMessage == nil
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

    onOpenCanvas?(makeOpenRequest(for: entry))
}

@objc
private func handleSelectFolderButtonTap() {
    dismissActionPanel()
    folderPicker.present(from: self) { [weak self] result in
        // ... 省略原有 folder picker 处理 ...
    }
}

@objc
private func handleDisplayModeChange() {
    dismissActionPanel()
    displayMode = BoardListDisplayMode(segmentIndex: displayModeControl.selectedSegmentIndex)
}
```

### 修改后

- `iOSBoardListViewController` 新增 `isTransitionInteractionFrozen`、透明 `transitionInteractionShieldView`、`setTransitionInteractionFrozen(_:)` 与 `applyTransitionInteractionFreeze()`。
- 冻结时会关闭 action panel、禁用 folder 选择按钮、禁用 display mode、禁止列表滚动，并在 `performPrimaryAction` / `handleSelectFolderButtonTap` / `handleDisplayModeChange` / `performBoardAction` / `didSelectItemAt` 入口统一短路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: viewDidLoad() / setTransitionInteractionFrozen(_:) / updateDisplayModeControlState() / applyTransitionInteractionFreeze() / performPrimaryAction(for:)
// 功能说明: 修改后 iOS BoardList 自身就能进入冻结态，转场中不会再继续滚动、切换显示模式、选文件夹或打开画板。
final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, iOSBoardListCanvasTransitionInteractionControlling {
    private var pendingTransitionTargetResolution: PendingTransitionTargetResolution?
    private var isTransitionInteractionFrozen = false
    private let actionPanelHostView = BoardListActionPanelHostView()
    private let transitionInteractionShieldView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        setupActionPanelHostView()
        refreshBookmarkStatus()
        applyTransitionInteractionFreeze()
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

    private func performPrimaryAction(for entry: BoardListEntry) {
        guard isTransitionInteractionFrozen == false else {
            return
        }

        dismissActionPanel()
        // ... 省略原有 hasSelectedFolder / storageError / editingBoardID guard ...
        onOpenCanvas?(makeOpenRequest(for: entry))
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: applyTransitionInteractionFreeze() / performPrimaryAction(for:) / handleSelectFolderButtonClick() / handleDisplayModeChange() / handleCollectionViewDoubleClick(_:)
// 功能说明: 修改后 macOS BoardList 除了禁用选择与按钮，还会阻断双击打开和 selection 回调，避免转场中途再次发起导航。
private func applyTransitionInteractionFreeze() {
    transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
    selectFolderButton.isEnabled = isTransitionInteractionFrozen == false
    collectionView.isSelectable = isTransitionInteractionFrozen == false
    if isTransitionInteractionFrozen {
        dismissActionPanel()
    }
    updateDisplayModeControlState()
}

private func performPrimaryAction(for entry: BoardListEntry) {
    guard isTransitionInteractionFrozen == false else {
        return
    }

    dismissActionPanel()
    // ... 省略原有打开逻辑 ...
    onOpenCanvas?(makeOpenRequest(for: entry))
}

@objc
private func handleSelectFolderButtonClick() {
    guard isTransitionInteractionFrozen == false else {
        return
    }
    dismissActionPanel()
    // ... 省略原有 file picker 处理 ...
}

@objc
private func handleDisplayModeChange() {
    guard isTransitionInteractionFrozen == false else {
        return
    }
    dismissActionPanel()
    // ... 省略原有 display mode 切换逻辑 ...
}

@objc
private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
    guard
        isTransitionInteractionFrozen == false,
        gestureRecognizer.state == .ended
    else {
        return
    }

    // ... 省略原有 indexPath / entry 解析 ...
    performPrimaryAction(for: entry)
}
```

## 修改四：Canvas 把命令、手势、导入链和 context menu 全部纳入冻结态

### 修改前

- `Canvas` 只在 reading mode 下禁掉一部分入口，转场期依旧可以继续走 `performCommand`、viewport pointer 回调、paste、drag/drop。
- 这意味着即使 `AppRoot` 顶层有 overlay，`Canvas` 内部的旁路输入链也没有统一收口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: performCommand(_:) / setupCanvasViewport() / dropInteraction(_:canHandle:) / canTransferContent(from:) / performTransferRequest(_:)
// 功能说明: 修改前 iOS Canvas 只判断 reading mode，不知道自己是否处于转场冻结期。
private func performCommand(_ command: CanvasCommand) {
    if command.id != .commitTextEdit,
       isInlineTextModeActive,
       workspaceMode == .editing
    {
        performCommand(.commitTextEdit)
    }

    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()
    // ... 省略执行逻辑 ...
}

private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    // ... 省略导入 lower / execute ...
    return true
}
```

### 修改后

- `iOSViewController` 与 `macOSViewController` 现在都实现了转场冻结协议。
- 冻结时不仅会显示本地透明屏蔽层，还会主动 `dismissContextMenu()`、取消 pointer 交互、阻断 `performCommand`、阻断 viewport 回调、阻断 paste / drag / import。
- macOS 额外会在冻结时 `makeFirstResponder(nil)`，解冻后把焦点还给 `canvasViewportView`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: performCommand(_:) / applyTransitionInteractionFreeze() / setTransitionInteractionFrozen(_:) / setupCanvasViewport()
// 功能说明: 修改后 iOS Canvas 不再只依赖顶层 overlay；自身会感知冻结态，并把 command、pointer、context menu 一起收住。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate, iOSBoardListCanvasTransitionInteractionControlling {
    private let transitionInteractionShieldView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()
    private var pointerDragState: PointerDragState = .idle
    private var isTransitionInteractionFrozen = false

    private func performCommand(_ command: CanvasCommand) {
        guard isTransitionInteractionFrozen == false else {
            return
        }

        // ... 省略原有 commitTextEdit / execute 逻辑 ...
    }

    private func applyTransitionInteractionFreeze() {
        transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
        textEditorOverlayView.isUserInteractionEnabled = isTransitionInteractionFrozen == false
        if isTransitionInteractionFrozen {
            dismissContextMenu()
            handlePrimaryPointerCancel()
        }
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

    private func setupCanvasViewport() {
        canvasViewportView.onPointerDown = { [weak self] location in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerDown(at: location)
        }
        canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerMove(to: location, from: previousLocation)
        }
        canvasViewportView.onPointerUp = { [weak self] location in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handlePrimaryPointerUp(at: location)
        }
        canvasViewportView.onLongPress = { [weak self] location in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleLongPress(at: location)
        }
        canvasViewportView.onPan = { [weak self] translation in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleIndirectPan(translation)
        }
        canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
            guard self?.isTransitionInteractionFrozen == false else {
                return
            }
            self?.handleZoom(scaleDelta, around: anchor)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: dropInteraction(_:canHandle:) / dropInteraction(_:sessionDidUpdate:) / dropInteraction(_:performDrop:) / canTransferContent(from:) / performTransferRequest(_:)
// 功能说明: 修改后 iOS 的导入链也会检查冻结态，避免转场中通过 paste / drag and drop 再次写入真实 board。
func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    isTransitionInteractionFrozen == false &&
        isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    sessionDidUpdate session: UIDropSession
) -> UIDropProposal {
    if isTransitionInteractionFrozen == false,
       isReadingModeActive == false,
       iOSCanvasImportAdapter.canResolveTransfer(from: session)
    {
        return UIDropProposal(operation: .copy)
    }

    return UIDropProposal(operation: .cancel)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    performDrop session: UIDropSession
) {
    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        guard
            self.isTransitionInteractionFrozen == false,
            self.isReadingModeActive == false
        else {
            return
        }

        // ... 省略 transferRequest 解析 ...
        _ = self.performTransferRequest(transferRequest)
    }
}

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    isTransitionInteractionFrozen == false &&
        isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard
        isTransitionInteractionFrozen == false,
        isReadingModeActive == false
    else {
        return false
    }

    // ... 省略原有导入执行逻辑 ...
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: performCommand(_:) / applyTransitionInteractionFreeze() / canPerformCommand(_:) / paste(_:) / canTransferContent(from:) / handleImportDrop(pasteboard:) / performTransferRequest(_:)
// 功能说明: 修改后 macOS Canvas 除了阻断命令和导入链，还会在冻结时主动释放 first responder，解冻后再把焦点还给 viewport。
private func performCommand(_ command: CanvasCommand) {
    guard isTransitionInteractionFrozen == false else {
        return
    }

    // ... 省略原有执行逻辑 ...
}

private func applyTransitionInteractionFreeze() {
    transitionInteractionShieldView.isHidden = isTransitionInteractionFrozen == false
    if isTransitionInteractionFrozen {
        dismissContextMenu()
        handlePrimaryPointerCancel()
        view.window?.makeFirstResponder(nil)
    } else if view.window != nil, view.isHidden == false {
        view.window?.makeFirstResponder(canvasViewportView)
    }
}

func canPerformCommand(_ commandID: CanvasCommandID) -> Bool {
    isTransitionInteractionFrozen == false &&
        commandDescriptor(for: commandID).isEnabled
}

@objc
func paste(_ sender: Any?) {
    guard isTransitionInteractionFrozen == false else {
        return
    }

    handlePasteRequest()
}

private func canTransferContent(from pasteboard: NSPasteboard) -> Bool {
    isTransitionInteractionFrozen == false &&
        isReadingModeActive == false &&
        macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func handleImportDrop(
    pasteboard: NSPasteboard
) -> Bool {
    guard
        isTransitionInteractionFrozen == false,
        isReadingModeActive == false
    else {
        return false
    }

    // ... 省略原有 transferRequest 构建 ...
    let didImport = performTransferRequest(transferRequest)
    if didImport {
        view.window?.makeFirstResponder(canvasViewportView)
    }
    return didImport
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard
        isTransitionInteractionFrozen == false,
        isReadingModeActive == false
    else {
        return false
    }

    // ... 省略原有导入执行逻辑 ...
    return true
}
```

## 修改五：新增 macOS 专用的交互屏蔽层，补齐鼠标 / 滚轮 / 缩放的吞事件能力

### 修改前

- `macOS` 侧没有独立的透明拦截 view。
- `BoardList` 和 `Canvas` 就算在视觉上被别的层盖住，也没有一块明确的本地 `NSView` 用来吞掉鼠标、滚轮、magnify、swipe 等事件。

### 修改后

- 新增 `macOSTransitionInteractionShieldView.swift`，作为 `BoardList` 与 `Canvas` 的共用冻结底座。
- 这个 view 在 `isHidden == false` 时通过 `hitTest(_:) -> self` 抢到事件，并把鼠标、滚轮、缩放和 swipe 全部吞掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSTransitionInteractionShieldView.swift
// 函数名/符号名: macOSTransitionInteractionShieldView / hitTest(_:) / acceptsFirstMouse(for:) / scrollWheel(with:) / magnify(with:) / swipe(with:)
// 功能说明: 新增 macOS 专用的透明交互屏蔽层，在可见时吞掉鼠标、滚轮、缩放与 swipe，为 BoardList / Canvas 的冻结态提供平台级底座。
#if os(macOS)
import AppKit

final class macOSTransitionInteractionShieldView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isHidden == false else {
            return nil
        }

        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
}
#endif
```

## 阶段结果与方案 B 升级边界核对

- 本轮没有回退或重做 `Phase 1` 到 `Phase 5` 已建立的 `BoardList source / target geometry`、`AppRoot` 状态机、返回持久化链与 reveal 链。
- 本轮新增的是“共享配置 + freeze protocol + 本地屏蔽层 + 各参与方 guard”，这些恰好也是未来方案 B 继续保留真实 `CanvasVC` 时所需要的基础保护。
- 从结构上看，后续升级到方案 B 时，仍然只需要把 `SnapshotShellCarrier` 换成 `LiveCanvasCarrier`，并把 closing 时对真实 `CanvasVC` 的保留时序接进现有冻结协议即可。

## 验证

- 已对本轮相关文件执行 `ReadLints`，无报错。
- 已执行 `xcrun --sdk macosx swiftc -frontend -parse` 对本轮相关 Swift 文件进行语法检查，通过。
- 已核对 `git status --short`，本轮涉及文件为：
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCoordinator.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionConfiguration.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSTransitionInteractionShieldView.swift`
- 未执行 git commit。
