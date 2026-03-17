# 20260317_105602_unified_editoverlay_stage2_renderer_selection_rotate_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中让 `selection / rotate` 的 `editOverlay` 由 shared renderer 直接产出。
  2. 保留旧的 `selectionOverlay / rotateOverlay` 输出，但改成从统一 `editOverlay` 兼容派生。
  3. 验证阶段二仍然只落在 shared renderer，不提前改动 viewport / controller。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - iOS / macOS viewport 的 `refreshEditOverlay()` 迁移
  - iOS / macOS controller 的统一 handle 命中迁移
  - crop payload / inline session 的 typed 收口
  - 原始 gif diff
  - git commit / push

## 修改一：让 `makeSnapshot(...)` 先生成统一 `editOverlay`，再兼容派生旧 overlay

### 修改前

- `makeSnapshot(...)` 先分别生成 `selectionOverlay`、`cropOverlay`、`rotateOverlay`。
- 然后通过 `makeEditOverlay(selectionOverlay:cropOverlay:rotateOverlay:)` 把旧 overlay 桥接成 `editOverlay`。
- 这意味着阶段一虽然已经有了统一 `editOverlay` 结构，但 `selection / rotate` 仍不是从 shared 层直接产出，统一 overlay 还不是它们的几何真源。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(selectionOverlay:cropOverlay:rotateOverlay:)
// 功能说明: 修改前 renderer 仍以旧 selection / rotate overlay 为先，editOverlay 只承担桥接兼容角色。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    // ... 省略 renderItems / boardOverlay ...

    let selectionOverlay = makeSelectionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )
    let cropOverlay = makeCropOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    )
    let rotateOverlay = makeRotateOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    )
    let editOverlay = makeEditOverlay(
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay,
        rotateOverlay: rotateOverlay
    )

    return CanvasRenderSnapshot(
        // ... 省略其他字段 ...
        editOverlay: editOverlay,
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay,
        rotateOverlay: rotateOverlay
    )
}

private func makeEditOverlay(
    selectionOverlay: CanvasSelectionRenderOverlay?,
    cropOverlay: CanvasCropRenderOverlay?,
    rotateOverlay: CanvasRotateRenderOverlay?
) -> CanvasEditRenderOverlay? {
    if let cropOverlay {
        return makeEditOverlay(from: cropOverlay)
    }

    if let rotateOverlay {
        return makeEditOverlay(from: rotateOverlay)
    }

    if let selectionOverlay {
        return makeEditOverlay(from: selectionOverlay)
    }

    return nil
}
```

### 修改后

- `makeSnapshot(...)` 现在先保留 `cropOverlay`，因为 crop 统一收口还要等后续阶段。
- shared renderer 新增 `makeEditOverlay(scene:camera:interactionState:inlineEditState:cropOverlay:)`，先直接判断并生成统一 `editOverlay`。
- `selectionOverlay / rotateOverlay` 改成从 `editOverlay` 反向兼容派生。
- 阶段二正式把优先级固化为 `crop > rotate > selection > nil`，让 selection / rotate 共享同一条 shared 输出入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(scene:camera:interactionState:inlineEditState:cropOverlay:)
// 功能说明: 修改后 renderer 先统一产出 editOverlay，再从 editOverlay 兼容导出旧 selection / rotate overlay。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    // ... 省略 renderItems / boardOverlay ...

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
    let selectionOverlay = makeSelectionOverlay(
        from: editOverlay
    )
    let rotateOverlay = makeRotateOverlay(
        from: editOverlay
    )

    return CanvasRenderSnapshot(
        // ... 省略其他字段 ...
        editOverlay: editOverlay,
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay,
        rotateOverlay: rotateOverlay
    )
}

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
```

## 修改二：让 `selection / rotate` 直接在 shared renderer 中生成统一 `editOverlay`

### 修改前

- `makeEditOverlay(from selectionOverlay:)` 只是把旧 `selectionOverlay` 的字段复制到统一模型。
- `makeEditOverlay(from rotateOverlay:)` 只是把旧 `rotateOverlay` 的字段复制到统一模型。
- `screenRotationRadians` 虽然已经在阶段一进入统一 handle 结构，但 selection / rotate 还没有真正把自己的几何与旋转语义收口到 shared renderer 的主生成路径中。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeEditOverlay(from selectionOverlay:) / makeEditOverlay(from rotateOverlay:)
// 功能说明: 修改前 selection / rotate 仍先生成 legacy overlay，再桥接到统一 editOverlay，shared 层没有把它们真正收口为主输出。
private func makeEditOverlay(
    from selectionOverlay: CanvasSelectionRenderOverlay
) -> CanvasEditRenderOverlay {
    CanvasEditRenderOverlay(
        itemID: selectionOverlay.itemID,
        kind: .selection,
        activeWorldQuad: selectionOverlay.worldQuad,
        activeScreenQuad: selectionOverlay.screenQuad,
        cornerHandles: makeEditCornerHandles(
            from: selectionOverlay.handles,
            in: selectionOverlay.screenQuad
        ),
        payload: .selection
    )
}

