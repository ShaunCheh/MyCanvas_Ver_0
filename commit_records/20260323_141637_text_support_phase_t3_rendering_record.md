# 20260323_141637_text_support_phase_t3_rendering_record

## 记录范围

- 记录内容：
  1. 将主画布 `CanvasRenderSnapshot` / `CanvasRenderer` 从 image-only render item 升级为可承载 image/text 两种 payload 的 mixed render snapshot。
  2. 将 `CanvasInteractionState`、`CanvasRotationPreviewState`、`CanvasRotationInteractionState`、`CanvasContextMenuContext`、`CanvasContextResolver` 的 item ID 语义提升到 `CanvasItemID`，让文本项能参与共享命中测试与选择态。
  3. 更新 `CanvasCommand`、`CanvasCommandCatalog`、`CanvasEditorSession`，让选择、复制、删除、层级调整等共享命令可以作用于任意 board item，而不是只作用于 image item。
  4. 新增 `CanvasTextLayer`，并把 `iOS` / `macOS` viewport 的 layer reconciliation 从单一路径 `imageLayers` 扩展为 `image + text` 双通道。
  5. 更新 `iOSViewController` / `macOSViewController` 的 pointer state 与交互流程，让文本项可以被选中、拖动、缩放、旋转。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 文本内容编辑 UI
  - 添加文本按钮与文本创建命令
  - minimap / board list preview / thumbnail 的文本绘制闭环
  - 原始 gif diff
  - git commit / push

## 修改一：共享 render snapshot 不再只表达图片，而是升级为 mixed render payload

### 修改前

- `CanvasRenderItem` 直接内嵌 `cgImage` 和 `contentsRect`，默认每个 render item 都是图片。
- `CanvasEditRenderOverlay` 与 `CanvasInteractionRenderOverlay` 的 `itemID` 仍是 `CanvasImageItemID`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: N/A（CanvasRenderItem / CanvasEditRenderOverlay / CanvasInteractionRenderOverlay）
// 功能说明: 修改前 render snapshot 仍是 image-only 设计；payload 直接烙死在 `CanvasRenderItem` 上，文本项无法进入主画布渲染快照。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let contentsRect: CGRect
    let rotationRadians: CGFloat
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

struct CanvasInteractionRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasInteractionOverlayKind
    let payload: CanvasInteractionRenderOverlayPayload
}
```

### 修改后

- 新增 `CanvasImageRenderPayload`、`CanvasTextRenderPayload`、`CanvasRenderPayload`，让 render item 用统一几何 + 分类型 payload 表达。
- `CanvasRenderItem.id`、overlay 的 `itemID` 全部提升到 `CanvasItemID`，为 image/text 共用 selection / rotate / hit-test 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: N/A（CanvasImageRenderPayload / CanvasTextRenderPayload / CanvasRenderItem）
// 功能说明: 修改后 render item 只保留共享几何字段，具体内容改由 image/text payload 分担；viewport 可以按 payload 类型做图层分流。
struct CanvasImageRenderPayload {
    let contentsRect: CGRect
    let cgImage: CGImage
}

struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case text(CanvasTextRenderPayload)
}

struct CanvasRenderItem {
    let id: CanvasItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let rotationRadians: CGFloat
    let zIndex: CGFloat
    let payload: CanvasRenderPayload
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: N/A（CanvasEditRenderOverlay / CanvasInteractionRenderOverlay）
// 功能说明: 修改后 selection/crop/rotation overlay 都以 `CanvasItemID` 追踪 item，不再把共享 overlay 绑定到图片专用 ID 上。
struct CanvasEditRenderOverlay {
    let itemID: CanvasItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

struct CanvasInteractionRenderOverlay {
    let itemID: CanvasItemID
    let kind: CanvasInteractionOverlayKind
    let payload: CanvasInteractionRenderOverlayPayload
}
```

## 修改二：共享选择态、旋转态与 context hit-test 从 image-only ID 升级为 board-item ID

### 修改前

