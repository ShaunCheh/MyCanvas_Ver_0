---
name: 修复macOS坐标反向
overview: 修复 macOS 画布中 board 边框与图片在拖动画布时方向相反的问题，根因定位为视口渲染层的坐标翻转策略不一致。计划将统一 macOS 端的坐标语义，并覆盖拖动、缩放、选中与边界高亮的回归验证。
todos:
  - id: audit-macos-flip-chain
    content: 梳理 macOS viewport 中 NSView.isFlipped 与各层 isGeometryFlipped 的当前关系，确定唯一坐标真相
    status: pending
  - id: unify-board-image-coords
    content: 在 macOS viewport 内统一 board path 与 image frame 对 screen 坐标的解释，消除方向相反现象
    status: pending
  - id: regression-verify-canvas
    content: 回归验证 macOS 的画布拖动、缩放、图片拖拽与 board 高亮扩张
    status: pending
isProject: false
---

# 修复 macOS 画布坐标反向计划

## 根因判断

当前共享链路 `[MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift)` 和 `[MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)` 同时为 `boardOverlay.screenRect` 与 `item.screenFrame` 产出同一套 viewport 坐标；如果是 `pan` 数学或 `worldToViewport` 符号错误，board 和图片应该一起反向，而不是一上一下。

真正的分叉点在 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)`：同一个 macOS 视口同时使用 `NSView.isFlipped = true` 和多层 `isGeometryFlipped = true`，但 `board` 走 `CAShapeLayer.path`，图片走 `CALayer.frame`，两条渲染链没有绑定到同一套坐标约定。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
override var isFlipped: Bool {
    true
}

backgroundLayer.isGeometryFlipped = true
itemsLayer.isGeometryFlipped = true
overlayLayer.isGeometryFlipped = true
boardHighlightLayer.isGeometryFlipped = true
```

## 修复策略

以 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)` 的 `NSView.isFlipped = true` 作为 macOS 视口唯一的 top-left 坐标真相，停止让 `board` 与 `image` 各自依赖额外的 layer 翻转配置。

1. 收敛翻转来源

清理 `macOSCanvasViewportView` 中对 `backgroundLayer`、`itemsLayer`、`overlayLayer`、`boardHighlightLayer` 的手动 `isGeometryFlipped` 依赖，避免 AppKit 的 flipped view 语义与手动 layer flip 叠加。

1. 统一 board 与 image 的 screen 坐标消费方式

保留共享层 `[MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)` 输出的 `screenRect/screenFrame` 不变，只在 macOS viewport 内统一解释：

- 图片仍由 `[MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift)` 消费 `frame`
- board 由 `refreshBoardHighlight()` 消费 `screenRect`
- 若移除手动翻转后 `CAShapeLayer.path` 与图片仍不一致，则只允许在 board path 生成处做一次显式坐标转换，禁止再引入第二套翻转来源

1. 保持共享层不被污染

不修改 `[MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift)` 的 `pan/worldToViewport` 约定，也不改 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 的拖动路由；这样 iOS 与共享数学保持稳定，修复面限定在 macOS 专有视口层。

## 实施步骤

1. 审视并收敛 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)` 的 layer 初始化与 `updateLayerFrames()`，建立一套单一的 flipped 规则。
2. 调整 `refreshBoardHighlight()`，确保 `boardHighlightLayer.path` 和 `CanvasImageLayer.frame` 对同一个 `screenY` 使用同一坐标语义。
3. 回看 `[MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift)`，确认图片 layer 本身没有额外翻转、anchor、transform 导致二次反向。
4. 在不改共享数学的前提下，验证 macOS 的直接拖动画布、滚轮平移、缩放、选中拖图、board 四向扩张高亮是否一致。

## 验证范围

- 鼠标左键按住向下拖动画布：board 和图片必须同向向下移动。
- 鼠标左键按住向上拖动画布：board 和图片必须同向向上移动。
- 选中图片后拖拽图片：图片位置变化正确，board 高亮只在越界扩张时变化，不应出现反向运动。
- 滚轮平移与缩放：图片和橙色虚线边框继续同向跟随，不引入新的上下颠倒。
- 不影响 iOS：仅改 macOS 视口层，不触碰 iOS viewport 逻辑。

