# 20260722_182352_group_frame_hit_testing_phase2_record

## 记录来源

- 时间戳来源：系统命令 `date +"%Y%m%d_%H%M%S"`，输出 `20260722_182352`。
- 记录对象：`group-frame-interaction` 阶段 2，给 group 框接入 hit-test。
- 参考范围：当前 `git diff` 与工作区 changes。当前 changes 中存在计划文件变更，但本记录只覆盖刚刚实施阶段 2 产生的代码改动。

## 修改概览

阶段 2 的核心变化是把 group 框纳入 shared hit-test 合同：

- pointer/context menu target 新增 `groupFrameBody` 与 `groupFrameResizeHandle`。
- pointer/context menu context 新增 `targetGroupID`，用于从 resolver 透传 group 命中目标。
- `CanvasContextResolver.resolveTarget(...)` 的命中顺序调整为：已有 edit overlay handle、group edit overlay handle、item body、group frame body、blank。
- iOS/macOS 在点击 group 框空白区域时选择 group；拖拽和缩放仍保持 no-op，留给后续阶段。
- `CanvasRenderSnapshot` 预留 `CanvasGroupEditOverlay`，当前 renderer 先返回 `nil`，等待阶段 3 生成和绘制 handles。

## 修改前后说明

### 1. Pointer target 合同

修改前，pointer target 只能表达 item、selection/crop/arrow handle 和 blank，不能表达 group 框本体或 group resize handle。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// 函数/类型：CanvasPointerTargetKind
// 功能注释：修改前没有 group frame 的 pointer 命中类型，resolver 即使命中 group 框也只能退化为 blank。
enum CanvasPointerTargetKind {
    case selectionTranslationArea
    case selectedItemBody
    case unselectedItemBody
    case blank
}
```

修改后，pointer target 可以区分 group 框本体和 group resize handle，并且 `CanvasPointerPressContext` 能携带 `targetGroupID`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// 函数/类型：CanvasPointerTargetKind, CanvasPointerPressContext
// 功能注释：新增 group frame 命中类型，并把命中的 group id 透传给 controller。
enum CanvasPointerTargetKind {
    case selectionTranslationArea
    case selectedItemBody
    case unselectedItemBody
    case groupFrameBody
    case groupFrameResizeHandle(role: CanvasSelectionHandleRole)
    case blank
}

struct CanvasPointerPressContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasPointerTargetKind
    let targetItemID: CanvasItemID?
    let targetGroupID: CanvasItemGroupID?
    let anchorRect: CGRect?
}
```

### 2. Context menu target 合同

修改前，context menu context 只能表达 item 或 canvas blank，无法知道当前菜单命中的是哪个 group。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数/类型：CanvasContextMenuTargetKind, CanvasContextMenuContext
// 功能注释：修改前 context menu 没有 group frame target，也没有 targetGroupID。
enum CanvasContextMenuTargetKind {
    case selectedItemBody
    case unselectedItemBody
    case blank
}

struct CanvasContextMenuContext {
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
}
```

修改后，context menu target 与 pointer target 对齐，保留 group frame 命中语义；阶段 2 暂不为 group frame 弹出 item 菜单。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数/类型：CanvasContextMenuTargetKind, CanvasContextMenuContext
// 功能注释：新增 group frame context 类型，并在 debugSummary 中输出 targetGroupID 方便后续定位。
enum CanvasContextMenuTargetKind {
    case selectedItemBody
    case unselectedItemBody
    case groupFrameBody
    case groupFrameResizeHandle(role: CanvasSelectionHandleRole)
    case blank
}

struct CanvasContextMenuContext {
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasItemID?
    let targetGroupID: CanvasItemGroupID?
    let anchorRect: CGRect?
}
```

### 3. Shared hit-test 顺序

修改前，`CanvasContextResolver.resolveTarget(...)` 在没有 item 命中时直接返回 blank，因此 group 框本体永远不会被选中。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数/类型：CanvasContextResolver.resolveTarget(...)
// 功能注释：修改前 item hit-test 失败后直接进入 blank 分支，没有 group frame body 分支。
guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
    return ResolutionResult(
        branch: "blank",
        resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
    )
}
```

修改后，resolver 先保持 item 优先，再检查 group frame body，保证层级语义仍是 `item > group frame > blank`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数/类型：CanvasContextResolver.resolveTarget(...)
// 功能注释：item 仍优先于 group；只有点击 group 框内空白区域才返回 groupFrameBody。
if let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) {
    return ResolutionResult(
        branch: "itemBody",
        resolvedTarget: ResolvedTarget(
            pointerTargetKind: selectedItemIDs.contains(itemID)
                ? .selectedItemBody
                : .unselectedItemBody,
            targetItemID: itemID,
            anchorRect: itemAnchorRect(for: itemID, renderSnapshot: renderSnapshot)
        ),
        sceneHitItemID: itemID
    )
}

if let groupFrameTarget = resolveGroupFrameBodyTarget(
    at: viewportPoint,
    renderSnapshot: renderSnapshot
) {
    return ResolutionResult(
        branch: "groupFrameBody",
        resolvedTarget: groupFrameTarget
    )
}
```

