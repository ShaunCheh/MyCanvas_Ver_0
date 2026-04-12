# 20260412_224510_macos_toolbar_hidden_geometry_rootfix_record

## 记录说明

本记录基于当前工作区里“刚刚这次 macOS toolbar hidden geometry rootfix”的实际 `git diff`、`git status` 与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 4 个业务代码文件：

- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift`

写入本记录前的代码状态依据：

- `git diff --stat -- <3 个已跟踪源码文件>` 统计为：`3 files changed, 223 insertions(+), 17 deletions(-)`。
- `git status --short -- <4 个业务文件>` 显示：
  - `M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `?? MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift`
- 本记录文件是随后新增的说明材料，不属于上述业务代码改动本身。

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 运行时人工复测录像

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 提取这次 macOS toolbar hidden geometry rootfix 的真实变更范围与当前工作区状态。
git status --short -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift" \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift"

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift" \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift" \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift"
```

## 问题背景

这次修改对应的是同一条根因链上的 macOS toolbar 首次入场异常：

1. 阅读模式下，`CanvasToolbarStateBuilder.mainToolbarState(...)` 会返回空 toolbar。
2. 共享 `CanvasToolbarPlacementPass.resolve(...)` 在空测量尺寸下会得到 `toolbarFrame = .zero`。
3. macOS 控制器里的 `applyToolbarFrame(_:)` 会把 `.zero` 通过 `CanvasChromeLayoutGeometry.sanitizedRect(...)` 直接丢弃，因此不会把隐藏态 frame 真正回写到 `toolbarHostView`。
4. 结果就是 `toolbarHostView` 会继续保留 bootstrap 或 stale frame；第一次 `toEditing` 时，首帧会泄漏这个残留 frame，视觉上像 toolbar 还是从左边出来。

因此，这次不是去改单独的动画方向，而是把“空 toolbar 的 steady hidden geometry”和“transition entering / exiting 使用的 hidden geometry”统一成同一套共享 contract。

## 修改一：在 `CanvasToolbarTransitionGeometry.swift` 中新增 hidden geometry contract

### 修改前

修改前的共享几何只有 `collapsedFrame(from:)` 和 `offscreenFrame(from:safeBounds:)`。它假设调用方已经拿到了一个合法的 collapsed frame；如果 steady toolbar 为空，就没有对等的 hidden frame contract。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: offscreenFrame(from:safeBounds:)
// 功能说明: 修改前只能把一个既有 collapsed frame 推到屏外，无法为“空 toolbar / 没有 visibleFrame”生成合法 hidden frame。
static func offscreenFrame(
    from collapsedFrame: CGRect,
    safeBounds: CGRect
) -> CGRect {
    let baseFrame = sanitizedRectOrFallback(
        collapsedFrame,
        fallbackOrigin: finiteOrigin(from: collapsedFrame.origin),
        fallbackSize: CGSize(
            width: collapsedSquareEdge(from: collapsedFrame),
            height: collapsedSquareEdge(from: collapsedFrame)
        )
    )
    let safeBoundsMaxX = CanvasChromeLayoutGeometry
        .sanitizedRect(safeBounds)?
        .maxX ?? baseFrame.maxX
    return CGRect(
        x: max(baseFrame.minX, safeBoundsMaxX),
        y: baseFrame.minY,
        width: baseFrame.width,
        height: baseFrame.height
    ).standardized
}
```

### 修改后

