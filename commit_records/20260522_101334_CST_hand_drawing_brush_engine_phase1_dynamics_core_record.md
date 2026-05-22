# 20260522_101334_CST_hand_drawing_brush_engine_phase1_dynamics_core_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 1`，把当前散落在 `radiusForSample(at:)` 的笔刷动力学抽成统一求解层。
  - 在不提升 `HandDrawingDocument.currentFormatVersion` 的前提下，为 `HandDrawingBrushStyle` 增加可选 dynamics 参数，并保持旧文档默认兼容。
  - 让 `HandDrawingStroke.radiusForSample(at:)`、`stroke.bounds`、`HandDrawingStrokeGeometry`、`HandDrawingStrokeRasterizer` 统一改为消费新的 brush dynamics 求解结果。
  - 新增 dynamics 单元测试，以及 brush dynamics 参数的 codec round-trip 测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_101334_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次已跟踪文件执行 `git diff --stat -- ...`，结果为：`4 files changed, 233 insertions(+), 77 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示：
    - 4 个已跟踪修改文件：`HandDrawingDocument.swift`、`HandDrawingStrokeGeometry.swift`、`HandDrawingStrokeRasterizer.swift`、`HandDrawingDocumentCodecTests.swift`
    - 2 个新增未跟踪文件：`HandDrawingBrushDynamics.swift`、`HandDrawingBrushDynamicsTests.swift`
  - 因此，本记录同时参考 `git diff` 和 `current changes`；新增文件由 `git status` 与当前文件内容共同说明。
- 本记录不包含：
  - `phase 0` 的测试基线补充记录。
  - `phase 2` 的 `InputNormalizer` / `StrokeBuilder` 重构。
  - `phase 3` 的 tilt-aware raster stamp 渲染接线。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统命令生成本次 phase 1 markdown 记录文件的时间戳前缀。
20260522_101334_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
# 功能说明: 汇总本次 phase 1 已跟踪文件的 diff 统计；新增未跟踪文件不会出现在这里。
.../HandDrawing/Core/HandDrawingDocument.swift     | 166 ++++++++++++++++-----
.../Editing/HandDrawingStrokeGeometry.swift        |  54 +++----
.../Rendering/HandDrawingStrokeRasterizer.swift    |  31 ++--
.../HandDrawingDocumentCodecTests.swift            |  59 ++++++++
4 files changed, 233 insertions(+), 77 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
# 功能说明: 记录本次 phase 1 触达文件的当前 changes 状态，补充显示新增未跟踪文件。
M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
M MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
?? MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
```

## 当前 changes 摘要

- `HandDrawingBrushStyle` 从仅包含 `baseSize` / `opacity` 的简单样式，升级为包含可选 dynamics 参数的兼容型样式结构，并补上显式 `Codable` 编解码与归一化逻辑。
- 新增 `HandDrawingBrushDynamics` 作为统一动力学求解层，集中产出：
  - `Configuration`
  - `radius(for:with:)`
  - `resolvedSamples(for:)`
  - `bounds(for:)`
  - pressure 曲线、size ratio clamp、tilt 因子解析
- `HandDrawingStroke.radiusForSample(at:)` 和 `stroke.bounds` 不再各自内联笔刷数学，而是委托给统一 solver。
- `HandDrawingStrokeGeometry` 与 `HandDrawingStrokeRasterizer` 不再一边遍历一边各自重复计算半径，而是统一消费 `HandDrawingResolvedBrushSample`。
- 新增 `HandDrawingBrushDynamicsTests` 直接锁定：
  - 默认配置兼容当前 pressure-only 半径
  - 自定义 pressure curve / min / max size ratio
  - tilt 因子解析但不提前改变当前半径合同
- `HandDrawingDocumentCodecTests` 新增 brush dynamics 参数 round-trip 测试，保证不升文档格式版本也能稳定存取新字段。

## 修改一：`HandDrawingBrushStyle` 扩展为可兼容的 dynamics 参数载体

### 修改前