### 4. Group frame body 与 handle 命中

修改前没有针对 group frame 的 resolver helper。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数/类型：CanvasContextResolver
// 功能注释：修改前只复用 CanvasEditOverlayHitTester 处理 item selection/crop/arrow 的编辑命中。
private let editOverlayHitTester = CanvasEditOverlayHitTester()
```

修改后新增两个 helper：`resolveGroupEditOverlayTarget(...)` 处理后续阶段 3 生成的 resize handles；`resolveGroupFrameBodyTarget(...)` 处理当前已渲染的 group 背景框。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数/类型：CanvasContextResolver.resolveGroupEditOverlayTarget(...)
// 功能注释：为阶段 3 的 group resize handles 预留 hit-test 入口，命中后返回 targetGroupID。
private func resolveGroupEditOverlayTarget(
    at viewportPoint: CGPoint,
    renderSnapshot: CanvasRenderSnapshot,
    metrics: CanvasContextResolverMetrics
) -> ResolvedTarget? {
    guard let overlay = renderSnapshot.groupEditOverlay else {
        return nil
    }

    for handle in overlay.handles.reversed() {
        guard let role = handle.role.selectionHandleRole else {
            continue
        }

        let hitRect = centeredHitRect(
            at: handle.screenCenter,
            targetSize: metrics.selectionHandleHitTargetSize
        )
        guard hitRect.contains(viewportPoint) else {
            continue
        }

        return ResolvedTarget(
            pointerTargetKind: .groupFrameResizeHandle(role: role),
            targetGroupID: overlay.groupID,
            anchorRect: hitRect
        )
    }

    return nil
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数/类型：CanvasContextResolver.resolveGroupFrameBodyTarget(...)
// 功能注释：从当前 renderSnapshot.groups 中查找命中的 group 框，本体命中返回 groupFrameBody。
private func resolveGroupFrameBodyTarget(
    at viewportPoint: CGPoint,
    renderSnapshot: CanvasRenderSnapshot
) -> ResolvedTarget? {
    guard let group = renderSnapshot.groups.reversed().first(
        where: { $0.screenFrame.contains(viewportPoint) }
    ) else {
        return nil
    }

    return ResolvedTarget(
        pointerTargetKind: .groupFrameBody,
        targetGroupID: group.id,
        anchorRect: group.screenFrame
    )
}
```

### 5. Render snapshot 预留 group edit overlay

修改前，snapshot 已有 `groups` 用于渲染浅灰 group 框，但没有独立的选中态 overlay 数据入口。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数/类型：CanvasRenderSnapshot
// 功能注释：修改前 snapshot 没有 group edit overlay，无法承载 group resize handles。
struct CanvasRenderSnapshot {
    let groups: [CanvasGroupRenderItem]
    let items: [CanvasRenderItem]
    let selectionHighlights: [CanvasSelectionHighlight]
    let editOverlay: CanvasEditRenderOverlay?
}
```

修改后新增 `CanvasGroupEditOverlay`，并在 snapshot 中加入 `groupEditOverlay`。当前阶段 renderer 先填 `nil`，不改变视觉渲染。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数/类型：CanvasGroupEditOverlay, CanvasRenderSnapshot
// 功能注释：为后续阶段渲染选中 group 的蓝色边框和 8 个缩放 handles 提供共享数据结构。
struct CanvasGroupEditOverlay {
    let groupID: CanvasItemGroupID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasEditHandleGeometry]
}

struct CanvasRenderSnapshot {
    let groups: [CanvasGroupRenderItem]
    let items: [CanvasRenderItem]
    let selectionHighlights: [CanvasSelectionHighlight]
    let groupEditOverlay: CanvasGroupEditOverlay?
    let editOverlay: CanvasEditRenderOverlay?
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数/类型：CanvasRenderer.makeSnapshot(...)
// 功能注释：阶段 2 只接 hit-test 合同，groupEditOverlay 暂为空，避免提前引入视觉变化。
return CanvasRenderSnapshot(
    groups: renderGroups,
    items: renderItems,
    selectionHighlights: selectionHighlights,
    groupEditOverlay: nil,
    editOverlay: editOverlay,
    interactionOverlay: interactionOverlay
)
```

### 6. 点击 group 框空白区域选择 group