修改后新增 `hiddenFrame(...)`，把“优先复用 visible frame 反解 collapsed frame”和“visible frame 缺失时自己求一个 fallback collapsed frame”统一封装进共享层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: hiddenFrame(for:visibleFrame:safeBounds:scale:baseChromeBlockers:solver:configuration:)
// 功能说明: 修改后共享层可以直接为 empty toolbar 或正常 toolbar 生成同语义的 hidden/offscreen frame，不再要求控制器先手写一份隐藏态几何。
static func hiddenFrame(
    for placement: CanvasToolbarPlacement,
    visibleFrame: CGRect?,
    safeBounds: CGRect,
    scale: CGFloat,
    baseChromeBlockers: [CanvasChromeBlocker],
    solver: CanvasToolbarPlacementSolver = CanvasToolbarPlacementSolver(),
    configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
) -> CGRect {
    let hiddenCollapsedFrame: CGRect
    if let visibleFrame,
       let sanitizedVisibleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
           visibleFrame
       )
    {
        hiddenCollapsedFrame = collapsedFrame(from: sanitizedVisibleFrame)
    } else {
        hiddenCollapsedFrame = resolvedFallbackCollapsedFrame(
            for: placement,
            safeBounds: safeBounds,
            scale: scale,
            baseChromeBlockers: baseChromeBlockers,
            solver: solver,
            configuration: configuration
        )
    }

    return offscreenFrame(
        from: hiddenCollapsedFrame,
        safeBounds: safeBounds
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: resolvedFallbackCollapsedFrame(for:safeBounds:scale:baseChromeBlockers:solver:configuration:) / fallbackCollapsedFrame(for:size:safeBounds:configuration:)
// 功能说明: 修改后当 visible frame 缺失时，共享几何会先以 bootstrap-size 的 collapsed square 走一次 placement 求解；求解失败时再回退到纯 safeBounds + placement 的兜底 frame。
private static func resolvedFallbackCollapsedFrame(
    for placement: CanvasToolbarPlacement,
    safeBounds: CGRect,
    scale: CGFloat,
    baseChromeBlockers: [CanvasChromeBlocker],
    solver: CanvasToolbarPlacementSolver,
    configuration: CanvasToolbarPlacementConfiguration
) -> CGRect {
    let collapsedEdge = collapsedSquareEdge(from: .zero)
    let collapsedSize = CGSize(
        width: collapsedEdge,
        height: collapsedEdge
    )
    let fallbackFrame = fallbackCollapsedFrame(
        for: placement,
        size: collapsedSize,
        safeBounds: safeBounds,
        configuration: configuration
    )
    let layoutContext = CanvasChromeLayoutContext(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: placement,
        toolbarMeasuredSize: collapsedSize,
        chromeBlockers: baseChromeBlockers
    )

    guard let resolvedFrame = solver.resolveFrame(
        in: layoutContext,
        configuration: configuration
    ).flatMap({
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            $0,
            scale: scale
        )
    }) else {
        return fallbackFrame
    }

    return sanitizedRectOrFallback(
        resolvedFrame,
        fallbackOrigin: fallbackFrame.origin,
        fallbackSize: fallbackFrame.size
    )
}
```

### 修改意图

这一步把“空 toolbar 不再退化成 `.zero + no-op`”正式变成共享 contract：

- 有 visible toolbar 时：hidden frame 继续沿用原来的 `visible -> collapsed -> offscreen` 语义。
- 没有 visible toolbar 时：共享层自己根据 placement / safeBounds / blockers 反解一个合法 hidden frame。
- 这样 steady layout 和 transition 都能消费同一套 hidden geometry，不再各自猜一套。

## 修改二：让 `CanvasToolbarPlacementPass.swift` 同时返回 visible/hidden 两套 frame

### 修改前

修改前的 placement pass 只返回 `toolbarFrame`。一旦 `toolbarMeasuredSize == .zero`，结果就只剩 `.zero`，上层没有第二套隐藏态几何可用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift
// 函数名: CanvasToolbarPlacementPassResult / resolve(...)
// 功能说明: 修改前 placement pass 只产出 toolbarFrame，空 toolbar 只能把 .zero 往上传。
struct CanvasToolbarPlacementPassResult: Hashable, Sendable {
    var toolbarFrame: CGRect
    var chromeLayoutContext: CanvasChromeLayoutContext
}

let toolbarFrame = solver.resolveFrame(
    in: toolbarPlacementContext,
    configuration: configuration
).flatMap { frame in
    CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
        frame,
        scale: scale
    )
} ?? .zero

return CanvasToolbarPlacementPassResult(
    toolbarFrame: toolbarFrame,
    chromeLayoutContext: makeChromeLayoutContext(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: toolbarPreferredPlacement,
        toolbarMeasuredSize: toolbarMeasuredSize,
        chromeBlockers: chromeBlockers
    )
)
```

