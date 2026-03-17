# 20260317_170554_remove_independent_rotate_mode_blue_selection_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift` 中，将 `CanvasInlineEditState` 从“`crop + rotate` 双模式”收缩为 `crop-only`，并新增 `CanvasRotationPreviewState` 承载旋转草稿。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 与 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中，删除独立 `rotate` overlay kind，改为由 `selection` payload 内嵌 `rotateAffordance`。
  3. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 与 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中，删除紫色 `rotate` overlay 绘制路径，统一为蓝色 `selection` chrome 自带的旋转引导线与旋转 handle。
  4. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 与 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中，删除 `rotateButton` 与 `rotate mode` 切换语义，把旋转交互改为“选中态直接拖动旋转 handle”，并使用 `rotationPreviewState` 做 transient preview。
  5. 补齐 `restore / undo / redo / selection sync` 对 `rotationPreviewState` 的清理。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - 手动 UI 交互回归实测

## 修改一：`CanvasInlineEditState` 改为 crop-only，并把旋转草稿拆到独立 preview state

### 修改前

- `inline edit` 同时承载 `crop` 与 `rotate` 两种 session。
- 旋转预览依赖 `inlineEditState.mode == .rotate`，旋转草稿直接保存在 `inlineEditState.draftRotationRadians`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditMode / CanvasInlineRotateSession / CanvasInlineEditSession / CanvasInlineEditState
// 功能说明: 修改前 shared inline edit 同时维护 crop 与 rotate 两套 session，rotate draft 直接挂在 inline edit state 上。
enum CanvasInlineEditMode: Equatable {
    case crop
    case rotate
}

struct CanvasInlineCropSession {
    var draftCropRectNormalized: CanvasImageCropRect
}

struct CanvasInlineRotateSession {
    var draftRotationRadians: CGFloat
}

enum CanvasInlineEditSession {
    case crop(CanvasInlineCropSession)
    case rotate(CanvasInlineRotateSession)

    var mode: CanvasInlineEditMode {
        switch self {
        case .crop:
            return .crop
        case .rotate:
            return .rotate
        }
    }
}

struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var session: CanvasInlineEditSession

    var mode: CanvasInlineEditMode {
        session.mode
    }

    var cropSession: CanvasInlineCropSession? {
        guard case let .crop(cropSession) = session else {
            return nil
        }

        return cropSession
    }

    var rotateSession: CanvasInlineRotateSession? {
        guard case let .rotate(rotateSession) = session else {
            return nil
        }

        return rotateSession
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            guard case let .crop(cropSession) = session else {
                preconditionFailure("Crop draft accessed outside crop inline session.")
            }

            return cropSession.draftCropRectNormalized
        }
        set {
            guard case let .crop(existingSession) = session else {
                preconditionFailure("Crop draft updated outside crop inline session.")
            }

            var cropSession = existingSession
            cropSession.draftCropRectNormalized = newValue
            session = .crop(cropSession)
        }
    }

    var draftRotationRadians: CGFloat {
        get {
            guard case let .rotate(rotateSession) = session else {
                preconditionFailure("Rotation draft accessed outside rotate inline session.")
            }

            return rotateSession.draftRotationRadians
        }
        set {
            guard case let .rotate(existingSession) = session else {
                preconditionFailure("Rotation draft updated outside rotate inline session.")
            }

            var rotateSession = existingSession
            rotateSession.draftRotationRadians = newValue
            session = .rotate(rotateSession)
        }
    }
}
```

### 修改后

- `CanvasInlineEditMode` 只保留 `crop`。
- 新增 `CanvasRotationPreviewState`，让“旋转预览”脱离 `inlineEditState`。
- `CanvasInlineEditState` 只保存 `cropSession` 与 `draftCropRectNormalized`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditMode / CanvasRotationPreviewState / CanvasInlineEditState
// 功能说明: 修改后 inline edit 只承载 crop draft；旋转预览单独存在，避免把 rotate 交互绑成一种 inline mode。
enum CanvasInlineEditMode: Equatable {
    case crop
}

struct CanvasInlineCropSession {
    var draftCropRectNormalized: CanvasImageCropRect
}

// Keep rotation preview separate from crop-only inline edit state so selected
// items can rotate directly without entering a dedicated mode.
struct CanvasRotationPreviewState {
    let itemID: CanvasImageItemID
    var draftRotationRadians: CGFloat
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var cropSession: CanvasInlineCropSession

    var mode: CanvasInlineEditMode {
        .crop
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            return cropSession.draftCropRectNormalized
        }
        set {
            cropSession.draftCropRectNormalized = newValue
        }
    }

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage
    ) {
        self.itemID = itemID
        switch mode {
        case .crop:
            cropSession = CanvasInlineCropSession(
                draftCropRectNormalized: draftCropRectNormalized
            )
        }
    }
}
```

