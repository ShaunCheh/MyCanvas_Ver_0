# 20260409_095531_boardlist_zoom_transition_phase4_opening_snapshot_shell_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 4`，实现方案 C 的 opening 放大动画。
- 记录内容：把双端 `SnapshotShellCarrier` 从“透明占位壳”升级为“可准备 snapshot shell、可执行 opening 动画、可在末尾 handoff 给真实 canvas”的 carrier。
- 记录内容：把双端 `AppRoot` 从“开始转场后下一帧直接 complete”升级为“等待 carrier 动画完成后再进入 steady state”。
- 记录依据：本记录基于当前工作树的 `git status --short`、本次相关文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 本记录不包含：`Phase 5` 的返回缩小动画。当前 closing 方向虽然已经接入统一生命周期，但 carrier 仍未执行真实缩小动画。
- 本记录不包含：`LiveCanvasCarrier` 的真实实现。
- 本记录不包含：git commit。

## 修改一：`TransitionCarrier` 从占位 `beginTransition` 升级为 `prepare + animate` 生命周期

### 修改前

- 双端 carrier 协议都只有 `beginTransition(...)` 一个启动入口。
- `SnapshotShellCarrier` 只会安装一个全屏透明壳，并在 `beginTransition(...)` 里把它显示出来。
- 这意味着 `AppRoot` 只能“调用 begin -> 下一帧自己 complete”，carrier 还没有真正掌控动画时机。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrying / iOSSnapshotShellCarrier.install(in:) / beginTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改前 iOS carrier 只有单个 beginTransition 入口，snapshot shell 只是一个透明全屏占位层，不承担真正的 opening 动画。
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

final class iOSSnapshotShellCarrier: iOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: UIView?
    private var shellView: UIView?

    func install(in overlayHostView: UIView) {
        if self.overlayHostView !== overlayHostView {
            cleanupShellView()
            self.overlayHostView = overlayHostView
        }

        guard shellView == nil else {
            return
        }

        let shellView = UIView()
        shellView.translatesAutoresizingMaskIntoConstraints = false
        shellView.isUserInteractionEnabled = false
        shellView.backgroundColor = .clear
        shellView.isHidden = true
        overlayHostView.addSubview(shellView)
        NSLayoutConstraint.activate([
            shellView.topAnchor.constraint(equalTo: overlayHostView.topAnchor),
            shellView.leadingAnchor.constraint(equalTo: overlayHostView.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: overlayHostView.trailingAnchor),
            shellView.bottomAnchor.constraint(equalTo: overlayHostView.bottomAnchor)
        ])
        self.shellView = shellView
    }

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
// 函数名/符号名: macOSBoardListCanvasTransitionCarrying / macOSSnapshotShellCarrier.install(in:) / beginTransition(with:sourceViewController:destinationViewController:)
// 功能说明: 修改前 macOS carrier 与 iOS 同构，也只有一个 beginTransition 入口，无法把 prepare/animate/handoff 明确拆开。
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

