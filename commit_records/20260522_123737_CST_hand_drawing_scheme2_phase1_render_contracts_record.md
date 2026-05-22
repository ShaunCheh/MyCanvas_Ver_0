# 20260522_123737_CST_hand_drawing_scheme2_phase1_render_contracts_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 1`，把 `Realtime` 与 `Committed` 两层 renderer 合同前置抽出来。
  - 本次修改只做到“契约层 + CPU 默认实现 + coordinator / surface 改向”，不进入 `phase 2` 的 `host` 拆分，也不接 `GPU / Metal`。
  - 本次保留 `HandDrawingCanvasRenderer` 作为 committed 路径的底层 CPU 实现，只是在其外部新增 backend 包装，不重写现有光栅化逻辑。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_123737_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对已跟踪文件执行 `git diff --stat -- ...`，结果为：`2 files changed, 37 insertions(+), 14 deletions(-)`。
  - 生成本记录前，针对两份新增文件执行 `git diff --no-index --stat -- /dev/null ...`，结果分别为：`88 insertions(+)` 与 `62 insertions(+)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short`，结果显示有 `2` 个已跟踪修改文件、`2` 个新增未跟踪文件。
- 本记录不包含：
  - `phase 2` 的 `committed host + realtime draft host` surface 拆分。
  - `phase 3` 的增量 `packetization`。
  - 任何 `GPU draft backend` 或 `GPU committed backend` 接线。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次方案二 phase 1 记录文件的时间戳前缀。
20260522_123737_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
# 功能说明: 汇总本次 phase 1 已跟踪生产文件的 diff 统计。
.../HandDrawingEditorCoordinator.swift             | 47 ++++++++++++++++------
.../UI/HandDrawingCanvasSurfaceView.swift          |  4 +-
2 files changed, 37 insertions(+), 14 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --no-index --stat -- /dev/null MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
# 功能说明: 汇总本次 phase 1 新增渲染契约文件的当前 changes 统计。
.../Rendering/HandDrawingRenderingContracts.swift  | 88 ++++++++++++++++++++++
1 file changed, 88 insertions(+)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --no-index --stat -- /dev/null MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 汇总本次 phase 1 新增契约测试文件的当前 changes 统计。
.../HandDrawingRenderingContractsTests.swift       | 62 ++++++++++++++++++++++
1 file changed, 62 insertions(+)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录本次 phase 1 相关文件在生成 markdown 前的当前 changes 状态。
M  MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M  MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
?? MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
```

## 当前 changes 摘要

- `HandDrawingRenderingContracts.swift` 新增 renderer-agnostic 契约层，把 `RealtimeDraftPacket`、`RealtimeBrushRenderer`、`CommittedCanvasBackend` 以及 CPU 默认实现集中到一处。
- `HandDrawingEditorCoordinator.swift` 从“直接持有 `draftStroke / committedImage` 的 UI 语义”改成“持有 `realtimeDraft / committedCanvas` 的可路由渲染语义”，并在内部构造 `currentRealtimeDraftPacket`。
- `HandDrawingCanvasSurfaceView.swift` 不再直接消费 `draftStroke / committedImage`，而是只读取 `realtimeDraft.stroke` 与 `committedCanvas.image`。
- `HandDrawingRenderingContractsTests.swift` 新增 phase 1 契约测试，锁住 CPU realtime renderer 只消费 packet，不重新发明笔刷数学或重建额外状态。

## 修改一：新增 renderer-agnostic 渲染契约层

### 修改前

- phase 1 之前，没有单独的 `Realtime / Committed` 渲染契约文件。
- `coordinator` 直接绑定具体 renderer 与 UI 语义，导致未来如果接入 `GPU draft backend`，很容易把后端细节继续粘进 `coordinator` 或 `surface`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift（修改前）
// 函数名: 无
// 功能说明: phase 1 前该文件不存在，realtime 与 committed 两层渲染合同尚未独立成共享接口。
// 修改前状态: 无独立 renderer-agnostic 契约层。
```

### 修改后

- 新增 `HandDrawingRealtimeDraftPacket`，把 realtime backend 真正需要消费的共享输入集中起来：
  - `brush`
  - `performanceProfile`
  - `normalizedSamples`
  - `draftStroke`
  - `resolvedStamps`
- 新增 `HandDrawingRealtimeBrushRenderer` 与 `HandDrawingCommittedCanvasBackend` 两个协议。
- 新增 `HandDrawingCPURealtimeBrushRenderer` 与 `HandDrawingCPUCommittedCanvasBackend` 两个 CPU 默认实现，先把依赖方向改对，再为后续替换 backend 预留插口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeBrushRenderer.render(packet:) / HandDrawingCommittedCanvasBackend.render(document:dirtyRegion:)
// 功能说明: phase 1 新增共享渲染合同，约束 realtime 与 committed backend 只消费统一笔刷数学产物；CPU 版本先作为默认实现落地。
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

