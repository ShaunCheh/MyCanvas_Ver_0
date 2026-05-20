# 20260520_173336_markdown_scrollbar_content_anchor_record

## 记录范围

- 记录内容：
  - 将 markdown block 的滚动条锚点从“容器最右侧”改为“实际内容最右侧附近”。
  - 将滚动条厚度从原来的约 `4` 调整为约 `6`，即接近原先的 `1.5x`。
  - 为了支撑这次定位修正，补齐 markdown 布局结果里的“已用内容区域”数据，并补回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
- 参考现状：
  - 本记录创建前，`git status --short` 显示当前工作区共有 `5` 个已跟踪代码文件处于修改状态。
  - `git diff --stat -- <本次相关文件>` 显示本次改动总计：`5 files changed, 204 insertions(+), 45 deletions(-)`。
  - 本记录不包含任何 git 提交行为。

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_markdown_scrollbar_content_anchor_record"
# 功能说明: 使用系统 date 命令生成本记录文件名的时间戳前缀。
20260520_173336_markdown_scrollbar_content_anchor_record
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录创建本记录前的当前工作区状态；以下 5 个文件属于这次“滚动条改到内容右边并加宽”的现状。
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift" "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift" "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift" "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift" "MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift"
# 功能说明: 统计这次“滚动条内容锚点修正 + 宽度调整”真实改动量，不直接贴原始 diff。
 .../Rendering/CanvasMarkdownContentLayer.swift     |   4 +
 .../Shared/Rendering/CanvasMarkdownItemLayer.swift |  48 ++++++----
 .../Rendering/CanvasMarkdownLayoutMeasurer.swift   | 103 ++++++++++++++++-----
 .../Rendering/CanvasMarkdownLayoutModel.swift      |   5 +
 MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift |  89 ++++++++++++++++--
 5 files changed, 204 insertions(+), 45 deletions(-)
```

## 当前 changes 摘要

- 这次不是简单把滚动条 `X` 往左挪一个固定值，而是补了一条新的布局语义：markdown 渲染结果现在知道“真实已用内容区域”的边界。
- `CanvasMarkdownItemLayer` 不再按 `logicalSize.width` 把滚动条贴到 block 外框右边，而是按 `layout.usedContentRightEdge + gap` 定位。
- `CanvasMarkdownContentLayer` 补了 `currentLayout` 读取口，让 item layer 能拿到当前布局的内容边界，而不是只看到 `contentLayer.bounds.size`。
- 回归测试从“只验证 overflow 时显示滚动条”扩展为“同时验证宽度为 6，且窄内容时滚动条明显贴内容右边而不是容器外框右边”。

## 修改一：在布局结果里补齐“实际内容已用区域”

### 1.1 修改前

- `CanvasMarkdownLayoutResult` 只返回 `attributedText`、`contentSize` 和 `decorations`。
- 这意味着滚动条定位阶段拿不到“内容真正占到了多宽”，只能用整个 markdown 容器宽度作为右边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift（修改前摘要）
// 函数名/类型: CanvasMarkdownLayoutResult
// 功能说明: 修改前布局结果只描述整块内容尺寸和装饰数据，没有暴露实际内容右边界。
struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize
    let decorations: [CanvasMarkdownDecoration]

    var contentHeight: CGFloat {
        contentSize.height
    }
}
```

### 1.2 修改后

- `CanvasMarkdownLayoutResult` 新增 `usedContentBounds` 和 `usedContentRightEdge`。
- 这让后续滚动条可以直接消费布局阶段的“真实内容右边界”，不再依赖容器宽度做猜测。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift
// 函数名/类型: CanvasMarkdownLayoutResult
// 功能说明: 修改后布局结果显式携带内容已用边界，滚动条与其他 overlay 可以按真实内容区域定位。
struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize
    let decorations: [CanvasMarkdownDecoration]
    let usedContentBounds: CGRect

    var contentHeight: CGFloat {
        contentSize.height
    }

    var usedContentRightEdge: CGFloat {
        usedContentBounds.maxX
    }
}
```

## 修改二：在布局测量阶段真实计算内容右边界，而不是继续只看容器宽度

### 2.1 修改前

- `CanvasMarkdownLayoutMeasurer.layout(...)` 会生成 `contentSize` 和 `decorations`，但不会额外计算内容的已用边界。
- code block 的灰底装饰会被生成出来，但这些装饰和文本真实 `usedRect` 不会被合并成一个“整体内容区域”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前摘要）
// 函数名/类型: layout(markdownSource:style:maxLayoutWidth:scale:includeCompatibilityCodeBlockBackgrounds:) / makeCodeBlockDecorations(...)
// 功能说明: 修改前 layout 只返回内容尺寸和装饰数组，没有汇总文本 usedRect 与 decoration rect 的并集。
let contentSize = CGSize(
    width: resolvedLayoutWidth,
    height: ceil(max(measuredTextHeight, minimumContentHeight(
        style: style,
        scale: scale
    )))
)

return CanvasMarkdownLayoutResult(
    attributedText: attributedText,
    contentSize: contentSize,
    decorations: makeCodeBlockDecorations(
        codeBlockRanges: composition.codeBlockRanges,
        attributedText: attributedText,
        maxLayoutWidth: resolvedLayoutWidth,
        style: style,
        scale: scale,
        contentSize: contentSize
    )
)
```

