# 20260722_190315_group_frame_history_autosave_phase7_record

## 记录范围

本记录如实对应刚刚实施的 group-frame-interaction 阶段 7：统一 group frame 拖拽/缩放、membership reconcile、history 与 autosave 提交。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 中仍存在 `.cursor/plans/group-frame-interaction_6e00e0c4.plan.md` 的既有修改；本记录只覆盖刚刚阶段 7 的代码改动。

## 修改前

### `BoardHistoryController` 不能查询 pending transaction 状态

修改前，history controller 只能 begin / cancel / commit pending transaction；外层无法判断当前是否有 pending transaction，也无法在 commit 前比较 pending 初始 snapshot 与当前 snapshot 是否已经不同。

```swift
// MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift
// 功能注释：修改前只提供取消与提交 pending transaction，不能单独查询 pending 状态或变化状态。
// 函数名：BoardHistoryController.cancelPendingTransaction()
func cancelPendingTransaction() {
    pendingTransaction = nil
}

@discardableResult
func commitPendingTransaction(
    to snapshot: BoardHistorySnapshot
) -> Bool {
    guard let pendingTransaction else {
        return false
    }

    self.pendingTransaction = nil
    return recordChange(
        from: pendingTransaction.initialSnapshot,
        to: snapshot,
        reason: pendingTransaction.reason
    )
}
```

### `CanvasEditorSession` 提交 pointer history 时缺少 membership-aware helper

修改前，`CanvasEditorSession.commitPendingHistoryTransaction(autosaveReason:)` 只把当前 snapshot 直接提交给 history controller；membership reconcile 的时机由平台 controller 自己在提交前调用，无法根据“只有 membership 变化”切换 autosave reason。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前提交 pending history transaction 时不感知 group membership reconcile。
// 函数名：CanvasEditorSession.commitPendingHistoryTransaction(autosaveReason:)
@discardableResult
func commitPendingHistoryTransaction(
    autosaveReason: String? = nil
) -> Bool {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return false
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }

    return true
}
```

### `updateGroupFrame(...)` 每次写 frame 都立即 reconcile

阶段 6 后，`updateGroupFrame(...)` 会在每次 frame 更新后立刻调用 `reconcileItemMembership(forGroupID:)`。这能保证 membership 正确，但在拖拽和缩放过程中会让 membership 随每一帧 pointer move 更新，不符合阶段 7 “move 期间只更新 frame 和 render，pointer up 时统一提交 frame + membership”的目标。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前 updateGroupFrame 每次更新 frame 都会同步重算 membership。
// 函数名：CanvasEditorSession.updateGroupFrame(withID:to:recordHistory:)
func updateGroupFrame(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    recordHistory: Bool = false
) -> Bool {
    // ... 校验 group、frame 有效性
    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    groups[groupIndex].frame = standardizedFrame
    expandBoardIfNeeded(toInclude: standardizedFrame)
    _ = reconcileItemMembership(forGroupID: groupID)

    // ... 按需记录 immediate history
    return true
}
```

### iOS/macOS 在 pointer commit 前直接 reconcile

修改前，iOS 和 macOS 的 `commitPendingPointerHistoryTransaction(...)` 直接在平台层调用 `reconcileFrameGroupMemberships()`，然后用原 autosave reason 提交。这样逻辑分散在平台 controller 中，也无法区分“只有 membership 变化”的 autosave reason。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS 在平台层直接 reconcile，然后按原 autosave reason 提交。
// 函数名：iOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    _ = editorSession.reconcileFrameGroupMemberships()
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS 在平台层直接 reconcile，然后按原 autosave reason 提交。
// 函数名：macOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    _ = editorSession.reconcileFrameGroupMemberships()
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

## 修改后

### `BoardHistoryController` 暴露 pending transaction 查询能力

新增 `hasPendingTransaction` 与 `pendingTransactionHasChanges(to:)`。外层可以在 reconcile membership 前判断 pending transaction 是否存在，以及当前 snapshot 相比 transaction 起点是否已经发生 frame / item / selection 等变化。

```swift
// MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift
// 功能注释：提供 pending transaction 状态与变化查询，供提交前决定 autosave reason。
// 函数名：BoardHistoryController.hasPendingTransaction / pendingTransactionHasChanges(to:)
var hasPendingTransaction: Bool {
    pendingTransaction != nil
}

func pendingTransactionHasChanges(
    to snapshot: BoardHistorySnapshot
) -> Bool? {
    guard let pendingTransaction else {
        return nil
    }

    return pendingTransaction.initialSnapshot != snapshot
}
```

### `CanvasEditorSession` 新增 membership-aware pending commit helper

