# 20260520_093322_markdown_bitmap_phase5_resize_parity_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 5。
  - 本阶段目标是统一 markdown resize 的最终提交语义，并把 thumbnail 路径收口到与主画布一致的 world-space semantic layout + bitmap renderer 语义。
  - 本次实际改动包括：给 `CanvasEditorSession` 增加 markdown resize 的最终提交收口 helper；让 `CanvasSelectionTransformSnapshot` 暴露 selection 内 markdown item 的原始 layout width；在 `iOSViewController` / `macOSViewController` 的 resize 结束链路中先执行 markdown finalize commit 再提交历史；让 `BoardThumbnailRenderer` 改回基于 world-space width 做 markdown layout；补充阶段 5 自动化回归。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 5 相关变更为 `7` 个已跟踪修改文件。
  - `git diff --stat` 显示当前阶段 5 相关变化为：`7 files changed, 388 insertions(+), 8 deletions(-)`。
  - 本阶段没有新增未跟踪代码文件；新增文件只有本记录自身。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
```

```bash
# 命令: git diff --stat -- <阶段5相关文件>
.../Canvas/Editing/CanvasEditorSession.swift       | 163 +++++++++++++++++++++
.../Editing/CanvasSelectionTransformState.swift    |   9 ++
.../Shared/BoardList/BoardThumbnailRenderer.swift  |  26 +++-
.../Platform/iOS/iOSViewController.swift           |  35 +++++
.../Platform/macOS/macOSViewController.swift       |  33 +++++
.../CanvasCommandPolicyParityTests.swift           |  59 ++++++++
.../MarkdownPreviewParityTests.swift               |  71 +++++++++
7 files changed, 388 insertions(+), 8 deletions(-)
```

## 当前 changes 摘要

- markdown resize 现在区分“拖拽中的几何预览”和“手势结束后的正式提交”：只有当容器宽度真的变化时，才按新宽度重新测量 markdown 内容高度，并把新的 `size.height` 写回模型。
- markdown editor 提交链没有被改成新语义分支，仍然继续复用 `updateMarkdownItemContent(...)` 的内容更新语义；阶段 5 只新增 resize 结束时的 finalize 收口逻辑。
- thumbnail 路径不再在 preview-space 重新决定 markdown 的语义换行，而是复用主画布的 world-space layout width，再把 preview scale 仅用于最终 bitmap 栅格化密度。
- minimap / preview seed / selection accessory 没有引入正文绘制复杂度；本次 parity 收口仍然只针对 resize 提交和 thumbnail 渲染路径。

## 修改一：给 markdown resize 增加最终提交收口

### 1.1 修改前

- `CanvasEditorSession` 只有 `updateMarkdownItemContent(...)` 这条“编辑器提交 / 样式变更”的 markdown 更新语义。
- resize 过程中如果 controller 已经把临时 `size` 写进 scene，那么手势结束时并没有专门的“按新宽度重算高度”收口逻辑。
- 这意味着 markdown 在 resize 后的 `height` 会停留在拖拽预览值，而不是新宽度下重新测量出的内容高度。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: updateMarkdownItemContent(withID:markdownSource:style:)
// 功能说明: 修改前只收口“内容/样式提交”语义；layoutWidth 取当前 item.size.width，但 resize 手势结束没有单独的 finalize reflow 入口。
@discardableResult
func updateMarkdownItemContent(
    withID itemID: CanvasItemID,
    markdownSource: String,
    style: CanvasTextStyle
) -> CanvasMarkdownItem? {
    guard let item = scene.markdownItem(withID: itemID) else {
        return nil
    }

    let size = measuredMarkdownItemSize(
        for: markdownSource,
        style: style,
        layoutWidth: item.size.width
    )
    return scene.updateMarkdownItem(
        withID: itemID,
        markdownSource: markdownSource,
        style: style,
        size: size
    )
}
```

### 1.2 修改后

- 新增 `geometryComparisonEpsilon`，避免宽度或高度只因浮点误差就触发 finalize 提交。
- 新增：
  - `finalizeMarkdownResizeCommit(withID:handleRole:originalLayoutWidth:)`
  - `finalizeMarkdownResizeCommits(handleRole:originalLayoutWidthsByItemID:)`
  - `markdownLayoutWidthChanged(for:originalLayoutWidth:)`
  - `resolvedMarkdownResizeCommittedItem(from:handleRole:)`