- `HandDrawingBrushStyle` 只有 `kind`、`color`、`baseSize`、`opacity`。
- `Codable` 依赖合成实现，没有单独的归一化逻辑。
- `HandDrawingSamplePoint` 里有 `resolvedForce`，而 `HandDrawingStroke.radiusForSample(at:)` 直接在模型层内联做 `baseSize * resolvedForce / 2`。
- `stroke.bounds` 也直接在模型层里逐点手工计算。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift（修改前）
// 函数名: HandDrawingBrushStyle.init(...) / HandDrawingSamplePoint.resolvedForce / HandDrawingStroke.radiusForSample(at:) / HandDrawingStroke.bounds
// 功能说明: 修改前 brush style 只是简单样式容器，半径与 bounds 计算直接散落在文档模型里。
struct HandDrawingBrushStyle: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case pen
    }

    static let defaultPen = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 6,
        opacity: 1
    )

    var kind: Kind
    var color: HandDrawingColor
    var baseSize: Double
    var opacity: Double

    init(
        kind: Kind = .pen,
        color: HandDrawingColor = .black,
        baseSize: Double = 6,
        opacity: Double = 1
    ) {
        self.kind = kind
        self.color = color
        self.baseSize = max(baseSize, 0.25)
        self.opacity = min(max(opacity, 0), 1)
    }
}

struct HandDrawingSamplePoint: Codable, Equatable {
    // ... 省略其他字段 ...

    var resolvedForce: CGFloat {
        CGFloat(max(force, 0.05))
    }
}

struct HandDrawingStroke: Codable, Equatable {
    // ... 省略其他字段 ...

    func radiusForSample(at index: Int) -> CGFloat {
        guard samplePoints.indices.contains(index) else {
            return CGFloat(brush.baseSize) / 2
        }
        return CGFloat(brush.baseSize) * samplePoints[index].resolvedForce / 2
    }

    var bounds: CGRect? {
        var accumulatedBounds: CGRect?
        let transformedPoints = transformedSamplePoints
        for (index, point) in transformedPoints.enumerated() {
            let radius = radiusForSample(at: index)
            let pointBounds = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
        }
        // ... 省略 eraseMask bounds 合并逻辑 ...
        return accumulatedBounds
    }
}
```

### 修改后

- `HandDrawingBrushStyle` 新增 5 个可选 dynamics 字段：
  - `pressureCurveExponent`
  - `minSizeRatio`
  - `maxSizeRatio`
  - `tiltSizeInfluence`
  - `tiltOpacityInfluence`
- 补上显式 `CodingKeys`、`init(from:)`、`encode(to:)`、以及各类归一化 helper，保证旧文档缺字段时自动回落到当前默认行为。
- 删除 `HandDrawingSamplePoint.resolvedForce`，把 pressure 归一化职责移交给统一 dynamics 层。
- `radiusForSample(at:)` 和 `bounds` 改为委托 `HandDrawingBrushDynamics`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingBrushStyle.init(...) / HandDrawingBrushStyle.init(from:) / HandDrawingBrushStyle.encode(to:) / HandDrawingStroke.radiusForSample(at:) / HandDrawingStroke.bounds
// 功能说明: 修改后 brush style 既能承载后续 phase 3/4 的 dynamics 参数，又能在默认值下保持当前 pressure-only 兼容；半径与 bounds 统一委托给 dynamics 求解器。
struct HandDrawingBrushStyle: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case pen
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case color
        case baseSize
        case opacity
        case pressureCurveExponent
        case minSizeRatio
        case maxSizeRatio
        case tiltSizeInfluence
        case tiltOpacityInfluence
    }

    static let defaultPen = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 6,
        opacity: 1
    )

    var kind: Kind
    var color: HandDrawingColor
    var baseSize: Double
    var opacity: Double
    var pressureCurveExponent: Double?
    var minSizeRatio: Double?
    var maxSizeRatio: Double?
    var tiltSizeInfluence: Double?
    var tiltOpacityInfluence: Double?

    init(
        kind: Kind = .pen,
        color: HandDrawingColor = .black,
        baseSize: Double = 6,
        opacity: Double = 1,
        pressureCurveExponent: Double? = nil,
        minSizeRatio: Double? = nil,
        maxSizeRatio: Double? = nil,
        tiltSizeInfluence: Double? = nil,
        tiltOpacityInfluence: Double? = nil
    ) {
        self.kind = kind
        self.color = color
        let resolvedBaseSize = baseSize.isFinite ? baseSize : 6
        let resolvedOpacity = opacity.isFinite ? opacity : 1
        let resolvedMinSizeRatio = Self.normalizedNonNegativeOptional(minSizeRatio)
        self.baseSize = max(resolvedBaseSize, 0.25)
        self.opacity = min(max(resolvedOpacity, 0), 1)
        self.pressureCurveExponent = Self.normalizedPositiveOptional(
            pressureCurveExponent
        )
        self.minSizeRatio = resolvedMinSizeRatio
        self.maxSizeRatio = Self.normalizedMaximumOptional(
            maxSizeRatio,
            minimum: resolvedMinSizeRatio
        )
        self.tiltSizeInfluence = Self.normalizedNonNegativeOptional(
            tiltSizeInfluence
        )
        self.tiltOpacityInfluence = Self.normalizedNonNegativeOptional(
            tiltOpacityInfluence
        )
    }

    // ... 省略若干 encode/decode 与归一化 helper ...
}

struct HandDrawingStroke: Codable, Equatable {
    // ... 省略其他字段 ...

    func radiusForSample(at index: Int) -> CGFloat {
        HandDrawingBrushDynamics.radius(
            forSampleAt: index,
            in: self
        )
    }

    var bounds: CGRect? {
        HandDrawingBrushDynamics.bounds(for: self)
    }
}
```

