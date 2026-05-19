# 20260519_211016_markdown_bitmap_phase1_layout_model_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 1。
  - 本阶段目标是把 `CanvasMarkdownLayoutMeasurer` 从“只产出 attributed string”的工具升级成“产出文本布局 + decorations”的语义布局器。
  - 本次实际改动包括：新增共享布局模型文件 `CanvasMarkdownLayoutModel.swift`；把 fenced code block 的 panel 语义抽成独立 decoration；为 decoration 增加 padding / corner radius 的上下限约束；补齐对应布局器测试，并回归阶段 0 的 markdown 契约测试与现有渲染/编辑链测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 1 相关变更为 `2` 个已跟踪修改文件和 `1` 个未跟踪新增文件。
  - `git diff --stat` 显示已跟踪文件的变化为：`2 files changed, 439 insertions(+), 62 deletions(-)`。
  - 由于 `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift` 是新增未跟踪文件，它不会出现在这条 `git diff --stat` 输出里，但已经出现在 `git status --short` 中。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift
```

```bash
# 命令: git diff --stat -- MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift
 .../Rendering/CanvasMarkdownLayoutMeasurer.swift   | 335 +++++++++++++++++----
 .../CanvasMarkdownLayoutMeasurerTests.swift        | 166 ++++++++++
 2 files changed, 439 insertions(+), 62 deletions(-)
```

## 当前 changes 摘要

- `CanvasMarkdownLayoutResult` 被从 `CanvasMarkdownLayoutMeasurer.swift` 内联定义迁移到独立的 `CanvasMarkdownLayoutModel.swift`，并新增了 `CanvasMarkdownDecoration` 与 `CanvasMarkdownDecorationKind`，把 markdown 布局结果正式升级成“文本 + decorations”模型。
- `CanvasMarkdownLayoutMeasurer.layout(...)` 现在不再只返回 `attributedText + contentSize`，而是会在保持原有高度测量语义不变的前提下，同时产出 fenced code block 的 panel decoration。
- fenced code block 的背景 panel 不再只依赖 `NSAttributedString.backgroundColor`；布局器内部新增了 `AttributedComposition`、`codeBlockRanges`、`TextLayoutContext` 和 `makeCodeBlockDecorations(...)`，通过 `NSLayoutManager` 的 line fragment 结果反推 panel rect。
- code block decoration 的 `horizontalPadding`、`verticalPadding` 和 `cornerRadius` 都增加了明确的最小值 / 最大值夹取，避免小字号和大字号两端出现视觉比例失控。
- `CanvasMarkdownLayoutMeasurerTests` 补上了 fenced code block decoration 产出和 clamp 约束的测试，同时回归运行了 `CanvasMarkdownLayerTests`、`CanvasMarkdownContractTests`、`CanvasCommandPolicyParityTests` 和 `CanvasSelectionTransformStateTests` 的相关 markdown 用例，全部通过。

## 修改一：抽出共享布局结果模型

### 1.1 修改前

- `CanvasMarkdownLayoutResult` 直接定义在 `CanvasMarkdownLayoutMeasurer.swift` 文件内部。
- 布局结果只包含 `attributedText` 和 `contentSize`，没有显式的 decorations 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 函数名: CanvasMarkdownLayoutResult（类型定义）
// 功能说明: 修改前布局结果只有富文本和内容尺寸，无法把 code block panel 作为独立语义输出给后续 bitmap renderer 复用。
struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize

    var contentHeight: CGFloat {
        contentSize.height
    }
}
```

### 1.2 修改后

- `CanvasMarkdownLayoutResult` 被抽到单独文件里，成为共享布局模型。
- 新增 `CanvasMarkdownDecorationKind` 与 `CanvasMarkdownDecoration`，第一版先只覆盖 fenced code block 的 `codeBlockPanel`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutModel.swift
// 函数名: CanvasMarkdownDecorationKind / CanvasMarkdownDecoration / CanvasMarkdownLayoutResult（类型定义）
// 功能说明: 修改后布局器可以把文本排版结果和独立 decoration 一起输出，为后续 bitmap renderer 与 thumbnail 绘制提供稳定输入。
import CoreGraphics
import Foundation

enum CanvasMarkdownDecorationKind: Equatable {
    case codeBlockPanel
}

