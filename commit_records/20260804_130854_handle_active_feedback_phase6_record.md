# 20260804_130854_handle_active_feedback_phase6_record

## 时间戳与记录范围

- 时间戳来源：在项目根目录执行系统命令 `date '+%Y%m%d_%H%M%S'`。
- 命令输出：`20260804_130854`。
- 对应任务：`Canvas Handle Active Feedback` 分阶段计划的阶段 6——边界与取消一致性加固。
- 参考依据：记录创建前的 `git status --short`、`git diff --stat`、完整当前 diff、当前 changes、相关文件内容，以及最终测试和双端构建输出。
- 本次没有提交代码，也没有修改已有 `.md` 文件；本文件是按要求新增的阶段记录。

记录创建前，本阶段当前 changes 为：

- 修改 `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`。
- 修改 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`。
- 修改 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`。
- 修改 `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`。
- 修改 `MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift`。

`git diff --stat` 显示本阶段最终为 5 个文件变化，新增 514 行、删除 176 行。行数主要来自 iOS/macOS 对称的 pointer failure 分支改造和原有 update 函数返回值契约调整。

## 修改目标

阶段 1～5 已完成 handle identity、pressed/dragging 状态机、snapshot 投影、双端 pointer 生命周期接入和 active 视觉样式，但边界清理仍存在以下缺口：

- session 在 board runtime/history restore 时会清除 `editHandleInteractionState`，controller 的 `pointerDragState` 和 adapter 缓存却不一定同步回到 idle。
- undo/redo、进入或退出 inline edit、reading/editing 模式切换可能抢占正在进行的 pointer interaction。
- 部分 target/state factory 失败只直接设置 `.idle`，可能遗漏 pending history transaction 的收尾。
- crop、rotate、item resize、selection resize 和 arrow endpoint 的 update 函数返回 `Void`，无法区分“几何没有变化但交互仍有效”和“目标或上下文已经失效”。
- 拖动中目标丢失时，部分路径只静默 `return`，handle 会继续保持 dragging/active，直到后续 pointer up 或 cancel。

本阶段的根因修复目标是建立统一边界：

1. 外部命令或模式切换抢占非 idle pointer 时，先复用既有 `handlePrimaryPointerCancel()` 业务语义。
2. session/history/inline 状态应用完毕后，再强制把 controller pointer 生命周期同步到 idle。
3. target、factory 或 mutation 失效时，不再裸写 `.idle`，而是统一进入原有 cancel 收尾路径。
4. `false` 只代表交互失效；“本次几何没有变化”返回 `true`，不会误终止正常拖动。
5. active 清理本身不记录 history、不触发 autosave；如果已有真实几何变化，仍按项目原有 cancel 语义提交。

## 修改前 1：command 只特殊处理 rotation

修改前，双端 `performCommand(_:)` 在命令执行前只调用 rotation 专用取消逻辑。普通 resize、crop、arrow、selection/group drag 或尚未越过阈值的 `.pressed` 没有统一收尾：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | performCommand(_:)（修改前）
dismissContextMenu()

if command.shouldCancelActiveRotation {
    cancelRotationInteractionIfNeeded(
        resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
    )
}

guard let executionResult = commandExecutor.execute(command) else {
    return
}

updateInlineEditButtonsAppearance()
updateGroupListPresentation()

