# 20260515_232111_text_content_driven_phase3_record

## 记录范围

- 记录内容：
  - 实施“文字内容驱动尺寸”计划的 `phase 3`，从主画布和缩略图渲染链路里移除 `shrink-to-fit`。
  - 把“最终渲染字号”的口径收口到共享层，明确文字渲染直接使用 `style.fontSize * scale`，不再按框二次缩字。
  - 新增与更新测试，锁定“权威字号渲染”这一阶段契约。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasTextLayerTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 显示：
    - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
    - `M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift`
    - `M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift`
    - `M MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift`
    - `?? MyCanvas_Ver_0Tests/CanvasTextLayerTests.swift`
  - 生成本记录前，`git diff --stat` 显示 4 个已跟踪文件共 `43 insertions(+), 87 deletions(-)`；新增测试文件因为尚未纳入跟踪，不出现在该统计里。
- 本记录不包含：
  - 单文字 / 含文字组选的 resize 交互语义调整
  - 旧文档加载归一
  - inline text editor 的字号控件与命令接线

## 当前 changes 摘要

- 共享层新增 `CanvasTextLayoutMeasurer.renderFontSize(...)`，把“最终渲染字号”定义为 `style.fontSize * scale`。
- `CanvasTextLayer` 删除了基于 `availableSize / intrinsicSize` 的缩字逻辑，也移除了与 `layoutBoundsSize` 绑定的 attributed string 刷新条件。
- `BoardThumbnailRenderer` 删除了 `fittedTextFont(...)` 的缩字逻辑，缩略图与主画布改为共用同一套权威字号口径。
- `CanvasTextLayoutMeasurerTests` 新增对 `renderFontSize(...)` 的契约测试。
- 新增 `CanvasTextLayerTests`，直接锁定“小 bounds 下也不会再缩字”的行为。

## 修改一：共享层新增“最终渲染字号”契约

### 修改前

- `CanvasTextLayoutMeasurer` 只有 intrinsic 测量接口，没有单独表达“最终渲染字号”的共享口径。
- 各个 surface 需要自己决定是否缩字，容易让渲染逻辑再次分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift（修改前）
// 函数名: intrinsicContentSize(for:style:scale:) / intrinsicItemSize(for:style:scale:metrics:) / measuredSize(for:style:scale:metrics:)
// 功能说明: 修改前共享层只负责文字尺寸测量，没有抽出“最终渲染字号”的统一规则；measuredSize 直接在内部用 style.fontSize * scale 参与测量。
enum CanvasTextLayoutMeasurer {
    static func intrinsicContentSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat = 1
    ) -> CGSize {
        measuredSize(
            for: text,
            style: style,
            scale: scale,
            metrics: .tightContent
        )
    }

    static func intrinsicItemSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat = 1,
        metrics: CanvasTextLayoutMetrics = .contentDrivenItem
    ) -> CGSize {
        measuredSize(
            for: text,
            style: style,
            scale: scale,
            metrics: metrics
        )
    }

    private static func measuredSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat,
        metrics: CanvasTextLayoutMetrics
    ) -> CGSize {
        let baseFontSize = max(style.fontSize * scale, 1)
        // ...
    }
}
```

### 修改后

- 新增 `renderFontSize(...)`，明确渲染层直接使用 `style.fontSize * scale`。
- `measuredSize(...)` 也改为复用同一个入口，这样测量与最终渲染都依赖同一份字号口径。
- 同时把 `tightContent` 注释改成“原始 glyph bounds 测量”，不再暗示它服务于 shrink-to-fit。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift
// 函数名: renderFontSize(for:scale:) / measuredSize(for:style:scale:metrics:)
// 功能说明: 修改后共享层同时提供“最终渲染字号”和“intrinsic 尺寸测量”两类能力，让主画布与缩略图都能复用同一套字号规则。
struct CanvasTextLayoutMetrics: Hashable, Sendable {
    // ...
    // Tight content measurement describes the raw glyph bounds surfaces can use
    // when they need content-only sizing without extra padding/minimum rules.
    static let tightContent = CanvasTextLayoutMetrics(
        minimumSize: .zero,
        horizontalInset: 0,
        verticalInset: 0
    )
}

enum CanvasTextLayoutMeasurer {
    static func renderFontSize(
        for style: CanvasTextStyle,
        scale: CGFloat = 1
    ) -> CGFloat {
        max(style.fontSize * scale, 1)
    }

    private static func measuredSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat,
        metrics: CanvasTextLayoutMetrics
    ) -> CGSize {
        let baseFontSize = renderFontSize(
            for: style,
            scale: scale
        )
        // ...
    }
}
```