private func makeEditOverlay(
    from rotateOverlay: CanvasRotateRenderOverlay
) -> CanvasEditRenderOverlay {
    let rotationRadians = editHandleRotation(for: rotateOverlay.screenQuad)
    return CanvasEditRenderOverlay(
        itemID: rotateOverlay.itemID,
        kind: .rotate,
        activeWorldQuad: rotateOverlay.worldQuad,
        activeScreenQuad: rotateOverlay.screenQuad,
        cornerHandles: makeEditCornerHandles(for: rotateOverlay.screenQuad),
        payload: .rotate(
            CanvasEditRotateOverlayPayload(
                guideScreenStart: rotateOverlay.guideScreenStart,
                guideScreenEnd: rotateOverlay.guideScreenEnd,
                handle: CanvasEditHandleGeometry(
                    role: .rotate,
                    screenCenter: rotateOverlay.handle.screenCenter,
                    screenRotationRadians: rotationRadians
                )
            )
        )
    )
}
```

### 修改后

- 新增 `makeSelectionEditOverlay(...)`，直接使用 `scene + interactionState + camera` 生成选中态的统一 overlay。
- 新增 `makeRotateEditOverlay(...)`，直接使用 `inlineEditState + previewedItem(...)` 生成旋转态的统一 overlay。
- 这样 draft rotation 时，outline、corner handles、rotate guide、rotate handle 都由 shared 层同一套几何一起计算。
- `makeEditCornerHandles(for:)` 和 `editHandleRotation(for:)` 继续在 shared 层补齐四角点与旋转手柄的旋转语义，满足阶段二“统一产出 selection / rotate edit overlay”的目标。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeRotateEditOverlay(...)
// 功能说明: 修改后 selection / rotate 直接由 shared renderer 生成统一 editOverlay，成为后续 viewport 迁移的几何真源。
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
        cornerHandles: makeEditCornerHandles(for: screenQuad),
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
        inlineEditState.mode == .rotate,
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
        cornerHandles: makeEditCornerHandles(for: screenQuad),
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
```

## 修改三：把旧 `selectionOverlay / rotateOverlay` 改成从统一 `editOverlay` 兼容派生

### 修改前

- `makeSelectionOverlay(...)` 会重新读取 `selectedItem` 并单独计算 `worldQuad / screenQuad / handles`。
- `makeRotateOverlay(...)` 会重新读取 `inlineEditState` 和 `previewedItem(...)`，再单独计算 guide 与 rotate handle。
- selection 还有 `makeSelectionHandles(for:)`、`selectionHandleCenter(...)`、`makeEditCornerHandles(from selection handles, in:)` 这一整套专用 helper，造成 selection / rotate / editOverlay 间的重复几何链路。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionOverlay(...) / makeRotateOverlay(...) / makeSelectionHandles(for:) / selectionHandleCenter(...)
// 功能说明: 修改前旧 selection / rotate overlay 各自独立计算几何，和统一 editOverlay 并不是同一条真源链路。
private func makeSelectionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasSelectionRenderOverlay? {
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
    let worldFrame = worldQuad.boundingRect.standardized
    let screenQuad = camera.worldToViewport(worldQuad)
    let screenFrame = screenQuad.boundingRect.standardized

    return CanvasSelectionRenderOverlay(
        itemID: selectedItemID,
        worldFrame: worldFrame,
        worldQuad: worldQuad,
        screenFrame: screenFrame,
        screenQuad: screenQuad,
        handles: makeSelectionHandles(for: screenQuad)
    )
}

private func makeRotateOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasRotateRenderOverlay? {
    guard
        let inlineEditState,
        inlineEditState.mode == .rotate,
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

    return CanvasRotateRenderOverlay(
        itemID: previewItem.id,
        mode: inlineEditState.mode,
        worldQuad: worldQuad,
        screenQuad: screenQuad,
        screenCenter: screenCenter,
        guideScreenStart: guideScreenStart,
        guideScreenEnd: guideScreenEnd,
        handle: CanvasRotateHandleGeometry(screenCenter: guideScreenEnd)
    )
}

private func makeSelectionHandles(for screenQuad: CanvasQuad) -> [CanvasSelectionHandleGeometry] {
    CanvasSelectionHandleRole.allCases.map { role in
        CanvasSelectionHandleGeometry(
            role: role,
            screenCenter: selectionHandleCenter(for: role, in: screenQuad)
        )
    }
}