### 2.2 修改后

- `layout(...)` 先构造 `textLayoutContext`，然后同时产出 `decorations` 与 `usedContentBounds`。
- `measuredUsedContentBounds(...)` 会把整段文本的 `usedRect` 与每个 decoration 的 `rect` 统一裁切并求并集。
- `usedRect(...)` 和 `standardizedVisibleRect(...)` 被抽成复用 helper，避免 code block 装饰与整体内容边界各算一套不同逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名/类型: layout(...) / measuredUsedContentBounds(...) / usedRect(forGlyphRange:layoutContext:) / standardizedVisibleRect(_:within:)
// 功能说明: 修改后 layout 在测量阶段就把“文字 + 装饰”的真实内容边界计算出来，为滚动条锚点提供稳定来源。
let contentSize = CGSize(
    width: resolvedLayoutWidth,
    height: ceil(max(measuredTextHeight, minimumContentHeight(
        style: style,
        scale: scale
    )))
)
let textLayoutContext = makeTextLayoutContext(
    attributedText: attributedText,
    maxLayoutWidth: resolvedLayoutWidth
)
let decorations = makeCodeBlockDecorations(
    codeBlockRanges: composition.codeBlockRanges,
    layoutContext: textLayoutContext,
    style: style,
    scale: scale,
    contentSize: contentSize
)
return CanvasMarkdownLayoutResult(
    attributedText: attributedText,
    contentSize: contentSize,
    decorations: decorations,
    usedContentBounds: measuredUsedContentBounds(
        layoutContext: textLayoutContext,
        contentSize: contentSize,
        decorations: decorations
    )
)

private static func measuredUsedContentBounds(
    layoutContext: TextLayoutContext,
    contentSize: CGSize,
    decorations: [CanvasMarkdownDecoration]
) -> CGRect {
    let contentBounds = CGRect(origin: .zero, size: contentSize)
    let glyphRange = layoutContext.layoutManager.glyphRange(
        for: layoutContext.textContainer
    )
    var resolvedBounds = standardizedVisibleRect(
        usedRect(
            forGlyphRange: glyphRange,
            layoutContext: layoutContext
        ),
        within: contentBounds
    )
    for decoration in decorations {
        guard let clippedRect = standardizedVisibleRect(
            decoration.rect,
            within: contentBounds
        ) else {
            continue
        }
        resolvedBounds = resolvedBounds.map { $0.union(clippedRect).standardized }
            ?? clippedRect
    }
    return resolvedBounds ?? .zero
}
```

## 修改三：让 item layer 能消费当前布局，并把滚动条锚到内容最右边

### 3.1 修改前

- `CanvasMarkdownItemLayer` 的滚动条位置直接按 `logicalSize.width` 算，所以天然贴容器最右侧。
- 滚动条厚度是 `4`，最小厚度是 `2`。
- item layer 只能拿到 `contentLayer.bounds.size`，看不到当前布局里真实的内容右边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift（修改前摘要）
// 函数名/类型: update(with:markdownPayload:contentsScale:) / applyScrollbar(logicalSize:contentSize:scrollOffsetY:) / resolvedScrollbarMetrics(logicalSize:contentSize:scrollOffsetY:)
// 功能说明: 修改前滚动条直接贴容器右边，厚度较窄，且定位完全基于 logicalSize。
private static let preferredScrollbarThickness: CGFloat = 4
private static let minimumScrollbarThickness: CGFloat = 2
private static let preferredScrollbarInset: CGFloat = 3

contentLayer.update(
    with: markdownPayload,
    contentsScale: contentsScale
)
applyScrollbar(
    logicalSize: markdownPayload.logicalSize,
    contentSize: contentLayer.bounds.size,
    scrollOffsetY: max(-contentLayer.position.y, 0)
)

let trackX = max(logicalSize.width - horizontalInset - thickness, 0)
```

### 3.2 修改后