## 修改二：新增统一的 `HandDrawingBrushDynamics` 求解器

### 修改前

- `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift` 文件不存在。
- 笔刷动力学没有集中入口，pressure / bounds / geometry / rasterizer 的语义耦合在多个位置。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有统一 brush dynamics 求解器文件，半径与几何语义分散在多个实现点。
// 文件不存在
```

### 修改后

- 新增 `HandDrawingResolvedBrushSample`，作为统一的 sample 解析结果。
- 新增 `HandDrawingBrushDynamics`，集中负责：
  - 把 `HandDrawingBrushStyle` 解析成 `Configuration`
  - 计算默认 / 自定义 pressure 曲线下的 size ratio 与半径
  - 生成 `resolvedSamples(for:)`
  - 统一计算 `bounds(for:)`
  - 预先解析 tilt size / opacity 因子，为后续 tilt-aware 渲染预留接口
- `phase 1` 仍保持 `bounds` 与当前 pressure-only 半径对齐，没有提前把 tiltAdjustedRadius 接进现有 invalidation 合同。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
// 函数名: configuration(for:) / radius(for:with:) / resolvedSamples(for:) / bounds(for:) / resolvePressureSizeRatio(for:configuration:) / resolveTiltFactor(altitudeRadians:influence:)
// 功能说明: 修改后统一动力学求解器集中负责 brush configuration、半径、resolved sample、bounds 和 tilt 因子解析，成为后续 phase 2/3 的单一真相源。
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

enum HandDrawingBrushDynamics {
    private static let defaultMinimumSizeRatio: CGFloat = 0.05
    private static let defaultPressureCurveExponent: CGFloat = 1

    struct Configuration: Equatable {
        let baseSize: CGFloat
        let baseOpacity: CGFloat
        let pressureCurveExponent: CGFloat
        let minSizeRatio: CGFloat
        let maxSizeRatio: CGFloat?
        let tiltSizeInfluence: CGFloat
        let tiltOpacityInfluence: CGFloat
    }

    static func configuration(
        for brush: HandDrawingBrushStyle
    ) -> Configuration {
        Configuration(
            baseSize: CGFloat(brush.baseSize),
            baseOpacity: CGFloat(brush.opacity),
            pressureCurveExponent: CGFloat(
                brush.pressureCurveExponent ?? Double(defaultPressureCurveExponent)
            ),
            minSizeRatio: CGFloat(
                brush.minSizeRatio ?? Double(defaultMinimumSizeRatio)
            ),
            maxSizeRatio: brush.maxSizeRatio.map { CGFloat($0) },
            tiltSizeInfluence: CGFloat(brush.tiltSizeInfluence ?? 0),
            tiltOpacityInfluence: CGFloat(brush.tiltOpacityInfluence ?? 0)
        )
    }

    static func radius(
        for sample: HandDrawingSamplePoint?,
        with brush: HandDrawingBrushStyle
    ) -> CGFloat {
        let configuration = configuration(for: brush)
        return resolveRadius(for: sample, configuration: configuration)
    }

    static func resolvedSamples(
        for stroke: HandDrawingStroke
    ) -> [HandDrawingResolvedBrushSample] {
        let transformedPoints = stroke.transformedSamplePoints
        let configuration = configuration(for: stroke.brush)
        return stroke.samplePoints.enumerated().compactMap { index, sample in
            guard transformedPoints.indices.contains(index) else {
                return nil
            }
            return resolveSample(
                sample,
                point: transformedPoints[index],
                configuration: configuration
            )
        }
    }

    static func bounds(
        for stroke: HandDrawingStroke
    ) -> CGRect? {
        var accumulatedBounds: CGRect?
        for sample in resolvedSamples(for: stroke) {
            // Phase 1 keeps bounds on the current pressure-only radius.
            let pointBounds = CGRect(
                x: sample.point.x - sample.radius,
                y: sample.point.y - sample.radius,
                width: sample.radius * 2,
                height: sample.radius * 2
            )
            accumulatedBounds = accumulatedBounds?.union(pointBounds) ?? pointBounds
        }
        // ... 省略 eraseMask bounds 合并逻辑 ...
        return accumulatedBounds
    }

    private static func resolvePressureSizeRatio(
        for sample: HandDrawingSamplePoint?,
        configuration: Configuration
    ) -> CGFloat {
        let rawForce = sample?.force ?? 1
        let finiteForce = rawForce.isFinite ? rawForce : 1
        let inputRatio = max(CGFloat(finiteForce), configuration.minSizeRatio)
        var resolvedSizeRatio = CGFloat(
            Foundation.pow(
                Double(inputRatio),
                Double(configuration.pressureCurveExponent)
            )
        )
        resolvedSizeRatio = max(resolvedSizeRatio, configuration.minSizeRatio)
        if let maxSizeRatio = configuration.maxSizeRatio {
            resolvedSizeRatio = min(resolvedSizeRatio, maxSizeRatio)
        }
        return resolvedSizeRatio
    }

    private static func resolveTiltFactor(
        altitudeRadians: Double?,
        influence: CGFloat
    ) -> CGFloat {
        guard
            influence > 0,
            let normalizedTilt = normalizedTilt(
                altitudeRadians: altitudeRadians
            )
        else {
            return 1
        }
        return 1 + (normalizedTilt * influence)
    }
}
```

