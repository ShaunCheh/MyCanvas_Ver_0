# 20260317_114612_unified_editoverlay_stage5_crop_inline_session_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift` 中把 inline edit state 从“一个 struct 同时挂两种 draft 字段”改为 typed session。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中把 crop 语义直接收口到 `editOverlay.payload.crop`，让 crop 几何从 shared renderer 直接产出。
  3. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 与 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中把 crop 绘制并入统一 `refreshEditOverlay()`。
  4. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 与 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中把 crop handle 命中并入统一 `EditHandleHit + hitTestEditHandle(...)`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 删除旧 `selectionOverlay / rotateOverlay / cropOverlay` 字段
  - 阶段六回归清理
  - 原始 gif diff
  - git commit / push

## 修改一：把 `CanvasInlineEditState` 改成 typed session

### 修改前

- `CanvasInlineEditState` 同时持有 `mode`、`draftCropRectNormalized`、`draftRotationRadians`。
- 即使当前只在 crop mode，rotate draft 也会常驻；反之亦然。
- shared 层只能依靠 `mode` 和调用约定判断哪个 draft 当前有效。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditState
// 功能说明: 修改前同一个 transient edit state 同时持有 crop / rotate 两类 draft，当前模式之外的数据也会长期挂在 state 上。
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var mode: CanvasInlineEditMode
    var draftCropRectNormalized: CanvasImageCropRect
    var draftRotationRadians: CGFloat

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage,
        draftRotationRadians: CGFloat = 0
    ) {
        self.itemID = itemID
        self.mode = mode
        self.draftCropRectNormalized = draftCropRectNormalized
        self.draftRotationRadians = draftRotationRadians
    }
}
```

### 修改后

- 新增 `CanvasInlineCropSession`、`CanvasInlineRotateSession` 和 `CanvasInlineEditSession`。
- `CanvasInlineEditState` 改为 `itemID + session`。
- `cropSession` / `rotateSession` 让 shared 层可以直接按真实模式消费 draft。
- 保留 `mode` / `draftCropRectNormalized` / `draftRotationRadians` 兼容访问口，避免一次性打碎 renderer / controller 的现有调用面。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineCropSession / CanvasInlineRotateSession / CanvasInlineEditSession / CanvasInlineEditState
// 功能说明: 修改后 inline edit state 只持有当前激活模式的 typed session；兼容属性仍保留，用于平滑迁移现有调用点。
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

## 修改二：让 crop 直接由 renderer 产出统一 `editOverlay`

### 修改前

- `makeSnapshot(...)` 先生成旧 `cropOverlay`。
- `makeEditOverlay(...)` 通过 `makeEditOverlay(from: cropOverlay)` 再把 crop 桥接到新 `editOverlay`。
- 这意味着 crop 仍然是“旧 overlay 先生成，新 overlay 后桥接”的链路，`editOverlay` 还不是 crop 的第一真源。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(..., cropOverlay:) / makeCropOverlay(...)
// 功能说明: 修改前 crop 仍先走旧 cropOverlay，再桥接成 editOverlay；统一 edit overlay 对 crop 还不是直接生产者。
let cropOverlay = makeCropOverlay(
    scene: scene,
    camera: camera,
    inlineEditState: inlineEditState
)
let editOverlay = makeEditOverlay(
    scene: scene,
    camera: camera,
    interactionState: interactionState,
    inlineEditState: inlineEditState,
    cropOverlay: cropOverlay,
)

private func makeEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    cropOverlay: CanvasCropRenderOverlay?,
) -> CanvasEditRenderOverlay? {
    if let cropOverlay {
        return makeEditOverlay(from: cropOverlay)
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

private func makeCropOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasCropRenderOverlay? {
    guard
        let inlineEditState,
        inlineEditState.mode == .crop,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        return nil
    }

    // ... 根据 inlineEditState.draftCropRectNormalized 生成 cropOverlay
}
```

### 修改后

- `makeEditOverlay(...)` 现在先尝试 `makeCropEditOverlay(...)`，直接产出 `kind == .crop` 的统一 overlay。
- `makeCropEditOverlay(...)` 直接读取 `inlineEditState.cropSession`，把 `fullImageWorldQuad`、`fullImageScreenQuad`、`cropRectNormalized`、`cropWorldQuad`、`cropScreenQuad` 一次性写进 `.crop` payload。
- 旧 `cropOverlay` 退化成兼容派生层，只从 `editOverlay` 反向生成，便于阶段六删除。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(...) / makeCropEditOverlay(...)
// 功能说明: 修改后 crop 直接由 renderer 产出统一 editOverlay；旧 cropOverlay 仅保留为兼容层。
let editOverlay = makeEditOverlay(
    scene: scene,
    camera: camera,
    interactionState: interactionState,
    inlineEditState: inlineEditState
)
let selectionOverlay = makeSelectionOverlay(
    from: editOverlay
)
let cropOverlay = makeCropOverlay(
    from: editOverlay
)
let rotateOverlay = makeRotateOverlay(
    from: editOverlay
)

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

