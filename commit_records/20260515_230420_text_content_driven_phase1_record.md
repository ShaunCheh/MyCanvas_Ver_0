# 20260515_230420_text_content_driven_phase1_record

## 记录范围

- 记录内容：
  - 实施“文字内容驱动尺寸”计划的 `phase 1`，先把共享契约和共享测量 helper 落下去。
  - 把主画布 `CanvasTextLayer` 与缩略图 `BoardThumbnailRenderer` 中各自重复的 intrinsic 文本测量收口到同一个 shared helper。
  - 新增最小测试，先锁定共享测量 helper 的基本契约。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 只显示上述 5 个文件处于修改/新增状态。
  - 这一步还没有改 `CanvasEditorSession.commitTextEdit()`、`CanvasScene.updateTextItem(...)` 或字号 UI，只建立共享契约与测量落点。
- 本记录不包含：
  - 去掉 `shrink-to-fit`
  - `text/style/size` 的原子提交写回
  - 旧文档加载归一
  - 单文字 / 组选缩放语义调整
  - inline editor 的字号入口

## 当前 changes 摘要

- `CanvasTextItem.size` 增加了语义注释，明确它是渲染、命中、选区共用的 layout bounds。
- 新增 `CanvasTextLayoutMetrics` / `CanvasTextLayoutMeasurer`：
  - `intrinsicContentSize(...)`：给当前主画布和缩略图复用的“紧凑内容测量”
  - `intrinsicItemSize(...)`：给后续内容驱动尺寸阶段预留的“带 minimum/inset 规则的 item 尺寸测量”
- `CanvasTextLayer` 不再维护私有 `measureText(...)`，改为复用共享 helper 做 intrinsic 测量。
- `BoardThumbnailRenderer` 也不再维护自己的私有 `measureText(...)`，改为复用同一个共享 helper。
- 新增 `CanvasTextLayoutMeasurerTests`，先锁定：
  - 字号变大时 intrinsic content size 会变大
  - item size 计算会正确加上 inset 和 minimum 约束
- 这一步刻意**没有**改变当前产品行为：
  - `shrink-to-fit` 仍然保留
  - 只是把“怎么算 intrinsic size”先统一到共享层

## 修改一：明确 `CanvasTextItem.size` 的共享契约

### 修改前

- `CanvasTextItem.size` 只是一个裸字段。
- 模型层没有在定义处说明它究竟代表“手动框尺寸”还是“共享 layout bounds”，后续阶段容易各层各自理解。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前）
// 函数名/类型名: CanvasTextItem
// 功能说明: 修改前 size 只是普通存储字段，没有在模型定义处明确内容驱动阶段需要遵守的共享几何语义。
struct CanvasTextItem {
    let id: CanvasItemID
    var text: String
    var style: CanvasTextStyle
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}
```

### 修改后

- 在 `CanvasTextItem` 定义处给 `size` 加了契约注释。
- 这一步本身不改行为，但先把后续阶段依赖的共享语义钉住：`size` 是渲染、命中、选区共用的 layout bounds。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 函数名/类型名: CanvasTextItem
// 功能说明: 修改后在模型定义处明确 size 的共享几何语义，为后续“内容决定尺寸”阶段提供统一口径。
struct CanvasTextItem {
    let id: CanvasItemID
    var text: String
    var style: CanvasTextStyle
    var center: CGPoint
    // Text size is the shared layout bounds consumed by rendering, hit-testing,
    // and selection geometry. Shared text measurement should own new text sizes
    // so every surface follows the same contract.
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}
```

## 修改二：新增共享文字测量 helper

### 修改前

- 共享层没有统一的文字 intrinsic 测量 helper。
- 主画布 `CanvasTextLayer` 和缩略图 `BoardThumbnailRenderer` 各自维护一套本地测量逻辑，后续很容易出现口径漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift（修改前）
// 函数名/类型名: CanvasTextLayoutMetrics / CanvasTextLayoutMeasurer
// 功能说明: phase 1 前共享层还没有统一的文字 intrinsic 测量 helper，主画布和缩略图各自维护自己的测量实现。
// 该文件在修改前不存在。
```

### 修改后

- 新增 `CanvasTextLayoutMetrics`，把未来内容驱动尺寸需要的 `minimumSize / horizontalInset / verticalInset` 规则集中起来。
- 新增 `CanvasTextLayoutMeasurer`，统一提供：
  - `intrinsicContentSize(...)`：当前主画布和缩略图复用的“紧凑内容测量”
  - `intrinsicItemSize(...)`：后续 phase 要用的“带 padding/minimum 的 item 尺寸测量”
- 这样后续就不需要再让每个 surface 自己复制一套 `framesetter` 测量逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayoutMeasurer.swift
// 函数名/类型名: CanvasTextLayoutMetrics / CanvasTextLayoutMeasurer
// 功能说明: 新增共享文字测量 helper，把主画布、缩略图和未来内容驱动 item 尺寸的测量口径收口到同一处。
struct CanvasTextLayoutMetrics: Hashable, Sendable {
    var minimumSize: CGSize
    var horizontalInset: CGFloat
    var verticalInset: CGFloat

    static let contentDrivenItem = CanvasTextLayoutMetrics(
        minimumSize: CGSize(width: 24, height: 20),
        horizontalInset: 12,
        verticalInset: 10
    )

    static let tightContent = CanvasTextLayoutMetrics(
        minimumSize: .zero,
        horizontalInset: 0,
        verticalInset: 0
    )
}

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

    // ... 省略 measuredSize / textParagraphStyle / textAttributes / textFont ...
}
```

