# 20260409_101437_boardlist_zoom_transition_phase5_closing_snapshot_shell_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 5`，实现方案 C 的返回缩小动画。
- 记录内容：让双端 `Canvas` 返回按钮在 `launchContext == .newBoard` 时先强制保存真实 board，再发出返回请求。
- 记录内容：让双端 `SnapshotShellCarrier` 在 closing 方向抓取实时 fullscreen shell，并缩回 `BoardList` 已解析出的目标卡片 rect。
- 记录依据：本记录基于当前工作树的 `git status --short`、本次相关文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 本记录复用但未改动的链路：`AppRoot` closing 状态机、`BoardList.prepareTransitionTargetGeometry(...)`、`pendingRevealBoardID -> revealPendingBoardIfNeeded()` 目标卡片 reveal 链。
- 本记录不包含：`Phase 4` 的打开放大动画。
- 本记录不包含：`Phase 6` 的输入冻结、共享配置收口和方案 B 升级缝隙验证。
- 本记录不包含：`LiveCanvasCarrier` 的真实实现。
- 本记录不包含：git commit。

## 修改一：返回按钮从“直接离场”升级为“新建板先持久化，再返回”

### 修改前

- `BoardListCanvasReturnRequest` 在 Phase 1 已经带有 `requiresBoardPersistence`，但双端 `CanvasViewController` 还没有真正消费它。
- 手动保存按钮和返回按钮各自维护一套逻辑：
  - 手动保存里直接写 `switch result`。
  - 返回按钮始终直接 `onReturnToBoardList?(makeReturnToBoardListRequest())`。
