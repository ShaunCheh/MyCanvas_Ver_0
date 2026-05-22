# 20260522_131103_CST_hand_drawing_scheme2_phase3_incremental_packet_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 3`，把 coordinator 从“每次发布整根 `draftStroke` 快照”升级为“发布可流式消费的增量 realtime packet”。
  - 本次修改继续坚持 `document / history / committed canvas` 仍是 CPU 真相源；`realtime draft` 只是显示层消费的临时语义，不越权回写文档。
  - 本次重点是先把 `packetization` 边界做对，为下一阶段接 `GPU draft backend` 留出稳定输入契约。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
- 本记录不包含：
  - 任何 `GPU / Metal` draft backend 接入。
  - 任何 committed backend 的 GPU 化。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date '+%Y%m%d_%H%M%S_CST_hand_drawing_scheme2_phase3_incremental_packet_record'
# 功能说明: 使用系统 date 命令生成本次 phase 3 记录文件的时间戳与文件名前缀。
20260522_131103_CST_hand_drawing_scheme2_phase3_incremental_packet_record
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 汇总本次 phase 3 增量 realtime packet 改造的 diff 统计。
.../Editing/HandDrawingBrushDynamics.swift         |  58 +++++++
.../Editing/HandDrawingInputNormalizer.swift       |  55 +++++++
.../Rendering/HandDrawingRenderingContracts.swift  | 103 ++++++++++--
.../Rendering/HandDrawingStrokeRasterizer.swift    |  29 ++--
.../HandDrawingEditorCoordinator.swift             | 179 +++++++++++++++------
.../UI/HandDrawingCanvasSurfaceView.swift          |  88 ++++++----
.../iOSHandDrawingEditorViewController.swift       |   8 +-
.../HandDrawingBrushDynamicsTests.swift            |  66 ++++++++
.../HandDrawingEditorCoordinatorTests.swift        |  60 ++++++-
.../HandDrawingInputNormalizerTests.swift          |  48 ++++++
.../HandDrawingRenderingContractsTests.swift       |  57 +++++--
11 files changed, 627 insertions(+), 124 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录生成本文件时，工作区里与本次 phase 3 对应的当前 changes。
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
M MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
M MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
M MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
```

## 当前 changes 摘要

- `HandDrawingRealtimeDraftPacket` 不再携带整根 `draftStroke`，而是改成：
  - `strokeID`
  - committed samples 的稳定前缀长度与 tail
  - committed resolved stamps 的稳定前缀长度与 tail
  - predicted tail
- `HandDrawingInputNormalizer` 和 `HandDrawingBrushDynamics` 分别新增“稳定前缀 + tail”的增量 helper，避免增量逻辑散落在 coordinator。
- `HandDrawingEditorCoordinator` 不再通过 `currentRealtimeDraftPacket` 每次现算整根草稿，而是维护 active stroke 的 committed 样本与 resolved stamps，并按 revision 推送 packet。
- `HandDrawingCanvasSurfaceView` 与 `iOSHandDrawingEditorViewController` 改成传递 `HandDrawingLiveInputBatch`，把 committed 输入和 predicted 输入拆开上送。
- CPU realtime fallback 不再依赖整根 `draftStroke` 绘制，而是直接消费 `resolvedStamps`。
- 回归测试从“renderer 返回整根 `draftStroke`”转为“packet 携带 committed tail / predicted tail 的契约”与底层增量 helper 覆盖。

## 修改一：realtime contract 从“整根 draftStroke”升级为“增量 packet”

### 修改前

- `HandDrawingRealtimeDraftPacket` 仍然把 `normalizedSamples`、`draftStroke`、`resolvedStamps` 一次性整包交给 realtime renderer。
- `HandDrawingCPURealtimeBrushRenderer` 只是把 `draftStroke` 原样返回给 UI host；显示层并没有形成“可持续 append 的流式消费边界”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift（修改前）
// 函数名: HandDrawingRealtimeDraftPacket / HandDrawingRealtimeDraftRenderOutput / HandDrawingRealtimeBrushRenderer.render(packet:)
// 功能说明: 修改前 realtime packet 仍然是整根草稿快照，CPU renderer 只把 draftStroke 透传给视图层。
struct HandDrawingRealtimeDraftPacket: Equatable {
    let brush: HandDrawingBrushStyle
    let performanceProfile: HandDrawingStrokePerformanceProfile
    let normalizedSamples: [HandDrawingInputSample]
    let draftStroke: HandDrawingStroke
    let resolvedStamps: [HandDrawingResolvedBrushSample]
}

enum HandDrawingRealtimeDraftRenderOutput {
    case none
    case stroke(HandDrawingStroke)

    var stroke: HandDrawingStroke? {
        switch self {
        case .none:
            return nil
        case let .stroke(stroke):
            return stroke
        }
    }
}

protocol HandDrawingRealtimeBrushRenderer {
    func render(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput
}
```

