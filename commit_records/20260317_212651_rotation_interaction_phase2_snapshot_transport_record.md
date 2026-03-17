# 20260317_212651_rotation_interaction_phase2_snapshot_transport_record

## 记录范围

- 记录内容：
  1. 为 canvas render snapshot 新增独立的 `interactionOverlay` 传输通道。
  2. 为旋转交互新增 `CanvasInteractionRenderOverlay` / `CanvasRotationInteractionOverlayPayload` 核心结构。
  3. 扩展 `CanvasRenderer.makeSnapshot(...)`，让 `rotationInteractionState` 可以进入 `renderer -> snapshot` 链路。
  4. 更新 iOS / macOS controller 的刷新入口，向 renderer 传入 `rotationInteractionState`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - iOS / macOS viewport 的 interaction overlay layer 接入
  - 刻度环、角度指针、角度文本的具体绘制
  - 原始 gif diff / git diff / git commit / git push

## 阶段结论

- 这一阶段完成的是“snapshot 传输层扩展”。
- 修改完成后，`rotationInteractionState` 已经可以独立进入 `CanvasRenderer`，并以 `interactionOverlay` 的形式附着在 `CanvasRenderSnapshot` 上。
- 当前还没有接入 viewport 绘制，因此画面暂时不会出现新的角度指示器。

## 修改一：为 CanvasRenderSnapshot 新增独立 interaction overlay 通道

### 修改前

- `CanvasRenderSnapshot` 只有：
  - `boardOverlay`
  - `items`
  - `editOverlay`
- 这意味着所有 transient HUD 如果继续接入，只能继续往 `editOverlay` 里塞，无法和 selection / crop chrome 解耦。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderSnapshot / empty
// 功能说明: 修改前 snapshot 只有 editOverlay，没有独立 interactionOverlay 通道。
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

- 新增：
  - `CanvasInteractionOverlayKind`
  - `CanvasInteractionAngleZeroReference`
  - `CanvasRotationInteractionOverlayPayload`
  - `CanvasInteractionRenderOverlayPayload`
  - `CanvasInteractionRenderOverlay`
- `CanvasRenderSnapshot` 正式新增 `interactionOverlay` 字段。
- `empty` 也同步补上默认空值，保证新通道生命周期和 `editOverlay` 平级但互不耦合。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasInteraction* 结构定义 / CanvasRenderSnapshot / empty
// 功能说明: 修改后新增独立 interaction overlay 通道，专门承载旋转中的瞬时 HUD 数据。
enum CanvasInteractionOverlayKind {
    case rotation
}

enum CanvasInteractionAngleZeroReference {
    case up
}

struct CanvasRotationInteractionOverlayPayload {
    let screenCenter: CGPoint
    let currentRotationRadians: CGFloat
    let zeroReference: CanvasInteractionAngleZeroReference
    let tickStepDegrees: CGFloat
    let ringRadius: CGFloat
    let isActive: Bool

    // 关键点: 在 snapshot 层先提供标准化 0~360 度显示值，避免后续平台侧各自重复换算。
    var displayDegrees0To360: CGFloat {
        let normalizedDegrees = (currentRotationRadians * 180 / .pi)
            .truncatingRemainder(dividingBy: 360)
        return normalizedDegrees >= 0
            ? normalizedDegrees
            : normalizedDegrees + 360
    }
}

enum CanvasInteractionRenderOverlayPayload {
    case rotation(CanvasRotationInteractionOverlayPayload)
}

struct CanvasInteractionRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasInteractionOverlayKind
    let payload: CanvasInteractionRenderOverlayPayload
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

## 修改二：扩展 CanvasRenderer.makeSnapshot(...)，并行生成 editOverlay 与 interactionOverlay

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 只接收 `rotationPreviewState`，不接收 `rotationInteractionState`。
- 它只会生成 `editOverlay`，不会生成任何独立的 interaction HUD 数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改前 renderer 只能产出 editOverlay，无法为独立 HUD 提供 snapshot 传输数据。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil
) -> CanvasRenderSnapshot {
    // ...
    let editOverlay = makeEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
        editOverlay: editOverlay
    )
}
```

### 修改后

- `makeSnapshot(...)` 新增 `rotationInteractionState` 参数。
- renderer 在生成 `editOverlay` 的同时，并行生成 `interactionOverlay`。
- 这一步没有迁移已有 `rotateAffordance`，所以 selection overlay 现有命中测试链路不受影响。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改后 renderer 在保留 editOverlay 的同时，新增 interactionOverlay 传输链路。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil
) -> CanvasRenderSnapshot {
    // ...
    let editOverlay = makeEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let interactionOverlay = makeInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )

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

## 修改三：新增 makeInteractionOverlay(...)，把旋转交互态转换为 snapshot payload

### 修改前

- renderer 里没有任何独立的 interaction overlay helper。
- 旋转相关的 screen-space 几何只会服务于 selection overlay 的 `rotateAffordance`。
- 即使阶段 1 已经有了 `rotationInteractionState`，此时也还不能进入 snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeRotateAffordance(...)
// 功能说明: 修改前旋转相关几何只服务于 selection overlay，没有单独的 HUD 传输 helper。
private func makeSelectionEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasEditRenderOverlay? {
    // ...
    let selectionPayload = CanvasEditSelectionOverlayPayload(
        rotateAffordance: makeRotateAffordance(
            for: presentation,
            camera: camera,
            screenQuad: screenQuad
        )
    )
    // ...
}
```

