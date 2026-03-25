---
name: Crop HitTester 分阶段
overview: >-
  基于方案 3，按“先无行为差异重构，再引入新交互语义，最后彻底解耦 pointer/menu”推进。
  前两阶段只做架构整理，真正的用户可见变化集中在 Phase 3-4，最后用 Phase 5-6 完成长期解耦与清理。
todos:
  - id: contract-freeze
    content: 冻结命中语义契约，明确 `cropOutline` 只保留为渲染语义，输入层改用 `cropTranslationArea` 等新命名。
    status: pending
  - id: geometry-foundation
    content: 下沉 `CanvasQuad` 的共享几何能力，为旋转 quad 的精确 hit test 做准备。
    status: pending
  - id: extract-overlay-hittester
    content: 新增 `CanvasEditOverlayHitTester`，先迁移现有 overlay hit test，保持行为等价。
    status: pending
  - id: add-crop-translation-area
    content: 在共享命中层引入 `cropTranslationArea`，让裁剪框内部也可命中平移区域。
    status: pending
  - id: wire-platform-state-machines
    content: 让 iOS/macOS 输入状态机消费 `cropTranslationArea`，接入现有 `movingCropFrame` 流程。
    status: pending
  - id: split-pointer-menu-context
    content: 新增独立 pointer 解析入口，彻底把 pointer target 与 context menu context 解耦。
    status: pending
  - id: cleanup-and-regression
    content: 清理旧命名与旧 helper，统一日志语义并完成双端回归验证。
    status: pending
isProject: false
---

# Crop HitTester 分阶段计划

## 总体策略

- 基于方案 3，按“先无行为差异重构，再引入新交互语义，最后彻底解耦 pointer/menu”推进。
- 前两阶段只做架构整理，真正的用户可见变化集中在 `Phase 3-4`。
- 先保证共享命中层稳定，再让平台状态机接入；最后用 `Phase 5-6` 收口长期架构债。

## 现状问题

- 当前 [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 的命中顺序是 `handle -> cropOutline -> inlineEditBlank -> scene item`，所以裁剪框内部如果没有命中 handle 或 outline，会直接退化成 `.blank`。
- 当前 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 和 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 只有 `.cropOutline` 会进入 `movingCropFrame`。
- 当前控制器拿的是 `CanvasContextMenuContext`，但它同时被拖拽、点击、菜单三条路径共用，pointer/menu 语义已经混在一起。

## Phase 0：契约冻结

- 目标：先把概念边界定死，避免后面继续把 `cropOutline` 同时当“渲染边框”和“交互区域”使用。
- 设计约束：
  - 输入层新增一套更贴近命中语义的类型：`CanvasEditOverlayHitTargetKind`、`CanvasEditOverlayHitTarget`、`CanvasEditOverlayHitTester`。
  - 交互层统一采用 `cropTranslationArea`，不要继续扩散 `cropOutline` 这个命名。
  - `cropOutline` 只保留在纯渲染层，例如 [MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift) 和 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)。
- 产出：
  - 明确的 API 草图。
  - 命名约束。
  - 命中优先级契约：`cropHandle > cropTranslationArea > blank/scene`，其中 Phase 2 先只让边线命中落到 `cropTranslationArea`，Phase 3 再把内部区域纳入。

## Phase 1：几何能力下沉到中性层

- 目标：给共享 hit tester 准备可靠的几何基础。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift](MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift](MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift)
- 任务：
  - 把 `CanvasQuad.cgPath` 从 minimap 几何文件迁回共享几何层，或者独立到中性几何文件。
  - 为 `CanvasQuad` 补齐通用几何能力，例如 `contains(_:)`、`edges`、点到线段距离等命中辅助函数。
  - 明确裁剪内部命中必须用真实四边形判定，不能退化成 `boundingRect.contains`，否则旋转图片会误命中。
- 阶段出口：
  - 共享几何层已经可以支撑旋转 quad 的精确 hit test。
  - 这一阶段不引入任何用户可见行为变化。

## Phase 2：抽出共享的 EditOverlay HitTester，先做到行为等价

