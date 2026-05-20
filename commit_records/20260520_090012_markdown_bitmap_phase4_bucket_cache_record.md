# 20260520_090012_markdown_bitmap_phase4_bucket_cache_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 4。
  - 本阶段目标是在不重新布局 markdown 的前提下，为主画布 markdown 内容层加入“分桶重栅格 + 双层缓存”，解决高倍 zoom 下的位图清晰度问题。
  - 本次实际改动包括：给 `CanvasMarkdownBitmapRenderer` 抽出可注入协议；让 `CanvasMarkdownContentLayer` 拥有 `layout cache` 与 `bitmap cache` 两层缓存；引入离散 `rasterScaleBucket`；补齐同 bucket 不重栅格、跨 bucket 只重栅格、返回旧 bucket 复用 bitmap 的自动化测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 4 相关变更为 `3` 个已跟踪修改文件。
  - `git diff --stat` 显示当前已跟踪变化为：`3 files changed, 332 insertions(+), 72 deletions(-)`。
  - 本阶段没有新增未跟踪文件；所有改动都落在上述 `3` 个已跟踪文件中。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
```

```bash
# 命令: git diff --stat
.../Rendering/CanvasMarkdownBitmapRenderer.swift   |   9 +-
.../Rendering/CanvasMarkdownContentLayer.swift     | 233 ++++++++++++++-------
MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift | 162 ++++++++++++++
3 files changed, 332 insertions(+), 72 deletions(-)
```

## 当前 changes 摘要

- `CanvasMarkdownContentLayer` 现在把缓存拆成两层：`layout cache key = markdownSource + style + logicalWidth`，`bitmap cache key = layoutKey + rasterScaleBucket`。
- markdown 内容层引入了离散的 upward raster bucket：`1 / 1.5 / 2 / 3 / 4 / 6 / 8 / 12 / 16 / 24`。连续 pinch 时，只要还在同一个 bucket 内，就继续复用当前 bitmap，不重栅格、不重布局。
- 当 zoom 跨过 bucket 边界时，`CanvasMarkdownContentLayer` 只会重新调用 renderer 生成 bitmap，不会重新调用 `CanvasMarkdownLayoutMeasurer.layout(...)`，因此换行、字号与 code block 面板语义不会再随着 zoom 漂移。
- `CanvasMarkdownBitmapRenderer` 被抽出 `CanvasMarkdownBitmapRendering` 协议，让内容层测试可以注入 spy renderer，精确断言“有没有真的重栅格”和“回到旧 bucket 时是否命中缓存 bitmap”。
- `CanvasMarkdownLayerTests` 新增三条阶段 4 核心回归：同 bucket 不重 layout/bitmap、跨 bucket 只重 bitmap、不跨 layout 的情况下返回旧 bucket 复用缓存位图。

## 修改一：给 bitmap renderer 抽出可注入协议

### 1.1 修改前

- `CanvasMarkdownBitmapRenderer` 只有一个具体类，没有抽象协议。
- `CanvasMarkdownContentLayer` 如果要验证“同 bucket 是否跳过重栅格”，只能依赖真实 renderer，无法在测试里直接观察 `render(layout:rasterScale:)` 的调用次数和 rasterScale 序列。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift（修改前）
// 函数名: CanvasMarkdownBitmapRenderer.render(layout:rasterScale:)
// 功能说明: 修改前只有具体 renderer 类型，没有可注入协议，内容层无法在测试里替换成 spy renderer 验证 bucket 行为。
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

        // ... 继续创建 CGContext 并输出位图
    }
}
```

### 1.2 修改后

- 新增 `CanvasMarkdownBitmapRendering` 协议。
- `CanvasMarkdownBitmapRenderer` 改为显式实现该协议，主画布运行时仍然使用真实 renderer，但测试现在可以安全注入 spy renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownBitmapRenderer.swift
// 函数名: CanvasMarkdownBitmapRendering.render(layout:rasterScale:) / CanvasMarkdownBitmapRenderer.render(layout:rasterScale:)
// 功能说明: 修改后通过协议把位图输出能力抽象出来，CanvasMarkdownContentLayer 可以在测试中注入 spy renderer，只观测重栅格行为而不依赖真实绘制实现。
protocol CanvasMarkdownBitmapRendering: AnyObject {
    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage?
}

