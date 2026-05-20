# 20260520_181034_CST_markdown_scroll_fast_path_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_滚动优化_a83bbb66.plan.md`。
  - 针对 iOS 长 markdown block 的 `overflow-y` 内部滚动卡顿，引入 transient layer fast path。
  - 保留 `scrollOffsetY` 的最终持久化、history、autosave 合同，但把滚动中的高频路径从“每帧写模型 + 整画布 refresh”改成“只更新当前 markdown layer 的可视偏移与滚动条，结束后再一次性 commit”。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
- 参考现状：
  - 生成本记录前，执行 `date +%Y%m%d_%H%M%S` 得到时间戳：`20260520_181034`，本文件按该时间戳命名。
  - 生成本记录前，针对本次优化相关文件执行 `git diff --stat -- ...`，结果为：`9 files changed, 273 insertions(+), 30 deletions(-)`。
  - 生成本记录前，`git status --short` 中，本次优化对应的 9 个文件均为已修改状态。
- 本记录不包含：
  - `macOS` 对称滚动优化。
  - 将 `scrollOffsetY` 从当前 content 变更语义中继续拆出、进一步弱化 autosave / thumbnail 代价的第二阶段重构。

## 当前 changes 摘要

- `iOSViewController` 引入 `TransientMarkdownScrollState`，滚动热路径开始复用 `contentHeight` / `maxScrollOffsetY` / 当前 transient offset。
- `iOSCanvasViewportView`、`CanvasMarkdownItemLayer`、`CanvasMarkdownContentLayer` 新增按 `itemID` 的 markdown 轻量 scroll 更新接口，滚动中只改 layer 偏移和 scrollbar，不重建整张 `CanvasRenderSnapshot`。
- `CanvasEditorSession.updateMarkdownItemScrollOffset(...)` 开始支持外部传入已知 `contentHeight`，避免最终 commit 时再次做全文测量。
- `CanvasRenderer`、`CanvasMarkdownLayoutMeasurer`、`CanvasMarkdownBitmapRenderer`、`CanvasMarkdownContentLayer`、`CanvasEditorSession` 的 markdown 高频 trace 默认关闭，降低滚动期间的日志噪音。
- `CanvasMarkdownLayerTests` 新增两条回归测试，锁定 transient scroll 不 relayout / 不 rerender，以及 scrollbar thumb 跟随 transient scroll 的合同。

## 修改一：iOS 滚动链路从“每帧写模型 + 全量刷新”改成“transient scroll + 结束 commit”

### 修改前

- 是否可滚动靠 `markdownItemSupportsInternalScroll(_:)` 每次现算。
- `consumeMarkdownScrollIfNeeded(for:markdownItemID:)` 每个有效增量都会重新测量 `contentHeight`。
- 一旦产生有效滚动，就直接调用 `editorSession.updateMarkdownItemScrollOffset(...)` 写回 scene，并立刻 `requestCanvasRefresh(...)` 触发整画布刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: markdownItemSupportsInternalScroll(_:) / consumeMarkdownScrollIfNeeded(for:markdownItemID:)
// 功能说明: 修改前滚动热路径会重复测量 markdown 内容高度，并把每次滚动增量直接写回 document/model，再同步触发整画布 refresh。
private func markdownItemSupportsInternalScroll(
    _ item: CanvasMarkdownItem
) -> Bool {
    let contentHeight = editorSession.measuredMarkdownContentHeight(for: item)
    return contentHeight - item.size.height > Self.geometryComparisonEpsilon
}