## 修改三：`geometry` 与 `rasterizer` 改为消费统一 `resolvedSamples`

### 3.1 `HandDrawingStrokeGeometry`

#### 修改前

- `intersectsCircle(...)` 与 `isStroke(..., enclosedBy:)` 直接依赖：
  - `stroke.transformedSamplePoints`
  - `stroke.radiusForSample(at:)`
- 这意味着 geometry 层仍在自己拼“点 + 半径”的语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift（修改前）
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改前 geometry 一边遍历 transformed points，一边重复调用 radiusForSample(at:) 组装当前 stroke 几何。
let transformedPoints = stroke.transformedSamplePoints
if transformedPoints.isEmpty {
    return false
}

for (index, point) in transformedPoints.enumerated() {
    let strokeRadius = stroke.radiusForSample(at: index)
    if distanceBetween(point, center) <= strokeRadius + resolvedRadius {
        return true
    }
}

for index in 1..<transformedPoints.count {
    let startPoint = transformedPoints[index - 1]
    let endPoint = transformedPoints[index]
    let strokeRadius = max(
        stroke.radiusForSample(at: index - 1),
        stroke.radiusForSample(at: index)
    )
    // ... 省略后续 segment 命中计算 ...
}
```

#### 修改后

- `geometry` 改为一次性拿到 `HandDrawingBrushDynamics.resolvedSamples(for:)`。
- 后续所有命中、包围、segment 采样都只消费统一求解后的 `point` + `radius`。
- 这样后面 phase 3 真正引入 tilt-aware footprint 时，几何层只需要继续围绕统一结果进化，而不是重新散改每个调用点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: intersectsCircle(_:center:radius:) / isStroke(_:enclosedBy:)
// 功能说明: 修改后 geometry 统一消费 HandDrawingResolvedBrushSample，避免在命中与包围逻辑里重复拼接半径语义。
let resolvedSamples = HandDrawingBrushDynamics.resolvedSamples(
    for: stroke
)
if resolvedSamples.isEmpty {
    return false
}

for sample in resolvedSamples {
    if distanceBetween(sample.point, center) <= sample.radius + resolvedRadius {
        return true
    }
}

for index in 1..<resolvedSamples.count {
    let previousSample = resolvedSamples[index - 1]
    let sample = resolvedSamples[index]
    let strokeRadius = max(
        previousSample.radius,
        sample.radius
    )
    // ... 省略后续 segment 命中与 probePoints 包围判断 ...
}
```

### 3.2 `HandDrawingStrokeRasterizer`

#### 修改前

