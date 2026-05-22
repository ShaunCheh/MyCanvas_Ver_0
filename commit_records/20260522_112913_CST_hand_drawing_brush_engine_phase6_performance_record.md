# 20260522_112913_CST_hand_drawing_brush_engine_phase6_performance_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 6`，对当前 CPU 路径做性能收口，并为后续 Hybrid 实时渲染路线预留独立接口。
  - 本次收口聚焦 4 个点：共享性能 profile、brush-aware 采样与 stamp spacing、dirty region 膨胀策略、`predictedTouches` 实验开关入口。
  - 补齐 `HandDrawingInputNormalizerTests`、`HandDrawingStrokeBuilderTests`、`HandDrawingEditorEngineTests` 的 phase 6 回归，并重新跑一轮 `BrushDynamics / CanvasRenderer / PreviewRenderer` 回归，确认渲染一致性未被破坏。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_112913_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次已跟踪 `phase 6` 相关文件执行 `git diff --stat -- ...`，结果为：`9 files changed, 214 insertions(+), 19 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示：`9` 个已跟踪修改文件，外加 `1` 个本次新增未跟踪文件 `HandDrawingStrokePerformanceProfile.swift`。
  - 当前工作区还存在 `/.cursor/plans/手绘笔刷引擎_b7888ee9.plan.md` 的现有修改，但该 `.md` 文件不属于本次 `phase 6` 代码产物，因此不纳入本记录正文。
- 本记录不包含：
  - `phase 5` 的兼容性与迁移收口。
  - `/.cursor/plans/手绘笔刷引擎_b7888ee9.plan.md` 的现有修改。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次 phase 6 markdown 记录文件的时间戳前缀。
20260522_112913_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 汇总本次 phase 6 已跟踪文件的 diff 统计；新建文件需结合 git status 查看。
.../Editing/HandDrawingBrushDynamics.swift         | 39 ++++++++++++++----
.../Editing/HandDrawingEditorEngine.swift          | 16 ++++++--
.../Editing/HandDrawingStrokeBuilder.swift         |  7 +++-
.../Rendering/HandDrawingDirtyRegionTracker.swift  | 12 +++++-
.../HandDrawingEditorCoordinator.swift             | 16 +++++++-
.../UI/HandDrawingCanvasSurfaceView.swift          | 14 ++++++-
.../HandDrawingEditorEngineTests.swift             | 48 ++++++++++++++++++++++
.../HandDrawingInputNormalizerTests.swift          | 34 +++++++++++++++
.../HandDrawingStrokeBuilderTests.swift            | 47 ++++++++++++++++++++-
9 files changed, 214 insertions(+), 19 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 记录本次 phase 6 相关文件的当前 changes 状态，并把新建的性能 profile 文件一并纳入。
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
M MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
M MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift
```

## 当前 changes 摘要

- 新增 `HandDrawingStrokePerformanceProfile`，把输入采样密度、stamp spacing、dirty region padding 和 live input 实验开关集中建模，避免 CPU 收口逻辑继续散落在 `BrushDynamics / Builder / SurfaceView / Engine` 多处。
- `HandDrawingBrushDynamics.resolvedStamps(...)` 不再只依赖内部硬编码的 `minimumStampSpacing`，改为接受独立的 `HandDrawingResolvedStampLayout`，并默认从 brush profile 推导 spacing。
- `HandDrawingStrokeBuilder.makeStroke(...)` 现在会默认根据当前 `brush.baseSize` 选择 normalization 配置，大笔刷在高频输入下会更积极地收口样本数量。
- `HandDrawingEditorCoordinator` 会为一次 active stroke 固定本次 `HandDrawingStrokePerformanceProfile`，保证 draft 路径与 commit 路径在同一套采样参数下运行，不再出现“中途按当前 UI 状态重新求配置”的分叉。
- `HandDrawingDirtyRegionTracker.markDirty(...)` 改为支持 padding，并在 `EditorEngine` 的 append / erase / translate 场景里按笔刷 profile 膨胀局部重绘区域。
- `HandDrawingCanvasSurfaceView` 为 `predictedTouches` 预留了实验开关，但默认关闭，当前 CPU 路径只继续消费 `coalescedTouches`。
- 新增 phase 6 定点测试，覆盖 brush-aware normalization、large brush 样本收口、dirty region 外扩；并重新验证 `BrushDynamics / CanvasRenderer / PreviewRenderer` 回归。

## 修改一：新增共享性能 profile，统一 CPU 路径参数入口

### 修改前