## 修改三：主画布 `CanvasTextLayer` 改为复用共享 intrinsic 测量

### 修改前

- `CanvasTextLayer` 自己维护 `measureText(...)`，内部用 `NSAttributedString.boundingRect(...)` 测量 intrinsic size。
- 这导致主画布文字测量逻辑和缩略图文字测量逻辑天然分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift（修改前）
// 函数名: makeAttributedText(from:availableSize:) / fittedFont(for:availableSize:paragraphStyle:) / measureText(_:font:paragraphStyle:)
// 功能说明: 修改前 CanvasTextLayer 在渲染层内部自带一套 intrinsic 测量实现，没有复用共享 helper。
private func makeAttributedText(
    from textPayload: CanvasTextRenderPayload,
    availableSize: CGSize
) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byClipping

    let font = fittedFont(
        for: textPayload,
        availableSize: availableSize,
        paragraphStyle: paragraphStyle
    )
    // ...
}

private func fittedFont(
    for textPayload: CanvasTextRenderPayload,
    availableSize: CGSize,
    paragraphStyle: NSParagraphStyle
) -> CanvasPlatformFont {
    let baseFontSize = max(textPayload.style.fontSize * textPayload.zoomScale, 1)
    let baseFont = platformFont(
        named: textPayload.style.fontName,
        size: baseFontSize
    )
    let intrinsicSize = measureText(
        textPayload.text,
        font: baseFont,
        paragraphStyle: paragraphStyle
    )
    // ...
}

private func measureText(
    _ text: String,
    font: CanvasPlatformFont,
    paragraphStyle: NSParagraphStyle
) -> CGSize {
    let attributedText = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
    )
    return attributedText.boundingRect(
        with: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral.size
}
```

### 修改后

- `CanvasTextLayer` 继续保留当前 `fittedFont(...)` 行为，但不再自己测 intrinsic size。
- 改为复用 `CanvasTextLayoutMeasurer.intrinsicContentSize(...)`，先把测量口径统一，后续 phase 再单独移除 `shrink-to-fit`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift
// 函数名: makeAttributedText(from:availableSize:) / fittedFont(for:availableSize:)
// 功能说明: 修改后主画布保留现有 shrink-to-fit 流程，但 intrinsic size 的计算改为复用共享 CanvasTextLayoutMeasurer。
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
    let textColor = platformColor(for: textPayload.style.color)
    // ...
}

private func fittedFont(
    for textPayload: CanvasTextRenderPayload,
    availableSize: CGSize
) -> CanvasPlatformFont {
    let baseFontSize = max(textPayload.style.fontSize * textPayload.zoomScale, 1)
    let baseFont = platformFont(
        named: textPayload.style.fontName,
        size: baseFontSize
    )
    let intrinsicSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
        for: textPayload.text,
        style: textPayload.style,
        scale: textPayload.zoomScale
    )
    // ... 其余 shrink-to-fit 逻辑保持不变 ...
}
```

## 修改四：缩略图文字测量改为复用共享 helper

### 修改前

- `BoardThumbnailRenderer` 在 `fittedTextFont(...)` 里也维护了自己的 `measureText(...)`。
- 这和主画布 `CanvasTextLayer` 形成了另一套独立实现，后续内容驱动阶段非常容易主画布和缩略图不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawText(_:style:in:worldToPixelScale:context:) / fittedTextFont(for:style:availableSize:worldToPixelScale:paragraphStyle:) / measureText(_:font:paragraphStyle:)
// 功能说明: 修改前 BoardThumbnailRenderer 也自带一套 intrinsic 测量逻辑，与主画布的 CanvasTextLayer 分开维护。
private func drawText(
    _ text: String,
    style: BoardTextStyleRecord,
    in rect: CGRect,
    worldToPixelScale: CGFloat,
    context: CGContext
) {
    let paragraphStyle = textParagraphStyle()
    let font = fittedTextFont(
        for: text,
        style: style,
        availableSize: availableSize,
        worldToPixelScale: worldToPixelScale,
        paragraphStyle: paragraphStyle
    )
    // ...
}