- `drawStrokeInk(...)` 直接基于 `stroke.transformedSamplePoints` 和 `stroke.radiusForSample(at:)` 画圆盘与线段。
- 渲染层和 geometry 层一样，都在重复读取 stroke 并各自拼当前半径语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift（修改前）
// 函数名: drawStrokeInk(_:in:)
// 功能说明: 修改前 rasterizer 直接遍历 transformed points，并重复调用 radiusForSample(at:) 决定 disk 半径与 lineWidth。
let points = stroke.transformedSamplePoints
guard let firstPoint = points.first else {
    return
}

if points.count == 1 {
    drawDisk(
        at: firstPoint,
        radius: stroke.radiusForSample(at: 0),
        in: context
    )
    return
}

for index in 0..<points.count {
    drawDisk(
        at: points[index],
        radius: stroke.radiusForSample(at: index),
        in: context
    )
}

for index in 1..<points.count {
    let lineWidth = stroke.radiusForSample(at: index - 1)
        + stroke.radiusForSample(at: index)
    // ... 省略后续 line stroke 绘制 ...
}
```

#### 修改后

- rasterizer 改为一次性消费 `resolvedSamples`。
- 单点笔迹、逐点 disk、连线宽度都从统一样本结果读取。
- 这一步还没有把 `tiltAdjustedRadius` 接进光栅化；当前渲染仍然保持 phase 0 的 pressure-only 合同。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
// 函数名: drawStrokeInk(_:in:)
// 功能说明: 修改后 rasterizer 与 geometry 共用同一套 resolved sample 语义，为后续 tilt-aware stamp 渲染预留统一接入点。
let resolvedSamples = HandDrawingBrushDynamics.resolvedSamples(
    for: stroke
)
guard let firstSample = resolvedSamples.first else {
    return
}

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
    let lineWidth = previousSample.radius + sample.radius
    // ... 省略后续 line stroke 绘制 ...
}
```

## 修改四：补充 dynamics 单测与 codec round-trip 回归

### 4.1 新增 `HandDrawingBrushDynamicsTests.swift`

#### 修改前

- `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift` 文件不存在。
- 没有任何测试直接锁定新的 dynamics solver 默认兼容与自定义参数行为。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有统一 brush dynamics 的独立测试文件。
// 文件不存在
```

#### 修改后

- 新增 3 组直接围绕 solver 的测试：
  - `testHandDrawingBrushDynamicsDefaultConfigurationMatchesCurrentPressureOnlyRadiusMapping()`
  - `testHandDrawingBrushDynamicsCustomPressureCurveAndBoundsStayInSync()`
  - `testHandDrawingBrushDynamicsResolvesTiltFactorsWithoutChangingCurrentRadiusSemantics()`
- 这些测试既锁住 phase 0 的默认兼容，又开始为 phase 3 的 tilt 扩展保留回归护栏。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
// 函数名: testHandDrawingBrushDynamicsDefaultConfigurationMatchesCurrentPressureOnlyRadiusMapping() / testHandDrawingBrushDynamicsCustomPressureCurveAndBoundsStayInSync() / testHandDrawingBrushDynamicsResolvesTiltFactorsWithoutChangingCurrentRadiusSemantics()
// 功能说明: 修改后独立测试文件直接锁定 solver 的默认兼容、自定义 pressure 曲线和 tilt 因子解析结果。
@MainActor
final class HandDrawingBrushDynamicsTests: XCTestCase {
    func testHandDrawingBrushDynamicsDefaultConfigurationMatchesCurrentPressureOnlyRadiusMapping() {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 0.8
        )

        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: HandDrawingSamplePoint(point: .zero, force: 0.25, timestamp: 0),
                with: brush
            ),
            2.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            HandDrawingBrushDynamics.radius(
                for: HandDrawingSamplePoint(point: .zero, force: 1, timestamp: 0.1),
                with: brush
            ),
            10,
            accuracy: 0.001
        )
    }

    func testHandDrawingBrushDynamicsCustomPressureCurveAndBoundsStayInSync() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 1,
            pressureCurveExponent: 2,
            minSizeRatio: 0.2,
            maxSizeRatio: 0.8
        )
        // ... 省略 stroke 构造 ...
        XCTAssertEqual(stroke.radiusForSample(at: 0), 2, accuracy: 0.001)
        XCTAssertEqual(stroke.radiusForSample(at: 2), 8, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 103, accuracy: 0.001)
    }

    func testHandDrawingBrushDynamicsResolvesTiltFactorsWithoutChangingCurrentRadiusSemantics() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 20,
            opacity: 0.8,
            tiltSizeInfluence: 0.6,
            tiltOpacityInfluence: 0.25
        )
        // ... 省略 stroke 构造 ...
        XCTAssertEqual(resolvedSample.radius, 5, accuracy: 0.001)
        XCTAssertGreaterThan(resolvedSample.tiltAdjustedRadius, resolvedSample.radius)
        XCTAssertGreaterThan(resolvedSample.opacity, 0.8)
    }
}
```

