# 20260722_183936_group_edit_overlay_phase3_record

## 记录来源

- 时间戳来源：系统命令 `date +"%Y%m%d_%H%M%S"`，输出 `20260722_183936`。
- 记录对象：`group-frame-interaction` 阶段 3，渲染选中 group 的 edit overlay。
- 参考范围：当前 `git diff` 与工作区 changes。当前 changes 中仍存在 `.cursor/plans/group-frame-interaction_6e00e0c4.plan.md` 的既有变更，本记录只覆盖刚刚阶段 3 的代码改动。

## 修改概览

阶段 3 的核心变化是让选中的 group 框拥有独立 edit overlay，并在 iOS/macOS 上显示蓝色选中边框和 8 个缩放 handles：

- `CanvasRenderer.makeSnapshot(...)` 新增 `groupInteractionState` 参数。
- `CanvasEditorSession.makeCanvasSnapshot()` 将当前 `groupInteractionState` 传给 renderer。
- renderer 根据 `selectedGroupID` 和合法 `frame` 生成 `CanvasGroupEditOverlay`。
- group overlay 包含 `worldFrame`、`screenFrame` 和 8 个 `CanvasEditHandleGeometry`，不生成 rotate handle。
- iOS/macOS viewport 在 `snapshot.groupEditOverlay` 存在时复用现有 selection outline/handle 图层渲染 group edit chrome。
- group 原有浅灰半透明背景层保持不变，蓝色 overlay 位于 item 之上。

## 修改前后说明

### 1. Renderer 输入：补充 group selection state

修改前，`CanvasRenderer.makeSnapshot(...)` 只接收普通 item selection state。即使 `CanvasEditorSession` 已有 `groupInteractionState`，renderer 也无法知道当前选中了哪个 group。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer.makeSnapshot(...)
// 功能注释：修改前 snapshot 构建只接收 CanvasInteractionState，group 选中态不会进入渲染层。
func makeSnapshot(
    scene: CanvasScene,
    groups: [CanvasItemGroup] = [],
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil,
    alignmentInteractionState: CanvasAlignmentInteractionState? = nil
) -> CanvasRenderSnapshot
```

修改后，renderer 显式接收 `CanvasGroupInteractionState`，为生成 group edit overlay 提供输入。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer.makeSnapshot(...)
// 功能注释：新增 groupInteractionState，让 renderer 能根据 selectedGroupID 生成 group edit overlay。
func makeSnapshot(
    scene: CanvasScene,
    groups: [CanvasItemGroup] = [],
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    groupInteractionState: CanvasGroupInteractionState = CanvasGroupInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil,
    alignmentInteractionState: CanvasAlignmentInteractionState? = nil
) -> CanvasRenderSnapshot
```

### 2. Session 到 renderer 的状态传递

修改前，`CanvasEditorSession.makeCanvasSnapshot()` 没有把 group 选中态传入 renderer，因此选中 group 之后只能看到已有的浅灰 group 框，不能看到选中边框和 handles。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数：CanvasEditorSession.makeCanvasSnapshot()
// 功能注释：修改前 renderer 只拿到 item interactionState，拿不到 groupInteractionState。
let snapshot = renderer.makeSnapshot(
    scene: scene,
    groups: groups,
    boardState: boardState,
    camera: camera,
    interactionState: presentationInteractionState,
    inlineEditState: presentationInlineEditState,
    rotationPreviewState: presentationRotationPreviewState,
    rotationInteractionState: presentationRotationInteractionState,
    alignmentInteractionState: presentationAlignmentInteractionState
)
```

修改后，session 将当前 `groupInteractionState` 传给 renderer，选中 group 后 snapshot 能携带 `groupEditOverlay`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数：CanvasEditorSession.makeCanvasSnapshot()
// 功能注释：把当前 group 选中态输入 renderer，驱动选中 group 的 overlay 渲染。
let snapshot = renderer.makeSnapshot(
    scene: scene,
    groups: groups,
    boardState: boardState,
    camera: camera,
    interactionState: presentationInteractionState,
    groupInteractionState: groupInteractionState,
    inlineEditState: presentationInlineEditState,
    rotationPreviewState: presentationRotationPreviewState,
    rotationInteractionState: presentationRotationInteractionState,
    alignmentInteractionState: presentationAlignmentInteractionState
)
```