- 收口逻辑现在会：
  1. 对比 resize 前后的 world-space layout width；
  2. 只有宽度真的变化时，才调用 `measuredMarkdownItemSize(...)` 重新计算 height；
  3. 按 handle 的 fixed opposite corner 重新计算 committed local frame；
  4. 同步更新 `center` 和 `size`，保证最终提交仍保持 resize 的固定对角语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: finalizeMarkdownResizeCommit(withID:handleRole:originalLayoutWidth:) / finalizeMarkdownResizeCommits(handleRole:originalLayoutWidthsByItemID:)
// 功能说明: 修改后把 markdown resize 的正式提交收口到 EditorSession，统一在宽度变化时重算内容高度并写回 scene。
private static let geometryComparisonEpsilon: CGFloat = 0.0001

@discardableResult
func finalizeMarkdownResizeCommit(
    withID itemID: CanvasItemID,
    handleRole: CanvasSelectionHandleRole,
    originalLayoutWidth: CGFloat
) -> CanvasMarkdownItem? {
    guard
        let item = scene.markdownItem(withID: itemID),
        markdownLayoutWidthChanged(
            for: item,
            originalLayoutWidth: originalLayoutWidth
        ),
        let updatedItem = resolvedMarkdownResizeCommittedItem(
            from: item,
            handleRole: handleRole
        ),
        let appliedItem = scene.applyBoardItems([.markdown(updatedItem)])?
            .first?
            .markdownItem
    else {
        return nil
    }

    expandBoardIfNeeded(toInclude: appliedItem.worldBounds)
    return appliedItem
}

