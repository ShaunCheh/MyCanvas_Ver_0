# 20260414_213056_board_multiselect_phase5_record

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff --stat`、当前文件内容、定向 `xcodebuild` 结果与本轮 phase5 实际改动；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”的方式归纳上下文菜单边界、目标对象语义、单对象动作约束、工具条模式边界与回归测试的真实落地情况。

下面的代码块都是围绕关键函数整理的真实摘录，保留必要上下文和功能注释，省略了与本轮无关的代码行。

## 当前 Changes 快照

```bash
# 路径: 工作区根目录
# 命令: date +"%Y%m%d_%H%M%S"
# 说明: 本记录文件名使用的时间戳
20260414_213056
```

```bash
# 路径: 工作区根目录
# 命令: git status --short
# 说明: 创建本记录前工作区中的全部 changes；其中 .cursor/plans 文件是当前工作区里同时存在的旧变更，本记录下面的代码说明聚焦 phase5 本轮实际代码修改
 M .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
 M MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
```

```bash
# 路径: 工作区根目录
# 命令: git diff --stat
# 说明: tracked 文件的 diff 体量概览；这条命令会把当前工作区里一并存在的 .cursor/plans 旧变更也统计进去
.../plans/board-multiselect-plan_96ecdbb5.plan.md  |   2 +-
.../Canvas/Core/CanvasContextMenuContext.swift     | 126 ++++++++++++-
.../Canvas/Core/CanvasContextResolver.swift        |   9 +-
MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift  |   4 +
.../Canvas/Editing/CanvasCommandCatalog.swift      |  37 ++--
.../Canvas/Editing/CanvasCommandExecutor.swift     |  10 ++
.../Canvas/Editing/CanvasEditorSession.swift       |  30 +++-
.../CanvasContextMenuCommandResolver.swift         |  73 +++++---
.../Shared/Toolbar/CanvasToolbarStateBuilder.swift |  17 +-
.../Platform/iOS/iOSViewController.swift           |  12 +-
.../Platform/macOS/macOSViewController.swift       |  12 +-
.../CanvasCommandPolicyParityTests.swift           |  28 +++
.../CanvasContextMenuActionResolverTests.swift     | 194 ++++++++++++++++++++-
.../CanvasToolbarStateBuilderTests.swift           | 107 +++++++++++-
14 files changed, 588 insertions(+), 73 deletions(-)
```

## 变更一：上下文菜单上下文从“单个 selectedItemID”升级为“当前选择集 + 实际作用目标”

本轮 phase5 的根因之一，是旧的 `CanvasContextMenuContext` 只有一个 `selectedItemID`，无法同时表达：

- 用户当前真实选中了哪些成员
- 这次右键菜单最终应该作用于当前选择集，还是作用于未选中的目标对象

这会导致显示逻辑、启用逻辑、命令解析逻辑各自再猜一遍语义，边界很容易分叉。

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数: CanvasContextMenuContext / debugSummary
// 说明: 旧模型只有 targetItemID 和 selectedItemID，无法显式区分“当前选择集”和“菜单实际作用对象”
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    var debugSummary: String {
        [
            "target=\(targetKind.debugName)",
            "targetItemID=\(targetItemID?.uuidString ?? "nil")",
            "selectedItemID=\(selectedItemID?.uuidString ?? "nil")",
            "inlineEdit=\(isInlineEditModeActive)",
            "inlineCrop=\(isInlineCropModeActive)"
        ].joined(separator: " ")
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数: makeContext(viewportPoint:worldPoint:resolvedTarget:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:)
// 说明: resolver 旧版只把 primary selectedItemID 往下透传，菜单层拿不到完整 selection 集合
private func makeContext(
    viewportPoint: CGPoint,
    worldPoint: CGPoint,
    resolvedTarget: ResolvedTarget,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: viewportPoint,
        invocationWorldPoint: worldPoint,
        targetKind: contextMenuTargetKind(for: resolvedTarget.pointerTargetKind),
        editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
        targetItemID: resolvedTarget.targetItemID,
        anchorRect: resolvedTarget.anchorRect,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数: CanvasContextMenuContext.init / singleEffectiveItemID / debugSummary
// 说明: 新模型同时保存 current selection、effective selection、以及这次菜单是否默认作用于当前选择集
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let currentSelectedItemIDs: [CanvasItemID]
    let currentPrimarySelectedItemID: CanvasItemID?
    let effectiveSelectedItemIDs: [CanvasItemID]
    let effectivePrimarySelectedItemID: CanvasItemID?
    let operatesOnCurrentSelection: Bool
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    init(
        invocationViewportPoint: CGPoint,
        invocationWorldPoint: CGPoint,
        targetKind: CanvasContextMenuTargetKind,
        editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?,
        targetItemID: CanvasItemID?,
        anchorRect: CGRect?,
        currentSelectedItemIDs: [CanvasItemID] = [],
        currentPrimarySelectedItemID: CanvasItemID? = nil,
        effectiveSelectedItemIDs: [CanvasItemID]? = nil,
        effectivePrimarySelectedItemID: CanvasItemID? = nil,
        operatesOnCurrentSelection: Bool? = nil,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool
    ) {
        let normalizedCurrentSelection = normalizeCanvasSelectionState(
            selectedItemIDs: currentSelectedItemIDs,
            primarySelectedItemID: currentPrimarySelectedItemID
        )
        self.currentSelectedItemIDs = normalizedCurrentSelection.selectedItemIDs
        self.currentPrimarySelectedItemID = normalizedCurrentSelection.primarySelectedItemID

        let resolvedOperatesOnCurrentSelection =
            operatesOnCurrentSelection
            ?? CanvasContextMenuContext.defaultOperatesOnCurrentSelection(for: targetKind)
        self.operatesOnCurrentSelection = resolvedOperatesOnCurrentSelection

        let normalizedEffectiveSelection: CanvasNormalizedSelectionState<CanvasItemID>
        if let effectiveSelectedItemIDs {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: effectiveSelectedItemIDs,
                primarySelectedItemID: effectivePrimarySelectedItemID
            )
        } else if resolvedOperatesOnCurrentSelection {
            let fallbackSelectedItemIDs =
                normalizedCurrentSelection.selectedItemIDs.isEmpty
                ? targetItemID.map { [$0] } ?? []
                : normalizedCurrentSelection.selectedItemIDs
            let fallbackPrimarySelectedItemID =
                normalizedCurrentSelection.primarySelectedItemID ?? targetItemID
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: fallbackSelectedItemIDs,
                primarySelectedItemID: fallbackPrimarySelectedItemID
            )
        } else if let targetItemID {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: [targetItemID],
                primarySelectedItemID: targetItemID
            )
        } else {
            normalizedEffectiveSelection = normalizeCanvasSelectionState(
                selectedItemIDs: [],
                primarySelectedItemID: nil
            )
        }

        self.effectiveSelectedItemIDs = normalizedEffectiveSelection.selectedItemIDs
        self.effectivePrimarySelectedItemID = normalizedEffectiveSelection.primarySelectedItemID
        self.isInlineEditModeActive = isInlineEditModeActive
        self.isInlineCropModeActive = isInlineCropModeActive
    }

    var singleEffectiveItemID: CanvasItemID? {
        effectiveSelectedItemIDs.count == 1 ? effectivePrimarySelectedItemID : nil
    }

    var debugSummary: String {
        [
            "target=\(targetKind.debugName)",
            "targetsCurrentSelection=\(operatesOnCurrentSelection)",
            "targetItemID=\(targetItemID?.uuidString ?? "nil")",
            "currentSelectedItemIDs=\(contextMenuDescribe(currentSelectedItemIDs))",
            "currentPrimarySelectedItemID=\(currentPrimarySelectedItemID?.uuidString ?? "nil")",
            "effectiveSelectedItemIDs=\(contextMenuDescribe(effectiveSelectedItemIDs))",
            "effectivePrimarySelectedItemID=\(effectivePrimarySelectedItemID?.uuidString ?? "nil")"
        ].joined(separator: " ")
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数: resolveContext(at:scene:camera:renderSnapshot:selectedItemIDs:primarySelectedItemID:isInlineEditModeActive:isInlineCropModeActive:isReadingModeActive:interactionMetrics:) / makeContext(...)
// 说明: resolver 现在把完整 selection 集合和 primary 一起交给 context，菜单层不再自己猜当前选择
let context = makeContext(
    viewportPoint: viewportPoint,
    worldPoint: invocationWorldPoint,
    resolvedTarget: resolution.resolvedTarget,
    selectedItemIDs: selectedItemIDs,
    primarySelectedItemID: primarySelectedItemID,
    isInlineEditModeActive: isInlineEditModeActive,
    isInlineCropModeActive: isInlineCropModeActive
)

private func makeContext(
    viewportPoint: CGPoint,
    worldPoint: CGPoint,
    resolvedTarget: ResolvedTarget,
    selectedItemIDs: [CanvasItemID],
    primarySelectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: viewportPoint,
        invocationWorldPoint: worldPoint,
        targetKind: contextMenuTargetKind(for: resolvedTarget.pointerTargetKind),
        editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
        targetItemID: resolvedTarget.targetItemID,
        anchorRect: resolvedTarget.anchorRect,
        currentSelectedItemIDs: selectedItemIDs,
        currentPrimarySelectedItemID: primarySelectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive
    )
}
```

