# 20260413_153027_interaction_intent_phase2_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase2` transfer attempt 收敛”的实际 `git status`、`git diff --stat`、`git diff`、构建结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 3 个业务代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前的当前工作区状态依据：

- `git status --short --branch` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short --branch` 显示本次 `phase2` 当前 changes 只包含上述 3 个跟踪文件
- `git diff --stat -- <3 个业务代码文件>` 统计为：`3 files changed, 248 insertions(+), 102 deletions(-)`
- `phase1` 的 shared input 文件未出现在这次当前 `git status` 中，因此本记录不把它们列为本次 `phase2` 的业务代码变更
- 本记录文件是随后新增的说明材料，不属于上述 3 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- `phase3` 的按钮摇头动画与 `macOS` 补充键盘 capture

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
# 功能说明: 提取本次 phase2 的当前工作区状态、统计信息与 3 个业务代码文件的真实改动范围。
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
# 功能说明: 验证 phase2 接线后的 macOS 与 iOS 平台是否仍可通过编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## 本次 phase2 的目标

这一步不是实现用户可见的按钮摇头动画，而是先把 paste / import / drag-and-drop 这些 transfer 入口，从“平台 controller 自己直接 `guard`”迁到“先构造 transfer intent，再问 shared policy”：

1. 在双端 controller 中引入统一归一入口 `handleTransferEntryAttempt(...)`。
2. 让 import button、paste、drag-drop 先走 `CanvasInteractionPolicy.decision(for:environment:)`。
3. `allow` 时继续沿用既有 transfer continuation，下沉到 `CanvasTransferRequest -> CanvasImportRequest -> CanvasTransferCommandLowerer`。
4. `block` 时先只保留 feedback bridge 占位，真正的按钮动画放到 `phase3`。
5. `performTransferRequest(_:)` 里的旧 guard 暂时保留，继续作为迁移期 safety net。

## 修改一：iOS transfer 入口改为“先判定、后解析”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleImportButtonTap / handlePasteKeyCommand / dropInteraction / canTransferContent
// 功能说明: 修改前 iOS 的 import、paste、drag-drop 入口分别直接读本地 reading/frozen guard，没有统一的 transfer intent 归一层。
@objc
private func handleImportButtonTap() {
    guard isReadingModeActive == false else {
        return
    }

    commitActiveTextEditIfNeeded()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .any(of: [.images, .videos])
    configuration.selectionLimit = 0

    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handlePasteRequest()
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    isTransitionInteractionFrozen == false &&
        isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

// ... 省略 performDrop / picker(didFinishPicking:) 中其它同类直接 guard 逻辑 ...

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    isTransitionInteractionFrozen == false &&
        isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource / interactionPolicy / handleTransferEntryAttempt / isTransferEntryAllowed
// 功能说明: 修改后 iOS 的 transfer 入口先归一成 CanvasTransferEntryIntent，经 shared policy 判定 allow/block 后，再继续原有 continuation。
private enum TransferEntryDeliverySource {
    case iOSKeyCommand
    case importButton
    case dragAndDrop
}

private let interactionPolicy = CanvasInteractionPolicy()

@objc
private func handleImportButtonTap() {
    handleTransferEntryAttempt(
        .importButton,
        deliverySource: .importButton
    ) {
        commitActiveTextEditIfNeeded()
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0

        let pickerViewController = PHPickerViewController(configuration: configuration)
        pickerViewController.delegate = self
        present(pickerViewController, animated: true)
        return true
    }
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleTransferEntryAttempt(
        .pasteKeyboardShortcut,
        deliverySource: .iOSKeyCommand
    ) {
        handlePasteRequest()
        return true
    }
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    isTransferEntryAllowed(.dragAndDrop) &&
        iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard
        results.isEmpty == false,
        isTransferEntryAllowed(.importButton)
    else {
        return
    }

    // ... 省略下游 adapter 解析细节 ...
}

private func makeInteractionEnvironment() -> CanvasInteractionEnvironment {
    CanvasInteractionEnvironment(
        workspaceMode: workspaceMode,
        isTransitionInteractionFrozen: isTransitionInteractionFrozen
    )
}

private func transferEntryDecision(
    for entry: CanvasTransferEntryIntent
) -> CanvasInteractionDecision {
    interactionPolicy.decision(
        for: .transferEntry(entry),
        environment: makeInteractionEnvironment()
    )
}

@discardableResult
private func handleTransferEntryAttempt(
    _ entry: CanvasTransferEntryIntent,
    deliverySource: TransferEntryDeliverySource,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = transferEntryDecision(for: entry)
    switch decision {
    case .allow:
        return continueIfAllowed()
    case .block(_, let feedback):
        if let feedback {
            applyInteractionFeedback(feedback)
        }
        return false
    }
}
```

