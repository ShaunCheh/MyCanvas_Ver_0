# 20260413_154907_interaction_intent_phase3_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase3` 反馈桥接与 `macOS` 补充键盘 capture”的实际 `git status`、`git diff --stat`、`git diff`、构建结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 3 个业务代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前的当前工作区状态依据：

- `git status --short --branch` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short --branch` 显示本次 `phase3` 当前 changes 只包含上述 3 个跟踪文件
- `git diff --stat -- <3 个业务代码文件>` 统计为：`3 files changed, 137 insertions(+), 4 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 3 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- `phase4` 的 command gate 收敛

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +%Y%m%d_%H%M%S
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff --stat / git diff
# 功能说明: 提取本次 phase3 的当前工作区状态、统计信息与 3 个业务代码文件的真实改动范围。
git status --short --branch

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase3 接线后的 macOS 与 iOS 平台是否仍可通过编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## 本次 phase3 的目标

这一步不是继续扩展 transfer intent 模型，而是把 `phase2` 里已经打通的 blocked decision 真正桥接成用户可见反馈，并补上 `macOS` 在阅读模式下标准菜单校验可能观测不到 keyboard paste attempt 的捕获缺口：

1. 双端 `applyInteractionFeedback(_:)` 从占位实现切到真实按钮摇头动画。
2. `iOS` 继续沿用现有 `UIKeyCommand -> handleTransferEntryAttempt(...)` 路径，只把 `.shakeWorkspaceModeButton` 映射到按钮动画。
3. `macOS` 在保留标准 `validateUserInterfaceItem(_:) -> paste(_:)` 路径的同时，引入按条件启停的本地 `keyDown` monitor。
4. `macOS` 的补充 monitor 只在阅读模式下键盘 paste 被 policy 阻断且需要反馈时启用，不常驻全开。
5. 对 monitor 捕获到的被阻断 `Command + V` 返回 `nil`，避免系统 beep 与按钮摇头叠加。