struct HandDrawingCPURealtimeBrushRenderer: HandDrawingRealtimeBrushRenderer {
    func render(
        packet: HandDrawingRealtimeDraftPacket?
    ) -> HandDrawingRealtimeDraftRenderOutput {
        guard let packet else {
            return .none
        }
        return .stroke(packet.draftStroke)
    }
}

enum HandDrawingCommittedCanvasRenderOutput {
    case none
    case bitmap(CGImage)

    var image: CGImage? {
        switch self {
        case .none:
            return nil
        case let .bitmap(image):
            return image
        }
    }
}

protocol HandDrawingCommittedCanvasBackend {
    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect?
    ) throws -> HandDrawingCommittedCanvasRenderOutput
}

final class HandDrawingCPUCommittedCanvasBackend: HandDrawingCommittedCanvasBackend {
    private let canvasRenderer: HandDrawingCanvasRenderer

    init(
        paperSize: CGSize,
        backgroundColor: HandDrawingColor? = nil
    ) throws {
        canvasRenderer = try HandDrawingCanvasRenderer(
            paperSize: paperSize,
            backgroundColor: backgroundColor
        )
    }

    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect?
    ) throws -> HandDrawingCommittedCanvasRenderOutput {
        .bitmap(
            try canvasRenderer.render(
                document: document,
                dirtyRegion: dirtyRegion
            )
        )
    }
}
```

## 修改二：`HandDrawingEditorCoordinator` 从直接持有 UI 原始对象，改为持有可路由渲染语义

### 修改前

- `HandDrawingCanvasSurfaceState` 直接暴露 `committedImage` 与 `draftStroke`。
- `HandDrawingEditorCoordinator` 直接持有 `HandDrawingCanvasRenderer`。
- realtime 路径内部只有一个 `draftStroke` 计算属性，surface 收到的也是最终 `stroke` 对象，而不是一个可路由的 packet。
- committed 路径也直接返回 `CGImage`，没有经过 backend 抽象。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: HandDrawingCanvasSurfaceState / init(editorContext:) / draftStroke / publishSurfaceState() / refreshCommittedImageAndPublishState(forceFullRender:)
// 功能说明: 修改前 coordinator 直接持有 draftStroke 与 committedImage 两类 UI 原始对象，尚未抽出可替换 backend 的渲染语义。
struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedImage: CGImage?
    var draftStroke: HandDrawingStroke?
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

private let canvasRenderer: HandDrawingCanvasRenderer
private var committedImage: CGImage?

init(editorContext: CanvasHandDrawingEditorContext) throws {
    self.editorContext = editorContext
    let document = try HandDrawingDocumentLoader.loadDocument(
        from: editorContext.documentData,
        paper: editorContext.paper
    )
    canvasRenderer = try HandDrawingCanvasRenderer(paperSize: document.paper.size)
    // ... 省略其它初始化代码 ...
    committedImage = try canvasRenderer.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
}

private var draftStroke: HandDrawingStroke? {
    guard
        let activeStrokeBrush,
        activeStrokeInputSamples.isEmpty == false
    else {
        return nil
    }
    return HandDrawingStrokeBuilder.makeStroke(
        brush: activeStrokeBrush,
        normalizedSamples: activeStrokeInputSamples
    )
}

private func publishSurfaceState() {
    onSurfaceStateChange?(
        HandDrawingCanvasSurfaceState(
            paperSize: editorContext.paper.size,
            committedImage: committedImage,
            draftStroke: draftStroke,
            lassoPathPoints: lassoToolController.points,
            selectedStrokeBounds: selectedStrokeBounds
        )
    )
}

private func refreshCommittedImageAndPublishState(
    forceFullRender: Bool = false
) {
    do {
        let dirtyRegion = forceFullRender
            ? engine.state.document.paperBounds
            : engine.consumeDirtyRegion()
        guard forceFullRender || dirtyRegion != nil else {
            return
        }
        committedImage = try canvasRenderer.render(
            document: engine.state.document,
            dirtyRegion: dirtyRegion
        )
        publishSurfaceState()
        publishPaletteState()
        publishLayerPanelState()
    } catch {
        onErrorMessage?(error.localizedDescription)
    }
}
```

### 修改后

- `HandDrawingCanvasSurfaceState` 改成暴露 `committedCanvas` 与 `realtimeDraft` 两类渲染语义。
- `HandDrawingEditorCoordinator` 改为持有：
  - `committedCanvasBackend`
  - `realtimeBrushRenderer`
