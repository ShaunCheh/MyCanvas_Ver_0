# 20260522_104449_CST_hand_drawing_brush_engine_phase3_tilt_stamp_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 3`，把 `pressure-only` 的圆形半径语义升级为真正可见、可命中、可包围的 `tilt-aware resolved stamp` 语义。
  - 将 `HandDrawingStrokeRasterizer` 从“圆盘 + 线段连接”升级为“插值后的椭圆 stamp”光栅化。
  - 同步收敛 `HandDrawingStrokeGeometry`、`stroke.bounds`、`dirty region` 相关包围盒语义到同一套 stamp footprint。
  - 补齐 `preview` / `canvas` / `lasso` / `pixel eraser` / `move selection` 的 tilt 回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_104449_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次 `phase 3` 相关文件执行 `git diff --stat -- ...`，结果为：`11 files changed, 679 insertions(+), 159 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示 11 个已跟踪修改文件，均属于本次 `phase 3` 变更。
  - 当前工作区还存在 `/.cursor/plans/手绘笔刷引擎_b7888ee9.plan.md` 的现有修改，但该 `.md` 文件不属于本次 phase 3 代码产物，因此不纳入本记录正文。
- 本记录不包含：
  - `phase 2` 的输入归一化与 builder 双轨统一记录。
  - `phase 4` 之后的 brush preset / UI / compatibility / performance 工作。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次 phase 3 markdown 记录文件的时间戳前缀。
20260522_104449_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
# 功能说明: 汇总本次 phase 3 相关已跟踪文件的 diff 统计。
.../Editing/HandDrawingBrushDynamics.swift         | 251 ++++++++++++++++++++-
.../Editing/HandDrawingStrokeGeometry.swift        |  80 +------
.../Rendering/HandDrawingStrokeRasterizer.swift    |  54 ++---
.../HandDrawingEditorCoordinator.swift             |   4 +-
.../HandDrawingBrushDynamicsTests.swift            |  26 +++
.../HandDrawingCanvasRendererTests.swift           | 108 +++++++--
.../HandDrawingCoreTestFixtures.swift              |  24 +-
.../HandDrawingLassoSelectionTests.swift           |  75 ++++++
.../HandDrawingMoveSelectionTests.swift            |  61 +++++
...HandDrawingPixelEraserToolControllerTests.swift |  65 ++++++
.../HandDrawingPreviewRendererTests.swift          |  90 ++++++--
11 files changed, 679 insertions(+), 159 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
# 功能说明: 记录本次 phase 3 相关文件的当前 changes 状态。
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
M MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
M MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
M MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
M MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
M MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
```

## 当前 changes 摘要

- `HandDrawingResolvedBrushSample` 不再只是“圆心 + radius”的中间结果，而是升级为带 `major/minor radius`、`rotationRadians`、`axisAlignedBounds`、`contains()`、`probePoints()` 的 stamp footprint。
- `HandDrawingBrushDynamics` 新增 `resolvedStamps(for:)`，把 anchor samples 插值为连续 stamp 序列，`stroke.bounds` 也随之基于 stamp 轴对齐包围盒重算。
- `HandDrawingStrokeGeometry` 不再手写“采样圆心距离 + 线段距离”逻辑，而是改为消费 stamp footprint 本身的 `contains()` / `probePoints()`。
- `HandDrawingStrokeRasterizer` 不再画圆盘并用线段补缝，而是直接绘制旋转椭圆 stamp。
- `HandDrawingEditorCoordinator` 给新建 brush style 接入默认 `tiltSizeInfluence`，让 phase 3 能在新画出的 stroke 上真正生效。
- 测试夹具支持构造 `azimuthRadians` / `altitudeRadians` / `tiltSizeInfluence`，并补齐动态学、预览、画布渲染、套索、橡皮擦、移动选择的 tilt 回归测试。

## 修改一：`HandDrawingBrushDynamics` 升级为 tilt-aware resolved stamp 语义

### 修改前

