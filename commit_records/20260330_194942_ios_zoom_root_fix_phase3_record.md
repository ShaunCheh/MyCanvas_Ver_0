# 20260330_194942_ios_zoom_root_fix_phase3_record

## 记录范围

- 记录内容：
  1. 在 `handlePinch(_:)` 的 `.changed` 分支中补充相邻 pinch 事件间隔 `dt` 的计算，并把 `dt` 传入归一化入口。
  2. 为 pinch 归一化新增阶段 3 所需的静态阈值常量，包括 deadzone、单帧 soft clamp、迟到事件阈值与衰减系数。
  3. 为 `indirectMirroringLike` 输入源落地抗噪、重复事件抑制和迟到事件弱化策略，同时给 `directTouch` 增加更小的噪声 deadzone。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本记录不包含：
  - 阶段 4 的控制器层 `handleZoom(_:around:)` no-op guard
  - 阶段 5 的 continuous zoom autosave 改为手势结束后调度
  - 阶段 6 的 A/B 日志验证与日志收敛

## 修改一：`handlePinch(_:)` 将相邻事件间隔 `dt` 接入归一化入口

### 修改前

- `.changed` 分支只计算 `rawScaleDelta`，然后直接调用 `normalizedPinchScaleDelta(rawDelta:source:)`。
- `PinchGestureSession.lastTimestamp` 虽然会被更新，但它还没有真正参与 delta 归一化，因此无法针对 Mirroring 的晚到事件做抑制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改前只把 rawScaleDelta 和 source 送入归一化入口，尚未利用相邻 pinch 事件的时间间隔抑制迟到输入。
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

### 修改后

- `.changed` 分支先根据 `session.lastTimestamp` 计算相邻事件间隔 `dt`。
- `dt` 会和 `rawScaleDelta`、`source` 一起进入 `normalizedPinchScaleDelta(rawDelta:source:dt:)`，为 Mirroring 晚到事件抑制提供输入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handlePinch(_:)
// 功能说明: 修改后会把相邻 pinch 事件的时间间隔 dt 一并送入归一化入口，用于弱化 Mirroring 晚到事件造成的缩放突变。
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

## 修改二：补充阶段 3 所需的 pinch 归一化常量

### 修改前

- 视图层只保留了诊断日志开关，没有为阶段 3 的抗噪、软钳制、迟到事件抑制准备专门的参数常量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 类型静态常量区（无单独函数）
// 功能说明: 修改前只有 pinch 诊断日志开关，阶段 3 所需的 deadzone、soft clamp 和迟到事件参数尚未定义。
private static let rotationTextCornerRadius: CGFloat = 8
private static let longPressMinimumDuration: TimeInterval = 0.5
private static let longPressAllowableMovement: CGFloat = 4
private static let isPinchZoomDiagnosticLoggingEnabled = true
```

### 修改后

- 为 `directTouch` 与 `indirectMirroringLike` 分别定义不同 deadzone。
- 为 `indirectMirroringLike` 新增单帧 soft clamp 区间、迟到事件阈值和衰减系数，使阶段 3 的行为调优有单独参数入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 类型静态常量区（无单独函数）
// 功能说明: 修改后新增阶段 3 所需的归一化参数常量，便于独立调整 Mirroring pinch 的抗噪与迟到事件抑制策略。
private static let rotationTextCornerRadius: CGFloat = 8
private static let longPressMinimumDuration: TimeInterval = 0.5
private static let longPressAllowableMovement: CGFloat = 4
private static let isPinchZoomDiagnosticLoggingEnabled = true
private static let directTouchPinchNoiseDeadzone: CGFloat = 0.002
private static let indirectMirroringLikePinchNoiseDeadzone: CGFloat = 0.006
private static let indirectMirroringLikePinchClampRange: ClosedRange<CGFloat> = 0.97 ... 1.03
private static let indirectMirroringLikeLateEventThreshold: TimeInterval = 0.05
private static let indirectMirroringLikeLateEventAttenuation: CGFloat = 0.5
```

## 修改三：为 `indirectMirroringLike` 落地抗噪、重复事件抑制和迟到事件弱化

### 修改前

- `normalizedPinchScaleDelta(...)` 只做 source 分流，不接收 `dt`。
- `directTouch` 与 `indirectMirroringLike` 两条函数都只是做有限性和正值校验，然后原样返回 `rawDelta`。
- 重复 raw scale 导致的 `rawDelta ~= 1`、以及 Mirroring 晚到事件导致的大跳变，都还没有被处理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: normalizedPinchScaleDelta(rawDelta:source:) / normalizedDirectTouchPinchScaleDelta(_:) / normalizedIndirectMirroringLikePinchScaleDelta(_:)
// 功能说明: 修改前仅完成 source 分流骨架，尚未对 indirectMirroringLike 做 deadzone、soft clamp 和迟到事件抑制。
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

### 修改后

- `normalizedPinchScaleDelta(...)` 新增 `dt` 参数，作为是否要弱化晚到事件的判断输入。
- `directTouch` 增加较小 deadzone，过滤直接触摸 pinch 的极小噪声，不改变其整体响应风格。
- `indirectMirroringLike` 增加更大 deadzone，用于过滤近似 `1.0` 的噪声和重复事件。
- `indirectMirroringLike` 在 deadzone 之后先做单帧 `0.97 ... 1.03` soft clamp，避免 Mirroring 一帧跳太大。
- 如果 `dt` 超过 `0.05s`，则对 soft clamp 后的 delta 再做 `0.5` 衰减，减轻停手后继续缩放和突发跳变。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: normalizedPinchScaleDelta(rawDelta:source:dt:) / normalizedDirectTouchPinchScaleDelta(_:) / normalizedIndirectMirroringLikePinchScaleDelta(_:dt:)
// 功能说明: 修改后 directTouch 保持较原始响应，indirectMirroringLike 则增加 deadzone、soft clamp 和迟到事件弱化，专门适配 Mirroring pinch。
private func normalizedPinchScaleDelta(
    rawDelta: CGFloat,
    source: PinchInputSource,
    dt: TimeInterval
) -> CGFloat? {
    // Keep source-specific normalization entry points separate so later
    // tuning for Mirroring/indirect pinch does not perturb direct touch.
    switch source {
    case .directTouch:
        return normalizedDirectTouchPinchScaleDelta(rawDelta)
    case .indirectMirroringLike:
        return normalizedIndirectMirroringLikePinchScaleDelta(
            rawDelta,
            dt: dt
        )
    }
}

private func normalizedDirectTouchPinchScaleDelta(_ rawDelta: CGFloat) -> CGFloat? {
    guard rawDelta.isFinite, rawDelta > 0 else {
        return nil
    }
    if abs(rawDelta - 1) < Self.directTouchPinchNoiseDeadzone {
        return nil
    }
    return rawDelta
}

private func normalizedIndirectMirroringLikePinchScaleDelta(
    _ rawDelta: CGFloat,
    dt: TimeInterval
) -> CGFloat? {
    guard rawDelta.isFinite, rawDelta > 0 else {
        return nil
    }
    if abs(rawDelta - 1) < Self.indirectMirroringLikePinchNoiseDeadzone {
        return nil
    }

    let clampedDelta = min(
        max(rawDelta, Self.indirectMirroringLikePinchClampRange.lowerBound),
        Self.indirectMirroringLikePinchClampRange.upperBound
    )
    if dt > Self.indirectMirroringLikeLateEventThreshold {
        return 1 + ((clampedDelta - 1) * Self.indirectMirroringLikeLateEventAttenuation)
    }
    return clampedDelta
}
```
