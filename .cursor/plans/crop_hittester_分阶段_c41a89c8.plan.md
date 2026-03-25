---
name: Crop HitTester 分阶段
overview: 把 Crop 模式的命中测试抽成共享 `CanvasEditOverlayHitTester`，将 pointer 命中与 context menu context 解耦，并在稳定架构上引入 `cropTranslationArea`，实现“按住裁剪框内部任意位置也能移动”。计划优先保证行为分阶段演进：前两阶段只重构不改行为，用户可见变化集中在新增内部平移区域的阶段。
todos:
  - id: geometry-foundation
    content: 整理 `CanvasQuad` 的共享几何能力，移除 minimap 文件对通用命中工具的承载。
    status: pending
  - id: extract-overlay-hittester
    content: 新增 `CanvasEditOverlayHitTester`，先完整迁移现有 overlay hit test，保持行为等价。
    status: pending
  - id: split-pointer-menu-context
    content: 引入 `CanvasHitTarget`，把 pointer 命中与 `CanvasContextMenuContext` 解耦。
    status: pending
  - id: add-crop-translation-area
    content: 在共享 hit target 中新增 `cropTranslationArea`，并定义 handle/outline/interior 的优先级。
    status: pending
  - id: wire-platform-state-machines
    content: 让 iOS/macOS 控制器改用新的 hit target，并把 `cropTranslationArea` 接入 `movingCropFrame`。
    status: pending
  - id: cleanup-and-regression
    content: 清理旧 resolver/helper，统一日志与命令语义，并完成双端回归验证。
    status: pending
isProject: false
---

# Crop HitTester 分阶段计划

## 目标

- 在共享层抽出 `CanvasEditOverlayHitTester`，把当前混在 [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 里的 overlay hit test 拆出来，形成单一数据源。
- 将 pointer 输入路径与 context menu 路径从同一个 `CanvasContextMenuContext` 中解耦，避免控制器继续把“菜单上下文”当“拖拽命中结果”使用。
- 在新架构上新增 `cropTranslationArea`，实现 `Crop` 模式下“按住裁剪框内部任意位置也能移动”，同时保持 handle、outline、history、autosave、菜单命令的一致性。

## 现状锚点

- 当前 [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 的顺序是：`handle -> cropOutline -> inlineEditBlank -> scene item`。这意味着裁剪框内部如果没有命中 handle 或 outline，会直接落到 `.blank`。
- 当前 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 和 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 只有 `.cropOutline` 才会进入 `movingCropFrame`；`beginPointerHistoryTransactionIfNeeded`、click logging、菜单候选命令也都依赖 `.cropOutline`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
if let resolvedTarget = resolveEditHandleTarget(...) { ... }
if let resolvedTarget = resolveCropOutlineTarget(...) { ... }
if isInlineEditModeActive {
    return finalize(branch: "inlineEditBlank", resolvedTarget: ResolvedTarget(targetKind: .blank))
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
case .cropOutline:
    guard let translationState = makePointerCropTranslationState(...) else { ... }
    pointerDragState = .movingCropFrame(translationState)
    updateTranslatedCropDraft(using: translationState, to: location)
```

## 阶段 1：几何基础收口

- 目标：把 overlay hit test 依赖的纯几何能力下沉到共享几何层，后续 `CanvasEditOverlayHitTester` 不再依赖 minimap 文件或 resolver 私有 helper。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift](MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift](MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift)
- 任务：
  - 把 `CanvasQuad.cgPath` 从 minimap 几何文件挪回共享几何层，避免通用四边形能力挂在 minimap 专用文件里。
  - 为 `CanvasQuad` 补齐 hit test 需要的纯函数能力，至少包含：`edges`、`contains(_ point: CGPoint)`，必要时补 `distance(from:toSegment:)` 这类静态/全局工具。
  - 明确裁剪内部命中必须使用真实四边形判定，不能退化成 `boundingRect.contains`，否则旋转图片会误命中。
- 阶段出口：没有用户可见行为变化；selection/crop overlay 的渲染代码无需改语义。

## 阶段 2：抽出共享 EditOverlay HitTester，先做到行为等价

- 目标：把当前 resolver 里的 overlay 命中逻辑抽成独立模块，但先保持外部行为完全等价。
- 主要文件：
  - 新增 `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift)
- 任务：
  - 新增 `CanvasEditOverlayHitTester`，输入固定为 `viewportPoint + editOverlay + interactionMetrics`，不直接依赖 `scene`、`camera`、选中态或 inline 标志。
  - 在新 hit tester 内先覆盖现有四类 overlay 命中：`rotateHandle`、`selectionHandle(role:)`、`cropHandle(role:)`、`cropOutline`。
  - 现阶段保留今天的优先级：`handle > cropOutline`；不要引入 `cropTranslationArea`。
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift) 改成编排层：先问 hit tester，再决定 `inlineEditBlank`、scene item、anchorRect、debug 日志。
- 阶段出口：iOS/macOS 上 crop handle、crop outline、rotate handle、selection handle 的命中行为与今天完全一致。

## 阶段 3：把 pointer target 与 context menu context 解耦

- 目标：让 resolver 先产出通用 `hit target`，再按需要派生 menu context；控制器不再把 `CanvasContextMenuContext` 当 pointer press context 使用。
- 主要文件：
  - 新增 `MyCanvas_Ver_0/Canvas/Core/CanvasHitTarget.swift`
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift)
  - [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift)