- 没有独立的性能 profile 文件。
- `BrushDynamics` 自己持有硬编码的 `minimumStampSpacing`。
- `StrokeBuilder` 默认直接使用固定的 `.brushStroke` normalization 配置，无法按 brush size 自适应。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift（修改前）
// 函数名: 无
// 功能说明: 修改前不存在统一的性能 profile 类型，输入采样、stamp spacing、dirty region padding 与 live input 开关没有共享入口。
// 文件不存在。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift（修改前）
// 函数名: HandDrawingBrushDynamics / resolvedStamps(for:) / interpolationStepDistance(from:to:)
// 功能说明: 修改前 stamp spacing 由 BrushDynamics 内部硬编码，未来若切 Hybrid renderer，还需要再次拆分布局语义。
enum HandDrawingBrushDynamics {
    private static let defaultMinimumSizeRatio: CGFloat = 0.05
    private static let defaultPressureCurveExponent: CGFloat = 1
    private static let minimumStampSpacing: CGFloat = 0.5

    static func resolvedStamps(
        for stroke: HandDrawingStroke
    ) -> [HandDrawingResolvedBrushSample] {
        // ... 省略无关代码 ...
    }

    private static func interpolationStepDistance(
        from start: HandDrawingResolvedBrushSample,
        to end: HandDrawingResolvedBrushSample
    ) -> CGFloat {
        max(
            min(start.minorRadius, end.minorRadius) * 0.5,
            minimumStampSpacing
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift（修改前）
// 函数名: makeStroke(brush:samples:transform:normalization:)
// 功能说明: 修改前 Builder 默认只会吃固定的 .brushStroke 配置，不能根据 brush 尺寸自动调节采样密度。
static func makeStroke(
    brush: HandDrawingBrushStyle,
    samples: [HandDrawingInputSample],
    transform: HandDrawingStrokeTransform = .identity,
    normalization: HandDrawingInputNormalizer.Configuration = .brushStroke
) -> HandDrawingStroke? {
    let normalizedSamples = HandDrawingInputNormalizer.normalized(
        samples,
        configuration: normalization
    )
    // ... 省略无关代码 ...
}
```

### 修改后

- 新增 `HandDrawingStrokePerformanceProfile` 作为共享入口。
- 新增 `HandDrawingResolvedStampLayout`，把 stamp spacing 语义从 `BrushDynamics` 硬编码中抽出来。
- `StrokeBuilder` 默认通过 `HandDrawingStrokePerformanceProfile.brushStroke(for:)` 取 normalization。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift
// 函数名: HandDrawingLiveInputConfiguration / HandDrawingStrokePerformanceProfile.brushStroke(for:)
// 功能说明: 修改后统一建模 brush-aware 的输入采样、stamp 布局、dirty region padding 与 predictedTouches 实验配置。
struct HandDrawingLiveInputConfiguration: Equatable {
    static let interactiveDraft = HandDrawingLiveInputConfiguration()

    let includesPredictedTouches: Bool
    let maximumPredictedSampleCount: Int
}

struct HandDrawingStrokePerformanceProfile: Equatable {
    let inputNormalization: HandDrawingInputNormalizer.Configuration
    let stampLayout: HandDrawingResolvedStampLayout
    let dirtyRegionPadding: CGFloat

    static func brushStroke(
        for brush: HandDrawingBrushStyle
    ) -> HandDrawingStrokePerformanceProfile {
        let baseSize = max(CGFloat(brush.baseSize), 0.25)
        return HandDrawingStrokePerformanceProfile(
            inputNormalization: HandDrawingInputNormalizer.Configuration(
                minimumSampleDistance: min(max(baseSize * 0.1, 0.5), 2),
                minimumTimestampDelta: 0.0001,
                minimumForce: 0.05,
                maximumForce: 1
            ),
            stampLayout: HandDrawingResolvedStampLayout(
                relativeSpacingFactor: 0.5,
                minimumSpacing: min(max(baseSize * 0.08, 0.5), 1.5)
            ),
            dirtyRegionPadding: min(max(baseSize * 0.2, 2), 6)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
// 函数名: HandDrawingResolvedStampLayout / resolvedStamps(for:layout:) / interpolationStepDistance(from:to:layout:)
// 功能说明: 修改后 BrushDynamics 支持独立的 stamp layout 输入，默认仍从 brush profile 推导，避免 spacing 继续硬编码在渲染内核里。
struct HandDrawingResolvedStampLayout: Equatable {
    let relativeSpacingFactor: CGFloat
    let minimumSpacing: CGFloat
}

static func resolvedStamps(
    for stroke: HandDrawingStroke,
    layout: HandDrawingResolvedStampLayout? = nil
) -> [HandDrawingResolvedBrushSample] {
    let anchorSamples = resolvedSamples(for: stroke)
    let resolvedLayout = layout
        ?? HandDrawingStrokePerformanceProfile.brushStroke(for: stroke.brush)
            .stampLayout
    // ... 省略无关代码 ...
}

private static func interpolationStepDistance(
    from start: HandDrawingResolvedBrushSample,
    to end: HandDrawingResolvedBrushSample,
    layout: HandDrawingResolvedStampLayout
) -> CGFloat {
    max(
        min(start.minorRadius, end.minorRadius) * layout.relativeSpacingFactor,
        layout.minimumSpacing
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift
// 函数名: makeStroke(brush:samples:transform:normalization:)
// 功能说明: 修改后 Builder 在调用方未显式传入 normalization 时，会自动按 brush profile 选取 brush-aware 采样配置。
static func makeStroke(
    brush: HandDrawingBrushStyle,
    samples: [HandDrawingInputSample],
    transform: HandDrawingStrokeTransform = .identity,
    normalization: HandDrawingInputNormalizer.Configuration? = nil
) -> HandDrawingStroke? {
    let resolvedNormalization = normalization
        ?? HandDrawingStrokePerformanceProfile.brushStroke(for: brush)
            .inputNormalization
    let normalizedSamples = HandDrawingInputNormalizer.normalized(
        samples,
        configuration: resolvedNormalization
    )
    // ... 省略无关代码 ...
}
```

## 修改二：让 draft / commit 共享同一套 brush-aware normalization

### 修改前

- `HandDrawingEditorCoordinator` 只缓存 `activeStrokeBrush` 与 `activeStrokeInputSamples`。
- 开始绘制和追加样本时都直接调用 `HandDrawingInputNormalizer.normalized(...)`，但没有把“本次 stroke 的采样参数”固定下来。
- 这意味着采样策略无法以一次 stroke 为粒度显式收口，也没有可复用的 profile 供未来 renderer 使用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: handlePencilStrokeBegan(_:) / appendStrokeSamples(_:) / clearActiveStroke()
// 功能说明: 修改前 coordinator 只保存 brush 和输入样本，不保存本次 stroke 的性能配置，draft 与 commit 只能隐式依赖默认 normalizer 配置。
private var activeStrokeBrush: HandDrawingBrushStyle?
private var activeStrokeInputSamples: [HandDrawingInputSample] = []

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    activeStrokeBrush = currentBrushStyle
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        [sample]
    )
}

private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        samples,
        appendingTo: activeStrokeInputSamples
    )
}

