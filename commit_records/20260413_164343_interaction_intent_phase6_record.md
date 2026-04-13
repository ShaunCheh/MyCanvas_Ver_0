# 20260413_164343_interaction_intent_phase6_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase6` 清理重复 guard、统一 interaction gate 日志并补 shared 测试”的实际 `git status`、`git diff --stat`、`git diff`、构建结果、测试结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 7 个业务/测试文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift`
- `MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前，当前工作区状态依据如下：

- `git status --short` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short` 显示本次 `phase6` 当前 changes 包含 7 个已跟踪源码/测试文件
- `git diff --stat -- <7 个 phase6 文件>` 统计为：`7 files changed, 347 insertions(+), 69 deletions(-)`
- 本记录文件是在上述取证之后新增的说明材料，不属于上面 7 个业务/测试文件本身

本记录不包含：

- 原始 `git diff` 文本
- `git commit` / `git push`
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- 计划里的手工回归矩阵真实执行结果；本次只完成了代码与自动化验证侧的收口

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date "+%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git branch / git status / git diff --stat / git diff
# 功能说明: 提取本次 phase6 的分支信息、当前工作区状态、统计信息与 7 个业务/测试文件的真实改动范围。
git branch --show-current

git status --short

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift"
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / xcodebuild test
# 功能说明: 验证 phase6 清理后的 macOS 编译状态，并如实记录 targeted test 继续被既有测试文件阻断的情况。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build

xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests \
  test
```

## 本次 phase6 的目标

这一步不再新增新的 intent lane，而是围绕已经落地的收敛结构做最后一轮清理和验证：

1. 删除已经被 policy 覆盖的展示层 / 入口层重复 guard。
2. 保留 `performTransferRequest(_:)` 这类末端 safety net，不冒然去掉底线防护。
3. 把 interaction gate 的 debug 日志格式统一成可追踪的 `intent / decision / reason / feedback / workspaceMode / frozen`。
4. 补齐 `reading`、`frozen`、显式 environment override 这些 phase6 更关心的 shared 测试。

## 修改一：给 intent / decision 补统一调试命名

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent / CanvasInteractionIntent
// 功能说明: 修改前 shared intent 只有语义枚举本身，还没有统一的 debugName，controller / resolver 想打 interaction gate 日志时只能各自拼字符串。
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionBlockReason / CanvasInteractionFeedbackHint / CanvasInteractionDecision
// 功能说明: 修改前 decision 模型只表达 allow / block 语义，没有统一的调试字符串接口，日志层需要分别取 reason / feedback 再自己转换。
enum CanvasInteractionBlockReason: Equatable, Sendable {
    case readingMode
    case transitionInteractionFrozen
}

enum CanvasInteractionFeedbackHint: Equatable, Sendable {
    case shakeWorkspaceModeButton
}

enum CanvasInteractionDecision: Equatable, Sendable {
    case allow
    case block(
        reason: CanvasInteractionBlockReason,
        feedback: CanvasInteractionFeedbackHint?
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent.debugName / CanvasInteractionIntent.debugName
// 功能说明: 修改后为 transfer entry 与 interaction intent 补统一 debugName，让 shared resolver 与双端 controller 可以稳定输出同一套 intent 名称。
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}

extension CanvasTransferEntryIntent {
    var debugName: String {
        switch self {
        case .pasteKeyboardShortcut:
            return "pasteKeyboardShortcut"
        case .pasteMenu:
            return "pasteMenu"
        case .importButton:
            return "importButton"
        case .dragAndDrop:
            return "dragAndDrop"
        }
    }
}

extension CanvasInteractionIntent {
    var debugName: String {
        switch self {
        case .transferEntry(let entry):
            return "transferEntry.\(entry.debugName)"
        case .command(let commandID):
            return "command.\(commandID.rawValue)"
        case .contextMenuRequest:
            return "contextMenuRequest"
        case .beginTextEdit:
            return "beginTextEdit"
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionBlockReason.debugName / CanvasInteractionFeedbackHint.debugName / CanvasInteractionDecision.debugName / blockReason / feedbackHint
// 功能说明: 修改后为 block reason、feedback hint 与最终 decision 补统一调试入口，并直接暴露 blockReason / feedbackHint 方便日志层消费。
enum CanvasInteractionDecision: Equatable, Sendable {
    case allow
    case block(
        reason: CanvasInteractionBlockReason,
        feedback: CanvasInteractionFeedbackHint?
    )
}

extension CanvasInteractionBlockReason {
    var debugName: String {
        switch self {
        case .readingMode:
            return "readingMode"
        case .transitionInteractionFrozen:
            return "transitionInteractionFrozen"
        }
    }
}

extension CanvasInteractionFeedbackHint {
    var debugName: String {
        switch self {
        case .shakeWorkspaceModeButton:
            return "shakeWorkspaceModeButton"
        }
    }
}

extension CanvasInteractionDecision {
    var debugName: String {
        switch self {
        case .allow:
            return "allow"
        case .block:
            return "block"
        }
    }

    var blockReason: CanvasInteractionBlockReason? {
        switch self {
        case .allow:
            return nil
        case .block(let reason, _):
            return reason
        }
    }

    var feedbackHint: CanvasInteractionFeedbackHint? {
        switch self {
        case .allow:
            return nil
        case .block(_, let feedback):
            return feedback
        }
    }
}
```