final class macOSSnapshotShellCarrier: macOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: NSView?
    private var shellView: NSView?

    func install(in overlayHostView: NSView) {
        if self.overlayHostView !== overlayHostView {
            cleanupShellView()
            self.overlayHostView = overlayHostView
        }

        guard shellView == nil else {
            return
        }

        let shellView = NSView()
        shellView.translatesAutoresizingMaskIntoConstraints = false
        shellView.wantsLayer = true
        shellView.layer?.backgroundColor = NSColor.clear.cgColor
        shellView.isHidden = true
        overlayHostView.addSubview(shellView)
        NSLayoutConstraint.activate([
            shellView.topAnchor.constraint(equalTo: overlayHostView.topAnchor),
            shellView.leadingAnchor.constraint(equalTo: overlayHostView.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: overlayHostView.trailingAnchor),
            shellView.bottomAnchor.constraint(equalTo: overlayHostView.bottomAnchor)
        ])
        self.shellView = shellView
    }

    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        shellView?.isHidden = false
    }
}
```

### 修改后

- 双端 carrier 协议都被拆成：
  - `prepareTransition(...)`
  - `animateTransition(completion:)`
  - `updateTransitionContext(...)`
- `SnapshotShellCarrier` 新增：
  - `currentContext`
  - `sourceViewController`
  - `destinationViewController`
  - `shellShadowView`
  - `shellContentView`
- 这样 `AppRoot` 可以先让 carrier 基于 `sourceGeometry` 组装 shell，再由 carrier 自己决定动画何时结束并回调 completion。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: iOSBoardListCanvasTransitionCarrying / prepareTransition(with:sourceViewController:destinationViewController:) / animateTransition(completion:)
// 功能说明: 修改后 iOS carrier 拥有显式的 prepare + animate 生命周期，AppRoot 可以等待动画回调而不是自己抢先 complete。
protocol iOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: UIView)
    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    )
    func animateTransition(completion: @escaping () -> Void)
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
}

final class iOSSnapshotShellCarrier: iOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: UIView?
    private var shellContentView: UIView?
    private static let openingDuration: TimeInterval = 0.38
    private static let handoffDuration: TimeInterval = 0.14
    private static let openingCornerRadius: CGFloat = 12

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        guard context.direction == .opening else {
            return
        }

        prepareOpeningShell(using: context)
    }

    func animateTransition(completion: @escaping () -> Void) {
        guard let context = currentContext else {
            completion()
            return
        }

        switch context.direction {
        case .opening:
            animateOpeningTransition(completion: completion)
        case .closing:
            completion()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: macOSBoardListCanvasTransitionCarrying / prepareTransition(with:sourceViewController:destinationViewController:) / animateTransition(completion:)
// 功能说明: 修改后 macOS carrier 与 iOS 保持同一套生命周期，后续 closing 缩回动画和 LiveCanvasCarrier 都可以走同一接口。
protocol macOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: NSView)
    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    )
    func animateTransition(completion: @escaping () -> Void)
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
}

final class macOSSnapshotShellCarrier: macOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: NSView?
    private weak var sourceViewController: NSViewController?
    private weak var destinationViewController: NSViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: NSView?
    private var shellContentView: NSView?
    private static let openingDuration: TimeInterval = 0.38
    private static let handoffDuration: TimeInterval = 0.14
    private static let openingCornerRadius: CGFloat = 12

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        guard context.direction == .opening else {
            return
        }

        prepareOpeningShell(using: context)
    }

    func animateTransition(completion: @escaping () -> Void) {
        guard let context = currentContext else {
            completion()
            return
        }

        switch context.direction {
        case .opening:
            animateOpeningTransition(completion: completion)
        case .closing:
            completion()
        }
    }
}
```

## 修改二：`SnapshotShellCarrier` 从透明占位壳升级为真实 opening snapshot shell

### 修改前

- 修改前的 `SnapshotShellCarrier` 没有：
  - source rect -> fullscreen 的几何动画
  - 卡片快照内容
  - 圆角/阴影/背景壳
  - 动画结束后的 handoff 淡入
- 它只是显示一个透明的全屏壳，视觉上仍然是瞬时切页。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: beginTransition(with:sourceViewController:destinationViewController:) / cleanupShellView()
// 功能说明: 修改前 iOS snapshot shell 不生成卡片快照，也不执行放大动画；complete/cancel 只是直接删掉透明壳。
func beginTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: UIViewController?,
    destinationViewController: UIViewController?
) {
    shellView?.isHidden = false
}

func completeTransition() {
    cleanupShellView()
}

func cancelTransition() {
    cleanupShellView()
}

