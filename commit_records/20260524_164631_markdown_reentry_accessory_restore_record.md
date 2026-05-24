# 20260524_164631_markdown_reentry_accessory_restore_record

## 记录范围

- 记录内容：
  - 修复 `markdown block` 在执行 `Edit Markdown` 之后，再次点击已选中 item 时，`edit / smaller / larger` 悬浮条无法恢复显示的问题。
  - 将共享点击选择语义从“重入文本编辑”调整为“重入当前已选中 item”，再由平台控制器按真实 item 类型分流。
  - 保留本轮定位问题时新增的 macOS 指针命中日志，继续为后续观察提供运行证据。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`
- 参考现状：
  - 生成本记录前，执行 `date +"%Y%m%d_%H%M%S"` 得到时间戳：`20260524_164631`，本文件按该时间戳命名。
  - 生成本记录前，针对本次修改相关文件执行 `git status --short -- ...`，结果为：`M MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`、`M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`、`M MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`。
  - 生成本记录前，针对同一批文件执行 `git diff -- ...`，确认当前 changes 同时包含：
    - 共享点击动作从 `attemptTextEdit` 改为 `reenterSelectedItem`
    - macOS / iOS 控制器新增 markdown reentry 处理
    - macOS 控制器保留 `PointerHitResolve` 调试日志
    - 单测断言同步更新
  - 生成本记录前，执行聚焦测试并通过：
    - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests`

## 当前 changes 摘要

- 共享点击决策层不再把“已选中的 item 再次点击”硬编码为“尝试文本编辑”，而是抽象成 `reenterSelectedItem(itemID:)`，避免把 markdown 误送入 text-only 分支。
- `macOSViewController` 与 `iOSViewController` 在处理 `reenterSelectedItem` 时，先尝试文本 item 的 inline edit；如果目标是 markdown，则直接重新调用 `syncSelectionAccessoryPresentation()` 恢复悬浮条。
- 本轮为了定位 hit-test / zIndex / scene candidate 问题而加的 `PointerHitResolve` 日志仍保留在 macOS 控制器中，属于当前 changes 的一部分。
- `CanvasClickSelectionResolverTests` 已随共享动作命名和语义一起更新，保证“已选中 item 再次点击”仍有单测覆盖。

## 修改一：把共享点击动作从 text-only 重入改为 item reentry

### 修改前

- `CanvasClickSelectionResolver` 在命中 `selectedItemBody` 且目标已经是单选主项时，直接返回 `.attemptTextEdit(itemID:)`。
- 这个共享语义对 `text` 成立，但对 `markdown` 不成立，因为 markdown 并不走 inline text edit 通路。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数名: CanvasClickSelectionAction / resolve(...)
// 功能说明: 修改前把“已选中 item 再次点击”统一解释成“尝试文本编辑”，会把 markdown 也送进 text-only 分支。
enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case attemptTextEdit(itemID: CanvasItemID)
}

if case .selectedItemBody = pressTargetKind,
   selection.singleSelectedItemID == itemID
{
    return CanvasClickSelectionDecision(
        target: "item",
        affectedItemID: itemID,
        action: .attemptTextEdit(itemID: itemID)
    )
}
```

### 修改后

- 共享点击层现在返回 `.reenterSelectedItem(itemID:)`，不再提前假设目标一定是 text。
- 这样控制器层可以按真实 item 类型继续分流，从根因上消除 markdown 被错误复用 text reentry 语义的问题。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数名: CanvasClickSelectionAction / resolve(...)
// 功能说明: 修改后把“已选中 item 再次点击”抽象成通用 reentry 语义，交给上层根据 item 类型做正确分流。
enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case reenterSelectedItem(itemID: CanvasItemID)
}

if case .selectedItemBody = pressTargetKind,
   selection.singleSelectedItemID == itemID
{
    return CanvasClickSelectionDecision(
        target: "item",
        affectedItemID: itemID,
        action: .reenterSelectedItem(itemID: itemID)
    )
}
```

## 修改二：macOS 重点击已选中 markdown 时恢复悬浮条

### 修改前

