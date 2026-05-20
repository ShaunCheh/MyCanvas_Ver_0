# 20260520_121813_markdown_coretext_height_fix_record

## 记录范围

- 记录内容：
  - 修复 markdown 位图渲染里“底部尾段文本被截断”的根因。
  - 把 `CanvasMarkdownLayoutMeasurer` 的 markdown 提交测高语义，从 `NSAttributedString.boundingRect(...)` 收口到与实际绘制一致的 `CoreText framesetter` 语义。
  - 保留现有临时 trace 输出，但把日志里的测高字段改成“新测高 + 旧测高”并排显示，方便继续观察修复效果。
  - 补充一条针对尾段段落可见性的回归测试，防止再次出现“最后一行进入 hidden range”的回归。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift`
- 参考现状：
  - `git status --short` 显示当前工作区包含 `3` 个已跟踪修改文件，其中 `1` 个是与本记录无关的 IDE 状态文件。
  - `git diff --stat -- <本次修复相关文件>` 显示本次修复相关变化为：`2 files changed, 185 insertions(+), 14 deletions(-)`。
  - 本记录只覆盖当前仍在 working tree 中、且与本次 markdown 截断根因修复直接相关的 `2` 个代码文件。
- 本记录不包含：
  - `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate` 的 IDE 状态变更。
  - 任何 git 提交行为。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_markdown_coretext_height_fix"
# 功能说明: 使用系统 date 命令生成本记录文件的时间戳前缀。
20260520_121813_markdown_coretext_height_fix
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录当前工作区状态；其中 xcuserstate 为无关变更，不计入本次代码修复范围。
 M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift" "MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift"
# 功能说明: 统计本次 markdown 截断根因修复的真实代码改动量。
.../Rendering/CanvasMarkdownLayoutMeasurer.swift   |  75 ++++++++++---
.../CanvasMarkdownContractTests.swift              | 124 +++++++++++++++++++++
2 files changed, 185 insertions(+), 14 deletions(-)
```

## 当前 changes 摘要

- markdown 的**提交测高来源**已经从 `boundingRect` 改成 `CTFramesetterSuggestFrameSizeWithConstraints(...)`，因此 `item.size.height` 与后续 `CTFrameDraw(...)` 的可见范围使用同一套布局语义。
- 原先仅用于诊断的 `boundingRect` 测高没有被直接删除，而是降级成 `legacyBoundingRectHeight`，只在 trace 开启时打印出来，便于继续比较“旧算法少算了多少高度”。
- 补了一条明确针对“尾段段落不能掉进 hidden range”的契约测试，测试输入保留了本次定位问题时使用的长 markdown + 末尾 `Test / Line 2` 结构。

## 修改一：统一 markdown 测高语义到 CoreText framesetter

### 1.1 修改前