- 目标：把当前散落在 resolver 里的 overlay 命中逻辑搬到独立模块，但先不改用户行为。
- 主要文件：
  - 新增 `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift)
- 推荐 API：
  - `resolve(at:renderSnapshot:metrics:) -> CanvasEditOverlayHitTarget?`
- 任务：
  - 在 `CanvasEditOverlayHitTester` 中统一承接 overlay hit test。
  - 先支持现有几类目标：`rotateHandle`、`selectionHandle(role:)`、`cropHandle(role:)`，以及当前等价的 crop 边线命中。
  - 按 Phase 0 的命名冻结，这里内部语义可以直接使用 `cropTranslationArea`，但在行为上只覆盖“现有 outline 边线命中”，不要提前把内部区域纳入。
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 改成编排层：调用 hit tester，再映射回当前 context 语义。
- 阶段出口：
  - 代码结构已经干净。
  - iOS/macOS 当前交互行为和今天一模一样。

## Phase 3：引入真正的 `cropTranslationArea`

- 目标：这是第一阶段用户可见变化，把“按住裁剪框内部任意位置也能移动”的命中语义正式接入共享层。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift)
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
- 任务：
  - 把 `cropTranslationArea` 定义成两部分的并集：
    - `payload.cropScreenQuad` 的内部区域。
    - 现有 `cropOutlineHitTargetWidth` 提供的边线容错区。
  - 让 `Crop` 内部点击不再退化成 `.blank`。
  - 让长按/右键点击裁剪框内部时，拿到和原来 outline 一致的 crop 菜单语义。
  - 更新 `debugName`、resolver branch、context summary，保证日志能区分旧 outline 语义和新的 translation area 语义。
- 阶段出口：
  - 菜单与上下文命中已经支持 `cropTranslationArea`。
  - `Crop` 内部点击不再是 blank，但平台拖拽状态机还未切换到新语义。

## Phase 4：把 iOS/macOS 控制器切到新语义

- 目标：把新的 `cropTranslationArea` 接到现有 `PointerCropTranslationState` 和 `movingCropFrame`。
- 主要文件：
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
- 任务：
  - 在输入状态机里让 `cropTranslationArea` 进入现有的 `movingCropFrame` 路径。
  - 补齐点击日志、`history transaction reason`、release 分支里的 `clickTarget`。
  - 保证：
    - `cropHandle` 仍然只负责 resize。
    - `cropTranslationArea` 负责 move。
    - `blank` 仍然保持画布 pan。
- 阶段出口：
  - 用户层面的目标能力完整生效。
  - 内部拖动、边线拖动、handle resize、画布 pan 的语义清晰分离。

## Phase 5：彻底把 pointer 语义和 context menu 语义拆开

- 目标：获得方案 3 真正的架构收益，避免控制器继续把菜单上下文当成 pointer 输入上下文。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
- 任务：
  - 在 [MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift) 新增独立的 `resolvePointerTarget(at:interactionMetrics:)`。
  - pointer 输入直接消费 `CanvasEditOverlayHitTarget` 或新的 `CanvasPointerPressContext`。
  - 原有 `resolveContext(at:interactionMetrics:)` 只保留给长按/右键菜单。
  - 控制器不再依赖 `CanvasContextMenuTargetKind` 决定拖拽行为。
  - `CanvasContextMenuContext` 中的 `anchorRect`、`selectedItemID` 等菜单专用字段不再污染 pointer 路径。
- 阶段出口：
  - pointer/menu 两条链路彻底解耦。
  - 后续继续演进 hover、cursor、手势扩展时，不再被旧 context 结构拖累。

## Phase 6：清理命名和旧逻辑

- 目标：收掉旧命名、旧 helper 和旧日志语义，让方案 3 真正闭环。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
- 任务：
  - 清理 `CanvasContextResolver` 里已被替换掉的 `resolveCropOutlineTarget`、私有 `ResolvedTarget`、旧的边线 helper 等逻辑。
  - 如果 `cropOutlineHitTargetWidth` 已经不再只代表“边线宽度”，重命名成更准确的 `cropTranslationHitSlop` 或同等语义名字。
  - 统一 `debugName`、日志 `branch` 名称和 click logging，避免继续残留“实际是 translation area，但名字仍叫 outline”的语义债。
- 阶段出口：
  - 命中语义、菜单语义、日志语义一致。
  - 代码只保留一条干净的共享命中链路。

## 推荐落地顺序

- `Phase 0` 是设计对齐，不单独算实现批次。
- 实际编码顺序建议按：`Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6`。
- 其中：
  - `Phase 1-2` 是纯重构，不改行为。
  - `Phase 3-4` 是功能落地。
  - `Phase 5-6` 是把这次改动沉淀成长期可维护架构。

## 验收矩阵

- `iOS`：未旋转图片进入 `Crop`，按住裁剪框内部中心拖动，裁剪框应平移。
- `iOS`：按住边线拖动，仍然应平移，不能因为新增内部命中而丢掉边线容错。
- `iOS`：按住 8 个 handle，仍然只做裁剪尺寸调整，不应误进平移。
- `iOS`：裁剪框外拖动，仍然保持当前画布 pan 语义。
- `macOS`：主键拖拽与 `iOS` 保持一致；右键/secondary click 在裁剪框内部应拿到 crop 菜单。
- `旋转场景`：对一个已旋转的图片进入 `Crop`，点击 quad 的 bounding rect 但在实际四边形外部的位置，不应误命中平移；点击实际四边形内部则必须能命中。
- `事务与提交`：move crop 后的撤销、历史事务、autosave 行为要和当前 `.cropOutline -> movingCropFrame` 保持一致。

## 风险点

- 最大风险不是拖拽本身，而是“命中语义升级后，controller 还继续依赖 menu context”，所以 `Phase 5` 不建议省。
- 第二个风险是误用 `boundingRect` 做 hit test，这会在旋转图片时直接出错。

## 实施与验证约束

- 当前工程里没有现成的 `*Tests*.swift`。
- 当前命令行 `xcodebuild` 也不可直接走完整 Xcode 构建链路。
- 这次验收默认按 `Xcode Build + iOS/macOS 手动交互矩阵` 来做。

