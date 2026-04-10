---
name: macos_chrome_root_fix
overview: 以 `macOS` 的 `chromeOverlayView` 为唯一几何真源，统一 toolbar/minimap/按钮/transition 的坐标语义与首次布局时机，从根因修复“工具栏从左下冒出”和“首次开板 minimap 与返回按钮重叠”两个问题。
todos:
  - id: unify-macos-chrome-space
    content: 统一 `chromeOverlayView` 及其子视图的坐标语义，收敛为单一几何真源。
    status: pending
  - id: stabilize-initial-blockers
    content: 重构首次 overlay layout 时机，确保 `backButton`/`modeToggle` frame 有效后再求解 `minimap` 稳态位置。
    status: pending
  - id: normalize-toolbar-transition-start
    content: 拆分 toolbar 初始摆位与正式动画，消除从 bootstrap `0,0` 起跳的错误首跳。
    status: pending
  - id: align-shared-geometry-contract
    content: 复核 shared `toolbar/minimap` solver 与新的 macOS 坐标语义，移除平台补偿心智。
    status: pending
  - id: verify-with-runtime-logs
    content: 基于现有 toolbar/minimap 日志回归首次开板、模式切换、窗口 resize 和 chrome 交互场景。
    status: pending
isProject: false
---

# macOS Chrome 根因修复计划

## 目标

- 从架构层统一 `macOS` chrome 区域的坐标语义，消除 `toolbar` 和 `minimap` 在 `macOS` 上的视觉偏差。
- 修复两类已证实问题：
  - `阅读模式 -> 编辑模式` 时工具栏先从左下 bootstrap 位置误动画，再从右边进入。
  - 首次打开画板时 `minimap` 先按“无 blocker”路径落位，和左上角返回按钮重叠。

## 已确认的根因

- `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift)` 当前没有显式 `isFlipped`，`chromeOverlayView` 仍是 `non-flipped`，而共享 `toolbar/minimap` 几何又天然按 `minY/maxY` 表达“上/下”。这让 `macOS` 上的视觉上下语义与 `iOS`/`viewport` 不一致。
- `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 中：
  - `toolbarLayoutSafeBounds()` 直接基于 `view.bounds + safeAreaInsets` 造几何输入。
  - `performOverlayLayoutPass()` 在 `backButton` / `workspaceModeButton` frame 仍为零时就可能先跑一轮，`baseChromeBlockersForToolbarLayout()` 因此返回空数组，导致 `minimap` 首次按“无 blocker”路径落位。
  - `toEditing` 过渡起点读取到了 bootstrap 的 `toolbarHostView.frame == {{0,0},{68,68}}`，因此 host 先从左下角动画到右侧 offscreen，再开始正确的 entering/expanding。
- `[MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift](MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift)` 的 `CanvasOverlayLayoutSolver` 本身会正确避让 blocker；日志已经证明当 `backButton` frame 有效时，`miniMapFrame.y` 会被准确推到 `210`，说明 solver 不是主因，主因是输入坐标与输入时机。

## 修复策略

- 不做两个问题各自的局部补丁，而是把 `macOS` 的 chrome 求解链统一到同一套可比较的坐标空间和同一生命周期。
- 优先方案：把 `chromeOverlayView` 明确收敛为与 `viewport/context menu` 一致的视觉坐标语义，并让所有 chrome 子元素、solver 输入、transition 采样都以它为单一真源。
- 同时补齐首次布局稳定机制：只有在 blocker frame 有效后，才允许 `minimap` 的最终稳态落位；toolbar 进入动画则必须先无动画落到 offscreen 起点，再启动进入动画，禁止从 bootstrap frame 直接参与动画。

## 实施步骤

### 1. 统一 macOS chrome 坐标真源

- 调整 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift)`，明确 `chromeOverlayView` 的坐标语义，不再依赖 `NSView` 默认 `non-flipped` 行为。
- 在 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 里，把 `safeBounds`、blocker 采样、`toolbarHostView.frame`、`miniMapMountView.frame` 的输入/输出全部绑定到 `chromeOverlayView` 坐标系，而不是混用根 `view` 坐标和 overlay 子视图 frame。
- 同步复核受影响的 overlay 子元素：`backButton`、`workspaceModeButton`、`textEditorOverlayView`、`toolbarHostView`、`miniMapMountView`、`contextMenuHostView`。

### 2. 收敛首次布局时机，修复 minimap 首次重叠

- 重构 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 的 `performOverlayLayoutPass()` / `updateChromeOverlayLayout()` / `baseChromeBlockersForToolbarLayout()`：
  - 首次开板时，若 `backButton` / `workspaceModeButton` frame 仍非法或为零，不直接把这轮结果视为最终稳态。
  - 在 chrome 控件 frame 从零变为有效后，强制重跑一轮 overlay layout，确保 `minimap` 的最终落位基于真实 blocker。
- 保留当前已加日志作为回归依据，直到验证完成后再决定是否降噪。

### 3. 修复 toolbar 的错误首跳与进入锚点

- 调整 `[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)` 中的 `beginToolbarModeTransition(...)`、`prepareToolbarTransitionContext(...)`、`currentToolbarTransitionStartFrame(...)`、`animateToolbarTransition(...)`：
  - `toEditing` 时先把 host 无动画摆到 `offscreenFrame`，再启动 `entering -> expanding`；不能再从 bootstrap 的 `{{0,0},{68,68}}` 起跳。
  - 若 placement 尚未稳定，transition 不应读取 bootstrap frame 作为真实起点。
- 复核 `[MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)` 的 `renderTransition(_:)` / `applyTransitionFrame(...)`，确保“初始摆位”和“正式动画”分离。

### 4. 对齐共享几何与平台语义

- 复核 `[MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift)`、`[MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementPass.swift)`、`[MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift](MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift)`、`[MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift](MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift)` 与新的 `macOS overlay` 坐标语义是否完全一致。
- 去掉当前仅靠日志解释的 `visualPreferredMiniMapAnchor` 式补偿心智，改成平台层真实坐标与 solver 语义天然一致。

## 验证计划

- 用现有日志回归两条现象：
  - `toolbar`：`currentHostFrame` 不再从 `{{0,0},{68,68}}` 动画到右侧，首帧应先稳定在 `offscreenFrame`，随后只出现 `right(+x)` 的 entering 和正确的 expanding。
  - `minimap`：首次开板时第一轮有效 `ChromeOverlayLayout` 就应包含 `backButton` blocker，`overlapBackButton=false` 且 `miniMapFrame` 不再落到视觉左上重叠区。
- 手动回归 `macOS` 特有风险点：窗口首次打开、从 BoardList 双击进入、模式切换、窗口 resize、context menu、text editor overlay、toolbar layout reconcile。
- 保持 `macOS` 工程构建通过，并确认不引入新的约束冲突或 frame sanitize 问题。