private func makeCropEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    guard
        let inlineEditState,
        let cropSession = inlineEditState.cropSession,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        return nil
    }

    let previewItem = previewedItem(
        for: item,
        inlineEditState: inlineEditState
    )
    let fullImageWorldQuad = previewItem.fullImageWorldQuad
    let cropWorldQuad = previewItem.worldQuad(
        forNormalizedCropRect: cropSession.draftCropRectNormalized
    )
    let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
    let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

    return CanvasEditRenderOverlay(
        itemID: previewItem.id,
        kind: .crop,
        activeWorldQuad: cropWorldQuad,
        activeScreenQuad: cropScreenQuad,
        cornerHandles: makeEditCornerHandles(for: cropScreenQuad),
        payload: .crop(
            CanvasEditCropOverlayPayload(
                fullImageWorldQuad: fullImageWorldQuad,
                fullImageScreenQuad: fullImageScreenQuad,
                cropRectNormalized: cropSession.draftCropRectNormalized,
                cropWorldQuad: cropWorldQuad,
                cropScreenQuad: cropScreenQuad
            )
        )
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeCropOverlay(from:) / makeRotateEditOverlay(...) / previewedItem(...)
// 功能说明: 修改后旧 cropOverlay 改为从 editOverlay 反向派生；rotate / preview 也开始直接读取 typed session。
private func makeCropOverlay(
    from editOverlay: CanvasEditRenderOverlay?
) -> CanvasCropRenderOverlay? {
    guard
        let editOverlay,
        editOverlay.kind == .crop,
        case let .crop(payload) = editOverlay.payload
    else {
        return nil
    }

    return CanvasCropRenderOverlay(
        itemID: editOverlay.itemID,
        mode: .crop,
        fullImageWorldQuad: payload.fullImageWorldQuad,
        fullImageScreenQuad: payload.fullImageScreenQuad,
        cropRectNormalized: payload.cropRectNormalized,
        cropWorldQuad: payload.cropWorldQuad,
        cropScreenQuad: payload.cropScreenQuad,
        handles: makeCropHandles(from: editOverlay.cornerHandles)
    )
}

// 关键片段: rotate overlay 不再用 mode == .rotate 判断，而是直接检查 typed rotate session。
guard
    let inlineEditState,
    inlineEditState.rotateSession != nil,
    let item = scene.item(withID: inlineEditState.itemID)
else {
    return nil
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

## 修改三：把 crop viewport 绘制并入统一 `refreshEditOverlay()`

### 修改前

- iOS / macOS viewport 都会在 `didMoveToWindow()` 与 `apply(_:)` 中同时调用 `refreshEditOverlay()` 和 `refreshCropOverlay()`。
- `refreshEditOverlay()` 在遇到 `.crop` 时只会 `hideEditOverlay()`。
- 真正的 crop mask / outline / handle 仍然完全依赖 `snapshot.cropOverlay` 单独绘制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshEditOverlay() / refreshCropOverlay()
// 功能说明: 修改前 iOS viewport 虽然已经有 refreshEditOverlay，但 crop 仍单独走 refreshCropOverlay 和 snapshot.cropOverlay。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
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
    case .rotate:
        refreshSelectionChrome(from: editOverlay)
        refreshRotateChrome(from: editOverlay)
    case .crop:
        hideEditOverlay()
    }
}

private func refreshCropOverlay() {
    guard let cropOverlay = snapshot.cropOverlay else {
        hideCropOverlay()
        return
    }

    let maskPath = CGMutablePath()
    maskPath.addPath(Self.quadPath(for: cropOverlay.fullImageScreenQuad))
    maskPath.addPath(Self.quadPath(for: cropOverlay.cropScreenQuad))
    // ... 继续从 cropOverlay.handles 取四个 crop handles
}
```

### 修改后

- iOS / macOS viewport 都只在主刷新路径里调用 `refreshEditOverlay()`，不再单独追加 `refreshCropOverlay()`。
- `refreshEditOverlay()` 在 `.crop` 分支中直接调 `refreshCropChrome(from: editOverlay)`。
- crop mask / outline / handles 统一从 `editOverlay.payload.crop` 与 `editOverlay.cornerHandles` 读取。
- `hideEditOverlay()` 也补齐了 `hideCropOverlay()`，确保三类 edit chrome 的隐藏路径一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshEditOverlay() / refreshCropChrome(from:)
// 功能说明: 修改后 iOS viewport 在 refreshEditOverlay() 内直接分发 crop；mask、outline、corner handle 都从统一 editOverlay 读取。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
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

private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    let maskPath = CGMutablePath()
    maskPath.addPath(Self.quadPath(for: payload.fullImageScreenQuad))
    maskPath.addPath(Self.quadPath(for: payload.cropScreenQuad))

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshEditOverlay() / refreshCropChrome(from:) / hideEditOverlay()
// 功能说明: 修改后 macOS viewport 与 iOS 对齐；crop 进入统一 editOverlay 分发，隐藏路径也与 selection / rotate 统一。
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

private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    let maskPath = CGMutablePath()
    maskPath.addPath(Self.quadPath(for: payload.fullImageScreenQuad))
    maskPath.addPath(Self.quadPath(for: payload.cropScreenQuad))

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
    }
}

private func hideEditOverlay() {
    hideSelectionOverlay()
    hideRotateOverlay()
    hideCropOverlay()
}
```