private func fittedTextFont(
    for text: String,
    style: BoardTextStyleRecord,
    availableSize: CGSize,
    worldToPixelScale: CGFloat,
    paragraphStyle: CTParagraphStyle
) -> CTFont {
    let baseFontSize = max(CGFloat(style.fontSize) * worldToPixelScale, 1)
    let baseFont = textFont(named: style.fontName, size: baseFontSize)
    let intrinsicSize = measureText(
        text,
        font: baseFont,
        paragraphStyle: paragraphStyle
    )
    // ...
}

// ... 省略 measureText(...) ...
```

### 修改后

- `BoardThumbnailRenderer` 继续保留当前 `fittedTextFont(...)` 行为，但 intrinsic size 也改为复用共享 `CanvasTextLayoutMeasurer`。
- 这样 phase 1 之后，主画布与缩略图至少已经共用一套基础测量口径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawText(_:style:in:worldToPixelScale:context:) / fittedTextFont(for:style:availableSize:worldToPixelScale:)
// 功能说明: 修改后缩略图保留现有 shrink-to-fit 行为，但 intrinsic size 的测量改为复用共享 CanvasTextLayoutMeasurer。
private func drawText(
    _ text: String,
    style: BoardTextStyleRecord,
    in rect: CGRect,
    worldToPixelScale: CGFloat,
    context: CGContext
) {
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
    let baseFont = textFont(named: style.fontName, size: baseFontSize)
    let intrinsicSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
        for: text,
        style: style.canvasTextStyle,
        scale: worldToPixelScale
    )
    // ... 其余 shrink-to-fit 逻辑保持不变 ...
}
```

## 修改五：新增共享测量 helper 的基础测试

### 修改前

- 仓库里还没有专门锁定“共享文字测量 helper”契约的测试文件。
- 如果直接在后续 phase 扩大使用面，而没有先测 `fontSize`、`inset`、`minimumSize` 的基本约束，后面很难快速回归。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift（修改前）
// 函数名/类型名: CanvasTextLayoutMeasurerTests
// 功能说明: phase 1 前还没有专门测试共享文字 intrinsic 测量 helper 的测试文件。
// 该文件在修改前不存在。
```

### 修改后

- 新增 `CanvasTextLayoutMeasurerTests`。
- 第一条测试锁定：字号变大时 `intrinsicContentSize` 也应变大。
- 第二条测试锁定：`intrinsicItemSize` 会在内容尺寸外正确叠加 `horizontalInset / verticalInset / minimumSize`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests.swift
// 函数名: testIntrinsicContentSizeGrowsWithFontSize() / testIntrinsicItemSizeAppliesInsetsAndMinimums()
// 功能说明: 新增基础单测，先锁定共享测量 helper 的最小契约，避免后续内容驱动阶段的测量口径回退。
final class CanvasTextLayoutMeasurerTests: XCTestCase {
    func testIntrinsicContentSizeGrowsWithFontSize() {
        let smallStyle = CanvasTextStyle(fontSize: 16)
        let largeStyle = CanvasTextStyle(fontSize: 48)

        let smallSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hello",
            style: smallStyle
        )
        let largeSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hello",
            style: largeStyle
        )

        XCTAssertGreaterThan(largeSize.width, smallSize.width)
        XCTAssertGreaterThan(largeSize.height, smallSize.height)
    }

    func testIntrinsicItemSizeAppliesInsetsAndMinimums() {
        let style = CanvasTextStyle(fontSize: 18)
        let metrics = CanvasTextLayoutMetrics(
            minimumSize: CGSize(width: 120, height: 72),
            horizontalInset: 12,
            verticalInset: 10
        )

        let contentSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: "Hi",
            style: style
        )
        let itemSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "Hi",
            style: style,
            metrics: metrics
        )

        XCTAssertGreaterThanOrEqual(itemSize.width, contentSize.width + metrics.horizontalInset * 2)
        XCTAssertGreaterThanOrEqual(itemSize.height, contentSize.height + metrics.verticalInset * 2)
        XCTAssertGreaterThanOrEqual(itemSize.width, metrics.minimumSize.width)
        XCTAssertGreaterThanOrEqual(itemSize.height, metrics.minimumSize.height)
    }
}
```

## 验证情况

- `ReadLints` 检查结果：本次改动未引入新的诊断问题。
- `macOS` 定向测试通过：
  - `CanvasTextLayoutMeasurerTests`
- `iOS` 构建通过：
  - `xcodebuild -scheme "MyCanvas_Ver_0" -project ".../MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS' build`

## 当前阶段结论

- `phase 1` 已把“共享文字 intrinsic 测量契约”先立住，并把主画布/缩略图的测量口径收口到同一个 helper。
- 当前仍然保留现有 `shrink-to-fit` 行为；后续 `phase 2` 才会开始把 `text/style/size` 的写回链路真正接通。