private func consumeMarkdownScrollIfNeeded(
    for translation: CGPoint,
    markdownItemID: CanvasItemID
) -> CGPoint {
    guard let markdownItem = scene.markdownItem(withID: markdownItemID) else {
        return translation
    }
    let contentHeight = editorSession.measuredMarkdownContentHeight(for: markdownItem)
    let maxScrollOffsetY = max(contentHeight - markdownItem.size.height, 0)
    guard maxScrollOffsetY > Self.geometryComparisonEpsilon else {
        return translation
    }

    let resolvedZoomScale =
        camera.zoomScale.isFinite && camera.zoomScale > 0 ? camera.zoomScale : 1
    let proposedScrollDeltaY = -translation.y / resolvedZoomScale
    guard proposedScrollDeltaY.isFinite else {
        return translation
    }

    let resolvedScrollOffsetY = min(
        max(markdownItem.scrollOffsetY + proposedScrollDeltaY, 0),
        maxScrollOffsetY
    )
    let appliedScrollDeltaY = resolvedScrollOffsetY - markdownItem.scrollOffsetY
    if abs(appliedScrollDeltaY) > Self.geometryComparisonEpsilon {
        beginMarkdownScrollHistoryTransactionIfNeeded()
        if editorSession.updateMarkdownItemScrollOffset(
            withID: markdownItem.id,
            scrollOffsetY: resolvedScrollOffsetY
        ) != nil {
            requestCanvasRefresh(reason: "scroll markdown item")
            scheduleMarkdownScrollHistoryCommit()
        }
    }

    let consumedViewportDeltaY = -appliedScrollDeltaY * resolvedZoomScale
    return CGPoint(
        x: translation.x,
        y: translation.y - consumedViewportDeltaY
    )
}
```

### 修改后

- 新增 `TransientMarkdownScrollState`，把 `contentHeight`、`maxScrollOffsetY` 和当前 transient `scrollOffsetY` 缓存在 controller。
- 在触摸滚动命中时，先通过 `makeTransientMarkdownScrollState(for:)` 解析并缓存可滚动信息。
- 滚动中优先走 `canvasViewportView.applyTransientMarkdownScroll(...)`，只更新当前 markdown layer；只有轻量通道不可用时才 fallback 到旧的 scene 写回路径。
- `commitMarkdownScrollHistoryTransactionIfNeeded()` 现在会在结束/取消/debounce 到期时，把 transient 结果一次性写回 `editorSession` 并补一次完整 refresh。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: TransientMarkdownScrollState / makeTransientMarkdownScrollState(for:commitExistingIfNeeded:) / consumeMarkdownScrollIfNeeded(for:markdownItemID:)
// 功能说明: 修改后 controller 在滚动开始时缓存 contentHeight 与 maxScrollOffsetY，滚动中优先走 transient layer fast path，避免每帧写 scene 和重建 snapshot。
private struct TransientMarkdownScrollState {
    let itemID: CanvasItemID
    let contentHeight: CGFloat
    let maxScrollOffsetY: CGFloat
    var scrollOffsetY: CGFloat
}

private func makeTransientMarkdownScrollState(
    for item: CanvasMarkdownItem,
    commitExistingIfNeeded: Bool = true
) -> TransientMarkdownScrollState? {
    if let transientMarkdownScrollState {
        if transientMarkdownScrollState.itemID == item.id {
            return transientMarkdownScrollState
        }
        if commitExistingIfNeeded {
            commitMarkdownScrollHistoryTransactionIfNeeded()
        }
    }

    let contentHeight = editorSession.measuredMarkdownContentHeight(for: item)
    let maxScrollOffsetY = max(contentHeight - item.size.height, 0)
    guard maxScrollOffsetY > Self.geometryComparisonEpsilon else {
        transientMarkdownScrollState = nil
        return nil
    }

    let scrollState = TransientMarkdownScrollState(
        itemID: item.id,
        contentHeight: contentHeight,
        maxScrollOffsetY: maxScrollOffsetY,
        scrollOffsetY: min(
            max(item.scrollOffsetY, 0),
            maxScrollOffsetY
        )
    )
    transientMarkdownScrollState = scrollState
    return scrollState
}

private func consumeMarkdownScrollIfNeeded(
    for translation: CGPoint,
    markdownItemID: CanvasItemID
) -> CGPoint {
    guard let markdownItem = scene.markdownItem(withID: markdownItemID) else {
        if transientMarkdownScrollState?.itemID == markdownItemID {
            transientMarkdownScrollState = nil
        }
        return translation
    }
    guard var scrollState = makeTransientMarkdownScrollState(for: markdownItem) else {
        return translation
    }

    let resolvedZoomScale =
        camera.zoomScale.isFinite && camera.zoomScale > 0 ? camera.zoomScale : 1
    let proposedScrollDeltaY = -translation.y / resolvedZoomScale
    guard proposedScrollDeltaY.isFinite else {
        return translation
    }

    let previousScrollOffsetY = scrollState.scrollOffsetY
    let resolvedScrollOffsetY = min(
        max(previousScrollOffsetY + proposedScrollDeltaY, 0),
        scrollState.maxScrollOffsetY
    )
    var appliedScrollDeltaY = resolvedScrollOffsetY - previousScrollOffsetY
    if abs(appliedScrollDeltaY) > Self.geometryComparisonEpsilon {
        beginMarkdownScrollHistoryTransactionIfNeeded()
        if let appliedScrollOffsetY = canvasViewportView.applyTransientMarkdownScroll(
            for: markdownItem.id,
            scrollOffsetY: resolvedScrollOffsetY
        ) {
            scrollState.scrollOffsetY = appliedScrollOffsetY
            transientMarkdownScrollState = scrollState
            appliedScrollDeltaY = appliedScrollOffsetY - previousScrollOffsetY
            scheduleMarkdownScrollHistoryCommit()
        } else if let updatedItem = editorSession.updateMarkdownItemScrollOffset(
            withID: markdownItem.id,
            scrollOffsetY: resolvedScrollOffsetY,
            contentHeight: scrollState.contentHeight
        ) {
            transientMarkdownScrollState = nil
            appliedScrollDeltaY = updatedItem.scrollOffsetY - previousScrollOffsetY
            requestCanvasRefresh(reason: "scroll markdown item fallback")
            scheduleMarkdownScrollHistoryCommit()
        }
    }

    let consumedViewportDeltaY = -appliedScrollDeltaY * resolvedZoomScale
    return CGPoint(
        x: translation.x,
        y: translation.y - consumedViewportDeltaY
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: commitMarkdownScrollHistoryTransactionIfNeeded()
// 功能说明: 修改后滚动结束时先把 transient scrollOffsetY 一次性写回 editorSession，再执行 history commit 与 autosave 链路。
private func commitMarkdownScrollHistoryTransactionIfNeeded() {
    markdownScrollHistoryCommitWorkItem?.cancel()
    markdownScrollHistoryCommitWorkItem = nil
    let transientScrollState = transientMarkdownScrollState
    transientMarkdownScrollState = nil
    if let transientScrollState {
        _ = editorSession.updateMarkdownItemScrollOffset(
            withID: transientScrollState.itemID,
            scrollOffsetY: transientScrollState.scrollOffsetY,
            contentHeight: transientScrollState.contentHeight
        )
        requestCanvasRefresh(reason: "commit markdown scroll item")
    }
    guard isMarkdownScrollHistoryTransactionActive else {
        return
    }
    isMarkdownScrollHistoryTransactionActive = false
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: "scroll markdown item"
    ) else {
        return
    }
}
```