final class CanvasMarkdownBitmapRenderer: CanvasMarkdownBitmapRendering {
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
        // ... 继续创建 CGContext 并输出位图
    }
}
```

## 修改二：在 `CanvasMarkdownContentLayer` 中加入 layout cache、bitmap cache 与 raster bucket

### 2.1 修改前

- `CanvasMarkdownContentLayer` 只有一个 `cachedLayout`，并通过 `lastAppliedMarkdownSource`、`lastAppliedStyle`、`lastAppliedLogicalWidth`、`lastAppliedRasterScale` 这组字段判断是否刷新。
- 每次 zoom 变化都会重新计算连续 `rasterScale`，只要和上次不同就直接调用 `bitmapRenderer.render(...)`。
- 这种实现虽然已经把“布局宽度”固定回了 logical width，但在连续 pinch 过程中仍然可能每次都重栅格，缺少可预测的 bucket 与位图缓存。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift（修改前）
// 函数名: update(with:contentsScale:) / makeLayout(from:) / resolvedRasterScale(markdownPayload:contentsScale:)
// 功能说明: 修改前内容层只有单份 cachedLayout 和连续 rasterScale，没有离散 bucket，也没有 layout cache / bitmap cache 的双层拆分。
final class CanvasMarkdownContentLayer: CALayer {
    private let bitmapRenderer: CanvasMarkdownBitmapRenderer
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedMarkdownSource: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedLogicalWidth: CGFloat
    private var lastAppliedRasterScale: CGFloat
    private var lastAppliedLayoutSize: CGSize
    private var cachedLayout: CanvasMarkdownLayoutResult?

    func update(
        with markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        let needsLayoutRefresh = shouldRefreshLayout(
            markdownPayload: markdownPayload
        ) || cachedLayout == nil
        if needsLayoutRefresh {
            cachedLayout = makeLayout(from: markdownPayload)
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedLogicalWidth = markdownPayload.logicalSize.width
        }

        if let cachedLayout {
            applyLayoutGeometry(cachedLayout)
            let rasterScale = resolvedRasterScale(
                markdownPayload: markdownPayload,
                contentsScale: contentsScale
            )
            if needsLayoutRefresh || lastAppliedRasterScale != rasterScale || contents == nil {
                contents = bitmapRenderer.render(
                    layout: cachedLayout,
                    rasterScale: rasterScale
                )
                lastAppliedRasterScale = rasterScale
            }
        }
    }
}
```

### 2.2 修改后

- `CanvasMarkdownContentLayer` 新增：
  - `LayoutCacheKey`
  - `RasterScaleBucket`
  - `BitmapCacheKey`
  - `layoutCache`
  - `bitmapCache`
- `update(...)` 现在先用 `LayoutCacheKey` 解析 / 复用 layout，再用 `RasterScaleBucket` 解析 bitmap key。
- 同 bucket 内只要 `activeBitmapKey` 不变，就完全跳过新的 `render(...)` 调用；跨 bucket 时只更新 bitmap，不重新布局。
- 为了让测试能注入自定义 layoutProvider，这里还把 `defaultLayout(for:)` 收口成了 `nonisolated` 静态方法，并把 `LayoutProvider` 作为内容层内部的可注入类型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名: LayoutCacheKey.init(markdownPayload:) / RasterScaleBucket.cgFloatScale / BitmapCacheKey（类型定义）
// 功能说明: 修改后内容层先把“语义布局”和“位图清晰度”拆成两个维度的 key，layout cache key 只绑定 markdownSource、style、logicalWidth；bitmap cache key 再叠加 raster bucket。
final class CanvasMarkdownContentLayer: CALayer {
    typealias LayoutProvider = (CanvasMarkdownRenderPayload) -> CanvasMarkdownLayoutResult

    private static let rasterScaleBuckets: [CGFloat] = [
        1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24
    ]

    private struct LayoutCacheKey: Hashable {
        let markdownSource: String
        let fontName: String
        let fontSize: Double
        let colorRed: Double
        let colorGreen: Double
        let colorBlue: Double
        let colorAlpha: Double
        let logicalWidth: Double

