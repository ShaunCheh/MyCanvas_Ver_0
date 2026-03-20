# 20260320_173544_canvas_workspace_phase5_shared_contract_cleanup_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 中删除旧的 `CanvasBoardRenderOverlay` 与 `boardOverlay` 字段。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中停止 dual-write 旧 `boardOverlay`，只保留 `workspaceOverlay` 作为共享渲染真源。
  3. 对 shared 与双端 viewport 做一轮收口检查，确认旧的 `boardOverlay` / `boardHighlight` / `boardStrokeColor` 命名已经退出代码路径。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - minimap / board preview 的视觉统一
  - 原始 gif diff
  - git commit / push

## 修改一：删除 shared snapshot 中遗留的 boardOverlay 契约

### 修改前

- `CanvasRenderSnapshot` 里同时存在：
  - 新的 `workspaceOverlay`
  - 旧的 `boardOverlay`
- `CanvasBoardRenderOverlay` 本身也还保留在 shared 层。
- 这意味着虽然双端 viewport 已经切到 `workspaceOverlay`，但 shared contract 仍然处于“过渡双轨”状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasBoardRenderOverlay / CanvasWorkspaceGridLineSegment / CanvasRenderSnapshot
// 功能说明: 修改前 shared snapshot 仍保留旧的 boardOverlay 契约，workspaceOverlay 和 boardOverlay 并存，属于迁移期双轨状态。
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

### 修改后

- `CanvasBoardRenderOverlay` 已从 shared 层删除。
- `CanvasRenderSnapshot` 现在只保留 `workspaceOverlay`，不再携带旧的 `boardOverlay`。
- 注释语义也从“迁移期加法契约”收口成“当前共享真源”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasWorkspaceGridLineSegment / CanvasRenderSnapshot
// 功能说明: 修改后 shared snapshot 只保留 workspaceOverlay，明确由它统一承载 board surface 和背景网格几何，旧 boardOverlay 契约已被移除。
// Workspace chrome is now the shared source of truth for board surface and
// background grid geometry across macOS and iOS viewports.
struct CanvasWorkspaceGridLineSegment {
    let start: CGPoint
    let end: CGPoint
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        workspaceOverlay: nil,
        items: [],
        editOverlay: nil,
        interactionOverlay: nil
    )
}
```

## 修改二：停止 renderer 双写旧 boardOverlay，只保留 workspaceOverlay

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 在生成 `workspaceOverlay` 的同时，仍然额外生成旧的 `boardOverlay`。
- 返回 `CanvasRenderSnapshot` 时，也会把这份旧字段继续塞回 snapshot。
- 这一步在阶段 1 是必要的，但在双端都已切换到 `workspaceOverlay` 后，就变成了纯技术债。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改前 renderer 仍然同时生成 workspaceOverlay 和旧的 boardOverlay，属于迁移期 dual-write。
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
```

### 修改后

- `CanvasRenderer.makeSnapshot(...)` 现在只生成 `workspaceOverlay`。
- `CanvasRenderSnapshot` 回传时也只写入 `workspaceOverlay`。
- 这样 shared renderer 的输出语义和双端 viewport 的消费语义终于完全一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改后 renderer 不再 dual-write 旧 boardOverlay，只保留 workspaceOverlay 作为 board surface 与工作区网格的共享输出。
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
    } else {
        workspaceOverlay = nil
    }

    // ... 省略 editOverlay / interactionOverlay 未改动代码 ...

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        workspaceOverlay: workspaceOverlay,
        items: renderItems,
        editOverlay: editOverlay,
        interactionOverlay: interactionOverlay
    )
}
```

## 修改三：完成旧命名的全局收口检查

### 修改前

- 阶段 4 前后，代码库里还留着几类“迁移期术语”风险：
  - `CanvasBoardRenderOverlay`
  - `boardOverlay`
  - `boardHighlight`
  - `refreshBoardHighlight`
  - `boardStrokeColor`
- 如果这些命名继续残留在 shared 或平台层，后续维护时很容易把“工作区白板”重新理解回“橙色高亮框”。

### 修改后

- 本阶段完成后，已确认 `*.swift` 范围内不存在上述旧命名。
- 也就是说：
  - shared 真源已经统一到 `workspaceOverlay`
  - macOS / iOS 两端也已经不再使用旧的 highlight 语义

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasWorkspaceGridLineSegment / CanvasWorkspaceRenderOverlay
// 功能说明: 修改后 shared 语义围绕 workspaceOverlay 收口，不再保留 board highlight 的过渡性命名。
// Workspace chrome is now the shared source of truth for board surface and
// background grid geometry across macOS and iOS viewports.
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
```

## 阶段结果

- `workspaceOverlay` 现在已经成为唯一有效的 board surface / 工作区网格共享渲染契约。
- shared 层不再处于 dual-write 状态，输出模型比阶段 1 到阶段 4 更干净。
- 双端 viewport 的消费语义和 shared renderer 的输出语义已经完全对齐。

## 验证情况

- 已对以下文件运行诊断检查，没有新增 lint 问题：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 已在 `*.swift` 范围内确认以下旧命名已全部退出代码：
  - `boardOverlay`
  - `CanvasBoardRenderOverlay`
  - `boardHighlight`
  - `refreshBoardHighlight`
  - `boardStrokeColor`
- 本次没有附带完整 `xcodebuild` 工程构建结果。

## 下一阶段输入

- 下一阶段将进入阶段 6，决定是否把 minimap 与 board preview 里的旧橙色 board 视觉一起统一到新的 workspace / board surface 语义。 