### 修改后

- realtime contract 新增 committed tail / predicted tail / stablePrefixCount 三类增量语义。
- `HandDrawingCPURealtimeBrushRenderer` 改为 stateful consumer：按 `strokeID` 切换流，按 `stablePrefixCount` 替换 committed tail，并单独维护 predicted tail。
- 这一步让 phase 4 可以直接在 GPU draft backend 侧消费 packet，而不是再把 brush math 搬进去重算。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeDraftPacket / HandDrawingRealtimeDraftRenderOutput / HandDrawingCPURealtimeBrushRenderer.apply(packet:)
// 功能说明: 修改后 packet 只发布 committed tail 与 predicted tail，CPU fallback 按 stablePrefixCount 维护增量 realtime 状态。
struct HandDrawingRealtimeNormalizedSampleUpdate: Equatable {
    let stablePrefixCount: Int
    let tailSamples: [HandDrawingInputSample]
}

struct HandDrawingRealtimeResolvedStampUpdate: Equatable {
    let stablePrefixCount: Int
    let tailStamps: [HandDrawingResolvedBrushSample]
}

struct HandDrawingRealtimePredictedTail: Equatable {
    static let empty = HandDrawingRealtimePredictedTail(
        normalizedSamples: [],
        resolvedStamps: []
    )

    let normalizedSamples: [HandDrawingInputSample]
    let resolvedStamps: [HandDrawingResolvedBrushSample]
}

struct HandDrawingRealtimeDraftPacket: Equatable {
    let strokeID: UUID
    let brush: HandDrawingBrushStyle
    let performanceProfile: HandDrawingStrokePerformanceProfile
    let committedSamples: HandDrawingRealtimeNormalizedSampleUpdate
    let committedResolvedStamps: HandDrawingRealtimeResolvedStampUpdate
    let predictedTail: HandDrawingRealtimePredictedTail
}

final class HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    private var activeStrokeID: UUID?
    private var committedResolvedStamps: [HandDrawingResolvedBrushSample] = []
    private var predictedResolvedStamps: [HandDrawingResolvedBrushSample] = []

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let packet else {
            // 清空流式状态，避免旧草稿残留到下一笔。
            activeStrokeID = nil
            committedResolvedStamps.removeAll()
            predictedResolvedStamps.removeAll()
            return .none
        }

        if activeStrokeID != packet.strokeID {
            // 新的一笔开始时，丢弃上一笔的增量缓存。
            committedResolvedStamps.removeAll()
            predictedResolvedStamps.removeAll()
        }
        activeStrokeID = packet.strokeID
        committedResolvedStamps = replaceTail(
            in: committedResolvedStamps,
            stablePrefixCount: packet.committedResolvedStamps.stablePrefixCount,
            tail: packet.committedResolvedStamps.tailStamps
        )
        predictedResolvedStamps = packet.predictedTail.resolvedStamps

        return .resolved(
            HandDrawingRealtimeDraftRenderState(
                brush: packet.brush,
                committedResolvedStamps: committedResolvedStamps,
                predictedResolvedStamps: predictedResolvedStamps
            )
        )
    }
}
```

## 修改二：把增量样本与增量 stamps helper 下沉到基础层

### 修改前

- `HandDrawingInputNormalizer` 只有 `normalized(...)`，只能输出一整份归一化数组。
- `HandDrawingBrushDynamics` 只有 `resolvedStamps(for stroke)` 这一类完整展开接口，不能直接告诉上层“稳定前缀到哪里、tail 从哪里开始更新”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift（修改前）
// 函数名: HandDrawingInputNormalizer.normalized(_:appendingTo:configuration:)
// 功能说明: 修改前只能拿到完整 normalizedSamples，调用者无法直接获知稳定前缀与 tail 分界。
enum HandDrawingInputNormalizer {
    static func normalized(
        _ rawSamples: [HandDrawingInputSample],
        appendingTo existingSamples: [HandDrawingInputSample] = [],
        configuration: Configuration = .brushStroke
    ) -> [HandDrawingInputSample] {
        var normalizedSamples = existingSamples
        // ... 逐个样本 sanitize / 合并近点 / 单调化时间戳 ...
        return normalizedSamples
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift（修改前）
// 函数名: HandDrawingBrushDynamics.resolvedStamps(for:layout:)
// 功能说明: 修改前 brush dynamics 只负责从 stroke 计算完整 resolvedStamps，不关心增量 tail。
static func resolvedStamps(
    for stroke: HandDrawingStroke,
    layout: HandDrawingResolvedStampLayout? = nil
) -> [HandDrawingResolvedBrushSample] {
    let anchorSamples = resolvedSamples(for: stroke)
    guard anchorSamples.count > 1 else {
        return anchorSamples
    }
    // ... 根据相邻锚点插值，展开出整根 stroke 的 stamps ...
    return resolvedStamps
}
```