- `CanvasMarkdownContentLayer` 新增 `currentLayout`，供 item layer 直接读取当前布局。
- `CanvasMarkdownItemLayer` 现在先拿 `layout.usedContentRightEdge`，再按 `contentRightEdge + gap` 计算 track 的 `X`。
- 厚度改为 `6`，最小厚度改为 `3`，并把“外边距”和“内容间距”拆成两个常量，语义更清楚。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名/类型: currentLayout
// 功能说明: 修改后 content layer 暴露当前活跃布局，供 item layer 读取内容右边界等几何信息。
var currentLayout: CanvasMarkdownLayoutResult? {
    activeLayout
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
// 函数名/类型: update(with:markdownPayload:contentsScale:) / applyScrollbar(logicalSize:layout:scrollOffsetY:) / resolvedScrollbarMetrics(logicalSize:layout:scrollOffsetY:)
// 功能说明: 修改后滚动条改为贴内容最右边，厚度从 4 提到 6，并继续保留 overflow/scrollOffsetY 驱动的显示与 thumb 定位逻辑。
private static let preferredScrollbarThickness: CGFloat = 6
private static let minimumScrollbarThickness: CGFloat = 3
private static let preferredScrollbarOuterInset: CGFloat = 3
private static let preferredScrollbarGapFromContent: CGFloat = 3

contentLayer.update(
    with: markdownPayload,
    contentsScale: contentsScale
)
guard let layout = contentLayer.currentLayout else {
    CATransaction.commit()
    return
}
applyScrollbar(
    logicalSize: markdownPayload.logicalSize,
    layout: layout,
    scrollOffsetY: max(-contentLayer.position.y, 0)
)

let maximumTrackX = max(
    logicalSize.width - Self.preferredScrollbarOuterInset - thickness,
    0
)
let minimumTrackX = min(Self.preferredScrollbarOuterInset, maximumTrackX)
let contentRightEdge = min(
    max(layout.usedContentRightEdge, 0),
    logicalSize.width
)
let trackX = min(
    max(
        contentRightEdge + Self.preferredScrollbarGapFromContent,
        minimumTrackX
    ),
    maximumTrackX
)
```

## 修改四：把回归测试从“有滚动条”升级到“滚动条贴内容右边且厚度为 6”

### 4.1 修改前

- 之前的回归只验证 overflow 时滚动条显示、thumb 比 track 短、滚到最大值时对齐底部。
- 但它没有约束“滚动条是否仍旧错误地贴在容器最右边”，所以这次 UI 语义缺口没法靠原测试捕获。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前摘要）
// 函数名/类型: testContentLayerOffsetsBitmapByClampedScrollOffset()
// 功能说明: 修改前测试只覆盖 overflow 与底部对齐，不验证内容锚点与加宽后的 track 宽度。
XCTAssertFalse(layer.scrollbarTrackLayer.isHidden)
XCTAssertFalse(layer.scrollbarThumbLayer.isHidden)
XCTAssertEqual(
    layer.scrollbarTrackLayer.frame.maxX,
    payload.logicalSize.width - 3,
    accuracy: 0.0001
)
XCTAssertLessThan(
    layer.scrollbarThumbLayer.frame.height,
    layer.scrollbarTrackLayer.frame.height
)
```

### 4.2 修改后

- `testContentLayerOffsetsBitmapByClampedScrollOffset()` 现在改成用 `expectedMarkdownScrollbarTrackX(...)` 推导真实预期位置，并验证 track 宽度为 `6`。
- 新增 `testScrollbarAnchorsToNarrowUsedContentInsteadOfContainerEdge()`，专门用“内容很窄、容器很宽”的样本防止滚动条退回容器外框右侧。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名/类型: testContentLayerOffsetsBitmapByClampedScrollOffset() / testScrollbarAnchorsToNarrowUsedContentInsteadOfContainerEdge() / expectedMarkdownScrollbarTrackX(logicalSize:layout:thickness:outerInset:contentGap:)
// 功能说明: 修改后测试把“滚动条贴内容右边”和“宽度为 6”都纳入回归，防止定位再次回退到容器右边。
let expectedTrackX = expectedMarkdownScrollbarTrackX(
    logicalSize: payload.logicalSize,
    layout: expectedLayout
)
XCTAssertFalse(layer.scrollbarTrackLayer.isHidden)
XCTAssertEqual(
    layer.scrollbarTrackLayer.frame.minX,
    expectedTrackX,
    accuracy: 0.0001
)
XCTAssertEqual(layer.scrollbarTrackLayer.frame.width, 6, accuracy: 0.0001)

func testScrollbarAnchorsToNarrowUsedContentInsteadOfContainerEdge() {
    // ... 构造窄内容、宽容器、存在 overflow 的 markdown ...
    XCTAssertFalse(layer.scrollbarTrackLayer.isHidden)
    XCTAssertEqual(layer.scrollbarTrackLayer.frame.minX, expectedTrackX, accuracy: 0.0001)
    XCTAssertEqual(layer.scrollbarTrackLayer.frame.width, 6, accuracy: 0.0001)
    XCTAssertLessThan(
        layer.scrollbarTrackLayer.frame.maxX,
        payload.logicalSize.width - 120
    )
}
```

## 验证

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownContractTests
# 功能说明: 定向验证 markdown layer 与 markdown contract，确认滚动条新锚点和宽度调整没有破坏现有 overflow/scrollOffsetY 合同。
# 结果说明: success（exit code 0）
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild build -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS'
# 功能说明: 验证共享渲染层改动在 iOS 目标上可以正常编译通过。
# 结果说明: success（exit code 0）
```

## 结果说明

- 这次修改把滚动条锚点从“容器语义”切成了“内容语义”，所以右侧留白再大，滚动条也会贴着实际 markdown 内容右边界走。
- 加宽后的滚动条仍然保持现有 overflow/scrollOffsetY 行为，没有改变 markdown 内容滚动、裁切和持久化的既有合同。
