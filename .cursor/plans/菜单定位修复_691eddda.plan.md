---
name: 菜单定位修复
overview: 修复上下文菜单偏离触点/光标的根因：统一锚点语义、改正布局首选策略，并在 macOS 上补齐 viewport 到 overlay/host 的坐标空间归一。保持共享层为主，不在 iOS/macOS 各自堆平台补丁。
todos:
  - id: anchor-semantics
    content: 重构共享菜单锚点语义，区分目标几何信息与菜单实际锚点
    status: pending
  - id: resolver-output
    content: 调整 ContextResolver，让 body 与 cropOutline 默认跟随 invocation point
    status: pending
  - id: coordinate-normalization
    content: 在 iOS/macOS 的 presentation bridge 中统一 viewport 到 host 的坐标转换，解决 macOS flipped 差异
    status: pending
  - id: layout-strategy
    content: 改写 LayoutSolver 的候选方向排序逻辑，按真实剩余空间而不是中线决定首选落位
    status: pending
  - id: verify-positioning
    content: 用现有位置日志回归 blank、body、cropOutline 场景，并完成 iOS/macOS 双端编译验证
    status: pending
isProject: false
---

# 菜单定位修复计划

## 根因确认

- `[CanvasContextMenuContext.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)`：当前 `anchorPoint` 只要存在 `anchorRect` 就直接取中心，导致 `selectedItemBody`、`unselectedItemBody`、`cropOutline` 的菜单位置跟随对象中心，而不是跟随用户实际点击/长按的位置。
- `[CanvasContextResolver.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)`：`item body` 命中时把 item 的 `screenQuad.boundingRect` 作为 `anchorRect`；`cropOutline` 命中时把 crop quad 的包围盒作为 `anchorRect`，进一步放大了偏移。
- `[CanvasContextMenuState.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift)`：`resolveMenuFrame()` 目前按 `anchorPoint` 是否落在中线左/右、上/下决定首选方向，而不是按四周真实剩余空间决定，所以即使触点附近有空间，也可能被翻到左边或上边。
- `[macOSCanvasViewportView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)`、`[macOSCanvasChromeOverlayView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift)`、`[CanvasContextMenuHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift)`：macOS 的 viewport 是 flipped，但 overlay/host 默认不是 flipped，当前又直接把 viewport 语义的点喂给 host 布局，macOS 会额外产生 y 方向错位。

```52:60:/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
    var anchorPoint: CGPoint {
        guard let anchorRect else {
            return invocationViewportPoint
        }

        return CGPoint(
            x: anchorRect.midX,
            y: anchorRect.midY
        )
    }
```

```64:79:/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
        let prefersTrailing = anchorPoint.x < layoutBounds.midX
        let prefersBottom = anchorPoint.y < layoutBounds.midY
        let placements = candidatePlacements(
            prefersTrailing: prefersTrailing,
            prefersBottom: prefersBottom
        )

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude
```

```68:69:/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
    override var isFlipped: Bool {
        true
```

## 实施方案

- 调整共享锚点语义：在 `[CanvasContextMenuContext.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)` 中把“目标几何信息”和“菜单锚点”解耦。`blank`、`selectedItemBody`、`unselectedItemBody`、`cropOutline` 默认改为使用 `invocationViewportPoint` 作为菜单锚点；`rotateHandle`、`selectionHandle`、`cropHandle` 继续使用 handle 中心，保持小目标菜单的稳定性。
- 收敛 resolver 输出：在 `[CanvasContextResolver.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)` 中保留 `anchorRect` 作为目标几何信息，但不再让 `item body` / `cropOutline` 依赖其中心来决定菜单落点。这样命中语义和菜单锚点语义分层清楚，后续不会再因为大图或旋转包围盒而偏离触点。
- 增加 presentation bridge：在 `[iOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)` 和 `[macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 的 `presentContextMenu(...)` 链路中，把 resolver 产出的 viewport 坐标/rect 显式转换到 `contextMenuHostView` 坐标系后，再冻结到菜单 state。iOS 这里应当是等价转换；macOS 在这里彻底解决 flipped 差异。
- 重写布局首选策略：在 `[CanvasContextMenuState.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift)` 中，把首选方向从“按中线翻面”改为“按 anchor 四周的真实可用空间排序候选方向”。默认优先贴近触点右下，右下放不下时再尝试右上、左下、左上，同时继续保留 `safeBounds` clamp 和 `occupiedRects` 避让。
- 维持共享 UI 宿主不变：`[CanvasContextMenuHostView.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift)` 继续只负责接收已经归一过的 state 并执行布局，不把平台坐标修正逻辑塞回 host 内部，避免宿主再次耦合 `viewport` 概念。

## 验证计划

- 使用现有 `ContextMenuInput` / `ContextMenuPosition` / `ContextMenuLayout` 日志，分别回归 `blank`、`selectedItemBody`、`unselectedItemBody`、`cropOutline` 四类场景，确认 `anchorPoint` 与触点/光标一致，且 `resolvedMenuFrame` 紧邻触点而不是对象中心。
- 重点复测 macOS：验证 flipped 坐标修正后，菜单不会再出现明显的 y 方向镜像偏移。
- 重点复测 iOS：确认改成共享锚点语义后，长按菜单位置更贴近手指，同时不破坏现有 blocker 避让和边界 clamp。
- 做双端编译验证：`generic/platform=macOS`、`generic/platform=iOS`。
- 命令面不在本次调整范围内：`[CanvasContextMenuCommandResolver.swift](/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift)` 不需要改动，避免把“菜单内容”问题和“菜单位置”问题混在一起。