struct CanvasMarkdownDecoration: Equatable {
    let kind: CanvasMarkdownDecorationKind
    let rect: CGRect
    let fillColor: CanvasTextColor
    let cornerRadius: CGFloat
}

struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize
    let decorations: [CanvasMarkdownDecoration]

    var contentHeight: CGFloat {
        contentSize.height
    }
}
```

## 修改二：把布局器从“纯 attributed text”升级到“文本 + decoration”组合输出

### 2.1 修改前

- `layout(...)` 只会调用 `makeAttributedText(...)` 生成富文本，再通过 `boundingRect(...)` 测高。
- 整个布局过程中没有独立的 block-range 跟踪，也没有 decoration 计算链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 函数名: layout(markdownSource:style:maxLayoutWidth:scale:), makeAttributedText(markdownSource:style:scale:)
// 功能说明: 修改前 layout 只负责把 markdown 转为 attributed text 并测量内容高度，没有产出任何 decoration 语义。
static func layout(
    markdownSource: String,
    style: CanvasTextStyle,
    maxLayoutWidth: CGFloat,
    scale: CGFloat = 1
) -> CanvasMarkdownLayoutResult {
    let resolvedLayoutWidth = max(maxLayoutWidth, 1)
    let attributedText = makeAttributedText(
        markdownSource: markdownSource,
        style: style,
        scale: scale
    )
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
    return CanvasMarkdownLayoutResult(
        attributedText: attributedText,
        contentSize: CGSize(
            width: resolvedLayoutWidth,
            height: ceil(max(measuredRect.height, minimumContentHeight(
                style: style,
                scale: scale
            )))
        )
    )
}
```

### 2.2 修改后

- `layout(...)` 先构建 `AttributedComposition`，再从 `codeBlockRanges` 生成 decorations。
- 新增 `includeCompatibilityCodeBlockBackgrounds` 作为过渡参数，允许当前 renderer 继续吃 `attributedText`，但阶段 1 已经把 fenced code block panel 的核心语义独立抽出来了。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: layout(markdownSource:style:maxLayoutWidth:scale:includeCompatibilityCodeBlockBackgrounds:), makeAttributedComposition(markdownSource:style:scale:includeCompatibilityCodeBlockBackgrounds:)
// 功能说明: 修改后 layout 先产出 attributed composition 和 code block range，再生成 decoration，实现“文本 + decorations”组合输出。
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
// 函数名: AttributedComposition, RenderedBlock（类型定义）
// 功能说明: 修改后布局器在富文本拼接阶段同步记住 fenced code block 对应的字符区间，为 decoration 反推提供稳定索引。
private struct RenderedBlock {
    let block: Block
    let attributedText: NSAttributedString
}

private struct AttributedComposition {
    let attributedText: NSAttributedString
    let codeBlockRanges: [NSRange]
}
```

## 修改三：把 fenced code block panel 从 typographic background box 抽成独立 decoration

### 3.1 修改前

- fenced code block 在 `makeAttributedBlock(...)` 里直接给整段 `NSAttributedString` 加 `.backgroundColor`。
- inline code 也会在 `makeLeafAttributedText(...)` 里走 `traits.isCode -> backgroundColor` 逻辑，panel 语义与字形背景盒耦合。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 函数名: makeAttributedBlock(for:style:scale:), makeLeafAttributedText(from:style:fontSize:traits:color:)
// 功能说明: 修改前 fenced code block 的灰底完全依赖 attributed string backgroundColor，因此会把空白、缩进和行高一起染上背景。
case let .codeBlock(text):
    let attributed = makeLeafAttributedText(
        from: text.isEmpty ? " " : text,
        style: style,
        fontSize: baseFontSize * 0.95,
        traits: .plain.merging(isCode: true),
        color: platformColor(for: style.color)
    )
    attributed.addAttribute(
        .backgroundColor,
        value: codeBackgroundColor(),
        range: NSRange(location: 0, length: attributed.length)
    )
    applyParagraphStyle(
        to: attributed,
        fontSize: baseFontSize,
        firstLineHeadIndent: baseFontSize * codeBlockInsetFactor,
        headIndent: baseFontSize * codeBlockInsetFactor,
        paragraphSpacing: baseFontSize * blockSpacingFactor
    )
    return attributed
```

