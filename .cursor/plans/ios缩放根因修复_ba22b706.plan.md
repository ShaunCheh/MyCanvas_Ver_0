---
name: iOS缩放根因修复
overview: 围绕 iPhone Mirroring 下 iOS 画布 pinch 缩放不精确的问题，按根因优先的方式制定修复计划：重写视图层 pinch 适配、在控制器层补无效缩放保护，并把 continuous zoom 的 autosave 挪到手势结束。
todos:
  - id: rewrite-pinch-adapter
    content: 重写 iOS 视图层 pinch 适配，改为基于 raw scale 相邻帧比值计算稳定 delta，并去掉 scale=1 重置
    status: completed
  - id: split-pinch-sources
    content: 将 direct touch pinch 与 Mirroring/间接 pinch 分流，并分别应用不同归一化策略
    status: completed
  - id: stabilize-indirect-pinch
    content: 为 indirect pinch 增加去噪、去重和迟到事件抑制，解决起步慢、停手后继续缩和大跳变
    status: completed
  - id: guard-noop-zoom
    content: 在 iOS 控制器中为无效 zoom 加保护，到达 min/max 后跳过 refresh 和 autosave
    status: completed
  - id: autosave-on-end
    content: 把 continuous zoom 的 autosave 从每帧调度改为手势结束后调度，减少缩放期间缩略图生成干扰
    status: pending
  - id: ab-verify-logs
    content: 保留现有诊断日志做 A/B 验证，确认 PinchInput、ControllerZoom、RenderZoom 和 ThumbnailTrace 的形态收敛
    status: pending
isProject: false
---

# iOS 缩放根因修复计划

## 根因判断

这次问题的主根因已经比较明确了，且发生在输入适配层，不在 `CanvasCamera` 或控制器刷新数学里。

