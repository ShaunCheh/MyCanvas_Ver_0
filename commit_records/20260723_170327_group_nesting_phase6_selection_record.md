# 20260723_170327_group_nesting_phase6_selection_record

## 背景

本次记录对应 group nesting 阶段6：明确嵌套 group 的选择、命令与删除语义。

阶段6计划中明确：

- `selectGroup` 保持只选当前 group，不隐式选中 children。
- `clearSelection` 继续复用已有 group selection 清选能力。
- 本阶段不扩展 delete group 语义。
- 需要确保 blank click、group frame click 与嵌套 hit target 一致。

阶段6前，iOS/macOS 对 group frame click 各自有一段手写分支，`CanvasClickSelectionResolver` 只统一处理 item 和 blank 的 click selection。这样 group frame click 的选择语义没有完全进入共享 resolver。

## 修改 1：将 group frame click 纳入共享 resolver

修改前，`CanvasClickSelectionAction` 没有 group selection action，`groupFrameBody` 只返回 `.none`。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift - CanvasClickSelectionAction / CanvasClickSelectionResolver.resolve(...)
enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case reenterSelectedItem(itemID: CanvasItemID)
}

case .groupFrameBody:
    return CanvasClickSelectionDecision(
        target: "group_frame_body",
        affectedItemID: nil,
        action: .none
    )
```

修改后，新增 `.selectGroup(groupID:)`，并让 resolver 接收 press/release 的 group ID。只有按下和释放命中同一个 group frame 时，才返回选择该 group 的 action；如果 release 命中不同 group，则返回 no-op，避免拖出/错位点击误选。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift - CanvasClickSelectionAction / CanvasClickSelectionResolver.resolve(...)
enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case selectGroup(groupID: CanvasItemGroupID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case reenterSelectedItem(itemID: CanvasItemID)
}

func resolve(
    pressTargetKind: CanvasPointerTargetKind,
    pressedItemID: CanvasItemID?,
    releasedItemID: CanvasItemID?,
    pressedGroupID: CanvasItemGroupID? = nil,
    releasedGroupID: CanvasItemGroupID? = nil,
    selection: CanvasClickSelectionState,
    isPersistentMultiSelectModeEnabled: Bool,
    pressedModifiers: CanvasPointerModifiers,
    releasedModifiers: CanvasPointerModifiers
) -> CanvasClickSelectionDecision {
    // ...
}

case .groupFrameBody:
    guard
        let groupID = pressedGroupID,
        releasedGroupID == groupID
    else {
        return CanvasClickSelectionDecision(
            target: "mismatched_group_hit_test",
            affectedItemID: nil,
            action: .none
        )
    }

    return CanvasClickSelectionDecision(
        target: "group_frame_body",
        affectedItemID: nil,
        action: .selectGroup(groupID: groupID)
    )
```

## 修改 2：iOS 删除手写 group frame click 分支，统一走 resolver

修改前，iOS 在 pointer up 时先调用 `executeGroupFrameClickSelectionIfMatched(...)`，命中 group 后直接提前 return。这个分支独立于 `CanvasClickSelectionResolver`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - pointer up click selection flow
if let groupClickResult = executeGroupFrameClickSelectionIfMatched(
    pressContext: pressContext,
    releasedContext: releasedContext
) {
    logClickResult(
        target: "group_frame",
        result: groupClickResult.result,
        pressedItemID: pressedItemID,
        releasedItemID: releasedItemID,
        previousInteractionState: previousInteractionState,
        currentInteractionState: interactionState,
        affectedItemID: nil
    )
    editorSession.cancelPendingHistoryTransaction()
    return
}
```

修改后，iOS 将 `pressContext.targetGroupID` 和 `releasedContext.targetGroupID` 传入共享 resolver。group、item、blank 都从同一条 click decision 流执行。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - pointer up click selection flow
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    pressedGroupID: pressContext.targetGroupID,
    releasedGroupID: releasedContext.targetGroupID,
    selection: previousClickSelectionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
let executionResult = executeClickSelectionDecision(clickDecision)
```

原来的 `executeGroupFrameClickSelectionIfMatched(...)` 被删除，选择 group 的执行逻辑改为 `executeClickSelectionDecision(...)` 的一个 action 分支。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - executeClickSelectionDecision(_:)
case let .selectGroup(groupID):
    let didSelectGroup = editorSession.selectGroup(
        withID: groupID,
        recordHistory: true
    )
    guard didSelectGroup else {
        return ("selection_unchanged", false)
    }

    requestCanvasRefresh(reason: "select group frame")
    return ("group_selected", true)
```

## 修改 3：macOS 同步统一 group click selection

macOS 修改前同样有独立的 `executeGroupFrameClickSelectionIfMatched(...)` 分支。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - pointer up click selection flow
if let groupClickResult = executeGroupFrameClickSelectionIfMatched(
    pressContext: pressContext,
    releasedContext: releasedContext
) {
    logClickResult(
        target: "group_frame",
        result: groupClickResult.result,
        pressedItemID: pressedItemID,
        releasedItemID: releasedItemID,
        previousInteractionState: previousInteractionState,
        currentInteractionState: interactionState,
        affectedItemID: nil
    )
    editorSession.cancelPendingHistoryTransaction()
    return
}
```