### 3. Snapshot 中生成 group edit overlay

修改前，`CanvasRenderSnapshot.groupEditOverlay` 在 renderer 中固定为 `nil`。阶段 2 已经预留了数据入口，但还没有实际生成。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer.makeSnapshot(...)
// 功能注释：修改前 groupEditOverlay 固定为空，viewport 无法绘制 group 选中 chrome。
return CanvasRenderSnapshot(
    viewportBounds: camera.viewportBounds,
    visibleWorldRect: visibleWorldRect,
    workspaceOverlay: workspaceOverlay,
    groups: renderGroups,
    items: renderItems,
    selectionHighlights: selectionHighlights,
    groupEditOverlay: nil,
    editOverlay: editOverlay,
    interactionOverlay: interactionOverlay
)
```

修改后，renderer 会先调用 `makeGroupEditOverlay(...)`，再把结果写入 snapshot。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer.makeSnapshot(...)
// 功能注释：根据当前 selectedGroupID 生成 groupEditOverlay，并交给 viewport 渲染。
let groupEditOverlay = makeGroupEditOverlay(
    groups: groups,
    camera: camera,
    groupInteractionState: groupInteractionState,
    inlineEditState: inlineEditState
)

return CanvasRenderSnapshot(
    viewportBounds: camera.viewportBounds,
    visibleWorldRect: visibleWorldRect,
    workspaceOverlay: workspaceOverlay,
    groups: renderGroups,
    items: renderItems,
    selectionHighlights: selectionHighlights,
    groupEditOverlay: groupEditOverlay,
    editOverlay: editOverlay,
    interactionOverlay: interactionOverlay
)
```

### 4. Group overlay 的生成规则

修改前，没有生成 group overlay 的私有方法，renderer 只负责普通 item selection/crop overlay。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer
// 功能注释：修改前只存在 makeEditOverlay(...)、makeSelectionEditOverlay(...) 等 item 编辑 overlay 构建路径。
private func makeEditOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasEditRenderOverlay?
```

修改后新增 `makeGroupEditOverlay(...)`。它只在非 inline edit、存在 selected group、group 有合法 frame、且 frame 与当前可见区域相交时生成 overlay。handles 使用 `CanvasSelectionHandleRole.allCases`，即 8 个缩放 handle，不包含 rotate。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数：CanvasRenderer.makeGroupEditOverlay(...)
// 功能注释：为选中的 group frame 生成 screen frame 和 8 个 resize handles，不生成 rotate handle。
private func makeGroupEditOverlay(
    groups: [CanvasItemGroup],
    camera: CanvasCamera,
    groupInteractionState: CanvasGroupInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasGroupEditOverlay? {
    guard
        inlineEditState == nil,
        let selectedGroupID = groupInteractionState.selectedGroupID,
        let group = groups.first(where: { $0.id == selectedGroupID }),
        let rawFrame = group.frame
    else {
        return nil
    }

    let worldFrame = rawFrame.standardized
    guard worldFrame.isNull == false,
          worldFrame.isInfinite == false,
          worldFrame.width > 0,
          worldFrame.height > 0,
          worldFrame.intersects(camera.visibleWorldRect)
    else {
        return nil
    }

    let worldQuad = CanvasQuad(rect: worldFrame)
    let screenQuad = camera.worldToViewport(worldQuad)
    let screenFrame = camera.worldToViewport(worldFrame).standardized
    return CanvasGroupEditOverlay(
        groupID: selectedGroupID,
        worldFrame: worldFrame,
        screenFrame: screenFrame,
        handles: makeEditHandles(
            for: screenQuad,
            roles: CanvasSelectionHandleRole.allCases.map(\.editHandleRole)
        )
    )
}
```

