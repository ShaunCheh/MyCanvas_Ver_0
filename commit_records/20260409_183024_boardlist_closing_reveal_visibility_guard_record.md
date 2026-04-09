# 20260409_183024_boardlist_closing_reveal_visibility_guard_record

## 记录说明

本记录基于当前工作区中“刚刚这次关闭转场位置修复”的 `git diff` 与已落地代码整理，不包含原始 `git diff` 文本。

本次只记录 2 个文件的新增修改：

- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`

当前统计：`2 files changed, 67 insertions(+), 15 deletions(-)`

## 问题现象

在 grid 视图里，从某个可见位置打开 board，再返回 boardlist 后，目标卡片会跑到顶部附近。

这次定位确认后的根因不是 `contentUpdatedAt` 排序仍然错误，而是关闭转场的 target-ready 链路里，为了拿目标卡片的 transition geometry，`revealBoard(...)` 会无条件触发滚动：

- iOS：`scrollToItem(..., at: .top, animated: false)`
- macOS：`scrollToItems(..., scrollPosition: .nearestVerticalEdge)`

这会把本来已经在可视区中的目标卡片也强行挪到顶部或最近边缘，造成“返回后位置不对”的视觉结果。

## 修改目标

把关闭转场里的 reveal 行为改成：

- 如果目标卡片已经在可视区内：不滚动，直接读取 geometry
- 如果目标卡片不在可视区内：才做最小必要滚动
- 同时补充 `wasVisible` / `didScroll` 诊断信息，方便后续继续看 trace

## 详细修改

### 1. `iOSBoardListViewController.swift`：关闭转场不再无条件滚到顶部

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: revealBoard(at:boardID:)
// 说明: iOS 关闭转场为了拿目标 geometry，会无条件把目标卡片滚到顶部。
private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        logRenameTrace("revealBoardAborted", extra: "boardID=\(boardID.uuidString)")
        return
    }

    let revealStart = BoardListCanvasTransitionDebugLogger.now()
    let dispatchDelay = closingTransitionTimingState?.revealDispatchEnqueuedAt.map {
        revealStart - $0
    }
    updateClosingTransitionTimingState { state in
        state.revealDispatchDelay = dispatchDelay
    }
    logClosingTransitionTiming(
        phase: "revealBoardBegin",
        localDuration: dispatchDelay,
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
    )
    logRenameTrace(
        "revealBoard",
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
    )

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(
        at: indexPath,
        at: .top,
        animated: false
    )
    collectionView.layoutIfNeeded()
    let preparationResult = resolveTransitionTargetGeometry(for: boardID)
    logClosingTransitionTiming(
        phase: "revealBoardEnd",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - revealStart,
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(preparationResult?.resolvedIndexPath.section ?? indexPath.section),item=\(preparationResult?.resolvedIndexPath.item ?? indexPath.item)] " +
            "usedFallbackGeometry=\(preparationResult?.usedFallbackGeometry ?? true) " +
            "hasCardRect=\(preparationResult?.geometry.cardRect != nil)"
    )
    if let preparationResult {
        finishPendingTransitionTargetResolution(preparationResult)
    } else {
        finishPendingTransitionTargetResolution(
            for: boardID,
            geometry: .init()
        )
    }
    pendingRevealBoardID = nil
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: revealBoard(at:boardID:) / isBoardTransitionTargetVisible(at:) / scrollBoardTransitionTargetIntoViewIfNeeded(at:)
// 说明: 先判断目标卡片是否已在可视区；已可见则不滚动，不可见才做最小滚动。
private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        logRenameTrace("revealBoardAborted", extra: "boardID=\(boardID.uuidString)")
        return
    }

    let revealStart = BoardListCanvasTransitionDebugLogger.now()
    let dispatchDelay = closingTransitionTimingState?.revealDispatchEnqueuedAt.map {
        revealStart - $0
    }
    updateClosingTransitionTimingState { state in
        state.revealDispatchDelay = dispatchDelay
    }
    collectionView.layoutIfNeeded()
    let wasVisibleBeforeReveal = isBoardTransitionTargetVisible(at: indexPath)
    logClosingTransitionTiming(
        phase: "revealBoardBegin",
        localDuration: dispatchDelay,
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)] " +
            "wasVisible=\(wasVisibleBeforeReveal)"
    )
    logRenameTrace(
        "revealBoard",
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)] " +
            "wasVisible=\(wasVisibleBeforeReveal)"
    )

    let didScroll = scrollBoardTransitionTargetIntoViewIfNeeded(at: indexPath)
    let preparationResult = resolveTransitionTargetGeometry(for: boardID)
    logClosingTransitionTiming(
        phase: "revealBoardEnd",
        localDuration: BoardListCanvasTransitionDebugLogger.now() - revealStart,
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(preparationResult?.resolvedIndexPath.section ?? indexPath.section),item=\(preparationResult?.resolvedIndexPath.item ?? indexPath.item)] " +
            "didScroll=\(didScroll) " +
            "usedFallbackGeometry=\(preparationResult?.usedFallbackGeometry ?? true) " +
            "hasCardRect=\(preparationResult?.geometry.cardRect != nil)"
    )
    if let preparationResult {
        finishPendingTransitionTargetResolution(preparationResult)
    } else {
        finishPendingTransitionTargetResolution(
            for: boardID,
            geometry: .init()
        )
    }
    pendingRevealBoardID = nil
}

private func isBoardTransitionTargetVisible(
    at indexPath: IndexPath
) -> Bool {
    guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
        return false
    }

    return collectionView.bounds.intersects(layoutAttributes.frame)
}

@discardableResult
private func scrollBoardTransitionTargetIntoViewIfNeeded(
    at indexPath: IndexPath
) -> Bool {
    guard isBoardTransitionTargetVisible(at: indexPath) == false else {
        return false
    }

    guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
        return false
    }

    collectionView.scrollRectToVisible(
        layoutAttributes.frame.insetBy(dx: 0, dy: -Layout.itemSpacing),
        animated: false
    )
    collectionView.layoutIfNeeded()
    return true
}
```

