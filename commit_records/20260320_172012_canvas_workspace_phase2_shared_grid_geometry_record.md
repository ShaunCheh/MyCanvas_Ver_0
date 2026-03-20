# 20260320_172012_canvas_workspace_phase2_shared_grid_geometry_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中把 `workspaceOverlay` 从“空占位 contract”升级为“真实 grid geometry 输出”。
  2. 让 shared renderer 统一生成 screen-space 的 `minorGridSegments` / `majorGridSegments`，为后续 viewport 绘制黑灰工作区网格提供直接输入。
  3. 明确网格锚定到 world-space 零点，不随 `board` 自动扩张重新相位。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - `macOS` / `iOS` viewport 对 `workspaceOverlay` 的消费接入
  - 白色 board surface 的实际 layer 绘制
  - 原始 gif diff
  - git commit / push

## 修改一：让 workspaceOverlay 输出真实网格线段，而不是空数组占位

### 修改前

- 阶段 1 里的 `workspaceOverlay` 只冻结了 contract，还没有真实生成网格几何。
- `makeWorkspaceOverlay(...)` 只回填 `boardSurfaceWorldRect`、`boardSurfaceScreenRect` 和步长参数。
- `minorGridSegments` / `majorGridSegments` 始终为空数组，因此后续 viewport 即使接入该 contract，也拿不到可绘制的网格线段。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeWorkspaceOverlay(...)
// 功能说明: 修改前 renderer 只把 board surface 几何和步长配置塞进 workspaceOverlay，网格线段仍为空数组，占位但不可直接渲染。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect
    // ... 省略 renderItems 未改动代码 ...

    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let boardOverlay: CanvasBoardRenderOverlay?
    if let boardState {
        let boardSurfaceWorldRect = boardState.worldRect.standardized
        let boardSurfaceScreenRect = camera
            .worldToViewport(boardSurfaceWorldRect)
            .standardized
        workspaceOverlay = makeWorkspaceOverlay(
            viewportBounds: camera.viewportBounds,
            boardSurfaceWorldRect: boardSurfaceWorldRect,
            boardSurfaceScreenRect: boardSurfaceScreenRect
        )
        boardOverlay = CanvasBoardRenderOverlay(
            worldRect: boardSurfaceWorldRect,
            screenRect: boardSurfaceScreenRect
        )
    } else {
        workspaceOverlay = nil
        boardOverlay = nil
    }

    // ... 省略 editOverlay / interactionOverlay 未改动代码 ...
}

private func makeWorkspaceOverlay(
    viewportBounds: CGRect,
    boardSurfaceWorldRect: CGRect,
    boardSurfaceScreenRect: CGRect
) -> CanvasWorkspaceRenderOverlay {
    // Phase 1 freezes the shared contract first; grid geometry lands next.
    CanvasWorkspaceRenderOverlay(
        viewportBounds: viewportBounds,
        boardSurfaceWorldRect: boardSurfaceWorldRect,
        boardSurfaceScreenRect: boardSurfaceScreenRect,
        minorGridStepWorld: Self.workspaceMinorGridStepWorld,
        majorGridLineEvery: Self.workspaceMajorGridLineEvery,
        minorGridSegments: [],
        majorGridSegments: []
    )
}
```

### 修改后

- `makeSnapshot(...)` 现在会把 `visibleWorldRect` 和 `camera` 一并传给 `makeWorkspaceOverlay(...)`。
- `makeWorkspaceOverlay(...)` 会先调用 `makeWorkspaceGridSegments(...)`，再把真实的 minor / major 线段写入 `workspaceOverlay`。
- 这样 shared 层已经能为 viewport 直接提供 screen-space 网格几何，不需要双端再各自重算一遍。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeWorkspaceOverlay(...)
// 功能说明: 修改后 renderer 在输出 workspaceOverlay 时同步生成真实网格线段，让后续 viewport 可以直接消费 shared 的 screen-space grid geometry。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect
    // ... 省略 renderItems 未改动代码 ...

    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let boardOverlay: CanvasBoardRenderOverlay?
    if let boardState {
        let boardSurfaceWorldRect = boardState.worldRect.standardized
        let boardSurfaceScreenRect = camera
            .worldToViewport(boardSurfaceWorldRect)
            .standardized
        workspaceOverlay = makeWorkspaceOverlay(
            visibleWorldRect: visibleWorldRect,
            camera: camera,
            viewportBounds: camera.viewportBounds,
            boardSurfaceWorldRect: boardSurfaceWorldRect,
            boardSurfaceScreenRect: boardSurfaceScreenRect
        )
        boardOverlay = CanvasBoardRenderOverlay(
            worldRect: boardSurfaceWorldRect,
            screenRect: boardSurfaceScreenRect
        )
    } else {
        workspaceOverlay = nil
        boardOverlay = nil
    }

    // ... 省略 editOverlay / interactionOverlay 未改动代码 ...
}

private func makeWorkspaceOverlay(
    visibleWorldRect: CGRect,
    camera: CanvasCamera,
    viewportBounds: CGRect,
    boardSurfaceWorldRect: CGRect,
    boardSurfaceScreenRect: CGRect
) -> CanvasWorkspaceRenderOverlay {
    let gridSegments = makeWorkspaceGridSegments(
        visibleWorldRect: visibleWorldRect,
        camera: camera,
        minorStepWorld: Self.workspaceMinorGridStepWorld,
        majorGridLineEvery: Self.workspaceMajorGridLineEvery
    )
    CanvasWorkspaceRenderOverlay(
        viewportBounds: viewportBounds,
        boardSurfaceWorldRect: boardSurfaceWorldRect,
        boardSurfaceScreenRect: boardSurfaceScreenRect,
        minorGridStepWorld: Self.workspaceMinorGridStepWorld,
        majorGridLineEvery: Self.workspaceMajorGridLineEvery,
        minorGridSegments: gridSegments.minor,
        majorGridSegments: gridSegments.major
    )
}
```

