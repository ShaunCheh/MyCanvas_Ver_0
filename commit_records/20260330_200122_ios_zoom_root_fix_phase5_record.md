# 20260330_200122_ios_zoom_root_fix_phase5_record

## 记录范围

- 记录内容：
  1. 在 `iOSCanvasViewportView` 中新增缩放手势生命周期回调：`onZoomGestureBegan` / `onZoomGestureEnded`。
  2. 在 `handlePinch(_:)` 中于合适的手势状态发出开始/结束回调，让控制器感知 continuous zoom 的生命周期。
  3. 在 `iOSViewController` 中新增 `didMutateCameraDuringZoomGesture`，并把 `zoom canvas` 的 autosave 从每帧触发改为手势结束后触发。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 阶段 6 的 A/B 日志验证与日志收敛

## 修改一：视图层新增缩放手势生命周期回调接口

### 修改前

- `iOSCanvasViewportView` 只向控制器暴露 `onZoom`，控制器只能收到每一帧的 zoom delta。
- 视图层没有“本次 pinch 开始了 / 结束了”的回调，因此控制器无法把 autosave 挪到手势结束时统一调度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 回调属性定义区（无单独函数）
// 功能说明: 修改前视图层只暴露逐帧 zoom 回调，没有暴露 zoom 手势生命周期事件。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?
```

### 修改后

- 新增 `onZoomGestureBegan` / `onZoomGestureEnded` 两个回调。
- 控制器现在可以独立感知“手势开始”和“手势结束”，不再只能依赖逐帧 `onZoom`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 回调属性定义区（无单独函数）
// 功能说明: 修改后视图层除逐帧 zoom 回调外，还会把 zoom 手势的开始和结束显式通知给控制器。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onZoomGestureBegan: (() -> Void)?
var onZoomGestureEnded: (() -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?
```

## 修改二：`handlePinch(_:)` 发出 zoom 手势开始/结束事件

### 修改前

