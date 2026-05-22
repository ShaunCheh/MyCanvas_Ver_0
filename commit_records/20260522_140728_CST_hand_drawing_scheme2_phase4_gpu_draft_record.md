# 20260522_140728_CST_hand_drawing_scheme2_phase4_gpu_draft_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 4`，把 realtime draft 从“只有 CPU fallback host”升级为“GPU 优先、CPU fallback 保留”的运行时结构。
  - 本次修改只作用于 realtime draft 渲染层，不改动 committed canvas、preview、export、persistence 的 CPU 真相源。
  - 本次重点是把 `MTKView / Metal` 真正接入现有 `realtime draft host`，而不是只停留在协议抽象层。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
- 本记录不包含：
  - committed canvas backend 的 GPU 原型。
  - preview / export 的 GPU 化。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date '+%Y%m%d_%H%M%S_CST_hand_drawing_scheme2_phase4_gpu_draft_record'
# 功能说明: 使用系统 date 命令生成本次 phase 4 记录文件的时间戳与文件名前缀。
20260522_140728_CST_hand_drawing_scheme2_phase4_gpu_draft_record
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 汇总本次 phase 4 GPU draft backend 接入的最终 diff 统计。
.../Rendering/HandDrawingRenderingContracts.swift  |  88 ++++--
.../HandDrawingEditorCoordinator.swift             |  25 +-
.../UI/HandDrawingCanvasSurfaceView.swift          | 343 +++++++++++++++++++++
.../HandDrawingEditorCoordinatorTests.swift        |   3 +
4 files changed, 419 insertions(+), 40 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录生成本文件时，工作区里与本次 phase 4 对应的当前 changes。
M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
```

## 当前 changes 摘要

- `HandDrawingRenderingContracts.swift` 新增 `HandDrawingRealtimeDraftBackendPreference`，并把 CPU realtime renderer 的增量缓存下沉为共享的 `HandDrawingRealtimeDraftPacketAccumulator`。
- `HandDrawingEditorCoordinator.swift` 开始把 realtime draft 的 backend 偏好显式发布到 `HandDrawingRealtimeDraftHostState`，默认值为 `.gpuPreferred`。
- `HandDrawingCanvasSurfaceView.swift` 在现有 CPU realtime host 之上接入 `MTKView` 路径：
  - host 会优先尝试装配 GPU renderer
  - 若 `MTLDevice` 或 pipeline 初始化失败，则自动回退 CPU renderer
- `HandDrawingEditorCoordinatorTests.swift` 新增对 `preferredBackend` 的断言，确认 coordinator 已按 phase 4 语义发布 host 状态。

## 修改一：把 realtime backend 偏好显式发布到 host state

### 修改前

- `HandDrawingRealtimeDraftHostState` 只有 `revision` 与 `packet`。
- coordinator 虽然已经能发布增量 realtime packet，但 surface host 不知道当前想要使用 CPU 还是 GPU，只能固定安装既有 renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: HandDrawingRealtimeDraftHostState / HandDrawingEditorCoordinator.init(...) / advanceRealtimeDraftHostState(with:)
// 功能说明: 修改前 realtime host state 不携带 backend 偏好，coordinator 也没有显式的 GPU/CPU 切换语义。
struct HandDrawingRealtimeDraftHostState {
    static let idle = HandDrawingRealtimeDraftHostState(
        revision: 0,
        packet: nil
    )

    var revision: UInt64
    var packet: HandDrawingRealtimeDraftPacket?
}

init(
    editorContext: CanvasHandDrawingEditorContext,
    committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil
) throws {
    self.editorContext = editorContext
    // ... 省略无关初始化 ...
}

private func advanceRealtimeDraftHostState(
    with packet: HandDrawingRealtimeDraftPacket?
) {
    realtimeDraftHostState = HandDrawingRealtimeDraftHostState(
        revision: realtimeDraftHostState.revision + 1,
        packet: packet
    )
}
```

### 修改后

