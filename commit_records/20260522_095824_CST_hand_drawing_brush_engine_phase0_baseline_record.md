# 20260522_095824_CST_hand_drawing_brush_engine_phase0_baseline_record

## 记录范围

- 记录内容：
  - 为手绘笔刷引擎方案一的 `phase 0` 补齐“当前 pressure-only 行为是什么”的测试基线。
  - 本次只修改 `MyCanvas_Ver_0Tests` 下的测试文件与测试夹具，不改动 `MyCanvas_Ver_0/Canvas/HandDrawing/...` 的生产实现。
  - 基线覆盖四类现状合同：
    - `force -> radius -> bounds` 的当前线性映射。
    - `preview renderer` 与 `canvas renderer` 的 pressure 宽度一致性。
    - `lasso` 对当前 stroke 半径的包围假设。
    - `pixel eraser` / `move selection` 对当前 stroke 半径的命中假设。
- 涉及文件：
  - `MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_095824_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次改动相关文件执行 `git diff --stat -- ...`，结果为：`7 files changed, 330 insertions(+), 23 deletions(-)`。
  - 生成本记录前，针对本次改动相关文件执行 `git status --short -- ...`，这 7 个文件均处于已修改未提交状态。
- 本记录不包含：
  - `phase 1` 的 `BrushDynamics` 生产代码抽取。
  - `document formatVersion`、codec、迁移逻辑的调整。
  - 任何 hand drawing 生产渲染/几何实现的重构。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统命令生成本次 markdown 记录文件的时间戳前缀。
20260522_095824_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
# 功能说明: 汇总本次 phase 0 相关文件的 diff 统计，不直接贴原始 diff。
.../HandDrawingCanvasRendererTests.swift           | 58 ++++++++++++++--
.../HandDrawingCoreTestFixtures.swift              | 35 +++++-----
.../HandDrawingEditorEngineTests.swift             | 18 +++++
.../HandDrawingLassoSelectionTests.swift           | 81 ++++++++++++++++++++++
.../HandDrawingMoveSelectionTests.swift            | 57 +++++++++++++++
...HandDrawingPixelEraserToolControllerTests.swift | 66 ++++++++++++++++++
.../HandDrawingPreviewRendererTests.swift          | 38 +++++++++-
7 files changed, 330 insertions(+), 23 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
# 功能说明: 记录本次 phase 0 触达文件在生成记录时的当前 changes 状态。
M MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
M MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
M MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
M MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
M MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
```

## 当前 changes 摘要

- 测试夹具 `makeHandDrawingTestStroke(...)` 从“固定 baseSize + 固定 force 样本”升级为“可配置 `baseSize` / `samplePoints` / `sampleForces`”，用于低成本构造细笔迹、粗笔迹、不同采样点位的 phase 0 场景。
- `HandDrawingEditorEngineTests` 新增显式断言，锁定当前 `radiusForSample(at:)` 仍是 `baseSize * resolvedForce / 2` 的 pressure-only 线性语义，并同步锁定 `bounds` 的结果。
- `HandDrawingPreviewRendererTests` 与 `HandDrawingCanvasRendererTests` 新增同一 `baseSize`、不同 `force` 的对照样本，确保预览链路与主画布渲染链路都体现当前 pressure 驱动的宽度差异。
- `HandDrawingLassoSelectionTests`、`HandDrawingPixelEraserToolControllerTests`、`HandDrawingMoveSelectionTests` 新增 pressure 几何基线，锁定当前 stroke 半径会影响包围判断、擦除命中、拖动命中。
- 本轮没有修改任何生产代码，所以这份记录的重点是“明确现状并防回归”，不是“改变 hand drawing 行为”。

## 修改一：测试夹具从固定样本升级为可配置 pressure 样本生成器

### 修改前

