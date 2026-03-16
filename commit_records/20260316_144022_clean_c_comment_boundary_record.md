# 20260316_144022_clean_c_comment_boundary_record

## 记录范围

- 记录内容：
  1. 为“干净的方案 C”相关模块补充职责边界注释，明确 shared core、viewport、controller、scene 的分工。
  2. 强化后续维护时的阅读指引，避免把 selection 语义、平台视觉和数据写入职责重新耦合。
  3. 本次仅新增注释，不修改任何运行时逻辑、交互结果、持久化模型或保存链路。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：新的 handle 功能、额外视觉参数调整、持久化 schema 变化、原始 gif diff。

## 修改一：为共享渲染模型补充“语义几何 vs 图片内容”职责注释

### 修改前

- `CanvasRenderItem` 与 `CanvasSelectionRenderOverlay` 在结构上已经分离，但代码里没有显式说明这种 clean C 边界。
- `CanvasImageLayer` 虽然已经只负责图片内容渲染，但没有注释提醒后续不要把选中框和 handle 再塞回 image layer。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderItem / CanvasSelectionRenderOverlay
// 功能说明: 修改前共享渲染模型已经分离图片内容和 selection overlay，但没有明确的职责边界注释。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasSelectionHandleGeometry]
}

// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: CanvasImageLayer
// 功能说明: 修改前 CanvasImageLayer 只承载图片 layer，但没有注释提醒不要重新耦合 selection chrome。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
}
```

### 修改后

- 在 `CanvasRenderSnapshot.swift` 中明确说明：`CanvasRenderItem` 只承载图片渲染数据，`CanvasSelectionRenderOverlay` 承载平台无关的 selection 语义几何。
- 在 `CanvasImageLayer.swift` 中明确说明：选中态视觉属于 viewport overlay，不应回流到 per-item image layer。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderItem / CanvasSelectionRenderOverlay
// 功能说明: 修改后显式说明 item 只承载图片渲染数据，selection chrome 独立随 overlay 传递。
// Render items stay focused on image content. Selection chrome travels separately
// so platform overlays and interaction state do not leak into per-item rendering.
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasSelectionRenderOverlay
// 功能说明: 修改后显式说明共享 selection geometry 保持平台无关，平台层自己决定视觉尺寸与命中热区。
// Shared selection geometry is intentionally platform-neutral: it describes what
// is selected and where it is, while each platform decides visual size and hit slop.
struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasSelectionHandleGeometry]
}

// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: CanvasImageLayer
// 功能说明: 修改后显式说明 CanvasImageLayer 只画图片内容，选中态视觉继续留在 viewport overlay。
// Image layers only render image content. Selection visuals live in viewport
// overlays so shared render items stay free of platform-specific chrome.
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
}
```

## 修改二：为 renderer / scene 补充“单一来源 / 统一写入入口”注释

### 修改前

- `CanvasRenderer.makeSelectionOverlay(...)` 已经承担 selection overlay 生成职责，但没有直接声明它应成为 selection geometry 的唯一来源。
- `CanvasScene.resizeItem(withID:to:)` 已经是统一写入入口，但没有注释强调 controller 只负责交互编排，scene 负责真正的数据写入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionOverlay(scene:camera:interactionState:)
// 功能说明: 修改前 renderer 已负责生成 selection overlay，但没有注释明确它是 selection geometry 的唯一来源。
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
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:)
// 功能说明: 修改前 scene 已提供统一 resize 写入入口，但没有注释强调 controller 只编排、scene 负责落数据。
@discardableResult
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        )
        item.size = standardizedFrame.size
        return item
    }
}
```

### 修改后

- 在 renderer 侧明确写出“selection geometry 单一来源”的原则，避免后续从 platform layer 状态反推命中几何。
- 在 scene 侧明确写出“controller 只算拖拽几何，scene 统一负责写入”的原则，防止平台各自散落写入逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionOverlay(scene:camera:interactionState:)
// 功能说明: 修改后显式说明 renderer 是 selection geometry 的唯一来源，绘制与命中都应消费同一份语义几何。
// Renderer is the single source of truth for selection geometry so drawing
// and hit testing stay aligned without consulting platform layer state.
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
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:)
// 功能说明: 修改后显式说明 controller 负责 pointer 几何编排，而 scene 继续作为统一的 resize 写入入口。
@discardableResult
// Controllers own pointer math, but Scene remains the shared mutation entry
// point for resizing so platform flows write geometry the same way.
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        )
        item.size = standardizedFrame.size
        return item
    }
}
```

## 修改三：为 iOS / macOS viewport 补充“只消费语义几何”的注释

### 修改前

