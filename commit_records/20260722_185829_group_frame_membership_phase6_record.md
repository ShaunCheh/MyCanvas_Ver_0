# 20260722_185829_group_frame_membership_phase6_record

## 记录范围

本记录如实对应刚刚实施的 group-frame-interaction 阶段 6：自动归组 membership reconcile。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 中还存在 `.cursor/plans/group-frame-interaction_6e00e0c4.plan.md` 的既有修改；本次记录只覆盖刚刚的阶段 6 代码改动，不把计划文件作为本次代码实现内容。

## 修改前

### `CanvasEditorSession.appendGroup(...)`

修改前，创建带 frame 的 group 时只扩展 board 范围，不会立刻根据 frame 计算框内 item membership；返回值也是创建时的局部 `group`，不会包含后续可能更新后的 `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前 appendGroup 只保存 group frame，不会自动把 frame 内 item 写入 itemIDs。
// 函数名：CanvasEditorSession.appendGroup(...)
groups.append(group)
if let frame {
    expandBoardIfNeeded(toInclude: frame)
}

if let beforeSnapshot {
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "add group",
        autosaveReason: "add group"
    )
}

return group
```

### `CanvasEditorSession.updateGroupFrame(...)`

修改前，更新 group frame 只会写入 frame 并扩展 board，不会同步重算 `groups[groupIndex].itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前 updateGroupFrame 只更新 frame，group membership 不随 frame 变化。
// 函数名：CanvasEditorSession.updateGroupFrame(withID:to:recordHistory:)
let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
groups[groupIndex].frame = standardizedFrame
expandBoardIfNeeded(toInclude: standardizedFrame)

if let beforeSnapshot {
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "update group frame",
        autosaveReason: "update group frame"
    )
}

return true
```

### iOS/macOS pointer history commit

修改前，pointer 几何事务提交时直接提交 history/autosave，没有统一刷新所有 frame group 的 membership。因此 item 移动、缩放、旋转进入或离开 group frame 后，`itemIDs` 可能保持旧值。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS pointer 提交只提交 pending history，不会先重算 group membership。
// 函数名：iOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
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
// 功能注释：修改前 macOS pointer 提交只提交 pending history，不会先重算 group membership。
// 函数名：macOSViewController.commitPendingPointerHistoryTransaction(autosaveReason:)
private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: autosaveReason
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

## 修改后

### 创建 group 后立即 reconcile

现在 `appendGroup(...)` 在保存带 frame 的 group 后，会立即调用 `reconcileItemMembership(forGroupID:)`。因为 membership 可能在 `groups` 数组中的真实 group 上更新，所以返回值改为优先读取 session 内最新 group。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：创建带 frame 的 group 后，立即按 frame 中心点规则计算初始 membership。
// 函数名：CanvasEditorSession.appendGroup(...)
groups.append(group)
if let frame {
    expandBoardIfNeeded(toInclude: frame)
    _ = reconcileItemMembership(forGroupID: group.id)
}

if let beforeSnapshot {
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "add group",
        autosaveReason: "add group"
    )
}

return self.group(withID: group.id) ?? group
```

### 更新 group frame 后同步 reconcile

现在 `updateGroupFrame(...)` 在写入标准化 frame 后，会立即重算当前 group 的 `itemIDs`。这覆盖 group frame 拖拽和缩放过程中的最终 frame 写入。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：group frame 改变后同步更新该 group 的 itemIDs，保证 frame 与 membership 不脱节。
// 函数名：CanvasEditorSession.updateGroupFrame(withID:to:recordHistory:)
let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
groups[groupIndex].frame = standardizedFrame
expandBoardIfNeeded(toInclude: standardizedFrame)
_ = reconcileItemMembership(forGroupID: groupID)

if let beforeSnapshot {
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "update group frame",
        autosaveReason: "update group frame"
    )
}

return true
```

### 新增单个 group membership 重算 API

新增 `reconcileItemMembership(forGroupID:)`，规则是：遍历 `scene.orderedBoardItems()`，取每个 item 的 `worldBounds.standardized` 中心点，中心点落在 group frame 内则纳入 `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：按 item worldBounds 中心点是否落入 group frame，重算单个 group 的 itemIDs。
// 函数名：CanvasEditorSession.reconcileItemMembership(forGroupID:)
@discardableResult
func reconcileItemMembership(forGroupID groupID: CanvasItemGroupID) -> Bool {
    guard
        let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
        let rawFrame = groups[groupIndex].frame
    else {
        return false
    }

    let frame = rawFrame.standardized
    guard frame.isNull == false,
          frame.isInfinite == false,
          frame.width > 0,
          frame.height > 0
    else {
        return false
    }

    let memberIDs = scene.orderedBoardItems().compactMap { item -> CanvasItemID? in
        let bounds = item.worldBounds.standardized
        guard bounds.isNull == false,
              bounds.isInfinite == false,
              bounds.width > 0,
              bounds.height > 0
        else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return frame.contains(center) ? item.id : nil
    }

    guard groups[groupIndex].itemIDs != memberIDs else {
        return false
    }

    groups[groupIndex].itemIDs = memberIDs
    return true
}
```

### 新增全部 frame group membership 重算 API

新增 `reconcileFrameGroupMemberships()`，只处理有 `frame` 的 group。这个 API 用于 pointer 几何事务提交前统一刷新 membership，覆盖 item move / resize / rotate 等路径。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：统一重算所有带 frame 的 group membership，用于几何事务提交前收敛最终状态。
// 函数名：CanvasEditorSession.reconcileFrameGroupMemberships()
@discardableResult
func reconcileFrameGroupMemberships() -> Bool {
    let groupIDs = groups.compactMap { group in
        group.frame == nil ? nil : group.id
    }
    var didChange = false
    for groupID in groupIDs {
        didChange = reconcileItemMembership(forGroupID: groupID) || didChange
    }
    return didChange
}
```

### iOS 提交 history 前统一 reconcile

iOS 侧在 `commitPendingPointerHistoryTransaction(...)` 开头调用 `reconcileFrameGroupMemberships()`，确保 frame / item 几何变化和最终 membership 一起进入 pending history transaction 的提交结果。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS pointer 几何事务提交前先重算所有 frame group membership。
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

### macOS 提交 history 前统一 reconcile

macOS 侧做同样接入，保持与 iOS 的交互提交语义一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS pointer 几何事务提交前先重算所有 frame group membership。
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

## 行为变化

- group frame 创建后，会自动把中心点落在 frame 内的 item 加入 group。
- group frame 拖拽或缩放后，会按最终 frame 自动刷新 `itemIDs`。
- item 移动、缩放、旋转等 pointer 几何事务提交前，会统一刷新所有带 frame 的 group membership。
- membership 判定使用 item `worldBounds` 的中心点，而不是 item 与 frame 的相交面积。
- 删除 item 仍沿用已有 `removeDeletedItemIDsFromGroups(...)` 清理逻辑，本次没有改动删除路径。

## 验证记录

- 已执行 `ReadLints` 检查 `CanvasEditorSession.swift`、`iOSViewController.swift`、`macOSViewController.swift`，未发现新增 linter 错误。
- 已执行 macOS build：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build`，通过。
- 已执行 iOS Simulator build：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build`，通过。