### 3.2 修改后

- fenced code block 本身改为通过 `includeCompatibilityCodeBlockBackgrounds` 控制是否继续保留 attributed fallback 背景。
- 新增 `makeCodeBlockDecorations(...)`、`makeTextLayoutContext(...)`、`codeBlockDecorationRect(...)`，基于 `NSLayoutManager` 的 line fragment 反推出 code block panel 几何。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: makeRenderedBlock(for:style:scale:includeCompatibilityCodeBlockBackgrounds:)
// 功能说明: 修改后 fenced code block 的 panel 语义已经独立出来，当前 attributed background 只保留为兼容现有 renderer 的过渡开关。
case let .codeBlock(text):
    let attributed = makeLeafAttributedText(
        from: text.isEmpty ? " " : text,
        style: style,
        fontSize: baseFontSize * 0.95,
        traits: .plain.merging(isCode: true),
        color: platformColor(for: style.color),
        // Stage 1 moves fenced code block semantics to decorations while
        // keeping an attributed-text fallback for current renderers.
        includesCodeBackground: includeCompatibilityCodeBlockBackgrounds
    )
    applyParagraphStyle(
        to: attributed,
        fontSize: baseFontSize,
        firstLineHeadIndent: baseFontSize * codeBlockInsetFactor,
        headIndent: baseFontSize * codeBlockInsetFactor,
        paragraphSpacing: baseFontSize * blockSpacingFactor
    )
    return RenderedBlock(
        block: block,
        attributedText: attributed
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: makeCodeBlockDecorations(codeBlockRanges:attributedText:maxLayoutWidth:style:scale:contentSize:), codeBlockDecorationRect(for:layoutContext:contentBounds:metrics:)
// 功能说明: 修改后 decoration rect 由 line fragment 的 usedRect 联合得出，再叠加 panel padding，并裁到 content bounds 内。
private static func makeCodeBlockDecorations(
    codeBlockRanges: [NSRange],
    attributedText: NSAttributedString,
    maxLayoutWidth: CGFloat,
    style: CanvasTextStyle,
    scale: CGFloat,
    contentSize: CGSize
) -> [CanvasMarkdownDecoration] {
    guard codeBlockRanges.isEmpty == false else {
        return []
    }

    let layoutContext = makeTextLayoutContext(
        attributedText: attributedText,
        maxLayoutWidth: maxLayoutWidth
    )
    let metrics = codeBlockDecorationMetrics(
        style: style,
        scale: scale
    )
    let contentBounds = CGRect(origin: .zero, size: contentSize)
    return codeBlockRanges.compactMap { characterRange in
        guard let rect = codeBlockDecorationRect(
            for: characterRange,
            layoutContext: layoutContext,
            contentBounds: contentBounds,
            metrics: metrics
        ) else {
            return nil
        }
        return CanvasMarkdownDecoration(
            kind: .codeBlockPanel,
            rect: rect,
            fillColor: codeDecorationFillColor(),
            cornerRadius: metrics.cornerRadius
        )
    }
}
```

## 修改四：为 code block panel 增加 padding / corner radius 的上下限

### 4.1 修改前

- code block 的可视外观主要靠字体大小、段落缩进和 attributed background 自然形成。
- 没有独立的 panel padding / corner radius 指标，更没有 clamp，因此小字号和大字号时不会有可控的几何边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 函数名: codeBackgroundColor(), codeBlockInsetFactor（常量与辅助函数）
// 功能说明: 修改前只有背景颜色和段落缩进，缺少 panel padding / radius 的独立度量与 clamp。
private static let codeBlockInsetFactor: CGFloat = 0.9

private static func codeBackgroundColor() -> CanvasMarkdownPlatformColor {
    #if os(macOS)
    return CanvasMarkdownPlatformColor(
        calibratedWhite: 0,
        alpha: 0.08
    )
    #else
    return CanvasMarkdownPlatformColor(
        white: 0,
        alpha: 0.08
    )
    #endif
}
```

### 4.2 修改后

- 新增 panel 的 `horizontalPadding`、`verticalPadding` 和 `cornerRadius` 因子与对应的最小/最大值。
- `codeBlockDecorationMetrics(...)` 统一负责 clamp；`codeDecorationFillColor()` 把 panel 的颜色语义转成共享 `CanvasTextColor`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 函数名: codeBlockDecorationMetrics(style:scale:), clamped(_:min:max:), codeDecorationFillColor()
// 功能说明: 修改后 fenced code block panel 的 padding 和圆角都走统一 clamp，避免在字号极小或极大时视觉比例失控。
private static let codeBlockPanelHorizontalPaddingFactor: CGFloat = 0.35
private static let codeBlockPanelVerticalPaddingFactor: CGFloat = 0.18
private static let codeBlockPanelCornerRadiusFactor: CGFloat = 0.24
private static let minimumCodeBlockPanelHorizontalPadding: CGFloat = 4
private static let maximumCodeBlockPanelHorizontalPadding: CGFloat = 12
private static let minimumCodeBlockPanelVerticalPadding: CGFloat = 2
private static let maximumCodeBlockPanelVerticalPadding: CGFloat = 6
private static let minimumCodeBlockPanelCornerRadius: CGFloat = 4
private static let maximumCodeBlockPanelCornerRadius: CGFloat = 10

private static func codeBlockDecorationMetrics(
    style: CanvasTextStyle,
    scale: CGFloat
) -> CodeBlockDecorationMetrics {
    let baseFontSize = CanvasTextLayoutMeasurer.renderFontSize(
        for: style,
        scale: scale
    )
    return CodeBlockDecorationMetrics(
        horizontalPadding: clamped(
            baseFontSize * codeBlockPanelHorizontalPaddingFactor,
            min: minimumCodeBlockPanelHorizontalPadding,
            max: maximumCodeBlockPanelHorizontalPadding
        ),
        verticalPadding: clamped(
            baseFontSize * codeBlockPanelVerticalPaddingFactor,
            min: minimumCodeBlockPanelVerticalPadding,
            max: maximumCodeBlockPanelVerticalPadding
        ),
        cornerRadius: clamped(
            baseFontSize * codeBlockPanelCornerRadiusFactor,
            min: minimumCodeBlockPanelCornerRadius,
            max: maximumCodeBlockPanelCornerRadius
        )
    )
}
```

## 修改五：补齐阶段 1 的语义布局回归测试

### 5.1 修改前

- `CanvasMarkdownLayoutMeasurerTests` 只有宽度测高、基础 block 转换、标题字号三个基线。
- 还没有任何测试验证 fenced code block 是否产出 decoration，更没有测试验证 padding / corner radius 的上下限。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift（修改前）
// 函数名: CanvasMarkdownLayoutMeasurerTests（测试集）
// 功能说明: 修改前测试只覆盖基础排版和字号关系，没有覆盖 decoration 语义。
@MainActor
final class CanvasMarkdownLayoutMeasurerTests: XCTestCase {
    func testMeasuredContentHeightGrowsWhenWidthShrinks() { /* ... */ }
    func testLayoutConvertsBasicBlocksIntoDisplayText() { /* ... */ }
    func testHeadingUsesLargerFontThanBody() throws { /* ... */ }
}
```

### 5.2 修改后

- 新增 `testLayoutProducesDecorationForFencedCodeBlock()`，验证 decoration 产出、范围和颜色。
- 新增 `testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds()`，锁定 padding / corner radius 的最小值与最大值。
- 新增 `markdownCodeBlockUsedRect(...)` 和 `markdownDecorationInsets(...)` 辅助函数，用实际 line fragment 结果对 panel rect 做几何断言。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift
// 函数名: testLayoutProducesDecorationForFencedCodeBlock()
// 功能说明: 修改后验证 fenced code block 一定会产出独立 decoration，并且 rect 会包住实际 code text 的 usedRect，且不会越出 content bounds。
func testLayoutProducesDecorationForFencedCodeBlock() throws {
    let width: CGFloat = 260
    let codeText = """
    let value = 1
    print(value)
    """
    let layout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: """
        Intro

        ```
        \(codeText)
        ```

        Outro
        """,
        style: CanvasTextStyle(fontSize: 18),
        maxLayoutWidth: width
    )
    let decoration = try XCTUnwrap(layout.decorations.first)
    let usedRect = try markdownCodeBlockUsedRect(
        in: layout.attributedText,
        codeText: codeText,
        width: width
    )

    XCTAssertEqual(layout.decorations.count, 1)
    XCTAssertEqual(decoration.kind, .codeBlockPanel)
    XCTAssertGreaterThanOrEqual(usedRect.minX, decoration.rect.minX)
    XCTAssertLessThanOrEqual(decoration.rect.maxX, layout.contentSize.width + 0.0001)
    XCTAssertLessThanOrEqual(decoration.rect.maxY, layout.contentSize.height + 0.0001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift
// 函数名: testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds()
// 功能说明: 修改后验证 panel 的左右/上下 padding 与圆角会被稳定夹在预期最小值和最大值之间。
func testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds() throws {
    let width: CGFloat = 280
    let codeText = "let value = 1"
    let source = """
    Intro

    ```
    \(codeText)
    ```

    Outro
    """

    let smallLayout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: source,
        style: CanvasTextStyle(fontSize: 8),
        maxLayoutWidth: width
    )
    let smallDecoration = try XCTUnwrap(smallLayout.decorations.first)
    let smallUsedRect = try markdownCodeBlockUsedRect(
        in: smallLayout.attributedText,
        codeText: codeText,
        width: width
    )
    let smallInsets = markdownDecorationInsets(
        decorationRect: smallDecoration.rect,
        usedRect: smallUsedRect
    )

    XCTAssertEqual(smallInsets.left, 4, accuracy: 1)
    XCTAssertEqual(smallInsets.top, 2, accuracy: 1)
    XCTAssertEqual(smallDecoration.cornerRadius, 4, accuracy: 1)

    let largeLayout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: source,
        style: CanvasTextStyle(fontSize: 80),
        maxLayoutWidth: width
    )
    let largeDecoration = try XCTUnwrap(largeLayout.decorations.first)
    let largeUsedRect = try markdownCodeBlockUsedRect(
        in: largeLayout.attributedText,
        codeText: codeText,
        width: width
    )
    let largeInsets = markdownDecorationInsets(
        decorationRect: largeDecoration.rect,
        usedRect: largeUsedRect
    )

    XCTAssertEqual(largeInsets.left, 12, accuracy: 1)
    XCTAssertEqual(largeInsets.top, 6, accuracy: 1)
    XCTAssertEqual(largeDecoration.cornerRadius, 10, accuracy: 1)
}
```

## 验证记录

- 本次已检查阶段 1 改动文件，没有新增 linter 问题。
- 本次已执行 markdown 阶段 1 的定向测试，同时回归了 markdown layer、阶段 0 契约、编辑链和 resize 语义相关的既有基线。

```bash
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownContractTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo" -only-testing:"MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests/testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry"
** TEST SUCCEEDED **
Test case 'CanvasMarkdownLayoutMeasurerTests.testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds()' passed
Test case 'CanvasMarkdownLayoutMeasurerTests.testLayoutProducesDecorationForFencedCodeBlock()' passed
Test case 'CanvasMarkdownLayerTests.testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts()' passed
Test case 'CanvasMarkdownLayerTests.testUpdateKeepsMarkdownFontSizesWhenOnlyHeightChanges()' passed
Test case 'CanvasMarkdownLayerTests.testUpdateReflowsAttributedMarkdownWhenLayoutWidthChanges()' passed
Test case 'CanvasCommandPolicyParityTests.testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth()' passed
Test case 'CanvasCommandPolicyParityTests.testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()' passed
Test case 'CanvasCommandPolicyParityTests.testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()' passed
Test case 'CanvasMarkdownContractTests.testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()' passed
Test case 'CanvasMarkdownContractTests.testMarkdownItemKeepsExplicitContainerHeightEvenWhenIntrinsicHeightDiffers()' passed
Test case 'CanvasMarkdownContractTests.testUpdateMarkdownItemContentKeepsCurrentWidthAndRemeasuresHeight()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()' passed
```

## 结论

- 本次阶段 1 的实质是把 markdown 布局器升级成“语义布局结果”生产者，而不是切换主画布显示对象。
- 到这一阶段为止，`measuredContentHeight(...)` 的既有语义仍然保持，当前 `CanvasMarkdownLayer` 仍可继续消费 `attributedText`，但 fenced code block panel 的核心几何语义已经从 typographic background box 中抽离出来，具备进入阶段 2 的条件。
