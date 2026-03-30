# 20260330_193442_ios_zoom_root_fix_phase1_record

## 记录范围

- 记录内容：
  1. 在 iOS 视图层新增 pinch 会话状态，用于保存 raw pinch 的上一帧信息。
  2. 将 `handlePinch(_:)` 从“直接使用 `gestureRecognizer.scale` 作为增量”改为“使用相邻两帧 raw scale 比值作为增量”。
  3. 移除 `gestureRecognizer.scale = 1` 这套依赖 UIKit 内部重置的增量写法。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本记录不包含：
  - direct touch pinch / Mirroring pinch 的差异化归一化策略
  - 控制器层 `handleZoom(_:around:)` 的 no-op guard
  - autosave 从每帧调度改为手势结束调度

## 修改一：新增 pinch 会话状态，保存 raw pinch 的上一帧信息

### 修改前

- 视图层只有 `TouchInteractionState`，没有任何专门保存 pinch 会话状态的结构。
- `handlePinch(_:)` 只能直接读取当前帧 `gestureRecognizer.scale`，无法基于上一帧 raw scale 计算稳定的相邻帧增量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: TouchInteractionState / 属性声明区
// 功能说明: 修改前视图层没有专门的 pinch 会话状态，无法跨帧保存 raw pinch 的上一帧 scale 与时间戳。
private enum TouchInteractionState {
    case idle
    case trackingPrimaryPointer(
        trackedTouch: UITouch,
        pressedLocation: CGPoint,
        lastLocation: CGPoint
    )
    case awaitingPinch
    case pinching
    case presentingContextMenu(trackedTouch: UITouch)
}

private var interactionState: TouchInteractionState = .idle
private var activeTouchesByID: [ObjectIdentifier: UITouch] = [:]
private var lastPinchInputTimestamp: TimeInterval?
```

### 修改后

- 新增 `PinchInputSource`，为后续 direct touch / Mirroring pinch 分流预留类型边界。
- 新增 `PinchGestureSession`，保存 `lastRawScale / lastTimestamp / lastAnchor / source`。
- 新增 `pinchGestureSession` 属性，让视图层可以跨帧计算 raw pinch 的相邻帧增量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: TouchInteractionState / PinchInputSource / PinchGestureSession / 属性声明区
// 功能说明: 修改后视图层显式保存 pinch 会话状态，为基于 raw scale 的相邻帧 delta 计算提供数据基础。
private enum TouchInteractionState {
    case idle
    case trackingPrimaryPointer(
        trackedTouch: UITouch,
        pressedLocation: CGPoint,
        lastLocation: CGPoint
    )
    case awaitingPinch
    case pinching
    case presentingContextMenu(trackedTouch: UITouch)
}

private enum PinchInputSource {
    case directTouch
    case indirectMirroringLike
}

private struct PinchGestureSession {
    var source: PinchInputSource
    var lastRawScale: CGFloat
    var lastTimestamp: TimeInterval
    var lastAnchor: CGPoint
}

private var interactionState: TouchInteractionState = .idle
private var activeTouchesByID: [ObjectIdentifier: UITouch] = [:]
private var pinchGestureSession: PinchGestureSession?
private var lastPinchInputTimestamp: TimeInterval?
```

## 修改二：重写 handlePinch(_:)，改为使用相邻两帧 raw scale 比值作为 delta

### 修改前

- `.began` 和 `.changed` 走同一条逻辑。
- 直接把 `gestureRecognizer.scale` 当作 `scaleDelta` 发给 `onZoom?(...)`。
- 每帧处理后都会执行 `gestureRecognizer.scale = 1`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改前直接把 UIKit 当前帧 scale 作为缩放增量使用，并依赖 scale = 1 的重置语义。
@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    logPinchInput(gestureRecognizer)

    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began, .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let scaleDelta = gestureRecognizer.scale
        guard scaleDelta.isFinite, scaleDelta > 0 else {
            return
        }

        onZoom?(scaleDelta, gestureRecognizer.location(in: self))
        gestureRecognizer.scale = 1
    case .ended, .cancelled, .failed:
        reconcileTouchInteractionState()
    default:
        break
    }
}
```

### 修改后

- `.began` 只负责初始化一份 `PinchGestureSession`。
- `.changed` 读取当前帧 `rawScale`，并用 `rawScale / lastRawScale` 计算相邻帧 `scaleDelta`。
- 每次计算完成后更新 `lastRawScale / lastTimestamp / lastAnchor`。
- 移除了 `gestureRecognizer.scale = 1`。
- 在 `.ended / .cancelled / .failed` 时清掉 `pinchGestureSession`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改后基于 raw pinch 的相邻帧比值计算稳定 delta，不再依赖 UIKit 的 scale 重置语义。
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

        pinchGestureSession = PinchGestureSession(
            source: resolvePinchInputSource(for: gestureRecognizer),
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
        guard var session = pinchGestureSession else {
            pinchGestureSession = PinchGestureSession(
                source: resolvePinchInputSource(for: gestureRecognizer),
                lastRawScale: rawScale,
                lastTimestamp: now,
                lastAnchor: anchor
            )
            return
        }

        let scaleDelta = rawScale / max(session.lastRawScale, 0.0001)
        session.lastRawScale = rawScale
        session.lastTimestamp = now
        session.lastAnchor = anchor
        pinchGestureSession = session

        guard scaleDelta.isFinite, scaleDelta > 0 else {
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

## 修改三：新增 resolvePinchInputSource(for:) 作为后续输入源分流的预留入口

### 修改前

- 视图层没有单独的输入源识别函数。
- pinch 处理逻辑无法区分 direct touch pinch 与 Mirroring/间接 pinch。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改前 pinch 逻辑没有单独的输入源判断入口，所有 pinch 都被同一套规则处理。
@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    // ...
}
```

### 修改后

- 新增 `resolvePinchInputSource(for:)`。
- 当前阶段先以 `numberOfTouches == 0 && activeTouchCount == 0` 识别 `indirectMirroringLike`，为下一阶段的差异化归一化留出明确扩展点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: resolvePinchInputSource(for:)
// 功能说明: 修改后为 pinch 输入源识别提供显式入口，下一阶段可在这里扩展 direct touch 与 Mirroring 的差异化策略。
private func resolvePinchInputSource(
    for gestureRecognizer: UIPinchGestureRecognizer
) -> PinchInputSource {
    if gestureRecognizer.numberOfTouches == 0, activeTouchCount == 0 {
        return .indirectMirroringLike
    }
    return .directTouch
}
```

## 本阶段结果

- iOS 视图层已经不再依赖 `gestureRecognizer.scale = 1` 这套增量写法。
- pinch delta 现在改为由“当前帧 raw scale / 上一帧 raw scale”计算得出。
- 当前修改仍停留在视图层，尚未加入 Mirroring pinch 的抗噪、迟到事件抑制和控制器层无效缩放保护。