### 修改后

- 新增 `makeInteractionOverlay(...)`。
- 只在以下条件同时满足时生成 interaction overlay：
  - 不处于 crop inline edit
  - 当前存在 `rotationInteractionState`
  - 当前选中项和 `rotationInteractionState.itemID` 一致
  - scene 中能找到对应 item
- 传输层先把 HUD 所需的关键字段收口为：
  - `screenCenter`
  - `currentRotationRadians`
  - `zeroReference = .up`
  - `tickStepDegrees = 10`
  - `ringRadius`
  - `isActive = true`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeInteractionOverlay(...)
// 功能说明: 修改后 renderer 能把独立旋转交互态转换成 interactionOverlay payload，供后续 viewport 绘制使用。
private func makeInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?
) -> CanvasInteractionRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let rotationInteractionState,
        interactionState.selectedItemID == rotationInteractionState.itemID,
        let item = scene.item(withID: rotationInteractionState.itemID)
    else {
        return nil
    }

    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let screenQuad = camera.worldToViewport(presentation.visibleWorldQuad)
    let rotateAffordance = makeRotateAffordance(
        for: presentation,
        camera: camera,
        screenQuad: screenQuad
    )
    let screenCenter = camera.worldToViewport(item.center)

    return CanvasInteractionRenderOverlay(
        itemID: presentation.itemID,
        kind: .rotation,
        payload: .rotation(
            CanvasRotationInteractionOverlayPayload(
                screenCenter: screenCenter,
                currentRotationRadians: presentation.effectiveRotationRadians,
                zeroReference: .up,
                tickStepDegrees: Self.rotationInteractionTickStepDegrees,
                // 关键点: 当前先复用旋转手柄距离作为环半径的初始传输值。
                ringRadius: distance(
                    from: screenCenter,
                    to: rotateAffordance.handle.screenCenter
                ),
                isActive: true
            )
        )
    )
}
```

同时新增一个固定的 tick step 常量，避免后面平台侧各自硬编码：

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: CanvasRenderer 常量区
// 功能说明: 修改后把交互态刻度步进常量放到 renderer，共享给 interactionOverlay payload。
struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28
    private static let rotationInteractionTickStepDegrees: CGFloat = 10
    // ...
}
```

## 修改四：iOS / macOS controller 刷新入口把 rotationInteractionState 传入 renderer

### 修改前

- 两个平台 controller 虽然已经在阶段 1 内部维护了 `rotationInteractionState`，但刷新 canvas 时没有把它传入 renderer。
- 这导致 renderer / snapshot 仍然感知不到独立交互态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:)
// 功能说明: 修改前 iOS 刷新入口没有把 rotationInteractionState 传入 renderer。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshCanvas()
// 功能说明: 修改前 macOS 刷新入口同样没有把 rotationInteractionState 传入 renderer。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

### 修改后

- iOS / macOS 都把 `rotationInteractionState` 传进 `renderer.makeSnapshot(...)`。
- 阶段 1 的状态边界拆分，至此真正进入了 renderer / snapshot 主链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:)
// 功能说明: 修改后 iOS 刷新入口把独立旋转交互态传入 renderer，让其可进入 snapshot。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshCanvas()
// 功能说明: 修改后 macOS 刷新入口也同步传入独立旋转交互态，保持双端链路一致。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

## 本阶段完成后的代码行为

1. `rotationInteractionState` 不再只停留在 controller 内部，而是可以被 renderer 消费。
2. snapshot 已经可以独立承载 `interactionOverlay`，无需继续把 HUD 数据塞回 selection overlay。
3. 当前 selection overlay 的 `rotateAffordance` 与现有 hit-test 链路保持不变。
4. 由于 viewport 还没有消费 `snapshot.interactionOverlay`，所以当前仍不会显示刻度环或角度文本。

## 校验结果

- 对以下文件执行过 lint 检查，未发现新增错误：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 尝试执行 `xcodebuild` 做工程级校验时失败，原因是当前 active developer directory 指向 `CommandLineTools`，不是完整 Xcode 环境，因此本阶段未完成构建验证。
