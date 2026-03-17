# 20260317_103912_unified_editoverlay_stage1_shared_snapshot_dualwrite_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 为统一 `editOverlay` 建立共享数据骨架。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 增加 `editOverlay` 的双写桥接，让旧的 `selectionOverlay / cropOverlay / rotateOverlay` 继续保留。
  3. 验证阶段一仅落在 shared 层，不提前修改 viewport / controller 的消费逻辑。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - iOS / macOS viewport 绘制迁移
  - iOS / macOS controller 命中测试迁移
  - `CanvasInlineEditState` typed session 改造
  - 原始 gif diff
  - git commit / push

## 修改一：在 shared snapshot 中新增统一 edit overlay 骨架

### 修改前

- `CanvasRenderSnapshot` 只有三条并行链路：`selectionOverlay`、`cropOverlay`、`rotateOverlay`。
- `CanvasSelectionHandleGeometry` 只有 `screenCenter`，还没有“方块与高亮框作为整体旋转”所需的统一 handle 旋转语义。
- shared 层还没有一个同时容纳 selection / rotate / crop 的统一 overlay 类型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasSelectionHandleGeometry / CanvasSelectionRenderOverlay / CanvasRotateRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 仍然是 selection / crop / rotate 三套并行模型，shared 层没有统一的 edit overlay 骨架。
struct CanvasSelectionHandleGeometry {
    let role: CanvasSelectionHandleRole
    let screenCenter: CGPoint
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let worldQuad: CanvasQuad
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let handles: [CanvasSelectionHandleGeometry]
}

struct CanvasRotateHandleGeometry {
    let screenCenter: CGPoint
}

struct CanvasRotateRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let worldQuad: CanvasQuad
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasRotateHandleGeometry
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?
    let rotateOverlay: CanvasRotateRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil,
        cropOverlay: nil,
        rotateOverlay: nil
    )
}
```

### 修改后

- 新增：
  - `CanvasEditOverlayKind`
  - `CanvasEditHandleRole`
  - `CanvasEditHandleGeometry`
  - `CanvasEditRotateOverlayPayload`
  - `CanvasEditCropOverlayPayload`
  - `CanvasEditRenderOverlayPayload`
  - `CanvasEditRenderOverlay`
- `CanvasEditHandleGeometry` 现在除了 `screenCenter` 还携带 `screenRotationRadians`，为后续阶段让四角方块和高亮框同角度显示提供 shared 语义。
- `CanvasRenderSnapshot` 新增 `editOverlay`，但旧的 `selectionOverlay / cropOverlay / rotateOverlay` 仍保留，实现阶段一要求的双写兼容。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditOverlayKind / CanvasEditHandleGeometry / CanvasEditRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 新增统一 edit overlay 骨架，并让 corner handle 自带旋转角度，供后续 viewport / controller 逐步迁移。
struct CanvasSelectionHandleGeometry {
    let role: CanvasSelectionHandleRole
    let screenCenter: CGPoint
}

enum CanvasEditOverlayKind {
    case selection
    case rotate
    case crop
}

enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case rotate
}

// Unified edit handles carry both their anchor point and the current chrome
// rotation so later stages can keep the resize squares visually aligned.
struct CanvasEditHandleGeometry {
    let role: CanvasEditHandleRole
    let screenCenter: CGPoint
    let screenRotationRadians: CGFloat
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

// Edit overlay is the future single source of truth for selection, rotate, and
// crop chrome. Old overlay structs remain during the migration so platforms can
// switch over incrementally.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let cornerHandles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?
    let rotateOverlay: CanvasRotateRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        editOverlay: nil,
        selectionOverlay: nil,
        cropOverlay: nil,
        rotateOverlay: nil
    )
}
```