private func clearActiveStroke() {
    activeStrokeBrush = nil
    activeStrokeInputSamples.removeAll()
}
```

### 修改后

- `HandDrawingEditorCoordinator` 新增 `activeStrokePerformanceProfile`。
- `handlePencilStrokeBegan(_:)` 会为当前 `currentBrushStyle` 固定一份 profile。
- `appendStrokeSamples(_:)` 与清理路径都会围绕同一份 profile 工作，保证 draft / commit 始终落在同一套 normalization 语义下。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: activeStrokePerformanceProfile / handlePencilStrokeBegan(_:) / appendStrokeSamples(_:) / clearActiveStroke()
// 功能说明: 修改后 coordinator 为每次 active stroke 固定一份 brush-aware profile，确保 draft 与 commit 的样本归一化策略保持一致。
private var activeStrokeBrush: HandDrawingBrushStyle?
private var activeStrokePerformanceProfile: HandDrawingStrokePerformanceProfile?
private var activeStrokeInputSamples: [HandDrawingInputSample] = []

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    activeStrokeBrush = currentBrushStyle
    let performanceProfile = HandDrawingStrokePerformanceProfile
        .brushStroke(for: currentBrushStyle)
    activeStrokePerformanceProfile = performanceProfile
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        [sample],
        configuration: performanceProfile.inputNormalization
    )
}

private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
    let normalizationConfiguration =
        activeStrokePerformanceProfile?.inputNormalization
        ?? HandDrawingStrokePerformanceProfile
            .brushStroke(for: activeStrokeBrush ?? currentBrushStyle)
            .inputNormalization
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        samples,
        appendingTo: activeStrokeInputSamples,
        configuration: normalizationConfiguration
    )
}

private func clearActiveStroke() {
    activeStrokeBrush = nil
    activeStrokePerformanceProfile = nil
    activeStrokeInputSamples.removeAll()
}
```