### 修改意图

这一步先统一 shared 层的“可观测性”命名，避免 `phase6` 本来是想收敛日志，最后却在 resolver、iOS、macOS 各自再造一套字符串协议。

## 修改二：`CanvasContextMenuActionResolver` 从局部 print 迁到统一 interaction gate 日志

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: CanvasContextMenuActionResolver.actionStates(for:session:environment:)
// 功能说明: 修改前 resolver 已经会走 shared policy，但 block / allow 后仍然分别手写不同 print，日志字段不统一，也没有显式输出 decision / feedback / frozen。
func actionStates(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession,
    environment: CanvasInteractionEnvironment? = nil
) -> [CanvasContextMenuActionState] {
    let resolvedEnvironment = environment ?? .workspaceModeOnly(
        workspaceMode: session.workspaceMode
    )
    let candidateActionIDs = candidateActionIDs(
        for: context,
        session: session
    )
    switch interactionPolicy.decision(
    for: .contextMenuRequest,
    environment: resolvedEnvironment
    ) {
    case .allow:
        break
    case .block(let reason, _):
        print(
            "[Canvas Shared][ContextMenuActions] " +
            context.debugSummary + " " +
            "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
            "enabledIDs=[] " +
            "disabledIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
            "reason=\(describeInteractionBlockReason(reason))"
        )
        return []
    }

    // ... 省略后续 enabled/disabled 输出 ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: CanvasContextMenuActionResolver.actionStates(for:session:environment:) / logContextMenuInteractionDecision(...)
// 功能说明: 修改后 resolver 会先固定 intent 和 decision，再统一通过 logContextMenuInteractionDecision(...) 输出 interaction gate 字段，不再区分 block/allow 两套临时 print。
func actionStates(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession,
    environment: CanvasInteractionEnvironment? = nil
) -> [CanvasContextMenuActionState] {
    let resolvedEnvironment = environment ?? .workspaceModeOnly(
        workspaceMode: session.workspaceMode
    )
    let intent = CanvasInteractionIntent.contextMenuRequest
    let candidateActionIDs = candidateActionIDs(
        for: context,
        session: session
    )
    let decision = interactionPolicy.decision(
        for: intent,
        environment: resolvedEnvironment
    )
    switch decision {
    case .allow:
        break
    case .block:
        logContextMenuInteractionDecision(
            intent: intent,
            decision: decision,
            environment: resolvedEnvironment,
            context: context,
            candidateActionIDs: candidateActionIDs,
            enabledActionIDs: [],
            disabledActionIDs: candidateActionIDs
        )
        return []
    }

    // ... 省略 actionStates 计算 ...

    logContextMenuInteractionDecision(
        intent: intent,
        decision: decision,
        environment: resolvedEnvironment,
        context: context,
        candidateActionIDs: candidateActionIDs,
        enabledActionIDs: enabledStates.map(\.actionID),
        disabledActionIDs: disabledIDs
    )
    return enabledStates
}

private func logContextMenuInteractionDecision(
    intent: CanvasInteractionIntent,
    decision: CanvasInteractionDecision,
    environment: CanvasInteractionEnvironment,
    context: CanvasContextMenuContext,
    candidateActionIDs: [CanvasContextMenuActionID],
    enabledActionIDs: [CanvasContextMenuActionID],
    disabledActionIDs: [CanvasContextMenuActionID]
) {
    print(
        "[Canvas Shared][InteractionGate] " +
        "source=\"contextMenuResolver\" " +
        "intent=\(intent.debugName) " +
        "decision=\(decision.debugName) " +
        "reason=\(decision.blockReason?.debugName ?? "none") " +
        "feedback=\(decision.feedbackHint?.debugName ?? "none") " +
        "workspaceMode=\(environment.workspaceMode.rawValue) " +
        "frozen=\(environment.isTransitionInteractionFrozen) " +
        context.debugSummary + " " +
        "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
        "enabledIDs=[\(describeContextMenuActionIDs(enabledActionIDs))] " +
        "disabledIDs=[\(describeContextMenuActionIDs(disabledActionIDs))]"
    )
}
```

### 修改意图

这一步让 shared resolver 的日志不再只是“打印一下当前有哪些 action”，而是真正进入 `phase6` 要求的 interaction gate 观测格式，能看出 intent、decision、block reason、feedback、workspaceMode 和 frozen。

## 修改三：iOS 入口层删除重复 guard，但保留 transfer safety net

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupCanvasViewport / handleLongPress(at:) / dropInteraction(_:performDrop:) / picker(_:didFinishPicking:)
// 功能说明: 修改前 iOS 既在 viewport callback 层挡 long press，又在 longPress / drag-drop / picker continuation 里保留重复的 query guard，interaction 日志也还没有统一格式。
canvasViewportView.onLongPress = { [weak self] location in
    guard self?.isTransitionInteractionFrozen == false else {
        return
    }
    self?.handleLongPress(at: location)
}

private func handleLongPress(at location: CGPoint) {
    // ... 省略 viewport size 判定 ...
    guard isInteractionAllowed(.contextMenuRequest) else {
        dismissContextMenu()
        return
    }

    // ... 省略后续 context menu 展示 ...
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    performDrop session: UIDropSession
) {
    handleTransferEntryAttempt(
        .dragAndDrop,
        deliverySource: .dragAndDrop
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard self.isTransferEntryAllowed(.dragAndDrop) else {
                return
            }

            guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
                from: session,
                sourceDescription: "drag and drop"
            ) else {
                return
            }

            _ = self.performTransferRequest(transferRequest)
            self.becomeFirstResponder()
        }
        return true
    }
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard
        results.isEmpty == false,
        isTransferEntryAllowed(.importButton)
    else {
        return
    }

    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        guard self.isTransferEntryAllowed(.importButton) else {
            return
        }

        // ... 省略 transferRequest 构造与 import ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:continueIfAllowed:) / performTransferRequest(_:) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 interactionAttempt 只是一个本地 gate helper，不会输出统一日志；performTransferRequest 仍然只有裸 guard；beginTextEdit 虽已走 policy，但还没有 sourceDescription。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
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

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard
        isTransitionInteractionFrozen == false,
        isReadingModeActive == false
    else {
        return false
    }

    // ... 省略 lower/import ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    handleInteractionAttempt(.beginTextEdit(itemID: itemID)) {
        guard scene.textItem(withID: itemID) != nil else {
            return false
        }

        performCommand(.beginTextEdit(itemID: itemID))
        return isInlineTextModeActive
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource.debugName / setupCanvasViewport / handleLongPress(at:) / dropInteraction(_:performDrop:) / picker(_:didFinishPicking:)
// 功能说明: 修改后 iOS 删除了已被 policy 覆盖的 longPress callback 与异步 continuation 重复 guard；longPress 改为直接走带日志的 handleInteractionAttempt，import / drag 异步阶段只保留 transferRequest 解析与末端 safety net。
private enum TransferEntryDeliverySource {
    case iOSKeyCommand
    case importButton
    case dragAndDrop

    var debugName: String {
        switch self {
        case .iOSKeyCommand:
            return "iOSKeyCommand"
        case .importButton:
            return "importButton"
        case .dragAndDrop:
            return "dragAndDrop"
        }
    }
}

canvasViewportView.onLongPress = { [weak self] location in
    self?.handleLongPress(at: location)
}

private func handleLongPress(at location: CGPoint) {
    // ... 省略 viewport size 判定 ...
    guard handleInteractionAttempt(
        .contextMenuRequest,
        sourceDescription: "longPress",
        continueIfAllowed: { true }
    ) else {
        dismissContextMenu()
        return
    }

    // ... 省略后续 context menu 展示 ...
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    performDrop session: UIDropSession
) {
    handleTransferEntryAttempt(
        .dragAndDrop,
        deliverySource: .dragAndDrop
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
                from: session,
                sourceDescription: "drag and drop"
            ) else {
                return
            }

            _ = self.performTransferRequest(transferRequest)
            self.becomeFirstResponder()
        }
        return true
    }
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard results.isEmpty == false else {
        return
    }

    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
            from: results,
            sourceDescription: "photo picker"
        ) else {
            return
        }

        _ = self.performTransferRequest(transferRequest)
        self.becomeFirstResponder()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:sourceDescription:continueIfAllowed:) / logInteractionDecision(...) / transferSafetyNetBlockReason() / logTransferSafetyNetBlock(...) / performTransferRequest(_:) / beginTextEditIfPossible(for:)
// 功能说明: 修改后 iOS 的 interactionAttempt 会先统一打 gate 日志；performTransferRequest 保留末端 safety net，但改为显式记录 block reason；beginTextEdit 也补上 sourceDescription。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    sourceDescription: String,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
    logInteractionDecision(
        intent: intent,
        decision: decision,
        sourceDescription: sourceDescription
    )
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

private func logInteractionDecision(
    intent: CanvasInteractionIntent,
    decision: CanvasInteractionDecision,
    sourceDescription: String
) {
    print(
        "[Canvas iOS][InteractionGate] " +
        "source=\"\(sourceDescription)\" " +
        "intent=\(intent.debugName) " +
        "decision=\(decision.debugName) " +
        "reason=\(decision.blockReason?.debugName ?? "none") " +
        "feedback=\(decision.feedbackHint?.debugName ?? "none") " +
        "workspaceMode=\(workspaceMode.rawValue) " +
        "frozen=\(isTransitionInteractionFrozen)"
    )
}

private func transferSafetyNetBlockReason() -> CanvasInteractionBlockReason? {
    if isTransitionInteractionFrozen {
        return .transitionInteractionFrozen
    }

    if isReadingModeActive {
        return .readingMode
    }

    return nil
}

private func logTransferSafetyNetBlock(
    request: CanvasTransferRequest,
    reason: CanvasInteractionBlockReason
) {
    print(
        "[Canvas iOS][InteractionGate] " +
        "source=\"\(request.sourceDescription)\" " +
        "intent=transferRequestSafetyNet " +
        "decision=block " +
        "reason=\(reason.debugName) " +
        "feedback=none " +
        "workspaceMode=\(workspaceMode.rawValue) " +
        "frozen=\(isTransitionInteractionFrozen)"
    )
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    if let reason = transferSafetyNetBlockReason() {
        logTransferSafetyNetBlock(request: request, reason: reason)
        return false
    }

    // ... 省略 lower/import ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    handleInteractionAttempt(
        .beginTextEdit(itemID: itemID),
        sourceDescription: "itemTapReentry"
    ) {
        guard scene.textItem(withID: itemID) != nil else {
            return false
        }

        performCommand(.beginTextEdit(itemID: itemID))
        return isInlineTextModeActive
    }
}
```

### 修改意图

phase6 对 iOS 的核心不是“再多加一层判断”，而是把已经被 shared policy 覆盖的重复入口 guard 清掉，同时把保留下来的末端 safety net 变成可追踪的、会显式吐出 block reason 的底线防护。

## 修改四：macOS 入口层做同样清理，并保持 supplemental capture 逻辑不动

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupCanvasViewport / handleSecondaryClick(at:) / handleImportButtonClick()
// 功能说明: 修改前 macOS 和 iOS 一样，在 secondaryClick callback、secondaryClick 自身、openPanel completion 里都留有不同层次的重复 gate。
canvasViewportView.onSecondaryClick = { [weak self] location in
    guard self?.isTransitionInteractionFrozen == false else {
        return
    }
    self?.handleSecondaryClick(at: location)
}

private func handleSecondaryClick(at location: CGPoint) {
    guard isInteractionAllowed(.contextMenuRequest) else {
        dismissContextMenu()
        return
    }

    // ... 省略后续 secondary click 处理 ...
}

private func handleImportButtonClick() {
    handleTransferEntryAttempt(
        .importButton,
        deliverySource: .importButton
    ) {
        // ... 省略 openPanel 初始化 ...
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let self
            else {
                return
            }

            guard self.isTransferEntryAllowed(.importButton) else {
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
        return true
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:continueIfAllowed:) / performTransferRequest(_:) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 macOS 的 interactionAttempt 还没有统一日志；performTransferRequest 仍然是裸 safety net；beginTextEdit 没有 sourceDescription。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
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

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard
        isTransitionInteractionFrozen == false,
        isReadingModeActive == false
    else {
        return false
    }

    // ... 省略 lower/import ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    handleInteractionAttempt(.beginTextEdit(itemID: itemID)) {
        guard scene.textItem(withID: itemID) != nil else {
            return false
        }

        performCommand(.beginTextEdit(itemID: itemID))
        return isInlineTextModeActive
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: TransferEntryDeliverySource.debugName / setupCanvasViewport / handleSecondaryClick(at:) / handleImportButtonClick()
// 功能说明: 修改后 macOS 删掉 secondaryClick callback 与 openPanel completion 里已被 policy 覆盖的重复 guard，但保留 supplemental keyboard capture 那条 phase3 的特殊路径不动。
private enum TransferEntryDeliverySource {
    case macOSPasteAction
    case macOSLocalKeyMonitor
    case importButton
    case dragAndDrop

    var debugName: String {
        switch self {
        case .macOSPasteAction:
            return "macOSPasteAction"
        case .macOSLocalKeyMonitor:
            return "macOSLocalKeyMonitor"
        case .importButton:
            return "importButton"
        case .dragAndDrop:
            return "dragAndDrop"
        }
    }
}

canvasViewportView.onSecondaryClick = { [weak self] location in
    self?.handleSecondaryClick(at: location)
}

private func handleSecondaryClick(at location: CGPoint) {
    guard handleInteractionAttempt(
        .contextMenuRequest,
        sourceDescription: "secondaryClick",
        continueIfAllowed: { true }
    ) else {
        dismissContextMenu()
        return
    }

    // ... 省略后续 secondary click 处理 ...
}

private func handleImportButtonClick() {
    handleTransferEntryAttempt(
        .importButton,
        deliverySource: .importButton
    ) {
        // ... 省略 openPanel 初始化 ...
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let self
            else {
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
        return true
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:sourceDescription:continueIfAllowed:) / logInteractionDecision(...) / transferSafetyNetBlockReason() / logTransferSafetyNetBlock(...) / performTransferRequest(_:) / beginTextEditIfPossible(for:)
// 功能说明: 修改后 macOS 和 iOS 一样，入口层先统一打 gate 日志；transfer safety net 仍保留在 performTransferRequest 末端，但现在会如实记录 block reason；beginTextEdit 也补上来源描述。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    sourceDescription: String,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
    logInteractionDecision(
        intent: intent,
        decision: decision,
        sourceDescription: sourceDescription
    )
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

private func logInteractionDecision(
    intent: CanvasInteractionIntent,
    decision: CanvasInteractionDecision,
    sourceDescription: String
) {
    print(
        "[Canvas macOS][InteractionGate] " +
        "source=\"\(sourceDescription)\" " +
        "intent=\(intent.debugName) " +
        "decision=\(decision.debugName) " +
        "reason=\(decision.blockReason?.debugName ?? "none") " +
        "feedback=\(decision.feedbackHint?.debugName ?? "none") " +
        "workspaceMode=\(workspaceMode.rawValue) " +
        "frozen=\(isTransitionInteractionFrozen)"
    )
}

private func transferSafetyNetBlockReason() -> CanvasInteractionBlockReason? {
    if isTransitionInteractionFrozen {
        return .transitionInteractionFrozen
    }

    if isReadingModeActive {
        return .readingMode
    }

    return nil
}

private func logTransferSafetyNetBlock(
    request: CanvasTransferRequest,
    reason: CanvasInteractionBlockReason
) {
    print(
        "[Canvas macOS][InteractionGate] " +
        "source=\"\(request.sourceDescription)\" " +
        "intent=transferRequestSafetyNet " +
        "decision=block " +
        "reason=\(reason.debugName) " +
        "feedback=none " +
        "workspaceMode=\(workspaceMode.rawValue) " +
        "frozen=\(isTransitionInteractionFrozen)"
    )
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    if let reason = transferSafetyNetBlockReason() {
        logTransferSafetyNetBlock(request: request, reason: reason)
        return false
    }

    // ... 省略 lower/import ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    handleInteractionAttempt(
        .beginTextEdit(itemID: itemID),
        sourceDescription: "itemClickReentry"
    ) {
        guard scene.textItem(withID: itemID) != nil else {
            return false
        }

        performCommand(.beginTextEdit(itemID: itemID))
        return isInlineTextModeActive
    }
}
```

### 修改意图

macOS 的重点是“入口层重复判断减少，但 phase3 的特殊 capture 能力不回退”。因此本次只清理已经被 policy 和 safety net 双覆盖的重复 guard，不动 `shouldEnableSupplementalKeyboardCapture()` / `handleSupplementalKeyboardCapture(_:)` 这类仍有平台价值的逻辑。

## 修改五：补 shared tests，锁定 frozen / 显式 environment override 语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: CanvasInteractionPolicyTests
// 功能说明: 修改前 policy tests 已覆盖 transfer entry、command、reading-mode context menu 与 beginTextEdit，但还没有显式锁定 editing+frozen、reading+frozen 优先级，以及 beginTextEdit 在 editing+notFrozen 下的 allow。
func testContextMenuRequestAllowsInEditingModeWhenNotFrozen() {
    let decision = policy.decision(
        for: .contextMenuRequest,
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
    )

    XCTAssertEqual(decision, .allow)
}

func testContextMenuRequestBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .contextMenuRequest,
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}

func testBeginTextEditBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .beginTextEdit(itemID: CanvasItemID()),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数名/符号名: CanvasContextMenuActionResolverTests
// 功能说明: 修改前 resolver tests 已覆盖 session.reading 与 explicit frozen environment，但还没有锁定“session 仍是 editing、显式 environment 却要求 reading”时 resolver 也必须服从注入环境。
func testReadingModeReturnsNoActionsEvenWhenContextHasCandidates() throws {
    let session = makeContextMenuActionResolverTestSession()
    // ... 省略测试数据构造 ...
    session.workspaceMode = .reading

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: imageItem.id,
            selectedItemID: imageItem.id
        ),
        session: session
    )

    XCTAssertTrue(actionStates.isEmpty)
}

func testFrozenEnvironmentReturnsNoActionsEvenInEditingMode() throws {
    let session = makeContextMenuActionResolverTestSession()
    // ... 省略测试数据构造 ...

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: imageItem.id,
            selectedItemID: imageItem.id
        ),
        session: session,
        environment: makeContextMenuEnvironment(
            workspaceMode: .editing,
            isFrozen: true
        )
    )

    XCTAssertTrue(actionStates.isEmpty)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testContextMenuRequestBlocksInEditingModeWhenFrozen / testContextMenuRequestPrioritizesFrozenBlockInReadingMode / testBeginTextEditAllowsInEditingModeWhenNotFrozen
// 功能说明: 修改后 policy tests 明确锁定 contextMenuRequest 和 beginTextEdit 在 frozen 优先级、editing allow、reading/frozen 组合下的 shared decision。
func testContextMenuRequestBlocksInEditingModeWhenFrozen() {
    let decision = policy.decision(
        for: .contextMenuRequest,
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: true)
    )

    XCTAssertEqual(
        decision,
        .block(reason: .transitionInteractionFrozen, feedback: nil)
    )
}

func testContextMenuRequestPrioritizesFrozenBlockInReadingMode() {
    let decision = policy.decision(
        for: .contextMenuRequest,
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: true)
    )

    XCTAssertEqual(
        decision,
        .block(reason: .transitionInteractionFrozen, feedback: nil)
    )
}

func testBeginTextEditAllowsInEditingModeWhenNotFrozen() {
    let decision = policy.decision(
        for: .beginTextEdit(itemID: CanvasItemID()),
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
    )

    XCTAssertEqual(decision, .allow)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数名/符号名: testExplicitReadingEnvironmentReturnsNoActionsEvenWhenSessionEditing
// 功能说明: 修改后 resolver tests 明确锁定“session 还是 editing，但外部显式注入 reading environment”时 actionStates 也必须为空，证明 resolver 真正服从注入环境而不是偷偷读 session。
func testExplicitReadingEnvironmentReturnsNoActionsEvenWhenSessionEditing() throws {
    let session = makeContextMenuActionResolverTestSession()
    let imageItem = CanvasImageItem(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: try makeContextMenuActionResolverTestImage(
                red: 0.6,
                green: 0.2,
                blue: 0.8
            )
        ),
        center: CGPoint(x: 48, y: 62),
        size: CGSize(width: 118, height: 88),
        zIndex: 0
    )
    session.scene.append(imageItem)

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: imageItem.id,
            selectedItemID: imageItem.id
        ),
        session: session,
        environment: makeContextMenuEnvironment(
            workspaceMode: .reading,
            isFrozen: false
        )
    )

    XCTAssertTrue(actionStates.isEmpty)
}
```

### 修改意图

phase6 的测试重点不是再铺更多路径，而是确认“policy 已覆盖”的地方真的可删掉重复 guard，而且 resolver/controller 不会因为保留旧习惯而偷偷绕回 `session.isReadingModeActive`。

## 构建与测试结果

本次验证结果如下：

- `ReadLints` 未发现这 7 个 phase6 文件的新增诊断
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build` 成功
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests test` 未完成，不是 phase6 新代码编译失败，而是继续被既有测试文件 `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 的 `BoardRuntimeState` 初始化参数错误阻断
- 计划里的双端手工回归矩阵本次未实际执行

```bash
# 文件路径: xcodebuild build 输出摘录
# 函数名/命令名: xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build
# 功能说明: 如实记录 phase6 修改完成后 macOS app target 可以成功完成构建。
CodeSign .../Build/Products/Debug/MyCanvas_Ver_0.app
Validate .../Build/Products/Debug/MyCanvas_Ver_0.app
RegisterWithLaunchServices .../Build/Products/Debug/MyCanvas_Ver_0.app
** BUILD SUCCEEDED **
```

```bash
# 文件路径: xcodebuild test 输出摘录
# 函数名/命令名: xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests test
# 功能说明: 如实记录 phase6 相关测试文件已进入编译，但整个 test 过程仍被既有的 AlignmentOverlayTests 编译错误中断。
SwiftCompile normal arm64 .../MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
SwiftCompile normal arm64 .../MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
SwiftCompile normal arm64 .../MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
.../MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:320:20: error: extra argument 'updatedAt' in call
.../MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:316:22: error: missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
Testing cancelled because the build failed.
```

## 本次 phase6 的结果归纳

这次 `phase6` 完成后，入口层能删掉的重复 guard 已经基本删掉了：iOS 的 `longPress` callback、macOS 的 `secondaryClick` callback、以及 import / drag 异步 continuation 里那几层已经被 policy 覆盖的 query guard 都已下线；同时 `performTransferRequest(_:)` 这类末端 safety net 仍然保留，并且不再静默失败，而是会把 block reason 明确打进统一 interaction gate 日志。

目前仍然保留的查询型 gate 主要是：

- `dropInteraction(...canHandle...)` / `sessionDidUpdate` 这类需要同步回答系统是否可接受拖拽的查询路径
- `validateUserInterfaceItem` / `canTransferContent(...)` 这类需要同步回答菜单或拖拽状态的查询路径
- `CanvasCommandExecutor` 这类末端 command safety net

换句话说，phase6 做的不是“把所有判断都删掉”，而是把真正重复、且已经被 shared policy + 末端 safety net 双覆盖的入口层 guard 清理掉，把必须保留的同步查询和末端兜底留住。
