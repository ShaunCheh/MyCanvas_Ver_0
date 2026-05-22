# 20260522_145528_CST_hand_drawing_scheme2_phase6_render_graph_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 6`，把 realtime、committed、preview 以及 tool geometry 共同依赖的渲染输入语义收口成统一 render graph。
  - 让 `HandDrawingStrokeRasterizer` 从“默认唯一渲染语义承载者”退化为“CPU backend 实现之一”。
  - 保持 `preview / export / persistence` 继续以 CPU/document 为真相源，不在本阶段切换 canonical preview。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift`
- 如实说明：
  - 当前工作区中的部分 tracked 文件已经承载了 `phase 5 + phase 6` 的叠加修改，因此下面的“修改前”指的是 `phase 6` 开始前、`phase 5` 已完成但尚未提交时的工作区状态。
  - 本记录不重复展开 `phase 5` 已记录过的 committed backend 抽象，只记录本轮继续推进到 render graph 的部分。
- 本记录不包含：
  - `phase 7` 的方案二收口与 go/no-go 判定。
  - preview/export 的 GPU 真相切换。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统 date 命令生成本次 phase 6 记录文件的时间戳前缀。
20260522_145528_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 汇总当前 tracked diff 中与 phase 6 直接相关的修改统计；新增的 render graph 文件与测试文件会在后面的 current changes 中体现。
.../Editing/HandDrawingStrokeGeometry.swift        | 18 ++---
.../Rendering/HandDrawingCanvasRenderer.swift      | 20 +++---
.../HandDrawingGPUCommittedCanvasBackend.swift     | 80 ++++------------------
.../Rendering/HandDrawingPreviewRenderer.swift     | 46 +++++--------
.../Rendering/HandDrawingRenderingContracts.swift  | 26 ++++++-
.../Rendering/HandDrawingStrokeRasterizer.swift    | 49 ++++++-------
.../UI/HandDrawingCanvasSurfaceView.swift          | 59 ++++++++--------
.../HandDrawingRenderingContractsTests.swift       | 18 +++++
8 files changed, 141 insertions(+), 175 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 记录生成本文件时，与本次 phase 6 直接对应的 current changes；其中 render graph 主文件和测试文件为新增未跟踪文件。
 M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
 M MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift
?? MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests.swift
```

## 当前 changes 摘要

- 新增 `HandDrawingRenderGraph.swift`，统一定义：
  - `HandDrawingStrokeRenderSnapshot`
  - `HandDrawingResolvedErasePath`
  - `HandDrawingRenderGraph`
  - `HandDrawingRenderGraphBuilder`
  - `HandDrawingCPURenderGraphRenderer`
- `HandDrawingStrokeRasterizer.swift` 不再自己决定“如何从原始 stroke 推导整套渲染语义”，而是直接消费 snapshot。
- `HandDrawingPreviewRenderer.swift`、`HandDrawingCanvasRenderer.swift`、`HandDrawingGPUCommittedCanvasBackend.swift` 全部切到同一套 graph 输入。
- `HandDrawingStrokeGeometry.swift` 改成基于同一份 snapshot 做命中与 enclosure 判断，避免 tool graph 与 render graph 分叉。
- `HandDrawingRenderingContracts.swift` 与 `HandDrawingCanvasSurfaceView.swift` 让 realtime draft 也显式暴露 `renderSnapshots`，统一 CPU/GPU draft host 的输入。
- 新增 `HandDrawingRenderGraphTests.swift`，并补 `HandDrawingRenderingContractsTests.swift` 中与 realtime snapshot 相关的断言。
- 实现过程中额外修正了一个真正的根因问题：
  - 离屏 stroke image 上下文被重复做 display coordinate flip
  - 导致 preview / canvas / document loader 多组测试整体上下颠倒
  - 最终在 `HandDrawingCPURenderGraphRenderer.makeImage(...)` 中移除了那层多余翻转

## 修改一：新增统一 render graph / stroke snapshot / CPU graph renderer

### 修改前

- 项目里不存在统一 render graph 文件。
- 渲染输入语义散落在多个调用方：
  - preview 自己按 stroke 循环
  - committed canvas 自己按 stroke 循环
  - geometry 自己重新算 `resolvedStamps`
  - realtime host 直接拿 `resolvedStamps + color`
