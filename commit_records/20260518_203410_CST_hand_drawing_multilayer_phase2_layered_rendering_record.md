# 20260518_203410_CST_hand_drawing_multilayer_phase2_layered_rendering_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 2：`渲染与 preview 改造成按 layer 合成`。
  2. 让 `HandDrawingCanvasRenderer` 与 `HandDrawingPreviewRenderer` 不再只消费 `document.strokes`，而是按可见 layer 顺序合成输出。
  3. 补阶段 2 的最小回归测试，直接验证 `visible layer 顺序` 和 `hidden layer 跳过绘制`。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_203410_CST`
- 说明：
  - 本记录只覆盖刚刚实施的多 layer 阶段 2，不包含阶段 3 之后的 engine、工具作用域、iPad layer UI 和宿主兼容收口。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 3 的 `HandDrawingEditorEngine` / 历史栈 layer 命令接入
  - 阶段 4 的 brush / pixel eraser / lasso / move 仅作用当前 layer
  - 阶段 5 的 iPad layer UI
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
    - 本阶段未修改；layer 合成发生在 renderer 遍历 stroke 的入口层，而不是单 stroke 栅格化层
  - git commit / push

## 修改一：给渲染链补文档级“可见 layer 顺序”聚合入口

### 修改前

- 阶段 1 完成后，`HandDrawingDocument` 已经有 `layers + activeLayerID`，但保留下来的 `document.strokes` 仍然等价于“当前 active layer 的 strokes”。
- 文档模型里还没有专门给渲染链消费的“可见 layer 顺序”聚合属性。
- 这意味着 renderer 如果继续读 `document.strokes`，拿到的仍然只是当前 layer，而不是整个多 layer 文档。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.strokes / allStrokes / activeLayer
// 功能注释: 修改前文档模型只有 active layer 兼容入口，没有给渲染链直接使用的 visible layer render order 聚合属性。
var strokes: [HandDrawingStroke] {
    get {
        activeLayer?.strokes ?? []
    }
    set {
        replaceStrokesInActiveLayer(with: newValue)
    }
}

var allStrokes: [HandDrawingStroke] {
    layers.flatMap(\.strokes)
}

var activeLayer: HandDrawingLayer? {
    guard let index = activeLayerIndex else {
        return nil
    }
    return layers[index]
}
```

### 修改后

- 在 `HandDrawingDocument` 上新增：
  - `visibleLayersInRenderOrder`
  - `renderedStrokesInOrder`
- 语义收口为：
  - 先按 `layers` 原始顺序遍历
  - 只保留 `isVisible == true` 的 layer
  - 再把每个 layer 内的 `strokes` 按原顺序展开
- `isLocked` 没有进入渲染筛选逻辑，仍然只保留给后续编辑语义使用，符合阶段 2 计划“locked 只影响编辑，不影响绘制”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.visibleLayersInRenderOrder / renderedStrokesInOrder
// 功能注释: 修改后渲染链通过文档级聚合入口统一获取“按可见 layer 顺序展开后的 strokes”。
var allStrokes: [HandDrawingStroke] {
    layers.flatMap(\.strokes)
}

var visibleLayersInRenderOrder: [HandDrawingLayer] {
    layers.filter(\.isVisible)
}

var renderedStrokesInOrder: [HandDrawingStroke] {
    visibleLayersInRenderOrder.flatMap(\.strokes)
}
```

## 修改二：`HandDrawingCanvasRenderer` 从“当前 layer”改为“按可见 layer 顺序”绘制 committed image

### 修改前

- `HandDrawingCanvasRenderer.render(document:dirtyRegion:)` 的核心遍历还是 `document.strokes`。
- 在阶段 1 的兼容语义下，这里实际只会绘制当前 active layer。
- `dirtyRegion` / `clip` / `clear(region:)` 的局部重绘策略当时没有问题，但在多 layer 下只能保证“当前层局部正确”，不能表达整个文档的 layer 合成结果。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: HandDrawingCanvasRenderer.render(document:dirtyRegion:)
// 功能注释: 修改前 committed image 仍然只遍历 document.strokes，因此在多 layer 文档下只会画 active layer。
clear(region: renderRegion)
bitmapContext.saveGState()
bitmapContext.addRect(renderRegion)
bitmapContext.clip()

for stroke in document.strokes where stroke.isEmpty == false {
    guard
        let strokeBounds = stroke.bounds,
        strokeBounds.intersects(renderRegion)
    else {
        continue
    }
    HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
}
bitmapContext.restoreGState()
```

### 修改后

- 只替换了 stroke 来源：从 `document.strokes` 改成 `document.renderedStrokesInOrder`。
- `dirtyRegion` 的正确性优先策略保持不变，没有在本阶段引入 layer 级缓存拆分或每层单独 bitmap。
- 这样编辑器依旧只消费一张 committed image，但这张图现在已经是多 layer 的可见合成结果。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: HandDrawingCanvasRenderer.render(document:dirtyRegion:)
// 功能注释: 修改后 committed image 在保持局部重绘策略不变的前提下，按可见 layer 顺序统一绘制。
clear(region: renderRegion)
bitmapContext.saveGState()
bitmapContext.addRect(renderRegion)
bitmapContext.clip()