## 修改四：把 crop handle 命中并入统一 `EditHandleHit`

### 修改前

- `EditHandleHit` 只表达 `.rotate` 和 `.resize`。
- `hitTestEditHandle(...)` 在 `.crop` 分支直接返回 `nil`。
- controller 还保留独立的 `hitTestCropHandle(...)`，`pointerPressTarget(at:)` 也需要先特殊分支处理 crop，再走统一 edit handle 命中。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: EditHandleHit / hitTestEditHandle(at:) / hitTestCropHandle(at:) / pointerPressTarget(at:)
// 功能说明: 修改前 iOS controller 的 crop 命中仍走旧 cropOverlay；统一 edit handle 命中只覆盖 selection / rotate。
private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
}

private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        return nil
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
                .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = selectionHandleRole(for: handle.role)
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func hitTestCropHandle(at viewportLocation: CGPoint) -> (role: CanvasCropHandleRole, itemID: CanvasImageItemID)? {
    guard let cropOverlay = lastRenderSnapshot.cropOverlay else {
        return nil
    }

    return cropOverlay.handles.first(where: { handle in
        Self.cropHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: cropOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineRotateModeActive {
        return .blank
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}
```

### 修改后

- `EditHandleHit` 新增 `.crop(role:itemID:)`，统一承接 crop corner handle 命中。
- `hitTestEditHandle(...)` 在 `.crop` 分支直接读取 `lastRenderSnapshot.editOverlay.cornerHandles`，不再回头依赖旧 `cropOverlay`。
- `pointerPressTarget(at:)` 只需先问一次 `hitTestEditHandle(...)`，再在 inline edit mode 下统一返回 `.blank`，交互入口减少一层分叉。
- 新增 `cropHandleRole(for:)`，把 shared `CanvasEditHandleRole` 映射回现有 `CanvasCropHandleRole`，复用原有 crop drag state。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: EditHandleHit / hitTestEditHandle(at:) / pointerPressTarget(at:) / cropHandleRole(for:)
// 功能说明: 修改后 iOS controller 统一从 editOverlay 命中 crop / rotate / resize handles，crop 不再单独走旧 cropOverlay。
private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case crop(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)

    var pressTarget: PointerPressTarget {
        switch self {
        case let .rotate(itemID):
            return .rotateHandle(itemID: itemID)
        case let .crop(role, itemID):
            return .cropHandle(role: role, itemID: itemID)
        case let .resize(role, itemID):
            return .handle(role: role, itemID: itemID)
        }
    }
}

private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = cropHandleRole(for: handle.role)
        else {
            return nil
        }

        return .crop(role: role, itemID: editOverlay.itemID)
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
                .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = selectionHandleRole(for: handle.role)
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineEditModeActive {
        return .blank
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}

private func cropHandleRole(
    for editHandleRole: CanvasEditHandleRole
) -> CanvasCropHandleRole? {
    switch editHandleRole {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    case .rotate:
        return nil
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: EditHandleHit / hitTestEditHandle(at:) / pointerPressTarget(at:) / cropHandleRole(for:)
// 功能说明: 修改后 macOS controller 与 iOS 对齐，crop handle 命中同样直接走 editOverlay。
private enum EditHandleHit {
    case rotate(itemID: CanvasImageItemID)
    case crop(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case resize(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
}

private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = cropHandleRole(for: handle.role)
        else {
            return nil
        }

        return .crop(role: role, itemID: editOverlay.itemID)
    case .selection, .rotate:
        if
            case let .rotate(payload) = editOverlay.payload,
            Self.rotateHandleHitRect(centeredAt: payload.handle.screenCenter)
                .contains(viewportLocation)
        {
            return .rotate(itemID: editOverlay.itemID)
        }

        guard
            let handle = editOverlay.cornerHandles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = selectionHandleRole(for: handle.role)
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineEditModeActive {
        return .blank
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}
```

## 验证结果

### Lints

- `CanvasInlineEditState.swift`
- `CanvasRenderer.swift`
- `iOSCanvasViewportView.swift`
- `macOSCanvasViewportView.swift`
- `iOSViewController.swift`
- `macOSViewController.swift`

以上文件执行 `ReadLints` 后无报错。

### 构建验证

```bash
# 功能说明: 阶段五 macOS Debug 构建验证
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath ".build/macos" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

- 结果：`Exit code 0`，构建通过。

```bash
# 功能说明: 阶段五 iOS Simulator Debug 构建验证
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ".build/ios-sim" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO
```

- 结果：`Exit code 0`，构建通过。

## 阶段五结果小结

- shared 层现在已经具备统一 `editOverlay + typed inline session` 的 crop 真源。
- viewport 与 controller 对 crop 的消费都已切到 `editOverlay`，阶段六可以专注于删除旧 overlay 字段与重复 helper。
- 旧 `cropOverlay` 仍保留，但它已经降级为兼容派生层，不再是 crop 的主生产链路。