- 任务：
  - 抽出 `CanvasHitTargetKind` 和 `CanvasHitTarget`。建议字段至少包含：`invocationViewportPoint`、`invocationWorldPoint`、`kind`、`targetItemID`、`anchorRect`。
  - `CanvasContextResolver` 新增 `resolveHitTarget(...)`，让 `resolveContext(...)` 退化为“从 hit target 派生菜单上下文”的包装层，或者直接新增 `resolveContextMenuContext(...)`。
  - [MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift) 对外提供两条入口：pointer 用 `resolveHitTarget`，menu 用 `resolveContextMenuContext`。
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift) 改成菜单专用类型，内部持有或派生自 `CanvasHitTarget`，`anchorPoint`、`debugSummary`、`selectedItemID`、inline 状态都留在菜单语义层。
  - [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift) 和 [MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift) 只依赖菜单上下文，不再影响 pointer press context 的建模。
- 阶段出口：功能行为仍应保持不变，但 pointer 和 menu 的类型边界已经清晰。

## 阶段 4：在共享命中层引入 `cropTranslationArea`

- 目标：把“裁剪框内部可平移区域”定义成共享命中语义，而不是 iOS/macOS 控制器里的局部补丁。
- 主要文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasHitTarget.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift)
- 任务：
  - 在 `CanvasHitTargetKind` 中新增 `cropTranslationArea`。
  - 在 `CanvasEditOverlayHitTester` 中新增内部命中分支：使用 `payload.cropScreenQuad.contains(viewportPoint)` 判断真实四边形内部。
  - 保持优先级为：`cropHandle > cropOutline > cropTranslationArea > inlineEditBlank/scene`。这样边线附近仍保持今天的抓取手感，内部区域新增平移能力。
  - 菜单侧把 `cropTranslationArea` 与 `cropOutline` 视为同一类 crop body 命中，命令集合保持一致；`anchorPoint` 继续沿用 invocation point，避免菜单位置突变。
  - `debugName`、resolver branch、context summary 一起升级，保证日志可区分 `cropOutline` 与 `cropTranslationArea`。
- 阶段出口：共享层已经可以把“裁剪框内部命中”准确区分出来，但平台输入状态机尚未切换到新 kind。

## 阶段 5：双端输入状态机接入新 hit target

- 目标：iOS/macOS pointer 路径切到新的 `hit target`，把 `cropTranslationArea` 接进现有 `movingCropFrame` 流程。
- 主要文件：
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
  - [MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift](MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift)
- 任务：
  - pointer 按下路径改用 `resolveHitTarget`，长按/secondary click 菜单路径改用 `resolveContextMenuContext`。
  - `handlePrimaryPointerMove` 的 `.pressed` 分支里，为 `cropTranslationArea` 增加与 `cropOutline` 相同的进入逻辑：`makePointerCropTranslationState -> .movingCropFrame -> updateTranslatedCropDraft`。
  - `beginPointerHistoryTransactionIfNeeded` 把 `cropTranslationArea` 并入 `"crop item"` 事务。
  - `handlePrimaryPointerUp` 的点击日志里新增区分字段，例如 `crop_translation_area`，便于后续排查实际命中占比；如果不想新增埋点名，也至少要确保 `cropOutline` 与内部区域不会被混成 `blank`。
  - 保持 `PointerCropTranslationState`、`movingCropFrame`、`updateTranslatedCropDraft`、`commitCropDraftIfNeeded` 的逻辑不变，避免把几何平移逻辑改散。
- 阶段出口：两端都支持“按住裁剪框内部任意位置移动”，且边线拖动、handle resize、画布 pan、撤销/提交语义保持稳定。

## 阶段 6：清理旧耦合并完成回归

- 目标：删掉已被新架构替代的旧辅助逻辑，确保代码只保留一条命中链路。
- 主要文件：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift](MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift)
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
- 任务：
  - 清理 `CanvasContextResolver` 中被 hit tester 替代的私有 helper，如旧的 `ResolvedTarget`、旧版 `resolveCropOutlineTarget`、重复几何函数。
  - 统一 `debugName`、`debugSummary`、`branch=` 日志，避免继续出现“行为已是 translation area，但名字仍叫 outline”的语义债。
  - 复查 [MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift) 与控制器 click logging，确认新 kind 的命令集与埋点完全对齐。
- 阶段出口：代码路径单一，命中语义、菜单语义、日志语义一致。

## 验收与回归矩阵

- `iOS`：未旋转图片进入 `Crop`，按住裁剪框内部中心拖动，裁剪框应平移。
- `iOS`：按住边线拖动，仍应平移；按住 8 个 handle，仍应只调整裁剪尺寸。
- `iOS`：裁剪框外拖动，仍保持画布 pan，而不是误命中 crop。
- `macOS`：主键拖拽与 `iOS` 一致；secondary click 在裁剪框内部应得到与 outline 一致的 crop 菜单。
- `旋转场景`：对已旋转图片进入 `Crop`，点击 quad 的 bounding rect 但在真实四边形外部的位置，不应误命中；点击真实四边形内部则必须命中 `cropTranslationArea`。
- `提交链路`：`movingCropFrame` 的撤销、history transaction、autosave、cancel/release 提交行为与当前 `.cropOutline` 路径保持一致。
- `无回归`：selection/rotate 的 handle 命中顺序不变；非 crop inline edit 仍按现有规则落到 `.blank` 或 scene item。

## 实施注意点

- 当前工程里没有现成的 `*Tests*.swift`；这次计划默认不额外新建 test target，验证以 Xcode UI 的双端 build + 手动交互矩阵为主。
- 当前 shell 环境的 `xcodebuild` 不能直接使用完整 Xcode 构建链路，因此阶段验收默认按 Xcode 工程手工编译与运行来执行。
- 本计划不走“控制器本地补丁”路线，不在 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) / [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 各自复制一份 quad 内部命中判断；命中规则必须收敛在共享 hit tester。