for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
    guard
        let strokeBounds = stroke.bounds,
        strokeBounds.intersects(renderRegion)
    else {
        continue
    }
    HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
}
bitmapContext.restoreGState()
```

## 修改三：`HandDrawingPreviewRenderer` 与 committed image 共享同一 layer 合成入口

### 修改前

- `HandDrawingPreviewRenderer.renderPreviewImage(for:scale:backgroundColor:)` 同样遍历 `document.strokes`。
- 所以 preview、thumbnail、小地图这条消费 preview image 的链路，在多 layer 文档下也只能拿到当前 active layer 的输出。
- 这会导致 editor committed image 和 preview image 在图层语义上都不完整，而且二者会一起遗漏非活动层内容。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: HandDrawingPreviewRenderer.renderPreviewImage(for:scale:backgroundColor:)
// 功能注释: 修改前 preview 渲染只遍历 document.strokes，在多 layer 文档下同样只会渲染 active layer。
let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
if let backgroundColor {
    compositeContext.setFillColor(backgroundColor.cgColor)
    compositeContext.fill(pixelRect)
}

for stroke in document.strokes where stroke.isEmpty == false {
    try drawStroke(
        stroke,
        into: compositeContext,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        scale: resolvedScale
    )
}
```

### 修改后

- `PreviewRenderer` 现在与 `CanvasRenderer` 一样，统一消费 `document.renderedStrokesInOrder`。
- 这样 preview image 的 API 没变，但语义已经变成“整个多 layer 文档的可见合成结果”。
- 下游继续消费 preview image 的 thumbnail / minimap 链路不需要额外改接口，就能继承相同的 layer 顺序和显隐行为。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: HandDrawingPreviewRenderer.renderPreviewImage(for:scale:backgroundColor:)
// 功能注释: 修改后 preview 与 committed image 共享同一份多 layer 合成入口，保证输出契约一致。
let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
if let backgroundColor {
    compositeContext.setFillColor(backgroundColor.cgColor)
    compositeContext.fill(pixelRect)
}

for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
    try drawStroke(
        stroke,
        into: compositeContext,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        scale: resolvedScale
    )
}
```

## 修改四：补回归测试，直接锁定 `layer 顺序` 与 `hidden layer` 语义

### 修改前

- `HandDrawingPreviewRendererTests` 只覆盖：
  - 单 stroke 可见像素
  - 单 stroke 局部擦除
  - 颜色/线宽差异
- `HandDrawingCanvasRendererTests` 只覆盖：
  - committed image 与 preview image 在局部擦除后的像素一致性
  - top-origin 显示坐标方向
- 这些测试都没有直接断言“两个重叠 layer 的前后顺序”和“隐藏 layer 完全不参与绘制”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererProducesVisiblePixelsForStroke / testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask / testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences
// 功能注释: 修改前 preview 测试只覆盖单层笔迹、擦除和画笔差异，不覆盖多 layer 顺序与显隐。
func testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() throws {
    // ...
}

func testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() throws {
    // ...
}

func testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences() throws {
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate / testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates
// 功能注释: 修改前 canvas 测试只覆盖局部擦除后的一致性和显示坐标方向，不覆盖多 layer 合成语义。
func testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate() throws {
    // ...
}

func testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates() throws {
    // ...
}
```

### 修改后

- `HandDrawingPreviewRendererTests` 新增 `testHandDrawingPreviewRendererRespectsVisibleLayerOrder()`：
  - 先构造红色 base layer 和绿色 overlay layer
  - 再构造一个只把 `isVisible` 改成 `false` 的 hidden overlay layer
  - 断言 overlay 可见时中心像素偏绿，overlay 隐藏时中心像素偏红
- `HandDrawingCanvasRendererTests` 新增 `testHandDrawingCanvasRendererMatchesPreviewRendererForVisibleLayerOrder()`：
  - 用同一组 layered document 同时渲染 canvas 与 preview
  - 同时断言：
    - canvas / preview 中心像素完全一致
    - visible overlay 时像素偏绿
    - hidden overlay 时像素偏红