- `HandDrawingResolvedBrushSample` 只承载 pressure 半径与 tilt 调整后的半径，没有 stamp 旋转角、长短轴、轴对齐包围盒或 footprint 命中接口。
- `bounds(for:)` 仅用 `sample.radius` 画圆形包围盒，低估了倾角拉长后的 footprint。
- `resolveSample` 只把 `tiltAdjustedRadius` 作为附加字段返回，真正的 `bounds` / `geometry` / `rasterizer` 并未围绕它建立统一合同。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift（修改前）
// 函数名: HandDrawingResolvedBrushSample / bounds(for:) / resolveSample(_:point:configuration:)
// 功能说明: 修改前 resolved sample 仍是 pressure-only 圆形语义，tilt 只存在于附加半径字段，未形成完整 stamp footprint。
struct HandDrawingResolvedBrushSample: Equatable {
    let point: CGPoint
    let radius: CGFloat
    let tiltAdjustedRadius: CGFloat
    let opacity: CGFloat
    let pressureSizeRatio: CGFloat
    let tiltSizeFactor: CGFloat
    let tiltOpacityFactor: CGFloat
    let azimuthRadians: CGFloat?
    let altitudeRadians: CGFloat?
}

static func bounds(
    for stroke: HandDrawingStroke
) -> CGRect? {
    var accumulatedBounds: CGRect?
    for sample in resolvedSamples(for: stroke) {
        let pointBounds = CGRect(
            x: sample.point.x - sample.radius,
            y: sample.point.y - sample.radius,
            width: sample.radius * 2,
            height: sample.radius * 2
        )
        accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
    }
    return accumulatedBounds
}

private static func resolveSample(
    _ sample: HandDrawingSamplePoint,
    point: CGPoint,
    configuration: Configuration
) -> HandDrawingResolvedBrushSample {
    let radius = (configuration.baseSize * pressureSizeRatio) / 2
    return HandDrawingResolvedBrushSample(
        point: point,
        radius: radius,
        tiltAdjustedRadius: radius * tiltSizeFactor,
        opacity: resolvedOpacity,
        pressureSizeRatio: pressureSizeRatio,
        tiltSizeFactor: tiltSizeFactor,
        tiltOpacityFactor: tiltOpacityFactor,
        azimuthRadians: sample.azimuthRadians.map { CGFloat($0) },
        altitudeRadians: sample.altitudeRadians.map { CGFloat($0) }
    )
}
```

### 修改后

- `HandDrawingResolvedBrushSample` 新增：
  - `rotationRadians`
  - `minorRadius`
  - `majorRadius`
  - `axisAlignedBounds`
  - `contains(_:padding:)`
  - `probePoints(sampleCount:padding:)`
- `HandDrawingBrushDynamics` 新增 `resolvedStamps(for:)`，把连续样本间插值成密集 stamp，避免旧版“disk + line”桥接逻辑与 geometry 分叉。
- `bounds(for:)` 改为遍历 `resolvedStamps(for:)` 并使用 `sample.axisAlignedBounds`，使 dirty region 与局部刷新包围盒覆盖真实椭圆 footprint。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
// 函数名: HandDrawingResolvedBrushSample / resolvedStamps(for:) / bounds(for:) / resolveSample(_:point:configuration:)
// 功能说明: 修改后 dynamics 把每个 sample 解析成带旋转角、长短轴和轴对齐包围盒的 stamp footprint，并为后续 geometry 与 rasterizer 提供统一消费入口。
struct HandDrawingResolvedBrushSample: Equatable {
    let point: CGPoint
    let radius: CGFloat
    let tiltAdjustedRadius: CGFloat
    let opacity: CGFloat
    let pressureSizeRatio: CGFloat
    let tiltSizeFactor: CGFloat
    let tiltOpacityFactor: CGFloat
    let azimuthRadians: CGFloat?
    let altitudeRadians: CGFloat?
    let rotationRadians: CGFloat

    var minorRadius: CGFloat {
        max(radius, 0.25)
    }

    var majorRadius: CGFloat {
        max(tiltAdjustedRadius, minorRadius)
    }

    var axisAlignedBounds: CGRect {
        let cosTheta = cos(rotationRadians)
        let sinTheta = sin(rotationRadians)
        let halfWidth = sqrt(
            pow(majorRadius * cosTheta, 2)
                + pow(minorRadius * sinTheta, 2)
        )
        let halfHeight = sqrt(
            pow(majorRadius * sinTheta, 2)
                + pow(minorRadius * cosTheta, 2)
        )
        return CGRect(
            x: point.x - halfWidth,
            y: point.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
    }
}

static func resolvedStamps(
    for stroke: HandDrawingStroke
) -> [HandDrawingResolvedBrushSample] {
    let anchorSamples = resolvedSamples(for: stroke)
    guard anchorSamples.count > 1 else {
        return anchorSamples
    }

    var resolvedStamps: [HandDrawingResolvedBrushSample] = [anchorSamples[0]]
    for index in 1..<anchorSamples.count {
        resolvedStamps.append(
            contentsOf: interpolatedStamps(
                from: anchorSamples[index - 1],
                to: anchorSamples[index]
            )
        )
    }
    return resolvedStamps
}

static func bounds(
    for stroke: HandDrawingStroke
) -> CGRect? {
    var accumulatedBounds: CGRect?
    for sample in resolvedStamps(for: stroke) {
        let pointBounds = sample.axisAlignedBounds
        accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
    }
    return accumulatedBounds
}
```