- iOS / macOS 的 `refreshSelectionOverlay()` 都已经只消费 `snapshot.selectionOverlay` 来绘制选中框与四角 handle。
- 但代码里没有直接说明：viewport 只负责平台视觉表达，不参与 selection 语义计算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay()
// 功能说明: 修改前 iOS viewport 已根据 selectionOverlay 绘制选中框与 handle，但没有注释说明视觉职责留在 viewport。
private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay()
// 功能说明: 修改前 macOS viewport 同样直接消费 selectionOverlay，但没有注释强调平台样式只应停留在 viewport。
private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    // ... 省略未改动代码 ...
}
```

### 修改后

- 在两端 viewport 的同名函数中补充一致的职责注释，明确平台层只消费 neutral geometry，并在本地决定视觉尺寸、线宽和 contentsScale。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay()
// 功能说明: 修改后显式说明 iOS viewport 只消费 renderer 产出的中性几何，iOS 平台视觉细节仍停留在这里。
private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    // The viewport owns selection presentation details; it only consumes the
    // renderer's neutral geometry and applies iOS-specific visuals here.
    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay()
// 功能说明: 修改后显式说明 macOS viewport 只消费 renderer 产出的中性几何，macOS 平台视觉细节仍停留在这里。
private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    // The viewport owns selection presentation details; it only consumes the
    // renderer's neutral geometry and applies macOS-specific visuals here.
    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    // ... 省略未改动代码 ...
}
```

## 修改四：为 iOS / macOS controller 补充交互优先级与 resize 编排注释

### 修改前

- 两端 controller 已经按照 `handle > item body > blank` 的顺序做命中，也已经按“controller 算几何、scene 写入”的路径做 resize。
- 但这些 clean C 约束只体现在代码结构里，没有被注释明确写出来，后续扩展时容易被误改。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: pointerPressTarget(at:)
// 功能说明: 修改前 iOS 已按 handle 优先命中，但没有注释明确这种优先级属于编辑器级交互约束。
private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resizeSelectedItem(using:to:) / makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改前 iOS 已遵循 controller 算拖拽几何、scene 写入、固定对角点等比缩放，但没有显式注释说明原因。
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }
    // ... 省略未改动代码 ...
}

private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: pointerPressTarget(at:) / resizeSelectedItem(using:to:) / makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改前 macOS 对应函数与 iOS 同步承担同样职责，但同样缺少交互边界说明注释。
private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }
    // ... 省略未改动代码 ...
}

private func resizeSelectedItem(using resizeState: PointerResizeState, to viewportLocation: CGPoint) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }
    // ... 省略未改动代码 ...
}

private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    // ... 省略未改动代码 ...
}
```

### 修改后

- 在 `pointerPressTarget(at:)` 上补充注释，明确 `handle > body > blank` 是与常见编辑器保持一致的交互优先级。
- 在 `resizeSelectedItem(using:to:)` 上补充注释，明确 controller 负责拖拽几何编排，scene 负责统一写入。
- 在 `makeResizedWorldFrame(...)` 上补充注释，明确等比缩放依赖“固定对角点 + 取较大轴 scale”的规则。
- macOS 对应函数同步增加同样语义的注释，保持双端行为和后续维护方向一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: pointerPressTarget(at:)
// 功能说明: 修改后显式说明 handle 命中优先级高于 body / blank，避免后续扩展时破坏编辑器交互手感。
// Keep interaction priority aligned with common editors: resize handles win
// over body hits so a visible handle is always the first-class press target.
private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resizeSelectedItem(using:to:)
// 功能说明: 修改后显式说明 controller 负责拖拽几何编排，而 scene 继续承担统一 resize 写入职责。
// Controllers solve drag geometry, but Scene still performs the write so
// move/resize mutations follow one shared data path across platforms.
private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改后显式说明等比缩放依赖固定对角点，并用较大轴 scale 保持比例稳定。
// Keep the opposite corner fixed and use the larger axis scale so resizing
// stays proportional regardless of drag direction.
private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: pointerPressTarget(at:) / resizeSelectedItem(using:to:) / makeResizedWorldFrame(using:draggedViewportLocation:)
// 功能说明: 修改后 macOS 在对应函数同步加入相同职责注释，保持双端 clean C 约束一致。
// Keep interaction priority aligned with common editors: resize handles win
// over body hits so a visible handle is always the first-class press target.
private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }
    // ... 省略未改动代码 ...
}

// Controllers solve drag geometry, but Scene still performs the write so
// move/resize mutations follow one shared data path across platforms.
private func resizeSelectedItem(using resizeState: PointerResizeState, to viewportLocation: CGPoint) {
    guard
        let resizedWorldFrame = makeResizedWorldFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }
    // ... 省略未改动代码 ...
}

// Keep the opposite corner fixed and use the larger axis scale so resizing
// stays proportional regardless of drag direction.
private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    // ... 省略未改动代码 ...
}
```

## 校验情况

- 已对上述 8 个文件执行 `ReadLints` 检查。
- 结果：`No linter errors found.`
- 本次记录对应的是注释补充，不包含额外的运行时逻辑改动。