if let refreshReason = executionResult.refreshReason {
    requestCanvasRefresh(reason: refreshReason)
}
```

这会形成两种不一致：

- 命令在真实 drag 期间执行时，rotation 可以撤销 preview，其他 pointer interaction 却可能继续持有旧 state。
- undo/redo 会让 session 应用 history snapshot 并清除 session transient state，但 controller adapter 仍可能保留原 handle identity。

## 修改后 1：command 边界分类与双阶段收尾

`CanvasCommand` 新增 `resetsEditHandleInteractionAfterExecution`。只有会切换 inline edit 生命周期或应用 history snapshot 的命令需要在成功执行后再次强制同步 idle：

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift | CanvasCommand.resetsEditHandleInteractionAfterExecution
var resetsEditHandleInteractionAfterExecution: Bool {
    switch self {
    case .beginTextEdit,
         .commitTextEdit,
         .beginMarkdownEdit,
         .commitMarkdownEdit,
         .crop,
         .beginCropMode,
         .undo,
         .redo:
        return true
    case .importMedia,
         .addTextItem,
         .addMarkdownItem,
         .addHandDrawingItem,
         .addArrowItem,
         .addGroup,
         .decreaseTextFontSize,
         .increaseTextFontSize,
         .decreaseMarkdownContentSize,
         .increaseMarkdownContentSize,
         .decreaseArrowThickness,
         .increaseArrowThickness,
         .selectItem,
         .toggleSelectionMembership,
         .clearSelection,
         .duplicateItem,
         .duplicateSelection,
         .deleteItem,
         .deleteSelection,
         .bringItemForward,
         .bringSelectionForward,
         .sendItemBackward,
         .sendSelectionBackward,
         .bringItemToFront,
         .bringSelectionToFront,
         .sendItemToBack,
         .sendSelectionToBack:
        return false
    }
}
```

双端 command 执行顺序改为：

1. 先确认命令可以执行，避免无效命令意外取消当前 drag。
2. 命令执行前，收尾当前非 idle pointer interaction。
3. 执行命令。
4. 对 inline/history 边界再次强制同步 idle。
5. 最后执行命令原有 refresh/follow-up。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | performCommand(_:)
guard commandExecutor.canExecute(command) else {
    return
}

dismissContextMenu()
cancelActivePointerInteractionForBoundaryIfNeeded()

if command.shouldCancelActiveRotation {
    cancelRotationInteractionIfNeeded(
        resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
    )
}

guard let executionResult = commandExecutor.execute(command) else {
    return
}

if command.resetsEditHandleInteractionAfterExecution {
    resetPointerInteractionForBoundary()
}

updateInlineEditButtonsAppearance()
updateGroupListPresentation()

if let refreshReason = executionResult.refreshReason {
    requestCanvasRefresh(reason: refreshReason)
}
```

macOS 使用相同顺序，仅保留原平台的 `refreshCanvas(reason:)` 和 UI 更新方式：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | performCommand(_:)
dismissContextMenu()
cancelActivePointerInteractionForBoundaryIfNeeded()

if command.shouldCancelActiveRotation {
    cancelRotationInteractionIfNeeded(
        resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
    )
}

guard let executionResult = commandExecutor.execute(command) else {
    return
}

if command.resetsEditHandleInteractionAfterExecution {
    resetPointerInteractionForBoundary()
}

updateInlineEditButtonsAppearance()

if let refreshReason = executionResult.refreshReason {
    refreshCanvas(reason: refreshReason)
}
```

## 修改后 2：统一 controller pointer boundary

双端增加相同的两个 controller helper：

- `cancelActivePointerInteractionForBoundaryIfNeeded()`：所有非 idle 状态都走既有 pointer cancel。
- `resetPointerInteractionForBoundary()`：在 session/command 已完成状态替换后，强制发出 idle 生命周期，进而同步 adapter 和 session handle state。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | cancelActivePointerInteractionForBoundaryIfNeeded() / resetPointerInteractionForBoundary()
private func cancelActivePointerInteractionForBoundaryIfNeeded() {
    guard case .idle = pointerDragState else {
        handlePrimaryPointerCancel()
        return
    }
}