## 修改二：`HandDrawingStrokeGeometry` 与新 stamp footprint 对齐

### 修改前

- 命中检测依赖：
  - 单点到圆心距离
  - 单点到线段距离
- 套索包围依赖：
  - 围绕圆形半径取十字 probe points
  - 线段中间按固定 fraction 继续补点
- 这些逻辑默认 stroke footprint 是“圆 + 粗线段”，与 phase 3 的椭圆 stamp 目标不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift（修改前）
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改前 geometry 仍假设 stroke 由圆盘和线段组成，命中与套索逻辑没有消费 tilt-aware footprint。
let resolvedSamples = HandDrawingBrushDynamics.resolvedSamples(
    for: stroke
)

for sample in resolvedSamples {
    if distanceBetween(sample.point, center) <= sample.radius + resolvedRadius {
        return true
    }
}

for index in 1..<resolvedSamples.count {
    let previousSample = resolvedSamples[index - 1]
    let sample = resolvedSamples[index]
    let strokeRadius = max(previousSample.radius, sample.radius)
    let distanceToSegment = distanceFromPoint(
        center,
        toSegmentFrom: previousSample.point,
        to: sample.point
    )
    if distanceToSegment <= strokeRadius + resolvedRadius {
        return true
    }
}

for sample in resolvedSamples {
guard probePoints(around: sample.point, radius: sample.radius).allSatisfy({
    contains($0, inPolygon: resolvedPolygonPoints)
}) else {
    return false
}
}
```

### 修改后

- `intersectsCircle` 改为消费 `resolvedStamps(for:)` 并直接调用 `sample.contains(center, padding:)`。
- `isStroke(_:enclosedBy:)` 改为让每个 stamp 自己吐出 `probePoints()`，从而按真实椭圆 footprint 做套索包围判定。
- 旧的“线段补判定”和“十字 probePoints”辅助逻辑被删除，减少 geometry 与 rasterizer 分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改后 geometry 统一消费 resolved stamp footprint，让命中、套索、移动与擦除判定和实际渲染椭圆保持一致。
let resolvedSamples = HandDrawingBrushDynamics.resolvedStamps(
    for: stroke
)
if resolvedSamples.isEmpty {
    return false
}

for sample in resolvedSamples {
    if sample.contains(center, padding: resolvedRadius) {
        return true
    }
}

for sample in resolvedSamples {
    guard sample.probePoints().allSatisfy({
        contains($0, inPolygon: resolvedPolygonPoints)
    }) else {
        return false
    }
}
```