### 修改后

- `HandDrawingInputNormalizer` 新增：
  - `IncrementalUpdate`
  - `normalizedUpdate(...)`
  - `normalizedPredictedTail(...)`
- `HandDrawingBrushDynamics` 新增：
  - `ResolvedStampUpdate`
  - `resolvedStamps(brush:normalizedSamples:...)`
  - `resolvedStampUpdate(...)`
- 这样 coordinator 不需要自己比较数组差异，也不需要在 presentation 层维护 brush math。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift
// 函数名: IncrementalUpdate / normalizedUpdate(_:appendingTo:configuration:) / normalizedPredictedTail(_:onto:configuration:)
// 功能说明: 修改后 InputNormalizer 直接产出稳定前缀长度与 tail，用于 committed 输入和 predicted tail 的分流。
struct IncrementalUpdate: Equatable {
    let normalizedSamples: [HandDrawingInputSample]
    let stablePrefixCount: Int

    var tailSamples: [HandDrawingInputSample] {
        Array(normalizedSamples.dropFirst(stablePrefixCount))
    }
}

static func normalizedUpdate(
    _ rawSamples: [HandDrawingInputSample],
    appendingTo existingSamples: [HandDrawingInputSample] = [],
    configuration: Configuration = .brushStroke
) -> IncrementalUpdate {
    let normalizedSamples = normalized(
        rawSamples,
        appendingTo: existingSamples,
        configuration: configuration
    )
    return IncrementalUpdate(
        normalizedSamples: normalizedSamples,
        stablePrefixCount: commonPrefixCount(
            between: existingSamples,
            and: normalizedSamples
        )
    )
}

