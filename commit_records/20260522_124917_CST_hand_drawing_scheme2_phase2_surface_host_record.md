# 20260522_124917_CST_hand_drawing_scheme2_phase2_surface_host_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 2`，把 `surface` 从“`UIImageView + 单一 overlay`”重构为“`committed host + realtime draft host + interaction overlay host`”。
  - 本次修改仍然保留 CPU fallback，不引入 `GPU / Metal`，也不提前进入 `phase 3` 的增量 `packetization`。
  - 本次重点是把宿主结构拆对，让后续 realtime draft backend 可以独立热插拔，而不是继续和 `lasso / selected bounds` 绑死在一个 overlay view 里。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_124917_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次 `phase 2` 文件执行 `git diff --stat -- ...`，结果为：`3 files changed, 300 insertions(+), 51 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short`，结果显示仅有 `3` 个已跟踪文件发生修改。
  - 本次工作区中与本记录对应的 changes 仅覆盖 `phase 2` 的 surface host 重构与对应测试。
- 本记录不包含：
  - `phase 3` 的增量 realtime packet 发布。
  - 任何 `GPU draft backend` 接入。
  - 任何 `GPU committed backend` 抽象。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次方案二 phase 2 markdown 记录文件的时间戳前缀。
20260522_124917_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 汇总本次方案二 phase 2 surface host 重构相关文件的 diff 统计。
.../HandDrawingEditorCoordinator.swift             |  61 ++++---
.../UI/HandDrawingCanvasSurfaceView.swift          | 182 +++++++++++++++++----
.../HandDrawingEditorCoordinatorTests.swift        | 108 ++++++++++++
3 files changed, 300 insertions(+), 51 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录本次方案二 phase 2 相关文件的当前 changes 状态。
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
```

## 当前 changes 摘要

- `HandDrawingEditorCoordinator.swift` 不再把 `surface state` 当成一份扁平的渲染数据，而是拆成：
  - `HandDrawingCommittedCanvasHostState`
  - `HandDrawingRealtimeDraftHostState`
  - `HandDrawingCanvasInteractionOverlayState`
- `HandDrawingCanvasSurfaceView.swift` 里的页面宿主不再是 `committedImageView + draftOverlayView` 两层结构，而是三层宿主：
  - `HandDrawingCommittedCanvasHostView`
  - `HandDrawingRealtimeDraftHostView`
  - `HandDrawingCanvasInteractionOverlayView`
- `HandDrawingRealtimeDraftHostView` 下新增 `HandDrawingRealtimeDraftRendererHosting` 协议和默认 `HandDrawingCPURealtimeDraftRendererView`，先为 future GPU host 预留热插拔位置。
- `HandDrawingEditorCoordinatorTests.swift` 新增 `HandDrawingEditorCoordinatorSurfaceStateTests`，验证 realtime 草稿和 interaction overlay 已经分层发布。

## 修改一：把 coordinator 的 surface state 从扁平渲染字段升级为三层 host 状态

### 修改前

- `HandDrawingCanvasSurfaceState` 直接混放：
  - `committedCanvas`
  - `realtimeDraft`
  - `lassoPathPoints`
  - `selectedStrokeBounds`
- 这样 `surface` 虽然在 phase 1 已经拿到了 committed / realtime 两类渲染语义，但 interaction overlay 仍然和 realtime draft 处在同一份扁平状态里，不利于 phase 2 的宿主拆分。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: HandDrawingCanvasSurfaceState / publishSurfaceState() / refreshCommittedImageAndPublishState(forceFullRender:)
// 功能说明: 修改前 coordinator 发布的是一份扁平 surface state，interaction overlay 还没有单独抽成 host 状态。
struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedCanvas: HandDrawingCommittedCanvasRenderOutput
    var realtimeDraft: HandDrawingRealtimeDraftRenderOutput
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

private func publishSurfaceState() {
    onSurfaceStateChange?(
        HandDrawingCanvasSurfaceState(
            paperSize: editorContext.paper.size,
            committedCanvas: committedCanvas,
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
    // ... 省略无关代码 ...
}
```