### 修改意图

这一步把 iOS 侧原先分散在 import button、paste、drag-drop、picker completion 里的 reading/frozen 判断统一上提成 shared policy：

1. 标准键盘 paste 入口先归一成 `.pasteKeyboardShortcut`。
2. import button 与 photo picker completion 统一按 `.importButton` 语义重判。
3. drag/drop 的 `canHandle`、`sessionDidUpdate` 与 `performDrop` 都改为先问 policy，再决定是否继续解析 payload。
4. `applyInteractionFeedback(_:)` 这次只留占位，`phase3` 再把 `.shakeWorkspaceModeButton` 真正映射成动画。

## 修改二：macOS 标准 transfer capture 改为共享 policy 驱动

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: validateUserInterfaceItem / paste / handleImportButtonClick / canTransferContent / handleImportDrop
// 功能说明: 修改前 macOS 的标准 paste、open panel 与 drag-drop 入口仍然直接依赖 controller 本地 guard，没有把标准 capture 归一到 shared policy。
func validateUserInterfaceItem(
    _ item: any NSValidatedUserInterfaceItem
) -> Bool {
    switch item.action {
    case #selector(macOSViewController.paste(_:)):
        return canTransferContent(from: .general)
    default:
        return true
    }
}

@objc
func paste(_ sender: Any?) {
    guard isTransitionInteractionFrozen == false else {
        return
    }

    handlePasteRequest()
}

private func handleImportButtonClick() {
    guard isReadingModeActive == false else {
        return
    }

    // ... 省略 openPanel 配置 ...

    openPanel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let self else {
            return
        }

        guard self.isReadingModeActive == false else {
            return
        }

        guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
            from: openPanel.urls,
            sourceDescription: "open panel"
        ) else {
            return
        }

        _ = self.performTransferRequest(transferRequest)
    }
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

    // ... 省略 transferRequest / performTransferRequest ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource / resolvedPasteTransferEntryIntent / handleTransferEntryAttempt / canTransferContent(from:entry:)
// 功能说明: 修改后 macOS 的标准可观测 transfer capture 先归一为 transfer intent，validate、paste、open panel 与 drag-drop 都先问 shared policy。
private enum TransferEntryDeliverySource {
    case macOSPasteAction
    case importButton
    case dragAndDrop
}

private let interactionPolicy = CanvasInteractionPolicy()

func validateUserInterfaceItem(
    _ item: any NSValidatedUserInterfaceItem
) -> Bool {
    switch item.action {
    case #selector(macOSViewController.paste(_:)):
        return canTransferContent(
            from: .general,
            entry: resolvedPasteTransferEntryIntent()
        )
    default:
        return true
    }
}

@objc
func paste(_ sender: Any?) {
    handleTransferEntryAttempt(
        resolvedPasteTransferEntryIntent(),
        deliverySource: .macOSPasteAction
    ) {
        handlePasteRequest()
        return true
    }
}

private func handleImportButtonClick() {
    handleTransferEntryAttempt(
        .importButton,
        deliverySource: .importButton
    ) {
        // ... 省略 openPanel 配置 ...
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else {
                return
            }

            guard self.isTransferEntryAllowed(.importButton) else {
                return
            }

            // ... 省略 transferRequest / performTransferRequest ...
        }
        return true
    }
}

private func resolvedPasteTransferEntryIntent() -> CanvasTransferEntryIntent {
    if NSApp.currentEvent?.type == .keyDown {
        return .pasteKeyboardShortcut
    }

    return .pasteMenu
}

private func canTransferContent(
    from pasteboard: NSPasteboard,
    entry: CanvasTransferEntryIntent
) -> Bool {
    isTransferEntryAllowed(entry) &&
        macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
    canTransferContent(from: pasteboard, entry: .dragAndDrop) ? .copy : []
}