static func normalizedPredictedTail(
    _ rawSamples: [HandDrawingInputSample],
    onto committedSamples: [HandDrawingInputSample],
    configuration: Configuration = .brushStroke
) -> [HandDrawingInputSample] {
    let combinedSamples = normalized(
        rawSamples,
        appendingTo: committedSamples,
        configuration: configuration
    )
    return Array(combinedSamples.dropFirst(committedSamples.count))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingBrushDynamics.swift
// 函数名: ResolvedStampUpdate / resolvedStamps(brush:normalizedSamples:transform:layout:) / resolvedStampUpdate(brush:normalizedSamples:previousResolvedStamps:transform:layout:)
// 功能说明: 修改后 BrushDynamics 既能从 normalizedSamples 直接求 stamps，也能输出稳定前缀与 tail 的增量结果。
struct ResolvedStampUpdate: Equatable {
    let resolvedStamps: [HandDrawingResolvedBrushSample]
    let stablePrefixCount: Int

    var tailStamps: [HandDrawingResolvedBrushSample] {
        Array(resolvedStamps.dropFirst(stablePrefixCount))
    }
}

static func resolvedStamps(
    brush: HandDrawingBrushStyle,
    normalizedSamples: [HandDrawingInputSample],
    transform: HandDrawingStrokeTransform = .identity,
    layout: HandDrawingResolvedStampLayout? = nil
) -> [HandDrawingResolvedBrushSample] {
    guard let stroke = HandDrawingStrokeBuilder.makeStroke(
        brush: brush,
        normalizedSamples: normalizedSamples,
        transform: transform
    ) else {
        return []
    }
    return resolvedStamps(for: stroke, layout: layout)
}

static func resolvedStampUpdate(
    brush: HandDrawingBrushStyle,
    normalizedSamples: [HandDrawingInputSample],
    previousResolvedStamps: [HandDrawingResolvedBrushSample] = [],
    transform: HandDrawingStrokeTransform = .identity,
    layout: HandDrawingResolvedStampLayout? = nil
) -> ResolvedStampUpdate {
    let resolvedStamps = resolvedStamps(
        brush: brush,
        normalizedSamples: normalizedSamples,
        transform: transform,
        layout: layout
    )
    return ResolvedStampUpdate(
        resolvedStamps: resolvedStamps,
        stablePrefixCount: commonPrefixCount(
            between: previousResolvedStamps,
            and: resolvedStamps
        )
    )
}
```

## 修改三：coordinator 不再现算整根 currentRealtimeDraftPacket，而是维护增量 active stroke 状态

### 修改前

- coordinator 只维护 `activeStrokeInputSamples`。
- `handlePencilStrokeMoved(_:)` 追加样本后，`publishSurfaceState()` 通过 `currentRealtimeDraftPacket` 现算整根 `draftStroke` 与整根 `resolvedStamps`。
- `predictedTouches` 即便开启，也只能混在同一份样本数组里，不具备单独 tail 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: handlePencilStrokeBegan(_:) / handlePencilStrokeMoved(_:) / currentRealtimeDraftPacket / appendStrokeSamples(_:)
// 功能说明: 修改前 coordinator 只维护整份样本数组，每次发布 surface state 都会重建整根 draftStroke 快照。
func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    activeStrokeBrush = currentBrushStyle
    let performanceProfile = HandDrawingStrokePerformanceProfile
        .brushStroke(for: currentBrushStyle)
    activeStrokePerformanceProfile = performanceProfile
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        [sample],
        configuration: performanceProfile.inputNormalization
    )
    publishSurfaceState()
}

func handlePencilStrokeMoved(_ samples: [HandDrawingInputSample]) {
    guard activeStrokeBrush != nil else {
        return
    }
    appendStrokeSamples(samples)
    publishSurfaceState()
}

private var currentRealtimeDraftPacket: HandDrawingRealtimeDraftPacket? {
    guard
        let activeStrokeBrush,
        let activeStrokePerformanceProfile,
        activeStrokeInputSamples.isEmpty == false
    else {
        return nil
    }
    guard let draftStroke = HandDrawingStrokeBuilder.makeStroke(
        brush: activeStrokeBrush,
        normalizedSamples: activeStrokeInputSamples
    ) else {
        return nil
    }
    return HandDrawingRealtimeDraftPacket(
        brush: activeStrokeBrush,
        performanceProfile: activeStrokePerformanceProfile,
        normalizedSamples: activeStrokeInputSamples,
        draftStroke: draftStroke,
        resolvedStamps: HandDrawingBrushDynamics.resolvedStamps(
            for: draftStroke,
            layout: activeStrokePerformanceProfile.stampLayout
        )
    )
}
```

### 修改后

- coordinator 现在新增：
  - `HandDrawingLiveInputBatch`
  - `activeStrokeID`
  - `activeStrokeResolvedStamps`
  - `realtimeDraftHostState.revision`
- `publishRealtimeDraftPacket(...)` 负责：
  - committed 样本增量归一化
  - committed resolved stamps tail 计算
  - predicted tail 独立归一化与独立 resolved stamps tail 计算
  - 把 packet 推进到 `realtimeDraftHostState`
- `clearActiveStroke()` 会同步推进一次 `packet = nil` 的新 revision，让 host 有机会清掉上一笔残留。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingLiveInputBatch / handlePencilStrokeBegan(_:) / handlePencilStrokeMoved(_:) / handlePencilStrokeEnded(_:) / publishRealtimeDraftPacket(committedSamples:predictedSamples:) / advanceRealtimeDraftHostState(with:)
// 功能说明: 修改后 coordinator 在 presentation 层只做增量 packet 组装与 revision 推送，不再每次重建整根 realtime 草稿对象。
struct HandDrawingLiveInputBatch: Equatable {
    static let empty = HandDrawingLiveInputBatch()

    let committedSamples: [HandDrawingInputSample]
    let predictedSamples: [HandDrawingInputSample]
}

struct HandDrawingRealtimeDraftHostState {
    static let idle = HandDrawingRealtimeDraftHostState(
        revision: 0,
        packet: nil
    )

    var revision: UInt64
    var packet: HandDrawingRealtimeDraftPacket?
}

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    activeStrokeID = UUID()
    activeStrokeBrush = currentBrushStyle
    activeStrokePerformanceProfile = HandDrawingStrokePerformanceProfile
        .brushStroke(for: currentBrushStyle)
    activeStrokeInputSamples.removeAll()
    activeStrokeResolvedStamps.removeAll()
    publishRealtimeDraftPacket(
        committedSamples: [sample],
        predictedSamples: []
    )
    publishSurfaceState()
}

