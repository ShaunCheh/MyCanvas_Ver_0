# 20260413_162108_interaction_intent_phase5_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase5` 非 command 直达入口收敛”的实际 `git status`、`git diff --stat`、`git diff`、构建结果、测试结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 6 个业务/测试文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前，当前工作区状态依据如下：

- `git status --short` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short` 显示本次 `phase5` 当前 changes 包含 6 个已跟踪文件
- `git diff --stat -- <6 个 phase5 文件>` 统计为：`6 files changed, 228 insertions(+), 46 deletions(-)`
- 本记录文件是在上述取证之后新增的说明材料，不属于上面 6 个业务/测试文件本身

本记录不包含：

- 原始 `git diff` 文本
- `git commit` / `git push`
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- `phase6` 的 guard 清理与回归矩阵补齐

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date "+%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff --stat / git diff
# 功能说明: 提取本次 phase5 的当前工作区状态、统计信息与 6 个业务/测试文件的真实改动范围。
git branch --show-current

git status --short

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / xcodebuild test
# 功能说明: 验证 phase5 非 command 直达入口收敛后的 macOS 编译状态，并如实记录 targeted test 被既有测试错误阻断的情况。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build

xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests \
  test
```

## 本次 phase5 的目标

这一步不是继续扩大 transfer entry 的覆盖面，而是把剩余的非 command 直达编辑入口也接入统一 intent-policy 语义：

1. 让 `contextMenuRequest` 不再在 resolver 和 controller 各自手写 reading-mode 特判。
2. 让 iOS / macOS 的长按、右键、`beginTextEditIfPossible(for:)` 都先走 `CanvasInteractionPolicy`。
3. 把 controller 内部已有的 transfer helper 提升成更通用的 interaction helper，避免 direct entry 再复制一套判断分支。
4. 为 `contextMenuRequest`、`beginTextEdit`、`frozen` 场景补 shared policy 与 resolver 回归测试。

## 修改一：为 shared resolver 补 `workspaceModeOnly(...)`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment.commandLane(workspaceMode:)
// 功能说明: 修改前 shared environment 只有 command lane 的归一入口，context menu resolver 这类不掌握 controller-local freeze 状态的调用方还没有通用的 workspace-only 工厂。
struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool

    // Command lane does not own controller-local freeze state, so phase4 only
    // normalizes workspace mode here and keeps transition freeze upstream.
    static func commandLane(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: false
        )
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment.workspaceModeOnly(workspaceMode:) / CanvasInteractionEnvironment.commandLane(workspaceMode:)
// 功能说明: 修改后补出 workspace-only 归一环境，给 shared resolver 这类非 controller-local 调用方复用；原有 commandLane 继续存在，但改为委托给新工厂。
struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool

    // Shared policy consumers outside controller-local capture can normalize to
    // workspace mode only and leave transition freeze at the controller edge.
    static func workspaceModeOnly(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: false
        )
    }

    // Command lane does not own controller-local freeze state, so phase4 only
    // normalizes workspace mode here and keeps transition freeze upstream.
    static func commandLane(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        workspaceModeOnly(workspaceMode: workspaceMode)
    }
}
```

### 修改意图

这一步先把 shared 层真正需要的环境归一入口补齐。这样 `CanvasContextMenuActionResolver` 在 phase5 不必再反向依赖 controller 才能知道“只看 workspace mode 的统一阻断语义”。

## 修改二：`CanvasContextMenuActionResolver` 改为消费统一 interaction policy

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: CanvasContextMenuActionResolver.actionStates(for:session:)
// 功能说明: 修改前 resolver 直接依赖 session.isReadingModeActive 早退，只能表达 reading mode，无法复用 transition frozen 等更通用的 interaction decision。
struct CanvasContextMenuActionResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func actionStates(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasContextMenuActionState] {
        let candidateActionIDs = candidateActionIDs(
            for: context,
            session: session
        )
        if session.isReadingModeActive {
            print(
                "[Canvas Shared][ContextMenuActions] " +
                context.debugSummary + " " +
                "candidateIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
                "enabledIDs=[] " +
                "disabledIDs=[\(describeContextMenuActionIDs(candidateActionIDs))] " +
                "reason=readingMode"
            )
            return []
        }

        // ... 省略后续 descriptor 过滤逻辑 ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/符号名: CanvasContextMenuActionResolver.actionStates(for:session:environment:) / describeInteractionBlockReason(_:)
// 功能说明: 修改后 resolver 先把 contextMenuRequest 送入 shared policy，再决定是否返回 actionStates；当被 block 时，会把 block reason 也写入日志，保持取证可见性。
struct CanvasContextMenuActionResolver {
    private let commandCatalog = CanvasCommandCatalog()
    private let interactionPolicy = CanvasInteractionPolicy()

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

        // ... 省略后续 descriptor 过滤逻辑 ...
    }
}

private func describeInteractionBlockReason(
    _ reason: CanvasInteractionBlockReason
) -> String {
    switch reason {
    case .readingMode:
        return "readingMode"
    case .transitionInteractionFrozen:
        return "transitionInteractionFrozen"
    }
}
```