- `CanvasInteractionState.selectedItemID`、`CanvasRotationPreviewState.itemID`、`CanvasRotationInteractionState.itemID` 都是 `CanvasImageItemID`。
- `CanvasContextMenuContext` 和 `CanvasContextResolver` 也默认命中的只有图片项，body hit-test 仍调用 `scene.topmostItemID(containing:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 函数名: N/A（CanvasInteractionState）
// 功能说明: 修改前共享选择态仍把“被选中的 item”限定为图片 ID，text item 无法进入统一选中链路。
struct CanvasInteractionState {
    var selectedItemID: CanvasImageItemID?

    init(selectedItemID: CanvasImageItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: N/A（CanvasRotationPreviewState / CanvasRotationInteractionState）
// 功能说明: 修改前旋转预览态与旋转交互态也都只接受图片 ID，因此文本项无法复用共享旋转预览逻辑。
struct CanvasRotationPreviewState {
    let itemID: CanvasImageItemID
    var draftRotationRadians: CGFloat
}

struct CanvasRotationInteractionState {
    let itemID: CanvasImageItemID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名: N/A（CanvasContextMenuContext）
// 功能说明: 修改前 context menu context 记录的 target / selected item 仍是图片专用 ID。
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasImageItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasImageItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveContext(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:interactionMetrics:)
// 功能说明: 修改前 body hit-test 仍通过 `scene.topmostItemID(containing:)` 命中图片项，text item 不会进入共享 context resolve 结果。
func resolveContext(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasImageItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
    // ... 省略 edit handle / crop outline 分支 ...
    guard let itemID = scene.topmostItemID(containing: invocationWorldPoint) else {
        return finalize(
            branch: "blank",
            resolvedTarget: ResolvedTarget(targetKind: .blank)
        )
    }

    let targetKind: CanvasContextMenuTargetKind =
        itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody
    // ... 省略后续组装逻辑 ...
}
```

### 修改后

- 选择态、旋转预览态、旋转交互态、context target 全部改成 `CanvasItemID`。
- `CanvasContextResolver` 的 body hit-test 切到 `scene.topmostBoardItemID(containing:)`，文本项现在可以和图片项一样被命中为 selected/unselected body。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 函数名: N/A（CanvasInteractionState）
// 功能说明: 修改后共享选择态已经能承载任意 board item 的 ID，文本项正式进入统一选中链路。
struct CanvasInteractionState {
    var selectedItemID: CanvasItemID?