private func cleanupShellView() {
    shellView?.removeFromSuperview()
    shellView = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: beginTransition(with:sourceViewController:destinationViewController:) / cleanupShellView()
// 功能说明: 修改前 macOS snapshot shell 也只是一个透明 overlay，占位意义大于动画意义。
func beginTransition(
    with context: BoardListCanvasTransitionContext,
    sourceViewController: NSViewController?,
    destinationViewController: NSViewController?
) {
    shellView?.isHidden = false
}

func completeTransition() {
    cleanupShellView()
}

func cancelTransition() {
    cleanupShellView()
}

private func cleanupShellView() {
    shellView?.removeFromSuperview()
    shellView = nil
}
```

### 修改后

- iOS 侧：
  - 在 `prepareOpeningShell(using:)` 里把 `sourceGeometry.cardRect` 转到 `overlayHostView` 坐标系。
  - 使用 `resizableSnapshotView(from:afterScreenUpdates:withCapInsets:)` 截取来源卡片快照。
  - 构建 `shadowView + contentView` 两层壳，补齐圆角、背景、阴影。
  - 在 `animateOpeningTransition(completion:)` 里先执行 `sourceRect -> overlayHostView.bounds` 的弹簧放大，再让真实 `destinationView` 淡入接管。
- macOS 侧：
  - 用 `bitmapImageRepForCachingDisplay` + `cacheDisplay` 构建 `NSImageView` 快照。
  - 用 `NSAnimationContext` 做放大和 handoff。
- closing 方向在本阶段仍不做真实缩小动画，因此 `animateTransition(completion:)` 的 `.closing` 分支仍直接 `completion()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningShell(using:) / animateOpeningTransition(completion:) / removeShellViews() / resetTransitionState()
// 功能说明: 修改后 iOS snapshot shell 会基于来源卡片真实几何生成快照壳，执行 opening 放大，再将展示权交给真实 CanvasVC.view。
private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
    removeShellViews()
    guard
        let overlayHostView,
        let sourceViewController,
        let sourceRect = context.sourceGeometry.cardRect
    else {
        return
    }

    overlayHostView.layoutIfNeeded()
    sourceViewController.view.layoutIfNeeded()

    let convertedSourceRect = overlayHostView.convert(
        sourceRect,
        from: sourceViewController.view
    ).standardized
    guard convertedSourceRect.isEmpty == false else {
        return
    }

    let shadowView = UIView(frame: convertedSourceRect)
    shadowView.backgroundColor = .clear
    shadowView.isUserInteractionEnabled = false
    shadowView.layer.shadowColor = UIColor.black.cgColor
    shadowView.layer.shadowOpacity = 0.08
    shadowView.layer.shadowRadius = 16
    shadowView.layer.shadowOffset = CGSize(width: 0, height: 8)

    let contentView = UIView(frame: shadowView.bounds)
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contentView.backgroundColor = .secondarySystemBackground
    contentView.layer.cornerRadius = Self.openingCornerRadius
    contentView.layer.masksToBounds = true

    if let snapshotView = sourceViewController.view.resizableSnapshotView(
        from: sourceRect,
        afterScreenUpdates: false,
        withCapInsets: .zero
    ) {
        snapshotView.frame = contentView.bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(snapshotView)
    }

    shadowView.addSubview(contentView)
    overlayHostView.addSubview(shadowView)
    shellShadowView = shadowView
    shellContentView = contentView
}