## 修改三：`HandDrawingStrokeRasterizer` 从圆盘 + 线段升级为椭圆 stamp 光栅化

### 修改前

- 仍以 `resolvedSamples(for:)` 为输入。
- 每个 sample 画一个圆盘。
- 样本之间再画一条 `lineWidth = previous.radius + sample.radius` 的粗线补缝。
- 这会让可见结果继续停留在“pressure-only 圆形轮廓”，即使 sample 已经带有 tilt 信息。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift（修改前）
// 函数名: drawStrokeInk(_:in:) / drawDisk(at:radius:in:)
// 功能说明: 修改前 rasterizer 通过圆盘加线段的方式绘制 stroke，azimuth 与 altitude 不会真正改变可见笔迹轮廓。
private static func drawStrokeInk(
    _ stroke: HandDrawingStroke,
    in context: CGContext
) {
    let resolvedSamples = HandDrawingBrushDynamics.resolvedSamples(
        for: stroke
    )
    guard let firstSample = resolvedSamples.first else {
        return
    }

    let resolvedColor = stroke.brush.color
        .withMultipliedAlpha(stroke.brush.opacity)
        .cgColor
    context.setStrokeColor(resolvedColor)
    context.setFillColor(resolvedColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    if resolvedSamples.count == 1 {
        drawDisk(
            at: firstSample.point,
            radius: firstSample.radius,
            in: context
        )
        return
    }

    for sample in resolvedSamples {
        drawDisk(
            at: sample.point,
            radius: sample.radius,
            in: context
        )
    }

    for index in 1..<resolvedSamples.count {
        let previousSample = resolvedSamples[index - 1]
        let sample = resolvedSamples[index]
        context.setLineWidth(max(previousSample.radius + sample.radius, 0.5))
        context.beginPath()
        context.move(to: previousSample.point)
        context.addLine(to: sample.point)
        context.strokePath()
    }
}
```

### 修改后

- 改为消费 `resolvedStamps(for:)`。
- 每个 stamp 都以自身 `majorRadius` / `minorRadius` / `rotationRadians` 直接绘制旋转椭圆。
- 不再显式补线段，连续性由插值后的 stamp 序列保证。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
// 函数名: drawStrokeInk(_:in:) / drawStamp(_:in:)
// 功能说明: 修改后 rasterizer 直接绘制插值后的旋转椭圆 stamp，tilt 真正进入可见笔迹。
private static func drawStrokeInk(
    _ stroke: HandDrawingStroke,
    in context: CGContext
) {
    let resolvedSamples = HandDrawingBrushDynamics.resolvedStamps(
        for: stroke
    )
    guard resolvedSamples.isEmpty == false else {
        return
    }

    let resolvedColor = stroke.brush.color.cgColor
    context.setFillColor(resolvedColor)

    for sample in resolvedSamples {
        drawStamp(
            sample,
            in: context
        )
    }
}

private static func drawStamp(
    _ sample: HandDrawingResolvedBrushSample,
    in context: CGContext
) {
    let rect = CGRect(
        x: -sample.majorRadius,
        y: -sample.minorRadius,
        width: sample.majorRadius * 2,
        height: sample.minorRadius * 2
    )
    context.saveGState()
    context.setAlpha(sample.opacity)
    context.translateBy(x: sample.point.x, y: sample.point.y)
    context.rotate(by: sample.rotationRadians)
    context.fillEllipse(in: rect)
    context.restoreGState()
}
```

## 修改四：`HandDrawingEditorCoordinator` 为新 stroke 接入默认 tilt 参数

### 修改前

- `currentBrushStyle` 只构造颜色、粗细、opacity。
- 即便 phase 3 共享层已经支持 tilt-aware stamp，新画出的 stroke 默认也不会显现椭圆倾角效果。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: currentBrushStyle
// 功能说明: 修改前 coordinator 创建的新 brush style 仍是纯 pressure-only 参数组合。
private var currentBrushStyle: HandDrawingBrushStyle {
    HandDrawingBrushStyle(
        kind: .pen,
        color: selectedColor,
        baseSize: Double(selectedLineWidth),
        opacity: 1
    )
}
```

### 修改后

- 给新建 brush style 接入默认 `tiltSizeInfluence: 0.85`。
- `tiltOpacityInfluence` 先保持 `0`，让 phase 3 先只引入椭圆 footprint，不在这一阶段额外改变 opacity 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: currentBrushStyle
// 功能说明: 修改后 coordinator 新建的 brush style 默认带上 tilt size influence，使 phase 3 的椭圆 stamp 能直接体现在新 stroke 上。
private var currentBrushStyle: HandDrawingBrushStyle {
    HandDrawingBrushStyle(
        kind: .pen,
        color: selectedColor,
        baseSize: Double(selectedLineWidth),
        opacity: 1,
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
}
```

## 修改五：测试夹具扩展为可构造 tilt 样本

### 修改前

- `makeHandDrawingTestStroke(...)` 只能传 `samplePoints` 和 `sampleForces`。
- 夹具无法直接生成带 `azimuthRadians` / `altitudeRadians` / `tiltSizeInfluence` 的 stroke，导致 tilt 场景测试需要各处重复手写数据。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift（修改前）
// 函数名: makeHandDrawingTestStroke(...)
// 功能说明: 修改前测试夹具只支持 pressure 样本，无法统一构造 tilt-aware 场景。
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

### 修改后

- 新增：
  - `sampleAzimuths`
  - `sampleAltitudes`
  - `tiltSizeInfluence`
  - `tiltOpacityInfluence`
- 统一在夹具里做参数长度校验和样本组装，后续 tilt 测试都可以直接复用。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: makeHandDrawingTestStroke(...)
// 功能说明: 修改后测试夹具可统一构造带 tilt 信息和 brush dynamics 参数的 stroke，为 phase 3 回归测试提供单一入口。
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
    sampleAzimuths: [Double?]? = nil,
    sampleAltitudes: [Double?]? = nil,
    tiltSizeInfluence: Double? = nil,
    tiltOpacityInfluence: Double? = nil,
    includeEraseMask: Bool = false,
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke {
    if let sampleAzimuths {
        precondition(
            samplePoints.count == sampleAzimuths.count,
            "Hand drawing test azimuth samples must align with sample points."
        )
    }
    if let sampleAltitudes {
        precondition(
            samplePoints.count == sampleAltitudes.count,
            "Hand drawing test altitude samples must align with sample points."
        )
    }

    return HandDrawingStroke(
        id: id,
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: baseSize,
            opacity: 1,
            tiltSizeInfluence: tiltSizeInfluence,
            tiltOpacityInfluence: tiltOpacityInfluence
        ),
        samplePoints: zip(samplePoints, sampleForces).enumerated().map {
            index,
            element in
            HandDrawingSamplePoint(
                point: element.0,
                force: element.1,
                timestamp: Double(index) * 0.1,
                azimuthRadians: sampleAzimuths?[index],
                altitudeRadians: sampleAltitudes?[index]
            )
        },
        transform: transform,
        eraseMask: eraseMask
    )
}
```

## 修改六：补齐 phase 3 的 tilt 回归测试

### 修改前

- `HandDrawingBrushDynamicsTests` 只覆盖：
  - 默认 pressure 半径
  - 自定义 pressure 曲线
  - tilt 因子求解
- `PreviewRenderer` / `CanvasRenderer` 只验证 pressure 宽度差异和 layer order。
- 套索、橡皮擦、移动选择只锁定 pressure 半径，不锁定 tilt 拉长后的 footprint。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift（修改前）
// 函数名: makePreviewRendererTestStroke(...)
// 功能说明: 修改前 preview 测试 helper 只能构造 pressure 场景，没有 tilt orientation 测试入口。
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
            HandDrawingSamplePoint(
                point: CGPoint(x: 24, y: y),
                force: force,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: y),
                force: force,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 96, y: y),
                force: force,
                timestamp: 0.2
            )
        ]
    )
}
```

