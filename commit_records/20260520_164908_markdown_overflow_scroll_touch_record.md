# 20260520_164908_markdown_overflow_scroll_touch_record

## 记录范围

- 记录内容：
  - 修改一：将 markdown block 从“左右 width-only resize”扩展为“四边 handle + 可调 viewport height + overflow 内部滚动”，并把 `scrollOffsetY` 接入持久化、渲染、undo/redo、duplicate。
  - 修改二：在 iOS 上补齐“单指命中有 overflow 的 markdown 内容区时进入内部纵向滚动；否则保留原有触摸语义”的 direct-touch 交互。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
- 参考现状：
  - 本记录创建前，`git status --short` 显示当前工作区共有 `19` 个已跟踪代码文件处于修改状态。
  - `git diff --stat -- <本次相关文件>` 显示本次两段 markdown 相关修改总计：`19 files changed, 865 insertions(+), 164 deletions(-)`。
  - 本记录不包含任何 git 提交行为。

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_markdown_overflow_scroll_touch_record"
# 功能说明: 使用系统 date 命令生成本记录文件名的时间戳前缀。
20260520_164908_markdown_overflow_scroll_touch_record
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录创建本记录前的当前工作区状态；以下 19 个文件都属于本次两段 markdown 相关修改的现状。
 M MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
 M MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- <本次 19 个相关文件>
# 功能说明: 统计这次“overflow scroll + scrollOffsetY 持久化 + iOS 单指内部滚动”真实改动量，不直接贴原始 diff。
 MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift   |   6 +
 .../Canvas/Core/CanvasRenderSnapshot.swift         |  34 +++-
 MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    |  12 +-
 MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift       |  18 +-
 .../Canvas/Editing/CanvasEditorSession.swift       | 155 ++++++++++++---
 .../Editing/CanvasSelectionTransformState.swift    |  69 ++++++-
 MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift  |   1 +
 .../Canvas/Storage/BoardDocumentMapper.swift       |   4 +-
 .../Rendering/CanvasMarkdownContentLayer.swift     |  27 ++-
 .../iOS/Canvas/iOSCanvasViewportView.swift         |  26 ++-
 .../Platform/iOS/iOSViewController.swift           | 209 ++++++++++++++++----
 .../macOS/Canvas/macOSCanvasViewportView.swift     |  26 ++-
 .../Platform/macOS/macOSViewController.swift       | 213 +++++++++++++++++----
 .../BoardSelectionStateMigrationTests.swift        |   6 +-
 .../CanvasCommandPolicyParityTests.swift           |  46 ++---
 .../CanvasEditorSessionAlignmentOverlayTests.swift |   4 +-
 .../CanvasMarkdownContractTests.swift              |  54 +++++-
 MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift |  51 +++++
 .../CanvasSelectionTransformStateTests.swift       |  68 ++++++-
 19 files changed, 865 insertions(+), 164 deletions(-)
