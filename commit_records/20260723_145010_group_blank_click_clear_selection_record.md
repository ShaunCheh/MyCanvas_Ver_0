# 20260723_145010_group_blank_click_clear_selection_record

## 记录范围

本记录如实对应刚刚完成的 group 空白点击取消选中根因修复：在编辑模式下，group 被选中后，再点击画布空白区域，现在会像 item selection 一样取消选中。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`

当前 `git status` 显示上述四个文件有修改。本记录基于当前 `git diff` 与工作区 changes 整理，不直接粘贴原始 diff。

## 根因

修改前，group selection 与 item selection 使用不同状态：

- item selection 在 `CanvasInteractionState` 中。
- group selection 在 `CanvasGroupInteractionState.selectedGroupID` 中。

空白点击的共享决策器 `CanvasClickSelectionResolver` 只接收 `CanvasInteractionState`，因此 group-only selection 时，resolver 会认为“当前没有 selection”，返回 `.none`，不会触发 `.clearSelection`。

同时，iOS/macOS controller 在执行 click selection decision 后，也只比较 `interactionState` 的 before/after。即使后续某处清掉了 group selection，也可能因为 item selection 没变化而判断为“不需要刷新”。

## 修改前

### resolver 只接收 item selection

修改前，`CanvasClickSelectionResolver.resolve(...)` 的 `selection` 参数类型是 `CanvasInteractionState`，只能表达 item selection，不能表达 group selection。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 功能注释：修改前 click selection resolver 只能看到 item selection，看不到 selected group。
// 函数名：CanvasClickSelectionResolver.resolve(...)
func resolve(
    pressTargetKind: CanvasPointerTargetKind,
    pressedItemID: CanvasItemID?,
    releasedItemID: CanvasItemID?,
    selection: CanvasInteractionState,
    isPersistentMultiSelectModeEnabled: Bool,
    pressedModifiers: CanvasPointerModifiers,
    releasedModifiers: CanvasPointerModifiers
) -> CanvasClickSelectionDecision {
    // ...
}
```

### blank click 只根据 item selection 决定是否 clear

修改前，空白点击只看 `selection.hasSelection`。当只有 group 被选中时，普通 item selection 已经为空，因此这里会返回 `.none`。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 功能注释：修改前 blank click 只在 item selection 非空时返回 clearSelection。
// 函数名：CanvasClickSelectionResolver.resolve(...)
return CanvasClickSelectionDecision(
    target: "blank",
    affectedItemID: selection.primarySelectedItemID,
    action: selection.hasSelection ? .clearSelection : .none
)
```

### iOS/macOS 只传入 interactionState

修改前，iOS/macOS pointer up 逻辑传给 resolver 的都是 `interactionState`，不包含 `editorSession.selectedGroupID`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS 只把 item selection 传给 click selection resolver。
// 函数名：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
let previousInteractionState = interactionState
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    selection: previousInteractionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS 也只把 item selection 传给 click selection resolver。
// 函数名：macOSViewController.handlePrimaryPointerUp(at:modifiers:)
let previousInteractionState = interactionState
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    selection: previousInteractionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
```

### 执行结果刷新判断只比较 item selection

修改前，`.clearSelection` 后只比较 `interactionStateBefore != interactionState`。如果只清掉 group，item selection 仍然没变，会被误判为没有 selection 变化。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 clearSelection 后只比较 item selection 的 before/after。
// 函数名：iOSViewController.executeClickSelectionDecision(_:)
case .clearSelection:
    clearSelectionIfNeeded(recordHistory: true)
    let didChangeSelection = interactionStateBefore != interactionState
    return (
        didChangeSelection ? "selection_cleared" : "selection_unchanged",
        didChangeSelection
    )
```

## 修改后

### 新增完整 click selection state

修改后新增 `CanvasClickSelectionState`，把 item selection 与 group selection 合并成共享 resolver 的输入模型。`hasAnySelection` 会同时考虑 item 与 group。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 功能注释：表达点击选择决策所需的完整 selection，包括 item selection 和 selected group。
// 函数名：CanvasClickSelectionState
struct CanvasClickSelectionState: Equatable, Sendable {
    let itemSelection: CanvasInteractionState
    let selectedGroupID: CanvasItemGroupID?

    init(
        itemSelection: CanvasInteractionState = CanvasInteractionState(),
        selectedGroupID: CanvasItemGroupID? = nil
    ) {
        self.itemSelection = itemSelection
        self.selectedGroupID = selectedGroupID
    }

    var hasAnySelection: Bool {
        itemSelection.hasSelection || selectedGroupID != nil
    }
}
```

### resolver 改为接收完整 selection context