## 修改二：shared overlay contract 不再暴露独立 `rotate` kind

### 修改前

- `CanvasEditOverlayKind` 里有独立的 `.rotate`。
- `CanvasEditRenderOverlayPayload` 也有独立的 `.rotate(CanvasEditRotateOverlayPayload)`。
- 这意味着 viewport / controller 需要显式区分“selection overlay”和“rotate overlay”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditOverlayKind / CanvasEditRenderOverlayPayload / CanvasEditRenderOverlay
// 功能说明: 修改前 rotate 作为独立 overlay kind 暴露给 viewport 和 controller。
enum CanvasEditOverlayKind {
    case selection
    case rotate
    case crop
}

struct CanvasEditRotateOverlayPayload {
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasEditHandleGeometry
}

struct CanvasEditCropOverlayPayload {
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
}

enum CanvasEditRenderOverlayPayload {
    case selection
    case rotate(CanvasEditRotateOverlayPayload)
    case crop(CanvasEditCropOverlayPayload)
}

// Edit overlay is now the single shared source of truth for selection, rotate,
// and crop chrome across renderer, viewport, and controller layers.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}
```

### 修改后

- 删除 `.rotate` kind。
- 新增 `CanvasEditSelectionOverlayPayload`，将 `rotateAffordance` 收到 `.selection(...)` payload 内。
- `selection` 成为选中框与旋转 affordance 的统一入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditOverlayKind / CanvasEditSelectionOverlayPayload / CanvasEditRenderOverlayPayload
// 功能说明: 修改后 rotate affordance 并入 selection payload，不再以独立 overlay kind 向外扩散。
enum CanvasEditOverlayKind {
    case selection
    case crop
}

struct CanvasEditRotateOverlayPayload {
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasEditHandleGeometry
}

struct CanvasEditSelectionOverlayPayload {
    let rotateAffordance: CanvasEditRotateOverlayPayload
}

struct CanvasEditCropOverlayPayload {
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
}

enum CanvasEditRenderOverlayPayload {
    case selection(CanvasEditSelectionOverlayPayload)
    case crop(CanvasEditCropOverlayPayload)
}

// Edit overlay is now the single shared source of truth for selection chrome
// (including rotate affordances) and crop chrome across renderer, viewport,
// and controller layers.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}
```

## 修改三：renderer 改为用 `rotationPreviewState` 预览旋转，并把 rotate affordance 并回 selection overlay

### 修改前

- `makeSnapshot()` 只接收 `inlineEditState`。
- `makeEditOverlay()` 会优先生成独立的 `rotateEditOverlay`。
- `previewedItem()` 通过 `inlineEditState.session == .rotate` 决定是否替换 `rotationRadians`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(...) / makeSelectionEditOverlay(...) / makeRotateEditOverlay(...) / previewedItem(...)
// 功能说明: 修改前 renderer 只有进入 rotate inline mode 才会生成独立 rotate overlay，并依赖 inline edit session 做旋转预览。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    let renderItems = visibleItems.map { item in
        makeRenderItem(
            for: item,
            camera: camera,
            inlineEditState: inlineEditState
        )
    }

    let editOverlay = makeEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )

    // 省略与本次修改无关的 boardOverlay / snapshot return 组装逻辑。
}

private func makeEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    if let cropEditOverlay = makeCropEditOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    ) {
        return cropEditOverlay
    }

    if let rotateEditOverlay = makeRotateEditOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    ) {
        return rotateEditOverlay
    }

    if let selectionEditOverlay = makeSelectionEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    ) {
        return selectionEditOverlay
    }

    return nil
}

private func makeSelectionEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let selectedItemID = interactionState.selectedItemID,
        let selectedItem = scene.item(withID: selectedItemID)
    else {
        return nil
    }

    let worldQuad = selectedItem.worldQuad
    let screenQuad = camera.worldToViewport(worldQuad)

    return CanvasEditRenderOverlay(
        itemID: selectedItemID,
        kind: .selection,
        activeWorldQuad: worldQuad,
        activeScreenQuad: screenQuad,
        handles: makeCornerEditHandles(for: screenQuad),
        payload: .selection
    )
}