## 修改二：`CanvasTextLayer` 去掉 shrink-to-fit 与 bounds 耦合刷新

### 修改前

- `CanvasTextLayer.makeAttributedText(...)` 依赖 `availableSize`。
- `fittedFont(...)` 会先测 intrinsic size，再按 `availableSize / intrinsicSize` 计算缩放比例，导致最终字号不是权威 `fontSize`。
- `shouldRefreshAttributedText(...)` 还会把 `layoutBoundsSize` 作为刷新条件，意味着只要框变了，就会重新触发缩字路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift（修改前）
// 函数名: shouldRefreshAttributedText(textPayload:layoutBoundsSize:) / makeAttributedText(from:availableSize:) / fittedFont(for:availableSize:)
// 功能说明: 修改前主画布文字层会根据当前 bounds 和 intrinsic size 二次缩小字体，并把 layoutBoundsSize 纳入 attributed string 的刷新条件。
private func shouldRefreshAttributedText(
    textPayload: CanvasTextRenderPayload,
    layoutBoundsSize: CGSize
) -> Bool {
    lastAppliedText != textPayload.text ||
    lastAppliedStyle != textPayload.style ||
    lastAppliedZoomScale != textPayload.zoomScale ||
    lastAppliedLayoutBoundsSize != layoutBoundsSize
}

private func makeAttributedText(
    from textPayload: CanvasTextRenderPayload,
    availableSize: CGSize
) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byClipping

    let font = fittedFont(
        for: textPayload,
        availableSize: availableSize
    )
    // ...
}

private func fittedFont(
    for textPayload: CanvasTextRenderPayload,
    availableSize: CGSize
) -> CanvasPlatformFont {
    let baseFontSize = max(textPayload.style.fontSize * textPayload.zoomScale, 1)
    let intrinsicSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
        for: textPayload.text,
        style: textPayload.style,
        scale: textPayload.zoomScale
    )
    let scale = min(
        availableSize.width / intrinsicSize.width,
        availableSize.height / intrinsicSize.height
    )
    return platformFont(
        named: textPayload.style.fontName,
        size: max(baseFontSize * scale, 1)
    )
}
```

### 修改后

- 移除了 `lastAppliedLayoutBoundsSize`，attributed string 刷新只看 `text / style / zoom`。
- `makeAttributedText(...)` 不再接受 `availableSize`。
- `renderFont(...)` 直接使用共享的 `renderFontSize(...)`，完全去掉 shrink-to-fit。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift
// 函数名: shouldRefreshAttributedText(textPayload:) / makeAttributedText(from:) / renderFont(for:)
// 功能说明: 修改后主画布文字层不再根据 bounds 缩字；最终字号只由 style.fontSize 和 zoomScale 决定，layoutBoundsSize 也不再驱动 attributed string 刷新。
private func shouldRefreshAttributedText(
    textPayload: CanvasTextRenderPayload
) -> Bool {
    lastAppliedText != textPayload.text ||
    lastAppliedStyle != textPayload.style ||
    lastAppliedZoomScale != textPayload.zoomScale
}

private func makeAttributedText(
    from textPayload: CanvasTextRenderPayload
) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byClipping

    let font = renderFont(for: textPayload)
    let textColor = platformColor(for: textPayload.style.color)
    return NSAttributedString(
        string: textPayload.text,
        attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    )
}

private func renderFont(
    for textPayload: CanvasTextRenderPayload
) -> CanvasPlatformFont {
    platformFont(
        named: textPayload.style.fontName,
        size: CanvasTextLayoutMeasurer.renderFontSize(
            for: textPayload.style,
            scale: textPayload.zoomScale
        )
    )
}
```