- 这意味着同一份 `resolved stamp / erase mask / layer order / render region / paper transform` 语义，没有一个统一的 renderer-agnostic 承载层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift（修改前）
// 函数名: 无
// 功能说明: phase 6 之前项目中不存在统一 render graph / stroke snapshot / CPU graph renderer 文件。
// 本文件不存在。
```

### 修改后

- 新增 `HandDrawingStrokeRenderSnapshot`，把单 stroke 的颜色、resolved stamps、resolved erase paths、bounds 显式化。
- 新增 `HandDrawingRenderGraph` 与 `HandDrawingRenderGraphLayer`，把 layer order、paper size、paper transform、render region 收口成一份统一输入。
- 新增 `HandDrawingRenderGraphBuilder`，负责从 document 或单根 stroke 生成统一 snapshot / graph。
- 新增 `HandDrawingCPURenderGraphRenderer`，作为统一 CPU graph renderer，供 preview、committed CPU、GPU committed 的离屏 canonical stroke image 复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift
// 函数名: HandDrawingStrokeRenderSnapshot / HandDrawingRenderGraph / HandDrawingRenderGraphBuilder.graph(...) / HandDrawingCPURenderGraphRenderer.makeImage(...)
// 功能说明: phase 6 新增统一 render graph 层，把 resolved stamps、erase paths、layer order、render region、paper transform 收口成 renderer-agnostic 输入。
struct HandDrawingStrokeRenderSnapshot: Equatable {
    let strokeID: UUID?
    let color: HandDrawingColor
    let resolvedStamps: [HandDrawingResolvedBrushSample]
    let resolvedErasePaths: [HandDrawingResolvedErasePath]
    let bounds: CGRect?

    var isEmpty: Bool {
        resolvedStamps.isEmpty && resolvedErasePaths.allSatisfy(\.samples.isEmpty)
    }
}

struct HandDrawingRenderGraph: Equatable {
    let paperSize: CGSize
    let paperTransform: CGAffineTransform
    let renderRegion: CGRect?
    let layers: [HandDrawingRenderGraphLayer]

    var renderedStrokeSnapshotsInOrder: [HandDrawingStrokeRenderSnapshot] {
        layers.flatMap(\.strokeSnapshots)
    }
}

enum HandDrawingRenderGraphBuilder {
    static func graph(
        for document: HandDrawingDocument,
        renderRegion: CGRect? = nil,
        paperTransform: CGAffineTransform = .identity
    ) -> HandDrawingRenderGraph {
        let layers = document.visibleLayersInRenderOrder.map { layer in
            HandDrawingRenderGraphLayer(
                layerID: layer.id,
                strokeSnapshots: layer.strokes.compactMap { stroke in
                    let snapshot = strokeSnapshot(for: stroke)
                    guard snapshot.isEmpty == false else {
                        return nil
                    }
                    if let renderRegion,
                       let bounds = snapshot.bounds,
                       bounds.intersects(renderRegion) == false
                    {
                        return nil
                    }
                    return snapshot
                }
            )
        }
        return HandDrawingRenderGraph(
            paperSize: document.paper.size,
            paperTransform: paperTransform,
            renderRegion: renderRegion,
            layers: layers
        )
    }
}

struct HandDrawingCPURenderGraphRenderer {
    func makeImage(
        for snapshot: HandDrawingStrokeRenderSnapshot,
        paperTransform: CGAffineTransform = .identity,
        canvasPixelSize: CGSize
    ) throws -> CGImage {
        let strokeContext = try makeBitmapContext(
            width: max(Int(ceil(canvasPixelSize.width)), 1),
            height: max(Int(ceil(canvasPixelSize.height)), 1)
        )
        strokeContext.concatenate(paperTransform)
        HandDrawingStrokeRasterizer.draw(snapshot, in: strokeContext)
        guard let strokeImage = strokeContext.makeImage() else {
            throw HandDrawingCPURenderGraphRendererError.failedToCreateStrokeImage
        }
        return strokeImage
    }
}
```

## 修改二：让 StrokeRasterizer 从“隐式语义持有者”退化为 CPU backend 实现

### 修改前

- `HandDrawingStrokeRasterizer.draw(_ stroke:in:)` 自己承担两件事：
  - 从 `stroke` 直接重新计算 `resolvedStamps`
  - 直接解析 `eraseMask + transform`