        init(markdownPayload: CanvasMarkdownRenderPayload) {
            markdownSource = markdownPayload.markdownSource
            fontName = markdownPayload.style.fontName
            fontSize = Double(markdownPayload.style.fontSize)
            colorRed = Double(markdownPayload.style.color.red)
            colorGreen = Double(markdownPayload.style.color.green)
            colorBlue = Double(markdownPayload.style.color.blue)
            colorAlpha = Double(markdownPayload.style.color.alpha)
            logicalWidth = Double(markdownPayload.logicalSize.width)
        }
    }

    private struct RasterScaleBucket: Hashable {
        let scale: Double

        var cgFloatScale: CGFloat {
            CGFloat(scale)
        }
    }

    private struct BitmapCacheKey: Hashable {
        let layoutKey: LayoutCacheKey
        let rasterScaleBucket: RasterScaleBucket
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownContentLayer.swift
// 函数名: update(with:contentsScale:) / resolvedLayout(for:layoutKey:) / applyBitmapIfNeeded(for:layoutKey:rasterScaleBucket:) / resolvedRasterScaleBucket(markdownPayload:contentsScale:)
// 功能说明: 修改后内容层先命中 layout cache，再决定 raster bucket；同 bucket 内只复用 bitmap，跨 bucket 才重栅格，而且不会重新调用 layoutProvider。
func update(
    with markdownPayload: CanvasMarkdownRenderPayload,
    contentsScale: CGFloat
) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    if lastAppliedContentsScale != contentsScale {
        self.contentsScale = contentsScale
        lastAppliedContentsScale = contentsScale
    }

    let layoutKey = LayoutCacheKey(markdownPayload: markdownPayload)
    let layout = resolvedLayout(
        for: markdownPayload,
        layoutKey: layoutKey
    )
    applyLayoutGeometry(layout)

    let rasterScaleBucket = resolvedRasterScaleBucket(
        markdownPayload: markdownPayload,
        contentsScale: contentsScale
    )
    applyBitmapIfNeeded(
        for: layout,
        layoutKey: layoutKey,
        rasterScaleBucket: rasterScaleBucket
    )

    CATransaction.commit()
}

nonisolated private static func defaultLayout(
    for markdownPayload: CanvasMarkdownRenderPayload
) -> CanvasMarkdownLayoutResult {
    CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: markdownPayload.markdownSource,
        style: markdownPayload.style,
        maxLayoutWidth: markdownPayload.logicalSize.width,
        scale: 1,
        includeCompatibilityCodeBlockBackgrounds: false
    )
}

private func resolvedLayout(
    for markdownPayload: CanvasMarkdownRenderPayload,
    layoutKey: LayoutCacheKey
) -> CanvasMarkdownLayoutResult {
    if activeLayoutKey == layoutKey, let activeLayout {
        return activeLayout
    }

    if let cachedLayout = layoutCache[layoutKey] {
        activeLayoutKey = layoutKey
        activeLayout = cachedLayout
        return cachedLayout
    }

    let resolvedLayout = layoutProvider(markdownPayload)
    layoutCache[layoutKey] = resolvedLayout
    activeLayoutKey = layoutKey
    activeLayout = resolvedLayout
    return resolvedLayout
}

private func applyBitmapIfNeeded(
    for layout: CanvasMarkdownLayoutResult,
    layoutKey: LayoutCacheKey,
    rasterScaleBucket: RasterScaleBucket
) {
    let bitmapKey = BitmapCacheKey(
        layoutKey: layoutKey,
        rasterScaleBucket: rasterScaleBucket
    )
    guard activeBitmapKey != bitmapKey || contents == nil else {
        return
    }

    if let cachedImage = bitmapCache[bitmapKey] {
        contents = cachedImage
        activeBitmapKey = bitmapKey
        return
    }

    let renderedImage = bitmapRenderer.render(
        layout: layout,
        rasterScale: rasterScaleBucket.cgFloatScale
    )
    contents = renderedImage
    if let renderedImage {
        bitmapCache[bitmapKey] = renderedImage
        activeBitmapKey = bitmapKey
    } else {
        activeBitmapKey = nil
    }
}