## 修改三：dirty region 从“原 bounds”收口为“按笔刷 profile 外扩后的局部重绘区域”

### 修改前

- `HandDrawingDirtyRegionTracker.markDirty(_:)` 只做原始 `rect` 的 union。
- `HandDrawingEditorEngine` 在 append / erase / translate 时直接把 stroke bounds 或 old/new union 传进去，没有额外膨胀。
- 大笔刷、倾斜 stamp 或抗锯齿边缘下，局部重绘区域容易收得过紧。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift（修改前）
// 函数名: markDirty(_:)
// 功能说明: 修改前 dirty region 仅合并原始 bounds，不支持按笔刷语义外扩。
mutating func markDirty(_ rect: CGRect?) {
    guard let rect, rect.isNull == false, rect.isEmpty == false else {
        return
    }
    dirtyRegion = dirtyRegion?.union(rect) ?? rect
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift（修改前）
// 函数名: appendStroke(_:) / upsertErasePaths(_:recordUndo:) / translateStrokes(withIDs:by:recordUndo:)
// 功能说明: 修改前 engine 仅把 stroke.bounds 或 old/new bounds union 直接提交给 dirty tracker，没有额外的 render padding。
state.document.appendStroke(stroke)
dirtyRegionTracker.markDirty(stroke.bounds ?? state.document.paperBounds)

dirtyRegionTracker.markDirty(
    resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds)
)
```

### 修改后

- `markDirty(...)` 新增 `padding` 参数，并统一做 `standardized + integral`。
- `EditorEngine` 在 append / erase / translate 时，通过 `HandDrawingStrokePerformanceProfile.brushStroke(for:)` 取 `dirtyRegionPadding`，让局部重绘边界按笔刷尺寸外扩。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift
// 函数名: markDirty(_:padding:)
// 功能说明: 修改后 dirty region 会按调用方给定的 padding 外扩，并收口成标准化、像素对齐后的矩形。
mutating func markDirty(
    _ rect: CGRect?,
    padding: CGFloat = 0
) {
    guard let rect, rect.isNull == false, rect.isEmpty == false else {
        return
    }
    let resolvedPadding = max(padding, 0)
    let expandedRect = rect
        .insetBy(dx: -resolvedPadding, dy: -resolvedPadding)
        .standardized
        .integral
    dirtyRegion = dirtyRegion?.union(expandedRect) ?? expandedRect
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: appendStroke(_:) / upsertErasePaths(_:recordUndo:) / translateStrokes(withIDs:by:recordUndo:)
// 功能说明: 修改后 engine 会按当前笔刷 profile 的 dirtyRegionPadding 扩张增量重绘区域，避免局部重绘边界过紧。
state.document.appendStroke(stroke)
dirtyRegionTracker.markDirty(
    stroke.bounds ?? state.document.paperBounds,
    padding: HandDrawingStrokePerformanceProfile.brushStroke(for: stroke.brush)
        .dirtyRegionPadding
)

dirtyRegionTracker.markDirty(
    resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds),
    padding: HandDrawingStrokePerformanceProfile
        .brushStroke(for: activeLayerStrokes[index].brush)
        .dirtyRegionPadding
)
```

## 修改四：为 `predictedTouches` 预留实验开关，但默认仍走当前 CPU 预算

### 修改前