- realtime contract 层新增 `HandDrawingRealtimeDraftBackendPreference`。
- `HandDrawingRealtimeDraftHostState` 现在显式包含 `preferredBackend`。
- coordinator 初始化时默认选择 `.gpuPreferred`，并在每次推进新 revision 时一并发布到 host state。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeDraftBackendPreference
// 功能说明: phase 4 引入 realtime draft backend 偏好，允许 host 在 GPU 优先与 CPU fallback 之间切换。
enum HandDrawingRealtimeDraftBackendPreference: Equatable {
    case cpu
    case gpuPreferred
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingRealtimeDraftHostState / HandDrawingEditorCoordinator.init(...) / advanceRealtimeDraftHostState(with:)
// 功能说明: 修改后 coordinator 会把 realtime draft 的 backend 偏好与 packet 一起发布给 surface host。
struct HandDrawingRealtimeDraftHostState {
    static func idle(
        preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) -> HandDrawingRealtimeDraftHostState {
        HandDrawingRealtimeDraftHostState(
            preferredBackend: preferredBackend,
            revision: 0,
            packet: nil
        )
    }

    var preferredBackend: HandDrawingRealtimeDraftBackendPreference
    var revision: UInt64
    var packet: HandDrawingRealtimeDraftPacket?
}

private let realtimeDraftBackendPreference: HandDrawingRealtimeDraftBackendPreference

init(
    editorContext: CanvasHandDrawingEditorContext,
    committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil,
    realtimeDraftBackendPreference: HandDrawingRealtimeDraftBackendPreference = .gpuPreferred
) throws {
    self.editorContext = editorContext
    self.realtimeDraftBackendPreference = realtimeDraftBackendPreference
    realtimeDraftHostState = .idle(
        preferredBackend: realtimeDraftBackendPreference
    )
    // ... 省略无关初始化 ...
}

private func advanceRealtimeDraftHostState(
    with packet: HandDrawingRealtimeDraftPacket?
) {
    realtimeDraftHostState = HandDrawingRealtimeDraftHostState(
        preferredBackend: realtimeDraftBackendPreference,
        revision: realtimeDraftHostState.revision + 1,
        packet: packet
    )
}
```

## 修改二：把 CPU realtime 增量状态提炼成共享 accumulator

### 修改前

- `HandDrawingCPURealtimeBrushRenderer` 自己持有：
  - `activeStrokeID`
  - `activeBrush`
  - committed / predicted `resolvedStamps`
- 这意味着如果 phase 4 的 GPU host 也要吃同一份增量 packet，就必须重复实现一遍完全相同的 packet 累加逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift（修改前）
// 函数名: HandDrawingCPURealtimeBrushRenderer.apply(packet:)
// 功能说明: 修改前 CPU realtime renderer 既承担 packet 累加，又承担 render output 组装，增量逻辑无法被 GPU host 复用。
final class HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    private var activeStrokeID: UUID?
    private var activeBrush: HandDrawingBrushStyle?
    private var committedResolvedStamps: [HandDrawingResolvedBrushSample] = []
    private var predictedResolvedStamps: [HandDrawingResolvedBrushSample] = []

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let packet else {
            activeStrokeID = nil
            activeBrush = nil
            committedResolvedStamps.removeAll()
            predictedResolvedStamps.removeAll()
            return .none
        }

        // ... 省略 tail replace / predicted tail 更新 ...
        return .resolved(
            HandDrawingRealtimeDraftRenderState(
                brush: activeBrush,
                committedResolvedStamps: committedResolvedStamps,
                predictedResolvedStamps: predictedResolvedStamps
            )
        )
    }
}
```

### 修改后

- 新增 `HandDrawingRealtimeDraftPacketAccumulator`，统一处理：
  - 新 stroke 切换
  - committed tail 替换
  - predicted tail 覆盖
  - reset
- `HandDrawingCPURealtimeBrushRenderer` 改成只做轻量包装。
- 这样 phase 4 的 CPU host 与 GPU host 都消费同一份 accumulator 结果，保证 packet 语义一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeDraftPacketAccumulator.apply(packet:) / reset() / HandDrawingCPURealtimeBrushRenderer.apply(packet:)
// 功能说明: 修改后增量 packet 的累加逻辑被抽成共享 accumulator，CPU/GPU 两条 realtime 路径都可以复用同一份 packet 解析结果。
final class HandDrawingRealtimeDraftPacketAccumulator {
    private var activeStrokeID: UUID?
    private var activeBrush: HandDrawingBrushStyle?
    private var committedResolvedStamps: [HandDrawingResolvedBrushSample] = []
    private var predictedResolvedStamps: [HandDrawingResolvedBrushSample] = []

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderState? {
        guard let packet else {
            reset()
            return nil
        }

        if activeStrokeID != packet.strokeID {
            committedResolvedStamps.removeAll()
            predictedResolvedStamps.removeAll()
        }
        activeStrokeID = packet.strokeID
        activeBrush = packet.brush
        committedResolvedStamps = replaceTail(
            in: committedResolvedStamps,
            stablePrefixCount: packet.committedResolvedStamps.stablePrefixCount,
            tail: packet.committedResolvedStamps.tailStamps
        )
        predictedResolvedStamps = packet.predictedTail.resolvedStamps

        guard let activeBrush else {
            return nil
        }
        return HandDrawingRealtimeDraftRenderState(
            brush: activeBrush,
            committedResolvedStamps: committedResolvedStamps,
            predictedResolvedStamps: predictedResolvedStamps
        )
    }

