# 20260317_130710_unified_editoverlay_crop_eight_handles_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 中，把统一 edit handle 集从 `cornerHandles` 扩成 `handles`，并将 `crop` handle role 从四角扩成八向。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中，为 `crop` overlay 生成四角 + 四边中点共 8 个 handle，而 `selection` / `rotate` 继续只生成四角。
  3. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 与 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中，改为从统一 `handles` 集合读取并绘制 `crop` / `selection` handle。
  4. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 与 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中，更新 handle 命中与 crop 拖拽求解，使边中点 handle 只影响单轴，角点 handle 继续影响双轴。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - 逐项手动 UI 回归实测

## 修改一：共享 handle 模型从四角扩成八向 crop

### 修改前

- `CanvasEditRenderOverlay` 只暴露 `cornerHandles`。
- `CanvasCropHandleRole` 只有四个角，shared 层没有边中点 role。
- controller / viewport 只要消费 crop handle，就天然只能围绕四角展开。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditHandleRole / CanvasEditRenderOverlay / CanvasCropHandleRole
// 功能说明: 修改前 unified edit overlay 仍把可交互点视为 cornerHandles，crop 只定义四个角 role。
enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case rotate
}

struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let cornerHandles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

enum CanvasCropHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
```

### 修改后

- 统一 edit overlay 现在暴露 `handles`，不再把接口语义限制在“corner”。
- `CanvasCropHandleRole` 扩成 `top / trailing / bottom / leading` 四个边中点，加上原来的四角，共 8 个 role。
- shared 层补上 role 映射扩展，让 viewport / controller 直接从统一枚举往返映射，不再各自写一份硬编码 switch。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditHandleRole / CanvasEditRenderOverlay / CanvasCropHandleRole
// 功能说明: 修改后 shared 层把 crop handle 扩成八向，并提供统一 role 映射，供 renderer / viewport / controller 共用。
enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
    case rotate
}

struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let handles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

enum CanvasCropHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
}

extension CanvasSelectionHandleRole {
    var editHandleRole: CanvasEditHandleRole {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

extension CanvasCropHandleRole {
    var editHandleRole: CanvasEditHandleRole {
        switch self {
        case .topLeading:
            return .topLeading
        case .top:
            return .top
        case .topTrailing:
            return .topTrailing
        case .trailing:
            return .trailing
        case .bottom:
            return .bottom
        case .leading:
            return .leading
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

extension CanvasEditHandleRole {
    var selectionHandleRole: CanvasSelectionHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .top, .trailing, .bottom, .leading, .rotate:
            return nil
        }
    }

    var cropHandleRole: CanvasCropHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .top:
            return .top
        case .topTrailing:
            return .topTrailing
        case .trailing:
            return .trailing
        case .bottom:
            return .bottom
        case .leading:
            return .leading
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .rotate:
            return nil
        }
    }
}
```

## 修改二：renderer 从“四角专用”改成“按 role 生成 handle”

### 修改前

- `selection` / `crop` / `rotate` 都复用 `makeEditCornerHandles(for:)`。
- 即使 `crop` overlay 已经有独立 kind，也只能拿到四个角的几何信息，没有边中点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeCropEditOverlay(...) / makeEditCornerHandles(for:)
// 功能说明: 修改前 crop overlay 与 selection/rotate 共用四角 handle 生成逻辑，因此 shared 层无法产出边中点 handle。
private func makeCropEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    // 省略前置 guard

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