private func makeRotateEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    guard
        let inlineEditState,
        inlineEditState.rotateSession != nil,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        return nil
    }

    let previewItem = previewedItem(
        for: item,
        inlineEditState: inlineEditState
    )
    let worldQuad = previewItem.worldQuad
    let screenQuad = camera.worldToViewport(worldQuad)
    let screenCenter = camera.worldToViewport(previewItem.center)
    let guideScreenStart = screenQuad.topMidpoint
    let outwardDirection = normalizedDirection(
        from: screenCenter,
        to: guideScreenStart
    )
    let guideScreenEnd = CGPoint(
        x: guideScreenStart.x + (outwardDirection.x * Self.rotateHandleScreenOffset),
        y: guideScreenStart.y + (outwardDirection.y * Self.rotateHandleScreenOffset)
    )
    let rotationRadians = editHandleRotation(for: screenQuad)

    return CanvasEditRenderOverlay(
        itemID: previewItem.id,
        kind: .rotate,
        activeWorldQuad: worldQuad,
        activeScreenQuad: screenQuad,
        handles: makeCornerEditHandles(for: screenQuad),
        payload: .rotate(
            CanvasEditRotateOverlayPayload(
                guideScreenStart: guideScreenStart,
                guideScreenEnd: guideScreenEnd,
                handle: CanvasEditHandleGeometry(
                    role: .rotate,
                    screenCenter: guideScreenEnd,
                    screenRotationRadians: rotationRadians
                )
            )
        )
    )
}

private func previewedItem(
    for item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?
) -> CanvasImageItem {
    guard
        let inlineEditState,
        inlineEditState.itemID == item.id
    else {
        return item
    }

    var previewItem = item
    switch inlineEditState.session {
    case .crop:
        return previewItem
    case let .rotate(rotateSession):
        previewItem.rotationRadians = rotateSession.draftRotationRadians
        return previewItem
    }
}
```

### 修改后

- `makeSnapshot()` 新增 `rotationPreviewState` 输入。
- `makeEditOverlay()` 只保留 `crop` 与 `selection` 两条分支。
- `makeSelectionEditOverlay()` 直接构造 `CanvasEditSelectionOverlayPayload(rotateAffordance: ...)`。
- `previewedItem()` 改为优先读取 `rotationPreviewState`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(...) / makeSelectionEditOverlay(...) / makeRotateAffordance(...) / previewedItem(...)
// 功能说明: 修改后 renderer 把旋转预览从 inline edit 解耦，selection overlay 自身就携带 rotate affordance。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil
) -> CanvasRenderSnapshot {
    let renderItems = visibleItems.map { item in
        makeRenderItem(
            for: item,
            camera: camera,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
    }

    let editOverlay = makeEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )

    // 省略与本次修改无关的 boardOverlay / snapshot return 组装逻辑。
}

private func makeEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasEditRenderOverlay? {
    if let cropEditOverlay = makeCropEditOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    ) {
        return cropEditOverlay
    }

    if let selectionEditOverlay = makeSelectionEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    ) {
        return selectionEditOverlay
    }

    return nil
}

private func makeSelectionEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasEditRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let selectedItemID = interactionState.selectedItemID,
        let selectedItem = scene.item(withID: selectedItemID)
    else {
        return nil
    }

    let previewItem = previewedItem(
        for: selectedItem,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let worldQuad = previewItem.worldQuad
    let screenQuad = camera.worldToViewport(worldQuad)
    let selectionPayload = CanvasEditSelectionOverlayPayload(
        rotateAffordance: makeRotateAffordance(
            for: previewItem,
            camera: camera,
            screenQuad: screenQuad
        )
    )

    return CanvasEditRenderOverlay(
        itemID: previewItem.id,
        kind: .selection,
        activeWorldQuad: worldQuad,
        activeScreenQuad: screenQuad,
        handles: makeCornerEditHandles(for: screenQuad),
        payload: .selection(selectionPayload)
    )
}

private func makeRotateAffordance(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    screenQuad: CanvasQuad
) -> CanvasEditRotateOverlayPayload {
    let screenCenter = camera.worldToViewport(item.center)
    let guideScreenStart = screenQuad.topMidpoint
    let outwardDirection = normalizedDirection(
        from: screenCenter,
        to: guideScreenStart
    )
    let guideScreenEnd = CGPoint(
        x: guideScreenStart.x + (outwardDirection.x * Self.rotateHandleScreenOffset),
        y: guideScreenStart.y + (outwardDirection.y * Self.rotateHandleScreenOffset)
    )
    let rotationRadians = editHandleRotation(for: screenQuad)
    return CanvasEditRotateOverlayPayload(
        guideScreenStart: guideScreenStart,
        guideScreenEnd: guideScreenEnd,
        handle: CanvasEditHandleGeometry(
            role: .rotate,
            screenCenter: guideScreenEnd,
            screenRotationRadians: rotationRadians
        )
    )
}

private func previewedItem(
    for item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasImageItem {
    if
        let inlineEditState,
        inlineEditState.itemID == item.id
    {
        return item
    }

    guard
        let rotationPreviewState,
        rotationPreviewState.itemID == item.id
    else {
        return item
    }

    var previewItem = item
    previewItem.rotationRadians = rotationPreviewState.draftRotationRadians
    return previewItem
}
```