修改后，macOS 也统一传入 group ID，由 resolver 决定是否产生 `.selectGroup(groupID:)`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - pointer up click selection flow
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    pressedGroupID: pressContext.targetGroupID,
    releasedGroupID: releasedContext.targetGroupID,
    selection: previousClickSelectionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
let executionResult = executeClickSelectionDecision(clickDecision)
```

macOS 的执行分支与 iOS 保持同构，只是刷新方法为 `refreshCanvas(...)`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - executeClickSelectionDecision(_:)
case let .selectGroup(groupID):
    let didSelectGroup = editorSession.selectGroup(
        withID: groupID,
        recordHistory: true
    )
    guard didSelectGroup else {
        return ("selection_unchanged", false)
    }

    refreshCanvas(reason: "select group frame")
    return ("group_selected", true)
```

## 修改 4：补充 click resolver 测试

新增 resolver 单测，覆盖 group frame 正常选择与 press/release group mismatch。

```swift
// MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift - testResolveSelectsGroupFrameWhenPressAndReleaseMatch()
let decision = resolver.resolve(
    pressTargetKind: .groupFrameBody,
    pressedItemID: nil,
    releasedItemID: nil,
    pressedGroupID: groupID,
    releasedGroupID: groupID,
    selection: CanvasClickSelectionState(),
    isPersistentMultiSelectModeEnabled: false,
    pressedModifiers: .none,
    releasedModifiers: .none
)

XCTAssertEqual(
    decision,
    CanvasClickSelectionDecision(
        target: "group_frame_body",
        affectedItemID: nil,
        action: .selectGroup(groupID: groupID)
    )
)
```

```swift
// MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift - testResolveDoesNotSelectGroupFrameWhenReleaseHitsDifferentGroup()
let decision = resolver.resolve(
    pressTargetKind: .groupFrameBody,
    pressedItemID: nil,
    releasedItemID: nil,
    pressedGroupID: pressedGroupID,
    releasedGroupID: releasedGroupID,
    selection: CanvasClickSelectionState(),
    isPersistentMultiSelectModeEnabled: false,
    pressedModifiers: .none,
    releasedModifiers: .none
)

XCTAssertEqual(
    decision,
    CanvasClickSelectionDecision(
        target: "mismatched_group_hit_test",
        affectedItemID: nil,
        action: .none
    )
)
```

## 修改 5：补充嵌套 group 选择语义测试

新增 group hierarchy 测试，覆盖阶段6要求的三类场景：

- 点击 child frame 选 child，不选 parent。
- 点击 parent 空白 frame 区域选 parent。
- 点击画布空白清除 selected group。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testNestedGroupClickSelectionSelectsChildFrameOnly()
let decision = makeGroupHierarchyClickDecision(
    session: session,
    worldPoint: CGPoint(x: 75, y: 75)
)

XCTAssertEqual(decision.action, .selectGroup(groupID: childID))
if case let .selectGroup(groupID) = decision.action {
    XCTAssertTrue(session.selectGroup(withID: groupID))
}
XCTAssertEqual(session.selectedGroupID, childID)
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testNestedGroupClickSelectionSelectsParentEmptyFrameArea()
let decision = makeGroupHierarchyClickDecision(
    session: session,
    worldPoint: CGPoint(x: 20, y: 20)
)

XCTAssertEqual(decision.action, .selectGroup(groupID: parentID))
if case let .selectGroup(groupID) = decision.action {
    XCTAssertTrue(session.selectGroup(withID: groupID))
}
XCTAssertEqual(session.selectedGroupID, parentID)
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testBlankClickSelectionClearsNestedSelectedGroup()
XCTAssertTrue(session.selectGroup(withID: childID))

let decision = CanvasClickSelectionResolver().resolve(
    pressTargetKind: .blank,
    pressedItemID: nil,
    releasedItemID: nil,
    selection: CanvasClickSelectionState(
        selectedGroupID: session.selectedGroupID
    ),
    isPersistentMultiSelectModeEnabled: false,
    pressedModifiers: .none,
    releasedModifiers: .none
)

XCTAssertEqual(decision.action, .clearSelection)
XCTAssertTrue(session.clearSelection())
XCTAssertNil(session.selectedGroupID)
```

测试 helper 先生成 snapshot，再通过 session 的真实 hit target 解析路径得到 group click decision。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - makeGroupHierarchyClickDecision(session:worldPoint:)
_ = session.makeCanvasSnapshot()
let viewportPoint = session.camera.worldToViewport(worldPoint)
let pressContext = session.resolvePointerTarget(
    at: viewportPoint,
    interactionMetrics: makeGroupHierarchyContextResolverMetrics()
)

return CanvasClickSelectionResolver().resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: pressContext.targetItemID,
    pressedGroupID: pressContext.targetGroupID,
    releasedGroupID: pressContext.targetGroupID,
    selection: CanvasClickSelectionState(
        itemSelection: session.interactionState,
        selectedGroupID: session.selectedGroupID
    ),
    isPersistentMultiSelectModeEnabled: false,
    pressedModifiers: .none,
    releasedModifiers: .none
)
```

## 删除语义说明

本阶段没有增加 delete group 行为。`selectGroup(withID:)` 仍只设置当前 `selectedGroupID`，不会隐式选中 children；`deleteSelection` 仍按 item selection 工作，不把 selected group 作为删除目标。

## 验证

已执行并通过：

- `ReadLints`：无 linter errors。
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS'`

## 当前变更文件

- `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
