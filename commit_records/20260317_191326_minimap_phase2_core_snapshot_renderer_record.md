# 20260317_191326_minimap_phase2_core_snapshot_renderer_record

## 记录范围

- 记录内容：
  1. 新增 `CanvasMiniMapSnapshot.swift`，定义 minimap 的 Core 数据模型。
  2. 新增 `CanvasMiniMapRenderer.swift`，生成 minimap 所需的 `boardWorldRect / displayWorldRect / visibleWorldRect / nodes`。
  3. 将 minimap renderer 接到 `Phase 1` 的 `CanvasImagePresentationResolver`，使节点几何直接使用“裁切后且已带旋转”的当前可见区域。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
- 依赖但未修改的相关文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`
- 本记录不包含：
  - minimap 的 iOS/macOS 视图实现
  - minimap 的 controller 接线
  - 原始 gif diff
  - git commit / push

## 修改一：新增 `CanvasMiniMapSnapshot`，补齐 minimap 的 Core 数据模型

### 修改前

- Core 层只有主画板自己的 `CanvasRenderSnapshot`。
- 还没有任何专门面向 minimap 的 snapshot 类型。
- 因此无法在不混入主画板 `selection/crop overlay` 语义的前提下，独立表达“整板范围 + 当前视口 + 内容节点”的数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderSnapshot
// 功能说明: 修改前 Core 层只有主画板渲染快照；其字段围绕 viewport items 与 edit overlay 设计，没有 minimap 专用结构。
struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        editOverlay: nil
    )
}
```

### 修改后

- 新增 `CanvasMiniMapNodeKind`，先支持 `image`，并为 `text / sticker / shape` 预留扩展位。
- 新增 `CanvasMiniMapNode`，以 `worldQuad + zIndex + preview 标记` 为中心表达 minimap 节点。
- 新增 `CanvasMiniMapSnapshot`，集中承载：
  - `boardWorldRect`
  - `displayWorldRect`
  - `visibleWorldRect`
  - `nodes`
- 这样 minimap 后续可以完全独立于主画板 overlay 语义消费自己的数据模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift
// 函数名: CanvasMiniMapNodeKind / CanvasMiniMapNode / CanvasMiniMapSnapshot
// 功能说明: 新增 minimap Core 数据模型，用通用几何节点表达整板内容分布与当前视口范围。
enum CanvasMiniMapNodeKind {
    case image
    case text
    case sticker
    case shape
}

struct CanvasMiniMapNode {
    let id: UUID
    let kind: CanvasMiniMapNodeKind
    let worldQuad: CanvasQuad
    let zIndex: CGFloat
    let isPreviewActive: Bool

    var worldBounds: CGRect {
        worldQuad.boundingRect.standardized
    }
}

struct CanvasMiniMapSnapshot {
    let boardWorldRect: CGRect
    let displayWorldRect: CGRect
    let visibleWorldRect: CGRect
    let nodes: [CanvasMiniMapNode]

    static let empty = CanvasMiniMapSnapshot(
        boardWorldRect: .zero,
        displayWorldRect: .zero,
        visibleWorldRect: .zero,
        nodes: []
    )
}
```

## 修改二：新增 `CanvasMiniMapRenderer`，从 `scene + board + camera` 生成 minimap snapshot

### 修改前

- 还没有 minimap renderer。
- Core 层唯一现成的 renderer 是主画板的 `CanvasRenderer`，它会按当前视口裁剪 `visibleItems`，只产出主画板当前看得见的元素。
- 这不适合 minimap，因为 minimap 需要的是整块画板上的内容分布，而不是当前 viewport 里的可见子集。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前只有主画板 renderer；当 viewport 有效时，它只渲染当前 visibleWorldRect 内的 items。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect
    let visibleItems: [CanvasImageItem]
    if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
        visibleItems = scene.visibleItems(in: visibleWorldRect)
    } else {
        visibleItems = scene.orderedItems()
    }
    // ...
}
```

### 修改后

- 新增 `CanvasMiniMapRenderer.makeSnapshot(...)`。
- 这条链路不再按 `camera.visibleWorldRect` 去裁剪节点，而是遍历 `scene.orderedItems()` 生成整板节点。
- minimap snapshot 会同时带上：
  - 当前主画板视口 `visibleWorldRect`
  - 画板正式边界 `boardWorldRect`
  - 当前展示边界 `displayWorldRect`
  - 所有 minimap 节点 `nodes`
- 后续平台视图只需要消费 `CanvasMiniMapSnapshot` 就能绘制 minimap。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 新增 minimap renderer，生成整板级别的 snapshot，而不是主画板当前 viewport 的局部渲染结果。
struct CanvasMiniMapRenderer {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(camera.visibleWorldRect) ?? .zero
        let nodes = scene.orderedItems().map { item in
            makeNode(
                for: item,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        }

        let boardWorldRect = resolveBoardWorldRect(
            boardState: boardState,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )
        let displayWorldRect = resolveDisplayWorldRect(
            boardWorldRect: boardWorldRect,
            nodes: nodes,
            fallbackVisibleWorldRect: visibleWorldRect
        )

        return CanvasMiniMapSnapshot(
            boardWorldRect: boardWorldRect,
            displayWorldRect: displayWorldRect,
            visibleWorldRect: visibleWorldRect,
            nodes: nodes
        )
    }
}
```

## 修改三：minimap 节点直接复用 `Phase 1` 的 presentation resolver

### 修改前

- 修改前没有 minimap renderer，因此也不存在“如何把裁切草稿 / 旋转草稿变成 minimap 节点”的 Core 处理逻辑。
- 如果直接从 `CanvasImageItem.worldBounds` 或 `scene` 正式状态取值，会丢掉两类关键信息：
  - 裁切中的临时可见区域
  - 旋转中的临时角度

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift（修改前不存在）
// 函数名: 无
// 功能说明: 修改前工程中没有 minimap renderer，因此不存在统一处理 crop/rotate preview 的 minimap 节点生成逻辑。
// 无对应实现
```

