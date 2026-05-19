# 20260519_212726_markdown_bitmap_phase2_thumbnail_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 2。
  - 本阶段目标是先把“`CanvasMarkdownLayoutResult` -> 自定义绘制 -> `CGImage`”跑通，并且只先接到 board thumbnail 路径，不提前切主画布 layer。
  - 本次实际改动包括：新增共享 `CanvasMarkdownBitmapRenderer`；让 `BoardThumbnailRenderer.drawMarkdownItem(...)` 改走 shared bitmap renderer；补充 markdown bitmap renderer 自测与 thumbnail 集成测试；修复新增测试在 XCTest 生命周期中的一次 `abort()` 崩溃。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests.swift`
  - `MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 2 相关变更为 `2` 个已跟踪修改文件和 `2` 个未跟踪新增文件。
  - `git diff --stat` 显示已跟踪文件的变化为：`2 files changed, 80 insertions(+), 7 deletions(-)`。
  - 由于 `CanvasMarkdownBitmapRenderer.swift` 与 `CanvasMarkdownBitmapRendererTests.swift` 都是新增未跟踪文件，它们不会出现在这条 `git diff --stat` 输出里，但已经出现在 `git status --short` 中。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
 M MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift
?? MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests.swift
```

```bash
# 命令: git diff --stat -- MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
 .../Shared/BoardList/BoardThumbnailRenderer.swift  | 60 +++++++++++++++++++---
 .../MarkdownPreviewParityTests.swift               | 27 ++++++++++
 2 files changed, 80 insertions(+), 7 deletions(-)
```

## 当前 changes 摘要

- 新增 `CanvasMarkdownBitmapRenderer`，把 markdown 从“直接在外部 CGContext 里画富文本”升级为“先画 decorations，再画 attributed text，最终输出 `CGImage`”的共享位图渲染器。
- `BoardThumbnailRenderer` 现在通过依赖注入持有 `markdownBitmapRenderer`，并在 `drawMarkdownItem(...)` 中关闭 fenced code block 的 compatibility background，优先使用阶段 1 的 decoration 语义生成位图后再绘制到 thumbnail。
- `BoardThumbnailRenderer` 新增了 `drawBitmapImage(...)`，沿用与现有 `drawPosterBackedImage(...)` 一致的本地 y 方向补偿，保证 `CGImage` 在 thumbnail 已翻转为 y-down 的上下文里不会倒置。
- `MarkdownPreviewParityTests` 新增“空 fenced code block 仍然能在 thumbnail 中看到 panel”的集成测试，证明 thumbnail 已真正接到 decoration 驱动的 shared bitmap 路径。
- 新增 `CanvasMarkdownBitmapRendererTests` 验证 shared renderer 的像素尺寸与 decoration 输出，但第一轮测试触发了 XCTest 生命周期里的 `abort()`；随后在测试里补了静态 retainer，最终回归全部通过。

## 修改一：新增共享 `CanvasMarkdownBitmapRenderer`

### 1.1 修改前

- 修改前没有共享的 markdown bitmap renderer。
- `BoardThumbnailRenderer` 和未来主画布都只能各自消费 `attributedText`，还没有“同一份布局结果统一栅格化”的共享实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift（修改前）
// 函数名: 新文件（修改前不存在）
// 功能说明: 修改前没有共享的 markdown 位图渲染器文件，布局结果无法直接转成复用的 CGImage。
// 无此文件
```

### 1.2 修改后

- 新增 `CanvasMarkdownBitmapRenderer.render(layout:rasterScale:)`。
- 渲染顺序固定为“先画 decorations，再画 attributed text”，并直接返回 `CGImage`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift
// 函数名: render(layout:rasterScale:)
// 功能说明: 修改后共享 renderer 接收语义布局结果，先栅格化 decoration，再叠加文本，最终产出 CGImage 给 thumbnail 等调用方复用。
final class CanvasMarkdownBitmapRenderer {
    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        guard
            rasterScale.isFinite,
            rasterScale > 0,
            layout.contentSize.width.isFinite,
            layout.contentSize.height.isFinite,
            layout.contentSize.width > 0,
            layout.contentSize.height > 0
        else {
            return nil
        }