- `makeHandDrawingTestStroke(...)` 的 `baseSize`、采样点、采样 `force` 都是写死的。
- 这意味着后续想写“同一路径、不同 pressure”或“同一 pressure、不同点位”的基线测试时，只能在每个测试文件里手写一份 stroke 构造逻辑。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift（修改前）
// 函数名: makeHandDrawingTestStroke(...)
// 功能说明: 修改前测试夹具固定了笔刷大小和 pressure 样本，不利于 phase 0 构造多种压力场景。
func makeHandDrawingTestStroke(
    id: UUID = UUID(),
    color: HandDrawingColor = HandDrawingColor(
        red: 0.18,
        green: 0.34,
        blue: 0.82,
        alpha: 1
    ),
    includeEraseMask: Bool = false,
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke {
    // ... 中间保持不变的 eraseMask 构造逻辑 ...
    return HandDrawingStroke(
        id: id,
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: 14,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 25, y: 60),
                force: 1,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: 60),
                force: 1,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 95, y: 60),
                force: 0.9,
                timestamp: 0.2
            )
        ],
        transform: transform,
        eraseMask: eraseMask
    )
}
```

### 修改后

- 新增 `baseSize`、`samplePoints`、`sampleForces` 参数。
- 增加 `precondition`，确保测试样本点数组与力值数组是一一对应的，避免构造出无效测试数据。
- 采样点统一由 `zip(samplePoints, sampleForces)` 生成，后面新增的 pressure 基线测试都复用这个入口。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: makeHandDrawingTestStroke(...)
// 功能说明: 修改后测试夹具支持按需生成不同 baseSize、不同采样点、不同 pressure 分布的 stroke，作为 phase 0 所有基线测试的共享样本入口。
func makeHandDrawingTestStroke(
    id: UUID = UUID(),
    color: HandDrawingColor = HandDrawingColor(
        red: 0.18,
        green: 0.34,
        blue: 0.82,
        alpha: 1
    ),
    baseSize: Double = 14,
    samplePoints: [CGPoint] = [
        CGPoint(x: 25, y: 60),
        CGPoint(x: 60, y: 60),
        CGPoint(x: 95, y: 60)
    ],
    sampleForces: [Double] = [1, 1, 0.9],
    includeEraseMask: Bool = false,
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke {
    precondition(
        samplePoints.count == sampleForces.count,
        "Hand drawing test samples and forces must align."
    )

    // ... 中间保持不变的 eraseMask 构造逻辑 ...
    return HandDrawingStroke(
        id: id,
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1
        ),
        samplePoints: zip(samplePoints, sampleForces).enumerated().map {
            index,
            element in
            HandDrawingSamplePoint(
                point: element.0,
                force: element.1,
                timestamp: Double(index) * 0.1
            )
        },
        transform: transform,
        eraseMask: eraseMask
    )
}
```

## 修改二：显式锁定当前 `force -> radius -> bounds` 的 pressure-only 基线

### 修改前

- `HandDrawingEditorEngineTests` 已覆盖 append/export/reload、undo/redo、layer 相关行为。
- 但修改前没有任何一个测试明确断言：
  - `radiusForSample(at:)` 的当前公式是什么；
  - `stroke.bounds` 是否仍然和这套 pressure 半径保持一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift（修改前）
// 函数名: 无（测试类开头）
// 功能说明: 修改前测试类一开始直接进入编辑器行为测试，没有独立锁定 pressure-only 半径与 bounds 语义。
@MainActor
final class HandDrawingEditorEngineTests: XCTestCase {
    func testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() throws {
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "engine-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )

        // ... 现有 append / export / reload 行为断言 ...
    }
}
```

### 修改后

- 新增 `testHandDrawingStrokeRadiusAndBoundsFollowCurrentPressureOnlyMapping()`。
- 测试直接固定三组 `force`：`0.25`、`1`、`0.05`，断言当前半径结果分别为 `2.5`、`10`、`0.5`。
- 同时断言 `bounds.minX / maxX / minY / maxY`，把“半径如何影响几何包围盒”也锁进 phase 0。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingStrokeRadiusAndBoundsFollowCurrentPressureOnlyMapping()
// 功能说明: 修改后显式锁定当前 pressure-only 线性半径公式，以及 bounds 仍然围绕这套半径语义计算。
@MainActor
final class HandDrawingEditorEngineTests: XCTestCase {
    func testHandDrawingStrokeRadiusAndBoundsFollowCurrentPressureOnlyMapping() throws {
        let stroke = makeHandDrawingTestStroke(
            baseSize: 20,
            sampleForces: [0.25, 1, 0.05]
        )

        XCTAssertEqual(stroke.radiusForSample(at: 0), 2.5, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 1), 10, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 99), 10, accuracy: 0.001)

        let bounds = try XCTUnwrap(stroke.bounds)
        XCTAssertEqual(bounds.minX, 22.5, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 95.5, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 50, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 70, accuracy: 0.001)
    }
}
```