## 修改一：iOS feedback bridge 从占位切到真实按钮摇头

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: applyInteractionFeedback
// 功能说明: 修改前 iOS 已经能在 blocked decision 上进入 feedback bridge，但 `.shakeWorkspaceModeButton` 仍然只是占位注释，没有真实动画。
private func applyInteractionFeedback(_ hint: CanvasInteractionFeedbackHint) {
    switch hint {
    case .shakeWorkspaceModeButton:
        // Phase 3 wires this to the workspace mode button animation.
        break
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: applyInteractionFeedback / animateWorkspaceModeButtonShake
// 功能说明: 修改后 iOS 将 `.shakeWorkspaceModeButton` 映射为 workspaceModeButton 的水平位移动画，用于阅读模式下键盘 paste 被阻断时的可见反馈。
private func applyInteractionFeedback(_ hint: CanvasInteractionFeedbackHint) {
    switch hint {
    case .shakeWorkspaceModeButton:
        animateWorkspaceModeButtonShake()
    }
}

private func animateWorkspaceModeButtonShake() {
    let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
    animation.values = [0, -10, 10, -7, 7, -4, 4, 0]
    animation.duration = 0.36
    animation.isAdditive = true
    animation.calculationMode = .linear
    workspaceModeButton.layer.removeAnimation(
        forKey: "CanvasWorkspaceModeButtonShake"
    )
    workspaceModeButton.layer.add(
        animation,
        forKey: "CanvasWorkspaceModeButtonShake"
    )
}
```

### 修改意图

这一步让 `phase2` 中已经走到 `feedback` 的 iOS 键盘 paste 阻断，第一次真正变成用户可见的按钮摇头行为，而不改动 iOS 的 capture 路径本身。

## 修改二：macOS feedback bridge 接上真实动画，并补本地键盘 capture

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource / applyInteractionFeedback / applyTransitionInteractionFreeze / applyWorkspaceModeForToolbarTransition
// 功能说明: 修改前 macOS 只有标准 `paste(_:)` 路径与 feedback 占位，没有本地键盘补充 capture，也没有 monitor 生命周期管理。
private enum TransferEntryDeliverySource {
    case macOSPasteAction
    case importButton
    case dragAndDrop
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

override func viewDidAppear() {
    super.viewDidAppear()
    updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
    updateChromeOverlayLayout()
}

private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    workspaceMode = targetMode
    updateWorkspaceModeButtonAppearance()
    syncTextEditorPresentation()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}

private func applyInteractionFeedback(_ hint: CanvasInteractionFeedbackHint) {
    switch hint {
    case .shakeWorkspaceModeButton:
        // Phase 3 wires this to the workspace mode button animation.
        break
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource / supplementalKeyboardCaptureMonitor / applyInteractionFeedback / shouldEnableSupplementalKeyboardCapture / updateSupplementalKeyboardCaptureIfNeeded / handleSupplementalKeyboardCapture
// 功能说明: 修改后 macOS 将 `.shakeWorkspaceModeButton` 映射为按钮摇头动画，并在阅读模式下按条件启用本地 keyDown monitor，补获被标准菜单校验挡掉的 keyboard paste 尝试。
private enum TransferEntryDeliverySource {
    case macOSPasteAction
    case macOSLocalKeyMonitor
    case importButton
    case dragAndDrop
}

private var supplementalKeyboardCaptureMonitor: Any?

deinit {
    removeSupplementalKeyboardCaptureIfNeeded()
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
    updateSupplementalKeyboardCaptureIfNeeded()
}

override func viewDidAppear() {
    super.viewDidAppear()
    updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
    updateChromeOverlayLayout()
    updateSupplementalKeyboardCaptureIfNeeded()
}

override func viewWillDisappear() {
    super.viewWillDisappear()
    removeSupplementalKeyboardCaptureIfNeeded()
}

private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    workspaceMode = targetMode
    updateWorkspaceModeButtonAppearance()
    updateSupplementalKeyboardCaptureIfNeeded()
    syncTextEditorPresentation()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}

private func applyInteractionFeedback(_ hint: CanvasInteractionFeedbackHint) {
    switch hint {
    case .shakeWorkspaceModeButton:
        animateWorkspaceModeButtonShake()
    }
}

private func animateWorkspaceModeButtonShake() {
    let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
    animation.values = [0, -10, 10, -7, 7, -4, 4, 0]
    animation.duration = 0.36
    animation.isAdditive = true
    animation.calculationMode = .linear
    workspaceModeButton.layer?.removeAnimation(
        forKey: "CanvasWorkspaceModeButtonShake"
    )
    workspaceModeButton.layer?.add(
        animation,
        forKey: "CanvasWorkspaceModeButtonShake"
    )
}

private func shouldEnableSupplementalKeyboardCapture() -> Bool {
    guard
        view.window != nil,
        view.isHiddenOrHasHiddenAncestor == false
    else {
        return false
    }

    switch transferEntryDecision(for: .pasteKeyboardShortcut) {
    case .block(
        reason: .readingMode,
        feedback: .shakeWorkspaceModeButton
    ):
        return true
    case .allow,
         .block:
        return false
    }
}

private func updateSupplementalKeyboardCaptureIfNeeded() {
    guard shouldEnableSupplementalKeyboardCapture() else {
        removeSupplementalKeyboardCaptureIfNeeded()
        return
    }

    guard supplementalKeyboardCaptureMonitor == nil else {
        return
    }

    supplementalKeyboardCaptureMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown]
    ) { [weak self] event in
        self?.handleSupplementalKeyboardCapture(event) ?? event
    }
}

private func handleSupplementalKeyboardCapture(
    _ event: NSEvent
) -> NSEvent? {
    guard
        shouldEnableSupplementalKeyboardCapture(),
        let window = view.window,
        event.window === window,
        isPasteKeyboardShortcutEvent(event)
    else {
        return event
    }

    guard case .block = transferEntryDecision(for: .pasteKeyboardShortcut) else {
        return event
    }

    _ = handleTransferEntryAttempt(
        .pasteKeyboardShortcut,
        deliverySource: .macOSLocalKeyMonitor
    ) {
        false
    }
    return nil
}
```

### 修改意图

这一步把 `phase3` 计划里的两件核心工作同时落地：

1. `macOS` 的 blocked feedback 不再停留在占位，而是和 iOS 一样落成真实按钮摇头动画。
2. monitor 只在“阅读模式下键盘 paste 被 policy 阻断且需要反馈”时启用，避免常驻全局监听。
3. monitor 生命周期挂到 `viewDidAppear`、`viewWillDisappear`、`applyTransitionInteractionFreeze()`、`applyWorkspaceModeForToolbarTransition(...)` 上，防止 monitor 泄漏或模式切换后状态不同步。
4. monitor 捕获到被阻断的 `Command + V` 时返回 `nil`，让这次补充 capture 自身成为最终消费方，避免系统 beep 与动画叠加。

## 修改三：补 `pasteMenu` 的 shared policy 回归测试

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testImportButtonBlocksInReadingModeWithoutFeedback / testDragAndDropBlocksInReadingModeWithoutFeedback
// 功能说明: 修改前测试已经覆盖 importButton 与 dragAndDrop 在 reading mode 下的无反馈阻断，但还没有显式锁定 pasteMenu 的同类语义。
func testImportButtonBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .transferEntry(.importButton),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}

func testDragAndDropBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .transferEntry(.dragAndDrop),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testPasteMenuBlocksInReadingModeWithoutFeedback
// 功能说明: 修改后新增 pasteMenu 的回归测试，明确 reading mode 下只有 keyboard paste 返回按钮反馈，menu paste 仍然是无反馈阻断。
func testPasteMenuBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .transferEntry(.pasteMenu),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}
```

### 修改意图

这一步把“keyboard paste 才触发 `.shakeWorkspaceModeButton`、menu paste 不触发”这个 `phase3` 关键语义明确锁进 shared 测试，避免后续 `phase4` / `phase5` 继续收敛时把菜单与键盘入口的反馈策略混成同一个结果。

## 验证结果

本次记录对应的实际验证结果如下：

- `ReadLints` 对 `iOSViewController.swift`、`macOSViewController.swift`、`CanvasInteractionPolicyTests.swift` 的读取结果为：无 linter 报错
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build` 结果为：`BUILD SUCCEEDED`
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build` 结果为：`BUILD SUCCEEDED`
- 本次 `phase3` 没有额外执行完整 `xcodebuild test`，因此本记录不新增完整 test target 的运行结论

构建输出里观测到的既有 warning 现象包括：

- `BoardSaveCoordinator.swift` 中与 `CanvasImageAssetReference` 相关的 Swift 6 actor warning
- `macOSViewController.swift` 中与 `CanvasToolbarTransitionDirection` / `CanvasToolbarTransitionStage` 相关的 Swift 6 actor warning
- `appintentsmetadataprocessor` 的 `Metadata extraction skipped. No AppIntents.framework dependency found.`

上述 warning 没有阻断本次 `phase3` 的双端 build 成功。

## 与当前其他 changes 的边界说明

这次 `phase3` 记录只覆盖上面 3 个业务代码文件，不覆盖当前工作区里另一个已存在的 `.md` 计划文件变更：

- `M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`

该 `.md` 文件在本次记录写入过程中未被我删除、修改或回滚；这里只做如实说明，不把它混入本次 `phase3` 代码变更记录。