private func makeEditCornerHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    let rotationRadians = editHandleRotation(for: screenQuad)
    return [
        CanvasEditHandleGeometry(
            role: .topLeading,
            screenCenter: screenQuad.topLeading,
            screenRotationRadians: rotationRadians
        ),
        CanvasEditHandleGeometry(
            role: .topTrailing,
            screenCenter: screenQuad.topTrailing,
            screenRotationRadians: rotationRadians
        ),
        CanvasEditHandleGeometry(
            role: .bottomLeading,
            screenCenter: screenQuad.bottomLeading,
            screenRotationRadians: rotationRadians
        ),
        CanvasEditHandleGeometry(
            role: .bottomTrailing,
            screenCenter: screenQuad.bottomTrailing,
            screenRotationRadians: rotationRadians
        )
    ]
}
```

### 修改后

- `selection` / `rotate` 继续只生成四角，但 `crop` 改为 `makeCropEditHandles(for:)`。
- 新增 `makeEditHandles(for:roles:)` 与 `editHandleCenter(for:in:)`，让不同 overlay 按需声明自己的 handle 集。
- `CanvasQuad` 的 `topMidpoint` / `trailingMidpoint` / `bottomMidpoint` / `leadingMidpoint` 开始真正参与 `crop` handle 生成。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeCropEditOverlay(...) / makeRotateEditOverlay(...) / makeCornerEditHandles(for:) / makeCropEditHandles(for:) / makeEditHandles(for:roles:) / editHandleCenter(for:in:)
// 功能说明: 修改后 renderer 为 crop 单独生成八个 handle，而 selection / rotate 仍保持四角 handle，不扩大已有 resize 语义。
private func makeSelectionEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    // 省略前置 guard

    return CanvasEditRenderOverlay(
        itemID: selectedItemID,
        kind: .selection,
        activeWorldQuad: worldQuad,
        activeScreenQuad: screenQuad,
        handles: makeCornerEditHandles(for: screenQuad),
        payload: .selection
    )
}

private func makeCropEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    // 省略前置 guard

    return CanvasEditRenderOverlay(
        itemID: previewItem.id,
        kind: .crop,
        activeWorldQuad: cropWorldQuad,
        activeScreenQuad: cropScreenQuad,
        handles: makeCropEditHandles(for: cropScreenQuad),
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

private func makeRotateEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasEditRenderOverlay? {
    // 省略前置 guard

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

private func makeCornerEditHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        roles: [
            .topLeading,
            .topTrailing,
            .bottomLeading,
            .bottomTrailing
        ]
    )
}

private func makeCropEditHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        roles: CanvasCropHandleRole.allCases.map(\.editHandleRole)
    )
}

private func makeEditHandles(
    for screenQuad: CanvasQuad,
    roles: [CanvasEditHandleRole]
) -> [CanvasEditHandleGeometry] {
    let rotationRadians = editHandleRotation(for: screenQuad)
    return roles.map { role in
        CanvasEditHandleGeometry(
            role: role,
            screenCenter: editHandleCenter(for: role, in: screenQuad),
            screenRotationRadians: rotationRadians
        )
    }
}

private func editHandleCenter(
    for role: CanvasEditHandleRole,
    in screenQuad: CanvasQuad
) -> CGPoint {
    switch role {
    case .topLeading:
        return screenQuad.topLeading
    case .top:
        return screenQuad.topMidpoint
    case .topTrailing:
        return screenQuad.topTrailing
    case .trailing:
        return screenQuad.trailingMidpoint
    case .bottomTrailing:
        return screenQuad.bottomTrailing
    case .bottom:
        return screenQuad.bottomMidpoint
    case .bottomLeading:
        return screenQuad.bottomLeading
    case .leading:
        return screenQuad.leadingMidpoint
    case .rotate:
        assertionFailure("Rotate handle center is derived separately.")
        return screenQuad.topMidpoint
    }
}
```

## 修改三：viewport 改为从统一 `handles` 集合绘制 crop / selection

### 修改前

- iOS / macOS viewport 都从 `editOverlay.cornerHandles` 中查找 handle。
- `crop` 和 `selection` 还各自维护了一份本地 `editHandleRole(for:)` 映射 helper。
- 当 shared 层要增加边中点 role 时，平台层没有办法直接消费。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:) / refreshSelectionChrome(from:) / editHandleRole(for:)
// 功能说明: 修改前 iOS viewport 只从 cornerHandles 取数据，并在平台层重复维护 role 映射 helper。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    // 省略与本次修改无关的 mask / outline 逻辑
    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.cropHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
    }
}

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.selectionHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
    }
}

