# 20260316_111602_phase_c_stage1_selection_overlay_record

## 记录范围

- 记录内容：
  1. 为“干净的方案 C”落地第一阶段，在 core 渲染模型中引入 `selectionOverlay`。
  2. 让 `CanvasRenderer` 基于当前 `selectedItemID` 统一产出选中框与四角 handle 的语义几何，作为后续 viewport 绘制与 controller hit test 的共享输入。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：原始 gif diff、viewport 选中框绘制、handle 命中与缩放交互。

## 修改一：扩展 CanvasRenderSnapshot，承载选中态语义几何

### 修改前

- `CanvasRenderSnapshot` 只保存 viewport、可见世界区域、board overlay 和图片 items。
- core 层还没有一个专门的结构来表达“当前被选中图片的选中框”和“四角 handle 锚点”。
- 这意味着后续如果要在 viewport 里绘制 handle，平台层只能自行从 item 或 selected state 反推几何，无法把 selection geometry 做成 renderer 的统一输出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasBoardRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 只承载 board overlay 和 items，没有选中框与 handle 的几何数据。
struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: []
    )
}
```

### 修改后

- 新增 `CanvasSelectionHandleRole`，把四个角的 handle 语义固定为 `topLeading / topTrailing / bottomLeading / bottomTrailing`。
- 新增 `CanvasSelectionHandleGeometry` 和 `CanvasSelectionRenderOverlay`，用于保存 handle 锚点中心、选中项 `worldFrame`、`screenFrame` 等中性几何数据。
- `CanvasRenderSnapshot` 新增 `selectionOverlay` 字段，`empty` 也同步补上 `selectionOverlay: nil`。
- 这一步只引入“语义几何”，没有把视觉大小、命中热区、颜色等平台细节塞进 core。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasSelectionHandleRole / CanvasSelectionHandleGeometry / CanvasSelectionRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 可以直接承载当前选中图片的选中框和四角 handle 几何，为后续 viewport 与 hit test 提供统一来源。
struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct CanvasSelectionHandleGeometry {
    let role: CanvasSelectionHandleRole
    let screenCenter: CGPoint
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasSelectionHandleGeometry]
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil
    )
}
```

## 修改二：让 CanvasRenderer 成为 selection geometry 的唯一来源

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 只负责生成 `renderItems` 和 `boardOverlay`。
- 选中态只通过 `CanvasRenderItem.isSelected` 下发到图片层，renderer 本身并不会生成独立的选中框或 handle 几何。
- 这样后续如果 viewport 或 controller 想使用统一的 selection geometry，就缺少一个来自 renderer 的权威输出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:)
// 功能说明: 修改前 renderer 只生成 items 与 board overlay，不会产出独立的 selection overlay。
struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState()
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        let visibleItems: [CanvasImageItem]
        if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
            visibleItems = scene.visibleItems(in: visibleWorldRect)
        } else {
            visibleItems = scene.orderedItems()
        }

        let renderItems = visibleItems.map { item in
            CanvasRenderItem(
                id: item.id,
                screenFrame: camera.worldToViewport(item.worldFrame),
                cgImage: item.cgImage,
                zIndex: item.zIndex,
                isSelected: interactionState.selectedItemID == item.id
            )
        }

        let boardOverlay = boardState.map { boardState in
            CanvasBoardRenderOverlay(
                worldRect: boardState.worldRect,
                screenRect: camera.worldToViewport(boardState.worldRect)
            )
        }

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems
        )
    }
}
```

### 修改后

- `makeSnapshot(...)` 现在在返回前额外生成 `selectionOverlay`，并将其注入 `CanvasRenderSnapshot`。
- 新增 `makeSelectionOverlay(...)`：基于 `interactionState.selectedItemID` 和 `scene.item(withID:)` 获取当前选中项，再统一计算其 `worldFrame`、`screenFrame`。
- 新增 `makeSelectionHandles(...)` 与 `selectionHandleCenter(...)`：从 `screenFrame` 派生四个角的 handle 锚点中心。
- 这里有意直接从 `scene.item(withID:)` 取选中项，而不是从 `visibleItems` 反推，避免 selection geometry 与裁剪结果耦合。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:) / makeSelectionOverlay(scene:camera:interactionState:) / makeSelectionHandles(for:) / selectionHandleCenter(for:in:)
// 功能说明: 修改后 renderer 统一输出当前选中项的选中框与四角 handle 语义几何，供后续 viewport 绘制与 controller 命中测试复用。
struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState()
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        let visibleItems: [CanvasImageItem]
        if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
            visibleItems = scene.visibleItems(in: visibleWorldRect)
        } else {
            visibleItems = scene.orderedItems()
        }

        let renderItems = visibleItems.map { item in
            CanvasRenderItem(
                id: item.id,
                screenFrame: camera.worldToViewport(item.worldFrame),
                cgImage: item.cgImage,
                zIndex: item.zIndex,
                isSelected: interactionState.selectedItemID == item.id
            )
        }

        let boardOverlay = boardState.map { boardState in
            CanvasBoardRenderOverlay(
                worldRect: boardState.worldRect,
                screenRect: camera.worldToViewport(boardState.worldRect)
            )
        }

        let selectionOverlay = makeSelectionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            selectionOverlay: selectionOverlay
        )
    }

    private func makeSelectionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState
    ) -> CanvasSelectionRenderOverlay? {
        guard
            let selectedItemID = interactionState.selectedItemID,
            let selectedItem = scene.item(withID: selectedItemID)
        else {
            return nil
        }

        let worldFrame = selectedItem.worldFrame.standardized
        let screenFrame = camera.worldToViewport(worldFrame).standardized

        return CanvasSelectionRenderOverlay(
            itemID: selectedItemID,
            worldFrame: worldFrame,
            screenFrame: screenFrame,
            handles: makeSelectionHandles(for: screenFrame)
        )
    }

    private func makeSelectionHandles(for screenFrame: CGRect) -> [CanvasSelectionHandleGeometry] {
        CanvasSelectionHandleRole.allCases.map { role in
            CanvasSelectionHandleGeometry(
                role: role,
                screenCenter: selectionHandleCenter(for: role, in: screenFrame)
            )
        }
    }

    private func selectionHandleCenter(
        for role: CanvasSelectionHandleRole,
        in screenFrame: CGRect
    ) -> CGPoint {
        switch role {
        case .topLeading:
            return CGPoint(x: screenFrame.minX, y: screenFrame.minY)
        case .topTrailing:
            return CGPoint(x: screenFrame.maxX, y: screenFrame.minY)
        case .bottomLeading:
            return CGPoint(x: screenFrame.minX, y: screenFrame.maxY)
        case .bottomTrailing:
            return CGPoint(x: screenFrame.maxX, y: screenFrame.maxY)
        }
    }
}
```

## 结果

- core 渲染层现在已经具备了 `selectionOverlay` 这条独立输出通路，后续 viewport 可以直接消费 `screenFrame + handles` 来画选中框和四角 handle。
- 这一步没有改动平台层绘制，因此当前可见的选中反馈仍然保持原样；阶段二再把选中框与 handle 正式迁入 `overlayLayer`。
- 这一步也没有修改持久化模型；图片尺寸与选中项恢复逻辑继续沿用现有存储结构。