## 修改四：viewport 删除紫色 `rotate` overlay，改为蓝色 `selection` 自带旋转 affordance

### 修改前（iOS）

- viewport 中存在独立的紫色 `rotateOutlineStrokeColor / rotateGuideStrokeColor / rotateHandleFillColor`。
- `refreshEditOverlay()` 里需要显式处理 `.rotate` 分支。
- `refreshRotateChrome()` 与 `hideRotateOverlay()` 独立管理一套 rotate layer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: configureRotateGuideLayer() / configureRotateOutlineLayer() / configureRotateHandleLayer() / refreshEditOverlay() / refreshRotateChrome(...) / hideRotateOverlay()
// 功能说明: 修改前 iOS viewport 仍把 rotate 视为一套单独的紫色 overlay。
private static let rotateOutlineStrokeColor = CGColor(
    red: 175.0 / 255.0,
    green: 82.0 / 255.0,
    blue: 222.0 / 255.0,
    alpha: 1
)
private static let rotateGuideStrokeColor = CGColor(
    red: 175.0 / 255.0,
    green: 82.0 / 255.0,
    blue: 222.0 / 255.0,
    alpha: 0.9
)
private static let rotateHandleFillColor = CGColor(gray: 1, alpha: 1)
private static let rotateOutlineLineWidth: CGFloat = 2

private let rotateOutlineLayer = CAShapeLayer()
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

private func configureRotateGuideLayer() {
    rotateGuideLayer.fillColor = nil
    rotateGuideLayer.strokeColor = Self.rotateGuideStrokeColor
    rotateGuideLayer.lineWidth = Self.rotateGuideLineWidth
    rotateGuideLayer.lineCap = .round
    rotateGuideLayer.isHidden = true
}

private func configureRotateOutlineLayer() {
    rotateOutlineLayer.fillColor = nil
    rotateOutlineLayer.strokeColor = Self.rotateOutlineStrokeColor
    rotateOutlineLayer.lineWidth = Self.rotateOutlineLineWidth
    rotateOutlineLayer.isHidden = true
}

private func configureRotateHandleLayer() {
    rotateHandleLayer.fillColor = Self.rotateHandleFillColor
    rotateHandleLayer.strokeColor = Self.rotateOutlineStrokeColor
    rotateHandleLayer.lineWidth = Self.rotateHandleLineWidth
    rotateHandleLayer.isHidden = true
}

private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideRotateOverlay()
        hideCropOverlay()
    case .rotate:
        refreshSelectionChrome(from: editOverlay)
        refreshRotateChrome(from: editOverlay)
        hideCropOverlay()
    case .crop:
        hideSelectionOverlay()
        hideRotateOverlay()
        refreshCropChrome(from: editOverlay)
    }
}