private func animateOpeningTransition(completion: @escaping () -> Void) {
    guard
        let overlayHostView,
        let destinationView = destinationViewController?.view
    else {
        completion()
        return
    }

    overlayHostView.layoutIfNeeded()
    destinationView.superview?.layoutIfNeeded()

    guard let shellShadowView, let shellContentView else {
        destinationView.isHidden = false
        destinationView.alpha = 0
        UIView.animate(withDuration: Self.handoffDuration) {
            destinationView.alpha = 1
        } completion: { _ in
            completion()
        }
        return
    }

    let targetFrame = overlayHostView.bounds.standardized
    UIView.animate(
        withDuration: Self.openingDuration,
        delay: 0,
        usingSpringWithDamping: 0.94,
        initialSpringVelocity: 0,
        options: [.beginFromCurrentState, .curveEaseInOut]
    ) {
        shellShadowView.frame = targetFrame
        shellContentView.layer.cornerRadius = 0
        shellShadowView.layer.shadowOpacity = 0
    } completion: { _ in
        destinationView.isHidden = false
        destinationView.alpha = 0
        UIView.animate(withDuration: Self.handoffDuration) {
            destinationView.alpha = 1
            shellShadowView.alpha = 0
        } completion: { _ in
            completion()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningShell(using:) / animateOpeningTransition(completion:) / makeSnapshotView(from:rect:)
// 功能说明: 修改后 macOS snapshot shell 会把来源卡片缓存成 NSImage 快照，再执行放大和 handoff，从而与 iOS 保持同样的 opening 观感结构。
private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
    removeShellViews()
    guard
        let overlayHostView,
        let sourceViewController,
        let sourceRect = context.sourceGeometry.cardRect
    else {
        return
    }

    overlayHostView.layoutSubtreeIfNeeded()
    sourceViewController.view.layoutSubtreeIfNeeded()

    let convertedSourceRect = overlayHostView.convert(
        sourceRect,
        from: sourceViewController.view
    ).standardized
    guard convertedSourceRect.isEmpty == false else {
        return
    }

    let shadowView = NSView(frame: convertedSourceRect)
    shadowView.wantsLayer = true
    shadowView.layer?.backgroundColor = NSColor.clear.cgColor
    shadowView.layer?.shadowColor = NSColor.black.cgColor
    shadowView.layer?.shadowOpacity = 0.08
    shadowView.layer?.shadowRadius = 16
    shadowView.layer?.shadowOffset = CGSize(width: 0, height: -8)

    let contentView = NSView(frame: shadowView.bounds)
    contentView.autoresizingMask = [.width, .height]
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    contentView.layer?.cornerRadius = Self.openingCornerRadius
    contentView.layer?.masksToBounds = true

    if let snapshotView = makeSnapshotView(
        from: sourceViewController.view,
        rect: sourceRect
    ) {
        snapshotView.frame = contentView.bounds
        snapshotView.autoresizingMask = [.width, .height]
        contentView.addSubview(snapshotView)
    }

    shadowView.addSubview(contentView)
    overlayHostView.addSubview(shadowView)
    shellShadowView = shadowView
    shellContentView = contentView
}

private func animateOpeningTransition(completion: @escaping () -> Void) {
    guard
        let overlayHostView,
        let destinationView = destinationViewController?.view
    else {
        completion()
        return
    }

    overlayHostView.layoutSubtreeIfNeeded()
    destinationView.superview?.layoutSubtreeIfNeeded()

    guard let shellShadowView else {
        destinationView.isHidden = false
        destinationView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.handoffDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            destinationView.animator().alphaValue = 1
        } completionHandler: {
            completion()
        }
        return
    }

    let targetFrame = overlayHostView.bounds.standardized
    shellShadowView.isHidden = false
    NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.openingDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shellShadowView.animator().frame = targetFrame
        shellShadowView.layer?.shadowOpacity = 0
        shellContentView?.layer?.cornerRadius = 0
    } completionHandler: {
        destinationView.isHidden = false
        destinationView.alphaValue = 0
        destinationView.superview?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.handoffDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            destinationView.animator().alphaValue = 1
            shellShadowView.animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }
}

private func makeSnapshotView(from sourceView: NSView, rect: CGRect) -> NSImageView? {
    let clippedRect = rect.standardized.intersection(sourceView.bounds)
    guard clippedRect.isEmpty == false else {
        return nil
    }

    guard let bitmap = sourceView.bitmapImageRepForCachingDisplay(in: clippedRect) else {
        return nil
    }

    sourceView.cacheDisplay(in: clippedRect, to: bitmap)
    let image = NSImage(size: clippedRect.size)
    image.addRepresentation(bitmap)

    let imageView = NSImageView(frame: CGRect(origin: .zero, size: clippedRect.size))
    imageView.image = image
    imageView.imageScaling = .scaleAxesIndependently
    return imageView
}
```

## 修改三：`AppRoot` 改为等待 carrier 动画完成，并显式管理 overlay 激活/关闭

### 修改前

- opening：
  - `AppRoot` 调用 `carrier.beginTransition(...)` 后，立即用 `DispatchQueue.main.async` 进入 `completeOpeningTransition(...)`。
  - carrier 即便以后真的有动画，`AppRoot` 也会过早把源页面卸掉。
- closing：
  - `handleResolvedClosingTargetGeometry(...)` 在更新完 `targetGeometry` 后，直接 `completeClosingTransition(...)`。
  - closing 生命周期还没有通过 carrier 收口。
- overlay：
  - 虽然 `overlayHostView` 已经存在，但没有专门的显式激活/关闭方法。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / setupTransitionInfrastructure() / discardActiveTransitionIfNeeded()
// 功能说明: 修改前 iOS AppRoot 会在启动转场后下一帧直接 complete；carrier 还没有真正掌控 opening/closing 的完成时机。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
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
        self?.completeOpeningTransition(sessionID: session.id)
    }
}

private func handleResolvedClosingTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    sessionID: UUID,
    expectedBoardID: UUID?
) {
    // ... 省略 guard 与 updateCurrentTransitionTargetGeometry ...
    session.context.targetGeometry = geometry
    session.carrier.updateTransitionContext(session.context)
    completeClosingTransition(sessionID: sessionID)
}

private func setupTransitionInfrastructure() {
    view.addSubview(overlayHostView)
    NSLayoutConstraint.activate([
        overlayHostView.topAnchor.constraint(equalTo: view.topAnchor),
        overlayHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        overlayHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        overlayHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}

private func discardActiveTransitionIfNeeded() {
    guard let session = activeTransitionSession else {
        return
    }

    session.carrier.cancelTransition()
    // ... 省略 destination cleanup ...
    currentViewController?.view.isHidden = false
    activeTransitionSession = nil
    transitionPhase = steadyPhase(for: currentViewController)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: beginOpeningTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / setupTransitionInfrastructure() / discardActiveTransitionIfNeeded()
// 功能说明: 修改前 macOS AppRoot 同样是“begin 后下一帧 complete”，overlay 也没有显式的激活/关闭边界。
private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
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
        self?.completeOpeningTransition(sessionID: session.id)
    }
}

private func handleResolvedClosingTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    sessionID: UUID,
    expectedBoardID: UUID?
) {
    // ... 省略 guard 与 updateCurrentTransitionTargetGeometry ...
    session.context.targetGeometry = geometry
    session.carrier.updateTransitionContext(session.context)
    completeClosingTransition(sessionID: sessionID)
}
```