## 修改二：在 renderer 中双写 edit overlay，而不破坏旧 overlay 输出

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 只会产出旧三套 overlay。
- shared 层没有一个统一桥接函数，把 selection / crop / rotate 映射到新的 `CanvasEditRenderOverlay`。
- 因而后续阶段若想改 viewport / controller，只能先继续直接读旧 overlay。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改前 renderer 只把旧的 selection / crop / rotate overlay 塞进 snapshot，尚未双写 editOverlay。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect
    // ... 省略 renderItems / boardOverlay 未改动代码 ...

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

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay,
        rotateOverlay: rotateOverlay
    )
}
```

### 修改后

- `makeSnapshot(...)` 先生成旧 overlay，再用新的 `makeEditOverlay(...)` 桥接成统一骨架，并把结果写入 `snapshot.editOverlay`。
- 优先级明确为 `crop > rotate > selection > nil`，和当前运行时 overlay 互斥关系保持一致。
- 阶段一没有删除旧 overlay，因而 viewport / controller 仍可以继续读取旧字段，不会引入行为回归。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeEditOverlay(selectionOverlay:cropOverlay:rotateOverlay:)
// 功能说明: 修改后 renderer 在保留旧 overlay 输出的同时，新增 editOverlay 双写桥接，给后续阶段迁移提供统一入口。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect
    // ... 省略 renderItems / boardOverlay 未改动代码 ...

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
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
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

## 修改三：把旧 overlay 几何桥接成统一 edit overlay，并补齐 corner handle 旋转语义

### 修改前

- `selection handles` 与 `crop handles` 都只会生成平台可直接消费的 `screenCenter`。
- `rotate overlay` 只输出 guide 和单独的 rotate handle，shared 层没有把 selection corners、rotate guide、crop full-image quad 归并到同一结构。
- 也没有 shared helper 统一计算 corner handle 的旋转角度。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionHandles(...) / makeCropHandles(...) / selectionHandleCenter(...) / cropHandleCenter(...)
// 功能说明: 修改前 renderer 只输出旧的 handle centers，还没有把它们桥接成统一的 edit handle 几何。
private func makeSelectionHandles(for screenQuad: CanvasQuad) -> [CanvasSelectionHandleGeometry] {
    CanvasSelectionHandleRole.allCases.map { role in
        CanvasSelectionHandleGeometry(
            role: role,
            screenCenter: selectionHandleCenter(for: role, in: screenQuad)
        )
    }
}

private func makeCropHandles(for screenQuad: CanvasQuad) -> [CanvasCropHandleGeometry] {
    CanvasCropHandleRole.allCases.map { role in
        CanvasCropHandleGeometry(
            role: role,
            screenCenter: cropHandleCenter(for: role, in: screenQuad)
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

- 新增三条桥接路径：
  - `makeEditOverlay(from: selectionOverlay)`
  - `makeEditOverlay(from: rotateOverlay)`
  - `makeEditOverlay(from: cropOverlay)`
- 新增统一 helper：
  - `makeEditCornerHandles(from:in:)`
  - `makeEditCornerHandles(for:)`
  - `editHandleRotation(for:)`
  - `editHandleRole(for:)`
- 这样阶段一虽然没有改平台消费层，但 shared 已经能把旧 overlay 的几何如实投影到未来的统一 `editOverlay`：
  - selection: `worldQuad + screenQuad + cornerHandles`
  - rotate: `worldQuad + screenQuad + cornerHandles + rotate payload`
  - crop: `crop quad + cornerHandles + crop payload`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeEditOverlay(from:) / makeEditCornerHandles(...) / editHandleRotation(for:) / editHandleRole(for:)
// 功能说明: 修改后 renderer 把旧 overlay 几何桥接成统一 edit overlay，并为 corner handles 补齐 screenRotationRadians。
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

private func makeEditOverlay(
    from cropOverlay: CanvasCropRenderOverlay
) -> CanvasEditRenderOverlay {
    CanvasEditRenderOverlay(
        itemID: cropOverlay.itemID,
        kind: .crop,
        activeWorldQuad: cropOverlay.cropWorldQuad,
        activeScreenQuad: cropOverlay.cropScreenQuad,
        cornerHandles: makeEditCornerHandles(
            from: cropOverlay.handles,
            in: cropOverlay.cropScreenQuad
        ),
        payload: .crop(
            CanvasEditCropOverlayPayload(
                fullImageWorldQuad: cropOverlay.fullImageWorldQuad,
                fullImageScreenQuad: cropOverlay.fullImageScreenQuad,
                cropRectNormalized: cropOverlay.cropRectNormalized,
                cropWorldQuad: cropOverlay.cropWorldQuad,
                cropScreenQuad: cropOverlay.cropScreenQuad
            )
        )
    )
}

private func makeEditCornerHandles(
    from handles: [CanvasSelectionHandleGeometry],
    in screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    let rotationRadians = editHandleRotation(for: screenQuad)
    return handles.map { handle in
        CanvasEditHandleGeometry(
            role: editHandleRole(for: handle.role),
            screenCenter: handle.screenCenter,
            screenRotationRadians: rotationRadians
        )
    }
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

private func editHandleRotation(
    for screenQuad: CanvasQuad
) -> CGFloat {
    normalizedCanvasAngle(
        atan2(
            screenQuad.topTrailing.y - screenQuad.topLeading.y,
            screenQuad.topTrailing.x - screenQuad.topLeading.x
        )
    )
}
```

## 阶段一结果与边界

- 已完成：
  - shared snapshot 中定义统一 `editOverlay` 骨架。
  - renderer 双写旧 overlay 与新 `editOverlay`。
  - 为 future corner handles 补上 `screenRotationRadians` 语义。
- 明确未做：
  - viewport 还没有消费 `editOverlay`。
  - controller 还没有接 `hitTestEditHandle(...)`。
  - 视觉上四角方块暂时仍不会和高亮框一起旋转，因为平台层还没进入阶段二/三迁移。

## 验证

```bash
# 功能说明: 阶段一构建验证命令，仅验证 shared 改动后的源码编译链路。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".build_editoverlay_stage1_ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ".build_editoverlay_stage1_macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

- 验证结果：
  - `ReadLints` 对 `CanvasRenderSnapshot.swift`、`CanvasRenderer.swift` 无报错。
  - iOS Simulator Debug build 通过。
  - macOS Debug build 通过。
  - `git status` 只显示这两个 shared 文件被修改，符合阶段一只动共享模型层的预期。