private func refreshRotateChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .rotate(payload) = editOverlay.payload else {
        hideRotateOverlay()
        return
    }

    let guidePath = CGMutablePath()
    guidePath.move(to: payload.guideScreenStart)
    guidePath.addLine(to: payload.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false

    rotateOutlineLayer.path = nil
    rotateOutlineLayer.isHidden = true

    let handleRect = Self.rotateHandleRect(centeredAt: payload.handle.screenCenter)
    rotateHandleLayer.frame = handleRect
    rotateHandleLayer.path = CGPath(
        ellipseIn: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    rotateHandleLayer.isHidden = false
}

private func hideRotateOverlay() {
    rotateGuideLayer.path = nil
    rotateGuideLayer.isHidden = true
    rotateOutlineLayer.path = nil
    rotateOutlineLayer.isHidden = true
    rotateHandleLayer.path = nil
    rotateHandleLayer.frame = .zero
    rotateHandleLayer.isHidden = true
}
```

### 修改后（iOS）

- 紫色 rotate 颜色与 `rotateOutlineLayer` 被删除。
- `configureRotateGuideLayer()` / `configureRotateHandleLayer()` 改为复用蓝色 `selection` 颜色。
- `refreshSelectionChrome()` 直接消费 `.selection(payload)` 并调用 `refreshRotateAffordance(payload.rotateAffordance)`。
- `hideSelectionOverlay()` 统一隐藏选中框与旋转 affordance。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: configureRotateGuideLayer() / configureRotateHandleLayer() / refreshEditOverlay() / refreshSelectionChrome(...) / refreshRotateAffordance(...) / hideSelectionOverlay()
// 功能说明: 修改后 iOS viewport 用 selection chrome 统一绘制选中框、四角 handle、旋转引导线和旋转 handle。
private func configureRotateGuideLayer() {
    rotateGuideLayer.fillColor = nil
    rotateGuideLayer.strokeColor = Self.selectionStrokeColor
    rotateGuideLayer.lineWidth = Self.rotateGuideLineWidth
    rotateGuideLayer.lineCap = .round
    rotateGuideLayer.isHidden = true
}

private func configureRotateHandleLayer() {
    rotateHandleLayer.fillColor = Self.selectionHandleFillColor
    rotateHandleLayer.strokeColor = Self.selectionStrokeColor
    rotateHandleLayer.lineWidth = Self.rotateHandleLineWidth
    rotateHandleLayer.isHidden = true
}

private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideCropOverlay()
    case .crop:
        hideSelectionOverlay()
        refreshCropChrome(from: editOverlay)
    }
}

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .selection(payload) = editOverlay.payload else {
        hideSelectionOverlay()
        return
    }

    // Selection owns both the outline/resize handles and the rotate
    // affordance so the viewport can keep one coherent blue chrome.
    selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = editOverlay.handles.first(where: {
                $0.role == role.editHandleRole
            })
        else {
            selectionHandleLayers[role]?.path = nil
            selectionHandleLayers[role]?.frame = .zero
            selectionHandleLayers[role]?.isHidden = true
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.selectionHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }

    refreshRotateAffordance(payload.rotateAffordance)
}

private func refreshRotateAffordance(
    _ rotateAffordance: CanvasEditRotateOverlayPayload
) {
    let guidePath = CGMutablePath()
    guidePath.move(to: rotateAffordance.guideScreenStart)
    guidePath.addLine(to: rotateAffordance.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false
    rotateGuideLayer.contentsScale = currentContentsScale

    let handleRect = Self.rotateHandleRect(centeredAt: rotateAffordance.handle.screenCenter)
    rotateHandleLayer.frame = handleRect
    rotateHandleLayer.path = CGPath(
        ellipseIn: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    rotateHandleLayer.isHidden = false
    rotateHandleLayer.contentsScale = currentContentsScale
}

private func hideSelectionOverlay() {
    selectionOutlineLayer.path = nil
    selectionOutlineLayer.isHidden = true

    for handleLayer in selectionHandleLayers.values {
        handleLayer.path = nil
        handleLayer.frame = .zero
        handleLayer.isHidden = true
    }

    rotateGuideLayer.path = nil
    rotateGuideLayer.isHidden = true
    rotateHandleLayer.path = nil
    rotateHandleLayer.frame = .zero
    rotateHandleLayer.isHidden = true
}
```

### 修改后（macOS，同构落地）

- macOS 侧与 iOS 完全对称：同样删除独立 `rotateOutlineLayer` / `.rotate` 分支，改为蓝色 `selection` 自带旋转 affordance。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: configureRotateGuideLayer() / configureRotateHandleLayer() / refreshEditOverlay() / refreshSelectionChrome(...) / refreshRotateAffordance(...) / hideSelectionOverlay()
// 功能说明: macOS viewport 同步改成蓝色 selection chrome 统一承载旋转 affordance。
private func configureRotateGuideLayer() {
    rotateGuideLayer.fillColor = nil
    rotateGuideLayer.strokeColor = Self.selectionStrokeColor
    rotateGuideLayer.lineWidth = Self.rotateGuideLineWidth
    rotateGuideLayer.lineCap = .round
    rotateGuideLayer.isHidden = true
}

private func configureRotateHandleLayer() {
    rotateHandleLayer.fillColor = Self.selectionHandleFillColor
    rotateHandleLayer.strokeColor = Self.selectionStrokeColor
    rotateHandleLayer.lineWidth = Self.rotateHandleLineWidth
    rotateHandleLayer.isHidden = true
}

private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideCropOverlay()
    case .crop:
        hideSelectionOverlay()
        refreshCropChrome(from: editOverlay)
    }
}