### 5. iOS viewport 渲染 group edit overlay

修改前，`iOSCanvasViewportView.refreshEditOverlay()` 只处理普通 `editOverlay`。如果 `snapshot.editOverlay` 为空，就隐藏所有编辑 chrome；`groupEditOverlay` 即使存在也不会被绘制。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.refreshEditOverlay()
// 功能注释：修改前只认普通 item edit overlay，不会渲染 group edit overlay。
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
```

修改后，iOS 会优先处理 `snapshot.groupEditOverlay`。由于 item selection 与 group selection 已互斥，可以复用现有蓝色 selection outline/handle 图层。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.refreshEditOverlay()
// 功能注释：groupEditOverlay 优先渲染，复用 selection chrome，保证 handles 位于 overlay layer。
private func refreshEditOverlay() {
    if let groupEditOverlay = snapshot.groupEditOverlay {
        refreshGroupEditOverlay(from: groupEditOverlay)
        hideCropOverlay()
        return
    }

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
```

### 6. iOS group overlay 具体绘制

修改前，iOS 没有 `refreshGroupEditOverlay(...)`，group 框只有 `groupFramesLayer` 中的浅灰半透明背景。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.refreshGroupFrameLayers()
// 功能注释：修改前只负责渲染 group 背景框，不负责选中态蓝色边框和 handles。
private func refreshGroupFrameLayers() {
    for group in snapshot.groups {
        let layer = groupFrameLayer(for: group.id)
        layer.frame = group.screenFrame
        layer.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
            cornerWidth: Self.groupFrameCornerRadius,
            cornerHeight: Self.groupFrameCornerRadius,
            transform: nil
        )
    }
}
```

修改后，iOS 用 `selectionOutlineLayer` 绘制蓝色圆角边框，用 `selectionHandleLayers` 绘制 8 个 handles，并隐藏 item arrow/rotate 辅助层。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.refreshGroupEditOverlay(...)
// 功能注释：复用现有 selection layer 树渲染 group 选中边框和 8 个缩放 handles。
private func refreshGroupEditOverlay(
    from groupEditOverlay: CanvasGroupEditOverlay
) {
    selectionHighlightsLayer.path = nil
    selectionHighlightsLayer.isHidden = true

    selectionOutlineLayer.path = Self.groupEditOverlayPath(
        for: groupEditOverlay.screenFrame
    )
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = groupEditOverlay.handles.first(where: {
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
            for: role,
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }

    for handleLayer in arrowEndpointHandleLayers.values {
        handleLayer.path = nil
        handleLayer.frame = .zero
        handleLayer.isHidden = true
    }

    hideRotateAffordance()
}
```

### 7. iOS group overlay 边框路径

修改前，group 的圆角只存在于背景框 layer，selection outline 默认使用 item quad path。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.quadPath(for:)
// 功能注释：普通 selection outline 使用四边形路径，不适合 group 的圆角框视觉。
private static func quadPath(for quad: CanvasQuad) -> CGPath {
    let path = UIBezierPath()
    path.move(to: quad.topLeading)
    path.addLine(to: quad.topTrailing)
    path.addLine(to: quad.bottomTrailing)
    path.addLine(to: quad.bottomLeading)
    path.close()
    return path.cgPath
}
```

修改后新增 `groupEditOverlayPath(for:)`，让蓝色选中边框与浅灰 group 背景框保持同样的圆角语义。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数：iOSCanvasViewportView.groupEditOverlayPath(for:)
// 功能注释：为 group 选中态生成圆角蓝色边框路径，并限制 cornerRadius 不超过边长一半。
private static func groupEditOverlayPath(for screenFrame: CGRect) -> CGPath {
    let frame = screenFrame.standardized
    let cornerRadius = min(
        groupFrameCornerRadius,
        min(frame.width, frame.height) / 2
    )
    return UIBezierPath(
        roundedRect: frame,
        cornerRadius: cornerRadius
    ).cgPath
}
```