private func resolvedRasterScaleBucket(
    markdownPayload: CanvasMarkdownRenderPayload,
    contentsScale: CGFloat
) -> RasterScaleBucket {
    let resolvedContentsScale =
        contentsScale.isFinite && contentsScale > 0 ? contentsScale : 1
    let resolvedZoomScale =
        markdownPayload.cameraZoomScale.isFinite && markdownPayload.cameraZoomScale > 0
        ? markdownPayload.cameraZoomScale
        : 1
    let requestedRasterScale = max(
        resolvedContentsScale * resolvedZoomScale,
        1
    )
    let bucketScale =
        Self.rasterScaleBuckets.first(where: { requestedRasterScale <= $0 })
        ?? max(
            ceil(requestedRasterScale),
            Self.rasterScaleBuckets.last ?? 1
        )
    return RasterScaleBucket(scale: Double(bucketScale))
}
```

## 修改三：补齐 raster bucket 与 bitmap cache 的定向回归

### 3.1 修改前

- `CanvasMarkdownLayerTests` 只验证了：
  - `ItemLayer` 使用逻辑容器尺寸和外层 zoom transform
  - 改宽触发重排
  - 只改高或改 zoom 时逻辑布局尺寸不变
- 但还没有自动化覆盖“同 bucket 不重栅格、跨 bucket 只重栅格、回到旧 bucket 复用 bitmap”这几个阶段 4 的关键验收点。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前）
// 函数名: testContentLayerKeepsLogicalLayoutSizeWhenOnlyHeightOrZoomChanges()
// 功能说明: 修改前测试只锁住“只改高或 zoom 不改 layout 结果”，但不能区分是否发生了额外的 render(layout:rasterScale:) 调用。
func testContentLayerKeepsLogicalLayoutSizeWhenOnlyHeightOrZoomChanges() throws {
    let itemID = CanvasItemID()
    let layer = CanvasMarkdownItemLayer(itemID: itemID)
    let compactPayload = CanvasMarkdownRenderPayload(
        markdownSource: """
        ## Title

        Body with `code`
        """,
        style: CanvasTextStyle(fontSize: 18),
        logicalSize: CGSize(width: 220, height: 80),
        cameraZoomScale: 1
    )

    // ... 验证 layout 尺寸稳定、zoom 后像素尺寸增大
}
```

### 3.2 修改后

- 新增 `CanvasMarkdownBitmapRendererSpy`，通过协议注入记录 `rasterScales`，不需要依赖真实 renderer 也能验证 bucket 行为。
- 新增三条测试：
  - `testContentLayerSkipsLayoutAndBitmapRefreshWithinSameRasterBucket()`
  - `testContentLayerCrossingRasterBucketRerendersWithoutRelayout()`
  - `testContentLayerReusesCachedBitmapWhenReturningToPreviousRasterBucket()`
- 同时补了 `makeMarkdownContentPayload(...)` 和本地测试 `CGImage` helper，方便稳定构造 bucket case。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: testContentLayerSkipsLayoutAndBitmapRefreshWithinSameRasterBucket() / testContentLayerCrossingRasterBucketRerendersWithoutRelayout() / testContentLayerReusesCachedBitmapWhenReturningToPreviousRasterBucket()
// 功能说明: 修改后测试直接断言 layoutProvider 调用次数与 renderer.rasterScales 序列，分别锁定“同 bucket 不重栅格、跨 bucket 只重栅格、回到旧 bucket 复用 bitmap”。
func testContentLayerSkipsLayoutAndBitmapRefreshWithinSameRasterBucket() throws {
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
    let firstPayload = makeMarkdownContentPayload(cameraZoomScale: 1.1)
    let secondPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)

    layer.update(with: firstPayload, contentsScale: 1)
    layer.update(with: secondPayload, contentsScale: 1)

    XCTAssertEqual(layoutInvocationCount, 1)
    XCTAssertEqual(renderer.rasterScales, [1.5])
}

func testContentLayerCrossingRasterBucketRerendersWithoutRelayout() throws {
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
    let firstPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)
    let secondPayload = makeMarkdownContentPayload(cameraZoomScale: 1.6)

    layer.update(with: firstPayload, contentsScale: 1)
    layer.update(with: secondPayload, contentsScale: 1)

    XCTAssertEqual(layoutInvocationCount, 1)
    XCTAssertEqual(renderer.rasterScales, [1.5, 2])
}