`CanvasClickSelectionResolver.resolve(...)` 现在接收 `CanvasClickSelectionState`。item 相关判断继续使用 `itemSelection`，group 是否选中只影响整体 selection 判断。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 功能注释：resolver 输入从单纯 item selection 升级为完整 click selection state。
// 函数名：CanvasClickSelectionResolver.resolve(...)
func resolve(
    pressTargetKind: CanvasPointerTargetKind,
    pressedItemID: CanvasItemID?,
    releasedItemID: CanvasItemID?,
    selection: CanvasClickSelectionState,
    isPersistentMultiSelectModeEnabled: Bool,
    pressedModifiers: CanvasPointerModifiers,
    releasedModifiers: CanvasPointerModifiers
) -> CanvasClickSelectionDecision {
    // ...
}
```

### blank click 根据 hasAnySelection 决定 clear

修改后，空白点击会根据 `hasAnySelection` 判断是否清空 selection。只有 group 被选中时，`selectedGroupID != nil`，因此也会返回 `.clearSelection`。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 功能注释：blank click 现在同时支持清空 item selection 和 group selection。
// 函数名：CanvasClickSelectionResolver.resolve(...)
return CanvasClickSelectionDecision(
    target: "blank",
    affectedItemID: selection.itemSelection.primarySelectedItemID,
    action: selection.hasAnySelection ? .clearSelection : .none
)
```

### iOS/macOS controller 构造完整 click selection state

iOS/macOS controller 新增 `currentClickSelectionState()`，从当前 `interactionState` 和 `editorSession.selectedGroupID` 构造完整 selection context。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS 生成完整 click selection state，供共享 resolver 与刷新判断使用。
// 函数名：iOSViewController.currentClickSelectionState()
private func currentClickSelectionState() -> CanvasClickSelectionState {
    CanvasClickSelectionState(
        itemSelection: interactionState,
        selectedGroupID: editorSession.selectedGroupID
    )
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS 生成完整 click selection state，供共享 resolver 与刷新判断使用。
// 函数名：macOSViewController.currentClickSelectionState()
private func currentClickSelectionState() -> CanvasClickSelectionState {
    CanvasClickSelectionState(
        itemSelection: interactionState,
        selectedGroupID: editorSession.selectedGroupID
    )
}
```

### pointer up 传入完整 selection context

修改后，iOS/macOS 在 pointer up 时先保存完整 click selection state，再传给 resolver。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS pointer up 使用完整 selection context 解析 click selection decision。
// 函数名：iOSViewController.handlePrimaryPointerUp(at:modifiers:)
let previousInteractionState = interactionState
let previousClickSelectionState = currentClickSelectionState()
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    selection: previousClickSelectionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
```

### 执行 click decision 后比较完整 selection context

修改后，`executeClickSelectionDecision(...)` 用 `currentClickSelectionState()` 的 before/after 判断是否真的发生 selection 变化。这样 group-only selection 被清掉时，也会返回 `selection_cleared` 并触发刷新。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS 执行 click selection decision 后，用完整 selection context 判断是否需要刷新。
// 函数名：macOSViewController.executeClickSelectionDecision(_:)
case .clearSelection:
    clearSelectionIfNeeded(recordHistory: true)
    let didChangeSelection = selectionStateBefore != currentClickSelectionState()
    return (
        didChangeSelection ? "selection_cleared" : "selection_unchanged",
        didChangeSelection
    )
```

### 单元测试覆盖 group-only blank click

修改后，resolver 单元测试切换到 `CanvasClickSelectionState`，并新增 group-only selection 下空白点击返回 `.clearSelection` 的测试。

```swift
// MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift
// 功能注释：验证只有 group 被选中时，点击空白也会产生 clearSelection decision。
// 函数名：CanvasClickSelectionResolverTests.testResolveClearsGroupSelectionOnBlankClick()
func testResolveClearsGroupSelectionOnBlankClick() {
    let selectedGroupID = CanvasItemGroupID()

    let decision = resolver.resolve(
        pressTargetKind: .blank,
        pressedItemID: nil,
        releasedItemID: nil,
        selection: CanvasClickSelectionState(
            selectedGroupID: selectedGroupID
        ),
        isPersistentMultiSelectModeEnabled: false,
        pressedModifiers: .none,
        releasedModifiers: .none
    )

    XCTAssertEqual(
        decision,
        CanvasClickSelectionDecision(
            target: "blank",
            affectedItemID: nil,
            action: .clearSelection
        )
    )
}
```

## 行为变化

- item 被选中时，点击画布空白位置仍会取消 item selection。
- group 被选中时，点击画布空白位置现在会取消 group selection。
- 如果 item 与 group selection 状态发生变化，iOS/macOS controller 会基于完整 selection context 触发刷新。
- 共享 resolver 仍然统一 iOS/macOS 的点击选择语义，避免平台分叉。

## 验证

已执行 lints 检查：

- `ReadLints`：`CanvasClickSelectionResolver.swift` 无 linter errors。
- `ReadLints`：`iOSViewController.swift` 无 linter errors。
- `ReadLints`：`macOSViewController.swift` 无 linter errors。
- `ReadLints`：`CanvasClickSelectionResolverTests.swift` 无 linter errors。

已执行 resolver 单元测试。第一次与两个 build 并发执行时，因 DerivedData `build.db` 被锁失败；待 build 完成后单独重跑通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 click selection resolver 在 group-only blank click 下会返回 clearSelection。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests
```

结果：测试通过。

已执行 macOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS group 空白点击取消选中修复后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

结果：build 成功。

已执行 iOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS group 空白点击取消选中修复后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

结果：build 成功。