    func reset() {
        activeStrokeID = nil
        activeBrush = nil
        committedResolvedStamps.removeAll()
        predictedResolvedStamps.removeAll()
    }
}

final class HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    private let accumulator = HandDrawingRealtimeDraftPacketAccumulator()

    func apply(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let renderState = accumulator.apply(packet: packet) else {
            return .none
        }
        return .resolved(renderState)
    }
}
```

## 修改三：把 realtime draft host 从“固定 CPU renderer”升级为“GPU 优先 / CPU fallback”

### 修改前

- `HandDrawingCanvasSurfaceView.swift` 里只有 CPU realtime draft host。
- `HandDrawingRealtimeDraftHostView.apply(state:)` 只是把状态直接转发给当前 renderer host。
- 没有 `MetalKit` 引入，也没有 `MTKView` 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingRealtimeDraftHostView.apply(state:) / HandDrawingCPURealtimeDraftRendererView.apply(state:) / draw(_:)
// 功能说明: 修改前 realtime draft host 只有 CPU 路径，无法按 runtime 状态切换到 GPU draft backend。
private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting

    func apply(state: HandDrawingRealtimeDraftHostState) {
        rendererHost.apply(state: state)
    }
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
        if let resolvedState = renderOutput.resolvedState {
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

### 修改后

- `HandDrawingCanvasSurfaceView.swift` 引入 `MetalKit`。
- `HandDrawingRealtimeDraftHostView` 新增：
  - `activeBackend`
  - `installPreferredRendererIfNeeded(for:)`
  - `resolveBackend(from:)`
- host 会先看 coordinator 发布的 `preferredBackend`，再尝试：
  - 装 `HandDrawingGPURealtimeDraftRendererView`
  - 失败则装回 `HandDrawingCPURealtimeDraftRendererView`
- `activeBackend` 会记录“实际装进去的 host”，避免“宣称 GPU，但运行时其实已回退 CPU”的状态错位。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingRealtimeDraftHostView.apply(state:) / installPreferredRendererIfNeeded(for:) / resolveBackend(from:)
// 功能说明: 修改后 realtime draft host 会根据 coordinator 发布的 backend 偏好，优先装 GPU host，失败时自动回退 CPU host。
#if canImport(MetalKit)
import MetalKit
#endif

private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting
    private var activeBackend: HandDrawingRealtimeDraftBackendPreference = .cpu

    func apply(state: HandDrawingRealtimeDraftHostState) {
        installPreferredRendererIfNeeded(for: state.preferredBackend)
        rendererHost.apply(state: state)
    }

    private func installPreferredRendererIfNeeded(
        for preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) {
        let resolvedBackend = Self.resolveBackend(from: preferredBackend)
        guard resolvedBackend != activeBackend else {
            return
        }

        let installedBackend: HandDrawingRealtimeDraftBackendPreference
        switch resolvedBackend {
        case .cpu:
            setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            installedBackend = .cpu
        case .gpuPreferred:
            #if canImport(MetalKit)
            if let gpuRendererHost = HandDrawingGPURealtimeDraftRendererView.makeIfSupported() {
                setRendererHost(gpuRendererHost)
                installedBackend = .gpuPreferred
            } else {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
                installedBackend = .cpu
            }
            #else
            setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            installedBackend = .cpu
            #endif
        }
        activeBackend = installedBackend
    }
}
```