- `.began` 只会建立 `pinchGestureSession`。
- `.changed` 在 session 缺失时只会补建 session 并直接返回。
- `.ended / .cancelled / .failed` 只会清理 `pinchGestureSession` 和交互状态。
- 整个手势生命周期内都不会通知控制器“这一轮 zoom 手势已经开始/结束”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改前 pinch 只负责产生 zoom delta，不负责把手势生命周期同步给控制器。
@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    logPinchInput(gestureRecognizer)

    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let rawScale = gestureRecognizer.scale
        guard rawScale.isFinite, rawScale > 0 else {
            return
        }

        let source = resolvePinchInputSource(for: gestureRecognizer)
        pinchGestureSession = PinchGestureSession(
            source: source,
            lastRawScale: rawScale,
            lastTimestamp: ProcessInfo.processInfo.systemUptime,
            lastAnchor: gestureRecognizer.location(in: self)
        )
    case .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let rawScale = gestureRecognizer.scale
        guard rawScale.isFinite, rawScale > 0 else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let anchor = gestureRecognizer.location(in: self)
        let source = resolvePinchInputSource(for: gestureRecognizer)
        guard var session = pinchGestureSession else {
            pinchGestureSession = PinchGestureSession(
                source: source,
                lastRawScale: rawScale,
                lastTimestamp: now,
                lastAnchor: anchor
            )
            return
        }

        let rawScaleDelta = rawScale / max(session.lastRawScale, 0.0001)
        let dt = max(now - session.lastTimestamp, 0)
        session.lastRawScale = rawScale
        session.lastTimestamp = now
        session.lastAnchor = anchor
        pinchGestureSession = session

        guard let scaleDelta = normalizedPinchScaleDelta(
            rawDelta: rawScaleDelta,
            source: session.source,
            dt: dt
        ) else {
            return
        }

        onZoom?(scaleDelta, anchor)
    case .ended, .cancelled, .failed:
        pinchGestureSession = nil
        reconcileTouchInteractionState()
    default:
        break
    }
}
```

### 修改后

- `.began` 在建立 `pinchGestureSession` 后立即触发 `onZoomGestureBegan?()`。
- `.changed` 如果发现 session 丢失、需要重建，也会补发一次 `onZoomGestureBegan?()`，防止控制器状态不同步。
- `.ended / .cancelled / .failed` 会在确认本次手势确实存在活动 session 后，再触发 `onZoomGestureEnded?()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改后 pinch 除了发出逐帧 zoom delta，还会把本轮 zoom 手势的开始和结束同步给控制器。
@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    logPinchInput(gestureRecognizer)

    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let rawScale = gestureRecognizer.scale
        guard rawScale.isFinite, rawScale > 0 else {
            return
        }

        let source = resolvePinchInputSource(for: gestureRecognizer)
        pinchGestureSession = PinchGestureSession(
            source: source,
            lastRawScale: rawScale,
            lastTimestamp: ProcessInfo.processInfo.systemUptime,
            lastAnchor: gestureRecognizer.location(in: self)
        )
        onZoomGestureBegan?()
    case .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let rawScale = gestureRecognizer.scale
        guard rawScale.isFinite, rawScale > 0 else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let anchor = gestureRecognizer.location(in: self)
        let source = resolvePinchInputSource(for: gestureRecognizer)
        guard var session = pinchGestureSession else {
            pinchGestureSession = PinchGestureSession(
                source: source,
                lastRawScale: rawScale,
                lastTimestamp: now,
                lastAnchor: anchor
            )
            onZoomGestureBegan?()
            return
        }

        let rawScaleDelta = rawScale / max(session.lastRawScale, 0.0001)
        let dt = max(now - session.lastTimestamp, 0)
        session.lastRawScale = rawScale
        session.lastTimestamp = now
        session.lastAnchor = anchor
        pinchGestureSession = session

        guard let scaleDelta = normalizedPinchScaleDelta(
            rawDelta: rawScaleDelta,
            source: session.source,
            dt: dt
        ) else {
            return
        }

        onZoom?(scaleDelta, anchor)
    case .ended, .cancelled, .failed:
        let hadActiveZoomGesture = pinchGestureSession != nil
        pinchGestureSession = nil
        reconcileTouchInteractionState()
        if hadActiveZoomGesture {
            onZoomGestureEnded?()
        }
    default:
        break
    }
}
```

## 修改三：控制器接入 zoom 手势生命周期，并把 autosave 挪到结束时

### 修改前

- `iOSViewController` 没有“本次 zoom 手势是否真的改过 camera”的状态位。
- `setupCanvasViewport()` 只接了 `onZoom`，没有接 zoom 手势开始/结束回调。
- `handleZoom(_:)` 在每次 zoom 有效变化后都会立刻 `scheduleAutosave(reason: "zoom canvas")`，这会让 Mirroring 的大间隔 pinch 在手势中途穿插 save / thumbnail generation。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性定义区 / setupCanvasViewport() / handleZoom(_:around:)
// 功能说明: 修改前控制器只有逐帧 zoom 通道，且每帧有效缩放后都会立刻调度一次 autosave。
private var pendingRefreshReason: String?
private var pointerDragState: PointerDragState = .idle
private var lastZoomDispatchTimestamp: TimeInterval?
private var lastZoomRefreshTimestamp: TimeInterval?
private var saveButtonResetWorkItem: DispatchWorkItem?

private func setupCanvasViewport() {
    // ... 省略其他回调接线 ...
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }
    // ... 省略其余安装逻辑 ...
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    let eventTime = ProcessInfo.processInfo.systemUptime
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

    let zoomBefore = camera.zoomScale
    camera.zoom(by: scaleDelta, around: anchor)
    let zoomAfter = camera.zoomScale
    let afterZoomApply = ProcessInfo.processInfo.systemUptime
    guard zoomAfter != zoomBefore else {
        return
    }

    let refreshReason = "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    requestCanvasRefresh(reason: refreshReason)
    let afterRefresh = ProcessInfo.processInfo.systemUptime
    scheduleAutosave(reason: "zoom canvas")
    let afterAutosave = ProcessInfo.processInfo.systemUptime

    logZoomDispatch(
        eventTime: eventTime,
        scaleDelta: scaleDelta,
        anchor: anchor,
        zoomBefore: zoomBefore,
        zoomAfter: zoomAfter,
        applyCostMs: (afterZoomApply - eventTime) * 1000,
        refreshCostMs: (afterRefresh - afterZoomApply) * 1000,
        autosaveCostMs: (afterAutosave - afterRefresh) * 1000,
        totalCostMs: (afterAutosave - eventTime) * 1000
    )
}
```