### 4.2 `HandDrawingDocumentCodecTests` 新增 brush dynamics 参数 round-trip

#### 修改前

- codec 测试已经覆盖自定义文档 round-trip、legacy flat 解码、manifest、preview PNG、非法版本/非法图片数据。
- 但修改前没有任何一个用例验证：新增的 brush dynamics 字段能否在当前文档版本下正常编解码。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift（修改前）
// 函数名: testHandDrawingDocumentCodecRoundTripsCustomDocument() / testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument()
// 功能说明: 修改前 codec 测试覆盖已有文档结构，但没有 dynamics 参数 round-trip 回归。
@MainActor
final class HandDrawingDocumentCodecTests: XCTestCase {
    func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
        // ... 现有 round-trip 测试 ...
    }

    func testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument() throws {
        // ... 现有 legacy 解码测试 ...
    }
}
```

#### 修改后

- 新增 `testHandDrawingDocumentCodecRoundTripsBrushDynamicsParameters()`。
- 用带 dynamics 参数的 `HandDrawingBrushStyle` 构造 stroke，编码再解码后验证：
  - 文档整体仍相等
  - `pressureCurveExponent`
  - `minSizeRatio`
  - `maxSizeRatio`
  - `tiltSizeInfluence`
  - `tiltOpacityInfluence`
  都能原样 round-trip

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
// 函数名: testHandDrawingDocumentCodecRoundTripsBrushDynamicsParameters()
// 功能说明: 修改后 codec 测试显式锁定新增 brush dynamics 参数在当前文档格式版本下的 round-trip 兼容性。
func testHandDrawingDocumentCodecRoundTripsBrushDynamicsParameters() throws {
    let stroke = HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.26, green: 0.31, blue: 0.84, alpha: 1),
            baseSize: 18,
            opacity: 0.9,
            pressureCurveExponent: 1.8,
            minSizeRatio: 0.16,
            maxSizeRatio: 0.92,
            tiltSizeInfluence: 0.55,
            tiltOpacityInfluence: 0.25
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 24, y: 24),
                force: 0.35,
                timestamp: 0,
                azimuthRadians: 0.8,
                altitudeRadians: .pi / 4
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 96, y: 96),
                force: 1,
                timestamp: 0.2,
                azimuthRadians: 0.8,
                altitudeRadians: .pi / 4
            )
        ]
    )
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "brush-dynamics-paper",
            size: CGSize(width: 140, height: 140)
        ),
        strokes: [stroke]
    )

    let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
    let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)
    let decodedStroke = try XCTUnwrap(decodedDocument.strokes.first)

    XCTAssertEqual(decodedDocument, document)
    XCTAssertEqual(decodedStroke.brush.pressureCurveExponent, 1.8)
    XCTAssertEqual(decodedStroke.brush.minSizeRatio, 0.16)
    XCTAssertEqual(decodedStroke.brush.maxSizeRatio, 0.92)
    XCTAssertEqual(decodedStroke.brush.tiltSizeInfluence, 0.55)
    XCTAssertEqual(decodedStroke.brush.tiltOpacityInfluence, 0.25)
}
```

## 验证情况

- `ReadLints` 检查本次 phase 1 修改文件：无新增诊断。
- 定向手绘测试通过，覆盖：
  - `HandDrawingBrushDynamicsTests`
  - `HandDrawingDocumentCodecTests`
  - phase 0 相关手绘基线测试

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase1Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 功能说明: 验证 phase 1 新 solver、新 codec 回归，以及 phase 0 既有手绘基线在默认配置下继续成立。
xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase1Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 结果: Exit code 0，定向测试通过。
```

## 结论

- 这次 `phase 1` 的实际落地结果，是把 hand drawing 的 brush dynamics 从“模型层/几何层/渲染层分散各算”收敛成了统一 solver。
- 默认配置下，当前 pressure-only 行为继续保持与 phase 0 基线一致；同时新参数、tilt 因子与 codec 兼容骨架已经搭好，为后续 `phase 2` 和 `phase 3` 做了真正可演进的底座。