- 这让 CPU rasterizer 同时扮演了：
  - 语义定义者
  - CPU backend 具体实现
- 后续不利于把 preview、committed、geometry、realtime 全部对齐到一份 renderer-agnostic 输入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift（修改前）
// 函数名: draw(_ stroke:in:) / drawStrokeInk(_:in:) / applyEraseMask(_:transform:in:)
// 功能说明: 修改前 rasterizer 直接从原始 stroke 重算 resolved stamps，并在内部解析 eraseMask 的 transform 语义。
enum HandDrawingStrokeRasterizer {
    static func draw(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        drawStrokeInk(stroke, in: context)
        applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: context)
    }

    private static func drawStrokeInk(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        let resolvedSamples = HandDrawingBrushDynamics.resolvedStamps(
            for: stroke
        )
        draw(
            resolvedSamples,
            color: stroke.brush.color,
            in: context
        )
    }

    private static func applyEraseMask(
        _ eraseMask: [HandDrawingErasePath],
        transform: HandDrawingStrokeTransform,
        in context: CGContext
    ) {
        // ... 省略 transform.apply(to:) 与 clear blend 逻辑 ...
    }
}
```

### 修改后

- 保留 `draw(_ stroke:in:)` 作为兼容入口，但它第一步会先构造 `strokeSnapshot`。
- 真正的 CPU rasterizer 入口改成 `draw(_ snapshot:in:)`。
- `eraseMask` 现在消费的是已经 resolve 到文档空间的 `HandDrawingResolvedErasePath`。
- 结果是：`StrokeRasterizer` 只负责“如何用 CPU 画 snapshot”，不再负责定义整套上层语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
// 函数名: draw(_ stroke:in:) / draw(_ snapshot:in:) / applyEraseMask(_:in:)
// 功能说明: 修改后 rasterizer 退化成 CPU backend，实现对象从原始 stroke 变为统一 snapshot。
enum HandDrawingStrokeRasterizer {
    static func draw(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        draw(
            HandDrawingRenderGraphBuilder.strokeSnapshot(for: stroke),
            in: context
        )
    }

    static func draw(
        _ snapshot: HandDrawingStrokeRenderSnapshot,
        in context: CGContext
    ) {
        guard snapshot.isEmpty == false else {
            return
        }
        draw(
            snapshot.resolvedStamps,
            color: snapshot.color,
            in: context
        )
        applyEraseMask(snapshot.resolvedErasePaths, in: context)
    }

    private static func applyEraseMask(
        _ eraseMask: [HandDrawingResolvedErasePath],
        in context: CGContext
    ) {
        // ... 省略 clear blend 逻辑 ...
    }
}
```

## 修改三：让 preview、committed CPU、GPU committed 共用同一套 graph 输入

### 修改前

- preview 自己按 `document.renderedStrokesInOrder` 循环，并为每根 stroke 新建离屏 context。
- committed CPU canvas 自己按 `document.renderedStrokesInOrder` 循环，再直接 `HandDrawingStrokeRasterizer.draw(stroke, in:)`。
- GPU committed backend 也自己按 `document.renderedStrokesInOrder` 循环，再把单根 stroke 重新 rasterize 成 `CGImage` 后上传。
- 三条路径虽然看起来相似，但没有共享显式 graph，后续如果要继续逼近方案三，仍然要从三个方向反向拆语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift（修改前）
// 函数名: renderPreviewImage(...) / drawStroke(...)
// 功能说明: 修改前 preview 自己逐 stroke 建离屏图，再 composite 到最终 preview context。
for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
    try drawStroke(
        stroke,
        into: compositeContext,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        scale: resolvedScale
    )
}

// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift（修改前）
// 函数名: render(request:)
// 功能说明: 修改前 committed CPU canvas 自己逐 stroke 遍历并直接调用 rasterizer。
for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
    guard
        let strokeBounds = stroke.bounds,
        strokeBounds.intersects(renderRegion)
    else {
        continue
    }
    HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
}

// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift（修改前）
// 函数名: renderIntoTexture(request:) / drawStrokeTexture(for:canvasSize:using:)
// 功能说明: 修改前 GPU committed backend 也直接按原始 stroke 循环，再在内部单独做 CPU rasterize。
for stroke in request.document.renderedStrokesInOrder where stroke.isEmpty == false {
    guard
        let strokeBounds = stroke.bounds,
        strokeBounds.intersects(renderRegion)
    else {
        continue
    }
    try drawStrokeTexture(
        for: stroke,
        canvasSize: request.document.paper.size,
        using: renderEncoder
    )
}
```

### 修改后

- preview、committed CPU、GPU committed 全部先构造 `HandDrawingRenderGraph`。
- preview 用 `paperTransform = scale(...)` 把缩放语义也放进 graph。
- CPU graph renderer 成为三者共享的 canonical CPU path。
- GPU committed 仍然保持“GPU 管 texture 生命周期、局部 clear、composite；单 stroke 像素走 CPU canonical path”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: renderPreviewImage(...)
// 功能说明: 修改后 preview 先构造 render graph，再统一交给 CPU graph renderer 画到 composite context。
let renderGraph = HandDrawingRenderGraphBuilder.graph(
    for: document,
    paperTransform: CGAffineTransform(
        scaleX: resolvedScale,
        y: resolvedScale
    )
)
try graphRenderer.draw(
    renderGraph,
    in: compositeContext,
    canvasPixelSize: CGSize(
        width: pixelWidth,
        height: pixelHeight
    )
)

// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: render(request:)
// 功能说明: 修改后 committed CPU canvas 也直接消费统一 render graph。
let renderGraph = HandDrawingRenderGraphBuilder.graph(
    for: document,
    renderRegion: renderRegion
)
try graphRenderer.draw(
    renderGraph,
    in: bitmapContext,
    canvasPixelSize: document.paper.size
)

// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift
// 函数名: renderIntoTexture(request:) / drawStrokeTexture(_:paperTransform:canvasSize:using:)
// 功能说明: 修改后 GPU committed backend 先拿到 render graph，再按 snapshot 顺序 composite；单根 stroke 的 canonical 像素由 CPU graph renderer 生成。
let renderGraph = HandDrawingRenderGraphBuilder.graph(
    for: request.document,
    renderRegion: renderRegion
)

for snapshot in renderGraph.renderedStrokeSnapshotsInOrder {
    try drawStrokeTexture(
        snapshot,
        paperTransform: renderGraph.paperTransform,
        canvasSize: request.document.paper.size,
        using: renderEncoder
    )
}

private func drawStrokeTexture(
    _ snapshot: HandDrawingStrokeRenderSnapshot,
    paperTransform: CGAffineTransform,
    canvasSize: CGSize,
    using renderEncoder: MTLRenderCommandEncoder
) throws {
    let strokeImage = try cpuGraphRenderer.makeImage(
        for: snapshot,
        paperTransform: paperTransform,
        canvasPixelSize: canvasSize
    )
    // ... 省略后续 texture upload 与 GPU composite ...
}
```

## 修改四：让 tool geometry 与 realtime draft 共享同一份 snapshot 语义

### 修改前

- `HandDrawingStrokeGeometry` 直接依赖：
  - `stroke.bounds`
  - `HandDrawingBrushDynamics.resolvedStamps(for: stroke)`
- realtime CPU host 直接画：
  - `committedResolvedStamps`
  - `predictedResolvedStamps`
- realtime GPU host 直接拿 `allResolvedStamps + brush.color` 生成 Metal instance。
- 这些路径都在“重复组合渲染输入”，而不是复用同一份显式 snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift（修改前）
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改前 geometry 直接依赖 stroke.bounds 与 HandDrawingBrushDynamics.resolvedStamps(for:)。
guard let strokeBounds = stroke.bounds else {
    return false
}
let resolvedSamples = HandDrawingBrushDynamics.resolvedStamps(
    for: stroke
)

// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingCPURealtimeDraftRendererView.draw(_:) / HandDrawingGPURealtimeDraftRendererView.makeStampInstances(from:)
// 功能说明: 修改前 realtime CPU/GPU host 直接消费裸 resolvedStamps 数组与 brush.color。
HandDrawingStrokeRasterizer.draw(
    resolvedState.committedResolvedStamps,
    color: resolvedState.brush.color,
    in: context
)
HandDrawingStrokeRasterizer.draw(
    resolvedState.predictedResolvedStamps,
    color: resolvedState.brush.color,
    in: context
)