### 修改意图

这里解决的是根因而不是表面现象：context menu 是否可见，不再由 resolver 自己维护一套 `session.isReadingModeActive` 规则，而是回到 shared policy 这条统一语义线上。

## 修改三：iOS controller 把长按、menu 展示、text edit re-entry 接到统一 interaction helper

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: presentContextMenu(for:) / handleLongPress(at:) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 iOS 的 context menu 与 text edit re-entry 都各自手写 reading-mode 早退，resolver 也拿不到完整 interaction environment。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let actionStates = contextMenuActionResolver.actionStates(
        for: resolvedContext,
        session: editorSession
    )
    guard actionStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    // ... 省略 contextMenuState 赋值 ...
}

private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    guard isReadingModeActive == false else {
        dismissContextMenu()
        return
    }

    // ... 省略长按后续处理 ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: presentContextMenu(for:) / interactionDecision(for:) / isInteractionAllowed(_:) / handleInteractionAttempt(_:continueIfAllowed:)
// 功能说明: 修改后 iOS controller 先统一构造 CanvasInteractionIntent，再让 context menu、text edit、transfer entry 共用同一套 allow/block 处理骨架。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let actionStates = contextMenuActionResolver.actionStates(
        for: resolvedContext,
        session: editorSession,
        environment: makeInteractionEnvironment()
    )
    guard actionStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    // ... 省略 contextMenuState 赋值 ...
}

private func interactionDecision(
    for intent: CanvasInteractionIntent
) -> CanvasInteractionDecision {
    interactionPolicy.decision(
        for: intent,
        environment: makeInteractionEnvironment()
    )
}

private func isInteractionAllowed(
    _ intent: CanvasInteractionIntent
) -> Bool {
    switch interactionDecision(for: intent) {
    case .allow:
        return true
    case .block:
        return false
    }
}

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

private func transferEntryDecision(
    for entry: CanvasTransferEntryIntent
) -> CanvasInteractionDecision {
    interactionDecision(for: .transferEntry(entry))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleLongPress(at:) / beginTextEditIfPossible(for:)
// 功能说明: 修改后长按与 beginTextEdit 都不再直接读 isReadingModeActive，而是先经过 contextMenuRequest / beginTextEdit 这两个 shared intent。
private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    guard isInteractionAllowed(.contextMenuRequest) else {
        dismissContextMenu()
        return
    }

    // ... 省略长按后续处理 ...
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

### 修改意图

这一步把 iOS controller 内已有的 transfer-only helper 升格成通用 interaction helper，避免 `phase5` 再长出第二套 direct-entry 判定逻辑。后面 `phase6` 清理 guard 时，也能围绕这一套统一骨架继续收束。

## 修改四：macOS controller 把右键、menu 展示、text edit re-entry 接到统一 interaction helper

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: presentContextMenu(for:) / handleSecondaryClick(at:) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 macOS 的 secondary click 与 text edit re-entry 和 iOS 一样，各自手写 reading-mode 早退，context menu resolver 只知道 session，不知道 controller-local freeze。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let actionStates = contextMenuActionResolver.actionStates(
        for: resolvedContext,
        session: editorSession
    )
    guard actionStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    // ... 省略 contextMenuState 赋值 ...
}