- `executeClickSelectionDecision(_:)` 在收到 `.attemptTextEdit(itemID:)` 后，只会调用 `beginTextEditIfPossible(for:)`。
- `beginTextEditIfPossible(for:)` 内部只接受 `scene.textItem(withID:)`，因此 markdown 命中这条链路时会直接失败。
- 失败后返回 `selection_unchanged`，既不会进入编辑，也不会重新同步 `SelectionAccessory`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: executeClickSelectionDecision(_:) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 macOS 对已选中 markdown 的重点击仍只尝试 text inline edit，失败后不会恢复 markdown accessory。
private func executeClickSelectionDecision(
    _ decision: CanvasClickSelectionDecision
) -> (result: String, didTriggerPressedRefresh: Bool) {
    switch decision.action {
    // ... 省略其他分支 ...
    case let .attemptTextEdit(itemID):
        if beginTextEditIfPossible(for: itemID) {
            return ("text_edit_began", true)
        }
        return ("selection_unchanged", false)
    }
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

### 修改后

- `executeClickSelectionDecision(_:)` 在 macOS 侧改为处理 `.reenterSelectedItem(itemID:)`。
- 新增 `handleSelectedItemReentry(for:)`：
  - `text` 仍然优先进入 inline text edit
  - `markdown` 则调用 `syncSelectionAccessoryPresentation()`，直接把悬浮条恢复出来
- 这一步命中的是根因：修正“重点击已选中 markdown”的语义，而不是在失败后做被动兜底。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: executeClickSelectionDecision(_:) / handleSelectedItemReentry(for:)
// 功能说明: 修改后 macOS 对已选中 item 的重点击按真实类型分流；text 进入编辑，markdown 恢复 selection accessory。
private func executeClickSelectionDecision(
    _ decision: CanvasClickSelectionDecision
) -> (result: String, didTriggerPressedRefresh: Bool) {
    switch decision.action {
    // ... 省略其他分支 ...
    case let .reenterSelectedItem(itemID):
        return handleSelectedItemReentry(for: itemID)
    }
}

private func handleSelectedItemReentry(
    for itemID: CanvasItemID
) -> (result: String, didTriggerPressedRefresh: Bool) {
    if beginTextEditIfPossible(for: itemID) {
        return ("text_edit_began", true)
    }
    if scene.markdownItem(withID: itemID) != nil {
        // markdown 不走 text inline edit，直接重新同步 accessory，恢复 edit / smaller / larger 悬浮条。
        syncSelectionAccessoryPresentation()
        return ("markdown_accessory_presented", false)
    }
    return ("selection_unchanged", false)
}
```

## 修改三：iOS 保持同语义分流，避免平台行为再次分叉

### 修改前

- iOS 控制器和 macOS 一样，也把 `.attemptTextEdit(itemID:)` 当成唯一的重点击处理分支。
- 这意味着共享 resolver 一旦错误地把 markdown 解释为 text reentry，iOS 侧也会承受同样的错误语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: executeClickSelectionDecision(_:)
// 功能说明: 修改前 iOS 与 macOS 一样，重点击分支只尝试 text edit，没有 markdown accessory 恢复语义。
private func executeClickSelectionDecision(
    _ decision: CanvasClickSelectionDecision
) -> (result: String, didTriggerPressedRefresh: Bool) {
    switch decision.action {
    // ... 省略其他分支 ...
    case let .attemptTextEdit(itemID):
        if beginTextEditIfPossible(for: itemID) {
            return ("text_edit_began", true)
        }
        return ("selection_unchanged", false)
    }
}
```

### 修改后

- iOS 侧同步引入 `handleSelectedItemReentry(for:)`，逻辑与 macOS 对齐。
- 这样共享点击层的“已选中 item reentry”语义在两个平台上保持一致，避免以后再次出现平台漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: executeClickSelectionDecision(_:) / handleSelectedItemReentry(for:)
// 功能说明: 修改后 iOS 与 macOS 保持一致；text 重入编辑，markdown 重建 selection accessory。
private func executeClickSelectionDecision(
    _ decision: CanvasClickSelectionDecision
) -> (result: String, didTriggerPressedRefresh: Bool) {
    switch decision.action {
    // ... 省略其他分支 ...
    case let .reenterSelectedItem(itemID):
        return handleSelectedItemReentry(for: itemID)
    }
}

private func handleSelectedItemReentry(
    for itemID: CanvasItemID
) -> (result: String, didTriggerPressedRefresh: Bool) {
    if beginTextEditIfPossible(for: itemID) {
        return ("text_edit_began", true)
    }
    if scene.markdownItem(withID: itemID) != nil {
        // 与 macOS 保持一致：markdown 不进 text edit，而是恢复 selection accessory。
        syncSelectionAccessoryPresentation()
        return ("markdown_accessory_presented", false)
    }
    return ("selection_unchanged", false)
}
```

## 修改四：更新共享点击单测断言

### 修改前

- 单测仍把“已选中 item 再次点击”的预期动作写死为 `.attemptTextEdit(itemID:)`。
- 如果不跟着更新，测试名和断言会继续固化旧语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift
// 函数名: testResolvePrefersTextEditOnlyForSoleSelectedItem()
// 功能说明: 修改前测试把共享 resolver 的重点击动作固定断言为 attemptTextEdit。
func testResolvePrefersTextEditOnlyForSoleSelectedItem() {
    let tappedItemID = CanvasItemID()
    let decision = resolver.resolve(
        pressTargetKind: .selectedItemBody,
        pressedItemID: tappedItemID,
        releasedItemID: tappedItemID,
        selection: CanvasInteractionState(
            selectedItemIDs: [tappedItemID],
            primarySelectedItemID: tappedItemID
        ),
        isPersistentMultiSelectModeEnabled: false,
        pressedModifiers: .none,
        releasedModifiers: .none
    )

    XCTAssertEqual(
        decision.action,
        .attemptTextEdit(itemID: tappedItemID)
    )
}
```

### 修改后

- 测试名称和断言一起更新为 `reenterSelectedItem(itemID:)`。
- 这样共享决策层的真实职责被明确下来：resolver 只负责输出“重入已选中 item”，不提前绑定 text-only 解释。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift
// 函数名: testResolveReentersSoleSelectedItem()
// 功能说明: 修改后测试验证共享 resolver 输出的是通用 reentry 语义，而不是 text-only attemptTextEdit。
func testResolveReentersSoleSelectedItem() {
    let tappedItemID = CanvasItemID()
    let decision = resolver.resolve(
        pressTargetKind: .selectedItemBody,
        pressedItemID: tappedItemID,
        releasedItemID: tappedItemID,
        selection: CanvasInteractionState(
            selectedItemIDs: [tappedItemID],
            primarySelectedItemID: tappedItemID
        ),
        isPersistentMultiSelectModeEnabled: false,
        pressedModifiers: .none,
        releasedModifiers: .none
    )

    XCTAssertEqual(
        decision.action,
        .reenterSelectedItem(itemID: tappedItemID)
    )
}
```

## 修改五：当前 changes 中仍保留 macOS PointerHitResolve 调试日志

### 修改前

- 在最开始修复前，macOS 控制器没有这组“点击点下所有候选 item / 最终命中项”的详细日志。
- 这使得 hit-test、zIndex、screen/world bounds 是否一致只能靠间接日志猜测。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: 类型级成员 / handlePrimaryPointerDown(...)
// 功能说明: 修改前没有 PointerHitResolve 调试开关，也没有在 pointer down / up 时输出候选命中列表。
final class macOSViewController: NSViewController, NSUserInterfaceValidations, NSTextViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
    private static let isMarkdownSelectionAccessoryTraceLoggingEnabled = false
}

private func handlePrimaryPointerDown(
    at location: CGPoint,
    modifiers: CanvasPointerModifiers
) {
    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext,
        pointerModifiers: modifiers
    )
}
```

### 修改后

- 当前 changes 中，macOS 仍保留 `isPointerHitTraceLoggingEnabled = true`。
- `pointer down / up` 都会输出 `PointerHitResolve`，包含目标类型、命中 item、候选列表、screen/world bounds、render zIndex 等信息。
- 这不是这次功能修复的主逻辑，但它确实存在于当前 `git diff` 中，所以这里如实记录。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 类型级成员 / handlePrimaryPointerDown(...) / logPointerHitResolution(...)
// 功能说明: 当前 changes 中保留了 macOS 命中链路调试日志，帮助继续观察 overlay / scene / zIndex 命中行为。
final class macOSViewController: NSViewController, NSUserInterfaceValidations, NSTextViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
    private static let isMarkdownSelectionAccessoryTraceLoggingEnabled = false
    private static let isPointerHitTraceLoggingEnabled = true
}