## 修改三：把 `preview renderer` 与 `canvas renderer` 的 pressure 宽度语义绑成回归基线

### 3.1 `HandDrawingPreviewRendererTests`

#### 修改前

- 已经有“颜色差异”“线宽差异”“图层顺序”等预览测试。
- 但原来的 stroke helper 没有 `force` 参数，因此无法低成本表达“同一 `baseSize`，仅 pressure 不同”这一种最核心的 phase 0 场景。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift（修改前）
// 函数名: makePreviewRendererTestStroke(...)
// 功能说明: 修改前 helper 只能构造固定 force=1 的样本，无法直接做 pressure 驱动的宽度回归测试。
private func makePreviewRendererTestStroke(
    y: CGFloat,
    baseSize: Double,
    color: HandDrawingColor
) -> HandDrawingStroke {
    HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
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

#### 修改后

- 为 helper 新增 `force` 参数。
- 新增 `testHandDrawingPreviewRendererReflectsPressureDrivenWidthDifferences()`：
  - `lowPressureStroke` 和 `highPressureStroke` 使用相同 `baseSize: 20`；
  - 仅用 `force: 0.35` 与 `force: 1` 拉开宽度差；
  - 通过边缘像素 alpha 判断窄笔迹和粗笔迹确实被预览渲染成不同厚度。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererReflectsPressureDrivenWidthDifferences() / makePreviewRendererTestStroke(...)
// 功能说明: 修改后把 preview 链路的 pressure 宽度语义固定为可回归行为，并允许 helper 构造不同 force 的对照样本。
func testHandDrawingPreviewRendererReflectsPressureDrivenWidthDifferences() throws {
    let renderer = HandDrawingPreviewRenderer()
    let lowPressureStroke = makePreviewRendererTestStroke(
        y: 34,
        baseSize: 20,
        force: 0.35,
        color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
    )
    let highPressureStroke = makePreviewRendererTestStroke(
        y: 86,
        baseSize: 20,
        force: 1,
        color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
    )
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(id: "pressure-paper", size: CGSize(width: 120, height: 120)),
        strokes: [lowPressureStroke, highPressureStroke]
    )

    let image = try renderer.renderPreviewImage(for: document, scale: 1)
    let lowEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 40)
    let highEdgePixel = sampleDisplayedRGBA(from: image, x: 60, y: 92)

    XCTAssertLessThan(lowEdgePixel.alpha, 16)
    XCTAssertGreaterThan(highEdgePixel.alpha, 64)
}

