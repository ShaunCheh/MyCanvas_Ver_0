# 20260317_124021_unified_editoverlay_stage6_cleanup_regression_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift` 中删除旧的 `selectionOverlay / cropOverlay / rotateOverlay` 类型与字段，只保留统一 `editOverlay`。
  2. 在 `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift` 中删除旧 overlay 的兼容派生逻辑与重复 helper，让 renderer 完全只围绕 `CanvasEditRenderOverlay` 工作。
  3. 通过搜索、lints 与双平台构建验证阶段六清理后的代码状态。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - viewport / controller 的新增功能修改
  - 原始 gif diff
  - git commit / push
  - 未实际执行的手动交互回归

## 修改一：在 `CanvasRenderSnapshot.swift` 中删除旧 overlay 类型族

### 修改前

- `CanvasRenderSnapshot.swift` 同时保留了新 `CanvasEditRenderOverlay`，以及旧的 selection / crop / rotate overlay 结构。
- 这些旧类型已经只承担兼容作用，不再是平台层的主消费入口，但仍然占据 shared 层接口面。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasSelectionHandleGeometry / CanvasSelectionRenderOverlay / CanvasCropHandleGeometry / CanvasCropRenderOverlay / CanvasRotateHandleGeometry / CanvasRotateRenderOverlay
// 功能说明: 修改前 shared 层仍保留 selection / crop / rotate 的旧 overlay 类型，作为 editOverlay 迁移过程中的兼容结构。
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

struct CanvasCropHandleGeometry {
    let role: CanvasCropHandleRole
    let screenCenter: CGPoint
}

struct CanvasCropRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
    let handles: [CanvasCropHandleGeometry]
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
```

### 修改后

- `CanvasRenderSnapshot.swift` 只保留统一的 `CanvasEditHandleGeometry`、`CanvasEditRenderOverlayPayload`、`CanvasEditRenderOverlay`。
- 注释也从“future single source of truth”更新为“now the single shared source of truth”，明确迁移已收口完成。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasEditHandleGeometry / CanvasEditRotateOverlayPayload / CanvasEditCropOverlayPayload / CanvasEditRenderOverlayPayload / CanvasEditRenderOverlay
// 功能说明: 修改后 shared 层只保留统一 edit overlay 类型族，selection / rotate / crop 都通过一个 payload 入口描述。
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

// Edit overlay is now the single shared source of truth for selection, rotate,
// and crop chrome across renderer, viewport, and controller layers.
struct CanvasEditRenderOverlay {
    let itemID: CanvasImageItemID
    let kind: CanvasEditOverlayKind
    let activeWorldQuad: CanvasQuad
    let activeScreenQuad: CanvasQuad
    let cornerHandles: [CanvasEditHandleGeometry]
    let payload: CanvasEditRenderOverlayPayload
}
```

## 修改二：在 `CanvasRenderSnapshot` 中删除旧字段，只保留 `editOverlay`

### 修改前

- `CanvasRenderSnapshot` 同时暴露四条编辑几何链路：
  - `editOverlay`
  - `selectionOverlay`
  - `cropOverlay`
  - `rotateOverlay`
- `CanvasRenderSnapshot.empty` 也要同步维护四个字段的空值。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 仍双写旧 overlay 字段，platform 层即使已迁移，也还要背负兼容接口。
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

### 修改后

- `CanvasRenderSnapshot` 现在只保留 `editOverlay`。
- `empty` 也同步收窄为唯一的统一 overlay 空值。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 只保留统一 editOverlay，shared 层不再暴露旧的 selection / crop / rotate overlay 字段。
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

## 修改三：在 `CanvasRenderer.makeSnapshot(...)` 中去掉旧 overlay 双写

### 修改前

- `makeSnapshot(...)` 在生成 `editOverlay` 后，还会继续从它派生：
  - `selectionOverlay`
  - `cropOverlay`
  - `rotateOverlay`
- 最后把四条编辑链路一起塞进 `CanvasRenderSnapshot`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改前 renderer 在统一 editOverlay 之外，仍继续派生旧 overlay 字段并写回 snapshot。
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
```

### 修改后

- `makeSnapshot(...)` 现在只生成并返回 `editOverlay`。
- renderer 不再承担“统一 overlay -> 旧 overlay”的兼容派生职责。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...)
// 功能说明: 修改后 renderer 只负责生产统一 editOverlay，再直接写入 snapshot。
let editOverlay = makeEditOverlay(
    scene: scene,
    camera: camera,
    interactionState: interactionState,
    inlineEditState: inlineEditState
)

return CanvasRenderSnapshot(
    viewportBounds: camera.viewportBounds,
    visibleWorldRect: visibleWorldRect,
    boardOverlay: boardOverlay,
    items: renderItems,
    editOverlay: editOverlay
)
```