func testContentLayerReusesCachedBitmapWhenReturningToPreviousRasterBucket() throws {
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
    let initialPayload = makeMarkdownContentPayload(cameraZoomScale: 1.4)
    let higherBucketPayload = makeMarkdownContentPayload(cameraZoomScale: 1.6)
    let returnPayload = makeMarkdownContentPayload(cameraZoomScale: 1.3)

    layer.update(with: initialPayload, contentsScale: 1)
    layer.update(with: higherBucketPayload, contentsScale: 1)
    layer.update(with: returnPayload, contentsScale: 1)

    XCTAssertEqual(layoutInvocationCount, 1)
    XCTAssertEqual(renderer.rasterScales, [1.5, 2])
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: CanvasMarkdownBitmapRendererSpy.render(layout:rasterScale:) / makeMarkdownContentPayload(markdownSource:logicalWidth:logicalHeight:cameraZoomScale:)
// 功能说明: 修改后测试通过 spy renderer 记录 rasterScale，并通过 helper 快速构造不同 zoom 的 payload，确保 bucket 测试不依赖真实绘制成本。
private func makeMarkdownContentPayload(
    markdownSource: String = """
    ## Title

    Body with `code`
    """,
    logicalWidth: CGFloat = 220,
    logicalHeight: CGFloat = 120,
    cameraZoomScale: CGFloat
) -> CanvasMarkdownRenderPayload {
    CanvasMarkdownRenderPayload(
        markdownSource: markdownSource,
        style: CanvasTextStyle(fontSize: 18),
        logicalSize: CGSize(width: logicalWidth, height: logicalHeight),
        cameraZoomScale: cameraZoomScale
    )
}

private final class CanvasMarkdownBitmapRendererSpy: CanvasMarkdownBitmapRendering {
    private(set) var rasterScales: [CGFloat] = []

    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        rasterScales.append(rasterScale)
        return makeMarkdownLayerTestImage(
            pixelWidth: Int(ceil(layout.contentSize.width * rasterScale)),
            pixelHeight: Int(ceil(layout.contentSize.height * rasterScale))
        )
    }
}
```

## 验证记录

- 本次已检查阶段 4 改动文件，没有新增 linter 问题。
- 第一轮阶段 4 回归里，`CanvasMarkdownContentLayer` 的可注入 `LayoutProvider` 触发了访问级别约束；随后在当前 changes 中把 `LayoutProvider` 改为内容层内部可见的 `typealias`，并把 `defaultLayout(for:)` 调整为 `nonisolated`，消除了这一轮编译阻塞。
- 修正后重新执行 macOS 定向回归和 iOS simulator 构建，全部通过。

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownContractTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests' -only-testing:'MyCanvas_Ver_0Tests/MarkdownPreviewParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests'
Testing failed:
Initializer must be declared private because its parameter uses a private type
```

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownContractTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasMarkdownBitmapRendererTests' -only-testing:'MyCanvas_Ver_0Tests/MarkdownPreviewParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests' -only-testing:'MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests'
** TEST SUCCEEDED **
Test case 'CanvasMarkdownLayerTests.testContentLayerCrossingRasterBucketRerendersWithoutRelayout()' passed
Test case 'CanvasMarkdownLayerTests.testContentLayerReusesCachedBitmapWhenReturningToPreviousRasterBucket()' passed
Test case 'CanvasMarkdownLayerTests.testContentLayerSkipsLayoutAndBitmapRefreshWithinSameRasterBucket()' passed
Test case 'MarkdownPreviewParityTests.testBoardThumbnailRendererKeepsEmptyCodeBlockPanelVisibleInThumbnail()' passed
Test case 'CanvasMarkdownContractTests.testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()' passed
Test case 'CanvasMarkdownBitmapRendererTests.testRenderDrawsCodeBlockDecorationWhenCompatibilityBackgroundsDisabled()' passed
```

```bash
# 命令: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'
** BUILD SUCCEEDED **
```

## 结论

- 本次阶段 4 已经把 markdown 主画布内容层从“只有连续 rasterScale 的单次位图更新”推进到“layout cache + bitmap cache + raster bucket”的稳定链路。
- 到这一阶段为止，markdown 的语义布局仍然严格绑定 `markdownSource + style + logicalWidth`；连续 pinch 时，只要还处在同一个 bucket 内，就不会重新跑 layout，也不会重新 raster。
- 高倍 zoom 下的清晰度现在可以通过跨 bucket 的重栅格逐步提升，而不会重新引入阶段 3 刚切断的“zoom 参与 markdown 语义布局”的问题。