### 8. macOS viewport 渲染 group edit overlay

修改前，`macOSCanvasViewportView.refreshEditOverlay()` 与 iOS 一样，只处理普通 item edit overlay，group 选中态不会显示蓝色边框和 handles。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.refreshEditOverlay()
// 功能注释：修改前没有 groupEditOverlay 优先分支。
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
```

修改后，macOS 与 iOS 保持一致：优先渲染 `groupEditOverlay`，并隐藏 crop chrome。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.refreshEditOverlay()
// 功能注释：macOS 优先处理 group edit overlay，保证跨平台选中态一致。
private func refreshEditOverlay() {
    if let groupEditOverlay = snapshot.groupEditOverlay {
        refreshGroupEditOverlay(from: groupEditOverlay)
        hideCropOverlay()
        return
    }

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
```

### 9. macOS group overlay 具体绘制

修改前，macOS 只渲染 group 背景框，没有选中态 overlay 绘制方法。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.refreshGroupFrameLayers()
// 功能注释：修改前只在 groupFramesLayer 上绘制浅灰半透明 group 框。
private func refreshGroupFrameLayers() {
    for group in snapshot.groups {
        let layer = groupFrameLayer(for: group.id)
        layer.frame = group.screenFrame
        layer.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
            cornerWidth: Self.groupFrameCornerRadius,
            cornerHeight: Self.groupFrameCornerRadius,
            transform: nil
        )
    }
}
```

修改后，macOS 新增 `refreshGroupEditOverlay(...)`，复用 selection outline/handle layer。这样蓝色边框和 handles 位于 `overlayLayer`，显示在 item 之上。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.refreshGroupEditOverlay(...)
// 功能注释：macOS 复用 selection chrome 渲染 group 选中边框和 8 个缩放 handles。
private func refreshGroupEditOverlay(
    from groupEditOverlay: CanvasGroupEditOverlay
) {
    selectionHighlightsLayer.path = nil
    selectionHighlightsLayer.isHidden = true

    selectionOutlineLayer.path = Self.groupEditOverlayPath(
        for: groupEditOverlay.screenFrame
    )
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = groupEditOverlay.handles.first(where: {
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
            for: role,
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }

    for handleLayer in arrowEndpointHandleLayers.values {
        handleLayer.path = nil
        handleLayer.frame = .zero
        handleLayer.isHidden = true
    }

    hideRotateAffordance()
}
```

### 10. macOS group overlay 边框路径

修改前，macOS selection outline 使用普通 quad path；group 背景框虽有圆角，但选中边框没有独立圆角路径。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.squareHandlePath(...)
// 功能注释：修改前附近只有 handle/selection 的通用路径 helper，没有 group 选中圆角路径 helper。
private static func squareHandlePath(
    centeredAt center: CGPoint,
    size: CGFloat,
    rotationRadians: CGFloat
) -> CGPath
```

修改后新增 macOS 版 `groupEditOverlayPath(for:)`，使用 `CGPath(roundedRect:)` 生成圆角蓝色边框。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数：macOSCanvasViewportView.groupEditOverlayPath(for:)
// 功能注释：macOS 使用 CoreGraphics 圆角路径绘制 group 选中边框。
private static func groupEditOverlayPath(for screenFrame: CGRect) -> CGPath {
    let frame = screenFrame.standardized
    let cornerRadius = min(
        groupFrameCornerRadius,
        min(frame.width, frame.height) / 2
    )
    return CGPath(
        roundedRect: frame,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
}
```

## 验证记录

本次阶段 3 修改完成后已做过以下验证：

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：读取系统时间戳，用于生成本记录文件名和标题。
date +"%Y%m%d_%H%M%S"
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS Simulator 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build
```

验证结果：

- `ReadLints`：无 linter errors。
- macOS build：通过。
- iOS Simulator build：通过。