### 修改后

修改后 `CanvasToolbarPlacementPassResult` 新增 `hiddenToolbarFrame`，并在 `resolve(...)` 内部统一调用共享 `hiddenFrame(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift
// 函数名: CanvasToolbarPlacementPassResult / resolve(...)
// 功能说明: 修改后 placement pass 在同一次求解中同时产出可见 toolbarFrame 和隐藏态 hiddenToolbarFrame，供 steady layout 与 transition 共用。
struct CanvasToolbarPlacementPassResult: Hashable, Sendable {
    var toolbarFrame: CGRect
    var hiddenToolbarFrame: CGRect
    var chromeLayoutContext: CanvasChromeLayoutContext
}

let toolbarFrame = solver.resolveFrame(
    in: toolbarPlacementContext,
    configuration: configuration
).flatMap { frame in
    CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
        frame,
        scale: scale
    )
} ?? .zero
let hiddenToolbarFrame = CanvasToolbarTransitionGeometry.hiddenFrame(
    for: toolbarPreferredPlacement,
    visibleFrame: CanvasChromeLayoutGeometry.sanitizedRect(toolbarFrame),
    safeBounds: safeBounds,
    scale: scale,
    baseChromeBlockers: baseChromeBlockers,
    solver: solver,
    configuration: configuration
)

return CanvasToolbarPlacementPassResult(
    toolbarFrame: toolbarFrame,
    hiddenToolbarFrame: hiddenToolbarFrame,
    chromeLayoutContext: makeChromeLayoutContext(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: toolbarPreferredPlacement,
        toolbarMeasuredSize: toolbarMeasuredSize,
        chromeBlockers: chromeBlockers
    )
)
```

### 修改意图

这样上层控制器不需要再自己拼 hidden frame：

- steady-state layout 可以直接取 `hiddenToolbarFrame`
- transition context 也可以直接取 `hiddenToolbarFrame` 背后的同源几何
- 共享层正式成为“visible / hidden 两套 frame contract”的唯一真源

## 修改三：`macOSViewController.swift` 的 steady layout 在空 toolbar 时回写 hiddenToolbarFrame

### 修改前

修改前的 macOS overlay layout 始终只回写 `toolbarPlacementResult.toolbarFrame`；而 `applyToolbarFrame(_:)` 会直接忽略 `.zero`，这正是阅读态保留 bootstrap/stale frame 的根因之一。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass() / applyToolbarFrame(_:)
// 功能说明: 修改前 overlay layout 无论 steady toolbar 是否为空，都只把 toolbarFrame 往下传；当 toolbarFrame == .zero 时，applyToolbarFrame 会直接 return。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let safeBounds = toolbarLayoutSafeBounds()
    let baseChromeBlockers = baseChromeBlockersForToolbarLayout()
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        baseChromeBlockers: baseChromeBlockers,
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(toolbarPlacementResult.toolbarFrame)
    // ...
}