新增 `commitPendingHistoryTransaction(reconcilingFrameGroupMembershipsWithAutosaveReason:membershipAutosaveReason:)`。它先确认存在 pending transaction，再在 membership reconcile 前判断是否已有变化，然后统一调用 `reconcileFrameGroupMemberships()`，最后提交同一个 pending transaction。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：提交 pending transaction 前统一重算 frame group membership，并按变化来源选择 autosave reason。
// 函数名：CanvasEditorSession.commitPendingHistoryTransaction(reconcilingFrameGroupMembershipsWithAutosaveReason:membershipAutosaveReason:)
@discardableResult
func commitPendingHistoryTransaction(
    reconcilingFrameGroupMembershipsWithAutosaveReason autosaveReason: String,
    membershipAutosaveReason: String = "update group membership"
) -> Bool {
    guard historyController.hasPendingTransaction else {
        return false
    }

    let hadChangesBeforeMembershipReconcile =
        historyController.pendingTransactionHasChanges(
            to: currentBoardHistorySnapshot()
        ) ?? false
    let didUpdateGroupMembership = reconcileFrameGroupMemberships()
    let resolvedAutosaveReason =
        didUpdateGroupMembership && hadChangesBeforeMembershipReconcile == false
        ? membershipAutosaveReason
        : autosaveReason

    return commitPendingHistoryTransaction(
        autosaveReason: resolvedAutosaveReason
    )
}
```

### `updateGroupFrame(...)` 支持延迟 membership reconcile

`updateGroupFrame(...)` 新增 `reconcileMembership` 参数，默认值为 `true`，保持普通调用路径的原行为。拖拽/缩放中的 group frame 更新可以传 `false`，让过程帧只更新 frame 和 render，不每帧改 `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：允许调用方选择是否在更新 group frame 后立即重算 membership。
// 函数名：CanvasEditorSession.updateGroupFrame(withID:to:recordHistory:reconcileMembership:)
func updateGroupFrame(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    recordHistory: Bool = false,
    reconcileMembership: Bool = true
) -> Bool {
    // ... 校验 group、frame 有效性
    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    groups[groupIndex].frame = standardizedFrame
    expandBoardIfNeeded(toInclude: standardizedFrame)
    if reconcileMembership {
        _ = reconcileItemMembership(forGroupID: groupID)
    }

    // ... 按需记录 immediate history
    return true
}
```

### iOS group frame 拖拽/缩放过程中只更新 frame

iOS 的 `moveGroupFrame(...)` 与 `resizeGroupFrame(...)` 调用 `updateGroupFrame(...)` 时传入 `reconcileMembership: false`，避免 pointer move 的每一帧都更新 membership。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group frame 拖拽过程中只更新 frame，membership 留到 pointer commit 前统一 reconcile。
// 函数名：iOSViewController.moveGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: dragState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group frame 缩放过程中只更新 frame，membership 留到 pointer commit 前统一 reconcile。
// 函数名：iOSViewController.resizeGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: resizeState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: resizeState.groupID)
        == proposedFrame.standardized
}
```

### macOS group frame 拖拽/缩放过程中只更新 frame

macOS 与 iOS 保持一致：拖拽/缩放过程只更新 group frame，不在 pointer move 期间更新 membership。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group frame 拖拽过程中只更新 frame，membership 留到 pointer commit 前统一 reconcile。
// 函数名：macOSViewController.moveGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: dragState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group frame 缩放过程中只更新 frame，membership 留到 pointer commit 前统一 reconcile。
// 函数名：macOSViewController.resizeGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: resizeState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: resizeState.groupID)
        == proposedFrame.standardized
}
```

### iOS/macOS pointer commit 改用 shared helper

iOS 和 macOS 都不再直接调用 `reconcileFrameGroupMemberships()`，而是调用 `CanvasEditorSession` 的 shared commit helper。这样 frame 变化、item 几何变化和 membership 变化都会被收敛到同一个 pending history transaction。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS pointer commit 交给 editor session 统一处理 membership reconcile 与 history/autosave 提交。
// 函数名：iOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        reconcilingFrameGroupMembershipsWithAutosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS pointer commit 交给 editor session 统一处理 membership reconcile 与 history/autosave 提交。
// 函数名：macOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        reconcilingFrameGroupMembershipsWithAutosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

## 行为变化

- group frame 拖拽和缩放开始时仍通过 pending history transaction 记录 before snapshot。
- pointer move 期间只更新 group frame 和 render，不再每帧重算 `itemIDs`。
- pointer up / cancel 的提交路径会先统一重算所有 frame group membership，再提交同一个 pending history transaction。
- 如果 frame / item 几何已经变化，autosave reason 保持原操作语义，例如 `move group frame` 或 `resize group frame`。
- 如果提交前只有 membership reconcile 产生变化，autosave reason 使用 `update group membership`。
- 如果 frame 和 membership 都没有变化，`BoardHistoryController.recordChange(...)` 仍会返回 `false`，不会产生 undo entry，也不会触发 autosave。

## 验证记录

- 已执行 `ReadLints` 检查 `BoardHistoryController.swift`、`CanvasEditorSession.swift`、`iOSViewController.swift`、`macOSViewController.swift`，未发现新增 linter 错误。
- 已执行 macOS build：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build`，通过。
- 已执行 iOS Simulator build：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build`，通过。