private func selectionHandleCenter(
    for role: CanvasSelectionHandleRole,
    in screenQuad: CanvasQuad
) -> CGPoint {
    switch role {
    case .topLeading:
        return screenQuad.topLeading
    case .topTrailing:
        return screenQuad.topTrailing
    case .bottomLeading:
        return screenQuad.bottomLeading
    case .bottomTrailing:
        return screenQuad.bottomTrailing
    }
}
```

### 修改后

- `makeSelectionOverlay(from:)` 直接消费 `editOverlay.activeWorldQuad / activeScreenQuad / cornerHandles`。
- `makeRotateOverlay(from:)` 直接消费 `editOverlay.payload.rotate`。
- selection 旧模型只保留最小兼容层：`makeSelectionHandles(from cornerHandles:)` 只做 role 映射，不再重新计算几何。
- `selectionHandleCenter(...)` 与 `makeEditCornerHandles(from selection handles, in:)` 被删除，减少 shared 层重复求解。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionOverlay(from:) / makeRotateOverlay(from:) / makeSelectionHandles(from:)
// 功能说明: 修改后旧 overlay 只作为兼容输出层存在，统一 editOverlay 才是 selection / rotate 的 shared 几何真源。
private func makeSelectionOverlay(
    from editOverlay: CanvasEditRenderOverlay?
) -> CanvasSelectionRenderOverlay? {
    guard
        let editOverlay,
        editOverlay.kind == .selection
    else {
        return nil
    }

    return CanvasSelectionRenderOverlay(
        itemID: editOverlay.itemID,
        worldFrame: editOverlay.activeWorldQuad.boundingRect.standardized,
        worldQuad: editOverlay.activeWorldQuad,
        screenFrame: editOverlay.activeScreenQuad.boundingRect.standardized,
        screenQuad: editOverlay.activeScreenQuad,
        handles: makeSelectionHandles(from: editOverlay.cornerHandles)
    )
}

private func makeRotateOverlay(
    from editOverlay: CanvasEditRenderOverlay?
) -> CanvasRotateRenderOverlay? {
    guard
        let editOverlay,
        editOverlay.kind == .rotate,
        case let .rotate(payload) = editOverlay.payload
    else {
        return nil
    }

    return CanvasRotateRenderOverlay(
        itemID: editOverlay.itemID,
        mode: .rotate,
        worldQuad: editOverlay.activeWorldQuad,
        screenQuad: editOverlay.activeScreenQuad,
        screenCenter: editOverlay.activeScreenQuad.center,
        guideScreenStart: payload.guideScreenStart,
        guideScreenEnd: payload.guideScreenEnd,
        handle: CanvasRotateHandleGeometry(screenCenter: payload.handle.screenCenter)
    )
}

private func makeSelectionHandles(
    from cornerHandles: [CanvasEditHandleGeometry]
) -> [CanvasSelectionHandleGeometry] {
    CanvasSelectionHandleRole.allCases.compactMap { role in
        guard
            let handle = cornerHandles.first(where: {
                $0.role == editHandleRole(for: role)
            })
        else {
            return nil
        }

        return CanvasSelectionHandleGeometry(
            role: role,
            screenCenter: handle.screenCenter
        )
    }
}
```

## 影响与边界

- 阶段二后，`selection / rotate` 已经在 shared 层共享同一条 `editOverlay` 输出路径，但平台 viewport 目前仍消费旧的 `selectionOverlay / rotateOverlay`。
- 因为旧 overlay 现在反向派生自 `editOverlay`，所以现有平台显示逻辑不需要在本阶段同步改动，行为仍应保持一致。
- `crop` 本阶段仍然沿用阶段一的桥接方式：`cropOverlay -> editOverlay`。这是刻意保留的边界，避免一次性把 crop session / viewport / controller 一起推进，导致 diff 过大。
- 视觉上“四角方块和高亮框一起旋转”的真正落地仍然要等阶段三，把 iOS / macOS viewport 切到 `refreshEditOverlay()` 后才会显现。

## 验证

```bash
# 功能说明: 阶段二构建验证命令，用于确认 shared renderer 改成“统一 editOverlay 真源”后，iOS / macOS 编译链路仍然通过。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".build_editoverlay_stage2_ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ".build_editoverlay_stage2_macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

- 验证结果：
  - `ReadLints` 对 `CanvasRenderer.swift`、`CanvasRenderSnapshot.swift` 无报错。
  - iOS Simulator Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - macOS Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - `git status` 只显示 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 被修改，符合阶段二只动 shared renderer 的预期。
