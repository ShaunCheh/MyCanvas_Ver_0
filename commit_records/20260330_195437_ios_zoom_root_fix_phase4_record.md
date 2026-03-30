# 20260330_195437_ios_zoom_root_fix_phase4_record

## 记录范围

- 记录内容：
  1. 在 `iOSViewController.handleZoom(_:around:)` 中补充 `zoomBefore` / `zoomAfter` 比较。
  2. 当缩放已被 min/max clamp 成 no-op 时，直接跳过后续 `requestCanvasRefresh(...)`、`scheduleAutosave(...)` 和有效缩放日志分发。
  3. 将 `logZoomDispatch(...)` 的 `zoomAfter` 参数改为复用本次已计算出的 `zoomAfter`，避免重复读取相机状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 阶段 5 的 zoom autosave 改为手势结束后调度
  - 阶段 6 的 A/B 日志验证与日志收敛

## 修改一：`handleZoom(_:around:)` 为 no-op zoom 增加短路保护

### 修改前

- `handleZoom(_:around:)` 在执行 `camera.zoom(by:around:)` 之后，不区分 `camera.zoomScale` 是否真的发生变化。
- 这意味着当缩放已经到达 `0.1` 或 `8.0` 边界、并被 clamp 成 no-op 时，控制器仍然会继续：
  - `requestCanvasRefresh(...)`
  - `scheduleAutosave(reason: "zoom canvas")`
  - `logZoomDispatch(...)`
- Mirroring 的迟到 pinch 事件在这种路径下会继续放大视觉噪声和无意义的后台工作。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleZoom(_:around:)
// 功能说明: 修改前无论 zoom 是否真正变化，都会继续刷新、调度 autosave，并记录一次控制器层 zoom 分发日志。
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
    let afterZoomApply = ProcessInfo.processInfo.systemUptime
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
        zoomAfter: camera.zoomScale,
        applyCostMs: (afterZoomApply - eventTime) * 1000,
        refreshCostMs: (afterRefresh - afterZoomApply) * 1000,
        autosaveCostMs: (afterAutosave - afterRefresh) * 1000,
        totalCostMs: (afterAutosave - eventTime) * 1000
    )
}
```

### 修改后

- 在 `camera.zoom(by:around:)` 之后立刻读取 `zoomAfter`。
- 如果 `zoomAfter == zoomBefore`，说明本次缩放已被 clamp 成 no-op，则直接返回。
- 只有当 zoom 真实变化时，才继续刷新画布、调度 autosave，并记录控制器层 zoom 日志。
- 这样可以把阶段 3 过滤不掉、但最终落到边界后无效的 Mirroring pinch 事件拦在控制器层，避免继续制造 refresh / autosave 噪声。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleZoom(_:around:)
// 功能说明: 修改后会在相机缩放应用后检查 zoom 是否真实变化；若已被 clamp 成 no-op，则直接跳过 refresh、autosave 和有效 zoom 日志。
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

## 结果说明

- 本阶段没有改变 zoom 的计算方式，也没有改动视图层 pinch 输入归一化。
- 本阶段只是在控制器层增加“实际没变就不继续做事”的保护，属于边界收口。
- 这样做可以直接削掉到达缩放上下限后的无意义刷新与 autosave，为下一阶段把 autosave 改成“手势结束后调度”继续减压。