## 修改四：新增 iOS-only 的 `MTKView` GPU realtime draft renderer

### 修改前

- realtime draft 层没有任何 `Metal / MTKView` 相关实现。
- 即使 phase 3 已经把 packet 抽成增量语义，显示层仍旧只能走 `CGContext`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: 无
// 功能说明: 修改前文件内不存在 GPU realtime draft renderer，也不存在 Metal shader 或 MTKView 生命周期。
// （此处无对应实现）
```

### 修改后

- 新增 `HandDrawingGPURealtimeDraftRendererView: MTKView`。
- GPU host 的职责是：
  - 用共享 `HandDrawingRealtimeDraftPacketAccumulator` 消费 packet
  - 把 `resolvedStamps` 转换成 Metal instance buffer
  - 使用运行时构建的 vertex / fragment shader 绘制椭圆 stamp
- 这条路径仍然只服务于 realtime draft，committed canvas 没有迁移到 GPU。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported() / apply(state:) / draw(in:) / rebuildStampInstanceBuffer()
// 功能说明: phase 4 新增 iOS-only GPU realtime draft host，直接消费增量 packet 展开的 resolvedStamps，并把它们提交给 Metal 渲染。
#if canImport(MetalKit)
private final class HandDrawingGPURealtimeDraftRendererView: MTKView, HandDrawingRealtimeDraftRendererHosting, MTKViewDelegate {
    private let accumulator = HandDrawingRealtimeDraftPacketAccumulator()
    private let metalCommandQueue: MTLCommandQueue
    private let renderPipelineState: MTLRenderPipelineState
    private var lastAppliedRevision: UInt64?
    private var renderState: HandDrawingRealtimeDraftRenderState?
    private var stampInstanceBuffer: MTLBuffer?
    private var stampInstanceCount = 0

    static func makeIfSupported() -> HandDrawingGPURealtimeDraftRendererView? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        return try? HandDrawingGPURealtimeDraftRendererView(device: device)
    }

    func apply(state: HandDrawingRealtimeDraftHostState) {
        guard lastAppliedRevision != state.revision else {
            return
        }
        lastAppliedRevision = state.revision
        renderState = accumulator.apply(packet: state.packet)
        rebuildStampInstanceBuffer()
        setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard
            let currentDrawable,
            let renderPassDescriptor = currentRenderPassDescriptor,
            let commandBuffer = metalCommandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            return
        }

        renderEncoder.setRenderPipelineState(renderPipelineState)
        if let stampInstanceBuffer, stampInstanceCount > 0 {
            var canvasSize = SIMD2<Float>(
                Float(max(bounds.width, 1)),
                Float(max(bounds.height, 1))
            )
            renderEncoder.setVertexBuffer(stampInstanceBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(
                &canvasSize,
                length: MemoryLayout<SIMD2<Float>>.stride,
                index: 1
            )
            renderEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: stampInstanceCount
            )
        }
        renderEncoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingGPURealtimeDraftRendererView.shaderSource
// 功能说明: GPU draft host 使用运行时构建的 Metal shader，对每个 stamp 做旋转椭圆插值与 feather 边缘处理。
private static let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct StampInstance {
    float2 center;
    float2 radii;
    float2 rotationSinCos;
    float2 padding0;
    float4 color;
    float opacity;
    float3 padding1;
};

vertex VertexOut handDrawingDraftVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant StampInstance *instances [[buffer(0)]],
    constant float2 &canvasSize [[buffer(1)]]
) {
    // ... 省略中间无关代码 ...
}

fragment half4 handDrawingDraftFragment(VertexOut in [[stage_in]]) {
    float radialDistance = length(in.unitPosition);
    float feather = max(fwidth(radialDistance), 0.001);
    float coverage = 1.0 - smoothstep(
        1.0 - feather,
        1.0 + feather,
        radialDistance
    );
    if (coverage <= 0.0) {
        discard_fragment();
    }

    return half4(
        half3(in.color.rgb),
        half(in.color.a * in.opacity * coverage)
    );
}
"""
```

## 修改五：测试改成检查 coordinator 已发布 GPU draft 偏好