## 修改二：新增 world 锁定网格几何生成 helpers

### 修改前

- `CanvasRenderer` 里没有任何专门生成工作区网格线段的 helper。
- `makeWorkspaceOverlay(...)` 之后会直接进入 `makeEditOverlay(...)`，说明 shared renderer 还没有承担 grid geometry 的职责。
- 这时如果要画网格，只能让双端 viewport 各自从 `visibleWorldRect` 再算一遍。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeWorkspaceOverlay(...) / makeEditOverlay(...)
// 功能说明: 修改前 workspaceOverlay 生成逻辑结束后就直接进入 edit overlay 生成，shared 层没有任何 workspace grid helper。
private func makeWorkspaceOverlay(
    viewportBounds: CGRect,
    boardSurfaceWorldRect: CGRect,
    boardSurfaceScreenRect: CGRect
) -> CanvasWorkspaceRenderOverlay {
    // Phase 1 freezes the shared contract first; grid geometry lands next.
    CanvasWorkspaceRenderOverlay(
        viewportBounds: viewportBounds,
        boardSurfaceWorldRect: boardSurfaceWorldRect,
        boardSurfaceScreenRect: boardSurfaceScreenRect,
        minorGridStepWorld: Self.workspaceMinorGridStepWorld,
        majorGridLineEvery: Self.workspaceMajorGridLineEvery,
        minorGridSegments: [],
        majorGridSegments: []
    )
}