private func handleSecondaryClick(at location: CGPoint) {
    guard isReadingModeActive == false else {
        dismissContextMenu()
        return
    }

    // ... 省略 secondary click 后续处理 ...
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: presentContextMenu(for:) / interactionDecision(for:) / isInteractionAllowed(_:) / handleInteractionAttempt(_:continueIfAllowed:)
// 功能说明: 修改后 macOS controller 和 iOS 保持同一骨架，让 secondary click、transfer entry、beginTextEdit 都统一落到 CanvasInteractionPolicy。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let actionStates = contextMenuActionResolver.actionStates(
        for: resolvedContext,
        session: editorSession,
        environment: makeInteractionEnvironment()
    )
    guard actionStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    // ... 省略 contextMenuState 赋值 ...
}

private func interactionDecision(
    for intent: CanvasInteractionIntent
) -> CanvasInteractionDecision {
    interactionPolicy.decision(
        for: intent,
        environment: makeInteractionEnvironment()
    )
}

private func isInteractionAllowed(
    _ intent: CanvasInteractionIntent
) -> Bool {
    switch interactionDecision(for: intent) {
    case .allow:
        return true
    case .block:
        return false
    }
}

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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleSecondaryClick(at:) / beginTextEditIfPossible(for:)
// 功能说明: 修改后右键请求与 beginTextEdit 都通过 shared intent 判定是否 allow，reading mode 与 frozen 的阻断语义不再由 macOS controller 私有维护。
private func handleSecondaryClick(at location: CGPoint) {
    guard isInteractionAllowed(.contextMenuRequest) else {
        dismissContextMenu()
        return
    }

    // ... 省略 secondary click 后续处理 ...
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

### 修改意图

macOS 在 phase3 已经为 keyboard paste 建好了额外 capture 层；phase5 的重点不是再补平台分支，而是保证 context menu / text edit 这些直达入口也和 iOS 一样收敛到 shared policy，而不是继续各写各的早退。

## 修改五：补齐 `contextMenuRequest` / `beginTextEdit` 的 shared 测试

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: CanvasInteractionPolicyTests
// 功能说明: 修改前 policy tests 已覆盖 transfer entry 与 command，但还没有显式锁定 contextMenuRequest 和 beginTextEdit 的 allow/block/frozen 行为。
func testDragAndDropBlocksInReadingModeWithoutFeedback() {
    let decision = policy.decision(
        for: .transferEntry(.dragAndDrop),
        environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
}

func testCommandAllowsInEditingModeWhenNotFrozen() {
    let decision = policy.decision(
        for: .command(.undo),
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
    )

    XCTAssertEqual(decision, .allow)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数名/符号名: CanvasContextMenuActionResolverTests
// 功能说明: 修改前 resolver tests 只验证 GIF / video action 暴露，不验证 reading mode 或 frozen 环境下 actionStates 是否被统一清空。
func testVideoItemKeepsVideoActionAndExcludesGIFAction() throws {
    let session = makeContextMenuActionResolverTestSession()
    // ... 省略测试数据构造 ...

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: videoItem.id,
            selectedItemID: videoItem.id
        ),
        session: session
    )

    XCTAssertTrue(actionStates.contains(where: isVideoDisplayFrameAction))
    XCTAssertFalse(actionStates.contains(where: isGIFFrameImportAction))
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: testContextMenuRequestAllowsInEditingModeWhenNotFrozen / testContextMenuRequestBlocksInReadingModeWithoutFeedback / testBeginTextEditBlocksInReadingModeWithoutFeedback / testBeginTextEditPrioritizesFrozenBlockInEditingMode
// 功能说明: 修改后 policy tests 明确锁定 contextMenuRequest 与 beginTextEdit 在 editing / reading / frozen 下的 shared decision，避免 phase5 回归时重新长出 controller 私有语义。
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

func testBeginTextEditPrioritizesFrozenBlockInEditingMode() {
    let decision = policy.decision(
        for: .beginTextEdit(itemID: CanvasItemID()),
        environment: makeEnvironment(workspaceMode: .editing, isFrozen: true)
    )

    XCTAssertEqual(
        decision,
        .block(reason: .transitionInteractionFrozen, feedback: nil)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数名/符号名: testReadingModeReturnsNoActionsEvenWhenContextHasCandidates / testFrozenEnvironmentReturnsNoActionsEvenInEditingMode / makeContextMenuEnvironment(workspaceMode:isFrozen:)
// 功能说明: 修改后 resolver tests 直接锁定 reading mode 与 injected frozen environment 下 actionStates 为空，验证 resolver 已经真正消费统一 policy，而不是只看 session.isReadingModeActive。
func testReadingModeReturnsNoActionsEvenWhenContextHasCandidates() throws {
    let session = makeContextMenuActionResolverTestSession()
    let imageItem = CanvasImageItem(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: try makeContextMenuActionResolverTestImage(
                red: 0.3,
                green: 0.5,
                blue: 0.7
            )
        ),
        center: CGPoint(x: 40, y: 50),
        size: CGSize(width: 120, height: 90),
        zIndex: 0
    )
    session.scene.append(imageItem)
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

private func makeContextMenuEnvironment(
    workspaceMode: CanvasWorkspaceMode,
    isFrozen: Bool
) -> CanvasInteractionEnvironment {
    CanvasInteractionEnvironment(
        workspaceMode: workspaceMode,
        isTransitionInteractionFrozen: isFrozen
    )
}
```

### 修改意图

这组测试的意义不是补数量，而是锁定 phase5 真正想统一的语义边界：`contextMenuRequest` 和 `beginTextEdit` 以后应该由 shared policy 决定能否继续，而不是再由平台入口偷偷绕开。

## 构建与测试结果

本次验证结果如下：

- `ReadLints` 未发现这 6 个 phase5 文件的新增诊断
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build` 成功
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests test` 未完成，不是 phase5 新代码编译失败，而是被既有测试文件 `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 的 `BoardRuntimeState` 初始化参数错误阻断

```bash
# 文件路径: xcodebuild test 输出摘录
# 函数名/命令名: xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests test
# 功能说明: 如实记录 phase5 相关测试文件已经进入编译，但整个 test 过程仍被既有测试文件的编译错误中断。
SwiftCompile normal arm64 Compiling CanvasCommandPolicyParityTests.swift, CanvasContextMenuActionResolverTests.swift
SwiftCompile normal arm64 .../MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
SwiftCompile normal arm64 Compiling CanvasInteractionPolicyTests.swift
SwiftCompile normal arm64 .../MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
SwiftCompile normal arm64 Compiling CanvasEditorSessionAlignmentOverlayTests.swift
.../MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:320:20: error: extra argument 'updatedAt' in call
.../MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:316:22: error: missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
Testing cancelled because the build failed.
```

## 本次 phase5 的结果归纳

这次 `phase5` 完成后，`contextMenuRequest`、iOS 长按、macOS 右键、`beginTextEditIfPossible(for:)`、以及 shared context menu resolver 都已经开始复用 `CanvasInteractionPolicy` 的同一套语义；controller 内原先那几处最直接的 `isReadingModeActive` 早退已经从这些主入口下线。

当前还没有做的是 `phase6`：把迁移期剩余的重复 guard 再审一遍，决定哪些是可以删除的入口层重复判断，哪些是应该保留的 safety net。