private func refreshRotateAffordance(
    _ rotateAffordance: CanvasEditRotateOverlayPayload
) {
    let guidePath = CGMutablePath()
    guidePath.move(to: rotateAffordance.guideScreenStart)
    guidePath.addLine(to: rotateAffordance.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false

    let handleRect = Self.rotateHandleRect(centeredAt: rotateAffordance.handle.screenCenter)
    rotateHandleLayer.frame = handleRect
    rotateHandleLayer.path = CGPath(
        ellipseIn: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    rotateHandleLayer.isHidden = false
}
```

## 修改五：controller 删除 `rotateButton / rotate mode`，改为选中态直接旋转

### 修改前（iOS：按钮入口 + 命中测试 + rotate draft/commit）

- iOS controller 有独立的 `rotateButton` 与 `handleRotateButtonTap()`。
- 旋转命中只认 `.rotate` overlay payload。
- 旋转拖拽与提交都要求 `inlineEditState.mode == .rotate`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupRotateButton() / handleRotateButtonTap() / hitTestEditHandle(...) / makePointerRotateState(...) / updateRotationDraft(...) / commitRotationDraftIfNeeded()
// 功能说明: 修改前 iOS controller 依赖独立 rotate mode 和 rotate button 才能进入旋转链路。
private let rotateButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private func setupRotateButton() {
    rotateButton.addTarget(self, action: #selector(handleRotateButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleRotateButtonTap() {
    if isInlineRotateModeActive {
        endInlineEditMode(reason: "exit rotate mode")
    } else {
        beginRotateModeIfPossible()
    }
}

// hitTestEditHandle(at:) 内部与本次修改直接相关的旧分支摘录：
// rotate handle 只能从独立 .rotate payload 中命中。
case .selection, .rotate:
    if
        case let .rotate(payload) = editOverlay.payload,
        Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
            .contains(viewportLocation)
    {
        return .rotate(itemID: editOverlay.itemID)
    }

private func makePointerRotateState(
    itemID: CanvasImageItemID,
    initialViewportLocation: CGPoint
) -> PointerRotateState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .rotate,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    let initialPointerAngle = angle(
        from: item.center,
        to: camera.viewportToWorld(initialViewportLocation)
    )

    return PointerRotateState(
        itemID: itemID,
        referenceCenter: item.center,
        rotationOffsetToPointerAngle: normalizedCanvasAngle(
            inlineEditState.draftRotationRadians - initialPointerAngle
        )
    )
}

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .rotate,
        inlineEditState.itemID == rotateState.itemID
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )

    inlineEditState.draftRotationRadians = draftRotationRadians
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update rotate draft")
}

private func commitRotationDraftIfNeeded() {
    guard
        let inlineEditState,
        inlineEditState.mode == .rotate,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: inlineEditState.itemID,
        to: inlineEditState.draftRotationRadians
    ) else {
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    self.inlineEditState = CanvasInlineEditState(item: rotatedItem, mode: .rotate)
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}
```

### 修改后（iOS：direct affordance + transient preview）

- `rotateButton` 与 `setupRotateButton()` 被删除，controller 只保留 `cropButton`。
- `hitTestEditHandle()` 改为从 `.selection(payload.rotateAffordance.handle)` 命中旋转 handle。
- `makePointerRotateState()` / `updateRotationDraft()` / `commitRotationDraftIfNeeded()` 改为使用 `rotationPreviewState`。
- `displayedRotationRadians(for:)` 负责把“已提交角度”和“未提交预览角度”统一成 controller 当前显示值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupViewHierarchy() / hitTestEditHandle(...) / makePointerRotateState(...) / updateRotationDraft(...) / commitRotationDraftIfNeeded() / displayedRotationRadians(...) / clearRotationPreviewState()
// 功能说明: 修改后 iOS controller 不再进入 rotate mode；只要当前不是 crop inline mode，就能直接拖动 selection 上的旋转 handle。
private let cropButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private let canvasViewportView = iOSCanvasViewportView()
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var inlineEditState: CanvasInlineEditState?
private var rotationPreviewState: CanvasRotationPreviewState?

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(cropButton)
    view.addSubview(undoButton)
    view.addSubview(redoButton)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

// hitTestEditHandle(at:) 内部与本次修改直接相关的新分支摘录：
// rotate handle 改为从 selection payload 里的 rotateAffordance 命中。
case .selection:
    guard case let .selection(payload) = editOverlay.payload else {
        return nil
    }

    if Self.rotateHandleHitRect(centeredAt: payload.rotateAffordance.handle.screenCenter)
        .contains(viewportLocation)
    {
        return .rotate(itemID: editOverlay.itemID)
    }

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

    let initialPointerAngle = angle(
        from: item.center,
        to: camera.viewportToWorld(initialViewportLocation)
    )

    return PointerRotateState(
        itemID: itemID,
        referenceCenter: item.center,
        rotationOffsetToPointerAngle: normalizedCanvasAngle(
            displayedRotationRadians(for: item) - initialPointerAngle
        )
    )
}

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    requestCanvasRefresh(reason: "update rotate draft")
}