private func makeEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasEditRenderOverlay? {
    // ... 省略未改动代码 ...
}
```

### 修改后

- 新增 `WorkspaceGridSegments` 作为内部聚合结果，避免在多个 helper 间直接传递两个并行数组。
- 新增：
  - `makeWorkspaceGridSegments(...)`
  - `appendVerticalWorkspaceGridSegments(...)`
  - `appendHorizontalWorkspaceGridSegments(...)`
  - `workspaceGridIndexRange(...)`
- 这些 helper 负责：
  - 在 `visibleWorldRect` 内求出可见 grid index 范围
  - 基于 world-space 零点生成横向/纵向网格线
  - 按 `majorGridLineEvery` 区分主网格和次网格
  - 在边界计算中加入微小 `epsilon`，降低浮点边界抖动导致的漏线/重复线问题

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: WorkspaceGridSegments / makeWorkspaceGridSegments(...) / appendVerticalWorkspaceGridSegments(...) / appendHorizontalWorkspaceGridSegments(...) / workspaceGridIndexRange(...)
// 功能说明: 修改后 shared renderer 统一在 world-space 零点锚定网格，生成 screen-space major/minor line segments，并通过 epsilon 稳定可见边界上的索引计算。
private struct WorkspaceGridSegments {
    let minor: [CanvasWorkspaceGridLineSegment]
    let major: [CanvasWorkspaceGridLineSegment]
}

private static let workspaceGridIndexEpsilonFactor: CGFloat = 0.0001

private func makeWorkspaceGridSegments(
    visibleWorldRect: CGRect,
    camera: CanvasCamera,
    minorStepWorld: CGFloat,
    majorGridLineEvery: Int
) -> WorkspaceGridSegments {
    let standardizedVisibleWorldRect = visibleWorldRect.standardized
    let resolvedMinorStepWorld = max(minorStepWorld, 1)
    let resolvedMajorGridLineEvery = max(majorGridLineEvery, 1)
    guard
        standardizedVisibleWorldRect.width > 0,
        standardizedVisibleWorldRect.height > 0
    else {
        return WorkspaceGridSegments(minor: [], major: [])
    }

    // Keep the workspace grid anchored to world-space zero so board auto
    // expansion changes the white surface bounds without rephasing the grid.
    var minorSegments: [CanvasWorkspaceGridLineSegment] = []
    var majorSegments: [CanvasWorkspaceGridLineSegment] = []
    appendVerticalWorkspaceGridSegments(
        visibleWorldRect: standardizedVisibleWorldRect,
        camera: camera,
        minorStepWorld: resolvedMinorStepWorld,
        majorGridLineEvery: resolvedMajorGridLineEvery,
        minorSegments: &minorSegments,
        majorSegments: &majorSegments
    )
    appendHorizontalWorkspaceGridSegments(
        visibleWorldRect: standardizedVisibleWorldRect,
        camera: camera,
        minorStepWorld: resolvedMinorStepWorld,
        majorGridLineEvery: resolvedMajorGridLineEvery,
        minorSegments: &minorSegments,
        majorSegments: &majorSegments
    )
    return WorkspaceGridSegments(
        minor: minorSegments,
        major: majorSegments
    )
}

private func appendVerticalWorkspaceGridSegments(
    visibleWorldRect: CGRect,
    camera: CanvasCamera,
    minorStepWorld: CGFloat,
    majorGridLineEvery: Int,
    minorSegments: inout [CanvasWorkspaceGridLineSegment],
    majorSegments: inout [CanvasWorkspaceGridLineSegment]
) {
    guard let xIndexRange = workspaceGridIndexRange(
        minimumWorld: visibleWorldRect.minX,
        maximumWorld: visibleWorldRect.maxX,
        stepWorld: minorStepWorld
    ) else {
        return
    }

    for xIndex in xIndexRange {
        let x = CGFloat(xIndex) * minorStepWorld
        let segment = CanvasWorkspaceGridLineSegment(
            start: camera.worldToViewport(
                CGPoint(x: x, y: visibleWorldRect.minY)
            ),
            end: camera.worldToViewport(
                CGPoint(x: x, y: visibleWorldRect.maxY)
            )
        )
        if xIndex.isMultiple(of: majorGridLineEvery) {
            majorSegments.append(segment)
        } else {
            minorSegments.append(segment)
        }
    }
}

private func workspaceGridIndexRange(
    minimumWorld: CGFloat,
    maximumWorld: CGFloat,
    stepWorld: CGFloat
) -> ClosedRange<Int>? {
    guard stepWorld > 0 else {
        return nil
    }

    let epsilon = stepWorld * Self.workspaceGridIndexEpsilonFactor
    let startIndex = Int(
        ceil((minimumWorld - epsilon) / stepWorld)
    )
    let endIndex = Int(
        floor((maximumWorld + epsilon) / stepWorld)
    )
    guard startIndex <= endIndex else {
        return nil
    }

    return startIndex...endIndex
}
```

## 阶段结果

- `workspaceOverlay` 现在已经能真实输出可见区域内的 `minorGridSegments` 和 `majorGridSegments`。
- 这些线段已经是 screen-space 坐标，后续 viewport 只需要把它们转成 path 并上色，不需要再重复 world -> screen 变换。
- 网格锚定在 world-space 零点，因此：
  - 平移时网格跟着世界坐标稳定移动
  - 缩放时网格密度跟随 `camera` 变化
  - `board` 自动扩张只会改变白色 board surface 的边界，不会让网格重新对齐

## 验证情况

- 已对 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 运行诊断检查，没有新增 lint 问题。
- 已通过 `swift -e` 验证负数索引下 `isMultiple(of:)` 的行为符合预期，主网格线在 world-space 原点两侧都能正确分类。
- 本次没有附带完整 `xcodebuild` 构建结果。

## 下一阶段输入

- 下一阶段将开始在 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 接入 `workspaceOverlay`，新增网格 layer 和白色 board surface layer，并移除旧的橙色虚线 board highlight 渲染路径。