private func handlePrimaryPointerDown(
    at location: CGPoint,
    modifiers: CanvasPointerModifiers
) {
    let pressContext = resolvePointerPressContext(at: location)
    logPointerHitResolution(
        phase: "down",
        location: location,
        context: pressContext
    )
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext,
        pointerModifiers: modifiers
    )
}

private func logPointerHitResolution(
    phase: String,
    location: CGPoint,
    context: CanvasPointerPressContext
) {
    // 输出 viewport/world 坐标、目标 targetKind、命中 item、候选命中列表，辅助继续观察 pointer 命中行为。
    let worldPoint = camera.viewportToWorld(location)
    let hitCandidates = scene
        .orderedBoardItems()
        .filter { $0.contains(worldPoint: worldPoint) }
        .reversed()
        .map { item in
            describePointerHitCandidate(
                item,
                viewportLocation: location
            )
        }
    let hitCandidateDescriptions = hitCandidates.joined(separator: ", ")
    print(
        "[Canvas macOS][PointerHitResolve] " +
        "phase=\(phase) " +
        "worldPoint=\(describe(point: worldPoint)) " +
        "targetKind=\(describe(pointerTargetKind: context.targetKind)) " +
        "candidateCount=\(hitCandidates.count) " +
        "candidates=[\(hitCandidateDescriptions)]"
    )
}
```

## 验证情况

- `ReadLints` 检查以下文件，未发现新增问题：
  - `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`
- 已执行聚焦测试并通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests`

## 结论

- 这次修复命中的不是“悬浮条没刷出来”的表象，而是“已选中 markdown 再次点击被错误复用成 text reentry 语义”的根因。
- 共享 resolver 现在只表达“重入当前已选中 item”，平台控制器再根据真实 item 类型决定进入 text edit 还是恢复 markdown accessory，语义边界更清晰。
- 当前 `git diff` 还包含一组保留中的 macOS 指针命中调试日志，本记录已如实纳入；如果后续确认问题稳定解决，可以再单独回收这批日志。 
