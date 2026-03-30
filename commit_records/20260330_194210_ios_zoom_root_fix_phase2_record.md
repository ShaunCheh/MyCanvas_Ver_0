# 20260330_194210_ios_zoom_root_fix_phase2_record

## 记录范围

- 记录内容：
  1. 将 pinch delta 的归一化入口改成按 `PinchInputSource` 分流。
  2. 新增 `normalizedPinchScaleDelta(...)` 及两条 source-specific 归一化函数骨架。
  3. 扩展 `PinchInput` 日志，显式输出当前 pinch 被解释成哪种输入源。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本记录不包含：
  - 阶段 3 的抗噪阈值、重复事件去重、迟到事件抑制
  - 控制器层 `handleZoom(_:around:)` 的 no-op guard
  - autosave 从每帧调度改为手势结束调度

## 修改一：handlePinch(_:) 改为通过 source-specific 归一化入口分流

### 修改前

- `.began` 和 `.changed` 都会解析 `resolvePinchInputSource(for:)`，但 source 只被保存到 `PinchGestureSession` 里。
- `.changed` 计算出 `rawScaleDelta` 后，会直接把它作为 `scaleDelta` 发给 `onZoom?(...)`。
- 换句话说，direct touch pinch 和 Mirroring/间接 pinch 仍然走的是同一条 delta 解释路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改前虽然已经识别了 pinch 输入源，但 rawScaleDelta 仍然会直接上送，尚未按 source 分流归一化。
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

### 修改后