@discardableResult
func finalizeMarkdownResizeCommits(
    handleRole: CanvasSelectionHandleRole,
    originalLayoutWidthsByItemID: [CanvasItemID: CGFloat]
) -> [CanvasMarkdownItem] {
    let updatedBoardItems: [CanvasBoardItem] = originalLayoutWidthsByItemID.compactMap { entry in
        let itemID = entry.key
        let originalLayoutWidth = entry.value
        guard
            let item = scene.markdownItem(withID: itemID),
            markdownLayoutWidthChanged(
                for: item,
                originalLayoutWidth: originalLayoutWidth
            )
        else {
            return nil
        }

        return resolvedMarkdownResizeCommittedItem(
            from: item,
            handleRole: handleRole
        ).map(CanvasBoardItem.markdown)
    }

    guard
        updatedBoardItems.isEmpty == false,
        let appliedItems = scene.applyBoardItems(updatedBoardItems)
    else {
        return []
    }

    let updatedMarkdownItems = appliedItems.compactMap { $0.markdownItem }
    for item in updatedMarkdownItems {
        expandBoardIfNeeded(toInclude: item.worldBounds)
    }
    return updatedMarkdownItems
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: resolvedMarkdownResizeCommittedItem(from:handleRole:) / markdownFixedOppositeResizeLocalCorner(for:in:) / markdownResizeLocalFrame(for:withFixedOppositeCorner:size:)
// 功能说明: 修改后正式提交不是沿用拖拽中的临时高度，而是按新宽度重新测量内容高度，并基于 fixed corner 重算 committed center。
private func resolvedMarkdownResizeCommittedItem(
    from item: CanvasMarkdownItem,
    handleRole: CanvasSelectionHandleRole
) -> CanvasMarkdownItem? {
    let committedSize = measuredMarkdownItemSize(
        for: item.markdownSource,
        style: item.style,
        layoutWidth: item.size.width
    )
    guard
        abs(committedSize.width - item.size.width) > Self.geometryComparisonEpsilon ||
        abs(committedSize.height - item.size.height) > Self.geometryComparisonEpsilon
    else {
        return nil
    }

    let currentLocalFrame = item.localFrame.standardized
    let fixedOppositeLocalCorner = markdownFixedOppositeResizeLocalCorner(
        for: handleRole,
        in: currentLocalFrame
    )
    let committedLocalFrame = markdownResizeLocalFrame(
        for: handleRole,
        withFixedOppositeCorner: fixedOppositeLocalCorner,
        size: committedSize
    )

    var updatedItem = item
    updatedItem.center = item.worldPoint(
        fromLocal: CGPoint(
            x: committedLocalFrame.midX,
            y: committedLocalFrame.midY
        )
    )
    updatedItem.size = committedSize
    return updatedItem
}
```

## 修改二：为 selection resize 补原始 markdown layout width，并在双端控制器接入 finalize 提交

### 2.1 修改前

- `CanvasSelectionTransformSnapshot` 只有 `memberItemIDs` 等几何信息，没有暴露 selection 内 markdown item 的原始 layout width。
- `iOSViewController` / `macOSViewController` 在 resize 结束时只会直接提交 history transaction，不会先对 markdown 做 finalize reflow。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名: memberItemIDs
// 功能说明: 修改前 snapshot 只暴露 selection 的成员 ID，group resize 结束时拿不到 markdown item 的 resize 前 layout width。
var memberItemIDs: [CanvasItemID] {
    memberGeometries.map(\.itemID)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: handlePrimaryPointerUp()
// 功能说明: 修改前 resize 结束直接提交 history transaction；如果 scene 中已经写入临时 markdown 尺寸，不会再补一次正式 reflow 收口。
case .resizingSelectedItem:
    commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
case .resizingSelection:
    commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")
```

### 2.2 修改后

- `CanvasSelectionTransformSnapshot` 新增 `markdownLayoutWidthsByItemID()`，只收集 selection 内 markdown item 的原始 width，供 group resize commit 使用。
- `iOSViewController` 和 `macOSViewController` 的 resize 结束链路都改成：
  1. 先调用 `finalizeMarkdownResizeCommitIfNeeded(...)`；
  2. 再调用 `commitPendingPointerHistoryTransaction(...)`。
- 这样 pointer drag 期间仍然保留现有预览，但最终落盘前会统一回到 markdown 的正式提交语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: markdownLayoutWidthsByItemID()
// 功能说明: 修改后 snapshot 会把 selection 内 markdown item 的原始 world-space layout width 提取出来，供 group resize 的 finalize commit 使用。
func markdownLayoutWidthsByItemID() -> [CanvasItemID: CGFloat] {
    memberItemIDs.reduce(into: [:]) { partialResult, itemID in
        guard let markdownItem = sourceItemsByID[itemID]?.markdownItem else {
            return
        }
        partialResult[itemID] = markdownItem.size.width
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp() / finalizeMarkdownResizeCommitIfNeeded(for:)
// 功能说明: 修改后 iOS 在 resize 结束前先补 markdown finalize reflow，再提交 history，从而把拖拽预览和正式提交分离。
case .resizingSelectedItem:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
case .resizingSelection:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")

private func finalizeMarkdownResizeCommitIfNeeded(
    for pointerDragState: PointerDragState
) {
    let updatedItems: [CanvasMarkdownItem]
    switch pointerDragState {
    case let .resizingSelectedItem(resizeState):
        updatedItems = editorSession.finalizeMarkdownResizeCommit(
            withID: resizeState.itemID,
            handleRole: resizeState.handleRole,
            originalLayoutWidth: resizeState.initialLocalFrame.width
        ).map { [$0] } ?? []
    case let .resizingSelection(resizeState):
        updatedItems = editorSession.finalizeMarkdownResizeCommits(
            handleRole: resizeState.handleRole,
            originalLayoutWidthsByItemID: resizeState.snapshot
                .markdownLayoutWidthsByItemID()
        )
    case .idle, .pressed, .croppingSelectedItem, .movingCropFrame,
         .rotatingSelectedItem, .rotatingSelection, .draggingSelectedItem,
         .draggingSelection, .draggingCanvas:
        return
    }

    guard updatedItems.isEmpty == false else {
        return
    }
    requestCanvasRefresh(reason: "finalize markdown resize commit")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerUp() / finalizeMarkdownResizeCommitIfNeeded(for:)
// 功能说明: 修改后 macOS 与 iOS 保持同构接入，结束 resize 时同样先执行 markdown finalize commit，再提交 history。
case .resizingSelectedItem:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
case .resizingSelection:
    finalizeMarkdownResizeCommitIfNeeded(for: pointerDragState)
    commitPendingPointerHistoryTransaction(autosaveReason: "resize selection")

private func finalizeMarkdownResizeCommitIfNeeded(
    for pointerDragState: PointerDragState
) {
    let updatedItems: [CanvasMarkdownItem]
    switch pointerDragState {
    case let .resizingSelectedItem(resizeState):
        updatedItems = editorSession.finalizeMarkdownResizeCommit(
            withID: resizeState.itemID,
            handleRole: resizeState.handleRole,
            originalLayoutWidth: resizeState.initialLocalFrame.width
        ).map { [$0] } ?? []
    case let .resizingSelection(resizeState):
        updatedItems = editorSession.finalizeMarkdownResizeCommits(
            handleRole: resizeState.handleRole,
            originalLayoutWidthsByItemID: resizeState.snapshot
                .markdownLayoutWidthsByItemID()
        )
    case .idle, .pressed, .croppingSelectedItem, .movingCropFrame,
         .rotatingSelectedItem, .rotatingSelection, .draggingSelectedItem,
         .draggingSelection, .draggingCanvas:
        return
    }

    guard updatedItems.isEmpty == false else {
        return
    }
    refreshCanvas(reason: "finalize markdown resize commit")
}
```

## 修改三：thumbnail 改为和主画布共用 world-space markdown layout 语义

### 3.1 修改前

- `BoardThumbnailRenderer` 中 markdown 的 `layout width` 取的是 `mappedVisibleSize.width`。
- 这意味着 thumbnail 会在 preview-space 宽度下重新换行，而不是复用 markdown item 持久化下来的 world-space layout width。
- 同时 `rasterScale` 固定为 `1`，thumbnail 和主画布的 semantic layout / bitmap density 语义被混在一起。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawMarkdownItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改前 thumbnail 直接用 mappedVisibleSize.width 参与 markdown layout，导致 preview-space reflow 和主画布 world-space 语义不一致。
let layout = CanvasMarkdownLayoutMeasurer.layout(
    markdownSource: itemRecord.markdownSource,
    style: itemRecord.style.canvasTextStyle,
    maxLayoutWidth: mappedVisibleSize.width,
    scale: geometry.scale,
    includeCompatibilityCodeBlockBackgrounds: false
)
let imageRect = CGRect(
    x: textRect.minX,
    y: textRect.minY,
    width: layout.contentSize.width,
    height: layout.contentSize.height
).standardized
let bitmapImage = markdownBitmapRenderer.render(
    layout: layout,
    rasterScale: 1
)
```

### 3.2 修改后

- `BoardThumbnailRenderer` 现在把 `markdownBitmapRenderer` 依赖也切到 `CanvasMarkdownBitmapRendering` 协议，thumbnail tests 可以直接注入 spy renderer。
- semantic layout 改回 `maxLayoutWidth: visibleSize.width` 且 `scale: 1`，与主画布 `logical width` 语义一致。
- preview scale 只作用在两处：
  - `imageRect` 的最终映射尺寸；
  - `bitmapRenderer.render(... rasterScale:)` 的位图密度。
- 如果 shared bitmap renderer 不出图，fallback 仍保留原来的 attributed text 绘制兜底。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: BoardThumbnailRenderer.init(...) / drawMarkdownItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改后 thumbnail 复用主画布的 world-space markdown semantic layout，preview scale 只影响最终 bitmap 清晰度，不再影响换行语义。
private let markdownBitmapRenderer: any CanvasMarkdownBitmapRendering

init(
    geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder(),
    mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
    markdownBitmapRenderer: any CanvasMarkdownBitmapRendering = CanvasMarkdownBitmapRenderer()
) {
    self.geometryPreviewBuilder = geometryPreviewBuilder
    self.mediaPosterImageResolver = mediaPosterImageResolver
    self.markdownBitmapRenderer = markdownBitmapRenderer
}

let layout = CanvasMarkdownLayoutMeasurer.layout(
    markdownSource: itemRecord.markdownSource,
    style: itemRecord.style.canvasTextStyle,
    maxLayoutWidth: visibleSize.width,
    scale: 1,
    includeCompatibilityCodeBlockBackgrounds: false
)
let imageRect = CGRect(
    x: textRect.minX,
    y: textRect.minY,
    width: layout.contentSize.width * geometry.scale,
    height: layout.contentSize.height * geometry.scale
).standardized
let bitmapImage = markdownBitmapRenderer.render(
    layout: layout,
    rasterScale: max(geometry.scale, 0.01)
)

if let bitmapImage {
    drawBitmapImage(bitmapImage, in: imageRect, context: context)
} else {
    let fallbackLayout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: itemRecord.markdownSource,
        style: itemRecord.style.canvasTextStyle,
        maxLayoutWidth: mappedVisibleSize.width,
        scale: geometry.scale,
        includeCompatibilityCodeBlockBackgrounds: false
    )
    drawAttributedText(
        fallbackLayout.attributedText,
        in: textRect,
        context: context
    )
}
```

## 修改四：补齐阶段 5 回归测试

### 4.1 修改前

- `CanvasCommandPolicyParityTests` 已有 `testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()`，但它覆盖的是编辑器提交链，不是 resize 结束后的 finalize reflow。
- `MarkdownPreviewParityTests` 只验证 thumbnail 可见性和 code block panel 可见性，没有直接断言 thumbnail 是否仍使用 world-space layout width。

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift（修改前）
// 函数名: testBoardThumbnailRendererRendersVisibleMarkdownThumbnail() / testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()
// 功能说明: 修改前 parity 测试只要求 thumbnail 可见，不会直接锁定“layout width 是否仍然来自 markdown item 的 world-space width”。
func testBoardThumbnailRendererRendersVisibleMarkdownThumbnail() throws {
    let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
    let renderer = BoardThumbnailRenderer()
    let renderedImage = try XCTUnwrap(
        renderer.renderPersistedThumbnail(
            for: runtimeState,
            maximumLongestSide: 256
        )
    )

    XCTAssertTrue(
        imageContainsVisiblePixels(renderedImage),
        "Expected markdown-only board thumbnail to contain visible pixels."
    )
}
```

### 4.2 修改后

- `CanvasCommandPolicyParityTests` 新增 `testFinalizeMarkdownResizeCommitRemeasuresHeightAndPreservesFixedCorner()`：
  - 先制造 resize 预览态；
  - 再执行 `finalizeMarkdownResizeCommit(...)`；
  - 断言最终 `height` 按新宽度重算；
  - 断言 fixed corner 世界坐标保持不变。
- `MarkdownPreviewParityTests` 新增：
  - `testBoardThumbnailRendererUsesWorldSpaceMarkdownLayoutWidth()`
  - `MarkdownPreviewBitmapRendererSpy`
- 新测试直接断言 thumbnail renderer 第一份 layout 的 `contentSize.width == markdownItem.size.width`，把阶段 5 parity 收口要求固定下来。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testFinalizeMarkdownResizeCommitRemeasuresHeightAndPreservesFixedCorner()
// 功能说明: 修改后测试锁定 resize finalize commit 的正式语义，确保 markdown 高度按新宽度重算，并保持 fixed-corner 几何不漂移。
func testFinalizeMarkdownResizeCommitRemeasuresHeightAndPreservesFixedCorner() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let originalItem = CanvasMarkdownItem(
        markdownSource: source,
        style: style,
        center: CGPoint(x: 40, y: 30),
        size: CGSize(width: 80, height: 60)
    )
    session.scene.append(originalItem)

    let provisionalItem = try XCTUnwrap(
        session.scene.resizeBoardItem(
            withID: originalItem.id,
            toCenter: CGPoint(x: 80, y: 45),
            size: CGSize(width: 160, height: 90)
        )?.markdownItem
    )

    let committedItem = try XCTUnwrap(
        session.finalizeMarkdownResizeCommit(
            withID: originalItem.id,
            handleRole: .bottomTrailing,
            originalLayoutWidth: originalItem.size.width
        )
    )
    let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: source,
        style: style,
        maxLayoutWidth: provisionalItem.size.width
    )

    XCTAssertEqual(committedItem.size.width, provisionalItem.size.width, accuracy: 0.0001)
    XCTAssertEqual(committedItem.size.height, expectedHeight, accuracy: 0.0001)
    XCTAssertEqual(committedFixedCorner.x, provisionalFixedCorner.x, accuracy: 0.0001)
    XCTAssertEqual(committedFixedCorner.y, provisionalFixedCorner.y, accuracy: 0.0001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
// 函数名: testBoardThumbnailRendererUsesWorldSpaceMarkdownLayoutWidth() / MarkdownPreviewBitmapRendererSpy.render(layout:rasterScale:)
// 功能说明: 修改后测试通过 spy renderer 直接拿到 thumbnail 实际使用的 markdown layout，确保 preview parity 绑定到 world-space width，而不是 preview-space reflow。
func testBoardThumbnailRendererUsesWorldSpaceMarkdownLayoutWidth() throws {
    let markdownItem = makeMarkdownPreviewTestItem(
        markdownSource: """
        # Heading

        This thumbnail should reuse the markdown semantic layout width from the persisted world item instead of reflowing in preview space.
        """,
        center: CGPoint(x: 220, y: 160),
        size: CGSize(width: 420, height: 240),
        zIndex: 1
    )
    let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
    let bitmapRendererSpy = MarkdownPreviewBitmapRendererSpy()
    let renderer = BoardThumbnailRenderer(
        markdownBitmapRenderer: bitmapRendererSpy
    )

    let renderedImage = try XCTUnwrap(
        renderer.renderPersistedThumbnail(
            for: runtimeState,
            maximumLongestSide: 256
        )
    )
    let renderedLayout = try XCTUnwrap(bitmapRendererSpy.layouts.first)

    XCTAssertTrue(imageContainsVisiblePixels(renderedImage))
    XCTAssertEqual(
        renderedLayout.contentSize.width,
        markdownItem.size.width,
        accuracy: 0.0001
    )
    XCTAssertGreaterThan(bitmapRendererSpy.rasterScales.first ?? 0, 0)
}

private final class MarkdownPreviewBitmapRendererSpy: CanvasMarkdownBitmapRendering {
    private(set) var layouts: [CanvasMarkdownLayoutResult] = []
    private(set) var rasterScales: [CGFloat] = []

    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        layouts.append(layout)
        rasterScales.append(rasterScale)
        return makeMarkdownPreviewBitmapRendererSpyImage()
    }
}
```

## 验证记录

- 本次编辑后已检查阶段 5 相关文件，没有新增 linter 问题。
- 第一轮 macOS 定向回归里，`CanvasEditorSession.finalizeMarkdownResizeCommits(...)` 的 `compactMap` 与 `\.markdownItem` 简写触发了 Swift 类型推断失败；随后在当前 changes 中改成了显式闭包和显式取值，构建恢复通过。
- 修正后重新执行 macOS 定向回归和 iOS simulator build，全部通过。

```bash
# 命令: xcodebuild test -scheme MyCanvas_Ver_0 -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/MarkdownPreviewParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests
Testing failed:
Generic parameter 'ElementOfResult' could not be inferred
Cannot infer key path type from context; consider explicitly specifying a root type
```

```bash
# 命令: xcodebuild test -scheme MyCanvas_Ver_0 -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/MarkdownPreviewParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests
** TEST SUCCEEDED **
Test case 'CanvasCommandPolicyParityTests.testFinalizeMarkdownResizeCommitRemeasuresHeightAndPreservesFixedCorner()' passed
Test case 'MarkdownPreviewParityTests.testBoardThumbnailRendererUsesWorldSpaceMarkdownLayoutWidth()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()' passed
Test case 'CanvasMarkdownLayerTests.testContentLayerCrossingRasterBucketRerendersWithoutRelayout()' passed
```

```bash
# 命令: xcodebuild build -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator'
** BUILD SUCCEEDED **
```

## 结论

- 阶段 5 已把 markdown resize 的“正式提交语义”从拖拽预览里独立出来：宽度变化时，最终提交会按新宽度稳定触发 reflow，并把正确高度写回模型。
- 编辑器提交链仍然复用 `updateMarkdownItemContent(...)`；resize finalize commit 则由双端 controller 在手势结束前统一接入，阶段边界清晰。
- thumbnail 现在与主画布共用同一套 world-space markdown semantic layout + shared bitmap renderer 语义；minimap / preview seed 仍只依赖 world geometry，没有把正文绘制复杂度带回这些路径。