关键变化：

- 不再直接 `scrollToItem(..., at: .top)`
- 新增可见性判断
- 新增“仅在不可见时滚动”的辅助函数
- trace 补了 `wasVisible` / `didScroll`

### 2. `macOSBoardListViewController.swift`：与 iOS 对齐 reveal 策略

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数: revealBoard(at:boardID:)
// 说明: macOS 关闭转场同样会无条件滚到最近边缘。
private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        logRenameTrace("revealBoardAborted", extra: "boardID=\(boardID.uuidString)")
        return
    }

    logRenameTrace(
        "revealBoard",
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)]"
    )

    collectionView.layoutSubtreeIfNeeded()
    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    collectionView.layoutSubtreeIfNeeded()
    finishPendingTransitionTargetResolution(
        for: boardID,
        geometry: transitionTargetGeometry(for: boardID)
    )
    pendingRevealBoardID = nil
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数: revealBoard(at:boardID:) / isBoardTransitionTargetVisible(at:) / scrollBoardTransitionTargetIntoViewIfNeeded(at:)
// 说明: macOS 也改成“已可见不滚动，不可见才最小滚动”，避免两端语义继续分叉。
private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        logRenameTrace("revealBoardAborted", extra: "boardID=\(boardID.uuidString)")
        return
    }

    logRenameTrace(
        "revealBoard",
        extra:
            "boardID=\(boardID.uuidString) " +
            "indexPath=[section=\(indexPath.section),item=\(indexPath.item)] " +
            "wasVisible=\(isBoardTransitionTargetVisible(at: indexPath))"
    )

    _ = scrollBoardTransitionTargetIntoViewIfNeeded(at: indexPath)
    finishPendingTransitionTargetResolution(
        for: boardID,
        geometry: transitionTargetGeometry(for: boardID)
    )
    pendingRevealBoardID = nil
}

private func isBoardTransitionTargetVisible(
    at indexPath: IndexPath
) -> Bool {
    guard let layoutAttributes = collectionView.layoutAttributesForItem(at: indexPath) else {
        return false
    }

    return collectionView.visibleRect.intersects(layoutAttributes.frame)
}

@discardableResult
private func scrollBoardTransitionTargetIntoViewIfNeeded(
    at indexPath: IndexPath
) -> Bool {
    collectionView.layoutSubtreeIfNeeded()
    guard isBoardTransitionTargetVisible(at: indexPath) == false else {
        return false
    }

    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    collectionView.layoutSubtreeIfNeeded()
    return true
}
```

关键变化：

- 不再默认 `scrollToItems(..., .nearestVerticalEdge)`
- 新增可见性守卫
- 让 macOS 和 iOS 的关闭转场 reveal 语义保持一致

## 本次修复的实际效果

这次修复解决的是“关闭转场为了找目标卡片而主动把它滚到顶部/边缘”的问题。

因此修复后的预期行为是：

- 如果目标卡片本来就在当前可视区，返回 boardlist 后应该保持原有屏幕位置附近，不再被强制顶到顶部
- 如果目标卡片已经滚出屏幕，仍然允许做最小必要滚动，以保证 closing target geometry 能被正常解析

## 验证

已完成：

- `git diff --stat` 已确认本次仅涉及 2 个 boardlist 控制器文件
- IDE lints：无新增错误
- 编译验证：
  - 命令：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -configuration Debug build`
  - 结果：`BUILD SUCCEEDED`

尚未在本记录中完成：

- iOS 手动回归验证“目标卡片本来已可见时，返回后不再被推到顶部”
- macOS 手动回归验证同一路径

## 补充说明

本记录只覆盖“关闭转场 reveal 可见性守卫”这次修复，不重复展开上一份 `split_update_time` 记录中的双时间线改造内容。