private func resetPointerInteractionForBoundary() {
    pointerDragState = .idle
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | cancelActivePointerInteractionForBoundaryIfNeeded() / resetPointerInteractionForBoundary()
private func cancelActivePointerInteractionForBoundaryIfNeeded() {
    guard case .idle = pointerDragState else {
        handlePrimaryPointerCancel()
        return
    }
}

private func resetPointerInteractionForBoundary() {
    pointerDragState = .idle
}
```

这里没有直接修改 `editHandleInteractionState` 或 adapter 私有缓存。`pointerDragState = .idle` 仍通过阶段 4 已建立的 property observer 和 `CanvasEditHandleControllerAdapter.event(for: .inactive)` 完成统一同步，避免新增第二条状态通道。

## 修改后 3：reading/editing 模式切换边界

修改前，workspace mode transition 直接切换 `workspaceMode`。reading presentation 虽然会隐藏 active handle，但 raw pointer/adapter state 可能继续保留：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | applyWorkspaceModeForToolbarTransition(to:)（修改前）
private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    workspaceMode = targetMode
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    syncTextEditorPresentation()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}
```

修改后，先按当前 pointer state 完成既有 cancel，再切 mode，并在最终 refresh 前强制同步 idle：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | applyWorkspaceModeForToolbarTransition(to:)
private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    cancelActivePointerInteractionForBoundaryIfNeeded()
    workspaceMode = targetMode
    resetPointerInteractionForBoundary()
    updateWorkspaceModeButtonAppearance()
    updateInlineEditButtonsAppearance()
    syncTextEditorPresentation()
    requestCanvasRefresh(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}
```

macOS 同样在 `workspaceMode` 赋值前后执行 cancel/reset，并继续使用原有 view-state-only autosave；本阶段没有新增 autosave：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | applyWorkspaceModeForToolbarTransition(to:)
private func applyWorkspaceModeForToolbarTransition(
    to targetMode: CanvasWorkspaceMode
) {
    cancelActivePointerInteractionForBoundaryIfNeeded()
    workspaceMode = targetMode
    resetPointerInteractionForBoundary()
    updateWorkspaceModeButtonAppearance()
    updateKeyboardShortcutObservationIfNeeded()
    syncTextEditorPresentation()
    refreshCanvas(reason: "toggle workspace mode")
    scheduleAutosave(
        reason: "toggle workspace mode",
        updateKind: .viewStateOnly
    )
}
```

## 修改后 4：board restore 后同步 controller/adapter

session 的 `loadBoard`、`startNewBoard`、persisted restore 和 `applyBoardRuntimeState` 原本已经清除 session transient editing state。本阶段在这些 session 操作完成后补上 controller pointer reset，使 session、pointer state 和 adapter 不再出现单边重置：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:)
try editorSession.loadBoard(id: boardID)
resetPointerInteractionForBoundary()

editorSession.startNewBoard()
resetPointerInteractionForBoundary()

editorSession.restorePersistedBoardIfPossible()
resetPointerInteractionForBoundary()

editorSession.applyBoardRuntimeState(runtimeState)
resetPointerInteractionForBoundary()
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | restoreBoard(withID:) / startNewBoard() / restorePersistedBoardIfPossible() / applyBoardRuntimeState(_:)
try editorSession.loadBoard(id: boardID)
resetPointerInteractionForBoundary()

editorSession.startNewBoard()
resetPointerInteractionForBoundary()

editorSession.restorePersistedBoardIfPossible()
resetPointerInteractionForBoundary()

editorSession.applyBoardRuntimeState(runtimeState)
resetPointerInteractionForBoundary()
```

该 reset 不调用 history/autosave。board load/new/restore 的持久化和 history 行为仍由原有 session 方法负责。

## 修改前 2：factory 或 mutation 失败可能裸写 idle

修改前，不同 handle family 使用了不同失败处理。有些路径取消 pending transaction 后直接 idle，有些只直接 idle：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | handlePrimaryPointerMove(to:from:)（修改前示例）
guard let rotateState = makePointerRotateState(
    itemID: itemID,
    initialViewportLocation: pressedLocation
) else {
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
    return
}

guard let resizeState = makePointerResizeState(
    itemID: itemID,
    handleRole: handleRole
) else {
    pointerDragState = .idle
    return
}
```

拖动已经开始后，item/selection/group move 失败也可能只写 idle。这会绕过该 interaction 已有的 finalize/commit 规则；如果之前已经应用过几何，pending transaction 可能无法按既有 cancel 语义收尾。

## 修改后 5：所有 pointer failure 复用同一 cancel 语义

双端 `handlePrimaryPointerMove(to:from:)` 中以下失败现在统一调用 `handlePrimaryPointerCancel()`：

