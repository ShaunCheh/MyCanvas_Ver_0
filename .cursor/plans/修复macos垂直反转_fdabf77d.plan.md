---
name: 修复macOS垂直反转
overview: 先回退我本轮引入的错误手工 Y 翻转，恢复原始现场；然后在 macOS viewport 中用运行时证据定位 `image frame` 与 `board path` 的实际坐标语义，最后把两条渲染分支统一到同一个公共坐标边界，根治图片与橙色虚线框垂直方向解释不一致的问题。
todos:
  - id: rollback-wrong-manual-flip
    content: 撤回当前 macOS viewport 中手工 layerRect 翻转，恢复原始现场
    status: pending
  - id: capture-runtime-coordinate-evidence
    content: 补最小化运行时证据，确认 image frame 与 board path 谁在按 bottom-left 解读 screenY
    status: pending
  - id: unify-macos-render-boundary
    content: 在 macOS viewport 内建立唯一的公共坐标边界，让 board 和 image 共享同一套 Y 轴语义
    status: pending
  - id: verify-macos-canvas-direction
    content: 回归验证拖动画布、滚轮平移、缩放、拖图与 board 扩张后的方向一致性
    status: pending
isProject: false
---

# 修复 macOS 垂直反转计划

## 根因结论

共享层 `[MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift)` 与 `[MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)` 产出的 `screenFrame/screenRect` 是同一套 top-left viewport 坐标，`pan` 数学本身没有分叉。

真正的问题出在 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)`：macOS 端把同一份 `screenY` 同时喂给了 `CALayer.frame` 和 `CAShapeLayer.path` 两条不同的 layer 语义，又混用了 `NSView.isFlipped` 与多层 `isGeometryFlipped`，导致图片分支和 board 分支对垂直方向的解释不一致。

当前文件里我后来加上的手工 `layerRect(fromViewportRect:)` 只是把两条分支一起翻错了，必须先撤回：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
let layerItem = CanvasRenderItem(
    id: item.id,
    screenFrame: layerRect(fromViewportRect: item.screenFrame),
    cgImage: item.cgImage,
    zIndex: item.zIndex,
    isSelected: item.isSelected
)

boardHighlightLayer.path = CGPath(
    rect: layerRect(fromViewportRect: boardOverlay.screenRect),
    transform: nil
)
```

## 修复目标

在 macOS 端建立唯一的“viewport 坐标 -> 渲染 layer 坐标”边界：

- `[MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift)` 和 `[MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)` 继续只负责输出 top-left viewport 坐标
- `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)` 只保留一处公共坐标转换/翻转真相
- `board` 和 `image` 必须走同一个坐标边界，不能再分别靠 `path`、`frame`、`isGeometryFlipped` 各自猜 Y 轴语义

## 实施步骤

1. 回退错误补丁

在 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)` 先撤掉我新加的 `layerRect(fromViewportRect:)` 路径，恢复到原始 asymmetry 现场，避免“两个都错”掩盖真实根因。

1. 补最小化运行时证据

只在 macOS viewport 层补临时诊断，记录一次拖动 tick 中这几组值：

- `snapshot.items.first?.screenFrame`
- 对应 `CanvasImageLayer.frame`
- `boardHighlightLayer.path` 的 bounding box
- `layer?.isGeometryFlipped`、`itemsLayer.isGeometryFlipped`、`overlayLayer.isGeometryFlipped`、`boardHighlightLayer.isGeometryFlipped`

目标是确认到底是哪一条链路在运行时仍按 bottom-left 解读 `screenY`，避免再次靠猜测改坐标。

1. 收敛为单一坐标真相

在 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)` 统一 `board` 与 `image` 的消费边界。优先方案：

- 保持共享 snapshot 仍输出 top-left viewport 坐标
- 在 macOS viewport 内引入一个公共 render 容器或等价的单点转换，让 `itemsLayer` 与 `overlayLayer` 共享同一套坐标空间
- 移除按分支分别处理 `frame/path` 的补丁式翻转，避免再次出现“一支向上、一支向下”或“两支一起错”的情况

1. 回归验证

验证以下场景：

- 左键向上、向下拖动画布时，图片和橙色虚线边框同向移动
- 滚轮平移与缩放后，图片和 board 继续保持同向
- 选中图片后拖动图片，不影响 board 的方向语义
- board 四向扩张后，边框与图片仍然在同一坐标系下渲染

## 影响文件

- 主要修改：[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)
- 可能增加/删除少量辅助日志：[MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift)
- 不应修改共享数学层：[MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift)、[MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)