- `HandDrawingCanvasSurfaceView` 只读取 `coalescedTouches(for:)`。
- 没有任何独立开关来决定是否接入 `predictedTouches`。
- 如果未来要对比“只吃 coalesced”与“coalesced + predicted”的 CPU 代价，还需要再次改输入层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: makeSamples(from:event:)
// 功能说明: 修改前 surface 只消费 coalescedTouches，没有 predictedTouches 的实验开关入口。
private func makeSamples(
    from touch: UITouch,
    event: UIEvent?
) -> [HandDrawingInputSample] {
    let touches = event?.coalescedTouches(for: touch) ?? [touch]
    return touches.compactMap(makeSample(from:))
}
```

### 修改后

- `HandDrawingCanvasPageView` 增加 `liveInputConfiguration`。
- 只有当 `includesPredictedTouches == true` 时才会追加预测点，且有 `maximumPredictedSampleCount` 上限。
- 当前 `interactiveDraft` 默认 `includesPredictedTouches = false`，因此 phase 6 完成后 CPU 路径仍然保守，只是接口已经预留。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokePerformanceProfile.swift
// 函数名: HandDrawingLiveInputConfiguration.interactiveDraft
// 功能说明: 修改后 predictedTouches 是否参与实时草稿，由独立配置显式控制；默认保持关闭。
struct HandDrawingLiveInputConfiguration: Equatable {
    static let interactiveDraft = HandDrawingLiveInputConfiguration()

    let includesPredictedTouches: Bool
    let maximumPredictedSampleCount: Int

    init(
        includesPredictedTouches: Bool = false,
        maximumPredictedSampleCount: Int = 2
    ) {
        self.includesPredictedTouches = includesPredictedTouches
        self.maximumPredictedSampleCount = max(maximumPredictedSampleCount, 0)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: liveInputConfiguration / makeSamples(from:event:)
// 功能说明: 修改后 surface 已具备 predictedTouches 入口，但默认 profile 仍只走 coalescedTouches，以控制当前 CPU 路径开销。
private let liveInputConfiguration = HandDrawingLiveInputConfiguration
    .interactiveDraft

private func makeSamples(
    from touch: UITouch,
    event: UIEvent?
) -> [HandDrawingInputSample] {
    var touches = event?.coalescedTouches(for: touch) ?? [touch]
    if
        liveInputConfiguration.includesPredictedTouches,
        let predictedTouches = event?.predictedTouches(for: touch)
    {
        touches.append(
            contentsOf: predictedTouches.prefix(
                liveInputConfiguration.maximumPredictedSampleCount
            )
        )
    }
    return touches.compactMap(makeSample(from:))
}
```

## 修改五：补 phase 6 回归测试，覆盖样本收口与 dirty region 外扩

### 修改前

- 没有直接验证“不同 brush size 会推导出不同 normalization distance”的测试。
- 没有直接验证“大笔刷高频输入会被收口为更少样本”的测试。
- 没有直接验证“dirty region 会按 profile padding 外扩”的测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift（修改前）
// 函数名: 无
// 功能说明: 修改前尚未覆盖 brush-aware normalization distance 的 phase 6 回归。
// 相关测试不存在。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift（修改前）
// 函数名: 无
// 功能说明: 修改前尚未覆盖 large brush 样本收口行为的 phase 6 回归。
// 相关测试不存在。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift（修改前）
// 函数名: 无
// 功能说明: 修改前尚未覆盖 dirty region padding 外扩行为的 phase 6 回归。
// 相关测试不存在。
```

### 修改后

- `HandDrawingInputNormalizerTests` 新增 profile 推导距离验证。
- `HandDrawingStrokeBuilderTests` 新增大笔刷样本收口验证，并同步让 draft/commit 等价测试使用 brush-aware normalization。
- `HandDrawingEditorEngineTests` 新增 dirty region 外扩断言。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
// 函数名: testHandDrawingStrokePerformanceProfileUsesBrushAwareNormalizationDistance()
// 功能说明: 修改后验证不同 baseSize 的笔刷会生成不同的 minimumSampleDistance，确保采样密度按 brush size 自适应。
func testHandDrawingStrokePerformanceProfileUsesBrushAwareNormalizationDistance() {
    let thinBrushProfile = HandDrawingStrokePerformanceProfile.brushStroke(
        for: HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 4,
            opacity: 1
        )
    )
    let thickBrushProfile = HandDrawingStrokePerformanceProfile.brushStroke(
        for: HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 18,
            opacity: 1
        )
    )

    XCTAssertEqual(
        thinBrushProfile.inputNormalization.minimumSampleDistance,
        0.5,
        accuracy: 0.001
    )
    XCTAssertEqual(
        thickBrushProfile.inputNormalization.minimumSampleDistance,
        1.8,
        accuracy: 0.001
    )
    XCTAssertGreaterThan(
        thickBrushProfile.inputNormalization.minimumSampleDistance,
        thinBrushProfile.inputNormalization.minimumSampleDistance
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
// 函数名: testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent() / testHandDrawingStrokeBuilderUsesBrushAwareSamplingForLargeBrushes()
// 功能说明: 修改后同时验证 draft/commit 继续共享同一套 normalization 结果，以及 large brush 下高频相邻样本会被主动收口。
let normalizedSamples = HandDrawingInputNormalizer.normalized(
    rawSamples,
    configuration: HandDrawingStrokePerformanceProfile
        .brushStroke(for: brush)
        .inputNormalization
)

func testHandDrawingStrokeBuilderUsesBrushAwareSamplingForLargeBrushes() throws {
    let brush = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 18,
        opacity: 1
    )
    let stroke = try XCTUnwrap(
        HandDrawingStrokeBuilder.makeStroke(
            brush: brush,
            samples: [
                HandDrawingInputSample(location: CGPoint(x: 10, y: 20), force: 1, timestamp: 0),
                HandDrawingInputSample(location: CGPoint(x: 10.7, y: 20), force: 0.9, timestamp: 0.01),
                HandDrawingInputSample(location: CGPoint(x: 11.4, y: 20), force: 0.85, timestamp: 0.02),
                HandDrawingInputSample(location: CGPoint(x: 16, y: 20), force: 0.8, timestamp: 0.03)
            ]
        )
    )

    XCTAssertEqual(stroke.samplePoints.count, 2)
    XCTAssertEqual(stroke.samplePoints[0].cgPoint.x, 11.4, accuracy: 0.001)
    XCTAssertEqual(stroke.samplePoints[1].cgPoint.x, 16, accuracy: 0.001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineInflatesDirtyRegionForPartialRerender()
// 功能说明: 修改后直接验证局部重绘 dirty region 会按 profile.dirtyRegionPadding 外扩，而不是等于原始 stroke bounds。
func testHandDrawingEditorEngineInflatesDirtyRegionForPartialRerender() throws {
    var engine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "dirty-region-paper",
                size: CGSize(width: 200, height: 200)
            )
        )
    )
    let brush = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 18,
        opacity: 1
    )
    let stroke = try XCTUnwrap(
        engine.appendStroke(
            brush: brush,
            samples: [
                HandDrawingInputSample(location: CGPoint(x: 40, y: 50), force: 1, timestamp: 0),
                HandDrawingInputSample(location: CGPoint(x: 80, y: 50), force: 1, timestamp: 0.1)
            ]
        )
    )

    let strokeBounds = try XCTUnwrap(stroke.bounds)
    let dirtyRegion = try XCTUnwrap(engine.consumeDirtyRegion())
    let expectedDirtyRegion = strokeBounds
        .insetBy(
            dx: -HandDrawingStrokePerformanceProfile.brushStroke(for: brush)
                .dirtyRegionPadding,
            dy: -HandDrawingStrokePerformanceProfile.brushStroke(for: brush)
                .dirtyRegionPadding
        )
        .standardized
        .integral

    XCTAssertEqual(dirtyRegion, expectedDirtyRegion)
}
```

