---
name: 画布范围高亮
overview: 按方案二新增独立的 `CanvasBoardState` 来表达逻辑画布范围，并把画布边界高亮接入现有 `renderer -> snapshot -> viewport` 链路，避免把 board 状态塞进 `CanvasScene` 或平台 view。
todos:
  - id: add-board-state
    content: 新增 CanvasBoardState，建模基础尺寸、当前 worldRect 和四向扩张规则
    status: pending
  - id: snapshot-board-overlay
    content: 扩展 CanvasRenderSnapshot 和 CanvasRenderer，把 board overlay 纳入统一渲染快照
    status: pending
  - id: viewport-board-highlight
    content: 在 iOS/macOS viewport 的 overlayLayer 上新增 board highlight layer 并消费 snapshot.boardOverlay
    status: pending
  - id: controller-board-integration
    content: 在 iOS/macOS controller 中持有 CanvasBoardState，并在导图和拖图后触发边界扩张与刷新
    status: pending
  - id: verify-board-highlight
    content: 验证边界高亮、四向扩张、平移缩放跟随和双平台构建
    status: pending
isProject: false
---

# 画布范围高亮方案二

## 目标

在当前画布架构上新增独立的逻辑画布状态 `CanvasBoardState`，让画布边界成为一份共享的 world-space 真相，并在 iOS/macOS 上把这个边界高亮显示出来。

默认规则按你刚刚确认的语义实现：

- 画布有一个基础尺寸 `baseSize`，当前逻辑边界是 `worldRect`。
- 当图片的 `worldFrame` 触碰或越过右边界时，向右扩一格；左/上/下同理。
- 左扩时 `origin.x` 向左移动一个基础宽度；上扩时 `origin.y` 向上移动一个基础高度。
- 支持一次命中多边时同时扩张；边界只扩不缩。
- 本轮默认在“图片导入后”和“图片拖动过程中”都执行边界扩张判断。

## 共享建模

- 新增 [MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift](MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift)。
  - 最小字段：`baseSize`、`worldRect`。
  - 最小能力：按 `CanvasImageItem.worldFrame` 判断是否触碰 `left/right/top/bottom`，并按基础尺寸更新 `worldRect`。
- 保持 [MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift](MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift) 继续只管图片集合与图片几何，不把 board 状态并进去。
- 保持 [MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift](MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift) 继续只管运行时交互态，例如 `selectedItemID`，不承载 board。

## 渲染链路

- 扩展 [MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift)，新增独立的 `boardOverlay` 渲染数据，而不是把 board 当成“假图片 item”。
- 更新 [MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)，让 renderer 同时消费 `scene + boardState + camera + interactionState`，统一输出：
  - `items`
  - `boardOverlay`
- 继续复用 [MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift](MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift) 的 `worldToViewport(_:)`，由 renderer 负责把 `boardState.worldRect` 转成 screen-space。不要新开 `controller -> viewport` 的直传通道。

## 视图显示

- 在 [MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift) 里复用现有 `overlayLayer`，新增一个专门的 board highlight layer，用来绘制画布边界。
- 在 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift) 做同样的接法，保持双平台一致。
- 画布边界高亮与图片选中高亮分离：
  - 图片选中继续由 [MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift) 处理。
  - 画布边界只走 viewport 的 overlay 子层，不复用 `CanvasImageLayer`。
- 样式上默认使用“范围框”而不是填充块，避免和图片本体高亮混淆。

## 控制器接线

- 在 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 持有 `CanvasBoardState`，与现有 `scene / camera / renderer / interactionState` 并列。
- 在 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 做同样的持有方式，保持共享层状态结构一致。
- 在两端 controller 中接入 board 更新时机：
  - 图片导入并 append 后，拿新 item 的 `worldFrame` 触发一次 board 扩张判断。
  - 拖动已选中图片时，在更新 item 世界坐标后，再对新 `worldFrame` 做 board 扩张判断。
- 刷新路径统一改成基于 `scene + boardState + camera + interactionState` 产出 snapshot，然后由 viewport 一次性消费。

## 实施顺序

1. 新增 `CanvasBoardState`，先把 world-space 画布边界和四向扩张规则建模出来。
2. 扩展 `CanvasRenderSnapshot` 和 `CanvasRenderer`，让 board overlay 进入统一渲染快照。
3. 在 iOS/macOS viewport 里接入 board highlight layer，用 overlay 子层画逻辑画布边界。
4. 在 iOS/macOS controller 中持有 `CanvasBoardState`，把导图和拖图后的边界扩张接入刷新链路。
5. 验证构建与行为，确认画布高亮跟随平移/缩放，并且拖图、选图、画布平移不回归。

## 验证要点

- 初始状态下能看到逻辑画布边界。
- 图片放到右/左/上/下边界时，画布边界按对应方向扩张，且扩张步长等于 `baseSize` 的相应维度。
- 图片触发多边越界时，边界能同时沿多个方向扩张。
- 边界高亮跟随 `camera.pan` 和 `camera.zoom` 正确变换。
- 图片选中蓝边与画布边界高亮不会混淆。
- iOS 和 macOS 构建都通过。

## 风险控制

- 不把 board 状态塞进 `CanvasScene` 或 `CanvasInteractionState`，避免文档数据、交互数据、逻辑画布状态耦合。
- 不让 controller 直接给 viewport 传 `screenRect`，避免形成第二条渲染真相通道。
- board 高亮只走 `overlayLayer`，图片 item 仍只走 `itemsLayer`，保持渲染职责清晰。