    init(selectedItemID: CanvasItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: N/A（CanvasRotationPreviewState / CanvasRotationInteractionState）
// 功能说明: 修改后旋转 preview / interaction 也改为追踪 `CanvasItemID`，text item 可复用共享旋转预览和旋转 HUD。
struct CanvasRotationPreviewState {
    let itemID: CanvasItemID
    var draftRotationRadians: CGFloat
}

struct CanvasRotationInteractionState {
    let itemID: CanvasItemID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名: N/A（CanvasContextMenuContext）
// 功能说明: 修改后 context target / selection 都改成 board-item 级别 ID，context menu 与 pointer resolve 不再排除文本项。
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveContext(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:interactionMetrics:)
// 功能说明: 修改后 body hit-test 直接命中 topmost board item；text item 现在和 image item 一样可以进入 selected/unselected item body 分支。
func resolveContext(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
    // ... 省略 edit handle / crop outline 分支 ...
    guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
        return finalize(
            branch: "blank",
            resolvedTarget: ResolvedTarget(targetKind: .blank)
        )
    }

    let targetKind: CanvasContextMenuTargetKind =
        itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody
    // ... 省略后续组装逻辑 ...
}
```

## 修改三：`CanvasRenderer` 从只渲染 `CanvasImageItem` 改为渲染 mixed board items，并为文本生成 selection / rotation overlay

### 修改前

- `makeSnapshot(...)` 只会拿到 `[CanvasImageItem]`。
- `makeSelectionEditOverlay(...)` 和 `makeRotationInteractionOverlay(...)` 通过 `scene.item(withID:)` 和 `CanvasImagePresentationResolver` 工作。
- `makeRenderItem(...)` 只存在图片版本，文本项不会进入 render snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:inlineEditState:rotationPreviewState:rotationInteractionState:)
// 功能说明: 修改前 renderer 仍只遍历 image items，因此 text item 即使存在于 runtime，也不会进入主画布 snapshot。
let visibleItems: [CanvasImageItem]
if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
    visibleItems = scene.visibleItems(in: visibleWorldRect)
} else {
    visibleItems = scene.orderedItems()
}

let renderItems = visibleItems.map { item in
    makeRenderItem(
        for: item,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 selection overlay 只能通过 `scene.item(withID:)` 取图片项，再用图片 presentation 求出可见 quad。
guard
    let selectedItemID = interactionState.selectedItemID,
    let selectedItem = scene.item(withID: selectedItemID)
else {
    return nil
}

let presentation = presentationResolver.resolve(
    item: selectedItem,
    inlineEditState: inlineEditState,
    rotationPreviewState: rotationPreviewState
)
let worldQuad = presentation.visibleWorldQuad
let screenQuad = camera.worldToViewport(worldQuad)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前渲染项构造函数只有图片版本，render item 直接塞 `contentsRect` 和 `cgImage`。
private func makeRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let worldQuad = presentation.isCropPreviewActive
        ? presentation.fullImageWorldQuad
        : presentation.visibleWorldQuad
    let renderCenter = presentation.isCropPreviewActive
        ? presentation.fullImageCenter
        : presentation.visibleCenter
    let renderSize = presentation.isCropPreviewActive
        ? presentation.fullImageSize
        : presentation.visibleSize
    let contentsRect = presentation.isCropPreviewActive
        ? CanvasImageCropRect.fullImage.cgRect
        : presentation.effectiveCropRectNormalized.cgRect
    let screenQuad = camera.worldToViewport(worldQuad)
    return CanvasRenderItem(
        id: presentation.itemID,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        contentsRect: contentsRect,
        rotationRadians: presentation.effectiveRotationRadians,
        cgImage: presentation.cgImage,
        zIndex: presentation.zIndex
    )
}
```

### 修改后

- `makeSnapshot(...)` 改为遍历 `[CanvasBoardItem]`。
- 文本项会通过 `makeTextRenderItem(...)` 生成 text payload；图片项仍保留原有 image payload。
- `makeSelectionEditOverlay(...)` / `makeRotationInteractionOverlay(...)` 切到 `scene.boardItem(withID:)`，并用 `effectiveBoardItem(...)` 为 image/text 统一处理旋转预览。
- `crop` overlay 仍然保持 image-only，并继续调用 `scene.item(withID:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:inlineEditState:rotationPreviewState:rotationInteractionState:)
// 功能说明: 修改后 renderer 会遍历可见 board items，因此 text-only / mixed scene 都能进入主画布 snapshot。
let visibleItems: [CanvasBoardItem]
if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
    visibleItems = scene.visibleBoardItems(in: visibleWorldRect)
} else {
    visibleItems = scene.orderedBoardItems()
}

let renderItems = visibleItems.map { item in
    makeRenderItem(
        for: item,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:) / effectiveBoardItem(from:rotationPreviewState:)
// 功能说明: 修改后 selection overlay 可以直接作用于 image/text 任一 board item；旋转预览也通过共享的 effectiveBoardItem 统一下沉。
guard
    let selectedItemID = interactionState.selectedItemID,
    let selectedItem = scene.boardItem(withID: selectedItemID)
else {
    return nil
}

let effectiveItem = effectiveBoardItem(
    from: selectedItem,
    rotationPreviewState: rotationPreviewState
)
let worldQuad = effectiveItem.worldQuad
let screenQuad = camera.worldToViewport(worldQuad)
let selectionPayload = CanvasEditSelectionOverlayPayload(
    rotateAffordance: makeRotateAffordance(
        screenCenter: camera.worldToViewport(effectiveItem.center),
        screenQuad: screenQuad
    )
)

private func effectiveBoardItem(
    from item: CanvasBoardItem,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasBoardItem {
    guard
        let rotationPreviewState,
        rotationPreviewState.itemID == item.id
    else {
        return item
    }

    var effectiveItem = item
    effectiveItem.rotationRadians = rotationPreviewState.draftRotationRadians
    return effectiveItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:) / makeImageRenderItem(...) / makeTextRenderItem(...)
// 功能说明: 修改后 renderer 会按 board item 类型分流；image 继续走 presentationResolver，text 则直接用几何 + 样式生成 text payload。
private func makeRenderItem(
    for item: CanvasBoardItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    switch item {
    case let .image(imageItem):
        return makeImageRenderItem(
            for: imageItem,
            camera: camera,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
    case let .text(textItem):
        return makeTextRenderItem(
            for: textItem,
            camera: camera,
            rotationPreviewState: rotationPreviewState
        )
    }
}

private func makeImageRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    // ... 省略 image presentation 计算 ...
    return CanvasRenderItem(
        id: presentation.itemID,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        rotationRadians: presentation.effectiveRotationRadians,
        zIndex: presentation.zIndex,
        payload: .image(
            CanvasImageRenderPayload(
                contentsRect: presentation.isCropPreviewActive
                    ? CanvasImageCropRect.fullImage.cgRect
                    : presentation.effectiveCropRectNormalized.cgRect,
                cgImage: presentation.cgImage
            )
        )
    )
}

private func makeTextRenderItem(
    for item: CanvasTextItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    // ... 省略 effectiveTextItem 解析 ...
    return CanvasRenderItem(
        id: effectiveTextItem.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(effectiveTextItem.center),
        screenBoundsSize: CGSize(
            width: effectiveTextItem.size.width * camera.zoomScale,
            height: effectiveTextItem.size.height * camera.zoomScale
        ),
        rotationRadians: effectiveTextItem.rotationRadians,
        zIndex: effectiveTextItem.zIndex,
        payload: .text(
            CanvasTextRenderPayload(
                text: effectiveTextItem.text,
                style: effectiveTextItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

## 修改四：共享命令与 `CanvasEditorSession` 的 item 操作从图片专用 ID 升级为通用 board-item ID

### 修改前

- `CanvasCommand` 里的 `selectItem`、`duplicateItem`、`deleteItem`、层级命令都以 `CanvasImageItemID` 为参数。
- `CanvasEditorSession` 的可执行判断与实际操作都调用 `scene.item(withID:)`、`scene.duplicateItem(...)` 这类 image-only API。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: N/A（CanvasCommand）
// 功能说明: 修改前共享命令层只接受图片项 ID；即使 text item 已经存在 runtime，也不能进入这些命令入口。
enum CanvasCommand {
    case importImages(CanvasImportRequest)
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasImageItemID, recordHistory: Bool)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canSelectItem(withID:) / canDuplicateItem(withID:) / duplicateItem(withID:selectDuplicatedItem:recordHistory:)
// 功能说明: 修改前 session 的 item 命令仍然依赖图片专用 API，text item 不能走统一的 select / duplicate / z-order 流程。
func canSelectItem(withID itemID: CanvasImageItemID) -> Bool {
    guard scene.item(withID: itemID) != nil else {
        return false
    }

    return interactionState.selectedItemID != itemID
}

func canDuplicateItem(withID itemID: CanvasImageItemID) -> Bool {
    scene.item(withID: itemID) != nil
}

@discardableResult
func duplicateItem(
    withID itemID: CanvasImageItemID,
    selectDuplicatedItem: Bool = true,
    recordHistory: Bool = false
) -> CanvasImageItem? {
    guard canDuplicateItem(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard let duplicatedItem = scene.duplicateItem(
        withID: itemID,
        offsetInWorld: duplicateOffsetInWorld()
    ) else {
        return nil
    }

    // ... 省略后续 history / selection 逻辑 ...
    return duplicatedItem
}
```

### 修改后

- 命令层正式切到 `CanvasItemID`，text item 可以进入 select / duplicate / delete / z-order 的共享路径。
- `CanvasEditorSession` 对外的 item 命令改成 `scene.boardItem(withID:)` / `scene.duplicateBoardItem(...)`，从运行时容器层面真正支持 mixed item。
- `crop` 仍旧保留 image-only 入口，不在本阶段一并泛化。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: N/A（CanvasCommand）
// 功能说明: 修改后 command 层的 item 相关 case 都改为 `CanvasItemID`，共享命令不再假设目标一定是图片。
enum CanvasCommand {
    case importImages(CanvasImportRequest)
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasItemID, recordHistory: Bool)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canSelectItem(withID:) / selectItem(withID:recordHistory:) / duplicateItem(withID:selectDuplicatedItem:recordHistory:)
// 功能说明: 修改后 session 的共享 item 命令都改为 board-item 级别语义，text item 也能复用同一套 history / autosave / selection 流程。
func canSelectItem(withID itemID: CanvasItemID) -> Bool {
    guard scene.boardItem(withID: itemID) != nil else {
        return false
    }

    return interactionState.selectedItemID != itemID
}

@discardableResult
func selectItem(
    withID itemID: CanvasItemID,
    recordHistory: Bool = false
) -> Bool {
    guard canSelectItem(withID: itemID) else {
        return false
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    syncInlineEditStateWithSelection()
    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }
    return true
}

@discardableResult
func duplicateItem(
    withID itemID: CanvasItemID,
    selectDuplicatedItem: Bool = true,
    recordHistory: Bool = false
) -> CanvasBoardItem? {
    guard canDuplicateItem(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    guard let duplicatedItem = scene.duplicateBoardItem(
        withID: itemID,
        offsetInWorld: duplicateOffsetInWorld()
    ) else {
        return nil
    }

    expandBoardIfNeeded(toInclude: duplicatedItem.worldBounds)
    if selectDuplicatedItem {
        interactionState.selectedItemID = duplicatedItem.id
    }
    syncInlineEditStateWithSelection()
    if let beforeSnapshot {
        _ = recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "duplicate item"
        )
    }
    return duplicatedItem
}
```

## 修改五：新增 `CanvasTextLayer`，并让 `iOS` / `macOS` viewport 按 render payload 做双通道图层对账

### 修改前

- 平台渲染层只有 `CanvasImageLayer`，`update(with:contentsScale:)` 直接读取 `CanvasRenderItem.cgImage` 与 `contentsRect`。
- `iOSCanvasViewportView` / `macOSCanvasViewportView` 只有 `imageLayers` 字典，生命周期也只会调用 `refreshImageLayers()`。
- 仓库中不存在 `CanvasTextLayer.swift`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:)
// 功能说明: 修改前 image layer 直接假设 render item 自带图片内容；一旦 render item 改成 payload 分流，这个接口就不够用了。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if !isDisplayingImage(item.cgImage) {
            contents = item.cgImage
            lastAppliedImage = item.cgImage
        }

        if lastAppliedContentsRect != item.contentsRect {
            contentsRect = item.contentsRect
            lastAppliedContentsRect = item.contentsRect
        }

        // ... 省略 position / bounds / rotation / zPosition 更新 ...
        CATransaction.commit()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshImageLayers()
// 功能说明: 修改前 viewport 只有 image layer 字典与刷新入口；text payload 即使存在，也不会生成任何平台图层。
private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]

override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}
```

```text
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift
// 函数名: N/A（新文件）
// 功能说明: 修改前仓库里不存在文本渲染 layer；平台层没有专门承载文本 glyph 的图层实现。
[文件不存在]
```

### 修改后

- `CanvasImageLayer` 改为显式消费 `CanvasImageRenderPayload`。
- 新增 `CanvasTextLayer`，在平台层就地把 text payload 变成 attributed string，并按 zoom / layout bounds 自适应字号。
- `iOS` / `macOS` viewport 新增 `textLayers` 字典，并用 `refreshItemLayers()` 按 payload 类型分流到 `CanvasImageLayer` / `CanvasTextLayer`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:imagePayload:contentsScale:)
// 功能说明: 修改后 image layer 只关心 image payload，自身不再依赖 render item 的旧内嵌图片字段。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasItemID

    func update(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if !isDisplayingImage(imagePayload.cgImage) {
            contents = imagePayload.cgImage
            lastAppliedImage = imagePayload.cgImage
        }

        if lastAppliedContentsRect != imagePayload.contentsRect {
            contentsRect = imagePayload.contentsRect
            lastAppliedContentsRect = imagePayload.contentsRect
        }

        // ... 省略 position / bounds / rotation / zPosition 更新 ...
        CATransaction.commit()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasTextLayer.swift
// 函数名: update(with:textPayload:contentsScale:) / makeAttributedText(from:availableSize:)
// 功能说明: 修改后平台共享层拥有专门的文本图层；text payload 会在这里被转换成 attributed string，并按 zoom 与目标 bounds 做字体适配。
final class CanvasTextLayer: CATextLayer {
    let itemID: CanvasItemID
    private var lastAppliedText: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedZoomScale: CGFloat

    func update(
        with item: CanvasRenderItem,
        textPayload: CanvasTextRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // ... 省略 bounds / position / rotation / zPosition / contentsScale 更新 ...
        if shouldRefreshAttributedText(
            textPayload: textPayload,
            layoutBoundsSize: item.screenBoundsSize
        ) {
            string = makeAttributedText(
                from: textPayload,
                availableSize: item.screenBoundsSize
            )
            lastAppliedText = textPayload.text
            lastAppliedStyle = textPayload.style
            lastAppliedZoomScale = textPayload.zoomScale
        }
        CATransaction.commit()
    }

    private func makeAttributedText(
        from textPayload: CanvasTextRenderPayload,
        availableSize: CGSize
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping

        let font = fittedFont(
            for: textPayload,
            availableSize: availableSize,
            paragraphStyle: paragraphStyle
        )
        let textColor = platformColor(for: textPayload.style.color)

        return NSAttributedString(
            string: textPayload.text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshItemLayers()
// 功能说明: 修改后 viewport 改成 image/text 双字典 reconciliation；snapshot 里进来的 text payload 会被分发到 `CanvasTextLayer`。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshItemLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshItemLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

private func refreshItemLayers() {
    let incomingImageIDs = Set(
        snapshot.items.compactMap { item in
            if case .image = item.payload {
                return item.id
            }
            return nil
        }
    )
    let incomingTextIDs = Set(
        snapshot.items.compactMap { item in
            if case .text = item.payload {
                return item.id
            }
            return nil
        }
    )
    // ... 省略 remove stale layers ...
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

## 修改六：`iOS` / `macOS` controller 的 pointer 交互从 image-only 提升为 board-item 级别

### 修改前

- pointer resize / rotate / drag state 都绑定 `CanvasImageItemID`。
- 单击日志与选择结果也把目标硬编码为 `"image"`。
- 旋转、移动、缩放时都通过 `scene.item(...)`、`scene.rotateItem(...)`、`scene.resizeItem(...)` 等图片 API 工作。
- `crop` 路径本身就是 image-only，这一部分保持不动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: N/A（PointerResizeState / PointerRotateState / PointerDragState）
// 功能说明: 修改前平台控制器里的 transform / drag 状态仍只接受图片 item ID，text item 不能被当成可拖拽可缩放对象。
private struct PointerResizeState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasSelectionHandleRole
    let referenceCenter: CGPoint
    let referenceRotationRadians: CGFloat
    let initialLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumScale: CGFloat
}

private struct PointerRotateState {
    let itemID: CanvasImageItemID
    let referenceCenter: CGPoint
    let rotationOffsetToPointerAngle: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改前平台 click log 把 body 命中目标写死成 `image`，文本项即使被命中也不会走“普通 item”语义。
var affectedItemID: CanvasImageItemID?

switch pressContext.targetKind {
case .selectedItemBody, .unselectedItemBody:
    if let itemID = pressContext.targetItemID,
       releasedItemID == itemID
    {
        clickTarget = "image"
        affectedItemID = itemID
        selectItem(
            withID: itemID,
            recordHistory: true
        )
        if previousSelectedItemID != itemID {
            clickResult = "image_selected"
        }
    }
case .blank:
    if releasedItemID == nil {
        clearSelectionIfNeeded(recordHistory: true)
        if previousSelectedItemID != nil {
            clickResult = "image_deselected"
        }
    }
default:
    break
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: makePointerRotateState(itemID:initialViewportLocation:) / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改前 rotation / move / resize 的主体都还是图片 API，因此 text item 不能进入这些共享几何交互路径。
private func makePointerRotateState(
    itemID: CanvasImageItemID,
    initialViewportLocation: CGPoint
) -> PointerRotateState? {
    guard
        inlineEditState == nil,
        let item = scene.item(withID: itemID)
    else {
        return nil
    }
    // ... 省略角度计算 ...
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.item(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldBounds)
    }
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedLocalFrame = makeResizedLocalFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    guard let resizedItem = scene.resizeItem(
        withID: resizeState.itemID,
        toCenter: resizedCenter,
        size: resizedLocalFrame.size
    ) else {
        return
    }

    expandBoardIfNeeded(toInclude: resizedItem.worldBounds)
}
```

### 修改后

- pointer resize / rotate / drag state 改用 `CanvasItemID`。
- 单击日志和结果文本也改成 item-neutral 的 `"item"` / `"item_selected"` / `"item_deselected"`。
- 旋转、移动、缩放统一切到 `scene.boardItem(...)`、`scene.rotateBoardItem(...)`、`scene.resizeBoardItem(...)`。
- `crop` 相关状态与函数仍然保留 `CanvasImageItemID`，明确维持 image-only 边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: N/A（PointerResizeState / PointerRotateState / PointerDragState）
// 功能说明: 修改后平台控制器已经把非 crop 的 pointer 交互状态提升到 board-item 级别，文本项可以进入 drag / resize / rotate 流程。
private struct PointerResizeState {
    let itemID: CanvasItemID
    let handleRole: CanvasSelectionHandleRole
    let referenceCenter: CGPoint
    let referenceRotationRadians: CGFloat
    let initialLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumScale: CGFloat
}

private struct PointerRotateState {
    let itemID: CanvasItemID
    let referenceCenter: CGPoint
    let rotationOffsetToPointerAngle: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasContextMenuContext
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:)
// 功能说明: 修改后 body hit-test 的点击日志不再把目标写死成 image；text item 会以普通 item 的身份走 select / deselect。
var affectedItemID: CanvasItemID?

switch pressContext.targetKind {
case .selectedItemBody, .unselectedItemBody:
    if let itemID = pressContext.targetItemID,
       releasedItemID == itemID
    {
        clickTarget = "item"
        affectedItemID = itemID
        selectItem(
            withID: itemID,
            recordHistory: true
        )
        if previousSelectedItemID != itemID {
            clickResult = "item_selected"
        }
    }
case .blank:
    if releasedItemID == nil {
        clearSelectionIfNeeded(recordHistory: true)
        if previousSelectedItemID != nil {
            clickResult = "item_deselected"
        }
    }
default:
    break
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: makePointerRotateState(itemID:initialViewportLocation:) / commitRotationDraftIfNeeded() / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改后 image/text 都能复用相同的 rotation / move / resize 几何路径；只有 crop 仍保留 image-only API。
private func makePointerRotateState(
    itemID: CanvasItemID,
    initialViewportLocation: CGPoint
) -> PointerRotateState? {
    guard
        inlineEditState == nil,
        let item = scene.boardItem(withID: itemID)
    else {
        return nil
    }
    // ... 省略角度计算 ...
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.boardItem(withID: rotationPreviewState.itemID)
    else {
        return
    }

    guard let rotatedItem = scene.rotateBoardItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
}

private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.boardItem(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldBounds)
    }
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedLocalFrame = makeResizedLocalFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.boardItem(withID: resizeState.itemID)
    else {
        return
    }

    guard let resizedItem = scene.resizeBoardItem(
        withID: resizeState.itemID,
        toCenter: resizedCenter,
        size: resizedLocalFrame.size
    ) else {
        return
    }

    expandBoardIfNeeded(toInclude: resizedItem.worldBounds)
}
```

## 验证

```text
// 验证说明: 本阶段完成后，对相关共享层 / 平台层执行 IDE lints 检查，并对全部 Swift 源文件执行 swiftc typecheck；
//           另外额外编写了一个本地 smoke test（验证完成后已删除），确认 text payload / selection overlay / hit-test / rotation preview 能成立。
- ReadLints:
  - `MyCanvas_Ver_0/Canvas/Core/`
  - `MyCanvas_Ver_0/Canvas/Editing/`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/`
  - `MyCanvas_Ver_0/Platform/macOS/`
  - `MyCanvas_Ver_0/Platform/iOS/`
  - 结果：无错误

- swiftc -typecheck:
  - 范围：`MyCanvas_Ver_0` 下全部 `.swift` 源文件
  - 结果：通过

- 本地 smoke test（临时脚本，不纳入仓库）:
  - 验证点：text-only scene 会生成 `CanvasRenderPayload.text`
  - 验证点：selected text item 会生成 selection overlay 与 resize handles
  - 验证点：`CanvasContextResolver` 可将文本 body 命中为 `selectedItemBody`
  - 验证点：`CanvasRotationPreviewState` 会影响文本 render snapshot 的旋转角度
  - 结果：通过
```
