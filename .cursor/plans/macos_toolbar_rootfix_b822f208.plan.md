---
name: macOS toolbar rootfix
overview: 围绕已确认的 macOS toolbar hidden geometry 泄漏问题，按当前共享 toolbar 几何与 macOS 控制器过渡架构制定根因修复方案，不做代码修改。计划内容与上一条答复保持一致：先补 hidden geometry contract，再收口 steady layout 与 transition 起点，最后做定向验证，不增加长期日志。
todos:
  - id: define-hidden-geometry-contract
    content: 在共享 toolbar 几何层建立隐藏态 toolbar 的合法几何 contract，避免空 toolbar 退化成 .zero + no-op。
    status: pending
  - id: reconcile-macos-steady-layout
    content: 收口 macOS steady layout 写入路径，让阅读态主动落到合法 hidden/offscreen frame，而不是保留 bootstrap/stale frame。
    status: pending
  - id: unify-transition-start-source
    content: 让 toEditing 的 entering 起点与阅读态 steady hidden state 共用同一来源，消除首帧脏状态泄漏。
    status: pending
  - id: run-focused-validation
    content: 按几何校验、运行时回归和日志策略完成定向验证，不新增长期日志。
    status: pending
isProject: false
---

# macOS Toolbar Hidden Geometry 根因修复计划

## 根因确认

- 当前原因已经足够确定，不建议先加长期日志。
- [MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift) 的 `mainToolbarState(...)` 在阅读态返回空 toolbar。
- [MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift) 在空测量尺寸下会得到 `toolbarFrame = .zero`。
- [MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift) 的 `CanvasChromeLayoutGeometry.sanitizedRect(...)` 会丢弃 `0x0` rect。
- [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 的 `applyToolbarFrame(_:)` 因此不会把隐藏态 frame 回写到 host，`toolbarHostView` 会继续保留 bootstrap 或 stale frame。
- 第一次 `toEditing` 时，这个残留 frame 会在 entering 首帧泄漏，视觉上就像 toolbar 还是从左边出来。

## 修复计划

### 1. 建立隐藏态 toolbar 的合法几何 contract

- 不再让“空 toolbar = `.zero` frame = 什么都不做”继续存在。
- 在共享层新增一个专门的 hidden geometry helper，放在 [MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift) 和 [MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift) 这一层附近，而不是把 empty-toolbar 特判散落到控制器里。
- 这个 helper 负责基于 `CanvasToolbarPlacement`、`safeBounds` 和 blockers 计算一个合法的 `collapsedFrame` / `offscreenFrame`，保证它是非零、可动画、可复用的隐藏态几何。
- 目标是把阅读态 steady frame 和编辑态 entering 起点统一到同一套几何来源。

### 2. 收口 macOS steady layout，不再让 hidden host 保留 bootstrap frame

- 在 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 收口 toolbar frame 写入入口，重点不是改动画，而是改 steady-state 几何落点。
- 重点收口的方法是 `updatePreparedToolbarPlacement()`、`performOverlayLayoutPass()` 和 `applyToolbarFrame(_:)`。
- 有 toolbar item 时，继续沿用现有 placement pass。
- 空 toolbar 时，不再因为 `.zero` 被 `return`，而是把 `toolbarHostView.frame` 主动放到第 1 步算出来的 hidden 或 offscreen frame，同时保留 `toolbarHostView.isHidden = true`。
- 这样阅读态结束后，host 留下的是右侧隐藏位，而不是 `{{0,0},{68,68}}` 的 bootstrap 位。

### 3. 让 transition 起点和 steady hidden state 共用同一来源

- 在 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 的 `beginToolbarModeTransition(to:)` 和 `prepareToolbarTransitionContext(direction:)` 这条链上，`toEditing` 不应该再隐式依赖 host 当前残留 frame 是否干净。
- `toEditing` 的初始 entering 起点要和阅读态 steady hidden frame 完全一致。
- `finishToolbarModeTransition(applying:)` 落到阅读态时，也要回到同一个 hidden frame。
- 这样首开、热切换和中断重基线都会走同一套 contract，transition 只是把 host 从正确的隐藏位带到可见位，而不是夹带历史脏状态。

### 4. 明确边界，不做偏修

- 不放宽 [MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift) 的 `sanitizedRect(...)` 让 `.zero` 通过。
- 不把 frame 逻辑塞进 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)。
- 不单独改 `ToolbarTransition` 的动画方向。
- 不继续叠加长期日志来“观察”。
- 原因是前两种会破坏之前为 bootstrap 和约束稳定性做的保护，后两种只是在治表现，不是在治根因。

## 验证计划

- 纯几何验证：给共享 hidden geometry helper 补一个聚焦测试，确认 trailing placement 下的 hidden 或 offscreen frame 不会落在 `{0,0}` 一带。
- 运行时回归：macOS 首次打开且初始为阅读态时，第一次切编辑态，toolbar 不再从左侧或左上角出现。
- 运行时回归：阅读态反复切编辑态，动画持续保持从右侧进入。
- 运行时回归：窗口 resize 后再切换，toolbar、minimap 和 blocker 仍然正确。
- 回归护栏：不回退之前修过的 bootstrap 和 constraint 稳定性问题。

## 日志策略

- 当前没必要增加长期日志。
- 如果担心修完还有 1 帧闪现，只在实现阶段临时加一条很短的 scoped 校验，确认阅读态 settled 后 `toolbarHostView.frame` 已经不再是 bootstrap frame；验证完成后删除，不留下长期噪音。

