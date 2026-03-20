# 20260320_170711_canvas_workspace_phase1_shared_render_contract_record

## 记录范围

- 记录内容：
  1. 在 shared snapshot 中新增 `workspaceOverlay` 契约，为后续黑灰工作区、白色 board surface、world 锁定网格提供统一几何入口。
  2. 在 `CanvasRenderer` 中开始双写 `workspaceOverlay` 与旧的 `boardOverlay`，保证阶段 1 只落在 shared 层，不提前改动双端 viewport。
  3. 明确阶段 1 只冻结 contract，不提前生成真实网格线段；`minorGridSegments` / `majorGridSegments` 暂时保持为空数组。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - `macOS` / `iOS` viewport 层级迁移
  - 白色 board surface 的实际绘制接入
  - 黑灰背景与网格的实际 UI 呈现
  - 原始 gif diff
  - git commit / push

## 修改一：在 shared snapshot 中建立 workspace render contract

### 修改前

- `CanvasRenderSnapshot` 只有 `boardOverlay`，还没有承载工作区背景、board surface、网格参数的统一字段。
- shared 层也没有专门描述工作区网格线段的类型，后续如果直接改 viewport，只能让双端分别推导自己的 grid 几何。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasBoardRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 只暴露旧的 boardOverlay，shared 层没有 workspaceOverlay 契约，无法统一承载 board surface 与网格几何。
struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        editOverlay: nil,
        interactionOverlay: nil
    )
}
```

### 修改后

- 新增 `CanvasWorkspaceGridLineSegment`，用最小共享几何单元描述工作区网格线段。
- 新增 `CanvasWorkspaceRenderOverlay`，先把 `viewportBounds`、`boardSurfaceWorldRect`、`boardSurfaceScreenRect`、`minorGridStepWorld`、`majorGridLineEvery` 和两组 grid segment 数组冻结下来。
- `CanvasRenderSnapshot` 新增 `workspaceOverlay`，但旧的 `boardOverlay` 继续保留，形成阶段 1 所需的加法 contract。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasWorkspaceGridLineSegment / CanvasWorkspaceRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 新增 workspaceOverlay 骨架，为后续 viewport 迁移提供统一的 board surface 与网格几何入口，同时保留旧 boardOverlay 做兼容过渡。
struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

// Workspace chrome is an additive contract during the migration away from
// board highlight rendering. Platform viewports can adopt this geometry
// incrementally while the legacy board overlay remains available.
struct CanvasWorkspaceGridLineSegment {
    let start: CGPoint
    let end: CGPoint
}

struct CanvasWorkspaceRenderOverlay {
    let viewportBounds: CGRect
    let boardSurfaceWorldRect: CGRect
    let boardSurfaceScreenRect: CGRect
    let minorGridStepWorld: CGFloat
    let majorGridLineEvery: Int
    let minorGridSegments: [CanvasWorkspaceGridLineSegment]
    let majorGridSegments: [CanvasWorkspaceGridLineSegment]
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        workspaceOverlay: nil,
        boardOverlay: nil,
        items: [],
        editOverlay: nil,
        interactionOverlay: nil
    )
}
```

## 修改二：在 renderer 中开始双写 workspaceOverlay，但不破坏旧 boardOverlay 输出

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 只会根据 `boardState.worldRect` 生成旧的 `boardOverlay`。
- shared 层没有 `makeWorkspaceOverlay(...)` 之类的桥接入口，因此后续阶段如果想切换 viewport，只能一边改 snapshot，一边直接重写双端视图。
- 这一状态不利于阶段式迁移。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改前 renderer 只生成旧的 boardOverlay；工作区 board surface 和网格相关契约尚未进入 shared snapshot。
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

    let boardOverlay = boardState.map { boardState in
        CanvasBoardRenderOverlay(
            worldRect: boardState.worldRect,
            screenRect: camera.worldToViewport(boardState.worldRect)
        )
    }

    // ... 省略 editOverlay / interactionOverlay 未改动代码 ...

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
        editOverlay: editOverlay,
        interactionOverlay: interactionOverlay
    )
}
```

### 修改后

- `CanvasRenderer` 新增 `workspaceMinorGridStepWorld` 与 `workspaceMajorGridLineEvery` 两个 shared 常量，先把网格步长契约固定下来。
- `makeSnapshot(...)` 现在会在 `boardState` 存在时，同时生成：
  - `workspaceOverlay`
  - 旧的 `boardOverlay`
- 新增 `makeWorkspaceOverlay(...)` 作为阶段 1 桥接函数。
- 目前它只负责填充 board surface 几何和网格参数，`minorGridSegments` / `majorGridSegments` 先保留为空数组，明确表示“阶段 1 冻结 contract，阶段 2 再下沉真实网格几何”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeWorkspaceOverlay(...)
// 功能说明: 修改后 renderer 开始双写 workspaceOverlay 与 boardOverlay；本阶段先冻结 shared contract，不提前在 renderer 中生成真实网格线段。
struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28
    private static let rotationInteractionTickStepDegrees: CGFloat = 10
    private static let minimumRotationInteractionRingRadius: CGFloat = 48
    private static let rotationInteractionTickLength: CGFloat = 8
    private static let rotationInteractionTextOffset: CGFloat = 18
    private static let workspaceMinorGridStepWorld: CGFloat = 64
    private static let workspaceMajorGridLineEvery: Int = 4
    private let presentationResolver = CanvasImagePresentationResolver()

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

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            workspaceOverlay: workspaceOverlay,
            boardOverlay: boardOverlay,
            items: renderItems,
            editOverlay: editOverlay,
            interactionOverlay: interactionOverlay
        )
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
}
```

## 阶段结果

- 阶段 1 已把 workspace 相关共享契约稳定下来，但没有改变任何 UI 行为。
- 旧的 `boardOverlay` 仍然可被 `macOS` / `iOS` viewport 继续消费，因此当前不会打断现有橙色虚线 board highlight 的渲染链路。
- 新的 `workspaceOverlay` 现在已经能稳定输出：
  - `boardSurfaceWorldRect`
  - `boardSurfaceScreenRect`
  - `minorGridStepWorld`
  - `majorGridLineEvery`
- 真实的网格线段生成仍留在下一阶段实现。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 与 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`，没有新增 lint 问题。
- 已确认本次变更只影响两个 shared 文件，没有波及 `BoardDocument`、`BoardDocumentMapper`、`BoardHistorySnapshot`、`macOS` / `iOS` viewport。
- 尝试使用 `xcodebuild` 做工程级验证时，系统当前 `xcode-select` 指向 `CommandLineTools` 而不是完整 `Xcode`，因此本次记录没有附带完整构建结果。

## 下一阶段输入

- 下一阶段将继续在 `CanvasRenderer` 中生成真实的 world 锁定网格线段，并把 screen-space 几何通过 `workspaceOverlay` 下发给 viewport。
- 在那之前，`workspaceOverlay` 可以视为“已冻结的 shared contract + 空网格占位实现”。