修改前，iOS/macOS 的 pointer up 统一交给 item click selection resolver；group 框命中会被视作 blank，无法选中 group。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.handlePrimaryPointerUp(...)
// 功能注释：修改前 pointer up 只解析 item click decision，没有 group frame special-case。
let clickDecision = clickSelectionResolver.resolve(
    pressTargetKind: pressContext.targetKind,
    pressedItemID: pressContext.targetItemID,
    releasedItemID: releasedItemID,
    selection: previousInteractionState,
    isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
    pressedModifiers: pressedModifiers,
    releasedModifiers: modifiers
)
let executionResult = executeClickSelectionDecision(clickDecision)
```

修改后，iOS 先判断 press/release 是否都是同一个 group frame body，是则调用 `editorSession.selectGroup(...)` 并刷新。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.executeGroupFrameClickSelectionIfMatched(...)
// 功能注释：只有按下和释放都命中同一个 group 框本体时才选择 group，避免误伤 item click。
private func executeGroupFrameClickSelectionIfMatched(
    pressContext: CanvasPointerPressContext,
    releasedContext: CanvasPointerPressContext
) -> (result: String, didTriggerPressedRefresh: Bool)? {
    guard
        case .groupFrameBody = pressContext.targetKind,
        case .groupFrameBody = releasedContext.targetKind,
        let groupID = pressContext.targetGroupID,
        releasedContext.targetGroupID == groupID
    else {
        return nil
    }

    let didSelectGroup = editorSession.selectGroup(
        withID: groupID,
        recordHistory: true
    )
    guard didSelectGroup else {
        return ("selection_unchanged", false)
    }

    requestCanvasRefresh(reason: "select group frame")
    return ("group_selected", true)
}
```

macOS 同步实现相同逻辑，只是刷新入口使用 `refreshCanvas(...)`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型：macOSViewController.executeGroupFrameClickSelectionIfMatched(...)
// 功能注释：macOS 与 iOS 保持同一点击选择语义，press/release 同 group 才选中 group。
private func executeGroupFrameClickSelectionIfMatched(
    pressContext: CanvasPointerPressContext,
    releasedContext: CanvasPointerPressContext
) -> (result: String, didTriggerPressedRefresh: Bool)? {
    guard
        case .groupFrameBody = pressContext.targetKind,
        case .groupFrameBody = releasedContext.targetKind,
        let groupID = pressContext.targetGroupID,
        releasedContext.targetGroupID == groupID
    else {
        return nil
    }

    let didSelectGroup = editorSession.selectGroup(
        withID: groupID,
        recordHistory: true
    )
    guard didSelectGroup else {
        return ("selection_unchanged", false)
    }

    refreshCanvas(reason: "select group frame")
    return ("group_selected", true)
}
```

### 7. 阶段 2 暂不启用拖拽和缩放

修改前，非 item 或 blank 的 pointer target 没有 group 分支。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.handlePrimaryPointerMove(...)
// 功能注释：修改前没有 groupFrameBody/groupFrameResizeHandle 分支。
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

修改后，group body 和 group resize handle 的拖拽起点在阶段 2 保持 no-op，不会误触发 canvas pan 或 item drag。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型：iOSViewController.handlePrimaryPointerMove(...)
// 功能注释：阶段 2 只完成 hit-test 与点击选择，拖拽/缩放留给后续阶段。
case .groupFrameBody, .groupFrameResizeHandle:
    pointerDragState = .idle
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型：macOSViewController.handlePrimaryPointerMove(...)
// 功能注释：macOS 同步保持阶段 2 的 no-op 行为，避免 group target 误触发 canvas pan。
case .groupFrameBody, .groupFrameResizeHandle:
    pointerDragState = .idle
case .unselectedItemBody, .blank:
    pointerDragState = .draggingCanvas
    panCanvas(from: pressedLocation, to: location)
```

### 8. Context menu 与 click resolver 的阶段 2 行为

修改前，click resolver 不认识 group target；context menu action resolver 也没有 group frame 分支。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数/类型：CanvasClickSelectionResolver.resolve(...)
// 功能注释：修改前只有 item body 和 blank 能触发点击选择决策。
case .selectedItemBody, .unselectedItemBody:
    return CanvasClickSelectionDecision(
        target: "item",
        affectedItemID: itemID,
        action: .selectSingle(itemID: itemID)
    )
case .blank:
    return CanvasClickSelectionDecision(
        target: "blank",
        affectedItemID: selection.primarySelectedItemID,
        action: selection.hasSelection ? .clearSelection : .none
    )
```

修改后，click resolver 对 group target 返回 no-op；真正的 group 选择由 iOS/macOS 的 `executeGroupFrameClickSelectionIfMatched(...)` 处理。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数/类型：CanvasClickSelectionResolver.resolve(...)
// 功能注释：group frame 点击不走 item selection resolver，避免混淆 item selection 与 group selection。
case .groupFrameBody:
    return CanvasClickSelectionDecision(
        target: "group_frame_body",
        affectedItemID: nil,
        action: .none
    )
case .groupFrameResizeHandle:
    return CanvasClickSelectionDecision(
        target: "group_frame_resize_handle",
        affectedItemID: nil,
        action: .none
    )
```

```swift
// MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数/类型：CanvasContextMenuActionResolver.candidateActionIDs(...)
// 功能注释：阶段 2 暂不给 group frame 弹出 item 操作菜单，避免把 group 命中误当 item 命中处理。
case .groupFrameBody, .groupFrameResizeHandle:
    return []
```

## 验证记录

本次修改后已完成以下验证：

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：读取系统时间戳，用于生成本记录文件名和标题。
date +"%Y%m%d_%H%M%S"
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build
```

```bash
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS Simulator 目标可编译通过。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build
```

验证结果：

- `ReadLints`：无 linter errors。
- macOS build：通过。
- iOS Simulator build：通过。