        let pixelSize = CGSize(
            width: ceil(layout.contentSize.width * rasterScale),
            height: ceil(layout.contentSize.height * rasterScale)
        )
        guard
            pixelSize.width > 0,
            pixelSize.height > 0,
            let context = CGContext(
                data: nil,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        prepareContext(
            context,
            layoutSize: layout.contentSize,
            pixelSize: pixelSize,
            rasterScale: rasterScale
        )
        drawDecorations(layout.decorations, in: context)
        drawAttributedText(
            layout.attributedText,
            in: CGRect(origin: .zero, size: layout.contentSize),
            context: context
        )
        return context.makeImage()
    }
}
```

## 修改二：让 `BoardThumbnailRenderer` 先接入 shared bitmap renderer

### 2.1 修改前

- `BoardThumbnailRenderer` 只有 `geometryPreviewBuilder` 和 `mediaPosterImageResolver` 两个依赖。
- `drawMarkdownItem(...)` 里直接调用 `CanvasMarkdownLayoutMeasurer.layout(...)` 得到 `attributedText`，然后用 `drawAttributedText(...)` 直接画到 thumbnail 的 CGContext。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: BoardThumbnailRenderer.init(...)
// 功能说明: 修改前 thumbnail renderer 并不知道共享 markdown bitmap renderer 的存在，markdown 仍然走直接富文本绘制路径。
final class BoardThumbnailRenderer {
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver

    init(
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver()
    ) {
        self.geometryPreviewBuilder = geometryPreviewBuilder
        self.mediaPosterImageResolver = mediaPosterImageResolver
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawMarkdownItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改前 markdown thumbnail 直接画 attributed text，无法验证 decoration 与文本的统一位图输出。
let layout = CanvasMarkdownLayoutMeasurer.layout(
    markdownSource: itemRecord.markdownSource,
    style: itemRecord.style.canvasTextStyle,
    maxLayoutWidth: mappedVisibleSize.width,
    scale: geometry.scale
)

context.saveGState()
context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
context.rotate(by: rotationRadians)
context.clip(to: textRect)
drawAttributedText(
    layout.attributedText,
    in: textRect,
    context: context
)
context.restoreGState()
```

### 2.2 修改后

- `BoardThumbnailRenderer` 新增 `markdownBitmapRenderer` 依赖。
- `drawMarkdownItem(...)` 先用 `includeCompatibilityCodeBlockBackgrounds: false` 生成语义布局，再通过 shared bitmap renderer 得到 `CGImage`，最后绘制进 thumbnail；只有在 `CGImage` 生成失败时才回退到旧的 `drawAttributedText(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: BoardThumbnailRenderer.init(...)
// 功能说明: 修改后 thumbnail renderer 显式持有 markdownBitmapRenderer，让 markdown 缩略图可以走共享位图渲染路径。
final class BoardThumbnailRenderer {
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let markdownBitmapRenderer: CanvasMarkdownBitmapRenderer

    init(
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
        markdownBitmapRenderer: CanvasMarkdownBitmapRenderer = CanvasMarkdownBitmapRenderer()
    ) {
        self.geometryPreviewBuilder = geometryPreviewBuilder
        self.mediaPosterImageResolver = mediaPosterImageResolver
        self.markdownBitmapRenderer = markdownBitmapRenderer
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawMarkdownItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改后 markdown thumbnail 先关闭 fenced code block 的 compatibility background，再走 shared bitmap renderer 输出位图；失败时保留原有富文本回退链路。
let layout = CanvasMarkdownLayoutMeasurer.layout(
    markdownSource: itemRecord.markdownSource,
    style: itemRecord.style.canvasTextStyle,
    maxLayoutWidth: mappedVisibleSize.width,
    scale: geometry.scale,
    // Stage 2 validates markdown bitmap rendering through thumbnails, so
    // fenced code block panels now come from semantic decorations here.
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

context.saveGState()
context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
context.rotate(by: rotationRadians)
context.clip(to: textRect)
if let bitmapImage {
    drawBitmapImage(
        bitmapImage,
        in: imageRect,
        context: context
    )
} else {
    drawAttributedText(
        layout.attributedText,
        in: textRect,
        context: context
    )
}
context.restoreGState()
```

## 修改三：为 thumbnail 新增本地 `CGImage` 绘制 helper

### 3.1 修改前