## 验证结果

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests
# 功能说明: 运行 phase 6 直接相关单测与渲染回归，验证 brush-aware sampling、dirty region 与 preview/canvas 一致性没有被破坏。
** TEST SUCCEEDED **
Test case 'HandDrawingEditorEngineTests.testHandDrawingEditorEngineInflatesDirtyRegionForPartialRerender()' passed
Test case 'HandDrawingStrokeBuilderTests.testHandDrawingStrokeBuilderUsesBrushAwareSamplingForLargeBrushes()' passed
Test case 'HandDrawingInputNormalizerTests.testHandDrawingStrokePerformanceProfileUsesBrushAwareNormalizationDistance()' passed
Test case 'HandDrawingCanvasRendererTests.testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate()' passed
Test case 'HandDrawingPreviewRendererTests.testHandDrawingPreviewRendererRendersTiltAwareStampOrientation()' passed
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushDynamicsCustomPressureCurveAndBoundsStayInSync()' passed
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
# 功能说明: 验证 iOS Simulator 目标在 phase 6 收口后仍可正常编译，通过该命令确认新增 profile 与 iOS surface 接线没有破坏移动端构建。
Build settings from command line:
    CODE_SIGNING_ALLOWED = NO

** BUILD SUCCEEDED **
```

## 结论

- 本次 `phase 6` 没有引入新的实时 renderer，而是把 CPU 路径的关键性能参数前移到统一 profile 中管理。
- 当前实现已经做到：
  - 采样密度按 brush size 自适应；
  - stamp spacing 不再硬编码在 `BrushDynamics` 内部；
  - dirty region 能按笔刷语义外扩；
  - `predictedTouches` 已有实验入口但默认关闭；
  - draft / commit / renderer 回归测试均通过。
- 这使得后续如果要接 Hybrid renderer，可以直接复用 `HandDrawingStrokePerformanceProfile`、`HandDrawingResolvedStampLayout` 与当前 brush-aware normalization 结果，而不需要再从 `rasterizer` 里反向拆逻辑。
