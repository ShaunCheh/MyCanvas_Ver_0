---
name: iOS拖动跟手修复
overview: 修复 iOS 画布在 raw touch 接入后仍然不跟手的问题，优先消除 `CALayer` 隐式动画带来的视觉滞后，再削减纯平移热路径里的冗余 layer 属性提交。
todos:
  - id: trace-layer-sync
    content: 确认拖动问题本轮只处理 layer 同步链路，不再改 raw touch 状态机和相机几何
    status: pending
  - id: disable-implicit-actions
    content: 在 iOS 视口层和共享图片层双层兜底关闭高频同步属性的隐式动画
    status: pending
  - id: trim-redundant-layer-writes
    content: 减少纯平移场景下对 contents、zPosition、contentsScale 的重复提交
    status: pending
  - id: verify-drag-follow
    content: 验证 iOS 跟手性恢复，并检查 macOS 是否无回归
    status: pending
isProject: false
---

# iOS 拖动跟手修复计划

## 目标

让 iOS 画布在单指拖动和 pinch 结束续拖时做到视觉位移与手指位移同步。本轮先不再改触摸状态机，而是聚焦高频渲染链路里的 `CALayer` 提交行为。

## 关键落点

- `[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift)`
  - 作为整批 layer 同步入口，在 `apply(_:)` / `refreshImageLayers()` 一层统一兜底关闭隐式动画，覆盖图片层更新和可见项增删两条路径。
- `[MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift)`
  - 把图片层做成默认无隐式动画的同步层，并减少纯平移时对 `contents`、`zPosition`、`contentsScale` 的重复写入。
- `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)`
  - 做一致性核对，确认共享层修复不会破坏 macOS 现有画布路径。

## 实施步骤

1. 固定修复范围在 layer 同步链路。
  - 保持现有 `touchesMoved -> onPan -> handlePan -> requestCanvasRefresh -> apply` 几何语义不变，不继续调整 `CanvasCamera` 平移公式或 raw touch 状态机。
2. 在 iOS 视口层做事务级兜底。
  - 在整批 `apply` / `refreshImageLayers` 期间关闭 `Core Animation` actions，重点覆盖 `bounds`、`position`、`contents`、`zPosition`，并一并照顾进入/离开视口时的 layer 增删。
3. 在共享图片层做第二道保险。
  - 让 `CanvasImageLayer` 对高频同步属性默认返回 no-action，避免未来其他调用点绕过视口事务后再次出现同类问题。
4. 清理纯拖动热路径里的冗余属性提交。
  - 纯平移时只更新位置/尺寸；仅当图片内容、层级或 scale 真正变化时才重写 `contents`、`zPosition`、`contentsScale`。
5. 按体感与性能两个维度验证。
  - 先验证单图拖动是否消除“追手/缓动”感，再验证多图场景下是否仍有明显掉帧；如果仍有性能瓶颈，再单独规划 `snapshot` / 可见项排序优化。

## 验证标准

- 单指拖动首帧立即响应，不再出现需要等待视觉追上的感觉。
- 连续平移时，图片视觉位移与手指位移保持同步。
- pinch 结束后的剩余单指续拖不回退到旧问题。
- macOS 现有画布显示与拖动不出现回归。

## 风险控制

- 共享层关闭隐式动画时，只针对画布同步涉及的 key 做定向处理，不做全局 blanket 关闭，避免误伤未来真正需要动画的场景。
- 如果关掉隐式动画后仍然存在明显卡顿，下一轮再进入容器层变换或 `CanvasRenderer`/`CanvasScene` 热路径优化，而不是继续改输入层。

