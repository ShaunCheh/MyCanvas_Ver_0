# 20260330_183124_ios_indirect_pan_phase2_record

## 记录范围

- 记录内容：
  1. 在 `iOSViewController` 中接入 `canvasViewportView.onPan`。
  2. 新增 `handleIndirectPan(_:)`，消费阶段 1 视图层上报的 `delta`。
  3. 抽取 `applyCanvasPan(_:refreshReason:)`，统一 direct pan / indirect pan 的相机平移逻辑。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 阶段 3 的冲突保护逻辑
  - 阶段 4 的方向校正与运行时手感验证
  - 新的 git commit / push

## 修改一：在 setupCanvasViewport() 中接入 onPan

### 修改前

- `setupCanvasViewport()` 只接了 `pointer`、`longPress`、`zoom`、`viewportSizeChange`。
- 视图层虽然在阶段 1 已经有了 `onPan`，但控制器层还没有消费入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport()
// 功能说明: 修改前控制器层还没有把视图层的 onPan 接到平移处理逻辑上。
private func setupCanvasViewport() {
    canvasViewportView.shouldAutoplayAnimatedImages =
        editorSession.shouldAutoplayAnimatedImagesOnCanvas
    canvasViewportView.resolveAnimatedImagePlaybackSource = { [weak self] assetReference in
        self?.editorSession.animatedImagePlaybackSource(for: assetReference)
    }
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }
}
```

### 修改后

- 新增 `canvasViewportView.onPan = { ... }`。
- 视图层上报的 indirect pan `translation` 现在会进入 `handleIndirectPan(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport()
// 功能说明: 修改后控制器层显式接入 onPan，让 indirect pan 可以进入后续的相机平移链路。
private func setupCanvasViewport() {
    canvasViewportView.shouldAutoplayAnimatedImages =
        editorSession.shouldAutoplayAnimatedImagesOnCanvas
    canvasViewportView.resolveAnimatedImagePlaybackSource = { [weak self] assetReference in
        self?.editorSession.animatedImagePlaybackSource(for: assetReference)
    }
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }
}
```

## 修改二：新增 handleIndirectPan(_:) 作为 indirect pan 的控制器入口

### 修改前

- `hasExceededPointerDragActivationDistance(...)` 后面直接进入 `handleZoom(_:)`。
- 控制器层没有 `handleIndirectPan(_:)`，indirect pan 还没有自己的消费入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hasExceededPointerDragActivationDistance(from:to:) / handleZoom(_:around:)
// 功能说明: 修改前控制器层只有缩放入口，没有独立的 indirect pan 入口。
private func hasExceededPointerDragActivationDistance(
    from pressedLocation: CGPoint,
    to currentLocation: CGPoint
) -> Bool {
    let dx = currentLocation.x - pressedLocation.x
    let dy = currentLocation.y - pressedLocation.y
    let distanceSquared = (dx * dx) + (dy * dy)
    let thresholdSquared = Self.pointerDragActivationDistance * Self.pointerDragActivationDistance
    return distanceSquared >= thresholdSquared
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    )
    scheduleAutosave(reason: "zoom canvas")
}
```

### 修改后

- 新增 `handleIndirectPan(_:)`。
- 当前阶段它不做额外保护，只把 `translation` 转交给统一的 `applyCanvasPan(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: hasExceededPointerDragActivationDistance(from:to:) / handleIndirectPan(_:) / handleZoom(_:around:)
// 功能说明: 修改后新增 indirect pan 控制器入口，并把其平移逻辑收口到 applyCanvasPan(...)。
private func hasExceededPointerDragActivationDistance(
    from pressedLocation: CGPoint,
    to currentLocation: CGPoint
) -> Bool {
    let dx = currentLocation.x - pressedLocation.x
    let dy = currentLocation.y - pressedLocation.y
    let distanceSquared = (dx * dx) + (dy * dy)
    let thresholdSquared = Self.pointerDragActivationDistance * Self.pointerDragActivationDistance
    return distanceSquared >= thresholdSquared
}

private func handleIndirectPan(_ translation: CGPoint) {
    applyCanvasPan(
        translation,
        refreshReason: "indirect pan \(describe(point: translation))"
    )
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    )
    scheduleAutosave(reason: "zoom canvas")
}
```

## 修改三：抽取 applyCanvasPan(...)，统一 direct pan / indirect pan 的平移逻辑

### 修改前

- `panCanvas(from:to:)` 自己负责计算位移、更新 camera、写日志、刷新画布、触发 autosave。
- 这意味着如果要新增 indirect pan，就会重复一套几乎相同的平移逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: panCanvas(from:to:)
// 功能说明: 修改前 direct touch 的画布平移逻辑全部写在 panCanvas(...) 内部，尚未抽成公共入口。
private func panCanvas(from previousLocation: CGPoint, to location: CGPoint) {
    let translation = CGPoint(
        x: location.x - previousLocation.x,
        y: location.y - previousLocation.y
    )
    guard translation != .zero else {
        return
    }

    let cameraCenterBeforePan = camera.center
    camera.pan(by: translation)
    logPanDispatch(
        translation: translation,
        cameraCenterBeforePan: cameraCenterBeforePan,
        cameraCenterAfterPan: camera.center
    )
    requestCanvasRefresh(reason: "pan \(describe(point: translation))")
    scheduleAutosave(reason: "pan canvas")
}
```

### 修改后

- `panCanvas(from:to:)` 现在只负责从两个点计算 `translation`。
- 真正的相机平移逻辑被抽到 `applyCanvasPan(_:refreshReason:)`，供 direct pan / indirect pan 复用。
- `requestCanvasRefresh(...)` 的 `reason` 也被参数化，便于区分 direct / indirect 的日志来源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: panCanvas(from:to:) / applyCanvasPan(_:refreshReason:)
// 功能说明: 修改后 panCanvas(...) 只计算 direct touch 位移，公共的 camera 平移、刷新与 autosave 统一收口到 applyCanvasPan(...)。
private func panCanvas(from previousLocation: CGPoint, to location: CGPoint) {
    let translation = CGPoint(
        x: location.x - previousLocation.x,
        y: location.y - previousLocation.y
    )
    applyCanvasPan(
        translation,
        refreshReason: "pan \(describe(point: translation))"
    )
}

private func applyCanvasPan(
    _ translation: CGPoint,
    refreshReason: String
) {
    guard translation != .zero else {
        return
    }

    let cameraCenterBeforePan = camera.center
    camera.pan(by: translation)
    logPanDispatch(
        translation: translation,
        cameraCenterBeforePan: cameraCenterBeforePan,
        cameraCenterAfterPan: camera.center
    )
    requestCanvasRefresh(reason: refreshReason)
    scheduleAutosave(reason: "pan canvas")
}
```

## 本阶段结果

- `iOSViewController` 已经能够消费阶段 1 视图层发出的 `onPan`。
- direct pan 与 indirect pan 现在共用同一套相机平移实现，不再分叉。
- 本阶段没有加入额外的冲突保护，因此后续还需要继续实施计划中的阶段 3。