### 修改后

- 新增三份更细粒度的 host 状态：
  - `HandDrawingCommittedCanvasHostState`
  - `HandDrawingRealtimeDraftHostState`
  - `HandDrawingCanvasInteractionOverlayState`
- `HandDrawingCanvasSurfaceState` 现在只做总装，不再把 interaction overlay 的字段和 realtime draft 并排混放。
- `publishSurfaceState()` 会先拿到 `realtimeDraftOutput`，再分别组装 committed host、realtime host、interaction overlay。
- `refreshCommittedImageAndPublishState(...)` 也改名为 `refreshCommittedCanvasAndPublishState(...)`，让命名与 phase 1 引入的 committed backend 语义保持一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingCommittedCanvasHostState / HandDrawingRealtimeDraftHostState / HandDrawingCanvasInteractionOverlayState / HandDrawingCanvasSurfaceState / publishSurfaceState() / refreshCommittedCanvasAndPublishState(forceFullRender:)
// 功能说明: 修改后 coordinator 发布三层 host 状态，明确区分 committed、realtime draft 与 interaction overlay 三种显示责任。
struct HandDrawingCommittedCanvasHostState {
    var output: HandDrawingCommittedCanvasRenderOutput
}

struct HandDrawingRealtimeDraftHostState {
    var output: HandDrawingRealtimeDraftRenderOutput
}

struct HandDrawingCanvasInteractionOverlayState {
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedHost: HandDrawingCommittedCanvasHostState
    var realtimeDraftHost: HandDrawingRealtimeDraftHostState
    var interactionOverlay: HandDrawingCanvasInteractionOverlayState
}

private func publishSurfaceState() {
    let realtimeDraftOutput = realtimeBrushRenderer.render(
        packet: currentRealtimeDraftPacket
    )
    onSurfaceStateChange?(
        HandDrawingCanvasSurfaceState(
            paperSize: editorContext.paper.size,
            committedHost: HandDrawingCommittedCanvasHostState(
                output: committedCanvas
            ),
            realtimeDraftHost: HandDrawingRealtimeDraftHostState(
                output: realtimeDraftOutput
            ),
            interactionOverlay: HandDrawingCanvasInteractionOverlayState(
                lassoPathPoints: lassoToolController.points,
                selectedStrokeBounds: selectedStrokeBounds
            ),
        )
    )
}

private func refreshCommittedCanvasAndPublishState(
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

## 修改二：把 page view 从“image + 单 overlay”拆成三个独立宿主

### 修改前

- `HandDrawingCanvasPageView` 里只有两层显示结构：
  - `committedImageView`
  - `draftOverlayView`
- `draftOverlayView` 同时负责三件事：
  - 画 realtime `draftStroke`
  - 画 `selectedStrokeBounds`
  - 画 `lassoPath`
- 这意味着只要想替换 realtime draft backend，连 interaction overlay 也会被迫跟着一起重构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingCanvasPageView.init(frame:) / HandDrawingCanvasPageView.apply(state:) / HandDrawingCanvasDraftOverlayView.draw(_:)
// 功能说明: 修改前 committed image 与 realtime draft/interaction overlay 只分成两层，draft overlay 同时承担草稿和交互辅助绘制。
private let committedImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleToFill
    imageView.isUserInteractionEnabled = false
    return imageView
}()
private let draftOverlayView = HandDrawingCanvasDraftOverlayView()