private static func editHandleRole(
    for role: CanvasCropHandleRole
) -> CanvasEditHandleRole {
    switch role {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    }
}
```

### 修改后

- iOS / macOS viewport 都直接查 `editOverlay.handles`。
- `CanvasCropHandleRole.editHandleRole` 与 `CanvasSelectionHandleRole.editHandleRole` 从 shared 层下发，平台层不再重复维护映射。
- `CanvasCropHandleRole.allCases` 现在返回 8 个 role，因此 viewport 会自动画出四角 + 四边中点共 8 个 crop handle。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:) / refreshSelectionChrome(from:)
// 功能说明: 修改后 iOS viewport 直接消费统一 handles；当 crop role 扩成八向后，绘制层会自动跟随扩容。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    // 省略与本次修改无关的 mask / outline 逻辑
    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.handles.first(where: {
                $0.role == role.editHandleRole
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.cropHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
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
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:) / refreshSelectionChrome(from:)
// 功能说明: macOS 侧同步改为直接从统一 handles 集合取值，结构与 iOS 对称。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.handles.first(where: {
                $0.role == role.editHandleRole
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.cropHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

## 修改四：controller 命中测试改为消费统一 `handles`

### 修改前

- `crop` 命中只在 `editOverlay.cornerHandles` 中查找。
- `CanvasEditHandleRole -> CanvasCropHandleRole` 与 `CanvasEditHandleRole -> CanvasSelectionHandleRole` 的转换逻辑各平台重复实现。
- 只要 shared 层不是四角结构，平台 hit testing 就会立刻失配。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestEditHandle(at:) / selectionHandleRole(for:) / cropHandleRole(for:)
// 功能说明: 修改前 iOS controller 只命中 cornerHandles，并在平台层手写 role 转换。
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
        // 省略 rotate 命中分支
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
```

### 修改后