- 修改前 thumbnail 内部只有 `drawPosterBackedImage(...)` 这类针对图片/手绘 poster 的 `CGImage` 绘制逻辑。
- markdown 没有自己的位图绘制 helper。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawPosterBackedImage(_:layout:in:clipPath:)
// 功能说明: 修改前只有 poster image 的本地 y 方向补偿逻辑，markdown 还没有位图绘制入口。
private func drawPosterBackedImage(
    _ image: CGImage,
    layout: PosterBackedThumbnailLayout,
    in context: CGContext,
    clipPath: CGPath?
) {
    context.saveGState()
    context.translateBy(x: layout.mappedCenter.x, y: layout.mappedCenter.y)
    context.rotate(by: layout.rotationRadians)
    if let clipPath {
        context.addPath(clipPath)
        context.clip()
    } else {
        context.clip(to: layout.visibleRect)
    }
    context.saveGState()
    context.translateBy(x: layout.fullImageRect.minX, y: layout.fullImageRect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(
        image,
        in: CGRect(origin: .zero, size: layout.fullImageRect.size)
    )
    context.restoreGState()
    context.restoreGState()
}
```

### 3.2 修改后

- 新增 `drawBitmapImage(...)`，让 markdown bitmap 在 thumbnail 已经 flipped 成 y-down 的上下文里也能按正确方向绘制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawBitmapImage(_:in:context:)
// 功能说明: 修改后 markdown bitmap 会复用与 poster image 同类的本地 y 方向补偿，避免 CGImage 在 thumbnail 中上下颠倒。
private func drawBitmapImage(
    _ image: CGImage,
    in rect: CGRect,
    context: CGContext
) {
    guard rect.width > 0, rect.height > 0 else {
        return
    }

    context.saveGState()
    // `CGImage` drawing still uses Quartz's native y-up sampling, so
    // compensate locally after the thumbnail surface has already been
    // flipped into y-down.
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(
        image,
        in: CGRect(origin: .zero, size: rect.size)
    )
    context.restoreGState()
}
```

## 修改四：补齐 thumbnail parity 集成测试

### 4.1 修改前

- `MarkdownPreviewParityTests` 只验证“普通 markdown board thumbnail 有可见像素”，还没有覆盖 fenced code block panel 的特殊场景。

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift（修改前）
// 函数名: testBoardThumbnailRendererRendersVisibleMarkdownThumbnail()
// 功能说明: 修改前只验证普通 markdown 内容在 thumbnail 里可见，还没有验证 decoration 驱动的 code block panel。
func testBoardThumbnailRendererRendersVisibleMarkdownThumbnail() throws {
    let markdownItem = makeMarkdownPreviewTestItem(
        markdownSource: """
        # Heading

        A longer markdown paragraph that should remain visible in board thumbnails.

        - First
        - Second
        """,
        center: CGPoint(x: 160, y: 120),
        size: CGSize(width: 260, height: 180),
        zIndex: 1
    )
    let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
    let renderer = BoardThumbnailRenderer()
    MarkdownPreviewParityTestRetainer.thumbnailRenderers.append(renderer)

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

- 新增 `testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()`。
- 这个 case 用“空 fenced code block”来验证：即使没有正文内容，thumbnail 仍然能通过 decoration 画出 panel，而不是完全依赖文字像素。

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
// 函数名: testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()
// 功能说明: 修改后新增空 fenced code block 场景，验证 thumbnail 已接到 decoration 驱动的 markdown bitmap 路径。
func testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail() throws {
    let markdownItem = makeMarkdownPreviewTestItem(
        markdownSource: """
        ```

        ```
        """,
        center: CGPoint(x: 160, y: 120),
        size: CGSize(width: 260, height: 180),
        zIndex: 1
    )
    let runtimeState = makeMarkdownPreviewRuntimeState(item: markdownItem)
    let renderer = BoardThumbnailRenderer()
    MarkdownPreviewParityTestRetainer.thumbnailRenderers.append(renderer)

    let renderedImage = try XCTUnwrap(
        renderer.renderPersistedThumbnail(
            for: runtimeState,
            maximumLongestSide: 256
        )
    )
    XCTAssertTrue(
        imageContainsVisiblePixels(renderedImage),
        "Expected empty fenced code block to remain visible via markdown decorations in the thumbnail."
    )
}
```

## 修改五：新增 shared bitmap renderer 自测，并修复测试生命周期崩溃

### 5.1 修改前

- 修改前没有 `CanvasMarkdownBitmapRendererTests.swift`。
- 因此 shared renderer 的像素尺寸、decoration 渲染和 `CGImage` 结果都没有独立测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests.swift（修改前）
// 函数名: 新文件（修改前不存在）
// 功能说明: 修改前没有 shared markdown bitmap renderer 的专门测试文件。
// 无此文件
```

### 5.2 修改后

- 新增 `CanvasMarkdownBitmapRendererTests`，覆盖：
  - `render(layout:rasterScale:)` 的像素尺寸是否与 `layout.contentSize * rasterScale` 一致；
  - 在 `includeCompatibilityCodeBlockBackgrounds: false` 时，decoration 是否仍会写进 bitmap。
- 第一轮运行时，这个新测试文件在 XCTest 生命周期里触发了 `abort()`；随后补了静态 retainer，固定住 `renderer`、`layout` 和 `CGImage` 的生命周期，最终测试稳定通过。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests.swift
// 函数名: testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize(), testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()
// 功能说明: 修改后 shared bitmap renderer 有了独立自测，既验证像素尺寸，也验证 decoration 在关闭 compatibility background 后仍会被画进最终位图。
@MainActor
final class CanvasMarkdownBitmapRendererTests: XCTestCase {
    func testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize() throws {
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            # Title

            Body
            """,
            style: CanvasTextStyle(fontSize: 18),
            maxLayoutWidth: 160
        )
        let renderer = CanvasMarkdownBitmapRenderer()
        CanvasMarkdownBitmapRendererTestRetainer.renderers.append(renderer)
        CanvasMarkdownBitmapRendererTestRetainer.layouts.append(layout)
        let rasterScale: CGFloat = 2

        let image = try XCTUnwrap(
            renderer.render(
                layout: layout,
                rasterScale: rasterScale
            )
        )
        CanvasMarkdownBitmapRendererTestRetainer.images.append(image)

        XCTAssertEqual(image.width, Int(ceil(layout.contentSize.width * rasterScale)))
        XCTAssertEqual(image.height, Int(ceil(layout.contentSize.height * rasterScale)))
    }

    func testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled() throws {
        let layout = CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: """
            ```

            ```
            """,
            style: CanvasTextStyle(fontSize: 20),
            maxLayoutWidth: 180,
            includeCompatibilityCodeBlockBackgrounds: false
        )
        let decoration = try XCTUnwrap(layout.decorations.first)
        let renderer = CanvasMarkdownBitmapRenderer()
        CanvasMarkdownBitmapRendererTestRetainer.renderers.append(renderer)
        CanvasMarkdownBitmapRendererTestRetainer.layouts.append(layout)
        let image = try XCTUnwrap(
            renderer.render(
                layout: layout,
                rasterScale: 1
            )
        )
        CanvasMarkdownBitmapRendererTestRetainer.images.append(image)

        XCTAssertNotNil(decoration.rect.integral)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests.swift
// 函数名: CanvasMarkdownBitmapRendererTestRetainer
// 功能说明: 修改后新增静态 retainer，避免新测试在 XCTest 释放期触发 abort()；这次修正只影响测试稳定性，不改变阶段2业务逻辑。
private enum CanvasMarkdownBitmapRendererTestRetainer {
    static var renderers: [CanvasMarkdownBitmapRenderer] = []
    static var layouts: [CanvasMarkdownLayoutResult] = []
    static var images: [CGImage] = []
}
```

## 验证记录

- 本次已检查阶段 2 改动文件，没有新增 linter 问题。
- 第一轮完整回归中，业务链路相关测试均通过，但新加的 `CanvasMarkdownBitmapRendererTests` 两条用例在 XCTest 生命周期里触发了 `abort()`。
- 加入静态 retainer 后，重新执行 shared renderer 自测和完整阶段 2 回归，全部通过。

```bash
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests"
** TEST FAILED **
Test case 'CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()' failed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize()' failed
```

```bash
# 命令: xcrun xcresulttool get --legacy --format json --path "<xcresult>"
"Crash: MyCanvas_Ver_0 at CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled(). libsystem_c.dylib: abort() called"
"Crash: MyCanvas_Ver_0 at CanvasMarkdownBitmapRendererTests.testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize(). libsystem_c.dylib: abort() called"
```

```bash
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests"
** TEST SUCCEEDED **
Test case 'CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()' passed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize()' passed
```

```bash
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests" -only-testing:"MyCanvas_Ver_0Tests/MarkdownPreviewParityTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownContractTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo" -only-testing:"MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests/testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry"
** TEST SUCCEEDED **
Test case 'CanvasMarkdownLayoutMeasurerTests.testCodeBlockDecorationPaddingClampsToMinimumAndMaximumBounds()' passed
Test case 'MarkdownPreviewParityTests.testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()' passed
Test case 'MarkdownPreviewParityTests.testBoardThumbnailRendererRendersVisibleMarkdownThumbnail()' passed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()' passed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderUsesLayoutContentSizeAndRasterScaleForPixelSize()' passed
Test case 'CanvasMarkdownContractTests.testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()' passed
Test case 'CanvasCommandPolicyParityTests.testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()' passed
```

## 结论

- 本次阶段 2 已经把 markdown 从“语义布局结果”推进到了“共享位图输出”，并先在 thumbnail 这条低风险链路上验证了 decorations 与文字统一成像的效果。
- 到这一阶段为止，主画布仍然保持现状；但 thumbnail 已经证明：fenced code block panel 可以脱离 `NSAttributedString.backgroundColor` 的主依赖，通过共享 bitmap renderer 稳定落图。