- rotate item / rotate selection state factory 或 update 失效。
- crop handle / crop translation state factory 或 update 失效。
- selected item resize state factory 或 update 失效。
- arrow endpoint state factory 或 update 失效。
- multi-selection resize state factory 或 update 失效。
- selected item / selection / group frame move state factory或 mutation 失效。
- group frame resize state factory或 mutation 失效。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | handlePrimaryPointerMove(to:from:)
guard let rotateState = makePointerRotateState(
    itemID: itemID,
    initialViewportLocation: pressedLocation
) else {
    handlePrimaryPointerCancel()
    return
}

pointerDragState = .rotatingSelectedItem(rotateState)
beginRotationInteraction(for: itemID)
guard updateRotationDraft(
    using: rotateState,
    to: location
) else {
    handlePrimaryPointerCancel()
    return
}
```

持续拖动期间同样不再裸写 idle：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | handlePrimaryPointerMove(to:from:)
case let .draggingSelectedItem(dragState):
    guard let updatedDragState = moveSelectedItem(
        using: dragState,
        to: location
    ) else {
        handlePrimaryPointerCancel()
        return
    }
    pointerDragState = .draggingSelectedItem(updatedDragState)

case let .draggingGroupFrame(groupDragState):
    guard moveGroupFrame(using: groupDragState, to: location) else {
        handlePrimaryPointerCancel()
        return
    }
```

## 修改后 6：update 返回“交互是否仍有效”

crop、rotate、item resize、arrow endpoint 和 selection resize update 从 `Void` 改为 `Bool`：

- 目标、inline mode、selection 或 mutation context 已失效：返回 `false`，调用方进入 cancel。
- 几何与当前状态相同：返回 `true`，pointer interaction 保持 active。
- mutation 成功：刷新并返回 `true`。