- `crop` / `selection` 命中都改为查询 `editOverlay.handles`。
- 统一通过 `handle.role.cropHandleRole` / `handle.role.selectionHandleRole` 读取 shared 映射。
- 当 `crop` 增加边中点 handle 后，controller 命中层可以无额外平台枚举扩展直接接住新 role。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hitTestEditHandle(at:)
// 功能说明: 修改后 iOS controller 从统一 handles 命中 crop / selection handle，并直接消费 shared 层的 role 映射。
private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        guard
            let handle = editOverlay.handles.first(where: { handle in
                Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.cropHandleRole
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
            let handle = editOverlay.handles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.selectionHandleRole
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: hitTestEditHandle(at:)
// 功能说明: macOS 侧同步改为命中统一 handles，并直接消费 shared 层的 role 映射。
private func hitTestEditHandle(at viewportLocation: CGPoint) -> EditHandleHit? {
    guard let editOverlay = lastRenderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        guard
            let handle = editOverlay.handles.first(where: { handle in
                Self.cropHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.cropHandleRole
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
            let handle = editOverlay.handles.first(where: { handle in
                Self.selectionHandleHitRect(centeredAt: handle.screenCenter)
                    .contains(viewportLocation)
            }),
            let role = handle.role.selectionHandleRole
        else {
            return nil
        }

        return .resize(role: role, itemID: editOverlay.itemID)
    }
}
```

## 修改五：crop 拖拽求解从“固定对角点”升级为“按 role 约束 frame”

### 修改前

- `PointerCropState` 保存的是 `fixedOppositeLocalCorner`。
- `updateCropDraft(...)` 先求出一个被约束的“拖拽角点”，再和固定对角点回推裁切矩形。
- 这套算法天然只适合四角；如果是边中点，没有“对角点拖拽”的几何含义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerCropState / makePointerCropState(...) / updateCropDraft(...) / fixedOppositeLocalCorner(for:in:) / constrainedDraggedCropLocalCorner(_:for:oppositeCorner:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改前 iOS crop 拖拽以“固定对角点 + 被拖动角点”为核心模型，因此只覆盖四角 handle。
private struct PointerCropState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasCropHandleRole
    let fullImageLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumLocalSize: CGSize
}

private func makePointerCropState(
    itemID: CanvasImageItemID,
    handleRole: CanvasCropHandleRole
) -> PointerCropState? {
    // 省略前置 guard
    return PointerCropState(
        itemID: itemID,
        handleRole: handleRole,
        fullImageLocalFrame: fullImageLocalFrame,
        fixedOppositeLocalCorner: fixedOppositeLocalCorner(
            for: handleRole,
            in: draftLocalFrame
        ),
        minimumLocalSize: CGSize(
            width: min(minimumLocalDimension, fullImageLocalFrame.width),
            height: min(minimumLocalDimension, fullImageLocalFrame.height)
        )
    )
}

private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) {
    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let constrainedLocalPoint = constrainedDraggedCropLocalCorner(
        draggedLocalPoint,
        for: cropState.handleRole,
        oppositeCorner: cropState.fixedOppositeLocalCorner,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let cropLocalFrame = CGRect(
        x: min(constrainedLocalPoint.x, cropState.fixedOppositeLocalCorner.x),
        y: min(constrainedLocalPoint.y, cropState.fixedOppositeLocalCorner.y),
        width: abs(constrainedLocalPoint.x - cropState.fixedOppositeLocalCorner.x),
        height: abs(constrainedLocalPoint.y - cropState.fixedOppositeLocalCorner.y)
    ).standardized

    inlineEditState.draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
}

private func fixedOppositeLocalCorner(
    for handleRole: CanvasCropHandleRole,
    in localFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
    case .topTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.maxY)
    case .bottomLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.minY)
    case .bottomTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.minY)
    }
}
```

### 修改后

- `PointerCropState` 改为保存 `initialLocalFrame`，即手势开始时的 crop 矩形。
- `updateCropDraft(...)` 直接调用 `constrainedCropLocalFrame(...)` 得到新的本地裁切 frame。
- `constrainedCropLocalFrame(...)` 按 handle role 分别约束：
  - 四角：同时改 `x/y` 或 `width/height`
  - 上下边：只改 `y/height`
  - 左右边：只改 `x/width`
- 这样边中点 handle 可以稳定维持另一轴不变，同时继续遵守图片边界和最小尺寸约束。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerCropState / makePointerCropState(...) / updateCropDraft(...) / constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改后 iOS crop 拖拽以“初始裁切 frame + 当前 role 约束”直接求解新的裁切矩形，可同时支持角点和边中点。
private struct PointerCropState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasCropHandleRole
    let fullImageLocalFrame: CGRect
    let initialLocalFrame: CGRect
    let minimumLocalSize: CGSize
}

private func makePointerCropState(
    itemID: CanvasImageItemID,
    handleRole: CanvasCropHandleRole
) -> PointerCropState? {
    // 省略前置 guard
    return PointerCropState(
        itemID: itemID,
        handleRole: handleRole,
        fullImageLocalFrame: fullImageLocalFrame,
        initialLocalFrame: draftLocalFrame,
        minimumLocalSize: CGSize(
            width: min(minimumLocalDimension, fullImageLocalFrame.width),
            height: min(minimumLocalDimension, fullImageLocalFrame.height)
        )
    )
}

private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) {
    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let cropLocalFrame = constrainedCropLocalFrame(
        draggedLocalPoint,
        for: cropState.handleRole,
        initialLocalFrame: cropState.initialLocalFrame,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
}

private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.maxY - minY
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .topTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottomTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: maxY - initialLocalFrame.minY
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .bottomLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: macOS 侧同步使用同一套八向 crop frame 求解策略，确保双平台交互行为一致。
private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.maxY - minY
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .topTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottomTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: maxY - initialLocalFrame.minY
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .bottomLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

## 验证结果

### lints

- 对以下文件执行 `ReadLints`，结果均为 `No linter errors found.`：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

### 构建验证

```bash
# 功能说明: iOS Simulator Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
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

```bash
# 功能说明: macOS Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
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

## 本次未执行的回归项

- 未逐项手动验证 8 个 crop handle 的真实拖拽体验，包括四边中点是否符合预期热区手感。
- 未逐项手动验证 rotated item 上进入 crop 模式后，8 个 handle 的视觉与拖拽是否都保持正确。
- 未逐项手动验证 undo / redo、autosave、手动保存、重开恢复，以及“单次手势只生成一条历史记录”。