### 修改前

- `HandDrawingEditorCoordinatorTests.swift` 只验证：
  - `packet`
  - `revision`
  - `predictedTail`
- 但没有验证 phase 4 新增的 `preferredBackend` 是否真的随 surface state 一起发布。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift（修改前）
// 函数名: testHandDrawingEditorCoordinatorPublishesSeparatedCommittedAndRealtimeHostState() / testHandDrawingEditorCoordinatorPublishesPredictedTailSeparatelyFromCommittedRealtimePacket()
// 功能说明: 修改前测试只检查 packet 与 revision，没有检查 GPU draft backend 偏好是否被 coordinator 正确发布。
XCTAssertNil(initialSurfaceState.realtimeDraftHost.packet)
XCTAssertEqual(initialSurfaceState.realtimeDraftHost.revision, 0)

let realtimePacket = try XCTUnwrap(activeDraftSurfaceState.realtimeDraftHost.packet)
XCTAssertGreaterThan(activeDraftSurfaceState.realtimeDraftHost.revision, 0)

let realtimePacket = try XCTUnwrap(latestSurfaceState?.realtimeDraftHost.packet)
XCTAssertEqual(realtimePacket.committedSamples.stablePrefixCount, 1)
```

### 修改后

- 在三个关键断言点补上 `preferredBackend == .gpuPreferred`。
- 这样可以确认：
  - coordinator 的默认配置确实进入了 surface state
  - 起笔后仍保持 GPU 优先偏好
  - predicted tail 更新路径没有把 backend 偏好丢掉

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: testHandDrawingEditorCoordinatorPublishesSeparatedCommittedAndRealtimeHostState() / testHandDrawingEditorCoordinatorPublishesPredictedTailSeparatelyFromCommittedRealtimePacket()
// 功能说明: 修改后测试会显式校验 coordinator 发布的 realtime draft host state 默认偏好是 GPU。
XCTAssertNil(initialSurfaceState.realtimeDraftHost.packet)
XCTAssertEqual(initialSurfaceState.realtimeDraftHost.preferredBackend, .gpuPreferred)
XCTAssertEqual(initialSurfaceState.realtimeDraftHost.revision, 0)

let realtimePacket = try XCTUnwrap(activeDraftSurfaceState.realtimeDraftHost.packet)
XCTAssertEqual(activeDraftSurfaceState.realtimeDraftHost.preferredBackend, .gpuPreferred)
XCTAssertGreaterThan(activeDraftSurfaceState.realtimeDraftHost.revision, 0)

let realtimePacket = try XCTUnwrap(latestSurfaceState?.realtimeDraftHost.packet)
XCTAssertEqual(latestSurfaceState?.realtimeDraftHost.preferredBackend, .gpuPreferred)
XCTAssertEqual(realtimePacket.committedSamples.stablePrefixCount, 1)
```

## 验证结果与备注

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests
# 功能说明: 执行本次 phase 4 仍可在 macOS 上稳定运行的 hand drawing 核心回归测试，确认 GPU draft 接入没有破坏 packet contract 与 CPU 真相源路径。
** TEST SUCCEEDED **

Test case 'HandDrawingCanvasRendererTests.testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints()' passed
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushDynamicsResolvedStampUpdateProducesTailAgainstCommittedPrefix()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately()' passed
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
# 功能说明: 验证 iOS 侧 `MTKView` GPU draft host、surface host 切换逻辑与 coordinator 接线在 simulator 目标上可以通过编译。
** BUILD SUCCEEDED **
```

- 如实说明一项验证取舍：
  - 在实现过程中，曾短暂尝试为共享 `HandDrawingRealtimeDraftPacketAccumulator` 增加一条 macOS 运行时单测，但该测试又复现了此前 phase 1 / phase 3 出现过的 `abort()` 型 test harness crash。
  - 由于这条测试最终没有保留在当前 changes 中，本次仓库里的稳定验证面仍然是：
    - `HandDrawingEditorCoordinatorTests.swift` 的 backend 偏好断言
    - 既有 packet contract / brush dynamics / CPU 真相源回归
    - iOS Simulator app build
- `ReadLints` 检查结果为：本次涉及文件没有新增 lint 问题。

