# 20260330_183825_ios_indirect_pan_phase3_record

## 记录范围

- 记录内容：
  1. 为 `handleIndirectPan(_:)` 增加 viewport 同步与可渲染状态校验。
  2. 为 `handleIndirectPan(_:)` 增加上下文菜单短路逻辑。
  3. 为 `handleIndirectPan(_:)` 增加活跃 pointer 交互时的忽略保护，避免与现有手势竞争。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 阶段 4 的方向校正
  - 真机 / Mirroring 运行时回归验证
  - 新的 git commit / push

## 修改一：为 handleIndirectPan(_:) 增加交互保护

### 修改前

- `handleIndirectPan(_:)` 只负责把 `translation` 转交给 `applyCanvasPan(...)`。
- 没有 viewport 尺寸同步、可渲染状态校验、上下文菜单短路，也没有“pointer 正在活跃交互时忽略 indirect pan”的保护。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleIndirectPan(_:) / applyCanvasPan(_:refreshReason:)
// 功能说明: 修改前 indirect pan 进入控制器后会直接走统一平移逻辑，尚未增加与现有手势系统的竞争保护。
private func handleIndirectPan(_ translation: CGPoint) {
    applyCanvasPan(
        translation,
        refreshReason: "indirect pan \(describe(point: translation))"
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

### 修改后

- 先调用 `syncCameraViewportSizeFromCurrentBoundsIfPossible()`，和其他输入入口保持一致。
- `hasRenderableViewportSize == false` 时直接忽略，并沿用现有 `logIgnoredCanvasInput(...)` 记录风格。
- 若上下文菜单处于显示状态，则先 `dismissContextMenu()` 并返回，不立即触发平移。
- 只有当 `pointerDragState == .idle` 时才允许 indirect pan 生效；如果用户正在拖拽元素、裁剪、旋转或拖动画布，则忽略这次 scroll 输入。
- 没有把 indirect pan 写入 `pointerDragState`，也没有主动取消现有 touch 交互。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleIndirectPan(_:) / logIgnoredCanvasInput(_:)
// 功能说明: 修改后 indirect pan 只有在视口可渲染、上下文菜单未显示且 pointer 处于空闲态时，才会进入统一的相机平移逻辑。
private func handleIndirectPan(_ translation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("indirect pan \(describe(point: translation))")
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    guard case .idle = pointerDragState else {
        logIgnoredCanvasInput("indirect pan \(describe(point: translation)) while pointer interaction is active")
        return
    }

    applyCanvasPan(
        translation,
        refreshReason: "indirect pan \(describe(point: translation))"
    )
}

private func logIgnoredCanvasInput(_ input: String) {
    guard Self.isDiagnosticLoggingEnabled else {
        return
    }

    print(
        "[Canvas iOS] ignored input=\(input) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "viewBoundsSize=\(describe(size: canvasViewportView.bounds.size))"
    )
}
```

## 本阶段结果

- indirect pan 现在只会在安全的交互窗口内生效。
- 现有单指拖拽、元素拖动、裁剪、旋转等 pointer 交互优先级高于 indirect pan。
- 上下文菜单显示时，scroll 输入不会直接推动画布移动。
- 本阶段仍未处理方向校正，因此最终滚动方向手感仍需后续阶段在运行环境中确认。