private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    guard let sanitizedToolbarFrame = CanvasChromeLayoutGeometry.sanitizedRect(
        toolbarFrame
    ) else {
        return
    }

    if toolbarHostView.frame != sanitizedToolbarFrame {
        toolbarHostView.frame = sanitizedToolbarFrame
    }
}
```

### 修改后

修改后先用 `makeToolbarState()` 拿到 steady toolbar 状态；如果 item 为空，就主动回写 `hiddenToolbarFrame`，不再把 host 留在 bootstrap 或 stale frame。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performOverlayLayoutPass()
// 功能说明: 修改后 steady overlay layout 会先判断当前 toolbarState 是否为空；空 toolbar 时主动把 host 落到 hiddenToolbarFrame，而不是继续保留旧 frame。
private func performOverlayLayoutPass() -> CanvasChromeLayoutContext {
    let safeBounds = toolbarLayoutSafeBounds()
    let baseChromeBlockers = baseChromeBlockersForToolbarLayout()
    let toolbarState = makeToolbarState()
    let toolbarPlacementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: toolbarState.placement,
        toolbarMeasuredSize: measuredToolbarHostSize(for: toolbarState),
        baseChromeBlockers: baseChromeBlockers,
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    applyToolbarFrame(
        toolbarState.items.isEmpty
            ? toolbarPlacementResult.hiddenToolbarFrame
            : toolbarPlacementResult.toolbarFrame
    )
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resolvedSteadyToolbarFrame(for:)
// 功能说明: 修改后 steady toolbar frame 的求解结果也和 overlay layout 使用同一来源；空 toolbar 不再把 .zero 当 steady frame。
private func resolvedSteadyToolbarFrame(
    for state: CanvasToolbarState
) -> CGRect {
    let placementResult = CanvasToolbarPlacementPass.resolve(
        safeBounds: toolbarLayoutSafeBounds(),
        toolbarPreferredPlacement: state.placement,
        toolbarMeasuredSize: measuredToolbarHostSize(for: state),
        baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
        scale: toolbarPlacementScale(),
        solver: toolbarPlacementSolver
    )
    let steadyFrame = state.items.isEmpty
        ? placementResult.hiddenToolbarFrame
        : placementResult.toolbarFrame

    return normalizedToolbarFrame(
        steadyFrame,
        fallback: steadyFrame
    )
}
```

### 修改意图

这一步把阅读态 steady frame 真正落到了合法的右侧 hidden frame 上：

- 空 toolbar 不再依赖 `.zero`
- `toolbarHostView.frame` 不再偷偷保留 `{0,0,68,68}` 的 bootstrap frame
- 后续第一次 `toEditing` 时，首帧就不会再夹带左侧脏状态

## 修改四：`macOSViewController.swift` 的 transition 起点改为复用同一个 hiddenFrame contract

### 修改前

修改前 `prepareToolbarTransitionContext(direction:)` 里的 `offscreenFrame` 仍然直接由 `collapsedFrame + safeBounds` 推导，steady hidden state 和 transition hidden state 虽然看起来接近，但并没有被强制绑定到同一个 contract。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改前 toReading / toEditing 的 offscreenFrame 仍然直接调用 offscreenFrame(from:safeBounds:)，没有显式复用 steady hidden geometry contract。
let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
    from: visibleFrame
)
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds()
)
```

### 修改后

修改后 `toReading` / `toEditing` 两条路径统一改为调用 `CanvasToolbarTransitionGeometry.hiddenFrame(...)`，让 transition entering/exiting 和 steady hidden state 使用同一个来源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后 transition context 的 offscreenFrame 不再自己拼，而是统一复用共享 hiddenFrame contract，确保阅读态稳态与 entering/exiting 起点完全同源。
let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
    from: visibleFrame
)
let offscreenFrame = CanvasToolbarTransitionGeometry.hiddenFrame(
    for: visibleState.placement,
    visibleFrame: visibleFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    scale: toolbarPlacementScale(),
    baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
    solver: toolbarPlacementSolver
)
```

### 修改意图

这一步解决的是“steady hidden state”和“transition hidden state”不同源的问题：

- `toEditing` 的 entering 起点现在和阅读态 steady hidden frame 完全一致
- `toReading` 的收口终点也回到了同一个 hidden frame
- 首开、热切换、中断重基线都使用同一条隐藏态几何链

## 修改五：新增聚焦测试锁住 trailing hidden frame contract

### 修改前

修改前仓库里没有针对 `CanvasToolbarPlacementPass.hiddenToolbarFrame` 的聚焦测试，无法直接证明：

- 空 toolbar 时，trailing hidden frame 仍然会稳定落到右侧屏外
- 有 visible toolbar 时，hidden frame 会沿用相同的 `minY` / `width` 语义

### 修改后