## 变更二：裁剪命令从“只能裁当前 selection”升级为“可直接裁未选中右键目标”

phase5 的另一个根因，是旧命令层只有一个 `.crop`，而 `.crop` 又强依赖当前必须已经是单选状态。结果就是：

- 右键未选中对象时，即使菜单想显示 `Crop`，真正执行时也没有“先把目标收口成单选再进入 crop”的命令语义
- 这会让菜单显示、命令启用和执行结果出现潜在不一致

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数: CanvasCommand
// 说明: 旧命令枚举只有通用 .crop，没有“按目标 item 进入裁剪”的命令形态
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case undo
    case redo
    // ... 其余命令省略
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: canBeginCropMode / beginCropModeIfPossible()
// 说明: 旧 session 只能依赖当前 singleSelectedItemID 进入裁剪，无法对未选中目标单独打开 crop
var canBeginCropMode: Bool {
    guard inlineEditState == nil else {
        return false
    }

    guard let selectedItemID = singleSelectedItemID else {
        return false
    }

    return scene.item(withID: selectedItemID) != nil
}

@discardableResult
func beginCropModeIfPossible() -> Bool {
    guard
        canBeginCropMode,
        let selectedItemID = singleSelectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return false
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    return true
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数: CanvasCommand / id / shouldCancelActiveRotation
// 说明: 新增 .beginCropMode(itemID:)；它仍然归类到 crop 命令 ID，但执行语义变成“先收口目标，再进入裁剪”
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case crop
    case beginCropMode(itemID: CanvasItemID)
    case undo
    case redo
    // ... 其余命令省略

    var id: CanvasCommandID {
        switch self {
        case .crop, .beginCropMode:
            return .crop
        // ... 其余映射省略
        default:
            fatalError("省略的分支在文件里完整存在")
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: canBeginCropMode / canBeginCropMode(withID:) / beginCropModeIfPossible() / beginCropModeIfPossible(withID:)
// 说明: session 新增按目标 item 进入裁剪的共享 API；进入裁剪前会把 selection 收口到目标对象，避免 UI 与执行器语义分叉
var canBeginCropMode: Bool {
    guard inlineEditState == nil else {
        return false
    }

    guard let selectedItemID = singleSelectedItemID else {
        return false
    }

    return canBeginCropMode(withID: selectedItemID)
}

func canBeginCropMode(withID itemID: CanvasItemID) -> Bool {
    guard inlineEditState == nil else {
        return false
    }

    return scene.item(withID: itemID) != nil
}

@discardableResult
func beginCropModeIfPossible() -> Bool {
    guard let selectedItemID = singleSelectedItemID else {
        return false
    }

    return beginCropModeIfPossible(withID: selectedItemID)
}

@discardableResult
func beginCropModeIfPossible(withID itemID: CanvasItemID) -> Bool {
    guard
        canBeginCropMode(withID: itemID),
        let item = scene.item(withID: itemID)
    else {
        return false
    }

    _ = replaceSelection(
        with: [itemID],
        primarySelectedItemID: itemID
    )
    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数: canExecute(_:) / execute(_:)
// 说明: 执行器补齐 .beginCropMode 的权限判定与执行分支，让右键未选中对象也能走完整 command lane
func canExecute(_ command: CanvasCommand) -> Bool {
    switch command {
    case .crop:
        return session.isInlineCropModeActive || session.canBeginCropMode
    case let .beginCropMode(itemID):
        return session.canBeginCropMode(withID: itemID)
    default:
        // ... 其余分支省略
        return true
    }
}

func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
    switch command {
    case .crop:
        if session.isInlineCropModeActive {
            guard session.endInlineEditMode() else { return nil }
            return CanvasCommandExecutionResult(refreshReason: "exit crop mode")
        }

        guard session.beginCropModeIfPossible() else { return nil }
        return CanvasCommandExecutionResult(refreshReason: "enter crop mode")
    case let .beginCropMode(itemID):
        guard session.beginCropModeIfPossible(withID: itemID) else {
            return nil
        }
        return CanvasCommandExecutionResult(
            refreshReason: "enter crop mode \(itemID.uuidString)"
        )
    default:
        // ... 其余分支省略
        return nil
    }
}
```

## 变更三：菜单候选动作与启用态统一收口到 effective subject

这里是 phase5 最核心的“菜单边界与收口”部分。目标是让三层语义完全一致：

- 菜单显示哪些动作
- 动作是否启用
- 点下去最终执行什么命令

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数: descriptor(for:session:context:) / operatesOnCurrentSelection(in:)
// 说明: 旧 descriptor 一边用 targetItemID，一边再用 usesCurrentSelection/singleSelectedItemID 自行猜语义；crop 启用态也只能看当前 selection
case .beginTextEdit:
    let resolvedTargetItemID = targetItemID(
        in: context,
        session: session
    )
    let usesCurrentSelection = operatesOnCurrentSelection(in: context)
    descriptor = CanvasCommandDescriptor(
        id: .beginTextEdit,
        title: "Edit Text",
        systemImageName: "pencil",
        isEnabled: resolvedTargetItemID.map { itemID in
            if usesCurrentSelection, session.singleSelectedItemID != itemID {
                return false
            }

            return session.canBeginTextEdit(withID: itemID)
        } ?? false,
        isActive: false
    )

case .crop:
    let isActive = session.isInlineCropModeActive
    descriptor = CanvasCommandDescriptor(
        id: .crop,
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        isEnabled: isActive || session.canBeginCropMode,
        isActive: isActive
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数: command(for:context:session:) / candidateActionIDs(for:session:)
// 说明: 旧 resolver 的 beginTextEdit/crop 直接绑 targetItemID 或当前 selection；未选中目标的 crop 没有独立命令，内联编辑/裁剪态也没有统一收口
case .beginTextEdit:
    guard let itemID = context.targetItemID else {
        return nil
    }
    return .beginTextEdit(itemID: itemID)

case .crop:
    return .crop

private func candidateActionIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasContextMenuActionID] {
    let targetTextItem = context.targetItemID.flatMap { itemID in
        session.scene.textItem(withID: itemID)
    }

    switch context.targetKind {
    case .selectedItemBody, .selectionHandle, .rotateHandle:
        return selectedItemActionIDs(
            includeCropCommand: targetTextItem == nil,
            includeBeginTextEditCommand: targetTextItem != nil,
            includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
            includeGIFFrameImportAction: includeGIFFrameImportAction
        )
    case .unselectedItemBody:
        return unselectedItemActionIDs(
            includeBeginTextEditCommand: targetTextItem != nil,
            includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
            includeGIFFrameImportAction: includeGIFFrameImportAction
        )
    case .cropHandle, .cropOutline:
        return selectedItemActionIDs(
            includeCropCommand: true,
            includeBeginTextEditCommand: false,
            includeVideoDisplayFrameAction: false,
            includeGIFFrameImportAction: false
        )
    default:
        // ... 其余分支省略
        return []
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数: descriptor(for:session:context:) / singleEffectiveItemID(in:session:) / operatesOnCurrentSelection(in:)
// 说明: descriptor 统一以 effective subject 为准；单对象专属动作必须先满足“effective selection count == 1”
case .beginTextEdit:
    let resolvedTargetItemID = singleEffectiveItemID(
        in: context,
        session: session
    )
    descriptor = CanvasCommandDescriptor(
        id: .beginTextEdit,
        title: "Edit Text",
        systemImageName: "pencil",
        isEnabled: resolvedTargetItemID.map { itemID in
            session.canBeginTextEdit(withID: itemID)
        } ?? false,
        isActive: false
    )

case .crop:
    let isActive = session.isInlineCropModeActive
    let resolvedTargetItemID = singleEffectiveItemID(
        in: context,
        session: session
    )
    descriptor = CanvasCommandDescriptor(
        id: .crop,
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        isEnabled: isActive || resolvedTargetItemID.map { itemID in
            session.canBeginCropMode(withID: itemID)
        } ?? false,
        isActive: isActive
    )

private func singleEffectiveItemID(
    in context: CanvasContextMenuContext?,
    session: CanvasEditorSession
) -> CanvasItemID? {
    context?.singleEffectiveItemID ?? session.singleSelectedItemID
}

private func operatesOnCurrentSelection(
    in context: CanvasContextMenuContext?
) -> Bool {
    context?.operatesOnCurrentSelection ?? true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数: command(for:context:session:) / candidateActionIDs(for:session:) / unselectedItemActionIDs(...)
// 说明: resolver 现在明确区分 target-only 与 selection-wide；未选中目标的 crop 会下降为 beginCropMode(itemID:)，内联文本/裁剪模式会在候选动作阶段直接收口
case .beginTextEdit:
    guard let itemID = context.singleEffectiveItemID else {
        return nil
    }
    return .beginTextEdit(itemID: itemID)

case .crop:
    if context.isInlineCropModeActive {
        return .crop
    }

    guard let itemID = context.singleEffectiveItemID else {
        return nil
    }

    if context.operatesOnCurrentSelection {
        return .crop
    }

    return .beginCropMode(itemID: itemID)

private func candidateActionIDs(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> [CanvasContextMenuActionID] {
    if context.isInlineCropModeActive {
        switch context.targetKind {
        case .cropHandle, .cropOutline:
            return [.command(.crop)]
        default:
            return []
        }
    }

    if context.isInlineEditModeActive {
        return []
    }

    let targetTextItem = context.singleEffectiveItemID.flatMap { itemID in
        session.scene.textItem(withID: itemID)
    }
    let includeCropCommand = context.singleEffectiveItemID.map { itemID in
        session.scene.textItem(withID: itemID) == nil
            && session.scene.item(withID: itemID) != nil
    } ?? false

    switch context.targetKind {
    case .selectedItemBody, .selectionHandle, .rotateHandle:
        return selectedItemActionIDs(
            includeCropCommand: includeCropCommand,
            includeBeginTextEditCommand: targetTextItem != nil,
            includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
            includeGIFFrameImportAction: includeGIFFrameImportAction
        )
    case .unselectedItemBody:
        return unselectedItemActionIDs(
            includeCropCommand: includeCropCommand,
            includeBeginTextEditCommand: targetTextItem != nil,
            includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
            includeGIFFrameImportAction: includeGIFFrameImportAction
        )
    case .cropHandle, .cropOutline:
        return [.command(.crop)]
    default:
        // ... 其余分支省略
        return []
    }
}

private func unselectedItemActionIDs(
    includeCropCommand: Bool,
    includeBeginTextEditCommand: Bool,
    includeVideoDisplayFrameAction: Bool,
    includeGIFFrameImportAction: Bool
) -> [CanvasContextMenuActionID] {
    var actionIDs: [CanvasContextMenuActionID] = [.command(.selectItem)]
    if includeCropCommand {
        actionIDs.append(.command(.crop))
    }
    if includeBeginTextEditCommand {
        actionIDs.append(.command(.beginTextEdit))
    }
    // ... 其余动作拼接省略
    return actionIDs
}
```

## 变更四：工具条与双端 controller 的模式边界收口

phase5 计划里明确要求：阅读模式、内联编辑、裁剪模式下，多选命中与工具条启用态必须被明确限制，避免出现“UI 显示可点，但执行器拒绝”或者“点一下先偷偷 commit 文本再切换多选”的冲突路径。

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(...) / multiSelectItemState(isActive:)
// 说明: 旧工具条 builder 只有 active/inactive，没有 enabled gating；内联编辑和裁剪中 multiSelect 仍然表现得可用
itemStates.append(
    multiSelectItemState(isActive: isMultiSelectModeActive)
)

func multiSelectItemState(isActive: Bool) -> CanvasToolbarItemState {
    CanvasToolbarItemState(
        id: .multiSelect,
        systemImageName: "checklist",
        isActive: isActive,
        accessibilityLabel: "Multi-select",
        accessibilityValue: isActive ? "On" : "Off",
        visualRole: isActive ? .accent : .neutral
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handleMultiSelectButtonTap()
// 说明: 旧 iOS 行为会先尝试 commitActiveTextEditIfNeeded，再直接切换多选状态，边界不够明确
@objc
private func handleMultiSelectButtonTap() {
    commitActiveTextEditIfNeeded()
    isMultiSelectModeActive.toggle()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handleMultiSelectButtonClick()
// 说明: macOS 旧逻辑与 iOS 对称，同样没有阅读模式 / 内联编辑的显式 guard
@objc
private func handleMultiSelectButtonClick() {
    commitActiveTextEditIfNeeded()
    isMultiSelectModeActive.toggle()
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(...) / multiSelectItemState(isActive:isEnabled:) / canToggleMultiSelectMode(session:)
// 说明: builder 现在直接把多选按钮的 enabled 状态收口到共享层；阅读模式直接隐藏整条工具条，内联编辑期间 multiSelect 明确禁用
itemStates.append(
    multiSelectItemState(
        isActive: isMultiSelectModeActive,
        isEnabled: canToggleMultiSelectMode(session: session)
    )
)

func multiSelectItemState(
    isActive: Bool,
    isEnabled: Bool = true
) -> CanvasToolbarItemState {
    CanvasToolbarItemState(
        id: .multiSelect,
        systemImageName: "checklist",
        isEnabled: isEnabled,
        isActive: isActive,
        accessibilityLabel: "Multi-select",
        accessibilityValue: isActive ? "On" : "Off",
        visualRole: isActive ? .accent : .neutral
    )
}

private func canToggleMultiSelectMode(
    session: CanvasEditorSession
) -> Bool {
    session.isInlineEditModeActive == false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: targetVideoItemID(for:) / targetGIFItemID(for:) / handleMultiSelectButtonTap()
// 说明: iOS controller 现在一方面按 effective subject 打开单对象 UI action，另一方面在按钮点击前阻断阅读模式和内联编辑态
private func targetVideoItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.singleEffectiveItemID,
        let item = scene.item(withID: itemID),
        item.isVideo
    else {
        return nil
    }

    return itemID
}

private func targetGIFItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.singleEffectiveItemID,
        let item = scene.item(withID: itemID),
        item.isVideo == false,
        item.assetKind == .animatedGIF
    else {
        return nil
    }

    return itemID
}

@objc
private func handleMultiSelectButtonTap() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: targetVideoItemID(for:) / targetGIFItemID(for:) / handleMultiSelectButtonClick()
// 说明: macOS controller 做了与 iOS 对称的收口，保证两端菜单和工具条边界一致
private func targetVideoItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.singleEffectiveItemID,
        let item = scene.item(withID: itemID),
        item.isVideo
    else {
        return nil
    }

    return itemID
}

private func targetGIFItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.singleEffectiveItemID,
        let item = scene.item(withID: itemID),
        item.isVideo == false,
        item.assetKind == .animatedGIF
    else {
        return nil
    }

    return itemID
}

@objc
private func handleMultiSelectButtonClick() {
    guard
        editorSession.isInlineEditModeActive == false,
        editorSession.isReadingModeActive == false
    else {
        return
    }

    isMultiSelectModeActive.toggle()
}
```

## 变更五：phase5 回归测试补齐，并修复工具条测试的生命周期缺口

这次测试补的不只是“看起来能跑”，而是围绕 phase5 的边界逐条加回归：

- 右键未选中图片时，菜单能显示 `Crop`，且命令会落到 `.beginCropMode(itemID:)`
- 多选命中文本/视频时，`Edit Text` / `Crop` / `Set Display Frame` 这类单对象动作会被正确隐藏
- 内联文本编辑态时，菜单直接为空
- 裁剪态时，菜单只保留 `Crop/Done`
- 工具条多选按钮在内联文本 / 裁剪时禁用，阅读模式整条工具条隐藏
- command lane 有新的 parity test，保证按目标进入 crop 会同步替换 selection 并进入裁剪

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: makeContextMenuContext(...) / 既有测试集合
// 说明: 旧测试 helper 只能构造单个 selectedItemID；覆盖面主要还是 duplicate 分流和已有单对象动作
private func makeContextMenuContext(
    targetKind: CanvasContextMenuTargetKind,
    targetItemID: CanvasItemID,
    selectedItemID: CanvasItemID?
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: CGPoint(x: 12, y: 18),
        invocationWorldPoint: CGPoint(x: 12, y: 18),
        targetKind: targetKind,
        editOverlayHitTargetKind: nil,
        targetItemID: targetItemID,
        anchorRect: nil,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: false,
        isInlineCropModeActive: false
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数: testMainToolbarStateIncludesMultiSelectItem / testMainToolbarStateReflectsActiveMultiSelectMode / makeToolbarStateBuilderTestSession()
// 说明: 旧工具条测试只校验了 multiSelect 的图标和 active 状态，还没覆盖模式边界；helper 也没有持有 session 生命周期
@MainActor
final class CanvasToolbarStateBuilderTests: XCTestCase {
    func testMainToolbarStateIncludesMultiSelectItem() throws {
        // ... 只检查初始态
    }

    func testMainToolbarStateReflectsActiveMultiSelectMode() throws {
        // ... 只检查 active 视觉状态
    }
}

private func makeToolbarStateBuilderTestSession() -> CanvasEditorSession {
    CanvasEditorSession(
        saveQueueLabel: "CanvasToolbarStateBuilderTests",
        logPrefix: "[CanvasToolbarStateBuilderTests]"
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: testUnselectedImageIncludesCropCommandAndResolvesToTargetCropCommand / testSelectedVideoInMultiSelectionHidesSingleItemVideoAction / testInlineTextEditSuppressesContextMenuActions / testInlineCropContextOnlyExposesCropDoneCommand / makeContextMenuContext(...)
// 说明: 新增 phase5 关键边界测试，并让 helper 能显式构造多选 context 与模式态
func testUnselectedImageIncludesCropCommandAndResolvesToTargetCropCommand() throws {
    let context = makeContextMenuContext(
        targetKind: .unselectedItemBody,
        targetItemID: targetImage.id,
        selectedItemID: selectedItem.id
    )
    let actionStates = resolver.actionStates(for: context, session: session)
    let command = resolver.command(for: .crop, context: context, session: session)

    XCTAssertTrue(actionStates.contains { actionState in
        if case .command(.crop) = actionState.actionID { return true }
        return false
    })
    guard case let .beginCropMode(itemID)? = command else {
        XCTFail("Expected unselected target crop to resolve to beginCropMode.")
        return
    }
    XCTAssertEqual(itemID, targetImage.id)
}

func testSelectedVideoInMultiSelectionHidesSingleItemVideoAction() throws {
    session.interactionState = CanvasInteractionState(
        selectedItemIDs: [videoItem.id, otherItem.id],
        primarySelectedItemID: videoItem.id
    )

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: videoItem.id,
            selectedItemID: videoItem.id,
            selectedItemIDs: [videoItem.id, otherItem.id],
            primarySelectedItemID: videoItem.id
        ),
        session: session
    )

    XCTAssertFalse(actionStates.contains(where: isVideoDisplayFrameAction))
    XCTAssertFalse(actionStates.contains { actionState in
        if case .command(.crop) = actionState.actionID { return true }
        return false
    })
}

func testInlineTextEditSuppressesContextMenuActions() {
    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: textItem.id,
            selectedItemID: textItem.id,
            isInlineEditModeActive: true
        ),
        session: session
    )

    XCTAssertTrue(actionStates.isEmpty)
}

func testInlineCropContextOnlyExposesCropDoneCommand() throws {
    XCTAssertTrue(session.beginCropModeIfPossible())

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .cropOutline,
            targetItemID: imageItem.id,
            selectedItemID: imageItem.id,
            isInlineEditModeActive: true,
            isInlineCropModeActive: true
        ),
        session: session
    )

    XCTAssertEqual(actionStates.count, 1)
    guard case .command(.crop) = try XCTUnwrap(actionStates.first).actionID else {
        XCTFail("Expected crop outline context to only expose crop.")
        return
    }
}

private func makeContextMenuContext(
    targetKind: CanvasContextMenuTargetKind,
    targetItemID: CanvasItemID,
    selectedItemID: CanvasItemID? = nil,
    selectedItemIDs: [CanvasItemID]? = nil,
    primarySelectedItemID: CanvasItemID? = nil,
    isInlineEditModeActive: Bool = false,
    isInlineCropModeActive: Bool = false
) -> CanvasContextMenuContext {
    let resolvedSelectedItemIDs = selectedItemIDs ?? selectedItemID.map { [$0] } ?? []
    let resolvedPrimarySelectedItemID = primarySelectedItemID ?? selectedItemID
    return CanvasContextMenuContext(
        invocationViewportPoint: CGPoint(x: 12, y: 18),
        invocationWorldPoint: CGPoint(x: 12, y: 18),
        targetKind: targetKind,
        editOverlayHitTargetKind: nil,
        targetItemID: targetItemID,
        anchorRect: nil,
        currentSelectedItemIDs: resolvedSelectedItemIDs,
        currentPrimarySelectedItemID: resolvedPrimarySelectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数: testMainToolbarStateDisablesMultiSelectDuringInlineTextEdit / testMainToolbarStateDisablesMultiSelectDuringCropMode / testMainToolbarStateHidesItemsInReadingMode / makeToolbarStateBuilderTestSession()
// 说明: 工具条测试补了 phase5 的模式边界；另外加了 retainer 持有 session，避免 test-without-building 下 helper 生命周期过早结束导致 suite crash
func testMainToolbarStateDisablesMultiSelectDuringInlineTextEdit() throws {
    XCTAssertNotNil(session.addTextItem())

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        isMultiSelectModeActive: true
    )

    let multiSelectItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .multiSelect })
    )
    XCTAssertFalse(multiSelectItem.isEnabled)
    XCTAssertTrue(multiSelectItem.isActive)
}

func testMainToolbarStateDisablesMultiSelectDuringCropMode() throws {
    session.scene.append(imageItem)
    session.interactionState = CanvasInteractionState(selectedItemID: imageItem.id)
    XCTAssertTrue(session.beginCropModeIfPossible())

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        isMultiSelectModeActive: true
    )

    let multiSelectItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .multiSelect })
    )
    XCTAssertFalse(multiSelectItem.isEnabled)
}

func testMainToolbarStateHidesItemsInReadingMode() {
    session.workspaceMode = .reading
    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        isMultiSelectModeActive: true,
        includesHistoryItems: true
    )

    XCTAssertTrue(state.items.isEmpty)
}

private enum CanvasToolbarStateBuilderTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeToolbarStateBuilderTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasToolbarStateBuilderTests",
        logPrefix: "[CanvasToolbarStateBuilderTests]"
    )
    CanvasToolbarStateBuilderTestRetainer.sessions.append(session)
    return session
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数: testBeginCropModeCommandTargetsUnselectedItemAndReplacesSelection()
// 说明: 新 parity test 直接验证 command lane 会把未选中目标收口成单选并进入裁剪
func testBeginCropModeCommandTargetsUnselectedItemAndReplacesSelection() throws {
    session.scene.append(selectedItem)
    session.scene.append(targetItem)
    session.interactionState = CanvasInteractionState(selectedItemID: selectedItem.id)

    XCTAssertTrue(executor.canExecute(.beginCropMode(itemID: targetItem.id)))
    XCTAssertNotNil(executor.execute(.beginCropMode(itemID: targetItem.id)))
    XCTAssertEqual(session.selectedItemIDs, [targetItem.id])
    XCTAssertEqual(session.primarySelectedItemID, targetItem.id)
    XCTAssertTrue(session.isInlineCropModeActive)
}
```

## 验证结果

```bash
# 路径: 工作区根目录
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests
# 说明: 正常 test 流程可以完成本轮代码编译，但依然会撞上项目里已有的 macOS ValidateEmbeddedBinary 问题；这不是 phase5 新引入的问题
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
Testing failed:
    Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
    Testing cancelled because the build failed.
```

```bash
# 路径: 工作区根目录
# 命令: xcodebuild test-without-building -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests
# 说明: 使用 test-without-building 绕过工程级 ValidateEmbeddedBinary 校验后，本轮相关定向测试全部通过；共 37 个测试用例通过
** TEST EXECUTE SUCCEEDED **

Test suite 'CanvasContextMenuActionResolverTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasContextMenuActionResolverTests.testUnselectedImageIncludesCropCommandAndResolvesToTargetCropCommand()' passed
Test case 'CanvasContextMenuActionResolverTests.testSelectedVideoInMultiSelectionHidesSingleItemVideoAction()' passed
Test case 'CanvasContextMenuActionResolverTests.testInlineTextEditSuppressesContextMenuActions()' passed
Test case 'CanvasContextMenuActionResolverTests.testInlineCropContextOnlyExposesCropDoneCommand()' passed

Test suite 'CanvasCommandPolicyParityTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasCommandPolicyParityTests.testBeginCropModeCommandTargetsUnselectedItemAndReplacesSelection()' passed

Test suite 'CanvasClickSelectionResolverTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasClickSelectionResolverTests.testResolveClearsSelectionOnBlankClickEvenWhenMultiSelectModeIsOn()' passed
Test case 'CanvasClickSelectionResolverTests.testResolveUsesCommandClickToToggleMembership()' passed
Test case 'CanvasClickSelectionResolverTests.testResolveUsesPersistentMultiSelectModeToToggleMembership()' passed

Test suite 'CanvasToolbarStateBuilderTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateDisablesMultiSelectDuringCropMode()' passed
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateDisablesMultiSelectDuringInlineTextEdit()' passed
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateHidesItemsInReadingMode()' passed
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateIncludesMultiSelectItem()' passed
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateReflectsActiveMultiSelectMode()' passed
```

## 当前结论

- `phase5` 的核心收口已经完成：上下文菜单、命令启用态、执行器和工具条现在都基于同一套 effective subject 语义工作。
- `Crop`、`Edit Text`、`Set Display Frame`、`Import GIF Frames` 这类单对象动作，已经被限制在 `effectiveSelectionCount == 1` 且目标类型匹配的前提下。
- 未选中对象右键时，菜单仍可针对目标对象；若命中已选中对象或组选框，批量命令仍默认作用于当前选择集。
- 当前工作区里仍有一个 `.cursor/plans/board-multiselect-plan_96ecdbb5.plan.md` 旧变更存在；本次记录没有修改该计划文件。
- 本次只写记录文件，未提交。