private func makePreviewRendererTestStroke(
    y: CGFloat,
    baseSize: Double,
    force: Double = 1,
    color: HandDrawingColor
) -> HandDrawingStroke {
    HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(point: CGPoint(x: 24, y: y), force: force, timestamp: 0),
            HandDrawingSamplePoint(point: CGPoint(x: 60, y: y), force: force, timestamp: 0.1),
            HandDrawingSamplePoint(point: CGPoint(x: 96, y: y), force: force, timestamp: 0.2)
        ]
    )
}
```

### 3.2 `HandDrawingCanvasRendererTests`

#### 修改前

- `canvas renderer` 之前已经和 `preview renderer` 对齐过部分擦除、图层顺序等场景。
- 但修改前没有一个测试专门锁定“pressure 导致的 stroke 宽度变化，在主画布和预览链路里必须一致”。
- 同时测试 helper 也没有 `baseSize`、`force` 参数。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift（修改前）
// 函数名: makeCanvasRendererLayeredTestStroke(...)
// 功能说明: 修改前 helper 只能构造固定 baseSize=18、force=1 的样本，无法单独验证 canvas 与 preview 的 pressure 宽度一致性。
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

#### 修改后

- helper 增加 `baseSize`、`force` 参数。
- 新增 `testHandDrawingCanvasRendererMatchesPreviewRendererForPressureDrivenStrokeWidths()`：
  - 构造同 `baseSize` 下的低压/高压 stroke；
  - 采样 `canvasImage` 与 `previewImage` 的中心与边缘像素；
  - 既断言两条链路像素一致，也断言低压 stroke 的边缘 alpha 低于高压 stroke，确保宽度差真实存在。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererForPressureDrivenStrokeWidths() / makeCanvasRendererLayeredTestStroke(...)
// 功能说明: 修改后把 canvas committed 渲染与 preview 渲染的 pressure 宽度语义锁成同一套可回归合同。
func testHandDrawingCanvasRendererMatchesPreviewRendererForPressureDrivenStrokeWidths() throws {
    let lowPressureStroke = makeCanvasRendererLayeredTestStroke(
        y: 34,
        baseSize: 20,
        force: 0.35,
        color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
    )
    let highPressureStroke = makeCanvasRendererLayeredTestStroke(
        y: 86,
        baseSize: 20,
        force: 1,
        color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
    )
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "canvas-pressure-paper",
            size: CGSize(width: 120, height: 120)
        ),
        strokes: [lowPressureStroke, highPressureStroke]
    )
    let renderer = try HandDrawingCanvasRenderer(
        paperSize: document.paper.size
    )

    let canvasImage = try renderer.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
    let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
        for: document,
        scale: 1
    )

    let lowCanvasEdgePixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 40)
    let lowPreviewEdgePixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 40)
    let highCanvasEdgePixel = sampleDisplayedRGBA(from: canvasImage, x: 60, y: 92)
    let highPreviewEdgePixel = sampleDisplayedRGBA(from: previewImage, x: 60, y: 92)

    assertPixelsEqual(lowCanvasEdgePixel, lowPreviewEdgePixel)
    assertPixelsEqual(highCanvasEdgePixel, highPreviewEdgePixel)
    XCTAssertLessThan(lowCanvasEdgePixel.alpha, highCanvasEdgePixel.alpha)
}

private func makeCanvasRendererLayeredTestStroke(
    y: CGFloat,
    baseSize: Double = 18,
    force: Double = 1,
    color: HandDrawingColor
) -> HandDrawingStroke {
    HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(point: CGPoint(x: 24, y: y), force: force, timestamp: 0),
            HandDrawingSamplePoint(point: CGPoint(x: 60, y: y), force: force, timestamp: 0.1),
            HandDrawingSamplePoint(point: CGPoint(x: 96, y: y), force: force, timestamp: 0.2)
        ]
    )
}
```

## 修改四：补齐 `lasso` / `pixel eraser` / `move selection` 的当前几何假设

### 4.1 `HandDrawingLassoSelectionTests`

#### 修改前

- 之前的套索测试已经覆盖“只选中封闭 stroke”“排除部分重叠”“只作用于 active layer”等场景。
- 但缺少一个直接回答“当前 stroke 半径变化会不会影响 lasso 包围判断”的 pressure 基线。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift（修改前）
// 函数名: testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke() / testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke()
// 功能说明: 修改前已有部分包围与 active layer 约束测试，但没有 pressure 半径差异场景。
func testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke() {
    // ... 已有部分包围断言 ...
}

func testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke() {
    // ... 已有 active layer 约束断言 ...
}
```

#### 修改后

- 新增 `testHandDrawingLassoToolControllerUsesCurrentPressureRadiusForEnclosure()`。
- 通过同样的窄套索矩形，对比：
  - `force: 0.35` 的细 stroke 可以被完整包围并选中；
  - `force: 1` 的粗 stroke 不再满足完整包围条件，不会被选中。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerUsesCurrentPressureRadiusForEnclosure()
// 功能说明: 修改后显式锁定当前 lasso 会把 stroke 半径纳入包围判定，而不是只看中心折线。
func testHandDrawingLassoToolControllerUsesCurrentPressureRadiusForEnclosure() {
    func applyNarrowLasso(
        to engine: inout HandDrawingEditorEngine,
        y: CGFloat
    ) -> Bool {
        var controller = HandDrawingLassoToolController()
        XCTAssertTrue(
            controller.beginLasso(
                with: HandDrawingInputSample(
                    location: CGPoint(x: 18, y: y - 6),
                    timestamp: 0
                ),
                engine: engine
            )
        )
        controller.appendSamples(
            [
                HandDrawingInputSample(location: CGPoint(x: 102, y: y - 6), timestamp: 0.1),
                HandDrawingInputSample(location: CGPoint(x: 102, y: y + 6), timestamp: 0.2),
                HandDrawingInputSample(location: CGPoint(x: 18, y: y + 6), timestamp: 0.3)
            ]
        )
        return controller.endLasso(engine: &engine)
    }

    let thinStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        samplePoints: [
            CGPoint(x: 25, y: 42),
            CGPoint(x: 60, y: 42),
            CGPoint(x: 95, y: 42)
        ],
        sampleForces: [0.35, 0.35, 0.35]
    )
    var thinEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "lasso-pressure-thin-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [thinStroke]
        )
    )

    XCTAssertTrue(applyNarrowLasso(to: &thinEngine, y: 42))
    XCTAssertEqual(thinEngine.state.selectedStrokeIDs, [thinStroke.id])

    let thickStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        samplePoints: [
            CGPoint(x: 25, y: 92),
            CGPoint(x: 60, y: 92),
            CGPoint(x: 95, y: 92)
        ],
        sampleForces: [1, 1, 1]
    )
    var thickEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "lasso-pressure-thick-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [thickStroke]
        )
    )

    XCTAssertFalse(applyNarrowLasso(to: &thickEngine, y: 92))
    XCTAssertTrue(thickEngine.state.selectedStrokeIDs.isEmpty)
}
```

### 4.2 `HandDrawingPixelEraserToolControllerTests`

#### 修改前

- 原有测试已经覆盖 pressure 缩放后的擦除半径、分裂 erase path、撤销恢复、active layer 约束等行为。
- 但没有一个 case 直接锁住“擦除命中是基于 `erase radius + 当前 stroke radius` 的几何关系”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift（修改前）
// 函数名: testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() / testHandDrawingPixelEraserToolControllerSplitsDisjointHitSequencesIntoSeparateErasePaths()
// 功能说明: 修改前已经验证擦除半径与 path 分裂，但没有单独区分细 stroke 与粗 stroke 的命中边界。
func testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() {
    // ... 已有擦除半径断言 ...
}

func testHandDrawingPixelEraserToolControllerSplitsDisjointHitSequencesIntoSeparateErasePaths() {
    // ... 已有 erase path 分裂断言 ...
}
```

#### 修改后

- 新增 `testHandDrawingPixelEraserToolControllerHitTestingUsesCurrentStrokeRadius()`。
- 使用同一擦除采样点与极小 `baseSize: 1` 的擦除工具，对比：
  - 细 stroke 不命中，不产生 `eraseMask`、`undo`、`dirtyRegion`；
  - 粗 stroke 命中，生成单个 `eraseMask` 样本并进入可撤销状态。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerHitTestingUsesCurrentStrokeRadius()
// 功能说明: 修改后显式锁定当前 pixel eraser 命中判定会吃进 stroke 半径，而不是只看采样中心线。
func testHandDrawingPixelEraserToolControllerHitTestingUsesCurrentStrokeRadius() {
    let eraseSample = HandDrawingInputSample(
        location: CGPoint(x: 60, y: 66),
        force: 0.05,
        timestamp: 0
    )

    let thinStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        sampleForces: [0.35, 0.35, 0.35]
    )
    var thinEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "eraser-pressure-thin-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [thinStroke]
        )
    )
    var thinController = HandDrawingPixelEraserToolController()

    thinController.beginErasing(
        with: eraseSample,
        baseSize: 1,
        engine: &thinEngine
    )
    thinController.endErasing()

    XCTAssertTrue(thinEngine.state.document.strokes[0].eraseMask.isEmpty)
    XCTAssertFalse(thinEngine.canUndo)
    XCTAssertNil(thinEngine.consumeDirtyRegion())

    let thickStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        sampleForces: [1, 1, 1]
    )
    var thickEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "eraser-pressure-thick-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [thickStroke]
        )
    )
    var thickController = HandDrawingPixelEraserToolController()

    thickController.beginErasing(
        with: eraseSample,
        baseSize: 1,
        engine: &thickEngine
    )
    thickController.endErasing()

    XCTAssertEqual(thickEngine.state.document.strokes[0].eraseMask.count, 1)
    XCTAssertEqual(
        thickEngine.state.document.strokes[0].eraseMask[0].samplePoints.count,
        1
    )
    XCTAssertTrue(thickEngine.canUndo)
    XCTAssertNotNil(thickEngine.consumeDirtyRegion())
}
```