- `.began` 先把 `source` 解析出来，再写入 `PinchGestureSession`。
- `.changed` 会先计算 `rawScaleDelta`，再通过 `normalizedPinchScaleDelta(rawDelta:source:)` 按 source 分流。
- 当前阶段 direct touch 与 Mirroring/间接 pinch 仍然都返回 `rawDelta`，但行为分流的结构已经明确建立，后续阶段可以只调整 `indirectMirroringLike` 分支而不影响直触摸。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改后 rawScaleDelta 会先经过 source-specific 归一化入口，再决定是否继续上送给 onZoom。
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
        session.lastRawScale = rawScale
        session.lastTimestamp = now
        session.lastAnchor = anchor
        pinchGestureSession = session

        guard let scaleDelta = normalizedPinchScaleDelta(
            rawDelta: rawScaleDelta,
            source: session.source
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

## 修改二：新增 source-specific pinch 归一化函数骨架

### 修改前

- 视图层没有单独的 pinch 归一化入口。
- 不存在 `directTouch` 与 `indirectMirroringLike` 两条独立的 delta 解释函数。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: resolvePinchInputSource(for:)
// 功能说明: 修改前只完成输入源识别，但没有基于输入源的 pinch 归一化分流。
private func resolvePinchInputSource(
    for gestureRecognizer: UIPinchGestureRecognizer
) -> PinchInputSource {
    if gestureRecognizer.numberOfTouches == 0, activeTouchCount == 0 {
        return .indirectMirroringLike
    }
    return .directTouch
}
```

### 修改后

- 新增 `normalizedPinchScaleDelta(rawDelta:source:)` 作为统一入口。
- 新增 `normalizedDirectTouchPinchScaleDelta(_:)` 和 `normalizedIndirectMirroringLikePinchScaleDelta(_:)` 两条 source-specific 函数。
- 当前这两条函数还只是最小骨架，只做有限性和正值校验，真正的抗噪/迟到抑制留到阶段 3。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: normalizedPinchScaleDelta(rawDelta:source:) / normalizedDirectTouchPinchScaleDelta(_:) / normalizedIndirectMirroringLikePinchScaleDelta(_:)
// 功能说明: 修改后 pinch 归一化具备按输入源分流的明确入口，后续可以只调 indirectMirroringLike 分支而不扰动 directTouch。
private func normalizedPinchScaleDelta(
    rawDelta: CGFloat,
    source: PinchInputSource
) -> CGFloat? {
    // Keep source-specific normalization entry points separate so later
    // tuning for Mirroring/indirect pinch does not perturb direct touch.
    switch source {
    case .directTouch:
        return normalizedDirectTouchPinchScaleDelta(rawDelta)
    case .indirectMirroringLike:
        return normalizedIndirectMirroringLikePinchScaleDelta(rawDelta)
    }
}

private func normalizedDirectTouchPinchScaleDelta(_ rawDelta: CGFloat) -> CGFloat? {
    guard rawDelta.isFinite, rawDelta > 0 else {
        return nil
    }
    return rawDelta
}

private func normalizedIndirectMirroringLikePinchScaleDelta(_ rawDelta: CGFloat) -> CGFloat? {
    guard rawDelta.isFinite, rawDelta > 0 else {
        return nil
    }
    return rawDelta
}
```

## 修改三：扩展 PinchInput 日志，显式输出 source

### 修改前

- `PinchInput` 日志只输出 `state / scale / velocity / anchor / touches / activeTouches`。
- 虽然可以从 `touches=0 activeTouches=0` 推断 Mirroring pinch，但日志没有直接给出“当前事件被解释成哪种 source”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: logPinchInput(_:)
// 功能说明: 修改前 PinchInput 日志只能看到原始 pinch 数据，无法直接确认当前事件被解释成 directTouch 还是 indirectMirroringLike。
private func logPinchInput(_ gestureRecognizer: UIPinchGestureRecognizer) {
    guard Self.isPinchZoomDiagnosticLoggingEnabled else {
        return
    }

    let now = ProcessInfo.processInfo.systemUptime
    let deltaMs = lastPinchInputTimestamp.map { (now - $0) * 1000 } ?? 0
    lastPinchInputTimestamp = now

    print(
        "[Canvas iOS][PinchInput] " +
        "t=\(String(format: "%.6f", now)) " +
        "dtMs=\(String(format: "%.3f", deltaMs)) " +
        "state=\(describe(gestureState: gestureRecognizer.state)) " +
        "scale=\(String(format: "%.6f", gestureRecognizer.scale)) " +
        "velocity=\(String(format: "%.6f", gestureRecognizer.velocity)) " +
        "anchor=\(NSCoder.string(for: gestureRecognizer.location(in: self))) " +
        "touches=\(gestureRecognizer.numberOfTouches) " +
        "activeTouches=\(activeTouchCount)"
    )
}
```

### 修改后

- 新增 `source = pinchGestureSession?.source ?? resolvePinchInputSource(for: gestureRecognizer)`。
- `PinchInput` 日志现在会显式打印 `source=directTouch` 或 `source=indirectMirroringLike`。
- 新增 `describe(pinchInputSource:)`，统一 source 的日志文本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: logPinchInput(_:) / describe(pinchInputSource:)
// 功能说明: 修改后 PinchInput 日志会直接输出 source，方便验证当前 pinch 事件是否按预期走入 Mirroring/直触摸分流。
private func logPinchInput(_ gestureRecognizer: UIPinchGestureRecognizer) {
    guard Self.isPinchZoomDiagnosticLoggingEnabled else {
        return
    }

    let now = ProcessInfo.processInfo.systemUptime
    let deltaMs = lastPinchInputTimestamp.map { (now - $0) * 1000 } ?? 0
    lastPinchInputTimestamp = now
    let source = pinchGestureSession?.source ?? resolvePinchInputSource(for: gestureRecognizer)

    print(
        "[Canvas iOS][PinchInput] " +
        "t=\(String(format: "%.6f", now)) " +
        "dtMs=\(String(format: "%.3f", deltaMs)) " +
        "state=\(describe(gestureState: gestureRecognizer.state)) " +
        "source=\(describe(pinchInputSource: source)) " +
        "scale=\(String(format: "%.6f", gestureRecognizer.scale)) " +
        "velocity=\(String(format: "%.6f", gestureRecognizer.velocity)) " +
        "anchor=\(NSCoder.string(for: gestureRecognizer.location(in: self))) " +
        "touches=\(gestureRecognizer.numberOfTouches) " +
        "activeTouches=\(activeTouchCount)"
    )
}

private func describe(pinchInputSource: PinchInputSource) -> String {
    switch pinchInputSource {
    case .directTouch:
        return "directTouch"
    case .indirectMirroringLike:
        return "indirectMirroringLike"
    }
}
```

## 本阶段结果

- 视图层 pinch 归一化已经显式按 `PinchInputSource` 分流。
- direct touch 与 Mirroring/间接 pinch 现在拥有独立的后续调参入口。
- 当前阶段仍然没有引入任何阈值、去重或迟到事件抑制逻辑；行为上还是“原样透传”，只是结构已拆开。