crop 的“无变化仍有效”示例：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | updateCropDraft(using:to:)
private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) -> Bool {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == cropState.itemID,
        let item = scene.item(withID: cropState.itemID)
    else {
        return false
    }

    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let cropLocalFrame = constrainedCropLocalFrame(
        draggedLocalPoint,
        for: cropState.handleRole,
        initialLocalFrame: cropState.initialLocalFrame,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let draftCropRectNormalized = item.normalizedCropRect(
        fromLocalFrame: cropLocalFrame
    )
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return true
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update crop draft")
    return true
}
```

rotate 使用相同契约，角度相同不会被误判为 target loss：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | updateRotationDraft(using:to:)
guard
    inlineEditState == nil,
    interactionState.selectedItemID == rotateState.itemID,
    rotationInteractionState?.itemID == rotateState.itemID,
    let item = scene.boardItem(withID: rotateState.itemID)
else {
    return false
}

guard !anglesMatch(
    displayedRotationRadians(for: item),
    draftRotationRadians
) else {
    return true
}

rotationPreviewState = CanvasRotationPreviewState(
    item: item,
    draftRotationRadians: draftRotationRadians
)
requestCanvasRefresh(reason: "update rotate draft")
return true
```

item resize 进一步拆分“没有变化”和“scene mutation 失败”。修改前两种情况共用同一个 guard/return，调用方无法知道是否应结束 interaction：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | resizeSelectedItem(using:to:)（修改前）
guard
    currentItem.center != resizedCenter ||
    currentItem.size != resizedLocalFrame.size,
    let appliedItem = scene.resizeBoardItem(
        withID: resizeState.itemID,
        toCenter: resizedCenter,
        size: resizedLocalFrame.size
    )
else {
    return
}
```

修改后先判断 no-op，再单独判断 mutation 是否成功：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | resizeSelectedItem(using:to:)
let didChange =
    currentItem.center != resizedCenter ||
    currentItem.size != resizedLocalFrame.size
guard didChange else {
    return true
}
guard let appliedItem = scene.resizeBoardItem(
    withID: resizeState.itemID,
    toCenter: resizedCenter,
    size: resizedLocalFrame.size
) else {
    return false
}
resizedItem = appliedItem
```

markdown resize 同样把 center/size/scroll offset 的 no-op 与 `scene.applyBoardItems` 失败分离，避免拖到约束边界时错误取消。

## 修改后 7：crop state factory 拒绝零尺寸 frame

修改前，crop factory 只校验 item 和 inline crop context。现在 crop resize 和 crop translation 都明确拒绝零宽或零高的 full-image/crop local frame：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | makePointerCropState(itemID:handleRole:)
let fullImageLocalFrame = item.fullImageLocalFrame.standardized
let draftLocalFrame = item.localFrame(
    forNormalizedCropRect: inlineEditState.draftCropRectNormalized
).standardized
guard
    fullImageLocalFrame.width > 0,
    fullImageLocalFrame.height > 0,
    draftLocalFrame.width > 0,
    draftLocalFrame.height > 0
else {
    return nil
}
```

macOS 使用相同校验；factory 返回 `nil` 后由调用方统一走 `handlePrimaryPointerCancel()`。

## cancel 业务语义保持不变

本阶段没有把 cancel 改成统一 rollback。双端仍复用原有业务规则：

- rotate item / selection：取消 rotation preview 和 pending transaction。
- crop：提交当前 crop draft；无变化或目标失效时取消 pending transaction。
- move/resize/arrow/group frame：提交已经应用的当前几何。
- pressed 或 canvas drag：取消 pending transaction。
- 最后才把 `pointerDragState` 设为 `.idle`，由 adapter/session 清除 active handle。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | handlePrimaryPointerCancel()
private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .rotatingSelectedItem, .rotatingSelection:
        cancelRotationInteractionIfNeeded(
            refreshReason: "cancel rotate interaction"
        )
    case .croppingSelectedItem, .movingCropFrame:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        clearAlignmentInteractionStateIfNeeded(
            refreshReason: "cancel move alignment interaction"
        )
    case .draggingSelection:
        commitPendingPointerHistoryTransaction(autosaveReason: "move selection")
        clearAlignmentInteractionStateIfNeeded(
            refreshReason: "cancel move alignment interaction"
        )
    case .draggingGroupFrame:
        commitPendingPointerHistoryTransaction(autosaveReason: "move group frame")
    case .resizingGroupFrame:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize group frame")
    case .resizingSelectedItem:
        finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .adjustingArrowEndpoint:
        commitPendingPointerHistoryTransaction(autosaveReason: "adjust arrow")
    case .resizingSelection:
        finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
        commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")
    case .scrollingMarkdownItem:
        commitMarkdownScrollHistoryTransactionIfNeeded()
    case .pressed, .draggingCanvas, .idle:
        editorSession.cancelPendingHistoryTransaction()
    }

    pointerDragState = .idle
}
```

因此 active 状态清理后的 refresh 仍发生在 commit/finalize 或 rotate rollback 之后，最终 snapshot 不会残留 active handle。

## 首轮实现复核与修正

首轮实现完成并通过测试/构建后，又对完整 diff 做了边界审查。审查发现两个 history transaction 风险：

1. 首轮 `cancelActivePointerInteractionForBoundaryIfNeeded()` 曾跳过 `.pressed(nil)`。但 selected item body 或 selection translation area 在 pointer down 时可能已经创建 pending history transaction；外部命令若直接切换状态，会遗留该 transaction。
2. 首轮只修复了 handle update failure，item/selection/group move 的 factory 或持续 mutation failure 仍有直接设置 `.idle` 的路径；如果此前已经应用过几何，可能留下未提交的 transaction。

最终修正为：

- 所有非 idle pointer state 都进入 `handlePrimaryPointerCancel()`。
- item、selection、group move 的初次和持续 failure 也进入同一 cancel 路径。
- 正常 pointer-up 内部触发 selection/text command 时，嵌套 cancel 先清 pending transaction；外层再次 cancel/idle 是幂等操作，不改变 click decision 或 selection history。

最终复核确认：

- iOS/macOS 路径对称。
- 无效命令仍在 `canExecute` 阶段被拦截，不会提前取消 drag。
- pointer failure 不再存在裸写 `.idle` 的路径。
- 普通 drag 提交、rotate rollback 的既有语义保持不变。

## 测试新增

### command 边界分类

新增测试锁定 inline/history 命令与普通 selection/add 命令的分类：

```swift
// MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift | testInlineAndHistoryCommandsResetEditHandleInteractionBoundary()
func testInlineAndHistoryCommandsResetEditHandleInteractionBoundary() {
    let itemID = CanvasItemID()
    let boundaryCommands: [CanvasCommand] = [
        .beginTextEdit(itemID: itemID),
        .commitTextEdit,
        .beginMarkdownEdit(itemID: itemID),
        .commitMarkdownEdit,
        .crop,
        .beginCropMode(itemID: itemID),
        .undo,
        .redo
    ]

    for command in boundaryCommands {
        XCTAssertTrue(command.resetsEditHandleInteractionAfterExecution)
    }

    XCTAssertFalse(
        CanvasCommand
            .selectItem(itemID: itemID, recordHistory: false)
            .resetsEditHandleInteractionAfterExecution
    )
    XCTAssertFalse(
        CanvasCommand.addArrowItem
            .resetsEditHandleInteractionAfterExecution
    )
}
```

### session 已重置时清理 adapter 缓存

新增测试模拟 session 先清 raw state、controller 后收到 idle boundary 的顺序。即使 session transition 已是幂等 no-op，adapter 的 `expectedDraggingIdentity` 仍必须被清除：

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift | testInactiveBoundaryClearsAdapterAfterSessionStateWasReset()
func testInactiveBoundaryClearsAdapterAfterSessionStateWasReset() {
    let identity = makeItemResizeIdentity()
    var adapter = CanvasEditHandleControllerAdapter()
    var state = CanvasEditHandleInteractionState()
    _ = state.apply(adapter.event(for: .pressed(identity)))
    _ = state.apply(adapter.event(for: .draggingHandle))

    state = CanvasEditHandleInteractionState()
    XCTAssertEqual(adapter.expectedDraggingIdentity, identity)
    XCTAssertEqual(state.phase, .inactive)

    let boundaryEvent = adapter.event(for: .inactive)
    let boundaryTransition = state.apply(boundaryEvent)

    XCTAssertEqual(boundaryEvent, .end)
    XCTAssertNil(adapter.expectedDraggingIdentity)
    XCTAssertFalse(boundaryTransition.didChangeState)
    XCTAssertFalse(boundaryTransition.didChangeVisualState)
    XCTAssertEqual(
        adapter.event(for: .draggingHandle),
        .cancel
    )
}
```

## 验证命令与最终结果

相关测试与双端构建按顺序执行，避免 DerivedData 并发锁：

```bash
# 项目根目录 /Users/shaun/cloudDev/MyCanvas_Ver_0 | 阶段 6 相关测试
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests
```

```bash
# 项目根目录 /Users/shaun/cloudDev/MyCanvas_Ver_0 | 阶段 6 双端构建
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS'

xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'generic/platform=iOS'
```

最终验证结果：

- 4 个相关 test suite 共 61 个测试通过，`TEST SUCCEEDED`。
- macOS build：`BUILD SUCCEEDED`。
- iOS build：`BUILD SUCCEEDED`。
- 本阶段相关文件 IDE lint：无错误。
- `git diff --check`：通过。
- 构建中只有既有的 AppIntents metadata skipped 和 macOS XCTest deployment-version linker warning；没有本阶段代码产生的 error。

## 本阶段未改变的行为

- 没有修改 handle identity、hit testing、4pt drag activation threshold 或 drag 离开原 hit rect 后继续使用初始 identity 的规则。
- 没有修改 handle normal/active 颜色、layer path、尺寸或 line width。
- 没有修改 resize、crop、rotate、arrow、selection 或 group frame 的几何算法。
- 没有修改文档格式、持久化模型或 autosave 数据结构。
- handle pressed/dragging 状态本身仍不进入 history snapshot，也不直接触发 autosave。
- 没有新增 undo step；只有真实几何已经变化时，边界 cancel 才继续执行项目原有的 transaction commit。
- 没有提交代码。
