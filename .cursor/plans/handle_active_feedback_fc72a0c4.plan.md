---
name: handle active feedback
overview: 采用方案三，为所有 canvas handle 建立共享 identity、pressed/dragging 状态机和 normal/active 渲染语义。保持现有 resize/crop/rotate/arrow/group 几何、history 与 autosave 路径不变，仅抽离 handle 的瞬态生命周期和视觉反馈。
todos:
  - id: handle-contract
    content: 阶段1：建立共享 handle identity、pressed/dragging 状态机及纯单元测试
    status: pending
  - id: handle-identity-pipeline
    content: 阶段2：将 identity 贯穿 renderer geometry、hit tester、context resolver 和 pointer context
    status: pending
  - id: handle-session-render
    content: 阶段3：接入 CanvasEditorSession 瞬态状态并投影到 snapshot visualState
    status: pending
  - id: handle-pointer-lifecycle
    content: 阶段4：统一接入 iOS/macOS pointer pressed、dragging、idle/cancel 生命周期
    status: pending
  - id: handle-visual-style
    content: 阶段5：抽取共享 normal/active 样式并更新双端 viewport 全部 handle layer
    status: pending
  - id: handle-boundaries
    content: 阶段6：加固失败、取消、菜单、transition、恢复和模式切换清理路径
    status: pending
  - id: handle-regression
    content: 阶段7：补齐 renderer/context/session 测试并执行双端回归验证
    status: pending
  - id: handle-cleanup
    content: 阶段8：清理重复平台逻辑并确认 persistence/history/autosave 零变化
    status: pending
isProject: false
---

# Canvas Handle Active Feedback 分阶段计划

## 目标与边界
- pointer down 命中具体 handle 后立即变色，不等待 4pt drag threshold。
- 超过阈值进入 dragging 后，即使指针离开原 hit rect，也保持同一 handle active。
- pointer up、cancel、失败回到 idle、长按/右键菜单抢占、transition freeze、切换 board 或恢复 history 后恢复 normal。
- 只让命中的 handle 变色；其他 handle 保持 normal。
- 覆盖 selection resize、multi-selection resize、crop、single/multi rotate、arrow endpoint 和 group frame resize。
- 不把状态写入文档、history 或 autosave；不迁移现有几何与事务逻辑；translation area 和 item/group body 不属于 handle。

## 核心数据结构
在 [Canvas/Core/CanvasEditHandleIdentity.swift](MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift) 新增稳定身份，避免只靠重复的方位 role 判断：

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift
// 稳定标识 owner、handle family 与 role；不包含屏幕坐标等易变几何。
struct CanvasEditHandleIdentity: Hashable, Sendable {
    let owner: CanvasEditHandleOwner
    let kind: CanvasEditHandleKind
}
```

- `CanvasEditHandleOwner`：single item、包含 primary 和无序 member set 的 multi-selection、canvas group。
- `CanvasEditHandleKind`：selection resize、crop resize、rotate、arrow endpoint、group frame resize。
- 为 `CanvasSelectionHandleRole`、`CanvasCropHandleRole`、`CanvasArrowEndpointRole`、必要的 edit role 补齐 `Hashable/Sendable`。
- multi-selection identity 使用无序 member 集合，避免相同成员因数组顺序不同产生不同 identity。

在 [Canvas/Input/CanvasEditHandleInteractionState.swift](MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift) 新增纯状态机：
- phase：inactive、pressed(identity)、dragging(identity)。
- event：press(identity?)、beginDragging(expectedIdentity)、end、cancel。
- `visualState(for:)`：只返回 normal/active；pressed 与 dragging 都映射为 active。
- transition 结果区分 state change 与 visual change，避免 pressed -> dragging 触发无意义的额外刷新。

目标数据流：

```mermaid
flowchart LR
    pointerInput["平台 Pointer 事件"] --> contextResolver["CanvasContextResolver<br/>命中稳定 HandleIdentity"]
    contextResolver --> lifecycleState["共享 Handle 状态机<br/>pressed 或 dragging"]
    lifecycleState --> editorSession["CanvasEditorSession<br/>非持久化瞬态状态"]
    editorSession --> canvasRenderer["CanvasRenderer<br/>生成 identity 与 visualState"]
    canvasRenderer --> renderSnapshot["CanvasRenderSnapshot"]
    renderSnapshot --> platformViewport["iOS/macOS Viewport<br/>应用共享视觉样式"]
    platformViewport --> activeLayer["仅当前 Handle 变色"]