private func commitRotationDraftIfNeeded() {
    guard
        let rotationPreviewState,
        let item = scene.item(withID: rotationPreviewState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard !anglesMatch(item.rotationRadians, rotationPreviewState.draftRotationRadians) else {
        clearRotationPreviewState()
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: rotationPreviewState.itemID,
        to: rotationPreviewState.draftRotationRadians
    ) else {
        clearRotationPreviewState()
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    self.rotationPreviewState = nil
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func displayedRotationRadians(for item: CanvasImageItem) -> CGFloat {
    guard
        let rotationPreviewState,
        rotationPreviewState.itemID == item.id
    else {
        return item.rotationRadians
    }

    return rotationPreviewState.draftRotationRadians
}

private func clearRotationPreviewState() {
    rotationPreviewState = nil
}
```

### 修改后（macOS，同构落地）

- macOS controller 同步去掉 `rotateButton` / `handleRotateButtonClick()`，并把 rotate hit-test 与 preview/commit 链路切到 `rotationPreviewState`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestEditHandle(...) / makePointerRotateState(...) / updateRotationDraft(...) / commitRotationDraftIfNeeded() / displayedRotationRadians(...) / clearRotationPreviewState()
// 功能说明: macOS controller 与 iOS 同步改成“selection affordance + transient preview”的旋转链路。
private var inlineEditState: CanvasInlineEditState?
private var rotationPreviewState: CanvasRotationPreviewState?

// hitTestEditHandle(at:) 内部与本次修改直接相关的新分支摘录：
// rotate handle 改为从 selection payload 里的 rotateAffordance 命中。
case .selection:
    guard case let .selection(payload) = editOverlay.payload else {
        return nil
    }

    if Self.rotateHandleHitRect(centeredAt: payload.rotateAffordance.handle.screenCenter)
        .contains(viewportLocation)
    {
        return .rotate(itemID: editOverlay.itemID)
    }

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        inlineEditState == nil,
        let item = scene.item(withID: rotateState.itemID)
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        displayedRotationRadians(for: item),
        draftRotationRadians
    ) else {
        return
    }

    rotationPreviewState = CanvasRotationPreviewState(
        itemID: rotateState.itemID,
        draftRotationRadians: draftRotationRadians
    )
    refreshCanvas()
}
```

## 修改六：`restore / history / selection sync` 主动清理 `rotationPreviewState`，并彻底移除 rotate mode 语义

### 修改前

- `applyBoardRuntimeState()` / `applyBoardHistorySnapshot()` 不会清理旋转 preview。
- `beginCropModeIfPossible()` 需要先排除 `isInlineRotateModeActive`。
- 仍然存在 `beginRotateModeIfPossible()`、`updateRotateButtonAppearance()`、`applyRotateButtonAppearance()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardRuntimeState(...) / applyBoardHistorySnapshot(...) / beginCropModeIfPossible() / beginRotateModeIfPossible() / syncInlineEditStateWithSelection() / updateInlineEditButtonsAppearance() / updateCropButtonAppearance() / updateRotateButtonAppearance()
// 功能说明: 修改前 controller 生命周期和按钮状态仍然保留 rotate mode 语义。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private var isInlineRotateModeActive: Bool {
    inlineEditState?.mode == .rotate
}

private func beginCropModeIfPossible() {
    guard
        !isInlineRotateModeActive,
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "enter crop mode")
}

private func beginRotateModeIfPossible() {
    guard
        !isInlineCropModeActive,
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .rotate)
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "enter rotate mode")
}

private func syncInlineEditStateWithSelection() {
    guard let inlineEditState else {
        updateInlineEditButtonsAppearance()
        return
    }

    guard interactionState.selectedItemID == inlineEditState.itemID else {
        self.inlineEditState = nil
        updateInlineEditButtonsAppearance()
        return
    }
}

private func updateInlineEditButtonsAppearance() {
    updateCropButtonAppearance()
    updateRotateButtonAppearance()
    updateHistoryButtonsAppearance()
}

private func updateCropButtonAppearance() {
    let isActive = isInlineCropModeActive
    let isEnabled = isActive || (interactionState.selectedItemID != nil && !isInlineRotateModeActive)
    applyCropButtonAppearance(
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        backgroundColor: isActive ? .systemOrange : .systemIndigo,
        isEnabled: isEnabled
    )
}

private func updateRotateButtonAppearance() {
    let isActive = isInlineRotateModeActive
    let isEnabled = isActive || (interactionState.selectedItemID != nil && !isInlineCropModeActive)
    applyRotateButtonAppearance(
        title: isActive ? "Done" : "Rotate",
        systemImageName: isActive ? "checkmark" : "rotate.right",
        backgroundColor: isActive ? .systemPurple : .systemTeal,
        isEnabled: isEnabled
    )
}
```

### 修改后

- `applyBoardRuntimeState()` / `applyBoardHistorySnapshot()` 显式清理 `rotationPreviewState`。
- `beginCropModeIfPossible()` 进入 crop 前先 `clearRotationPreviewState()`。
- `syncInlineEditStateWithSelection()` 会在选中项切换时清理 preview。
- `updateInlineEditButtonsAppearance()` 只维护 `cropButton` 与 history 按钮，不再存在 rotate mode 按钮语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyBoardRuntimeState(...) / applyBoardHistorySnapshot(...) / beginCropModeIfPossible() / syncInlineEditStateWithSelection() / updateInlineEditButtonsAppearance() / updateCropButtonAppearance()
// 功能说明: 修改后 controller 生命周期明确把 rotation preview 当成 transient state 清理；UI 只保留 crop 独占模式。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    rotationPreviewState = nil
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
        rotationPreviewState = nil
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    clearRotationPreviewState()
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    requestCanvasRefresh(reason: "enter crop mode")
}

private func syncInlineEditStateWithSelection() {
    if
        let rotationPreviewState,
        interactionState.selectedItemID != rotationPreviewState.itemID
    {
        clearRotationPreviewState()
    }

    guard let inlineEditState else {
        updateInlineEditButtonsAppearance()
        return
    }

    guard interactionState.selectedItemID == inlineEditState.itemID else {
        self.inlineEditState = nil
        updateInlineEditButtonsAppearance()
        return
    }

    if let item = scene.item(withID: inlineEditState.itemID) {
        self.inlineEditState = CanvasInlineEditState(item: item, mode: inlineEditState.mode)
    }
    updateInlineEditButtonsAppearance()
}

private func updateInlineEditButtonsAppearance() {
    updateCropButtonAppearance()
    updateHistoryButtonsAppearance()
}

private func updateCropButtonAppearance() {
    let isActive = isInlineCropModeActive
    let isEnabled = isActive || interactionState.selectedItemID != nil
    applyCropButtonAppearance(
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        backgroundColor: isActive ? .systemOrange : .systemIndigo,
        isEnabled: isEnabled
    )
}
```

### 修改后（macOS，同构落地）

- macOS 同步去掉 `beginRotateModeIfPossible()` / `updateRotateButtonAppearance()` / `applyRotateButtonAppearance()`，并在 runtime restore / history restore / selection sync 里清理 `rotationPreviewState`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyBoardRuntimeState(...) / applyBoardHistorySnapshot(...) / beginCropModeIfPossible() / syncInlineEditStateWithSelection() / updateInlineEditButtonsAppearance() / updateCropButtonAppearance()
// 功能说明: macOS controller 同步收缩为“crop-only inline edit + transient rotation preview”。
private func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    rotationPreviewState = nil
    updateInlineEditButtonsAppearance()
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
        rotationPreviewState = nil
    }

    refreshCanvas()
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    clearRotationPreviewState()
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateInlineEditButtonsAppearance()
    refreshCanvas()
}

private func updateInlineEditButtonsAppearance() {
    updateCropButtonAppearance()
}
```

## 验证结果

- `ReadLints`：本次涉及的 7 个源码文件当前均为 `No linter errors found.`。
- 本轮实现中已完成双平台构建验证：
  - iOS Simulator Debug：构建通过。
  - macOS Debug：构建通过。
- 本记录只复述已完成的构建结果，本次未再次重跑手动 UI 回归。