新增 `MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift`，分别覆盖 empty-toolbar 和 visible-toolbar 两种 contract。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift
// 函数名: testResolveReturnsTrailingHiddenFrameForEmptyToolbar() / testResolveDerivesTrailingHiddenFrameFromVisibleToolbarFrame()
// 功能说明: 修改后测试直接锁住 trailing hidden frame 的几何语义，确保空 toolbar 不会再退回左上角 bootstrap 区域。
@MainActor
final class CanvasToolbarPlacementPassTests: XCTestCase {
    func testResolveReturnsTrailingHiddenFrameForEmptyToolbar() {
        let safeBounds = CGRect(x: 0, y: 0, width: 640, height: 420)
        let result = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: CanvasToolbarPlacement(
                preferredEdge: .trailing
            ),
            toolbarMeasuredSize: .zero,
            baseChromeBlockers: makeToolbarPlacementTestChromeBlockers(),
            scale: 2
        )

        XCTAssertEqual(result.toolbarFrame, .zero)
        XCTAssertEqual(result.hiddenToolbarFrame.minX, safeBounds.maxX)
        XCTAssertEqual(
            result.hiddenToolbarFrame.size,
            CanvasToolbarMeasurement.measuredContentSize(
                forMeasuredStackSize: CGSize(
                    width: CanvasToolbarChromeMetrics.buttonEdge,
                    height: CanvasToolbarChromeMetrics.buttonEdge
                )
            )
        )
    }

    func testResolveDerivesTrailingHiddenFrameFromVisibleToolbarFrame() throws {
        let safeBounds = CGRect(x: 0, y: 0, width: 640, height: 420)
        let result = CanvasToolbarPlacementPass.resolve(
            safeBounds: safeBounds,
            toolbarPreferredPlacement: CanvasToolbarPlacement(
                preferredEdge: .trailing
            ),
            toolbarMeasuredSize: makeToolbarPlacementTestVerticalToolbarSize(
                buttonCount: 6
            ),
            baseChromeBlockers: makeToolbarPlacementTestChromeBlockers(),
            scale: 2
        )

        let visibleFrame = try XCTUnwrap(
            CanvasChromeLayoutGeometry.sanitizedRect(result.toolbarFrame)
        )

        XCTAssertEqual(result.hiddenToolbarFrame.minX, safeBounds.maxX)
        XCTAssertEqual(result.hiddenToolbarFrame.minY, visibleFrame.minY)
        XCTAssertEqual(result.hiddenToolbarFrame.width, visibleFrame.width)
        XCTAssertEqual(result.hiddenToolbarFrame.height, visibleFrame.width)
    }
}
```

## 验证

已完成：

- `ReadLints`：本次修改文件无新增 lints。
- macOS 构建验证：`BUILD SUCCEEDED`。

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 对这次 macOS toolbar hidden geometry rootfix 执行 macOS 目标构建校验，确认共享几何 contract 与控制器接线没有破坏工程编译。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-rootfix-build" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

已尝试但未完成：

- 定向测试命令本身没有跑到新增测试断言阶段，而是被仓库里已有的无关测试编译错误阻塞：
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - 现有错误为 `BoardRuntimeState` 仍在使用旧的 `updatedAt` 参数，缺少 `contentUpdatedAt` / `viewStateUpdatedAt`
  - 这不是本次 toolbar rootfix 引入的问题

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 尝试只跑本次新增的 toolbar placement pass 聚焦测试；实际被现有无关测试编译错误提前阻塞。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-rootfix-tests" \
  test
```

## 修改影响

这次修改把原本散落在 macOS 控制器里的“空 toolbar 处理空洞”收敛成了共享 contract：

- 空 toolbar 不再退化成 `.zero + no-op`
- 阅读态 steady frame 会明确停在合法的右侧 hidden frame
- `toEditing` / `toReading` 的 offscreen 起止点与 steady hidden state 共用同一来源
- 首次开板从阅读态切换到编辑态时，toolbar 不再因为 bootstrap/stale frame 泄漏而看起来从左边出来

## 补充说明

本记录只覆盖这次 `macOS toolbar hidden geometry rootfix` 的真实代码改动，不重复展开此前的 `macOS chrome root fix`、`toolbar bootstrap constraint fix`、`toolbar frame sanitize guard fix` 等历史记录内容。