```

## 阶段 1：共享 identity 与状态机契约
- 新增上述 Core/Input 文件，将“哪个 handle”和“当前生命周期”分离。
- 明确状态规则：重复 press 幂等；dragging 只接受与 pressed 相同的 identity；end/cancel 总是回 inactive；press(nil) 清除陈旧状态。
- 新增 [CanvasEditHandleInteractionStateTests.swift](MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift)，覆盖所有 identity family、multi-selection 顺序不敏感、pressed/dragging/end/cancel、identity mismatch 和 visual-change 返回值。
- 本阶段不接 controller 和 renderer，现有行为不变。

## 阶段 2：identity 贯穿 renderer、hit-test 与 pointer context
- 扩展 [CanvasRenderSnapshot.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift) 中的 `CanvasEditHandleGeometry`，增加 `identity` 和 `visualState`；默认 visual state 为 normal。
- 更新 [CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift) 的 selection、multi-selection、crop、rotate、arrow endpoint、group frame handle 构建函数，为每个 geometry 生成完整 identity。
- rotate handle 位于 `rotateAffordance.handle`，group frame handle 位于 `groupEditOverlay.handles`，两条非普通数组路径必须单独覆盖。
- 更新 [CanvasEditOverlayHitTester.swift](MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift)，命中时直接返回 geometry 自带 identity，不重新根据 role 拼装。
- 更新 [CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 和 [CanvasPointerPressContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift)，把 identity 透传为 `targetHandleIdentity`；translation/body/blank 保持 nil。
- 保留现有 `CanvasPointerTargetKind` 分支用于几何行为，identity 只作为生命周期和视觉来源。
- 新增 hit-test/renderer contract 测试，确认 selection 与 crop 的同方位 role 不冲突，multi-selection 与 canvas group 不混淆。

## 阶段 3：Session 瞬态状态与 snapshot 投影
- 在 [CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift) 增加 `editHandleInteractionState`，与 rotation/alignment interaction state 同级管理。
- 增加 presentation 入口：reading mode、inline edit 不展示 active handle；状态仍不得进入 `BoardHistorySnapshot` 或存储 mapper。
- `makeCanvasSnapshot()` 将 interaction state 传入 `CanvasRenderer.makeSnapshot(...)`。
- renderer 对每个 geometry 调用 `visualState(for: identity)`，只标记完全匹配的 handle 为 active。
- `applyBoardRuntimeState`、`applyBoardHistorySnapshot`、切换 board 等现有 transient reset 路径同步清空状态。
- 在现有 session overlay 测试基础上增加：默认全部 normal、exact identity active、reading mode 隐藏、runtime/history restore 清空、history snapshot 前后相等。

## 阶段 4：iOS/macOS pointer 生命周期接入
- 在 [iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 和 [macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 增加统一的 controller adapter，将私有 `PointerDragState` 映射为 shared event：
  - `.pressed`：发送 `press(pressContext.targetHandleIdentity)`，若视觉发生变化立即 refresh。
  - handle 对应的 resize/crop/rotate/arrow/group drag state：发送 `beginDragging`；保持同一 active identity。
  - `.idle` 和所有非 handle drag state：发送 end/cancel 并在视觉变化时 refresh。
- 使用单一 `pointerDragState` 状态同步入口或 property observer，确保所有 factory 失败、stale target、mutation 失败后直接写 `.idle` 的早退路径也会清理 active 状态，避免逐个 guard 手工补漏。
- pointer up 的 defer、primary cancel、iOS long press、macOS secondary click、transition freeze 均沿用现有收尾路径，由回到 idle 统一清理。
- iOS 特有 markdown scroll 映射为非 handle state；两端现有 4pt activation threshold、history begin/commit、geometry update 和 refresh API 不改变。

## 阶段 5：共享视觉样式与双端 viewport 渲染
- 在 [Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift) 定义 CoreGraphics-only style resolver；shared snapshot 只携带 normal/active 语义，不携带 UIKit/AppKit 类型。
- 默认视觉：
  - selection、rotate、arrow、group frame：normal 为白色 fill + 蓝色 stroke；active 为蓝色 fill + 白色 stroke。
  - crop：normal 为白色 fill + 橙色 stroke；active 为橙色 fill + 白色 stroke。
  - handle 大小、形状、line width 保持平台现状。
- 更新 [iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift) 和 [macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift)：
  - selection/group frame 共用的 `selectionHandleLayers`
  - `cropHandleLayers`
  - `arrowEndpointHandleLayers`
  - `rotateHandleLayer`
- 每次 refresh 可见 handle 时都重新应用 style，防止复用 layer 残留上一次 active 颜色；隐藏逻辑和路径几何不变。
- 为纯 style resolver 增加测试，验证 normal/active 确实不同且 crop/selection accent 不串用。

## 阶段 6：边界与取消一致性加固
- 验证并补齐以下清理路径：未超过阈值的单击释放、拖动中移出 handle、pointer cancel、context menu 抢占、transition freeze、目标丢失、零尺寸或 state factory 失败、board restore、undo/redo、进入 reading/inline edit。
- 明确 cancel 仅清理 handle 视觉状态，不改变当前项目里“多数 drag cancel 会提交当前几何、rotate cancel 会撤销 preview”的既有业务语义。
- 确认 active 状态清理后的 refresh 发生在最终 commit/finalize 之后，避免最后一帧 snapshot 仍带 active。
- 确认状态变化不调用 history/autosave，不增加 undo step。

## 阶段 7：回归测试与验收
- 新增 [CanvasRendererEditHandleVisualStateTests.swift](MyCanvas_Ver_0Tests/CanvasRendererEditHandleVisualStateTests.swift)：覆盖 selection、all-markdown edge、multi-selection、crop、rotate/group rotate、arrow start/end、group frame resize，并断言只有精确 identity active。
- 新增或扩展 context resolver 测试，断言 hit geometry identity 与 `CanvasPointerPressContext.targetHandleIdentity` 一致。
- 扩展 [CanvasEditorSessionAlignmentOverlayTests.swift](MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift) 和 [CanvasEditorSessionGroupHierarchyTests.swift](MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift) 的 transient/reset/group frame 覆盖。
- 运行新测试，以及 selection transform、click selection、group hierarchy 相关回归；顺序执行 macOS 测试/build 和 iOS build，避免 DerivedData 锁冲突。
- 手动验收矩阵：每类 handle 分别执行 press 不拖动、拖动越过阈值、拖出原 hit rect、正常释放、取消/菜单/模式切换；确认只有当前 handle 变色并最终恢复。

## 阶段 8：清理与扩展边界
- 删除两端重复的 normal/active 颜色判断，只保留平台 layer 应用和尺寸差异。
- 检查 identity、状态机、style resolver 无 UIKit/AppKit 依赖，无文档格式升级，无存储迁移。
- 保留 `CanvasEditHandleVisualState` 的扩展空间，但本次不实现 hover/disabled 等额外状态。
- 最终确认现有 resize/crop/rotate/arrow/group 操作结果、history transaction 数量和 autosave reason 均未变化。