func handlePencilStrokeMoved(_ batch: HandDrawingLiveInputBatch) {
    guard activeStrokeBrush != nil else {
        return
    }
    publishRealtimeDraftPacket(
        committedSamples: batch.committedSamples,
        predictedSamples: batch.predictedSamples
    )
    publishSurfaceState()
}

private func publishRealtimeDraftPacket(
    committedSamples rawCommittedSamples: [HandDrawingInputSample],
    predictedSamples rawPredictedSamples: [HandDrawingInputSample]
) {
    let committedSamplesUpdate = HandDrawingInputNormalizer.normalizedUpdate(
        rawCommittedSamples,
        appendingTo: activeStrokeInputSamples,
        configuration: activeStrokePerformanceProfile.inputNormalization
    )
    let committedResolvedStampsUpdate = HandDrawingBrushDynamics.resolvedStampUpdate(
        brush: activeStrokeBrush,
        normalizedSamples: committedSamplesUpdate.normalizedSamples,
        previousResolvedStamps: activeStrokeResolvedStamps,
        layout: activeStrokePerformanceProfile.stampLayout
    )
    activeStrokeInputSamples = committedSamplesUpdate.normalizedSamples
    activeStrokeResolvedStamps = committedResolvedStampsUpdate.resolvedStamps

    let predictedTailSamples = HandDrawingInputNormalizer.normalizedPredictedTail(
        rawPredictedSamples,
        onto: activeStrokeInputSamples,
        configuration: activeStrokePerformanceProfile.inputNormalization
    )
    let predictedTailResolvedStamps = HandDrawingBrushDynamics.resolvedStampUpdate(
        brush: activeStrokeBrush,
        normalizedSamples: activeStrokeInputSamples + predictedTailSamples,
        previousResolvedStamps: activeStrokeResolvedStamps,
        layout: activeStrokePerformanceProfile.stampLayout
    )

    advanceRealtimeDraftHostState(
        with: HandDrawingRealtimeDraftPacket(
            strokeID: activeStrokeID,
            brush: activeStrokeBrush,
            performanceProfile: activeStrokePerformanceProfile,
            committedSamples: HandDrawingRealtimeNormalizedSampleUpdate(
                stablePrefixCount: committedSamplesUpdate.stablePrefixCount,
                tailSamples: committedSamplesUpdate.tailSamples
            ),
            committedResolvedStamps: HandDrawingRealtimeResolvedStampUpdate(
                stablePrefixCount: committedResolvedStampsUpdate.stablePrefixCount,
                tailStamps: committedResolvedStampsUpdate.tailStamps
            ),
            predictedTail: HandDrawingRealtimePredictedTail(
                normalizedSamples: predictedTailSamples,
                resolvedStamps: predictedTailResolvedStamps.tailStamps
            )
        )
    )
}
```

## 修改四：surface 输入通路把 committed / predicted 样本分开，CPU host 按 revision 消费 packet

### 修改前

- `HandDrawingCanvasSurfaceView` 与 `HandDrawingCanvasPageView` 的回调签名都是 `([HandDrawingInputSample]) -> Void`。
- `makeSamples(...)` 会把 `coalescedTouches` 和 `predictedTouches` 合并成一份数组再上传。
- CPU realtime host 只会从 `state.output.stroke` 里拿整根 `draftStroke`，缺少 revision 边界，也缺少 committed / predicted 的可见分层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingCanvasSurfaceView.onPencilStrokeMoved / HandDrawingCanvasPageView.makeSamples(from:event:) / HandDrawingCPURealtimeDraftRendererView.apply(state:)
// 功能说明: 修改前 surface 侧只上传一份样本数组，predictedTouches 与 committed 输入混在一起，CPU host 直接吃整根 draftStroke。
var onPencilStrokeMoved: (([HandDrawingInputSample]) -> Void)?
var onPencilStrokeEnded: (([HandDrawingInputSample]) -> Void)?

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

func apply(state: HandDrawingRealtimeDraftHostState) {
    draftStroke = state.output.stroke
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift（修改前）
// 函数名: configureSurfaceView()
// 功能说明: 修改前 controller 只把整份样本数组转发给 coordinator。
surfaceView.onPencilStrokeMoved = { [weak self] samples in
    self?.coordinator.handlePencilStrokeMoved(samples)
}
surfaceView.onPencilStrokeEnded = { [weak self] samples in
    self?.coordinator.handlePencilStrokeEnded(samples)
}
```