```

## 当前 changes 摘要

- markdown 文档模型从“只存容器矩形”升级为“容器矩形 + `scrollOffsetY`”，所以滚动位置不再只是 layer 临时态。
- markdown selection handle 从“左右边”扩展为“四边中点”，并引入 `heightOnly` 语义，允许单独调整 viewport height。
- markdown 渲染从“全文 bitmap + 容器裁切但永远停在顶部”改为“全文 bitmap + `scrollOffsetY` 偏移 + 容器裁切”。
- markdown 内容/样式更新不再强行覆盖 viewport height，而是保留当前高度，只对 `scrollOffsetY` 做 clamp。
- iOS direct-touch 不再把所有 markdown body 拖动都当作“移动 item / 拖动画布”；命中有 overflow 的 markdown 且纵向拖动时，会进入 block 内部滚动状态。

## 修改一：markdown 四边 handle + overflow scroll + `scrollOffsetY` 持久化

### 1.1 修改前

- 上一个阶段的 markdown resize 仍然是“只调宽度”的合同：handle 只有左右边，`top / bottom` 不属于 markdown selection handle。
- markdown 模型和存储层没有 `scrollOffsetY`，所以即使容器高度小于内容高度，滚动位置也不能保存。
- render payload 不携带滚动偏移，`CanvasMarkdownContentLayer` 只知道全文布局尺寸，不知道该把内容向上偏移多少。
- 内容编辑、字体调整、width-only resize 的最终提交都会把 `size.height` 重新测回内容高度，viewport height 不是独立语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前摘要）
// 函数名/类型: CanvasMarkdownItem / matchesDocumentState(_:)
// 功能说明: 修改前 markdown 只持久化文本、样式和容器几何，没有 scrollOffsetY，history 比较也不关心滚动位置。
struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}

func matchesDocumentState(_ other: CanvasMarkdownItem) -> Bool {
    id == other.id &&
        markdownSource == other.markdownSource &&
        style == other.style &&
        center == other.center &&
        size == other.size &&
        zIndex == other.zIndex &&
        rotationRadians == other.rotationRadians
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前摘要）
// 函数名/类型: CanvasMarkdownRenderPayload / CanvasSelectionHandleRole
// 功能说明: 修改前 payload 没有 scrollOffsetY；markdown 的 selection handle 仍然只有左右边，没有 top / bottom。
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let logicalSize: CGSize
    let cameraZoomScale: CGFloat
}

enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case leading
    case trailing
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前摘要）
// 函数名/类型: makeWidthOnlyEditHandles(for:) / selectionEditHandles(...)
// 功能说明: 修改前单选 markdown 和“全 markdown 多选”都只产出 leading / trailing 两个 handle。
private func makeWidthOnlyEditHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        roles: [
            .leading,
            .trailing
        ]
    )
}

private func selectionEditHandles(
    forSingleSelectedItem item: CanvasBoardItem,
    screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    switch item.kind {
    case .text:
        return []
    case .markdown:
        return makeWidthOnlyEditHandles(for: screenQuad)
    case .image, .handDrawing:
        return makeCornerEditHandles(for: screenQuad)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift（修改前摘要）
// 函数名/类型: update(with:contentsScale:)
// 功能说明: 修改前内容层只更新全文 layout 和 bitmap，没有根据滚动位置去偏移内容。
let layout = resolvedLayout(
    for: markdownPayload,
    layoutKey: layoutKey
)
applyLayoutGeometry(layout)

let rasterScaleBucket = resolvedRasterScaleBucket(
    markdownPayload: markdownPayload,
    contentsScale: contentsScale
)
logLayoutMismatchIfNeeded(
    markdownPayload: markdownPayload,
    layout: layout,
    contentsScale: contentsScale,
    rasterScaleBucket: rasterScaleBucket
)
applyBitmapIfNeeded(
    for: layout,
    layoutKey: layoutKey,
    rasterScaleBucket: rasterScaleBucket
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前摘要）
// 函数名/类型: updateMarkdownItemContent(withID:markdownSource:style:) / resolvedMarkdownResizeCommittedItem(from:handleRole:)
// 功能说明: 修改前内容提交和 resize finalize 都会把 height 重新测回内容高度，viewport height 不能独立存在。
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

- `CanvasMarkdownItem`、`BoardMarkdownItemRecord`、`BoardDocumentMapper`、`CanvasScene` 现在完整携带 `scrollOffsetY`，并把它接入 document state 比较。
- `CanvasMarkdownRenderPayload` 新增 `scrollOffsetY`；selection handle 新增 `top / bottom`，renderer 对 markdown 改成四边中点输出。
- `CanvasMarkdownContentLayer` 新增 `applyScrollOffset(...)`，把文档态滚动位置 clamp 后映射为 `contentLayer.position.y`。
- `CanvasSelectionTransformState` 新增 `heightOnly`，宽高 resize 语义拆开；`CanvasEditorSession.normalizedMarkdownItem(...)` 统一负责 clamp `scrollOffsetY`。
- iOS/macOS viewport 现在会把 `top / bottom` 画成水平 edge handle，而不是继续沿用方形角点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 函数名/类型: CanvasMarkdownItem / init(...) / matchesDocumentState(_:)
// 功能说明: 修改后 markdown 模型显式携带 scrollOffsetY，并把它纳入持久化比较合同。
struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    var size: CGSize
    // Scroll is stored in logical markdown coordinates so overflow presentation
    // survives save/load, undo/redo, and duplication.
    var scrollOffsetY: CGFloat
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    init(
        id: CanvasItemID = UUID(),
        markdownSource: String,
        style: CanvasTextStyle = .default,
        center: CGPoint,
        size: CGSize,
        scrollOffsetY: CGFloat = 0,
        zIndex: CGFloat = 0,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.markdownSource = markdownSource
        self.style = style
        self.center = center
        self.size = size
        self.scrollOffsetY = scrollOffsetY
        self.zIndex = zIndex
        self.rotationRadians = rotationRadians
    }
}

func matchesDocumentState(_ other: CanvasMarkdownItem) -> Bool {
    id == other.id &&
        markdownSource == other.markdownSource &&
        style == other.style &&
        center == other.center &&
        size == other.size &&
        scrollOffsetY == other.scrollOffsetY &&
        zIndex == other.zIndex &&
        rotationRadians == other.rotationRadians
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名/类型: BoardMarkdownItemRecord
// 功能说明: 修改后文档记录新增可选 scrollOffsetY；旧文档缺字段时仍可按 0 解码。
struct BoardMarkdownItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var markdownSource: String
    var style: BoardTextStyleRecord
    var rotationRadians: Double?
    var scrollOffsetY: Double? = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名/类型: makeMarkdownItem(from:) / makeMarkdownRecord(from:)
// 功能说明: 修改后 mapper 双向搬运 scrollOffsetY，让 save/load、import/export、undo snapshot 使用同一份文档字段。
private static func makeMarkdownItem(
    from markdownRecord: BoardMarkdownItemRecord
) -> CanvasMarkdownItem {
    CanvasMarkdownItem(
        id: markdownRecord.id,
        markdownSource: markdownRecord.markdownSource,
        style: markdownRecord.style.canvasTextStyle,
        center: markdownRecord.center.cgPoint,
        size: markdownRecord.size.cgSize,
        scrollOffsetY: CGFloat(markdownRecord.scrollOffsetY ?? 0),
        zIndex: CGFloat(markdownRecord.zIndex),
        rotationRadians: CGFloat(markdownRecord.rotationRadians ?? 0)
    )
}

private static func makeMarkdownRecord(
    from item: CanvasMarkdownItem
) -> BoardMarkdownItemRecord {
    BoardMarkdownItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        markdownSource: item.markdownSource,
        style: BoardTextStyleRecord(item.style),
        rotationRadians: Double(item.rotationRadians),
        scrollOffsetY: Double(item.scrollOffsetY)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型: CanvasMarkdownRenderPayload / CanvasSelectionHandleRole
// 功能说明: 修改后 payload 携带 scrollOffsetY；selection handle 角色补齐 top / bottom，为 height-only resize 提供入口。
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let logicalSize: CGSize
    let scrollOffsetY: CGFloat
    let cameraZoomScale: CGFloat
}

enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomLeading
    case bottomTrailing
    case bottom
    case leading
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名/类型: makeMarkdownRenderItem(...) / makeMarkdownEdgeEditHandles(for:) / selectionEditHandles(...)
// 功能说明: 修改后 markdown render payload 会把 scrollOffsetY 送到渲染层，同时选中时产出四边 handle。
payload: .markdown(
    CanvasMarkdownRenderPayload(
        markdownSource: effectiveMarkdownItem.markdownSource,
        style: effectiveMarkdownItem.style,
        logicalSize: effectiveMarkdownItem.size,
        scrollOffsetY: effectiveMarkdownItem.scrollOffsetY,
        cameraZoomScale: camera.zoomScale
    )
)

private func makeMarkdownEdgeEditHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        roles: [
            .top,
            .trailing,
            .bottom,
            .leading,
        ]
    )
}

private func selectionEditHandles(
    forSingleSelectedItem item: CanvasBoardItem,
    screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    switch item.kind {
    case .text:
        return []
    case .markdown:
        return makeMarkdownEdgeEditHandles(for: screenQuad)
    case .image, .handDrawing:
        return makeCornerEditHandles(for: screenQuad)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名/类型: update(with:contentsScale:) / applyScrollOffset(markdownPayload:layout:)
// 功能说明: 修改后内容层会对 scrollOffsetY 做 clamp，并把逻辑滚动位置映射成 contentLayer 的 Y 偏移。
let layout = resolvedLayout(
    for: markdownPayload,
    layoutKey: layoutKey
)
applyLayoutGeometry(layout)
applyScrollOffset(markdownPayload: markdownPayload, layout: layout)

private func applyScrollOffset(
    markdownPayload: CanvasMarkdownRenderPayload,
    layout: CanvasMarkdownLayoutResult
) {
    let maxScrollOffsetY = max(
        layout.contentSize.height - markdownPayload.logicalSize.height,
        0
    )
    let resolvedScrollOffsetY = min(
        max(markdownPayload.scrollOffsetY, 0),
        maxScrollOffsetY
    )
    guard lastAppliedScrollOffsetY != resolvedScrollOffsetY else {
        return
    }
    position = CGPoint(x: 0, y: -resolvedScrollOffsetY)
    lastAppliedScrollOffsetY = resolvedScrollOffsetY
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名/类型: resizedMarkdownItem(_:scaledCenter:proposedSize:scalingMode:) / resizeScalingMode(...) / resolvedScale(...)
// 功能说明: 修改后 markdown resize 把“改宽”和“改高”拆成 widthOnly / heightOnly；resize 完成后统一 clamp scrollOffsetY。
private func resizedMarkdownItem(
    _ item: CanvasMarkdownItem,
    scaledCenter: CGPoint,
    proposedSize: CGSize,
    scalingMode: CanvasSelectionResizeScalingMode
) -> CanvasMarkdownItem {
    let resolvedSize = CGSize(
        width: max(proposedSize.width, 1),
        height: max(proposedSize.height, 1)
    )
    let contentHeight = markdownContentHeight(
        for: item,
        layoutWidth: resolvedSize.width
    )
    let resolvedScrollOffsetY = clampedMarkdownScrollOffsetY(
        proposedScrollOffsetY: item.scrollOffsetY,
        contentHeight: contentHeight,
        containerHeight: resolvedSize.height
    )
    return CanvasMarkdownItem(
        id: item.id,
        markdownSource: item.markdownSource,
        style: item.style,
        center: scaledCenter,
        size: resolvedSize,
        scrollOffsetY: resolvedScrollOffsetY,
        zIndex: item.zIndex,
        rotationRadians: item.rotationRadians
    )
}

private func resizeScalingMode(
    for itemID: CanvasItemID,
    handleRole: CanvasSelectionHandleRole
) -> CanvasSelectionResizeScalingMode {
    if handleRole.isWidthOnly {
        return .widthOnly
    }
    if handleRole.isHeightOnly, sourceItemsByID[itemID]?.kind == .markdown {
        return .heightOnly
    }
    return sourceItemsByID[itemID]?.kind == .markdown ? .nonUniform : .uniform
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型: normalizedMarkdownItem(_:markdownSource:style:center:size:scrollOffsetY:)
// 功能说明: 修改后内容提交、字体变化、resize finalize、滚动更新都共用同一套 normalize + clamp 逻辑，不再散落多份高度/滚动计算。
func normalizedMarkdownItem(
    _ item: CanvasMarkdownItem,
    markdownSource: String? = nil,
    style: CanvasTextStyle? = nil,
    center: CGPoint? = nil,
    size: CGSize? = nil,
    scrollOffsetY: CGFloat? = nil
) -> CanvasMarkdownItem {
    var normalizedItem = item
    if let markdownSource { normalizedItem.markdownSource = markdownSource }
    if let style { normalizedItem.style = style }
    if let center { normalizedItem.center = center }
    if let size {
        normalizedItem.size = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }
    if let scrollOffsetY {
        normalizedItem.scrollOffsetY = scrollOffsetY
    }

    let contentHeight = measuredMarkdownContentHeight(for: normalizedItem)
    normalizedItem.scrollOffsetY = clampedMarkdownScrollOffsetY(
        proposedScrollOffsetY: normalizedItem.scrollOffsetY,
        contentHeight: contentHeight,
        containerHeight: normalizedItem.size.height
    )
    return normalizedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型: selectionHandlePath(for:centeredAt:rotationRadians:) / edgeHandlePath(...)
// 功能说明: 修改后 top / bottom 也会绘制成水平 edge handle，leading / trailing 保持垂直 edge handle。
private static func selectionHandlePath(
    for role: CanvasSelectionHandleRole,
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    switch role {
    case .leading, .trailing:
        return edgeHandlePath(
            centeredAt: center,
            length: selectionEdgeHandleLength,
            thickness: selectionEdgeHandleThickness,
            rotationRadians: rotationRadians,
            isHorizontal: false
        )
    case .top, .bottom:
        return edgeHandlePath(
            centeredAt: center,
            length: selectionEdgeHandleLength,
            thickness: selectionEdgeHandleThickness,
            rotationRadians: rotationRadians,
            isHorizontal: true
        )
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
        break
    }
    return squareHandlePath(
        centeredAt: center,
        size: selectionHandleSize,
        rotationRadians: rotationRadians
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名/类型: testUpdateMarkdownItemContentKeepsExplicitViewportHeightAndClampsScrollOffset() / testUpdateMarkdownItemScrollOffsetClampsIntoOverflowRange()
// 功能说明: 修改后测试合同从“自动改高度”切成“保留 viewport height，只 clamp scrollOffsetY”。
func testUpdateMarkdownItemContentKeepsExplicitViewportHeightAndClampsScrollOffset() throws {
    let originalItem = CanvasMarkdownItem(
        markdownSource: "Seed",
        style: CanvasTextStyle(fontSize: 18),
        center: CGPoint(x: 40, y: 24),
        size: CGSize(width: 210, height: 48),
        scrollOffsetY: 30,
        zIndex: 1,
        rotationRadians: .pi / 9
    )
    // ... 省略 session 构造 ...
    XCTAssertEqual(updatedItem.size.width, originalItem.size.width)
    XCTAssertEqual(updatedItem.size.height, originalItem.size.height, accuracy: 0.0001)
    XCTAssertEqual(updatedItem.scrollOffsetY, expectedScrollOffset, accuracy: 0.0001)
}

func testUpdateMarkdownItemScrollOffsetClampsIntoOverflowRange() throws {
    let updatedItem = try XCTUnwrap(
        session.updateMarkdownItemScrollOffset(
            withID: item.id,
            scrollOffsetY: 10_000
        )
    )
    XCTAssertEqual(
        updatedItem.scrollOffsetY,
        max(expectedContentHeight - item.size.height, 0),
        accuracy: 0.0001
    )
}
```