override init(frame: CGRect) {
    super.init(frame: frame)
    // ... 省略无关代码 ...
    addSubview(committedImageView)
    addSubview(draftOverlayView)
    NSLayoutConstraint.activate([
        committedImageView.topAnchor.constraint(equalTo: topAnchor),
        committedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
        committedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        committedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        draftOverlayView.topAnchor.constraint(equalTo: topAnchor),
        draftOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
        draftOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
        draftOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
}

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

override func draw(_ rect: CGRect) {
    super.draw(rect)
    guard let context = UIGraphicsGetCurrentContext() else {
        return
    }
    context.saveGState()
    if let draftStroke {
        HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
    }
    drawSelectedStrokeBoundsIfNeeded(in: context)
    drawLassoPathIfNeeded(in: context)
    context.restoreGState()
}
```

### 修改后

- `HandDrawingCanvasPageView` 现在拆成三层宿主：
  - `HandDrawingCommittedCanvasHostView`
  - `HandDrawingRealtimeDraftHostView`
  - `HandDrawingCanvasInteractionOverlayView`
- realtime draft host 下再抽出 `HandDrawingRealtimeDraftRendererHosting` 协议，并给出默认 CPU fallback `HandDrawingCPURealtimeDraftRendererView`。
- interaction overlay 只负责：
  - `lassoPath`
  - `selectedStrokeBounds`
- realtime draft host 只负责 `draftStroke`，这样后续换 GPU host 时不会把 interaction overlay 一起带走。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCanvasPageView.init(frame:) / HandDrawingCanvasPageView.apply(state:) / HandDrawingCommittedCanvasHostView.apply(state:) / HandDrawingRealtimeDraftHostView.apply(state:) / HandDrawingCanvasInteractionOverlayView.apply(state:)
// 功能说明: 修改后将 committed、realtime draft、interaction overlay 拆成三个独立宿主；CPU realtime draft renderer 作为默认 host 挂载实现。
private let committedCanvasHostView = HandDrawingCommittedCanvasHostView()
private let realtimeDraftHostView = HandDrawingRealtimeDraftHostView()
private let interactionOverlayView = HandDrawingCanvasInteractionOverlayView()

override init(frame: CGRect) {
    super.init(frame: frame)
    // ... 省略无关代码 ...
    addSubview(committedCanvasHostView)
    addSubview(realtimeDraftHostView)
    addSubview(interactionOverlayView)
    NSLayoutConstraint.activate([
        committedCanvasHostView.topAnchor.constraint(equalTo: topAnchor),
        committedCanvasHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
        committedCanvasHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
        committedCanvasHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
        realtimeDraftHostView.topAnchor.constraint(equalTo: topAnchor),
        realtimeDraftHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
        realtimeDraftHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
        realtimeDraftHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
        interactionOverlayView.topAnchor.constraint(equalTo: topAnchor),
        interactionOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
        interactionOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
        interactionOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
}

func apply(state: HandDrawingCanvasSurfaceState) {
    committedCanvasHostView.apply(state: state.committedHost)
    realtimeDraftHostView.apply(state: state.realtimeDraftHost)
    interactionOverlayView.apply(state: state.interactionOverlay)
}

private final class HandDrawingCommittedCanvasHostView: UIView {
    // ... 省略 imageView 定义 ...
    func apply(state: HandDrawingCommittedCanvasHostState) {
        if let committedImage = state.output.image {
            imageView.image = UIImage(cgImage: committedImage)
        } else {
            imageView.image = nil
        }
    }
}

private protocol HandDrawingRealtimeDraftRendererHosting: AnyObject {
    var view: UIView { get }
    func apply(state: HandDrawingRealtimeDraftHostState)
}

private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting

    init(
        rendererHost: HandDrawingRealtimeDraftRendererHosting = HandDrawingCPURealtimeDraftRendererView()
    ) {
        self.rendererHost = rendererHost
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        installRendererHost(rendererHost)
    }

    func setRendererHost(_ rendererHost: HandDrawingRealtimeDraftRendererHosting) {
        guard rendererHost !== self.rendererHost else {
            return
        }
        self.rendererHost.view.removeFromSuperview()
        self.rendererHost = rendererHost
        installRendererHost(rendererHost)
    }

    func apply(state: HandDrawingRealtimeDraftHostState) {
        rendererHost.apply(state: state)
    }
}

private final class HandDrawingCPURealtimeDraftRendererView: UIView, HandDrawingRealtimeDraftRendererHosting {
    var view: UIView { self }
    var draftStroke: HandDrawingStroke? {
        didSet {
            setNeedsDisplay()
        }
    }

    func apply(state: HandDrawingRealtimeDraftHostState) {
        draftStroke = state.output.stroke
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        if let draftStroke {
            HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
        }
        context.restoreGState()
    }
}

private final class HandDrawingCanvasInteractionOverlayView: UIView {
    var lassoPathPoints: [CGPoint] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    var selectedStrokeBounds: CGRect? {
        didSet {
            setNeedsDisplay()
        }
    }

    func apply(state: HandDrawingCanvasInteractionOverlayState) {
        lassoPathPoints = state.lassoPathPoints
        selectedStrokeBounds = state.selectedStrokeBounds
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        drawSelectedStrokeBoundsIfNeeded(in: context)
        drawLassoPathIfNeeded(in: context)
        context.restoreGState()
    }
}
```

## 修改三：新增 phase 2 测试，锁住 host 分层边界

### 修改前

- `HandDrawingEditorCoordinatorTests.swift` 里已有刷子 preset 相关测试。
- 但还没有任何测试明确说明：
  - realtime draft host 和 interaction overlay 已经分开发布
  - `lasso` 行为应该只更新 interaction overlay，而不是写入 realtime draft host

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift（修改前）
// 函数名: HandDrawingEditorCoordinatorBrushPresetTests
// 功能说明: 修改前只有 brush preset 相关测试，还没有验证 phase 2 surface host 分层的新测试。
@MainActor
final class HandDrawingEditorCoordinatorBrushPresetTests: XCTestCase {
    func testHandDrawingEditorCoordinatorCommitsSelectedBrushPresetWithFullDynamics() throws {
        // ... 省略无关代码 ...
    }

    func testHandDrawingEditorCoordinatorRestoresCustomBrushPresetFromDocument() throws {
        // ... 省略无关代码 ...
    }
}
```

### 修改后

- 新增 `HandDrawingEditorCoordinatorSurfaceStateTests`。
- 新增两条关键测试：
  - `testHandDrawingEditorCoordinatorPublishesSeparatedCommittedAndRealtimeHostState()`
  - `testHandDrawingEditorCoordinatorKeepsInteractionOverlaySeparateFromRealtimeDraftHost()`
- 同时新增 `makeHandDrawingCoordinatorInputSample(...)`，简化输入样本构造。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: HandDrawingEditorCoordinatorSurfaceStateTests / makeHandDrawingCoordinatorInputSample(x:y:timestamp:)
// 功能说明: 修改后新增 phase 2 回归测试，验证 committed host、realtime draft host、interaction overlay 已经分层发布。
@MainActor
final class HandDrawingEditorCoordinatorSurfaceStateTests: XCTestCase {
    func testHandDrawingEditorCoordinatorPublishesSeparatedCommittedAndRealtimeHostState() throws {
        let document = HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "coordinator-surface-paper",
                size: CGSize(width: 120, height: 120)
            )
        )
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: document
            )
        )
        var latestSurfaceState: HandDrawingCanvasSurfaceState?
        coordinator.onSurfaceStateChange = { latestSurfaceState = $0 }

        coordinator.activate()

        let initialSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNotNil(initialSurfaceState.committedHost.output.image)
        XCTAssertNil(initialSurfaceState.realtimeDraftHost.output.stroke)
        XCTAssertTrue(initialSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNil(initialSurfaceState.interactionOverlay.selectedStrokeBounds)

        coordinator.handlePencilStrokeBegan(
            makeHandDrawingCoordinatorInputSample(
                x: 24,
                y: 30,
                timestamp: 0
            )
        )

        let activeDraftSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNotNil(activeDraftSurfaceState.committedHost.output.image)
        XCTAssertNotNil(activeDraftSurfaceState.realtimeDraftHost.output.stroke)
        XCTAssertTrue(activeDraftSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNil(activeDraftSurfaceState.interactionOverlay.selectedStrokeBounds)
    }

    func testHandDrawingEditorCoordinatorKeepsInteractionOverlaySeparateFromRealtimeDraftHost() throws {
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: makeHandDrawingTestDocument()
            )
        )
        var latestSurfaceState: HandDrawingCanvasSurfaceState?
        coordinator.onSurfaceStateChange = { latestSurfaceState = $0 }
        coordinator.activate()
        coordinator.selectTool(.lasso)

        coordinator.handlePencilStrokeBegan(
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 40,
                timestamp: 0
            )
        )
        coordinator.handlePencilStrokeMoved([
            makeHandDrawingCoordinatorInputSample(
                x: 110,
                y: 40,
                timestamp: 0.1
            ),
            makeHandDrawingCoordinatorInputSample(
                x: 110,
                y: 80,
                timestamp: 0.2
            ),
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 80,
                timestamp: 0.3
            )
        ])

        let activeLassoSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNil(activeLassoSurfaceState.realtimeDraftHost.output.stroke)
        XCTAssertEqual(activeLassoSurfaceState.interactionOverlay.lassoPathPoints.count, 4)
        XCTAssertNil(activeLassoSurfaceState.interactionOverlay.selectedStrokeBounds)

        coordinator.handlePencilStrokeEnded([
            makeHandDrawingCoordinatorInputSample(
                x: 10,
                y: 40,
                timestamp: 0.4
            )
        ])

        let selectedSurfaceState = try XCTUnwrap(latestSurfaceState)
        XCTAssertNil(selectedSurfaceState.realtimeDraftHost.output.stroke)
        XCTAssertTrue(selectedSurfaceState.interactionOverlay.lassoPathPoints.isEmpty)
        XCTAssertNotNil(selectedSurfaceState.interactionOverlay.selectedStrokeBounds)
    }
}

private func makeHandDrawingCoordinatorInputSample(
    x: CGFloat,
    y: CGFloat,
    timestamp: TimeInterval
) -> HandDrawingInputSample {
    HandDrawingInputSample(
        location: CGPoint(x: x, y: y),
        force: 0.8,
        timestamp: timestamp
    )
}
```

## 验证结果

- 已尝试执行 iOS Simulator 上的定点测试，但当前项目测试目标 `MyCanvas_Ver_0Tests` 不支持 `iphonesimulator` 平台，因此这两条新测试本次无法在 iPhone Simulator 上实际运行。
- 已执行 iOS Simulator `build`，确认 `surface host` 重构后的代码链路可以正常编译。
- 已检查本次修改文件的 lints，无新增问题。

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project /Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj -scheme MyCanvas_Ver_0 -destination "platform=iOS Simulator,id=DD672436-D01E-40AA-92E3-3FDACB01D5CE" -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorBrushPresetTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorSurfaceStateTests
# 功能说明: 尝试在 iOS Simulator 上验证 phase 2 新增的 coordinator surface state 测试。
xcodebuild: error: Failed to build project MyCanvas_Ver_0 with scheme MyCanvas_Ver_0.: Cannot test target “MyCanvas_Ver_0Tests” on “iPhone 17”: MyCanvas_Ver_0Tests does not support iPhone 17’s platform: com.apple.platform.iphonesimulator
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project /Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj -scheme MyCanvas_Ver_0 -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
# 功能说明: 验证 phase 2 surface host 重构后的 iOS Simulator 构建链路。
** BUILD SUCCEEDED **
```

## 与 phase 3 的边界

- 到 phase 2 为止，`surface` 的宿主结构已经拆成 committed / realtime / interaction 三层。
- 但 realtime draft host 当前仍只接收一整根 `draftStroke`，还没有进入 phase 3 的“增量 packet 发布”阶段。
- 因此下一阶段如果继续推进，重点应放在：
  - coordinator 增量产出 realtime packet
  - realtime backend 直接消费共享 brush math 产物
  - 继续保持 document / committed / preview 仍由 CPU truth 裁决