- 另外新增 `makeCanvasRendererLayeredTestStroke(...)` 测试辅助函数，避免把多 layer 场景构造直接塞进断言函数内部。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererRespectsVisibleLayerOrder
// 功能注释: 修改后 preview 测试直接验证“后层覆盖前层”以及“隐藏 layer 完全跳过绘制”。
func testHandDrawingPreviewRendererRespectsVisibleLayerOrder() throws {
    let renderer = HandDrawingPreviewRenderer()
    let baseLayer = makeHandDrawingTestLayer(
        name: "Base",
        strokes: [
            makePreviewRendererTestStroke(
                y: 60,
                baseSize: 18,
                color: HandDrawingColor(red: 0.92, green: 0.12, blue: 0.1, alpha: 1)
            )
        ]
    )
    let visibleOverlayLayer = makeHandDrawingTestLayer(
        name: "Overlay",
        isVisible: true,
        strokes: [
            makePreviewRendererTestStroke(
                y: 60,
                baseSize: 18,
                color: HandDrawingColor(red: 0.12, green: 0.86, blue: 0.18, alpha: 1)
            )
        ]
    )
    let hiddenOverlayLayer = makeHandDrawingTestLayer(
        id: visibleOverlayLayer.id,
        name: visibleOverlayLayer.name,
        isVisible: false,
        strokes: visibleOverlayLayer.strokes
    )

    let visibleDocument = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, visibleOverlayLayer],
        activeLayerID: visibleOverlayLayer.id
    )
    let hiddenDocument = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, hiddenOverlayLayer],
        activeLayerID: hiddenOverlayLayer.id
    )

    let visibleImage = try renderer.renderPreviewImage(for: visibleDocument, scale: 1)
    let hiddenImage = try renderer.renderPreviewImage(for: hiddenDocument, scale: 1)
    let visiblePixel = sampleDisplayedRGBA(from: visibleImage, x: 60, y: 60)
    let hiddenPixel = sampleDisplayedRGBA(from: hiddenImage, x: 60, y: 60)

    XCTAssertGreaterThan(visiblePixel.green, visiblePixel.red)
    XCTAssertGreaterThan(hiddenPixel.red, hiddenPixel.green)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererForVisibleLayerOrder / makeCanvasRendererLayeredTestStroke(y:color:)
// 功能注释: 修改后 canvas 测试同时锁定 canvas 与 preview 的多 layer 输出一致性，并补充 layered stroke 构造工装。
func testHandDrawingCanvasRendererMatchesPreviewRendererForVisibleLayerOrder() throws {
    let baseLayer = makeHandDrawingTestLayer(
        name: "Base",
        strokes: [
            makeCanvasRendererLayeredTestStroke(
                y: 60,
                color: HandDrawingColor(red: 0.92, green: 0.12, blue: 0.1, alpha: 1)
            )
        ]
    )
    let visibleOverlayLayer = makeHandDrawingTestLayer(
        name: "Overlay",
        isVisible: true,
        strokes: [
            makeCanvasRendererLayeredTestStroke(
                y: 60,
                color: HandDrawingColor(red: 0.12, green: 0.86, blue: 0.18, alpha: 1)
            )
        ]
    )
    let hiddenOverlayLayer = makeHandDrawingTestLayer(
        id: visibleOverlayLayer.id,
        name: visibleOverlayLayer.name,
        isVisible: false,
        strokes: visibleOverlayLayer.strokes
    )
    let visibleDocument = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, visibleOverlayLayer],
        activeLayerID: visibleOverlayLayer.id
    )
    let hiddenDocument = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, hiddenOverlayLayer],
        activeLayerID: hiddenOverlayLayer.id
    )
    let renderer = try HandDrawingCanvasRenderer(
        paperSize: visibleDocument.paper.size
    )

    let visibleCanvasImage = try renderer.render(
        document: visibleDocument,
        dirtyRegion: visibleDocument.paperBounds
    )
    let visiblePreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
        for: visibleDocument,
        scale: 1
    )
    let hiddenCanvasImage = try renderer.render(
        document: hiddenDocument,
        dirtyRegion: hiddenDocument.paperBounds
    )
    let hiddenPreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
        for: hiddenDocument,
        scale: 1
    )

    let visibleCanvasPixel = sampleDisplayedRGBA(from: visibleCanvasImage, x: 60, y: 60)
    let visiblePreviewPixel = sampleDisplayedRGBA(from: visiblePreviewImage, x: 60, y: 60)
    let hiddenCanvasPixel = sampleDisplayedRGBA(from: hiddenCanvasImage, x: 60, y: 60)
    let hiddenPreviewPixel = sampleDisplayedRGBA(from: hiddenPreviewImage, x: 60, y: 60)

    assertPixelsEqual(visibleCanvasPixel, visiblePreviewPixel)
    assertPixelsEqual(hiddenCanvasPixel, hiddenPreviewPixel)
    XCTAssertGreaterThan(visibleCanvasPixel.green, visibleCanvasPixel.red)
    XCTAssertGreaterThan(hiddenCanvasPixel.red, hiddenCanvasPixel.green)
}

private func makeCanvasRendererLayeredTestStroke(
    y: CGFloat,
    color: HandDrawingColor
) -> HandDrawingStroke {
    HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: 18,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 24, y: y),
                force: 1,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: y),
                force: 1,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 96, y: y),
                force: 1,
                timestamp: 0.2
            )
        ]
    )
}
```

## 结果小结

- 阶段 2 已把多 layer 的渲染语义真正接入主渲染链：
  - editor committed image：按可见 layer 顺序合成
  - preview image：按可见 layer 顺序合成
- `hidden layer` 现在完全跳过绘制；`locked layer` 仍不影响绘制。
- 输出契约没有变化：
  - 编辑器仍消费一张 committed image
  - 宿主仍消费一张 preview image
- 本阶段没有引入 layer 级 bitmap 缓存或更细粒度的每层 dirty 策略；当前仍以正确性优先。