return renderState.allResolvedStamps.map { stamp in
    HandDrawingRealtimeDraftMetalStampInstance(
        // ... 省略 point / radii / rotation ...
        color: SIMD4<Float>(
            Float(renderState.brush.color.red),
            Float(renderState.brush.color.green),
            Float(renderState.brush.color.blue),
            Float(renderState.brush.color.alpha)
        ),
        opacity: Float(stamp.opacity)
    )
}
```

### 修改后

- geometry 先把原始 stroke 统一转成 `strokeSnapshot`，再从 snapshot 上取 `bounds` 和 `resolvedStamps`。
- realtime contract 新增：
  - `committedRenderSnapshot`
  - `predictedRenderSnapshot`
  - `renderSnapshots`
- CPU realtime host 直接画 snapshot；GPU realtime host 直接从 snapshot 生成 Metal instance。
- 这样 realtime、geometry、committed、preview 都围绕同一套 graph 输入工作。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改后 geometry 改为消费统一 stroke snapshot，避免和 renderer 分别重算 stamps / bounds。
let renderSnapshot = HandDrawingRenderGraphBuilder.strokeSnapshot(
    for: stroke
)
guard let strokeBounds = renderSnapshot.bounds else {
    return false
}
let resolvedSamples = renderSnapshot.resolvedStamps

// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeDraftRenderState.committedRenderSnapshot / predictedRenderSnapshot / renderSnapshots
// 功能说明: 修改后 realtime draft state 也显式暴露 snapshot 语义，供 CPU/GPU host 复用。
var committedRenderSnapshot: HandDrawingStrokeRenderSnapshot? {
    guard committedResolvedStamps.isEmpty == false else {
        return nil
    }
    return HandDrawingRenderGraphBuilder.strokeSnapshot(
        brush: brush,
        resolvedStamps: committedResolvedStamps
    )
}

var renderSnapshots: [HandDrawingStrokeRenderSnapshot] {
    [committedRenderSnapshot, predictedRenderSnapshot].compactMap { $0 }
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCPURealtimeDraftRendererView.draw(_:) / HandDrawingGPURealtimeDraftRendererView.makeStampInstances(from:)
// 功能说明: 修改后 realtime CPU/GPU host 不再直接拼裸 stamps + 颜色，而是统一遍历 snapshot。
if let resolvedState = renderOutput.resolvedState {
    for snapshot in resolvedState.renderSnapshots {
        HandDrawingStrokeRasterizer.draw(snapshot, in: context)
    }
}

return renderState.renderSnapshots.flatMap { snapshot in
    snapshot.resolvedStamps.map { stamp in
        HandDrawingRealtimeDraftMetalStampInstance(
            // ... 省略 point / radii / rotation ...
            color: SIMD4<Float>(
                Float(snapshot.color.red),
                Float(snapshot.color.green),
                Float(snapshot.color.blue),
                Float(snapshot.color.alpha)
            ),
            opacity: Float(stamp.opacity)
        )
    }
}
```

## 修改五：补 render graph 回归，并修正离屏 stroke image 的双重坐标翻转

### 修改前