### 修改后

- `HandDrawingCanvasSurfaceView` 与 `HandDrawingCanvasPageView` 改成传递 `HandDrawingLiveInputBatch`。
- `makeInputBatch(...)` 分别返回：
  - `committedSamples`
  - `predictedSamples`
- 抬笔时强制 `includePredictedTouches: false`，避免 predicted tail 被错误提交到 committed path。
- `HandDrawingCPURealtimeDraftRendererView` 按 `revision` 判重，只在 revision 变化时消费 packet，并把 committed / predicted 的 `resolvedStamps` 分开绘制。
- `iOSHandDrawingEditorViewController` 的桥接也同步改成 batch 形式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCanvasSurfaceView.onPencilStrokeMoved / HandDrawingCanvasPageView.makeInputBatch(from:event:includePredictedTouches:) / HandDrawingCPURealtimeDraftRendererView.apply(state:) / draw(_:)
// 功能说明: 修改后 surface 把 committed 与 predicted 样本分开上送，CPU draft host 按 revision 消费 packet，并直接画 resolvedStamps。
var onPencilStrokeMoved: ((HandDrawingLiveInputBatch) -> Void)?
var onPencilStrokeEnded: ((HandDrawingLiveInputBatch) -> Void)?

private func makeInputBatch(
    from touch: UITouch,
    event: UIEvent?,
    includePredictedTouches: Bool
) -> HandDrawingLiveInputBatch {
    let committedSamples = (event?.coalescedTouches(for: touch) ?? [touch])
        .compactMap(makeSample(from:))
    let predictedSamples: [HandDrawingInputSample]
    if
        includePredictedTouches,
        let predictedTouches = event?.predictedTouches(for: touch)
    {
        predictedSamples = predictedTouches
            .prefix(liveInputConfiguration.maximumPredictedSampleCount)
            .compactMap(makeSample(from:))
    } else {
        predictedSamples = []
    }
    return HandDrawingLiveInputBatch(
        committedSamples: committedSamples,
        predictedSamples: predictedSamples
    )
}

private final class HandDrawingCPURealtimeDraftRendererView: UIView, HandDrawingRealtimeDraftRendererHosting {
    private let renderer = HandDrawingCPURealtimeBrushRenderer()
    private var lastAppliedRevision: UInt64?
    private var renderOutput: HandDrawingRealtimeDraftRenderOutput = .none