## 修改二：viewport 与 shared layer 增加按 itemID 的轻量滚动更新接口

### 修改前

- `iOSCanvasViewportView` 只有 `apply(_ snapshot:)` 这类整张快照入口。
- `CanvasMarkdownItemLayer` 只有完整 `update(with:markdownPayload:contentsScale:)` 路径。
- 也就是说，controller 想让 markdown 视觉滚动，只能回到 snapshot / item refresh 的完整通路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: apply(_:)
// 功能说明: 修改前 viewport 只接受完整 snapshot，没有按 itemID 轻量更新 markdown scroll 的入口。
func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshItemLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}
```

### 修改后

- `iOSCanvasViewportView` 新增 `applyTransientMarkdownScroll(for:scrollOffsetY:)`，controller 可以直接命中当前 markdown layer。
- `CanvasMarkdownItemLayer` 新增 `updateTransientScrollOffset(_:)`，复用现有布局结果，只更新 `contentLayer.position.y` 和 scrollbar。
- `CanvasMarkdownContentLayer` 新增 `applyTransientScrollOffset(_:logicalSize:)` 与 `applyResolvedScrollOffset(...)`，把“滚动偏移 clamp + layer 位移”抽成可复用的轻量 path。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: applyTransientMarkdownScroll(for:scrollOffsetY:)
// 功能说明: 修改后 controller 可以按 itemID 直接推送 transient scrollOffsetY，只更新当前 markdown layer，不触发整张 snapshot apply。
@discardableResult
func applyTransientMarkdownScroll(
    for itemID: CanvasItemID,
    scrollOffsetY: CGFloat
) -> CGFloat? {
    guard let markdownLayer = markdownLayers[itemID] else {
        return nil
    }

    var resolvedScrollOffsetY: CGFloat?
    performWithoutLayerActions {
        resolvedScrollOffsetY = markdownLayer.updateTransientScrollOffset(
            scrollOffsetY
        )
    }
    return resolvedScrollOffsetY
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
// 函数名: updateTransientScrollOffset(_:)
// 功能说明: 修改后 item layer 会在不改变 world geometry、rotation、zIndex 的前提下，只更新 markdown 内部滚动位移与 scrollbar 几何。
@discardableResult
func updateTransientScrollOffset(
    _ scrollOffsetY: CGFloat
) -> CGFloat? {
    let logicalSize = bounds.size
    guard
        logicalSize.width > 0,
        logicalSize.height > 0,
        let layout = contentLayer.currentLayout,
        let resolvedScrollOffsetY = contentLayer.applyTransientScrollOffset(
            scrollOffsetY,
            logicalSize: logicalSize
        )
    else {
        return nil
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    applyScrollbar(
        logicalSize: logicalSize,
        layout: layout,
        scrollOffsetY: resolvedScrollOffsetY
    )
    CATransaction.commit()
    return resolvedScrollOffsetY
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名: applyTransientScrollOffset(_:logicalSize:) / applyResolvedScrollOffset(proposedScrollOffsetY:logicalSize:layout:)
// 功能说明: 修改后 content layer 把滚动偏移 clamp 与 position 更新抽成独立轻量接口，复用已有 layout，不触发 relayout / reraster。
@discardableResult
func applyTransientScrollOffset(
    _ scrollOffsetY: CGFloat,
    logicalSize: CGSize
) -> CGFloat? {
    guard let layout = currentLayout else {
        return nil
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let resolvedScrollOffsetY = applyResolvedScrollOffset(
        proposedScrollOffsetY: scrollOffsetY,
        logicalSize: logicalSize,
        layout: layout
    )
    CATransaction.commit()
    return resolvedScrollOffsetY
}

@discardableResult
private func applyResolvedScrollOffset(
    proposedScrollOffsetY: CGFloat,
    logicalSize: CGSize,
    layout: CanvasMarkdownLayoutResult
) -> CGFloat {
    let maxScrollOffsetY = max(
        layout.contentSize.height - logicalSize.height,
        0
    )
    let resolvedScrollOffsetY = min(
        max(proposedScrollOffsetY, 0),
        maxScrollOffsetY
    )
    guard lastAppliedScrollOffsetY != resolvedScrollOffsetY else {
        return resolvedScrollOffsetY
    }
    position = CGPoint(x: 0, y: -resolvedScrollOffsetY)
    lastAppliedScrollOffsetY = resolvedScrollOffsetY
    return resolvedScrollOffsetY
}
```