## 修改三：`BoardThumbnailRenderer` 去掉缩略图缩字逻辑

### 修改前

- `BoardThumbnailRenderer.drawText(...)` 也会调用 `fittedTextFont(...)`。
- 这条链路会基于 `availableSize / intrinsicSize` 重新缩小缩略图里的字号，导致 board list 预览和主画布文字观感可能不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawText(_:style:in:worldToPixelScale:context:) / fittedTextFont(for:style:availableSize:worldToPixelScale:)
// 功能说明: 修改前缩略图渲染也会根据可用框尺寸和 intrinsic size 计算缩放比例，从而二次缩小最终字号。
private func drawText(
    _ text: String,
    style: BoardTextStyleRecord,
    in rect: CGRect,
    worldToPixelScale: CGFloat,
    context: CGContext
) {
    let availableSize = rect.size
    let paragraphStyle = textParagraphStyle()
    let font = fittedTextFont(
        for: text,
        style: style,
        availableSize: availableSize,
        worldToPixelScale: worldToPixelScale
    )
    // ...
}

private func fittedTextFont(
    for text: String,
    style: BoardTextStyleRecord,
    availableSize: CGSize,
    worldToPixelScale: CGFloat
) -> CTFont {
    let baseFontSize = max(CGFloat(style.fontSize) * worldToPixelScale, 1)
    let intrinsicSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
        for: text,
        style: style.canvasTextStyle,
        scale: worldToPixelScale
    )
    let scale = min(
        availableSize.width / intrinsicSize.width,
        availableSize.height / intrinsicSize.height
    )
    return textFont(
        named: style.fontName,
        size: max(baseFontSize * scale, 1)
    )
}
```

### 修改后

- `drawText(...)` 改为调用 `renderTextFont(...)`。
- 缩略图渲染直接使用共享的 `renderFontSize(...)`，与主画布彻底统一到同一套字号规则。
- 仍然保留现有 `frame + clip` 的绘制方式，但不再靠缩小字号兜底。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawText(_:style:in:worldToPixelScale:context:) / renderTextFont(style:worldToPixelScale:)
// 功能说明: 修改后缩略图不再根据矩形框收缩字号，而是直接以 style.fontSize * worldToPixelScale 作为最终渲染字号，和主画布保持一致。
private func drawText(
    _ text: String,
    style: BoardTextStyleRecord,
    in rect: CGRect,
    worldToPixelScale: CGFloat,
    context: CGContext
) {
    let availableSize = rect.size
    let paragraphStyle = textParagraphStyle()
    let font = renderTextFont(
        style: style,
        worldToPixelScale: worldToPixelScale
    )
    let attributedText = NSAttributedString(
        string: text,
        attributes: textAttributes(
            font: font,
            paragraphStyle: paragraphStyle,
            color: textColor(for: style.color)
        )
    )
    // ...
}

private func renderTextFont(
    style: BoardTextStyleRecord,
    worldToPixelScale: CGFloat
) -> CTFont {
    return textFont(
        named: style.fontName,
        size: CanvasTextLayoutMeasurer.renderFontSize(
            for: style.canvasTextStyle,
            scale: worldToPixelScale
        )
    )
}
```

## 修改四：补充“权威字号”测试

### 修改前

- `CanvasTextLayoutMeasurerTests` 只覆盖 intrinsic size 的增长与 padding/minimum 规则。
- 仓库里还没有直接验证“最终渲染字号就是 `fontSize * scale`”的测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift（修改前）
// 函数名: testIntrinsicContentSizeGrowsWithFontSize() / testIntrinsicItemSizeAppliesInsetsAndMinimums()
// 功能说明: 修改前测试只锁定 intrinsic 测量契约，还没有单独验证 phase 3 引入的最终渲染字号规则。
final class CanvasTextLayoutMeasurerTests: XCTestCase {
    func testIntrinsicContentSizeGrowsWithFontSize() {
        // ...
    }