private func handleImportDrop(
    pasteboard: NSPasteboard
) -> Bool {
    guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: pasteboard,
        sourceDescription: "drag and drop"
    ) else {
        return false
    }

    let didImport = performTransferRequest(transferRequest)
    if didImport {
        view.window?.makeFirstResponder(canvasViewportView)
    }

    return didImport
}
```

### 修改意图

这一步把 macOS 这条“标准可观测 capture”链先统一到 shared policy：

1. `validateUserInterfaceItem(_:)` 不再直接看本地 reading/frozen guard，而是通过 `entry` 语义判定标准 paste 是否可走。
2. `paste(_:)` 会根据 `NSApp.currentEvent?.type` 区分 `.pasteKeyboardShortcut` 与 `.pasteMenu`，再归一到 `handleTransferEntryAttempt(...)`。
3. open panel completion 与 drag/drop completion 都在真正解析 payload 之前重问一次 policy，避免入口打开后模式变化导致继续执行旧 continuation。
4. `handleImportDrop(...)` 里移除了本地 reading/frozen guard，统一把“先判定”责任上提到 `handleTransferEntryAttempt(...)`。
5. `phase2` 仍只覆盖标准可观测 capture；阅读模式下 `macOS` 键盘 paste attempt 的补充捕获缺口，明确留给 `phase3`。

## 修改三：补 phase2 的 policy 回归测试

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testPasteKeyboardShortcutPrioritizesFrozenBlockInReadingMode / testCommandAllowsInEditingModeWhenNotFrozen
// 功能说明: 修改前测试只覆盖 pasteKeyboardShortcut 与 command 的基础语义，还没有锁定 importButton / dragAndDrop 在 reading mode 下的 block 行为。
func testPasteKeyboardShortcutPrioritizesFrozenBlockInReadingMode() {
    let decision = policy.decision(
        for: .transferEntry(.pasteKeyboardShortcut),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: true)
    )

    XCTAssertEqual(
        decision,
        .block(reason: .transitionInteractionFrozen, feedback: nil)
    )
}

func testCommandAllowsInEditingModeWhenNotFrozen() {
    let decision = policy.decision(
        for: .command(.undo),
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
    )

    XCTAssertEqual(decision, .allow)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testImportButtonBlocksInReadingModeWithoutFeedback / testDragAndDropBlocksInReadingModeWithoutFeedback
// 功能说明: 修改后新增 phase2 回归测试，明确 importButton 与 dragAndDrop 在 reading mode 下会被 shared policy 阻断且不返回按钮反馈。
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

### 修改意图

`phase2` 已经把 import button 与 drag/drop 真实接到了运行时路径里，所以这一步额外把它们的 shared policy 语义补成回归测试，避免后续 `phase3` 接反馈桥或 `phase4` 接 command lane 时把这两个 transfer entry 的阻断行为改歪。

## 验证结果

本次记录对应的实际验证结果如下：

- `ReadLints` 对 `iOSViewController.swift`、`macOSViewController.swift`、`CanvasInteractionPolicyTests.swift` 的读取结果为：无 linter 报错
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build` 结果为：`BUILD SUCCEEDED`
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build` 结果为：`BUILD SUCCEEDED`
- 本次 `phase2` 没有额外执行 `xcodebuild test`，因此本记录不新增完整 test target 的运行结论

构建输出里观测到的既有 warning 现象包括：

- `BoardSaveCoordinator.swift` 中与 `CanvasImageAssetReference` 相关的 Swift 6 actor warning
- `BoardDocumentMapper.swift` 中同步上下文调用 main actor 方法的 warning
- `appintentsmetadataprocessor` 的 `Metadata extraction skipped. No AppIntents.framework dependency found.`

上述 warning 没有阻断本次 `phase2` 的双端 build 成功。

## 与当前其他 changes 的边界说明

这次 `phase2` 记录只覆盖上面 3 个业务代码文件，不覆盖当前工作区里另一个已存在的 `.md` 计划文件变更：

- `M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`

该 `.md` 文件在本次记录写入过程中未被我删除、修改或回滚；这里只做如实说明，不把它混入本次 `phase2` 代码变更记录。