### 修改后

- opening：
  - `beginOpeningTransition(...)` 现在会先 `activateTransitionOverlay()`。
  - 再调用 `carrier.prepareTransition(...)` 组装 shell。
  - 然后由 `carrier.animateTransition { ... }` 回调 `completeOpeningTransition(...)`。
- closing：
  - `handleResolvedClosingTargetGeometry(...)` 不再直接 complete，而是统一走 `session.carrier.animateTransition { ... }`。
  - 当前 closing 分支虽然仍是无动画 completion，但生命周期已经统一到 carrier。
- overlay：
  - 新增 `activateTransitionOverlay()` / `deactivateTransitionOverlay()`。
  - 在 `display(_:)`、`completeOpeningTransition(...)`、`completeClosingTransition(...)`、`discardActiveTransitionIfNeeded()` 中都显式收口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: display(_:) / beginOpeningTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / completeOpeningTransition(sessionID:) / completeClosingTransition(sessionID:) / activateTransitionOverlay() / deactivateTransitionOverlay()
// 功能说明: 修改后 iOS AppRoot 会等待 carrier 动画完成后再进入 steady state，并对 overlay 的可见性和交互状态进行显式管理。
func display(_ destination: AppLaunchDestination) {
    discardActiveTransitionIfNeeded()
    let viewController = makeViewController(for: destination)
    setCurrentViewControllerImmediately(viewController)
    transitionPhase = steadyPhase(for: destination)
    deactivateTransitionOverlay()
}

private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .opening
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    view.layoutIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    carrier.animateTransition { [weak self] in
        self?.completeOpeningTransition(sessionID: session.id)
    }
}

private func handleResolvedClosingTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    sessionID: UUID,
    expectedBoardID: UUID?
) {
    // ... 省略 guard 与 updateCurrentTransitionTargetGeometry ...
    session.context.targetGeometry = geometry
    session.carrier.updateTransitionContext(session.context)
    session.carrier.animateTransition { [weak self] in
        self?.completeClosingTransition(sessionID: sessionID)
    }
}

private func completeOpeningTransition(sessionID: UUID) {
    // ... 省略 source 卸载与 currentViewController 切换 ...
    session.carrier.completeTransition()
    activeTransitionSession = nil
    transitionPhase = .steadyCanvas
    deactivateTransitionOverlay()
}

private func completeClosingTransition(sessionID: UUID) {
    // ... 省略 source 卸载与 currentViewController 切换 ...
    session.carrier.completeTransition()
    activeTransitionSession = nil
    transitionPhase = .steadyBoardList
    deactivateTransitionOverlay()
}