    func testIntrinsicItemSizeAppliesInsetsAndMinimums() {
        // ...
    }
}
```

### 修改后

- 在 `CanvasTextLayoutMeasurerTests` 里新增 `testRenderFontSizeMatchesFontSizeTimesScale()`。
- 用一个直接的比例校验锁住共享层的字号规则，避免后续渲染链路又偷偷引入缩字。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift
// 函数名: testRenderFontSizeMatchesFontSizeTimesScale()
// 功能说明: 修改后新增共享字号契约测试，锁定 renderFontSize 必须直接返回 fontSize * scale。
final class CanvasTextLayoutMeasurerTests: XCTestCase {
    func testRenderFontSizeMatchesFontSizeTimesScale() {
        let style = CanvasTextStyle(fontSize: 18)

        let renderFontSize = CanvasTextLayoutMeasurer.renderFontSize(
            for: style,
            scale: 2.5
        )

        XCTAssertEqual(renderFontSize, 45, accuracy: 0.0001)
    }
}
```

## 修改五：新增 `CanvasTextLayer` 的反缩字回归测试

### 修改前

- 仓库里还没有专门覆盖 `CanvasTextLayer` 的测试文件。
- 没有测试直接观察主画布文字层写入的 attributed string 字号，后续如果有人把 shrink-to-fit 再带回来，回归会很隐蔽。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayerTests.swift（修改前）
// 函数名/类型名: CanvasTextLayerTests
// 功能说明: phase 3 实施前，仓库里还没有专门锁定 CanvasTextLayer 最终渲染字号行为的测试文件。
// 该文件在修改前不存在。
```

### 修改后

- 新增 `CanvasTextLayerTests`。
- 通过构造一个很小的 `screenBoundsSize`，直接检查 `layer.string` 里的 `.font` 属性，确认 `CanvasTextLayer` 即便在小 bounds 下也不会再缩字。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayerTests.swift
// 函数名: testUpdateUsesAuthoritativeFontSizeEvenWhenBoundsAreSmall()
// 功能说明: 新增主画布文字层回归测试，直接校验 CanvasTextLayer 写入 attributed string 的字号与共享 renderFontSize 规则一致，不受小 bounds 影响。
final class CanvasTextLayerTests: XCTestCase {
    func testUpdateUsesAuthoritativeFontSizeEvenWhenBoundsAreSmall() throws {
        let itemID = CanvasItemID()
        let layer = CanvasTextLayer(itemID: itemID)
        let textPayload = CanvasTextRenderPayload(
            text: "A very long line of text",
            style: CanvasTextStyle(fontSize: 32),
            zoomScale: 1.5
        )
        let renderItem = makeTextLayerRenderItem(
            itemID: itemID,
            size: CGSize(width: 24, height: 12),
            textPayload: textPayload
        )

        layer.update(
            with: renderItem,
            textPayload: textPayload,
            contentsScale: 2
        )

        let attributedText = try XCTUnwrap(layer.string as? NSAttributedString)
        let font = try XCTUnwrap(
            attributedText.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? PlatformTestFont
        )

        XCTAssertEqual(
            font.pointSize,
            CanvasTextLayoutMeasurer.renderFontSize(
                for: textPayload.style,
                scale: textPayload.zoomScale
            ),
            accuracy: 0.0001
        )
    }
}
```

## 验证情况

- `ReadLints` 检查结果：本次改动未引入新的诊断问题。
- `macOS` 定向测试通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests -only-testing:MyCanvas_Ver_0Tests/CanvasTextLayerTests`
- `iOS Simulator` 构建通过：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17'`

## 当前阶段结论

- `phase 3` 已把主画布与缩略图里的 `shrink-to-fit` 拔掉，文字渲染正式切换到“内容决定尺寸、`fontSize` 是权威字号”的语义。
- 当前仍然保留现有的文本裁剪 / frame 绘制方式，但不再靠缩小字体来把内容塞回旧框。
- 这也意味着后续 `phase 5` 的旧文档归一会更重要，因为旧数据里的 `size` 仍可能带着历史固定框语义。