- initializer 支持注入 backend；默认仍走 CPU 实现，所以 phase 1 不引入行为变化。
- 新增 `currentRealtimeDraftPacket`，统一承载未来 realtime backend 的共享输入，不再把 `draftStroke` 当成唯一语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingCanvasSurfaceState / init(editorContext:committedCanvasBackend:realtimeBrushRenderer:) / currentRealtimeDraftPacket / publishSurfaceState() / refreshCommittedImageAndPublishState(forceFullRender:)
// 功能说明: 修改后 coordinator 改为持有可路由的 committed / realtime 渲染语义，并统一通过 packet 向 realtime backend 发布共享笔刷输入。
struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedCanvas: HandDrawingCommittedCanvasRenderOutput
    var realtimeDraft: HandDrawingRealtimeDraftRenderOutput
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

private let committedCanvasBackend: HandDrawingCommittedCanvasBackend
private let realtimeBrushRenderer: HandDrawingRealtimeBrushRenderer
private var committedCanvas: HandDrawingCommittedCanvasRenderOutput = .none

init(
    editorContext: CanvasHandDrawingEditorContext,
    committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil,
    realtimeBrushRenderer: HandDrawingRealtimeBrushRenderer = HandDrawingCPURealtimeBrushRenderer()
) throws {
    self.editorContext = editorContext
    let document = try HandDrawingDocumentLoader.loadDocument(
        from: editorContext.documentData,
        paper: editorContext.paper
    )
    let resolvedCommittedCanvasBackend = try committedCanvasBackend
        ?? HandDrawingCPUCommittedCanvasBackend(paperSize: document.paper.size)
    self.committedCanvasBackend = resolvedCommittedCanvasBackend
    self.realtimeBrushRenderer = realtimeBrushRenderer
    // ... 省略其它初始化代码 ...
    committedCanvas = try resolvedCommittedCanvasBackend.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
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

private func publishSurfaceState() {
    onSurfaceStateChange?(
        HandDrawingCanvasSurfaceState(
            paperSize: editorContext.paper.size,
            committedCanvas: committedCanvas,
            // 将实时笔刷输入路由给可替换 backend，当前默认实现仍返回 stroke。
            realtimeDraft: realtimeBrushRenderer.render(
                packet: currentRealtimeDraftPacket
            ),
            lassoPathPoints: lassoToolController.points,
            selectedStrokeBounds: selectedStrokeBounds
        )
    )
}

private func refreshCommittedImageAndPublishState(
    forceFullRender: Bool = false
) {
    do {
        let dirtyRegion = forceFullRender
            ? engine.state.document.paperBounds
            : engine.consumeDirtyRegion()
        guard forceFullRender || dirtyRegion != nil else {
            return
        }
        committedCanvas = try committedCanvasBackend.render(
            document: engine.state.document,
            dirtyRegion: dirtyRegion
        )
        publishSurfaceState()
        publishPaletteState()
        publishLayerPanelState()
    } catch {
        onErrorMessage?(error.localizedDescription)
    }
}
```

## 修改三：`HandDrawingCanvasSurfaceView` 改为只消费渲染语义，不直接依赖旧字段

### 修改前

- `surface view` 直接读取 `state.committedImage` 与 `state.draftStroke`。
- 这意味着一旦 `coordinator` 想切换 backend，surface 也会跟着绑定具体数据形态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingCanvasPageView.apply(state:)
// 功能说明: 修改前 surface 直接消费 committedImage 与 draftStroke，UI 层与具体渲染数据形态强耦合。
func apply(state: HandDrawingCanvasSurfaceState) {
    if let committedImage = state.committedImage {
        committedImageView.image = UIImage(cgImage: committedImage)
    } else {
        committedImageView.image = nil
    }
    draftOverlayView.draftStroke = state.draftStroke
    draftOverlayView.lassoPathPoints = state.lassoPathPoints
    draftOverlayView.selectedStrokeBounds = state.selectedStrokeBounds
}
```

### 修改后

- `surface view` 仍然复用现有 `UIImageView + draftOverlayView` 结构。
- 但读取入口已经改成：
  - `state.committedCanvas.image`
  - `state.realtimeDraft.stroke`
- 这样 phase 2 再拆 host 时，可以在不改 `coordinator` 语义边界的前提下继续推进。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCanvasPageView.apply(state:)
// 功能说明: 修改后 surface 只消费 committed / realtime 两类渲染输出语义，不再直接依赖旧的 raw image / raw stroke 字段名。
func apply(state: HandDrawingCanvasSurfaceState) {
    if let committedImage = state.committedCanvas.image {
        committedImageView.image = UIImage(cgImage: committedImage)
    } else {
        committedImageView.image = nil
    }
    draftOverlayView.draftStroke = state.realtimeDraft.stroke
    draftOverlayView.lassoPathPoints = state.lassoPathPoints
    draftOverlayView.selectedStrokeBounds = state.selectedStrokeBounds
}
```

## 修改四：新增 phase 1 契约测试，先锁住 CPU realtime renderer 的默认语义

### 修改前

- phase 0 已经补过 `resolved stamps` 与 `draft / committed / preview` 的护栏。
- 但在 phase 1 新引入 `realtime renderer` 契约后，还没有一条测试明确说明“CPU realtime renderer 只是消费 packet 并回传 draft stroke 语义”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift（修改前）
// 函数名: 无
// 功能说明: phase 1 前该测试文件不存在，CPU realtime renderer 的默认契约没有独立测试覆盖。
// 修改前状态: 无独立的 HandDrawingRenderingContractsTests。
```

### 修改后

- 新增 `HandDrawingRenderingContractsTests`。
- 新增 `testHandDrawingCPURealtimeBrushRendererReturnsDraftStrokeFromPacket()`：
  - 先构造 `brush`
  - 再构造 `performanceProfile`
  - 再生成 `normalizedSamples`
  - 再生成 `draftStroke`
  - 再组装 `HandDrawingRealtimeDraftPacket`
  - 最后验证 CPU realtime renderer：
    - 传 `nil` 返回 `.none`
    - 传 packet 返回 `.stroke(draftStroke)`
- 这条测试的作用不是重复验证 brush math，而是保证 phase 1 新引入的 CPU 默认 renderer 不额外创造状态，不篡改 packet 里的既有语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
// 函数名: testHandDrawingCPURealtimeBrushRendererReturnsDraftStrokeFromPacket()
// 功能说明: 修改后新增 phase 1 契约测试，锁住 CPU realtime renderer 仅消费 packet 并返回 draft stroke 语义。
final class HandDrawingRenderingContractsTests: XCTestCase {
    func testHandDrawingCPURealtimeBrushRendererReturnsDraftStrokeFromPacket() throws {
        let brush = HandDrawingBrushStyle(
            kind: .pen,
            color: .black,
            baseSize: 12,
            opacity: 0.9,
            tiltSizeInfluence: 0.65,
            tiltOpacityInfluence: 0.14
        )
        let performanceProfile = HandDrawingStrokePerformanceProfile
            .brushStroke(for: brush)
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 20, y: 24),
                    force: 0.4,
                    timestamp: 0
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 58, y: 42),
                    force: 0.72,
                    timestamp: 0.1,
                    azimuthRadians: 0.42,
                    altitudeRadians: .pi / 4
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 96, y: 60),
                    force: 0.95,
                    timestamp: 0.2,
                    azimuthRadians: 0.75,
                    altitudeRadians: .pi / 5
                )
            ],
            configuration: performanceProfile.inputNormalization
        )
        let draftStroke = try XCTUnwrap(
            HandDrawingStrokeBuilder.makeStroke(
                brush: brush,
                normalizedSamples: normalizedSamples
            )
        )
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
    }
}
```

## 验证结果

- 已执行 hand drawing 相关定点测试，覆盖：
  - `HandDrawingRenderingContractsTests`
  - `HandDrawingStrokeBuilderTests`
  - `HandDrawingBrushDynamicsTests`
  - `HandDrawingCanvasRendererTests`
  - `HandDrawingPreviewRendererTests`
  - `HandDrawingEditorEngineTests`
- 已执行 iOS Simulator 构建，确认 `coordinator / surface / 渲染契约层` 编译链路通过。
- 已检查本次修改相关文件的 lints，无新增问题。

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project /Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj -scheme MyCanvas_Ver_0 -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests
# 功能说明: 验证 phase 1 契约层以及现有 hand drawing 护栏在本次改造后仍保持通过。
# 结果说明: 命令执行成功，相关测试集通过。
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project /Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj -scheme MyCanvas_Ver_0 -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
# 功能说明: 验证 iOS Simulator 构建链路在引入 phase 1 renderer contracts 后仍能通过。
# 结果说明: 命令执行成功，iOS Simulator build 通过。
```

## 与 phase 2 的边界

- phase 1 到这里为止，已经把：
  - `realtime draft` 的输入语义
  - `committed canvas` 的输出语义
  - `coordinator -> surface` 的路由边界
  抽成了可替换 backend 的合同。
- 但当前 `surface view` 仍然是一个宿主里同时持有 `committedImageView` 与 `draftOverlayView` 的结构，还没有进入 `phase 2` 的 host 拆分。
- 因此下一阶段如果继续推进，重点应放在：
  - 把 committed host 与 realtime draft host 拆开
  - 保留 CPU fallback
  - 不把 `lasso / selection / 其它 overlay` 一起卷进 GPU