### 4.3 `HandDrawingMoveSelectionTests`

#### 修改前

- 原有测试已经覆盖拖动后的平移结果、取消恢复、只移动 active layer 选区、隐藏/锁定 layer 不能开始移动。
- 但修改前没有一个专门验证：当前 `beginMoving(...)` 的命中边界，会随着 stroke 半径变化而变化。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift（修改前）
// 函数名: testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition() / testHandDrawingMoveSelectionControllerCancelRestoresPosition()
// 功能说明: 修改前已有平移与撤销恢复测试，但没有 pressure 半径对 beginMoving 命中的影响测试。
func testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition() {
    // ... 已有平移与 undo 断言 ...
}

func testHandDrawingMoveSelectionControllerCancelRestoresPosition() {
    // ... 已有 cancel 恢复断言 ...
}
```

#### 修改后

- 新增 `testHandDrawingMoveSelectionControllerHitTestingUsesCurrentStrokeRadiusWithPadding()`。
- 使用同一个 `hitSample`，对比：
  - 细 stroke 在当前半径下无法命中，`beginMoving(...)` 返回 `false`；
  - 粗 stroke 在当前半径加上 controller 自带 padding 后可以命中，`beginMoving(...)` 返回 `true` 并进入活动态。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerHitTestingUsesCurrentStrokeRadiusWithPadding()
// 功能说明: 修改后显式锁定当前 move selection 的命中判定既依赖 stroke 半径，也保留 controller 自带 hit padding。
func testHandDrawingMoveSelectionControllerHitTestingUsesCurrentStrokeRadiusWithPadding() {
    let hitSample = HandDrawingInputSample(
        location: CGPoint(x: 60, y: 77),
        timestamp: 0
    )

    let thinStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        sampleForces: [0.35, 0.35, 0.35]
    )
    var thinEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "move-pressure-thin-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [thinStroke]
        )
    )
    XCTAssertTrue(thinEngine.selectStrokes(withIDs: [thinStroke.id]))

    var thinController = HandDrawingMoveSelectionController()
    XCTAssertFalse(
        thinController.beginMoving(
            with: hitSample,
            engine: thinEngine
        )
    )
    XCTAssertFalse(thinController.isActive)

    let thickStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        sampleForces: [1, 1, 1]
    )
    var thickEngine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "move-pressure-thick-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [thickStroke]
        )
    )
    XCTAssertTrue(thickEngine.selectStrokes(withIDs: [thickStroke.id]))

    var thickController = HandDrawingMoveSelectionController()
    XCTAssertTrue(
        thickController.beginMoving(
            with: hitSample,
            engine: thickEngine
        )
    )
    XCTAssertTrue(thickController.isActive)
}
```

## 验证情况

- `ReadLints` 检查本次 7 个修改文件：无新增诊断。
- 定向运行 hand drawing phase 0 相关测试：通过。

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase0Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 功能说明: 只验证本次 phase 0 触达的手绘测试基线，并使用独立 DerivedData 避免 build.db 争用。
xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase0Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 结果: Exit code 0，定向测试通过。
```

## 结论

- 这次 `phase 0` 的实际落地内容，是把“当前 hand drawing pressure-only 行为是什么”固定成测试基线。
- 记录到此为止，生产实现仍保持原样；后续进入 `phase 1` 时，应在这些测试继续通过的前提下，再抽出统一的 `BrushDynamics` 求解层。