## 修改三：最终 commit 复用已知 contentHeight，避免滚动结束时再次全文测量

### 修改前

- `updateMarkdownItemScrollOffset(...)` 只有 `scrollOffsetY` 参数。
- 内部直接调用 `normalizedMarkdownItem(...)`，而 `normalizedMarkdownItem(...)` 会重新执行 `measuredMarkdownContentHeight(...)`。
- 这样即便 controller 在滚动热路径里已经算过一次 `contentHeight`，最终提交时也会再测一遍。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: updateMarkdownItemScrollOffset(withID:scrollOffsetY:)
// 功能说明: 修改前最终 scroll commit 仍然经过 normalizedMarkdownItem，无法复用 controller 已经算好的 contentHeight。
@discardableResult
func updateMarkdownItemScrollOffset(
    withID itemID: CanvasItemID,
    scrollOffsetY: CGFloat
) -> CanvasMarkdownItem? {
    guard let item = scene.markdownItem(withID: itemID) else {
        return nil
    }
    let updatedItem = normalizedMarkdownItem(
        item,
        scrollOffsetY: scrollOffsetY
    )
    guard abs(updatedItem.scrollOffsetY - item.scrollOffsetY) > Self.geometryComparisonEpsilon else {
        return nil
    }
    return scene.updateMarkdownItemScrollOffset(
        withID: itemID,
        scrollOffsetY: updatedItem.scrollOffsetY
    )
}
```

### 修改后

- `updateMarkdownItemScrollOffset(...)` 新增 `contentHeight: CGFloat? = nil`。
- 如果 controller 已知 `contentHeight`，session 直接用 `clampedMarkdownScrollOffsetY(...)` 做 clamp，不再重复测量。
- 这让滚动结束 commit 的开销收敛到一次纯 clamp + scene update。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: updateMarkdownItemScrollOffset(withID:scrollOffsetY:contentHeight:)
// 功能说明: 修改后 session 支持复用外部已知的 contentHeight，在 scroll commit 阶段只做 clamp 和 scene update，不再强制走全文测量。
@discardableResult
func updateMarkdownItemScrollOffset(
    withID itemID: CanvasItemID,
    scrollOffsetY: CGFloat,
    contentHeight: CGFloat? = nil
) -> CanvasMarkdownItem? {
    guard let item = scene.markdownItem(withID: itemID) else {
        return nil
    }
    let resolvedContentHeight = contentHeight ?? measuredMarkdownContentHeight(
        for: item
    )
    let resolvedScrollOffsetY = clampedMarkdownScrollOffsetY(
        proposedScrollOffsetY: scrollOffsetY,
        contentHeight: resolvedContentHeight,
        containerHeight: item.size.height
    )
    guard abs(resolvedScrollOffsetY - item.scrollOffsetY) > Self.geometryComparisonEpsilon else {
        return nil
    }
    return scene.updateMarkdownItemScrollOffset(
        withID: itemID,
        scrollOffsetY: resolvedScrollOffsetY
    )
}
```