### 修改后

- 新增 `didMutateCameraDuringZoomGesture`，用来记录本轮缩放手势中 camera 是否真的变化过。
- `setupCanvasViewport()` 接上 `onZoomGestureBegan` / `onZoomGestureEnded`，并分别转发到控制器侧处理函数。
- `handleZoomGestureBegan()` 在手势开始时清零状态。
- `handleZoomGestureEnded()` 只在本轮手势确实改过 camera 时，才补调一次 `scheduleAutosave(reason: "zoom canvas")`。
- `handleZoom(_:)` 不再每帧调 autosave，而是在发生有效 zoom 后只标记 `didMutateCameraDuringZoomGesture = true`；同时把本帧日志中的 autosave 成本置为 `0`，忠实反映“本帧未执行 autosave”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性定义区 / setupCanvasViewport() / handleZoomGestureBegan() / handleZoomGestureEnded() / handleZoom(_:around:)
// 功能说明: 修改后 continuous zoom 期间只做 camera 和 render，autosave 改为在手势结束后按需触发一次。
private var pendingRefreshReason: String?
private var pointerDragState: PointerDragState = .idle
private var lastZoomDispatchTimestamp: TimeInterval?
private var lastZoomRefreshTimestamp: TimeInterval?
private var didMutateCameraDuringZoomGesture = false
private var saveButtonResetWorkItem: DispatchWorkItem?

private func setupCanvasViewport() {
    // ... 省略其他回调接线 ...
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onZoomGestureBegan = { [weak self] in
        self?.handleZoomGestureBegan()
    }
    canvasViewportView.onZoomGestureEnded = { [weak self] in
        self?.handleZoomGestureEnded()
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }
    // ... 省略其余安装逻辑 ...
}

private func handleZoomGestureBegan() {
    didMutateCameraDuringZoomGesture = false
}

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringZoomGesture else {
        return
    }

    scheduleAutosave(reason: "zoom canvas")
    didMutateCameraDuringZoomGesture = false
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    let eventTime = ProcessInfo.processInfo.systemUptime
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

    let zoomBefore = camera.zoomScale
    camera.zoom(by: scaleDelta, around: anchor)
    let zoomAfter = camera.zoomScale
    let afterZoomApply = ProcessInfo.processInfo.systemUptime
    guard zoomAfter != zoomBefore else {
        return
    }

    didMutateCameraDuringZoomGesture = true
    let refreshReason = "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    requestCanvasRefresh(reason: refreshReason)
    let afterRefresh = ProcessInfo.processInfo.systemUptime
    let afterAutosave = afterRefresh

    logZoomDispatch(
        eventTime: eventTime,
        scaleDelta: scaleDelta,
        anchor: anchor,
        zoomBefore: zoomBefore,
        zoomAfter: zoomAfter,
        applyCostMs: (afterZoomApply - eventTime) * 1000,
        refreshCostMs: (afterRefresh - afterZoomApply) * 1000,
        autosaveCostMs: (afterAutosave - afterRefresh) * 1000,
        totalCostMs: (afterAutosave - eventTime) * 1000
    )
}
```

## 结果说明

- 本阶段没有改变 pinch delta 的归一化规则，也没有关闭任何诊断日志。
- 本阶段的核心是把 `zoom canvas` 的持久化时机从“每一帧有效缩放”改成“本轮缩放手势结束且确实改过 zoom”。
- 这样可以减少 Mirroring pinch 中途穿插的 autosave / thumbnail generation，为阶段 6 的 A/B 日志验证创造更干净的观察条件。
