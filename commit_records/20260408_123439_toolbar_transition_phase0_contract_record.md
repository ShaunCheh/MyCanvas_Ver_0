# 20260408_123439_toolbar_transition_phase0_contract_record

## 记录范围

- 记录内容：
  1. 为工具栏模式切换实现 `Phase 0` 共享契约，新增统一的过渡方向、阶段、配置、快照、几何 frame 集合、上下文、presentation、runtime 数据结构。
  2. 为工具栏模式切换实现 `Phase 0` 共享几何 helper，把“完整可见 frame -> 顶部固定正方形 -> 右侧离屏”和阶段性 `frame / alpha / scale` 映射收口到共享纯函数。
  3. 保持本次改动只停留在共享层，不改 iOS/macOS 控制器和 Toolbar Host，为后续 `Phase 1` 到 `Phase 4` 提供稳定消费边界。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
- 当前 changes 依据：
  - `git status --short` 仅显示两份新增未跟踪文件：`CanvasToolbarTransitionState.swift`、`CanvasToolbarTransitionGeometry.swift`。
  - 结合 `git diff --no-index -- /dev/null <path>` 可确认两份文件都是全量新增，不包含对既有文件的改写。
- 本记录不包含：
  - `Phase 1` 的 iOS/macOS Toolbar Host 结构改造
  - `Phase 2` / `Phase 3` 的控制器动画编排
  - `Phase 4` 的布局竞争与 reconcile 收口
  - git commit / push

## 修改一：新增共享过渡契约文件

### 修改前

- 项目中还没有工具栏模式切换的共享过渡契约源码文件。
- 如果直接进入后续 `Phase 1` / `Phase 2` / `Phase 3`，iOS Host、macOS Host、双端控制器很容易各自临时拼装 `Context / Frames / Presentation / Runtime`，导致阶段之间不同步。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionState.swift
// 函数名: 无（顶层过渡契约类型定义尚不存在）
// 功能说明: 修改前项目中没有这个文件；工具栏模式切换的方向、阶段、配置、快照、上下文、presentation、runtime 还未形成统一共享契约。
```

### 修改后

- 新增 `CanvasToolbarTransitionState.swift`，把计划里的共享 contract 正式落到源码里。
- 统一冻结了：
  - 方向：`toReading` / `toEditing`
  - 阶段：`steadyVisible` / `collapsing` / `exiting` / `hidden` / `entering` / `expanding`
  - 配置：`collapseDuration` / `slideDuration` / `minimumContentScale`
  - 数据载体：`Snapshot / Frames / Context / Presentation / Runtime`
- 同时把计划中的默认参数直接落成代码默认值：
  - `collapseDuration = 0.18`
  - `slideDuration = 0.14`
  - `minimumContentScale = 0.78`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionState.swift
// 函数名: 无（顶层过渡契约类型定义）
// 功能说明: 修改后新增工具栏模式切换 Phase 0 的统一共享 contract，后续 Host 和双端控制器都必须消费这套结构，而不是再各自定义本地过渡模型。
enum CanvasToolbarTransitionDirection: Hashable, Sendable {
    case toReading
    case toEditing
}

enum CanvasToolbarTransitionStage: Hashable, Sendable {
    case steadyVisible
    case collapsing(progress: CGFloat)
    case exiting(progress: CGFloat)
    case hidden
    case entering(progress: CGFloat)
    case expanding(progress: CGFloat)
}

struct CanvasToolbarTransitionConfiguration: Hashable, Sendable {
    var collapseDuration: TimeInterval
    var slideDuration: TimeInterval
    var minimumContentScale: CGFloat

    init(
        collapseDuration: TimeInterval = 0.18,
        slideDuration: TimeInterval = 0.14,
        minimumContentScale: CGFloat = 0.78
    ) {
        self.collapseDuration = max(collapseDuration, 0)
        self.slideDuration = max(slideDuration, 0)
        self.minimumContentScale = min(
            max(minimumContentScale, 0),
            1
        )
    }
}

struct CanvasToolbarTransitionSnapshot: Hashable, Sendable {
    var state: CanvasToolbarState
    var frame: CGRect
}

struct CanvasToolbarTransitionFrames: Hashable, Sendable {
    var visibleFrame: CGRect
    var collapsedFrame: CGRect
    var offscreenFrame: CGRect
}

// ... 同文件继续定义 Context / Presentation / Runtime，统一承载后续阶段所需的共享过渡状态 ...
```

## 修改二：新增共享几何与 presentation 纯函数 helper

### 修改前

- 项目中还没有一个共享入口来表达：
  - 如何从完整可见工具栏收拢到“顶部固定、底部上升”的正方形
  - 如何从正方形继续移动到右侧离屏位置
  - 如何把阶段性 `progress` 映射成 `frame / alpha / scale / keepsHostVisible / isInteractive`