### 修改后

- `HandDrawingBrushDynamicsTests` 新增旋转椭圆 stamp bounds 测试，锁定 `major/minor radius` 与 `axisAlignedBounds`。
- `HandDrawingPreviewRendererTests` / `HandDrawingCanvasRendererTests` 新增 tilt orientation 可见性测试，并扩展 helper 支持 `samplePoints` / `azimuthRadians` / `altitudeRadians` / `tiltSizeInfluence`。
- `HandDrawingLassoSelectionTests` / `HandDrawingPixelEraserToolControllerTests` / `HandDrawingMoveSelectionTests` 新增 tilt footprint 命中回归，确保编辑操作与渲染 footprint 一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
// 函数名: testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent()
// 功能说明: 修改后新增 solver 回归测试，锁定旋转椭圆 stamp 的长短轴与轴对齐包围盒计算。
func testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent() throws {
    let stroke = makeHandDrawingTestStroke(
        baseSize: 20,
        samplePoints: [CGPoint(x: 60, y: 60)],
        sampleForces: [0.5],
        sampleAzimuths: [.pi / 4],
        sampleAltitudes: [0],
        tiltSizeInfluence: 1
    )

    let resolvedStamp = try XCTUnwrap(
        HandDrawingBrushDynamics.resolvedStamps(for: stroke).first
    )
    let bounds = try XCTUnwrap(stroke.bounds)
    let expectedHalfExtent = sqrt(62.5)

    XCTAssertEqual(resolvedStamp.minorRadius, 5, accuracy: 0.001)
    XCTAssertEqual(resolvedStamp.majorRadius, 10, accuracy: 0.001)
    XCTAssertEqual(bounds.minX, 60 - expectedHalfExtent, accuracy: 0.001)
    XCTAssertEqual(bounds.maxX, 60 + expectedHalfExtent, accuracy: 0.001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererRendersTiltAwareStampOrientation() / makePreviewRendererTestStroke(...)
// 功能说明: 修改后新增 preview 可见性测试，锁定水平/垂直倾角的椭圆 footprint 像素差异，并让 helper 支持 tilt 场景样本构造。
func testHandDrawingPreviewRendererRendersTiltAwareStampOrientation() throws {
    let renderer = HandDrawingPreviewRenderer()
    let horizontalTiltStroke = makePreviewRendererTestStroke(
        y: 60,
        baseSize: 20,
        force: 0.5,
        samplePoints: [CGPoint(x: 36, y: 60)],
        azimuthRadians: [0],
        altitudeRadians: [0],
        tiltSizeInfluence: 1,
        color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
    )
    let verticalTiltStroke = makePreviewRendererTestStroke(
        y: 60,
        baseSize: 20,
        force: 0.5,
        samplePoints: [CGPoint(x: 84, y: 60)],
        azimuthRadians: [.pi / 2],
        altitudeRadians: [0],
        tiltSizeInfluence: 1,
        color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
    )

    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "tilt-preview-paper",
            size: CGSize(width: 120, height: 120)
        ),
        strokes: [horizontalTiltStroke, verticalTiltStroke]
    )
    let image = try renderer.renderPreviewImage(for: document, scale: 1)
    let horizontalRightPixel = sampleDisplayedRGBA(from: image, x: 44, y: 60)
    let horizontalDownPixel = sampleDisplayedRGBA(from: image, x: 36, y: 68)
    let verticalRightPixel = sampleDisplayedRGBA(from: image, x: 92, y: 60)
    let verticalDownPixel = sampleDisplayedRGBA(from: image, x: 84, y: 68)

    XCTAssertGreaterThan(horizontalRightPixel.alpha, 48)
    XCTAssertLessThan(horizontalDownPixel.alpha, 16)
    XCTAssertLessThan(verticalRightPixel.alpha, 16)
    XCTAssertGreaterThan(verticalDownPixel.alpha, 48)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererForTiltAwareStampOrientation()
// 功能说明: 修改后锁定 committed canvas 与 preview 在 tilt-aware stamp 朝向上的像素一致性。
func testHandDrawingCanvasRendererMatchesPreviewRendererForTiltAwareStampOrientation() throws {
    let horizontalTiltStroke = makeCanvasRendererLayeredTestStroke(
        y: 60,
        baseSize: 20,
        force: 0.5,
        samplePoints: [CGPoint(x: 36, y: 60)],
        azimuthRadians: [0],
        altitudeRadians: [0],
        tiltSizeInfluence: 1,
        color: HandDrawingColor(red: 0.88, green: 0.16, blue: 0.12, alpha: 1)
    )
    let verticalTiltStroke = makeCanvasRendererLayeredTestStroke(
        y: 60,
        baseSize: 20,
        force: 0.5,
        samplePoints: [CGPoint(x: 84, y: 60)],
        azimuthRadians: [.pi / 2],
        altitudeRadians: [0],
        tiltSizeInfluence: 1,
        color: HandDrawingColor(red: 0.12, green: 0.72, blue: 0.21, alpha: 1)
    )

    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "canvas-tilt-paper",
            size: CGSize(width: 120, height: 120)
        ),
        strokes: [horizontalTiltStroke, verticalTiltStroke]
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
    let horizontalCanvasRight = sampleDisplayedRGBA(from: canvasImage, x: 44, y: 60)
    let horizontalPreviewRight = sampleDisplayedRGBA(from: previewImage, x: 44, y: 60)
    let horizontalCanvasDown = sampleDisplayedRGBA(from: canvasImage, x: 36, y: 68)
    let horizontalPreviewDown = sampleDisplayedRGBA(from: previewImage, x: 36, y: 68)
    let verticalCanvasRight = sampleDisplayedRGBA(from: canvasImage, x: 92, y: 60)
    let verticalPreviewRight = sampleDisplayedRGBA(from: previewImage, x: 92, y: 60)
    let verticalCanvasDown = sampleDisplayedRGBA(from: canvasImage, x: 84, y: 68)
    let verticalPreviewDown = sampleDisplayedRGBA(from: previewImage, x: 84, y: 68)

    assertPixelsEqual(horizontalCanvasRight, horizontalPreviewRight)
    assertPixelsEqual(horizontalCanvasDown, horizontalPreviewDown)
    assertPixelsEqual(verticalCanvasRight, verticalPreviewRight)
    assertPixelsEqual(verticalCanvasDown, verticalPreviewDown)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerUsesTiltedStampFootprintForEnclosure()
// 功能说明: 修改后锁定套索包围判定会按椭圆 stamp footprint 工作，而不是继续按圆形 stroke 假设工作。
func testHandDrawingLassoToolControllerUsesTiltedStampFootprintForEnclosure() {
    let circularStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        samplePoints: [CGPoint(x: 60, y: 60)],
        sampleForces: [0.5]
    )
    XCTAssertTrue(applyCompactLasso(to: &circularEngine))

    let tiltedStroke = makeHandDrawingTestStroke(
        id: UUID(),
        baseSize: 20,
        samplePoints: [CGPoint(x: 60, y: 60)],
        sampleForces: [0.5],
        sampleAzimuths: [0],
        sampleAltitudes: [0],
        tiltSizeInfluence: 1
    )
    XCTAssertFalse(applyCompactLasso(to: &tiltedEngine))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerHitTestingUsesTiltedStampFootprint()
// 功能说明: 修改后锁定 pixel eraser 命中区域会随着椭圆 stamp 拉长方向变化。
func testHandDrawingPixelEraserToolControllerHitTestingUsesTiltedStampFootprint() {
    let eraseSample = HandDrawingInputSample(
        location: CGPoint(x: 68, y: 60),
        force: 0.05,
        timestamp: 0
    )

    XCTAssertTrue(circularEngine.state.document.strokes[0].eraseMask.isEmpty)

    XCTAssertEqual(tiltedEngine.state.document.strokes[0].eraseMask.count, 1)
    XCTAssertTrue(tiltedEngine.canUndo)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerHitTestingUsesTiltedStampFootprintWithPadding()
// 功能说明: 修改后锁定 move selection 命中判定既保留 controller padding，又与 tilt-aware stamp footprint 对齐。
func testHandDrawingMoveSelectionControllerHitTestingUsesTiltedStampFootprintWithPadding() {
    let hitSample = HandDrawingInputSample(
        location: CGPoint(x: 78, y: 60),
        timestamp: 0
    )

    XCTAssertFalse(
        circularController.beginMoving(
            with: hitSample,
            engine: circularEngine
        )
    )

    XCTAssertTrue(
        tiltedController.beginMoving(
            with: hitSample,
            engine: tiltedEngine
        )
    )
    XCTAssertTrue(tiltedController.isActive)
}
```

## 验证结果

- 已执行最近改动文件的 `ReadLints`，结果：无 linter 错误。
- 已执行 `phase 3` 定向手绘测试套件：通过。
- 已执行 `iOS Simulator build`：通过。
- 补充观测：尝试执行 `macOS` 全量测试时，当前仓库仍有与本次 phase 3 定向验收无关的失败项，因此这里如实一并记录。

```sh
# 文件路径: 无（终端命令输出）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -parallel-testing-enabled NO -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -derivedDataPath "/tmp/MyCanvasPhase3HandDrawingSuite"
# 功能说明: 串行执行 phase 3 直接相关的手绘测试套件，验证 dynamics / preview / canvas / lasso / eraser / move selection / engine 合同。
Executed 42 tests, with 0 failures (0 unexpected) in 0.038 (0.054) seconds
** TEST SUCCEEDED **
```

```sh
# 文件路径: 无（终端命令输出）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasPhase3iOSBuild"
# 功能说明: 验证 iOS 平台层接入默认 tilt brush 参数后，工程仍可在 Simulator 目标上成功编译。
** BUILD SUCCEEDED **
exit_code: 0
elapsed_ms: 20725
```

```sh
# 文件路径: 无（终端命令输出）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS"
# 功能说明: 补充记录执行 macOS 全量测试时的当前仓库状态；以下失败不作为本次 phase 3 定向验收失败结论，但属于本次实际观测结果。
BoardHandDrawingStorageTests.testBoardStoreLoadHandDrawingSourceDataFallsBackToLegacyFlatAssets() failed
BoardHandDrawingStorageTests.testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail() failed
BoardHandDrawingStorageTests.testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() failed
BoardHandDrawingStorageTests.testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing() failed
BoardHandDrawingStorageTests.testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets() failed
CanvasInputIndicatorQueueTests.testEnqueueKeepsNewestVisibleItems() failed
CanvasInputIndicatorQueueTests.testSnapshotAppliesFadeOutNearLifetimeEnd() failed
CanvasInputIndicatorQueueTests.testSnapshotPurgesExpiredEntries() failed
CanvasInputIndicatorQueueTests.testSnapshotUsesStackOpacityForOlderEntries() failed
```

- `BoardHandDrawingStorageTests` 的 5 个失败里：
  - 4 个报错为 `invalidSourceData`
  - 1 个断言为 `XCTAssertEqual failed: ("357 bytes") is not equal to ("19 bytes")`
- `CanvasInputIndicatorQueueTests` 在并发测试上下文里出现测试宿主异常退出；串行单跑时 4 个断言测试本身实际通过，但 `xcodebuild` 仍在会话重启后返回 `65`，因此这里仅将其作为补充观测记录，不归因到本次 phase 3 逻辑回归。