    func apply(state: HandDrawingRealtimeDraftHostState) {
        guard lastAppliedRevision != state.revision else {
            return
        }
        lastAppliedRevision = state.revision
        renderOutput = renderer.apply(packet: state.packet)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        if let resolvedState = renderOutput.resolvedState {
            // 先画 committed 部分，再叠加 predicted tail，保持实时尾巴可单独替换。
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
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: configureSurfaceView()
// 功能说明: 修改后 controller 直接把 batch 事件转发给 coordinator，保留 committed 与 predicted 的分流语义。
surfaceView.onPencilStrokeMoved = { [weak self] batch in
    self?.coordinator.handlePencilStrokeMoved(batch)
}
surfaceView.onPencilStrokeEnded = { [weak self] batch in
    self?.coordinator.handlePencilStrokeEnded(batch)
}
```

## 修改五：CPU fallback 补出“直接画 resolvedStamps”的公共入口

### 修改前

- `HandDrawingStrokeRasterizer` 的公共入口只有 `draw(_ stroke: HandDrawingStroke, in:)`。
- 即便 host 已经拿到了 `resolvedStamps`，也必须重新回到 `stroke` 语义，无法直接绘制增量 packet 展开的 stamp tail。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift（修改前）
// 函数名: draw(_ stroke:in:) / drawStrokeInk(_:in:)
// 功能说明: 修改前 rasterizer 只能从整根 stroke 开始画，无法直接消费 resolvedStamps。
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
        let resolvedColor = stroke.brush.color.cgColor
        context.setFillColor(resolvedColor)
        for sample in resolvedSamples {
            drawStamp(sample, in: context)
        }
    }
}
```

### 修改后

- 新增 `draw(_ resolvedSamples: [HandDrawingResolvedBrushSample], color: HandDrawingColor, in: CGContext)`。
- 原来的 `drawStrokeInk(...)` 改成调用这个新入口，避免同一套 stamp 绘制逻辑分叉出两份。
- 这让 realtime host 可以直接画 committed / predicted 两段 `resolvedStamps`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
// 函数名: draw(_:color:in:) / drawStrokeInk(_:in:)
// 功能说明: 修改后 rasterizer 可以直接消费 resolvedStamps，给增量 realtime packet 和 future GPU parity 对照提供统一 stamp 绘制入口。
enum HandDrawingStrokeRasterizer {
    static func draw(
        _ resolvedSamples: [HandDrawingResolvedBrushSample],
        color: HandDrawingColor,
        in context: CGContext
    ) {
        guard resolvedSamples.isEmpty == false else {
            return
        }
        context.setFillColor(color.cgColor)
        for sample in resolvedSamples {
            drawStamp(sample, in: context)
        }
    }

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
        draw(
            resolvedSamples,
            color: stroke.brush.color,
            in: context
        )
    }
}
```

## 修改六：回归测试从“整根草稿返回”切到“增量 tail / predicted tail / packet 发布”

### 修改前

- `HandDrawingRenderingContractsTests` 还在验证“CPU realtime renderer 会把 `draftStroke` 原样返回”。
- 没有测试 `stablePrefixCount`、`tailSamples`、`predictedTail` 这些 phase 3 新语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift（修改前）
// 函数名: testHandDrawingCPURealtimeBrushRendererReturnsDraftStrokeFromPacket()
// 功能说明: 修改前 contract test 只验证 renderer 会返回整根 draftStroke，没有覆盖增量 packet 语义。
let packet = HandDrawingRealtimeDraftPacket(
    brush: brush,
    performanceProfile: performanceProfile,
    normalizedSamples: normalizedSamples,
    draftStroke: draftStroke,
    resolvedStamps: HandDrawingBrushDynamics.resolvedStamps(
        for: draftStroke,
        layout: performanceProfile.stampLayout
    )
)
let renderer = HandDrawingCPURealtimeBrushRenderer()

XCTAssertNil(renderer.render(packet: nil).stroke)
XCTAssertEqual(renderer.render(packet: packet).stroke, draftStroke)
```

### 修改后

- `HandDrawingInputNormalizerTests` 新增 `testHandDrawingInputNormalizerProducesStablePrefixAndTailSamplesForIncrementalUpdates()`，验证 committed 样本更新的稳定前缀与 tail。
- `HandDrawingBrushDynamicsTests` 新增 `testHandDrawingBrushDynamicsResolvedStampUpdateProducesTailAgainstCommittedPrefix()`，验证 predicted tail 进入 dynamics 后 tail 边界仍然正确。
- `HandDrawingRenderingContractsTests` 改成验证 `HandDrawingRealtimeDraftPacket` 是否正确携带 committed tail 与 predicted tail。
- `HandDrawingEditorCoordinatorTests` 改成检查 `realtimeDraftHost.packet`、`revision`、`predictedTail`，不再检查旧的 `output.stroke`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
// 函数名: testHandDrawingInputNormalizerProducesStablePrefixAndTailSamplesForIncrementalUpdates()
// 功能说明: 新增测试直接验证 normalizedUpdate 会输出正确的 stablePrefixCount 与 tailSamples。
let update = HandDrawingInputNormalizer.normalizedUpdate(
    [
        HandDrawingInputSample(
            location: CGPoint(x: 20.2, y: 20.2),
            force: 0.7,
            timestamp: 0.11
        ),
        HandDrawingInputSample(
            location: CGPoint(x: 30, y: 30),
            force: 0.9,
            timestamp: 0.2
        )
    ],
    appendingTo: existingSamples,
    configuration: configuration
)

XCTAssertEqual(update.stablePrefixCount, 1)
XCTAssertEqual(update.tailSamples.count, 2)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
// 函数名: testHandDrawingBrushDynamicsResolvedStampUpdateProducesTailAgainstCommittedPrefix()
// 功能说明: 新增测试验证 predicted tail 进入 resolvedStampUpdate 后，stablePrefixCount 仍然等于 committedResolvedStamps.count。
let predictedTailUpdate = HandDrawingBrushDynamics.resolvedStampUpdate(
    brush: brush,
    normalizedSamples: committedSamples + predictedTailSamples,
    previousResolvedStamps: committedResolvedStamps,
    layout: performanceProfile.stampLayout
)

XCTAssertEqual(
    predictedTailUpdate.stablePrefixCount,
    committedResolvedStamps.count
)
XCTAssertFalse(predictedTailUpdate.tailStamps.isEmpty)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
// 函数名: testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately()
// 功能说明: 修改后 contract test 关注 packet 结构本身，验证 committed tail 与 predicted tail 已被拆开表达。
let packet = HandDrawingRealtimeDraftPacket(
    strokeID: strokeID,
    brush: brush,
    performanceProfile: performanceProfile,
    committedSamples: HandDrawingRealtimeNormalizedSampleUpdate(
        stablePrefixCount: 1,
        tailSamples: Array(committedSamples.dropFirst())
    ),
    committedResolvedStamps: HandDrawingRealtimeResolvedStampUpdate(
        stablePrefixCount: committedResolvedStamps.count,
        tailStamps: []
    ),
    predictedTail: HandDrawingRealtimePredictedTail(
        normalizedSamples: predictedTailSamples,
        resolvedStamps: predictedTailUpdate.tailStamps
    )
)

XCTAssertEqual(packet.committedSamples.stablePrefixCount, 1)
XCTAssertEqual(packet.predictedTail.normalizedSamples.count, 1)
XCTAssertFalse(packet.predictedTail.resolvedStamps.isEmpty)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: testHandDrawingEditorCoordinatorPublishesPredictedTailSeparatelyFromCommittedRealtimePacket()
// 功能说明: 新增 coordinator 测试验证 realtimeDraftHost.packet 会分别发布 committed tail 与 predicted tail。
coordinator.handlePencilStrokeMoved(
    HandDrawingLiveInputBatch(
        committedSamples: [
            makeHandDrawingCoordinatorInputSample(
                x: 52,
                y: 40,
                timestamp: 0.1
            )
        ],
        predictedSamples: [
            makeHandDrawingCoordinatorInputSample(
                x: 86,
                y: 56,
                timestamp: 0.2
            )
        ]
    )
)

let realtimePacket = try XCTUnwrap(latestSurfaceState?.realtimeDraftHost.packet)
XCTAssertEqual(realtimePacket.committedSamples.stablePrefixCount, 1)
XCTAssertEqual(realtimePacket.predictedTail.normalizedSamples.count, 1)
XCTAssertFalse(realtimePacket.predictedTail.resolvedStamps.isEmpty)
```

## 验证结果与备注

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests
# 功能说明: 执行本次 phase 3 可在 macOS 上稳定运行的 hand drawing 核心回归测试。
** TEST SUCCEEDED **

Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushDynamicsResolvedStampUpdateProducesTailAgainstCommittedPrefix()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately()' passed
Test case 'HandDrawingInputNormalizerTests.testHandDrawingInputNormalizerProducesStablePrefixAndTailSamplesForIncrementalUpdates()' passed
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
# 功能说明: 验证 iOS 侧 coordinator / surface / realtime host / controller 接线在 simulator 目标上可以通过编译。
** BUILD SUCCEEDED **
```

- 如实说明一项测试取舍：
  - 在实现过程中，曾尝试直接对 `HandDrawingCPURealtimeBrushRenderer` 做 macOS XCTest 运行时调用断言，但测试 harness 再次出现 `abort()`，模式与 `phase 1` 曾遇到的 renderer harness crash 一致。
  - 因此最终保留在仓库中的稳定覆盖方式是：
    - packet 结构契约测试
    - `InputNormalizer` 增量 tail 测试
    - `BrushDynamics` 增量 stamp tail 测试
    - macOS hand drawing 核心回归
    - iOS Simulator app build
- `HandDrawingEditorCoordinatorTests.swift` 已按 phase 3 语义更新为检查 `packet / revision / predictedTail`，但本轮验证仍主要依赖上面的 macOS 核心回归与 iOS app 编译结果。