private func activateTransitionOverlay() {
    overlayHostView.isHidden = false
    overlayHostView.isUserInteractionEnabled = true
    view.bringSubviewToFront(overlayHostView)
}

private func deactivateTransitionOverlay() {
    overlayHostView.isUserInteractionEnabled = false
    overlayHostView.isHidden = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: display(_:) / beginOpeningTransition(with:) / beginClosingTransition(with:) / handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:) / activateTransitionOverlay() / deactivateTransitionOverlay()
// 功能说明: 修改后 macOS AppRoot 与 iOS 采用相同的“prepare -> animate -> complete”转场时序，并把 overlay 的展示边界显式化。
func display(_ destination: AppLaunchDestination) {
    discardActiveTransitionIfNeeded()
    let viewController = makeViewController(for: destination)
    setCurrentViewControllerImmediately(viewController)
    transitionPhase = steadyPhase(for: destination)
    deactivateTransitionOverlay()
}

private func beginOpeningTransition(
    with request: BoardListCanvasOpenRequest
) {
    // ... 省略 session 构建代码 ...
    activeTransitionSession = session
    transitionPhase = .opening
    activateTransitionOverlay()
    carrier.install(in: overlayHostView)
    mountViewController(destinationViewController, hidden: true)
    view.layoutSubtreeIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
    carrier.animateTransition { [weak self] in
        self?.completeOpeningTransition(sessionID: session.id)
    }
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
    destinationViewController.prepareForDisplay()
    view.layoutSubtreeIfNeeded()
    carrier.prepareTransition(
        with: session.context,
        sourceViewController: sourceViewController,
        destinationViewController: destinationViewController
    )
}

private func handleResolvedClosingTargetGeometry(
    _ geometry: BoardListCanvasTransitionTargetGeometry,
    sessionID: UUID,
    expectedBoardID: UUID?
) {
    // ... 省略 guard 与 updateCurrentTransitionTargetGeometry ...
    session.context.targetGeometry = geometry
    session.carrier.updateTransitionContext(session.context)
    session.carrier.animateTransition { [weak self] in
        self?.completeClosingTransition(sessionID: sessionID)
    }
}

private func activateTransitionOverlay() {
    overlayHostView.isHidden = false
}

private func deactivateTransitionOverlay() {
    overlayHostView.isHidden = true
}
```

## 行为结果

- 从 `BoardList` 打开已有板卡片时，容器现在会先生成来源卡片快照壳，再执行 `sourceRect -> fullscreen` 的放大，最后由真实 `CanvasVC.view` 淡入接管。
- 从 `BoardList` 打开新建占位时，也走同一条 opening snapshot shell 路径，因此视觉上和已有板打开保持一致。
- 真实 `CanvasVC.view` 在 opening 前半段仍按全屏页面完成初始化与布局，不承担几何变化；这符合 `Phase 4` 里“不要让真实 viewport 链参与前半段放大”的约束。
- closing 方向虽然已经接入 `prepareTransition(...) -> updateTransitionContext(...) -> animateTransition(...) -> completeTransition()` 这条统一生命周期，但当前 `.closing` 分支仍直接 completion，尚未实现缩回目标卡片动画。
- `LiveCanvasCarrier` 仍未落地；当前阶段依然是方案 C 的 snapshot shell 路线，只是 opening 动画已经从“占位”升级为“真实放大 + handoff”。

## 校验结果

- 当前工作树在记录前的相关变更为：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 已通过 `ReadLints` 检查以下文件，未发现新的 lint 错误：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 已执行并通过以下语法解析命令：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift"`
- iOS 侧本轮仍以 IDE lint 结果为主，没有额外执行完整 iOS SDK 编译解析。

## 后续衔接

- `Phase 5` 可以直接在当前 `SnapshotShellCarrier.animateTransition(completion:)` 的 `.closing` 分支里补真正的缩回动画，而不需要再改 `AppRoot` 状态机接口。
- 如果未来升级到 `LiveCanvasCarrier`，当前 `prepareTransition(...) / animateTransition(...) / updateTransitionContext(...)` 这组生命周期、`overlayHostView`、以及 `AppRoot` 的 session 管理都可以继续复用。