## 修改四：关闭高频 markdown trace，并补充 transient scroll 回归测试

### 修改前

- markdown 相关 trace 默认仍是开启状态，滚动期间会持续输出 payload / measure / draw / commit 等日志。
- `CanvasMarkdownLayerTests` 只覆盖完整 update 路径，还没有锁定 transient scroll 的“不 relayout / 不 rerender”合同。

### 修改后

- 以下开关都从默认开启改成默认关闭：
  - `CanvasRenderer.isMarkdownTraceLoggingEnabled`
  - `CanvasMarkdownLayoutMeasurer.isTraceLoggingEnabled`
  - `CanvasMarkdownBitmapRenderer.isTraceLoggingEnabled`
  - `CanvasMarkdownContentLayer.isTraceLoggingEnabled`
  - `CanvasEditorSession.isMarkdownTraceLoggingEnabled`
- `CanvasMarkdownLayerTests` 新增两条回归：
  - `testTransientContentScrollOffsetMovesLayerWithoutRelayoutOrRerender()`
  - `testItemLayerTransientScrollOffsetMovesScrollbarThumb()`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: testTransientContentScrollOffsetMovesLayerWithoutRelayoutOrRerender() / testItemLayerTransientScrollOffsetMovesScrollbarThumb()
// 功能说明: 修改后测试明确锁住 transient scroll 期间不重新 layout、不重新 raster bitmap，并且 scrollbar thumb 会跟随 transient offset 同步移动。
func testTransientContentScrollOffsetMovesLayerWithoutRelayoutOrRerender() throws {
    let renderer = CanvasMarkdownBitmapRendererSpy()
    var layoutInvocationCount = 0
    let layer = CanvasMarkdownContentLayer(
        itemID: CanvasItemID(),
        bitmapRenderer: renderer,
        layoutProvider: { payload in
            layoutInvocationCount += 1
            return makeExpectedMarkdownLayout(for: payload)
        }
    )
    let payload = CanvasMarkdownRenderPayload(
        markdownSource: """
        ## Scroll

        Line 1

        Line 2

        Line 3

        Line 4
        """,
        style: CanvasTextStyle(fontSize: 18),
        logicalSize: CGSize(width: 220, height: 52),
        scrollOffsetY: 0,
        cameraZoomScale: 1
    )

    layer.update(with: payload, contentsScale: 1)
    let initialImage = try markdownContentImage(from: layer)
    let resolvedScrollOffsetY = try XCTUnwrap(
        layer.applyTransientScrollOffset(
            10_000,
            logicalSize: payload.logicalSize
        )
    )
    let imageAfterTransientScroll = try markdownContentImage(from: layer)

    XCTAssertEqual(layoutInvocationCount, 1)
    XCTAssertEqual(renderer.rasterScales, [1])
    XCTAssertTrue(initialImage === imageAfterTransientScroll)
    XCTAssertEqual(layer.position.y, -resolvedScrollOffsetY, accuracy: 0.0001)
}

func testItemLayerTransientScrollOffsetMovesScrollbarThumb() {
    let itemID = CanvasItemID()
    let layer = CanvasMarkdownItemLayer(itemID: itemID)
    // ... 其余 setup 省略 ...
    let initialThumbFrame = layer.scrollbarThumbLayer.frame
    let resolvedScrollOffsetY = layer.updateTransientScrollOffset(24)

    XCTAssertFalse(layer.scrollbarTrackLayer.isHidden)
    XCTAssertFalse(layer.scrollbarThumbLayer.isHidden)
    XCTAssertNotNil(resolvedScrollOffsetY)
    XCTAssertGreaterThan(
        layer.scrollbarThumbLayer.frame.minY,
        initialThumbFrame.minY
    )
}
```

## 验证结果

- 定向测试已通过：
  - `CanvasMarkdownLayerTests`
  - `CanvasMarkdownContractTests`
- iOS 定向构建已通过：
  - `xcodebuild build -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS'`

## 结果判断

- 这次修改的重点不是改滚动灵敏度，而是改滚动路径本身：把高频手势阶段从文档态更新链路中剥离出来，变成当前 markdown layer 的 transient 可视更新。
- 从当前实现看，`scrollOffsetY` 的持久化、history、autosave 语义仍然保留，只是提交时机从“每帧”收敛成“滚动结束或 debounce 到期后一次性提交”。
- 当前计划文件里定义的 5 个阶段都已经覆盖到本次 changes 中；尚未继续外扩到 `macOS` 对称路径。