- `CanvasMarkdownLayoutMeasurer.layout(...)` 先拼出 `attributedText`，然后直接用 `boundingRect(...)` 量高度。
- 这个高度会继续参与 `contentSize.height` 的提交。
- 但实际位图渲染在 `CanvasMarkdownBitmapRenderer` 里走的是 `CTFramesetterCreateFrame(...) + CTFrameDraw(...)`，两边在复杂段落 / 尾段文本上会出现高度偏差。
- 日志里已经复现过：旧测高约为 `1906.75`，而 CoreText 实际绘制需要约 `1915.00`，最终让 `Line 2` 落入 hidden range。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 函数名: layout(markdownSource:style:maxLayoutWidth:scale:includeCompatibilityCodeBlockBackgrounds:)
// 功能说明: 修改前 markdown 提交高度直接来自 NSAttributedString.boundingRect(...)，与实际绘制的 CoreText framesetter 不是同一套测高语义。
static func layout(
    markdownSource: String,
    style: CanvasTextStyle,
    maxLayoutWidth: CGFloat,
    scale: CGFloat = 1,
    includeCompatibilityCodeBlockBackgrounds: Bool = true
) -> CanvasMarkdownLayoutResult {
    let resolvedLayoutWidth = max(maxLayoutWidth, 1)
    let composition = makeAttributedComposition(
        markdownSource: markdownSource,
        style: style,
        scale: scale,
        includeCompatibilityCodeBlockBackgrounds: includeCompatibilityCodeBlockBackgrounds
    )
    let attributedText = composition.attributedText
    let measuredRect = attributedText.boundingRect(
        with: CGSize(
            width: resolvedLayoutWidth,
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    )
    let contentSize = CGSize(
        width: resolvedLayoutWidth,
        height: ceil(max(measuredRect.height, minimumContentHeight(
            style: style,
            scale: scale
        )))
    )
    logLayoutTrace(
        markdownSource: markdownSource,
        blocks: composition.blocks,
        measuredRect: measuredRect,
        contentSize: contentSize,
        attributedTextLength: attributedText.length,
        resolvedLayoutWidth: resolvedLayoutWidth
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
}
```

### 1.2 修改后

- `CanvasMarkdownLayoutMeasurer` 现在显式引入 `CoreText`。
- 新增 `measuredAttributedTextHeight(...)`，直接使用 `CTFramesetterSuggestFrameSizeWithConstraints(...)` 作为 markdown 的正式测高来源。
- 新增 `legacyMeasuredTextHeight(...)`，只用于 trace 对照，不再参与正式 `contentSize.height` 提交。
- `logLayoutTrace(...)` 的测量输出也同步改成：
  - `measuredTextHeight`
  - `legacyBoundingRectHeight`
  - `committedHeight`
- 这样一来，markdown 的**测量**和**绘制**都回到同一套 CoreText framesetter 语义，避免尾段文本因高度低估而被裁掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: layout(markdownSource:style:maxLayoutWidth:scale:includeCompatibilityCodeBlockBackgrounds:)
// 功能说明: 修改后 markdown 的正式提交高度来自 CoreText framesetter；legacy boundingRect 仅作为调试对照输出。
import CoreGraphics
import CoreText
import Foundation

static func layout(
    markdownSource: String,
    style: CanvasTextStyle,
    maxLayoutWidth: CGFloat,
    scale: CGFloat = 1,
    includeCompatibilityCodeBlockBackgrounds: Bool = true
) -> CanvasMarkdownLayoutResult {
    let resolvedLayoutWidth = max(maxLayoutWidth, 1)
    let composition = makeAttributedComposition(
        markdownSource: markdownSource,
        style: style,
        scale: scale,
        includeCompatibilityCodeBlockBackgrounds: includeCompatibilityCodeBlockBackgrounds
    )
    let attributedText = composition.attributedText
    let measuredTextHeight = measuredAttributedTextHeight(
        attributedText,
        maxLayoutWidth: resolvedLayoutWidth
    )
    let legacyBoundingRectHeight = isTraceLoggingEnabled
        ? legacyMeasuredTextHeight(
            attributedText,
            maxLayoutWidth: resolvedLayoutWidth
        )
        : nil
    let contentSize = CGSize(
        width: resolvedLayoutWidth,
        height: ceil(max(measuredTextHeight, minimumContentHeight(
            style: style,
            scale: scale
        )))
    )
    logLayoutTrace(
        markdownSource: markdownSource,
        blocks: composition.blocks,
        measuredTextHeight: measuredTextHeight,
        legacyBoundingRectHeight: legacyBoundingRectHeight,
        contentSize: contentSize,
        attributedTextLength: attributedText.length,
        resolvedLayoutWidth: resolvedLayoutWidth
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
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: measuredAttributedTextHeight(_:maxLayoutWidth:) / legacyMeasuredTextHeight(_:maxLayoutWidth:) / logLayoutTrace(markdownSource:blocks:measuredTextHeight:legacyBoundingRectHeight:contentSize:attributedTextLength:resolvedLayoutWidth:)
// 功能说明: 修改后把 CoreText 测高封装成正式 helper，同时保留旧算法的 trace 输出，便于继续对照修复前后的高度差。
private static func measuredAttributedTextHeight(
    _ attributedText: NSAttributedString,
    maxLayoutWidth: CGFloat
) -> CGFloat {
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        nil,
        CGSize(
            width: max(maxLayoutWidth, 1),
            height: CGFloat.greatestFiniteMagnitude
        ),
        nil
    )
    return suggestedSize.height
}

private static func legacyMeasuredTextHeight(
    _ attributedText: NSAttributedString,
    maxLayoutWidth: CGFloat
) -> CGFloat {
    attributedText.boundingRect(
        with: CGSize(
            width: max(maxLayoutWidth, 1),
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).height
}

private static func logLayoutTrace(
    markdownSource: String,
    blocks: [Block],
    measuredTextHeight: CGFloat,
    legacyBoundingRectHeight: CGFloat?,
    contentSize: CGSize,
    attributedTextLength: Int,
    resolvedLayoutWidth: CGFloat
) {
    print(
        "[Canvas Markdown][Measure] " +
        "width=\(debugScalar(resolvedLayoutWidth)) " +
        "measuredTextHeight=\(debugScalar(measuredTextHeight)) " +
        "legacyBoundingRectHeight=\(debugOptionalScalar(legacyBoundingRectHeight)) " +
        "committedHeight=\(debugScalar(contentSize.height)) " +
        "attributedLength=\(attributedTextLength)"
    )
}
```

## 修改二：补“尾段段落必须可见”的回归测试

### 2.1 修改前

- `CanvasMarkdownContractTests` 已经覆盖：
  - markdown item 的 container height 与 intrinsic height 分离；
  - `updateMarkdownItemContent(...)` 会按当前 width 重测 height；
  - snapshot payload 会映射正确的 world/screen geometry。
- 但修改前**没有**任何一条测试会把 markdown 布局结果放回 CoreText frame 里，再检查 `visibleRange` 是否已经完整覆盖最后一段文本。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift（修改前）
// 函数名: testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()
// 功能说明: 修改前契约测试只覆盖 geometry / payload 合同，还没有“末尾段落不能落进 CoreText hidden range”的回归保护。
func testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract() throws {
    let session = makeMarkdownContractTestSession()
    session.camera = CanvasCamera(
        center: CGPoint(x: 100, y: -20),
        zoomScale: 1.5,
        viewportSize: CGSize(width: 400, height: 300)
    )

    let source = """
    ## Snapshot

    A wrapped paragraph that keeps the stored markdown container height
    smaller than the measured intrinsic height.
    """
    let style = CanvasTextStyle(fontSize: 18)
    let item = CanvasMarkdownItem(
        markdownSource: source,
        style: style,
        center: CGPoint(x: 160, y: 40),
        size: CGSize(width: 180, height: 48),
        zIndex: 3,
        rotationRadians: .pi / 6
    )
    let intrinsicHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: source,
        style: style,
        maxLayoutWidth: item.size.width
    )
    XCTAssertGreaterThan(intrinsicHeight, item.size.height)
    // ... 省略后续 geometry / payload 断言 ...
}
```

### 2.2 修改后

- 新增 `testMeasuredMarkdownHeightKeepsTrailingParagraphVisibleInCoreTextFrame()`。
- 测试输入保留了问题定位时使用的长 markdown 结构，并在尾部保留：
  - `Test`
  - `Line 2`
- 断言点从“高度值大于 0”提升为更贴近根因的三条：
  1. `visibleRange.location + visibleRange.length == layout.attributedText.length`
  2. `layout.contentSize.height >= ceil(suggestedSize.height)`
  3. `suggestedSize.height - legacyBoundingRectHeight > 0.5`
- 另外新增 `coreTextSuggestedSize(...)` 和 `coreTextVisibleRange(...)` 测试 helper，避免测试再走另一套伪造语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: testMeasuredMarkdownHeightKeepsTrailingParagraphVisibleInCoreTextFrame()
// 功能说明: 修改后直接验证 markdown 测高结果能完整覆盖 CoreText 的可见范围，防止尾段文本再次进入 hidden range。
func testMeasuredMarkdownHeightKeepsTrailingParagraphVisibleInCoreTextFrame() {
    let source = """
    # Event Loop

    # React Scheduler

    Summary.

    ```swift
    func workLoop() {
        while hasWork {
            if shouldYieldToHost() {
                break
            }
            performUnitOfWork()
        }
    }
    ```

    Yield note.

    ```javascript
    function shouldYieldToHost() {
        return performance.now() >= deadline
    }
    ```

    More details around cooperative scheduling and host yielding continue here.

    ```typescript
    export function scheduleWork() {
        requestHostCallback(flushWork)
    }
    ```

    Continue reading.

    React Scheduler 源码里也能看到类似逻辑：Scheduler 会周期性 yield，让主线程有机会处理用户事件等工作；`shouldYieldToHost` 会根据当前任务占用主线程的时间判断是否让出。

    Test

    Line 2
    """
    let style = CanvasTextStyle(fontSize: 22)
    let layoutWidth: CGFloat = 1197.67
    let layout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: source,
        style: style,
        maxLayoutWidth: layoutWidth,
        scale: 1,
        includeCompatibilityCodeBlockBackgrounds: false
    )
    let suggestedSize = coreTextSuggestedSize(
        for: layout.attributedText,
        maxLayoutWidth: layoutWidth
    )
    let visibleRange = coreTextVisibleRange(
        for: layout.attributedText,
        size: layout.contentSize
    )
    let legacyBoundingRectHeight = layout.attributedText.boundingRect(
        with: CGSize(
            width: layoutWidth,
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).height

    XCTAssertEqual(
        visibleRange.location + visibleRange.length,
        layout.attributedText.length,
        "Expected measured markdown height to keep the trailing paragraph visible."
    )
    XCTAssertGreaterThanOrEqual(
        layout.contentSize.height,
        ceil(suggestedSize.height)
    )
    XCTAssertGreaterThan(
        suggestedSize.height - legacyBoundingRectHeight,
        0.5,
        "Regression fixture should stay sensitive to the old boundingRect under-measurement."
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: coreTextSuggestedSize(for:maxLayoutWidth:) / coreTextVisibleRange(for:size:)
// 功能说明: 修改后测试 helper 与生产代码一样走 CoreText framesetter，确保“测量”和“可见范围校验”基于同一套语义。
import CoreGraphics
import CoreText
import XCTest

private func coreTextSuggestedSize(
    for attributedText: NSAttributedString,
    maxLayoutWidth: CGFloat
) -> CGSize {
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    return CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        nil,
        CGSize(
            width: maxLayoutWidth,
            height: CGFloat.greatestFiniteMagnitude
        ),
        nil
    )
}

private func coreTextVisibleRange(
    for attributedText: NSAttributedString,
    size: CGSize
) -> CFRange {
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
        nil
    )
    return CTFrameGetVisibleStringRange(frame)
}
```

## 验证

- 已执行 markdown 相关 macOS 定向测试，结果通过。
- 已执行 iOS Simulator 构建，结果通过。
- 本次记录没有触碰 `commit_records/` 之外的 `.md` 文件。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild test -scheme MyCanvas_Ver_0 -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownContractTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/MarkdownPreviewParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests
# 功能说明: 验证 markdown 合同测试、layer 测试、preview parity 测试与阶段 5 相关回归在本次修复后仍然通过。
结果: 通过
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild build -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator'
# 功能说明: 验证生产代码在 iOS Simulator 目标上可以正常构建。
结果: 通过
```