### 修改后

- `CanvasMiniMapRenderer.makeNode(...)` 直接调用 `CanvasImagePresentationResolver.resolve(...)`。
- minimap 节点统一使用 `presentation.visibleWorldQuad`，这意味着：
  - 节点天然是“裁切后的当前可见区域”
  - 节点天然保留旋转后的四边形角度
- `isPreviewActive` 则把 `crop preview` 和 `rotation preview` 统一折叠成 minimap 层可感知的标记。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeNode(for:inlineEditState:rotationPreviewState:)
// 功能说明: minimap 节点不直接取 item.worldBounds，而是复用 presentation resolver 的 visibleWorldQuad，保证裁切与旋转预览都能同步进 minimap。
private func makeNode(
    for item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasMiniMapNode {
    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    return CanvasMiniMapNode(
        id: presentation.itemID,
        kind: .image,
        worldQuad: presentation.visibleWorldQuad,
        zIndex: presentation.zIndex,
        isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
    )
}
```

## 修改四：新增 `displayWorldRect` 的预览扩展逻辑，避免 minimap 裁掉活跃草稿

### 修改前

- 修改前还没有 minimap 的显示边界概念。
- 也就不存在“正式 board 边界”和“当前预览显示边界”之间的区分。
- 如果后续 minimap 直接死用 `boardState.worldRect`，一旦活跃裁切/旋转预览超出 board，灰块就会被截断。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift（修改前不存在）
// 函数名: 无
// 功能说明: 修改前没有 displayWorldRect 的概念，也没有把活跃 preview bounds 临时并入显示边界的逻辑。
// 无对应实现
```

### 修改后

- 新增 `resolveBoardWorldRect(...)`：
  - 优先使用正式 `boardState.worldRect`
  - 没有 board 时退回到所有节点包围盒
  - 再退回到当前相机 `visibleWorldRect`
- 新增 `resolveDisplayWorldRect(...)`：
  - 默认使用正式 `boardWorldRect`
  - 若存在活跃 preview 节点，则把这些节点的 `worldBounds` 合并进来
  - 只影响 minimap 当前显示范围，不会回写正式 `boardState`
- 这样 minimap 后续既能忠实显示当前活跃草稿，又不会污染文档层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: resolveBoardWorldRect(boardState:nodes:fallbackVisibleWorldRect:) / resolveDisplayWorldRect(boardWorldRect:nodes:fallbackVisibleWorldRect:)
// 功能说明: 正式 board 边界与 minimap 当前显示边界分离；displayWorldRect 会临时 union 活跃 preview bounds，避免预览灰块被裁掉。
private func resolveBoardWorldRect(
    boardState: CanvasBoardState?,
    nodes: [CanvasMiniMapNode],
    fallbackVisibleWorldRect: CGRect
) -> CGRect {
    if let boardWorldRect = boardState.flatMap({ sanitizedWorldRect($0.worldRect) }) {
        return boardWorldRect
    }

    if let nodeBounds = combinedWorldBounds(of: nodes) {
        return nodeBounds
    }

    return fallbackVisibleWorldRect
}

private func resolveDisplayWorldRect(
    boardWorldRect: CGRect,
    nodes: [CanvasMiniMapNode],
    fallbackVisibleWorldRect: CGRect
) -> CGRect {
    guard let previewWorldBounds = combinedWorldBounds(
        of: nodes.filter(\\.isPreviewActive)
    ) else {
        return sanitizedWorldRect(boardWorldRect) ?? fallbackVisibleWorldRect
    }

    guard let sanitizedBoardWorldRect = sanitizedWorldRect(boardWorldRect) else {
        return previewWorldBounds
    }

    return sanitizedBoardWorldRect.union(previewWorldBounds).standardized
}
```

## 结果与影响

- 本次修改已经把 minimap `Phase 2` 的 Core 数据链补齐了。
- 当前工程已经具备：
  - minimap 自己的 snapshot 模型
  - minimap 自己的 renderer
  - 整板节点生成逻辑
  - 基于 preview 的临时显示边界扩展
- 但这一步仍然不涉及 UI，所以用户侧暂时看不到 minimap；后续 `Phase 3+` 只需要继续补布局层、平台视图和 controller 接线。

## 校验情况

- 已执行 `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift`，通过。
- `ReadLints` 已检查 `CanvasMiniMapSnapshot.swift` 与 `CanvasMiniMapRenderer.swift`，无新增诊断。
- 本次新增文件位于 `MyCanvas_Ver_0/Canvas/Core/`；工程使用 `PBXFileSystemSynchronizedRootGroup`，因此未单独修改 `project.pbxproj`。