- 这意味着新建板返回时仍然依赖 autosave 延迟，不满足 `Phase 5` 的“先确保真实卡片存在，再触发 closing 动画”要求。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleSaveButtonTap() / makeReturnToBoardListRequest() / handleBackButtonTap()
// 功能说明: 修改前 iOS 返回按钮不区分已有板和新建板，始终直接离场；手动保存结果处理也还是一段内联 switch。
@objc
private func handleSaveButtonTap() {
    commitActiveTextEditIfNeeded()
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(.success)
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(.missingFolder)
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(.failure)
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonTap() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onReturnToBoardList?(makeReturnToBoardListRequest())
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleSaveButtonClick() / makeReturnToBoardListRequest() / handleBackButtonClick()
// 功能说明: 修改前 macOS 与 iOS 同构，也还是“手动保存内联处理 + 返回直接离场”。
@objc
private func handleSaveButtonClick() {
    commitActiveTextEditIfNeeded()
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(.success)
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(.missingFolder)
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(.failure)
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonClick() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onReturnToBoardList?(makeReturnToBoardListRequest())
}
```

### 修改后

- 双端都新增 `requestReturnToBoardList()`：
  - 已有板：保持直接返回。
  - 新建板：先 `saveBoardNow(reason:createBoardIfNeeded:completion:)`，成功后重新生成 request，再交给 `AppRoot`。
- 双端都新增 `handleImmediateBoardSaveResult(...)`：
  - 手动保存和返回前保存复用同一套成功/失败反馈。
  - 保存失败时保留在 canvas，不再发出返回请求。
- 这样 `Phase 5` 的“新建板先确保真实卡片存在，再缩回真实卡片”约束第一次被真正落到 `Canvas` 侧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleSaveButtonTap() / handleBackButtonTap() / requestReturnToBoardList()
// 功能说明: 修改后 iOS 在返回新建板时会先立即保存真实 board；保存成功才真正发出返回请求，失败则留在当前 canvas 并复用现有错误反馈。
@objc
private func handleSaveButtonTap() {
    commitActiveTextEditIfNeeded()
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        self.handleImmediateBoardSaveResult(
            result,
            missingFolderMessage: "Select a folder from the board list before saving."
        )
    }
}

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonTap() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    requestReturnToBoardList()
}

private func requestReturnToBoardList() {
    let request = makeReturnToBoardListRequest()
    guard request.requiresBoardPersistence else {
        onReturnToBoardList?(request)
        return
    }

    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "return to board list",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        self.handleImmediateBoardSaveResult(
            result,
            missingFolderMessage: "Select a folder from the board list before returning so the new board can be saved."
        ) { [weak self] in
            guard let self else {
                return
            }

            self.onReturnToBoardList?(self.makeReturnToBoardListRequest())
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleImmediateBoardSaveResult(_:missingFolderMessage:onSuccess:)
// 功能说明: 修改后 iOS 把“立即保存”的成功/失败反馈收口成独立 helper，手动保存与返回前保存都走同一套按钮状态和弹窗逻辑。
private func handleImmediateBoardSaveResult(
    _ result: Result<Void, Error>,
    missingFolderMessage: String,
    onSuccess: (() -> Void)? = nil
) {
    switch result {
    case .success:
        showSaveButtonFeedback(.success)
        onSuccess?()
    case let .failure(error):
        if case FolderBookmarkStoreError.missingBookmarkData = error {
            showSaveButtonFeedback(.missingFolder)
            presentSaveError(message: missingFolderMessage)
        } else {
            showSaveButtonFeedback(.failure)
            presentSaveError(message: error.localizedDescription)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleSaveButtonClick() / handleBackButtonClick() / requestReturnToBoardList()
// 功能说明: 修改后 macOS 同样在返回新建板时先立即保存真实 board，再用最新 boardID 生成返回请求，保证 closing 动画的 target 是真实卡片。
@objc
private func handleSaveButtonClick() {
    commitActiveTextEditIfNeeded()
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        self.handleImmediateBoardSaveResult(
            result,
            missingFolderMessage: "Select a folder from the board list before saving."
        )
    }
}

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonClick() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    requestReturnToBoardList()
}

private func requestReturnToBoardList() {
    let request = makeReturnToBoardListRequest()
    guard request.requiresBoardPersistence else {
        onReturnToBoardList?(request)
        return
    }

    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "return to board list",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        self.handleImmediateBoardSaveResult(
            result,
            missingFolderMessage: "Select a folder from the board list before returning so the new board can be saved."
        ) { [weak self] in
            guard let self else {
                return
            }

            self.onReturnToBoardList?(self.makeReturnToBoardListRequest())
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleImmediateBoardSaveResult(_:missingFolderMessage:onSuccess:)
// 功能说明: 修改后 macOS 也把“立即保存结果处理”独立出来，避免手动保存和返回前保存各写一套分支。
private func handleImmediateBoardSaveResult(
    _ result: Result<Void, Error>,
    missingFolderMessage: String,
    onSuccess: (() -> Void)? = nil
) {
    switch result {
    case .success:
        showSaveButtonFeedback(.success)
        onSuccess?()
    case let .failure(error):
        if case FolderBookmarkStoreError.missingBookmarkData = error {
            showSaveButtonFeedback(.missingFolder)
            presentSaveError(message: missingFolderMessage)
        } else {
            showSaveButtonFeedback(.failure)
            presentSaveError(message: error.localizedDescription)
        }
    }
}
```

## 修改二：`SnapshotShellCarrier` 从“closing 直接 completion”升级为“抓实时 fullscreen shell 并缩回目标卡片”

### 修改前

- `prepareTransition(...)` 只在 `.opening` 时组装 shell。
- `animateTransition(...)` 的 `.closing` 分支直接 `completion()`。
- 也就是说：
  - `AppRoot` 和 `BoardList` 虽然已经能在 closing 时准备好 `targetGeometry`，
  - 但 carrier 还没有真正消费 `targetGeometry`，
  - 视觉上仍然只是瞬时切回列表。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: openingDuration / handoffDuration / prepareTransition(with:sourceViewController:destinationViewController:) / animateTransition(completion:)
// 功能说明: 修改前 iOS carrier 只支持 opening 动画；closing 分支只是直接 completion，尚未消费 targetGeometry。
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
// 函数名/符号名: openingDuration / handoffDuration / prepareTransition(with:sourceViewController:destinationViewController:) / animateTransition(completion:)
// 功能说明: 修改前 macOS carrier 与 iOS 一样，也只有 opening 真动画，closing 仍是空实现。
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

### 修改后

- 双端 carrier 都新增 closing 侧专用配置：
  - `closingDuration`
  - `shellCornerRadius`
  - `shellShadowOpacity`
  - `shellShadowRadius`
  - `shellShadowOffset`
  - `fallbackClosingScale`
- `prepareTransition(...)` 现在会在 `.closing` 时调用 `prepareClosingShell()`：
  - 从当前真实 canvas 全屏视图抓取实时 snapshot。
  - 不是复用旧卡片 preview，因此符合计划里“返回时优先用实时 capture 的 fullscreen shell”的要求。
- `animateClosingTransition(completion:)` 现在分两条路径：
  - 目标卡片可解析：从 fullscreen 缩回 `targetGeometry.cardRect`。
  - 目标卡片缺失：降级为居中缩小淡出。
- 这样 `Phase 2` 提供的 target geometry reveal 链，在 `Phase 5` 第一次被 closing 动画真正消费。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: closingDuration / prepareTransition(with:sourceViewController:destinationViewController:) / prepareClosingShell() / animateClosingTransition(completion:)
// 功能说明: 修改后 iOS carrier 会在 closing 时先抓取实时 fullscreen shell，再根据 targetGeometry 缩回目标卡片；若拿不到目标，则降级为居中缩小淡出。
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

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        switch context.direction {
        case .opening:
            prepareOpeningShell(using: context)
        case .closing:
            prepareClosingShell()
        }
    }

    private func prepareClosingShell() {
        removeShellViews()
        guard
            let overlayHostView,
            let sourceView = sourceViewController?.view
        else {
            return
        }

        overlayHostView.layoutIfNeeded()
        sourceView.layoutIfNeeded()
        sourceView.superview?.layoutIfNeeded()

        let fullscreenFrame = overlayHostView.bounds.standardized
        guard fullscreenFrame.isEmpty == false else {
            return
        }

        let shadowView = UIView(frame: fullscreenFrame)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: 0
        )
        configureShadow(for: shadowView, opacity: 0)

        if let snapshotView = sourceView.resizableSnapshotView(
            from: sourceView.bounds,
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

    private func animateClosingTransition(completion: @escaping () -> Void) {
        guard
            let overlayHostView,
            let destinationView = destinationViewController?.view
        else {
            completion()
            return
        }

        overlayHostView.layoutIfNeeded()
        destinationView.isHidden = false
        destinationView.alpha = 1
        destinationView.superview?.layoutIfNeeded()

        guard let shellShadowView, let shellContentView else {
            completion()
            return
        }

        shellShadowView.isHidden = false
        shellShadowView.alpha = 1

        let targetFrame = resolvedClosingTargetFrame(in: overlayHostView)
        let fallbackFrame = fallbackClosingFrame(in: overlayHostView)

        if let targetFrame {
            UIView.animate(
                withDuration: Self.closingDuration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut]
            ) {
                shellShadowView.frame = targetFrame
                shellContentView.layer.cornerRadius = Self.shellCornerRadius
                shellShadowView.layer.shadowOpacity = Self.shellShadowOpacity
            } completion: { _ in
                UIView.animate(
                    withDuration: Self.handoffDuration,
                    delay: 0,
                    options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    shellShadowView.alpha = 0
                } completion: { _ in
                    completion()
                }
            }
            return
        }

        destinationView.alpha = 0
        UIView.animate(
            withDuration: Self.closingDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            shellShadowView.frame = fallbackFrame
            shellContentView.layer.cornerRadius = Self.shellCornerRadius
            shellShadowView.layer.shadowOpacity = Self.shellShadowOpacity
            shellShadowView.alpha = 0
            destinationView.alpha = 1
        } completion: { _ in
            completion()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: resolvedClosingTargetFrame(in:) / fallbackClosingFrame(in:) / makeShellContentView(frame:cornerRadius:) / configureShadow(for:opacity:)
// 功能说明: 修改后 iOS closing 动画会优先缩回真实目标卡片；如果目标解析失败，则降级成居中缩小淡出，而不是缩回一个不存在的空目标。
private func resolvedClosingTargetFrame(
    in overlayHostView: UIView
) -> CGRect? {
    guard
        let destinationView = destinationViewController?.view,
        let targetRect = currentContext?.targetGeometry.cardRect
    else {
        return nil
    }

    let convertedTargetRect = overlayHostView.convert(
        targetRect,
        from: destinationView
    ).standardized
    guard convertedTargetRect.isEmpty == false else {
        return nil
    }

    return convertedTargetRect
}

private func fallbackClosingFrame(in overlayHostView: UIView) -> CGRect {
    let bounds = overlayHostView.bounds.standardized
    let scaledWidth = bounds.width * Self.fallbackClosingScale
    let scaledHeight = bounds.height * Self.fallbackClosingScale
    return CGRect(
        x: bounds.midX - (scaledWidth / 2),
        y: bounds.midY - (scaledHeight / 2),
        width: scaledWidth,
        height: scaledHeight
    ).integral
}

private func makeShellContentView(
    frame: CGRect,
    cornerRadius: CGFloat
) -> UIView {
    let contentView = UIView(frame: frame)
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contentView.backgroundColor = .secondarySystemBackground
    contentView.layer.cornerRadius = cornerRadius
    contentView.layer.masksToBounds = true
    return contentView
}

private func configureShadow(
    for shadowView: UIView,
    opacity: Float
) {
    shadowView.backgroundColor = .clear
    shadowView.isUserInteractionEnabled = false
    shadowView.layer.shadowColor = UIColor.black.cgColor
    shadowView.layer.shadowOpacity = opacity
    shadowView.layer.shadowRadius = Self.shellShadowRadius
    shadowView.layer.shadowOffset = Self.shellShadowOffset
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: closingDuration / prepareTransition(with:sourceViewController:destinationViewController:) / prepareClosingShell() / animateClosingTransition(completion:)
// 功能说明: 修改后 macOS carrier 也会在 closing 时抓取实时全屏快照，并在目标就绪后缩回目标卡片；若目标缺失，则走居中缩小降级。
final class macOSSnapshotShellCarrier: macOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: NSView?
    private weak var sourceViewController: NSViewController?
    private weak var destinationViewController: NSViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: NSView?
    private var shellContentView: NSView?
    private static let openingDuration: TimeInterval = 0.38
    private static let closingDuration: TimeInterval = 0.32
    private static let handoffDuration: TimeInterval = 0.14
    private static let shellCornerRadius: CGFloat = 12
    private static let shellShadowOpacity: Float = 0.08
    private static let shellShadowRadius: CGFloat = 16
    private static let shellShadowOffset = CGSize(width: 0, height: -8)
    private static let fallbackClosingScale: CGFloat = 0.82

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        switch context.direction {
        case .opening:
            prepareOpeningShell(using: context)
        case .closing:
            prepareClosingShell()
        }
    }

    private func prepareClosingShell() {
        removeShellViews()
        guard
            let overlayHostView,
            let sourceView = sourceViewController?.view
        else {
            return
        }

        overlayHostView.layoutSubtreeIfNeeded()
        sourceView.layoutSubtreeIfNeeded()
        sourceView.superview?.layoutSubtreeIfNeeded()

        let fullscreenFrame = overlayHostView.bounds.standardized
        guard fullscreenFrame.isEmpty == false else {
            return
        }

        let shadowView = NSView(frame: fullscreenFrame)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: 0
        )
        configureShadow(for: shadowView, opacity: 0)

        if let snapshotView = makeSnapshotView(
            from: sourceView,
            rect: sourceView.bounds
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

    private func animateClosingTransition(completion: @escaping () -> Void) {
        guard
            let overlayHostView,
            let destinationView = destinationViewController?.view
        else {
            completion()
            return
        }

        overlayHostView.layoutSubtreeIfNeeded()
        destinationView.isHidden = false
        destinationView.alphaValue = 1
        destinationView.superview?.layoutSubtreeIfNeeded()

        guard let shellShadowView else {
            completion()
            return
        }

        shellShadowView.isHidden = false
        shellShadowView.alphaValue = 1

        let targetFrame = resolvedClosingTargetFrame(in: overlayHostView)
        let fallbackFrame = fallbackClosingFrame(in: overlayHostView)

        if let targetFrame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.closingDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shellShadowView.animator().frame = targetFrame
                shellShadowView.layer?.shadowOpacity = Self.shellShadowOpacity
                shellContentView?.layer?.cornerRadius = Self.shellCornerRadius
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.handoffDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    shellShadowView.animator().alphaValue = 0
                } completionHandler: {
                    completion()
                }
            }
            return
        }

        destinationView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closingDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shellShadowView.animator().frame = fallbackFrame
            shellShadowView.animator().alphaValue = 0
            shellShadowView.layer?.shadowOpacity = Self.shellShadowOpacity
            shellContentView?.layer?.cornerRadius = Self.shellCornerRadius
            destinationView.animator().alphaValue = 1
        } completionHandler: {
            completion()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: resolvedClosingTargetFrame(in:) / fallbackClosingFrame(in:) / makeShellContentView(frame:cornerRadius:) / configureShadow(for:opacity:)
// 功能说明: 修改后 macOS closing 动画也把“真实目标卡片”和“目标缺失降级”两条路径显式收口，和 iOS 保持同构。
private func resolvedClosingTargetFrame(
    in overlayHostView: NSView
) -> CGRect? {
    guard
        let destinationView = destinationViewController?.view,
        let targetRect = currentContext?.targetGeometry.cardRect
    else {
        return nil
    }

    let convertedTargetRect = overlayHostView.convert(
        targetRect,
        from: destinationView
    ).standardized
    guard convertedTargetRect.isEmpty == false else {
        return nil
    }

    return convertedTargetRect
}

private func fallbackClosingFrame(in overlayHostView: NSView) -> CGRect {
    let bounds = overlayHostView.bounds.standardized
    let scaledWidth = bounds.width * Self.fallbackClosingScale
    let scaledHeight = bounds.height * Self.fallbackClosingScale
    return CGRect(
        x: bounds.midX - (scaledWidth / 2),
        y: bounds.midY - (scaledHeight / 2),
        width: scaledWidth,
        height: scaledHeight
    ).integral
}

private func makeShellContentView(
    frame: CGRect,
    cornerRadius: CGFloat
) -> NSView {
    let contentView = NSView(frame: frame)
    contentView.autoresizingMask = [.width, .height]
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    contentView.layer?.cornerRadius = cornerRadius
    contentView.layer?.masksToBounds = true
    return contentView
}

private func configureShadow(
    for shadowView: NSView,
    opacity: Float
) {
    shadowView.wantsLayer = true
    shadowView.layer?.backgroundColor = NSColor.clear.cgColor
    shadowView.layer?.shadowColor = NSColor.black.cgColor
    shadowView.layer?.shadowOpacity = opacity
    shadowView.layer?.shadowRadius = Self.shellShadowRadius
    shadowView.layer?.shadowOffset = Self.shellShadowOffset
}
```

## 行为结果

- 已有板返回时，closing 动画会优先把实时 fullscreen shell 缩回同一张列表卡片。
- 新建板返回时，不再依赖 autosave 的延迟；会先强制创建并保存真实 board，再缩回新生成的真实卡片。
- 如果目标卡片解析失败，carrier 会降级为居中缩小淡出，而不是伪造一个“缩回空目标”的动画。
- 如果新建板保存失败，返回请求不会发出，用户会继续留在当前 canvas，并看到现有保存失败反馈。
- `AppRoot` 和 `BoardList` 在 Phase 2/3/4 建好的 `targetGeometry` reveal 链和 closing 状态机，本轮没有推翻，而是被 closing snapshot shell 真正消费起来。

## 校验结果

- 当前工作树在记录前的相关变更为：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已通过 `ReadLints` 检查以下文件，未发现新的 lint 错误：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 已执行并通过以下语法解析命令：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCoordinator.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift"`
- iOS 侧本轮仍以 IDE lint 结果为主，没有额外执行完整 iOS SDK 编译解析。

## 后续衔接

- `Phase 6` 可以直接在当前 closing/opening 生命周期上补输入冻结，不需要再改返回保存链或 target reveal 链。
- 如果未来升级到 `LiveCanvasCarrier`，本轮新增的“返回前强制持久化”和“closing 优先消费 targetGeometry / 缺失目标降级”仍然可以直接复用。