## 修改四：在 `CanvasRenderer` 中删除旧 overlay 派生 helper 与重复 helper

### 修改前

- `CanvasRenderer.swift` 内仍保留大量只为兼容旧 overlay 而存在的 helper：
  - `makeSelectionOverlay(from:)`
  - `makeCropOverlay(from:)`
  - `makeRotateOverlay(from:)`
  - `makeSelectionHandles(from:)`
  - `makeCropHandles(from:)`
  - `editHandleRole(for: CanvasSelectionHandleRole)`
  - `editHandleRole(for: CanvasCropHandleRole)`
  - `cropHandleCenter(for:in:)`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionOverlay(from:) / makeCropOverlay(from:) / makeRotateOverlay(from:)
// 功能说明: 修改前 renderer 仍维护旧 overlay 派生链，把统一 editOverlay 再次转换回 selection / crop / rotate 三套旧结构。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionHandles(from:) / makeCropHandles(from:) / editHandleRole(for:) / cropHandleCenter(for:in:)
// 功能说明: 修改前 renderer 还维护旧 handle geometry 转换逻辑，只为服务已迁出的旧 overlay 类型。
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

private func makeCropHandles(
    from cornerHandles: [CanvasEditHandleGeometry]
) -> [CanvasCropHandleGeometry] {
    CanvasCropHandleRole.allCases.compactMap { role in
        guard
            let handle = cornerHandles.first(where: {
                $0.role == editHandleRole(for: role)
            })
        else {
            return nil
        }

        return CanvasCropHandleGeometry(
            role: role,
            screenCenter: handle.screenCenter
        )
    }
}

private func editHandleRole(
    for role: CanvasSelectionHandleRole
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

private func editHandleRole(
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

private func cropHandleCenter(
    for role: CanvasCropHandleRole,
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

- 这些兼容 helper 已全部删除。
- `CanvasRenderer` 现在只保留真正服务于统一 `editOverlay` 的几何 helper，例如：
  - `makeEditCornerHandles(for:)`
  - `editHandleRotation(for:)`
  - `previewedItem(for:inlineEditState:)`
- shared 层的辅助函数边界明显缩小，文件结构也更贴近当前真实架构。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeEditCornerHandles(for:) / editHandleRotation(for:) / previewedItem(for:inlineEditState:)
// 功能说明: 修改后 renderer 只保留统一 editOverlay 所需的 helper，不再保留旧 overlay 派生与旧 geometry 转换逻辑。
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

## 验证结果

### 变更范围确认

```bash
# 功能说明: 确认阶段六实际修改文件范围
git status --short
```

- 结果：当前阶段六源码改动只落在以下两个文件。
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`

### 搜索验证

```bash
# 功能说明: 确认旧 overlay 字段、旧 overlay 类型、旧 helper 已无残留引用
rg "selectionOverlay|cropOverlay|rotateOverlay|CanvasSelectionRenderOverlay|CanvasCropRenderOverlay|CanvasRotateRenderOverlay|CanvasSelectionHandleGeometry|CanvasCropHandleGeometry|CanvasRotateHandleGeometry" MyCanvas_Ver_0 --glob "*.swift"
```

- 结果：无匹配。

```bash
# 功能说明: 确认平台层也已无旧 refresh/hitTest 入口残留
rg "refreshSelectionOverlay|refreshCropOverlay|refreshRotateOverlay|hitTestSelectionHandle|hitTestCropHandle|hitTestRotateHandle" MyCanvas_Ver_0/Platform --glob "*.swift"
```

- 结果：无匹配。

### Lints

- `ReadLints` 检查以下文件后无报错：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`

### 构建验证

```bash
# 功能说明: iOS Simulator Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数
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
# 功能说明: macOS Debug 构建验证；沿用工作区内 derivedDataPath
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

### 本次未执行的回归项

- 阶段六计划里提到的手动交互回归，本次**未逐项实际执行**，包括但不限于：
  - 普通选中
  - 空白取消选中
  - 旋转后 resize
  - rotate mode 拖拽中方块是否跟框同角度
  - crop on rotated item
  - undo/redo
  - autosave
  - 手动保存
  - 重开恢复
  - 单次手势只生成一条历史记录

## 本次修改结论

- 阶段六完成后，shared 层已经不存在旧 `selectionOverlay / cropOverlay / rotateOverlay` 兼容壳。
- `CanvasRenderSnapshot` 与 `CanvasRenderer` 的接口面已经真正收口为统一 `editOverlay`。
- viewport / controller 早先阶段的迁移结果，在阶段六清理后仍能通过搜索与双平台构建验证，说明统一链路已经闭合。