- 如果直接在控制器里各自实现这些规则，后续双端很容易出现：
  - iOS 用一套几何
  - macOS 用另一套几何
  - Host 再额外发明一套 presentation 规则

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: collapsedFrame(from:) / offscreenFrame(from:safeBounds:) / presentation(for:context:)
// 功能说明: 修改前项目中没有这个文件；“正方形收拢”“右侧离屏”“阶段性 frame/alpha/scale 映射”都还没有共享纯函数入口。
```

### 修改后

- 新增 `CanvasToolbarTransitionGeometry.swift`，把几何与视觉过渡映射统一收口到共享纯函数。
- 这次实际落下的核心规则有三组：
  1. `collapsedFrame(from:)`
     - 直接以 `visibleFrame.minX/minY` 为起点
     - 用 `visibleFrame.width` 作为收拢后正方形边长
     - 因而顶部保持不变，底部向上收拢
  2. `offscreenFrame(from:safeBounds:)`
     - 保持与正方形相同的尺寸和 `minY`
     - 仅沿 X 方向移动到 `safeBounds.maxX` 之外
  3. `presentation(for:context:)`
     - 统一计算各阶段的 `frame / itemStates / alpha / scale / keepsHostVisible / isInteractive`
- 同时补了 fallback 逻辑：
  - 当 `visibleFrame` 或传入 frame 不合法时，退回到 `CanvasToolbarMeasurement + CanvasToolbarChromeMetrics` 推导正方形边长
  - 保证 `Phase 0` 先把共享几何 contract 固化下来

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: collapsedFrame(from:) / offscreenFrame(from:safeBounds:)
// 功能说明: 修改后统一定义“完整工具栏 -> 顶部固定正方形 -> 右侧离屏”的共享几何规则。
enum CanvasToolbarTransitionGeometry {
    static func collapsedFrame(from visibleFrame: CGRect) -> CGRect {
        let origin = finiteOrigin(from: visibleFrame.origin)
        let edge = collapsedSquareEdge(from: visibleFrame)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: edge,
            height: edge
        ).standardized
    }

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
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: presentation(for:context:)
// 功能说明: 修改后统一把阶段 progress 映射为真实展示态；收拢阶段负责“frame 收拢 + alpha 变淡 + scale 变小”，离屏阶段负责“正方形右移出屏”。
static func presentation(
    for stage: CanvasToolbarTransitionStage,
    context: CanvasToolbarTransitionContext
) -> CanvasToolbarTransitionPresentation {
    let visibleState = context.visibleSnapshot.state
    let frames = normalizedFrames(from: context)
    let minimumScale = context.configuration.minimumContentScale

    switch stage {
    case .steadyVisible:
        return CanvasToolbarTransitionPresentation(
            frame: frames.visibleFrame,
            itemStates: visibleState.items,
            showsBackground: visibleState.showsBackground,
            contentAlpha: 1,
            contentScale: 1,
            keepsHostVisible: true,
            isInteractive: true
        )

    case let .collapsing(progress):
        let t = clamped(progress)
        return CanvasToolbarTransitionPresentation(
            frame: interpolatedRect(
                from: frames.visibleFrame,
                to: frames.collapsedFrame,
                progress: t
            ),
            itemStates: visibleState.items,
            showsBackground: visibleState.showsBackground,
            contentAlpha: interpolatedValue(from: 1, to: 0, progress: t),
            contentScale: interpolatedValue(from: 1, to: minimumScale, progress: t),
            keepsHostVisible: true,
            isInteractive: false
        )

    case let .exiting(progress):
        let t = clamped(progress)
        return CanvasToolbarTransitionPresentation(
            frame: interpolatedRect(
                from: frames.collapsedFrame,
                to: frames.offscreenFrame,
                progress: t
            ),
            itemStates: visibleState.items,
            showsBackground: visibleState.showsBackground,
            contentAlpha: 0,
            contentScale: minimumScale,
            keepsHostVisible: true,
            isInteractive: false
        )

    // ... 同文件继续定义 hidden / entering / expanding 分支，保证反向进入编辑模式时可完整倒放 ...
    }
}
```

## 修改三：本次变更边界保持在共享层

### 修改前

- 计划要求 `Phase 0` 只做共享 contract 冻结，不应该提前碰 Host 和控制器。
- 如果这一阶段就去修改 iOS/macOS 控制器或 Toolbar Host，会打破计划里 `Phase 0 -> Phase 1 -> Phase 2/3` 的承接边界。

### 修改后

- 结合当前 `git status --short` 与本次新增文件内容，可以确认：
  - 只有两份共享层新文件
  - 没有任何既有控制器、Host、Builder、Placement 代码被改写
- 这意味着当前代码状态仍然满足计划中的 `Phase 0` 边界：
  - 先冻结共享契约
  - 后续 `Phase 1` 再接 Host
  - 再由 `Phase 2/3` 接控制器

## 验证情况

- `ReadLints` 检查新增共享文件，无 linter 报错。
- 已执行构建校验：
  - `xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO`
  - 结果：构建通过。

## 当前结论

- 本次改动如实对应 `Phase 0`：
  - 共享过渡数据结构已落地
  - 共享几何与 presentation 纯函数已落地
  - 现有控制器与 Host 尚未接入，界面行为暂时不变
- 从当前 changes 看，这是一组干净的共享层新增改动，适合作为后续 `Phase 1` 的基础。