- `iPhone Mirroring` 下的 `UIPinchGestureRecognizer` 事件流是“稀疏、延后、会在停手后继续吐 `changed`”的。
- 当前 [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`] 里的 `handlePinch(_:)` 把 `gestureRecognizer.scale` 当作每帧增量使用，并且每次都 `gestureRecognizer.scale = 1`。这套写法对直接触摸 pinch 常见，但对 Mirroring 这类间接 pinch 输入不稳。
- 结果是：
  - 晚到事件会被当成新的“大增量”继续乘到 `camera.zoomScale`
  - 重复的 raw scale 会被重复放大
  - 手停后继续收到 `changed` 时，画面也继续缩放/放大
- 次级问题有两个：
  - 到达 `min/max zoom` 后，控制器仍然继续 refresh + autosave
  - `BoardSaveCoordinator` 的 `0.35s` debounce 会在 Mirroring 的大间隔里触发保存，缩略图生成会穿插到缩放期间，加重噪声和系统负载

所以根因优先的修法应该是：重写 iOS 视图层的 pinch delta 归一化逻辑，把“raw pinch 语义”变成稳定的 zoom delta，再让控制器消费；不要去改 `CanvasCamera`。

## 修改边界

只动这两层：

- [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`]
- [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`]

明确不动：

- [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`]
- [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`]

原因很简单：现在的日志已经证明，`camera.zoom(by:)` 和正常渲染耗时都不是主因，问题在它们之前。

## 详细分阶段计划

### 阶段 1：重写视图层 pinch 适配器，去掉 `scale = 1` 依赖

目标：把 `UIPinchGestureRecognizer` 的 raw scale 转成稳定的相邻帧 delta，不再直接用“本帧 scale 乘 camera”。

要做的事：

1. 在 `iOSCanvasViewportView` 增加一份 pinch 会话状态。
2. 记录：
  - `lastRawScale`
  - `lastTimestamp`
  - `inputSource`
  - `lastAnchor`
3. 在 `.began` 时初始化 session。
4. 在 `.changed` 时不再直接取 `gestureRecognizer.scale` 作为 `scaleDelta`，而是改成：
  `rawDelta = currentRawScale / lastRawScale`
5. 更新 `lastRawScale = currentRawScale`，然后只把 `rawDelta` 送给 `onZoom?(...)`。
6. 删除当前这句：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 当前实现每次把 recognizer.scale 重置为 1，这会放大 Mirroring 间接 pinch 的事件流问题。
gestureRecognizer.scale = 1
```

建议新增的状态骨架：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 新增类型 PinchInputSource / PinchGestureSession
// 功能说明: 在视图层保存 raw pinch 的上一帧状态，把不稳定的 UIKit 事件流转换成稳定的相邻帧缩放增量。
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

private var pinchGestureSession: PinchGestureSession?
```

建议替换后的 handler 骨架：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 不再使用“重置 scale=1”的增量模式，而是基于 raw scale 的相邻帧比值计算稳定 delta。
@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    let now = ProcessInfo.processInfo.systemUptime
    let anchor = gestureRecognizer.location(in: self)
    let rawScale = gestureRecognizer.scale

    switch gestureRecognizer.state {
    case .began:
        pinchGestureSession = PinchGestureSession(
            source: resolvePinchInputSource(for: gestureRecognizer),
            lastRawScale: rawScale,
            lastTimestamp: now,
            lastAnchor: anchor
        )
    case .changed:
        guard var session = pinchGestureSession else {
            return
        }

        let rawDelta = rawScale / max(session.lastRawScale, 0.0001)
        session.lastRawScale = rawScale
        session.lastTimestamp = now
        session.lastAnchor = anchor
        pinchGestureSession = session

        guard let normalizedDelta = normalizedPinchScaleDelta(
            rawDelta: rawDelta,
            source: session.source,
            dt: now - session.lastTimestamp
        ) else {
            return
        }

        onZoom?(normalizedDelta, anchor)
    case .ended, .cancelled, .failed:
        pinchGestureSession = nil
        onZoomGestureEnded?()
    default:
        break
    }
}
```

这一阶段是主修复点，优先级最高。

### 阶段 2：把 indirect pinch 和 direct touch pinch 分流

目标：不要再把 Mirroring 的间接 pinch 和 iPhone/iPad 直接触摸 pinch 当成同一种输入语义。

基于你现在的日志，Mirroring pinch 明显满足：

- `touches = 0`
- `activeTouches = 0`

所以可以先在 `iOSCanvasViewportView` 里用这个规则做输入源识别：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: resolvePinchInputSource(for:)
// 功能说明: 将 Mirroring/间接 pinch 与直接触摸 pinch 分流，避免同一套 delta 规则误伤直触摸体验。
private func resolvePinchInputSource(
    for gestureRecognizer: UIPinchGestureRecognizer
) -> PinchInputSource {
    if gestureRecognizer.numberOfTouches == 0, activeTouchCount == 0 {
        return .indirectMirroringLike
    }
    return .directTouch
}
```

然后做两套不同的归一化策略：

- `directTouch`
  - 保持较原始的响应
- `indirectMirroringLike`
  - 加抗噪和去重
  - 抑制迟到事件造成的大跳变

### 阶段 3：为 indirect pinch 增加抗噪、去重、迟到事件抑制

目标：解决“开始慢、停手后继续缩、一下子缩很多”。

在 `normalizedPinchScaleDelta(...)` 里做三件事：

1. 去掉近似 `1.0` 的噪声 delta
2. 去掉重复 raw scale 导致的重复缩放
3. 对大间隔晚到事件做弱化处理

建议规则：

- 死区：`abs(rawDelta - 1) < epsilon` 直接忽略
- 对 indirect pinch 单独设置更大的死区，比如 `0.003 ~ 0.008`
- 当 `dtMs > 40~50ms` 时，说明事件流已经不稳定，不要 100% 接收原始 delta
- 对 indirect pinch 的单帧 delta 加软钳制，避免一次跳太大

建议函数骨架：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: normalizedPinchScaleDelta(rawDelta:source:dt:)
// 功能说明: 对 Mirroring 间接 pinch 做去噪、去重、迟到事件抑制，把 raw pinch 变成可控的 zoom delta。
private func normalizedPinchScaleDelta(
    rawDelta: CGFloat,
    source: PinchInputSource,
    dt: TimeInterval
) -> CGFloat? {
    guard rawDelta.isFinite, rawDelta > 0 else {
        return nil
    }

    let epsilon: CGFloat = source == .indirectMirroringLike ? 0.006 : 0.002
    if abs(rawDelta - 1) < epsilon {
        return nil
    }

    if source == .indirectMirroringLike {
        let clampedDelta = min(max(rawDelta, 0.97), 1.03)

        if dt > 0.05 {
            return 1 + ((clampedDelta - 1) * 0.5)
        }

        return clampedDelta
    }

    return rawDelta
}
```

这里的具体参数要靠二轮日志和手感微调，但结构应该先固定下来。

### 阶段 4：给控制器加“无效 zoom 不刷新”的保护

目标：去掉所有“zoom 已经没变，但还在 refresh / autosave”的无意义工作。

你现在的日志已经证明，在到达 `0.1` 和 `8.0` 之后，控制器仍然一直在跑：

- `requestCanvasRefresh(...)`
- `scheduleAutosave(...)`

这会放大 Mirroring 迟到事件带来的视觉噪声。

在 [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`] 的 `handleZoom(_:around:)` 里加这个守卫：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleZoom(_:around:)
// 功能说明: 如果 camera.zoomScale 实际没有变化，就跳过 refresh 和 autosave，避免 min/max clamp 后继续做无意义工作。
private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        return
    }

    let zoomBefore = camera.zoomScale
    camera.zoom(by: scaleDelta, around: anchor)
    let zoomAfter = camera.zoomScale

    guard zoomAfter != zoomBefore else {
        return
    }

    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: \"%.4f\", scaleDelta)) anchor=\(describe(point: anchor))"
    )
    markZoomGestureDirty()
}
```

这一步不是主根因修复，但必须做。

### 阶段 5：把 continuous zoom 的 autosave 从“每帧调度”改成“手势结束后调度”

目标：避免 Mirroring 大间隔导致 autosave/thumbnail generation 在缩放中途穿插执行。

当前结构的问题是：

- `handleZoom` 每帧都 `scheduleAutosave(reason: "zoom canvas")`
- `BoardSaveCoordinator` 的 debounce 是 `0.35s`
- Mirroring pinch 日志里存在 `130ms / 370ms / 598ms` 这种 gap
- 这些 gap 会让 save 在缩放中途真正落地，带出 `BoardList][ThumbnailTrace]`

所以应该把 zoom 持久化改成：

- 手势进行中只改 camera 和 render
- 只有在 pinch `ended/cancelled/failed` 后，且本次 pinch 确实改过 zoom，才调一次 autosave

这一步需要扩展视图到控制器的接口，推荐新增：

- `onZoomGestureBegan`
- `onZoomGestureEnded`

或者更简洁一点：

- `onZoomInteractionStateChange`

控制器侧新增：

```swift
// 文件路径: /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleZoomGestureEnded()
// 功能说明: 将 continuous zoom 的持久化从每帧触发改为手势结束触发，避免 Mirroring 间隔期间穿插缩略图生成。
private var didMutateCameraDuringZoomGesture = false

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringZoomGesture else {
        return
    }

    scheduleAutosave(reason: "zoom canvas")
    didMutateCameraDuringZoomGesture = false
}
```

这是次级优化，但我建议和阶段 4 一起做。

### 阶段 6：保留日志，做 A/B 验证，再收日志

验证标准不要再看“感觉”，而要看日志形态是否变成下面这样：

- `PinchInput`
  - 即便仍然有不规则 `dtMs`，也没关系
- `ControllerZoom`
  - 不再出现重复的大 `scaleDelta`
  - 停手后晚到的 `changed` 大多被归一化成 `≈1` 或直接丢弃
- `RenderZoom`
  - 只在 zoom 真变化时出现
  - 到达 `min/max` 后基本不再刷新
- `BoardList][ThumbnailTrace]`
  - 在持续 pinch 过程中显著减少，最好只在结束后出现

## 推荐实施顺序

1. 先改 `iOSCanvasViewportView` 的 pinch session 和 raw-scale delta 归一化
2. 再改 `iOSViewController.handleZoom(_:around:)` 的 no-op guard
3. 然后补 `onZoomGestureEnded`，把 autosave 挪到手势结束
4. 保留现有日志，再做一轮 Mirroring 验证
5. 参数调稳后，再把 pinch 诊断日志降到可控开关

## 这套计划为什么是“根因修改”

因为它不去掩盖现象，而是把问题拆回到正确层次：

- 不是去调 `CanvasCamera`
- 不是去做 UI 层动画平滑
- 不是去“感觉上减速”
- 而是直接修正 [`/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`] 对 Mirroring 间接 pinch 的错误输入语义解释