## 修改二：iOS 单指命中 overflow markdown 时进入内部滚动

### 2.1 修改前

- iOS 之前只给 `indirect pan`（触控板/滚轮）接了 markdown 内部滚动；direct touch 仍然全走原来的 pointer 状态机。
- `PointerDragState` 里没有“markdown 内部滚动”状态，单指拖动一旦超过激活阈值，就直接进入 rotate / crop / resize / move item / drag canvas 之一。
- 也就是说，在 iPhone/iPad 触摸下，命中 overflow markdown 内容区后，仍然更容易触发“移动 item”或“拖动画布”，没有块内滚动分流。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前摘要）
// 函数名/类型: PointerDragState / handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前 direct-touch 路径没有 scrollingMarkdownItem 这样的专用状态。
private enum PointerDragState {
    case idle
    case pressed(...)
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case rotatingSelection(CanvasSelectionRotateState)
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case resizingSelectedItem(PointerResizeState)
    case resizingSelection(CanvasSelectionResizeState)
    case draggingCanvas
}

switch pressContext.targetKind {
case .selectionTranslationArea, .selectedItemBody:
    // 命中选中项内容区后，仍然直接进入移动 item / 移动 selection 语义。
case .unselectedItemBody, .blank:
    // 命中空白或未选中项后，直接进入拖动画布语义。
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前摘要）
// 函数名/类型: handleIndirectPan(_:at:) / consumeMarkdownScrollIfNeeded(for:at:)
// 功能说明: 修改前只有 indirect pan 会尝试吃掉 markdown 内部滚动，单指 direct touch 不会走到这里。
private func handleIndirectPan(
    _ translation: CGPoint,
    at viewportLocation: CGPoint
) {
    let remainingTranslation =
        consumeMarkdownScrollIfNeeded(
            for: translation,
            at: viewportLocation
        )
        ?? translation
    guard remainingTranslation != .zero else {
        return
    }

    applyCanvasPan(
        remainingTranslation,
        refreshReason: "indirect pan ..."
    )
}
```

### 2.2 修改后

- iOS controller 新增 `PointerMarkdownScrollState` 和 `PointerDragState.scrollingMarkdownItem(...)`。
- `handlePrimaryPointerMove(...)` 在 `.pressed` 阶段先做一次 markdown 内部滚动判定：
  - 命中 `selectedItemBody / unselectedItemBody`
  - 目标 item 是 markdown
  - markdown 当前确实有 overflow
  - 当前拖动是“纵向优先”
- 满足上面条件时，direct touch 会从原 pointer history 事务退出，切到 markdown 内部滚动事务；否则继续保留原来的拖拽/平移分支。
- 抬手或 cancel 时，`scrollingMarkdownItem` 会单独提交 markdown scroll history transaction，不会污染 move/resize 的历史。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型: PointerMarkdownScrollState / PointerDragState / handlePrimaryPointerMove(to:from:)
// 功能说明: 修改后 direct-touch 在 pressed 阶段先尝试切到 markdown 内部滚动状态；失败时才继续原来的 move / pan / resize / rotate 流程。
private struct PointerMarkdownScrollState {
    let itemID: CanvasItemID
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case rotatingSelection(CanvasSelectionRotateState)
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case resizingSelectedItem(PointerResizeState)
    case resizingSelection(CanvasSelectionResizeState)
    case scrollingMarkdownItem(PointerMarkdownScrollState)
    case draggingCanvas
}

case let .pressed(pressedLocation, pressContext, _):
    guard hasExceededPointerDragActivationDistance(from: pressedLocation, to: location) else {
        return
    }

    if let markdownScrollState = makeMarkdownTouchScrollStateIfNeeded(
        for: pressContext,
        pressedLocation: pressedLocation,
        currentLocation: location
    ) {
        editorSession.cancelPendingHistoryTransaction()
        beginMarkdownScrollHistoryTransactionIfNeeded()
        pointerDragState = .scrollingMarkdownItem(markdownScrollState)
        scrollMarkdownItem(
            using: markdownScrollState,
            from: pressedLocation,
            to: location
        )
        return
    }
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型: makeMarkdownTouchScrollStateIfNeeded(...) / markdownItemSupportsInternalScroll(_:) / isVerticalDominantPointerDrag(from:to:) / scrollMarkdownItem(using:from:to:)
// 功能说明: 修改后 direct-touch 只有在“命中 markdown 内容区 + 有 overflow + 纵向优先拖动”时才会进入块内滚动。
private func makeMarkdownTouchScrollStateIfNeeded(
    for pressContext: CanvasPointerPressContext,
    pressedLocation: CGPoint,
    currentLocation: CGPoint
) -> PointerMarkdownScrollState? {
    let isItemBodyTarget: Bool
    switch pressContext.targetKind {
    case .selectedItemBody, .unselectedItemBody:
        isItemBodyTarget = true
    default:
        isItemBodyTarget = false
    }
    guard
        isItemBodyTarget,
        let itemID = pressContext.targetItemID,
        let markdownItem = scene.markdownItem(withID: itemID),
        markdownItemSupportsInternalScroll(markdownItem),
        isVerticalDominantPointerDrag(from: pressedLocation, to: currentLocation)
    else {
        return nil
    }
    return PointerMarkdownScrollState(itemID: itemID)
}

private func markdownItemSupportsInternalScroll(
    _ item: CanvasMarkdownItem
) -> Bool {
    let contentHeight = editorSession.measuredMarkdownContentHeight(for: item)
    return contentHeight - item.size.height > Self.geometryComparisonEpsilon
}

private func scrollMarkdownItem(
    using scrollState: PointerMarkdownScrollState,
    from previousLocation: CGPoint,
    to currentLocation: CGPoint
) {
    let translation = CGPoint(
        x: currentLocation.x - previousLocation.x,
        y: currentLocation.y - previousLocation.y
    )
    guard translation != .zero else {
        return
    }
    _ = consumeMarkdownScrollIfNeeded(
        for: translation,
        markdownItemID: scrollState.itemID
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型: handlePrimaryPointerUp(at:modifiers:) / handlePrimaryPointerCancel() / commitMarkdownScrollHistoryTransactionIfNeeded()
// 功能说明: 修改后 markdown 内部滚动在抬手/取消时会单独提交 scroll history 事务，保持 undo/redo 语义完整。
switch pointerDragState {
case .scrollingMarkdownItem:
    commitMarkdownScrollHistoryTransactionIfNeeded()
case .draggingCanvas, .idle:
    break
default:
    break
}

private func commitMarkdownScrollHistoryTransactionIfNeeded() {
    markdownScrollHistoryCommitWorkItem?.cancel()
    markdownScrollHistoryCommitWorkItem = nil
    guard isMarkdownScrollHistoryTransactionActive else {
        return
    }
    isMarkdownScrollHistoryTransactionActive = false
    guard editorSession.commitPendingHistoryTransaction(
        autosaveReason: "scroll markdown item"
    ) else {
        return
    }
    updateInlineEditButtonsAppearance()
}
```

## 验证

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS' build
# 功能说明: 验证共享 markdown 模型、渲染、session、测试代码修改后，macOS 目标仍可正常构建。
** BUILD SUCCEEDED **
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS' test -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownContractTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests
# 功能说明: 验证 overflow scroll / scrollOffsetY 持久化 / 四边 handle / resize finalize 的共享合同回归。
** TEST SUCCEEDED **
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS' build
# 功能说明: 验证 iOS direct-touch 单指内部滚动改动不会引入编译错误。
** BUILD SUCCEEDED **
```

## 结论

- 修改一把 markdown block 的语义从“宽度驱动、自动回写高度”升级成了“宽度决定排版，viewport height 独立可调，内部滚动位置持久化”。
- 修改二只在 iOS direct-touch 上新增了一个更窄的分流条件：`单指 + 命中 overflow markdown 内容区 + 纵向优先拖动` 才进入块内滚动；其余场景继续保留原来的移动 item、拖动画布和其他交互语义。