- 没有专门覆盖 render graph 的测试。
- realtime contract 也没有断言 `renderSnapshots`。
- 实现 render graph 的第一版中，`HandDrawingCPURenderGraphRenderer.makeImage(...)` 对离屏 stroke image context 额外做了一次 display coordinate flip；但 preview/canvas 最终 composite 的目标 context 已经有自己的坐标系处理，这会导致上下再次翻转。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift（实现过程中的首次版本）
// 函数名: HandDrawingCPURenderGraphRenderer.makeImage(...)
// 功能说明: 第一次落地时，这里额外执行了 display coordinate flip，导致离屏 stroke image 与最终 composite context 形成双重翻转。
let strokeContext = try makeBitmapContext(width: width, height: height)
Self.configureDisplayCoordinateSpace(
    for: strokeContext,
    height: CGFloat(height)
)
strokeContext.concatenate(paperTransform)
HandDrawingStrokeRasterizer.draw(snapshot, in: strokeContext)
```

### 修改后

- 新增 `HandDrawingRenderGraphTests.swift`，覆盖：
  - visible layer order
  - render region 过滤
  - erase mask resolve 到文档空间
- `HandDrawingRenderingContractsTests.swift` 新增 realtime snapshot 断言。
- 最终移除 `makeImage(...)` 中那层多余的 display coordinate flip，只保留 `paperTransform`，彻底修正上下颠倒的根因。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests.swift
// 函数名: testHandDrawingRenderGraphBuilderPreservesVisibleLayerOrderAndFiltersSnapshotsByRenderRegion() / testHandDrawingRenderGraphBuilderResolvesEraseMaskIntoDocumentSpace()
// 功能说明: 新增 render graph 层级、区域过滤、erase mask 文档空间解析的 focused tests。
func testHandDrawingRenderGraphBuilderPreservesVisibleLayerOrderAndFiltersSnapshotsByRenderRegion() {
    let graph = HandDrawingRenderGraphBuilder.graph(
        for: document,
        renderRegion: CGRect(x: 0, y: 48, width: 120, height: 24)
    )

    XCTAssertEqual(graph.layers.count, 3)
    XCTAssertEqual(graph.layers[0].strokeSnapshots.map(\.strokeID), [baseStroke.id])
    XCTAssertTrue(graph.layers[1].strokeSnapshots.isEmpty)
    XCTAssertEqual(graph.layers[2].strokeSnapshots.map(\.strokeID), [overlayStroke.id])
}

func testHandDrawingRenderGraphBuilderResolvesEraseMaskIntoDocumentSpace() throws {
    let snapshot = HandDrawingRenderGraphBuilder.strokeSnapshot(for: stroke)
    let eraseSample = try XCTUnwrap(
        snapshot.resolvedErasePaths.first?.samples.first
    )

    XCTAssertEqual(eraseSample.point, CGPoint(x: 52, y: 28))
    XCTAssertEqual(eraseSample.radius, 6)
    XCTAssertEqual(eraseSample.opacity, 0.4, accuracy: 0.001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
// 函数名: testHandDrawingRealtimeDraftRenderStateExposesRenderSnapshotsForCommittedAndPredictedSegments()
// 功能说明: 补充 realtime draft state 到 renderSnapshots 的合同断言。
func testHandDrawingRealtimeDraftRenderStateExposesRenderSnapshotsForCommittedAndPredictedSegments() {
    let state = HandDrawingRealtimeDraftRenderState(
        brush: stroke.brush,
        committedResolvedStamps: Array(resolvedStamps.prefix(2)),
        predictedResolvedStamps: Array(resolvedStamps.suffix(2))
    )

    XCTAssertEqual(state.renderSnapshots.count, 2)
    XCTAssertEqual(state.committedRenderSnapshot?.color, stroke.brush.color)
    XCTAssertEqual(state.predictedRenderSnapshot?.color, stroke.brush.color)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderGraph.swift
// 函数名: HandDrawingCPURenderGraphRenderer.makeImage(...)
// 功能说明: 最终版本移除了多余的 display coordinate flip，只保留 paperTransform，修正离屏 stroke image 的上下颠倒根因。
func makeImage(
    for snapshot: HandDrawingStrokeRenderSnapshot,
    paperTransform: CGAffineTransform = .identity,
    canvasPixelSize: CGSize
) throws -> CGImage {
    let strokeContext = try makeBitmapContext(width: width, height: height)
    strokeContext.concatenate(paperTransform)
    HandDrawingStrokeRasterizer.draw(snapshot, in: strokeContext)
    guard let strokeImage = strokeContext.makeImage() else {
        throw HandDrawingCPURenderGraphRendererError.failedToCreateStrokeImage
    }
    return strokeImage
}
```

## 验证结果

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:...
# 功能说明: 验证 phase 6 引入 render graph 后，canvas / preview / geometry / persistence 相关回归仍成立。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingRenderGraphTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" \
  -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests"
# 结果: Exit code 0
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"
# 功能说明: 验证 phase 6 的 render graph 接口在 iOS Simulator target 下能够完整编译通过。
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"
# 结果: Exit code 0
```

## 结论

- `phase 6` 完成后，realtime、committed、preview、tool geometry 已经共享一套 renderer-agnostic 输入语义。
- `HandDrawingStrokeRasterizer` 已退化为 CPU backend 实现，而不是全系统默认唯一语义源。
- canonical preview 仍稳固落在 CPU/document 路径上，符合“逼近方案三但不越过 CPU truth”的阶段目标。
