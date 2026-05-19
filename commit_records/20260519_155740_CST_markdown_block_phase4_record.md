# 20260519_155740_CST_markdown_block_phase4_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 4。
  - 把 iOS 上的“单选 markdown -> 悬浮 accessory -> Edit / +/- -> 最简编辑器 -> 回写 markdown source 并按当前宽度重排高度”链路接通。
  - 从根因上修正 `beginMarkdownEdit(withID:)` 在“目标 markdown 已经是当前单选项”时返回 `false` 的问题，避免 accessory 上点击 `Edit` 无法打开编辑器。
  - 把 markdown `+/-` 的语义从“只改 style、不重排容器高度”修正为“保留当前 block 宽度，并按新字号重算高度”。
  - 新增 iOS 最简 markdown 编辑器，并补充针对 follow-up、尺寸重排和回写行为的测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示工作区里除阶段 4 相关文件外，还存在两个未纳入本记录的当前 changes：`@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 与 `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`。
  - 针对阶段 4 相关代码，`git status --short` 显示 `7` 个已跟踪修改文件，外加 `1` 个未跟踪新增目录 `MyCanvas_Ver_0/Platform/iOS/Markdown/`（其中包含本次新增的 `iOSCanvasMarkdownEditorViewController.swift`）。
  - 针对阶段 4 已跟踪文件，`git diff --stat` 显示：`7 files changed, 350 insertions(+), 8 deletions(-)`。
  - 上述 `git diff --stat` 只统计已跟踪文件，不包含本次新增的 `MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`。
- 本记录不包含：
  - 阶段 5 的 board list / minimap / macOS 编辑 parity。
  - 任何 git 提交行为。

## 当前 changes 摘要

- `CanvasCommandFollowUp` 新增 `presentMarkdownEditor(itemID:)`，`beginMarkdownEdit` 不再只刷新选中态，而是可以触发 controller follow-up。
- `CanvasEditorSession` 新增 `CanvasMarkdownEditCommitResult`、`measuredMarkdownItemSize(...)`、`updateMarkdownItemContent(...)`、`commitMarkdownEdit(withID:markdownSource:)`，把 markdown 编辑回写与尺寸重排统一收敛到 session。
- `CanvasEditorSession.adjustMarkdownContentSize(by:)` 不再直接复用旧容器高度，而是改为“保留当前宽度、重新测量高度”。
- `SelectionAccessoryHostView` 的命中链从“整屏自吃 hit test”改为“仅响应内部按钮或显式 dismiss”，避免接线后第一下点击画布被 accessory 容器吞掉。
- `iOSViewController` 接入 `selectionAccessoryHostView`、selection accessory 的布局刷新、命令分发、`presentMarkdownEditor(for:)` 和 accessory 状态同步。
- 新增 `iOSCanvasMarkdownEditorViewController`，提供最简 `Cancel / Done + UITextView` 的 markdown source 编辑入口。
- `macOSViewController` 只做 follow-up 穷举补齐，当前阶段保持 no-op，以保证阶段 4 在双端 target 下可编译。
- `CanvasCommandPolicyParityTests` 新增/修正了 markdown follow-up 与重排高度契约测试。

## 修改一：把 markdown 编辑入口接到命令 follow-up 链

### 1.1 `CanvasCommand.swift`

#### 修改前

- `CanvasCommandFollowUp` 只有手绘编辑器入口。
- `beginMarkdownEdit` 即使在 executor 成功执行，也没有后续的 controller 级编辑器弹出协议。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift（修改前）
// 函数名: CanvasCommandFollowUp
// 功能说明: 修改前 follow-up 枚举只覆盖 hand drawing editor，没有 markdown editor 入口。
enum CanvasCommandFollowUp: Equatable {
    case presentHandDrawingEditor(itemID: CanvasItemID)
}
```

#### 修改后

- 增加 `presentMarkdownEditor(itemID:)`，把 markdown 编辑器弹出也纳入命令 follow-up 协议。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandFollowUp
// 功能说明: 修改后命令系统可以把 markdown 编辑器弹出请求传递给平台 controller。
enum CanvasCommandFollowUp: Equatable {
    case presentHandDrawingEditor(itemID: CanvasItemID)
    case presentMarkdownEditor(itemID: CanvasItemID)
}
```

### 1.2 `CanvasCommandExecutor.swift`

#### 修改前

- `beginMarkdownEdit(itemID:)` 只会返回 `refreshReason`。
- 即使 session 认为可以开始 markdown edit，controller 层也拿不到明确的“弹出 markdown 编辑器”信号。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift（修改前）
// 函数名: execute(_:)
// 功能说明: 修改前 beginMarkdownEdit 只刷新画布，不产生 editor follow-up。
case let .beginMarkdownEdit(itemID):
    guard session.beginMarkdownEdit(withID: itemID) else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "begin markdown edit \(itemID.uuidString)"
    )
```

#### 修改后

- `beginMarkdownEdit(itemID:)` 在 session 通过后，显式返回 `.presentMarkdownEditor(itemID:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: execute(_:)
// 功能说明: 修改后 beginMarkdownEdit 会显式请求 controller 弹出 markdown editor。
case let .beginMarkdownEdit(itemID):
    guard session.beginMarkdownEdit(withID: itemID) else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "begin markdown edit \(itemID.uuidString)",
        followUp: .presentMarkdownEditor(itemID: itemID)
    )
```

## 修改二：在 `CanvasEditorSession` 中从根因上补齐 markdown 编辑与重排语义

### 2.1 修正 `beginMarkdownEdit(withID:)` 的根因问题

#### 修改前

- `beginMarkdownEdit(withID:)` 一律调用 `replaceSelection(...)`。
- 当目标 markdown 已经是当前单选项时，`replaceSelection(...)` 会因为“选中态无变化”而返回 `false`。
- 这会让 `CanvasCommandExecutor.execute(.beginMarkdownEdit(...))` 直接失败，导致 accessory 上点 `Edit` 打不开编辑器。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: beginMarkdownEdit(withID:)
// 功能说明: 修改前 beginMarkdownEdit 依赖 replaceSelection 的返回值，已选中 markdown 会被误判为不能进入编辑。
@discardableResult
func beginMarkdownEdit(withID itemID: CanvasItemID) -> Bool {
    guard canBeginMarkdownEdit(withID: itemID) else {
        return false
    }

    return replaceSelection(
        with: [itemID],
        primarySelectedItemID: itemID
    )
}
```

#### 修改后

- 增加“如果当前就是该 markdown 单选，则直接返回 `true`”的短路分支。
- 这样 accessory 的 `Edit` 按钮不会再被“选中态未变化”卡死。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: beginMarkdownEdit(withID:)
// 功能说明: 修改后 beginMarkdownEdit 允许已单选 markdown 直接进入编辑，避免 Edit follow-up 被 selection no-op 拦截。
@discardableResult
func beginMarkdownEdit(withID itemID: CanvasItemID) -> Bool {
    guard canBeginMarkdownEdit(withID: itemID) else {
        return false
    }

    if singleSelectedItemID == itemID {
        return true
    }

    return replaceSelection(
        with: [itemID],
        primarySelectedItemID: itemID
    )
}
```

### 2.2 补齐 markdown 的提交结果模型和提交入口

#### 修改前

- `commitMarkdownEdit()` 仍然是占位实现，直接返回 `false`。
- session 内没有真正的 markdown source 回写提交入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: commitMarkdownEdit()
// 功能说明: 修改前 markdown edit 提交仍是空壳，controller 无法通过 session 完成内容回写。
@discardableResult
func commitMarkdownEdit() -> Bool {
    false
}
```

#### 修改后

- 新增 `CanvasMarkdownEditCommitResult`。
- 新增 `commitMarkdownEdit(withID:markdownSource:)`，在 session 内统一处理 source 是否变化、历史记录、board 扩张与返回值。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasMarkdownEditCommitResult / commitMarkdownEdit(withID:markdownSource:)
// 功能说明: 修改后 session 可以真实提交 markdown source，并把历史记录与 board expand 统一收敛到一处。
struct CanvasMarkdownEditCommitResult {
    let itemID: CanvasItemID
    let didChangeDocument: Bool
}

@discardableResult
func commitMarkdownEdit(
    withID itemID: CanvasItemID,
    markdownSource: String
) -> CanvasMarkdownEditCommitResult? {
    guard let item = scene.markdownItem(withID: itemID) else {
        return nil
    }

    if markdownSource == item.markdownSource {
        return CanvasMarkdownEditCommitResult(
            itemID: itemID,
            didChangeDocument: false
        )
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard let updatedItem = updateMarkdownItemContent(
        withID: itemID,
        markdownSource: markdownSource,
        style: item.style
    ) else {
        return nil
    }

    expandBoardIfNeeded(toInclude: updatedItem.worldBounds)
    let changeReason = "edit markdown item"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return CanvasMarkdownEditCommitResult(
        itemID: itemID,
        didChangeDocument: true
    )
}
```

### 2.3 把 markdown 尺寸重算从 controller 侧收回到 session helper

#### 修改前

- `CanvasEditorSession` 只有 text 的内容测量入口。
- `adjustMarkdownContentSize(by:)` 直接把旧的 `item.size` 原样传回 `scene.updateMarkdownItem(...)`，导致字号变化后容器高度不跟着重排。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: adjustMarkdownContentSize(by:)
// 功能说明: 修改前 markdown +/- 只改 style，不重算基于当前宽度的新高度。
let beforeSnapshot = currentBoardHistorySnapshot()
guard let updatedItem = scene.updateMarkdownItem(
    withID: item.id,
    markdownSource: item.markdownSource,
    style: updatedStyle,
    size: item.size
) else {
    return nil
}
```

#### 修改后

- 新增 `measuredMarkdownItemSize(...)` 与 `updateMarkdownItemContent(...)`，把“保留当前容器宽度 -> 按 markdown 重新测量高度 -> 更新 scene”统一封装。
- `adjustMarkdownContentSize(by:)` 改成复用 `updateMarkdownItemContent(...)`，让 `+/-` 与 Done 提交遵循同一套尺寸语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: measuredMarkdownItemSize(for:style:layoutWidth:) / updateMarkdownItemContent(withID:markdownSource:style:)
// 功能说明: 修改后 session 会在保留当前 block 宽度的前提下，统一重算 markdown 的容器高度。
func measuredMarkdownItemSize(
    for markdownSource: String,
    style: CanvasTextStyle,
    layoutWidth: CGFloat
) -> CGSize {
    let resolvedLayoutWidth = max(layoutWidth, 1)
    return CGSize(
        width: resolvedLayoutWidth,
        height: CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: markdownSource,
            style: style,
            maxLayoutWidth: resolvedLayoutWidth
        )
    )
}

@discardableResult
func updateMarkdownItemContent(
    withID itemID: CanvasItemID,
    markdownSource: String,
    style: CanvasTextStyle
) -> CanvasMarkdownItem? {
    guard let item = scene.markdownItem(withID: itemID) else {
        return nil
    }

    let size = measuredMarkdownItemSize(
        for: markdownSource,
        style: style,
        layoutWidth: item.size.width
    )
    return scene.updateMarkdownItem(
        withID: itemID,
        markdownSource: markdownSource,
        style: style,
        size: size
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: adjustMarkdownContentSize(by:)
// 功能说明: 修改后 markdown +/- 复用统一的内容更新 helper，字号变化后容器高度会重新测量。
let beforeSnapshot = currentBoardHistorySnapshot()
guard let updatedItem = updateMarkdownItemContent(
    withID: item.id,
    markdownSource: item.markdownSource,
    style: updatedStyle
) else {
    return nil
}
```

## 修改三：修正 `SelectionAccessoryHostView` 的整屏命中拦截问题

#### 修改前

- `hitTest(...)` 在点击 accessory 容器外部区域时，会把根 view 自己返回出去。
- 一旦阶段 4 在 iOS 上把 accessory 真正挂上来，整屏 overlay 会吞掉第一下画布点击，导致外部点击无法直接落到画布。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift（修改前）
// 函数名: hitTest(_:with:) / hitTest(_:)
// 功能说明: 修改前 accessory host 会把自身作为命中结果返回，导致容器外区域也拦截事件。
let hitView = super.hitTest(point, with: event)
return hitView === self ? self : hitView

let hitView = super.hitTest(point)
return hitView === self ? self : hitView
```

#### 修改后

- 容器外区域改为返回 `nil`，只让 accessory 内部按钮或显式 dismiss 逻辑响应。
- 这让 accessory 能作为悬浮工具条存在，而不是成为新的整屏输入层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift
// 函数名: hitTest(_:with:) / hitTest(_:)
// 功能说明: 修改后 accessory host 对容器外区域不再自吃事件，画布命中链可以继续向下传递。
let hitView = super.hitTest(point, with: event)
return hitView === self ? nil : hitView

let hitView = super.hitTest(point)
return hitView === self ? nil : hitView
```

## 修改四：在 `iOSViewController` 接通 accessory、编辑器与回写刷新

### 4.1 follow-up 分发与 accessory 命令派发

#### 修改前

- `handleCommandFollowUp(_:)` 只处理手绘编辑器。
- controller 内没有 markdown accessory 的按钮分发逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: handleCommandFollowUp(_:)
// 功能说明: 修改前 controller 只接手 hand drawing follow-up，没有 markdown 编辑器入口。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case let .presentHandDrawingEditor(itemID):
        guard supportsHandDrawingEditing else {
            return
        }
        presentHandDrawingEditor(for: itemID)
    }
}
```

#### 修改后

- 新增 markdown follow-up 处理。
- 新增 `performSelectionAccessoryCommand(_:)`，把 accessory 上的 `Edit / - / +` 分发回命令系统。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleCommandFollowUp(_:) / performSelectionAccessoryCommand(_:)
// 功能说明: 修改后 iOS controller 可以处理 markdown editor follow-up，并把 accessory 动作派发回命令系统。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case let .presentHandDrawingEditor(itemID):
        guard supportsHandDrawingEditing else {
            return
        }
        presentHandDrawingEditor(for: itemID)
    case let .presentMarkdownEditor(itemID):
        presentMarkdownEditor(for: itemID)
    }
}

private func performSelectionAccessoryCommand(_ commandID: CanvasCommandID) {
    switch commandID {
    case .beginMarkdownEdit:
        guard let itemID = selectionAccessoryHostView.currentState?.itemID else {
            return
        }
        performCommand(.beginMarkdownEdit(itemID: itemID))
    case .decreaseMarkdownContentSize:
        performCommand(.decreaseMarkdownContentSize)
    case .increaseMarkdownContentSize:
        performCommand(.increaseMarkdownContentSize)
    default:
        return
    }
}
```

### 4.2 让 accessory 真正随选区显示、重排和消失

#### 修改前

- `iOSViewController` 只有 `contextMenuHostView`、`inputIndicatorHostView` 等 chrome。
- `updateContextMenuPresentation()`、`performCanvasRefresh(reason:)` 都不会同步 markdown accessory 的状态和布局。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: updateContextMenuPresentation() / performCanvasRefresh(reason:)
// 功能说明: 修改前 controller 不维护 markdown accessory 的显示状态，也不会在 refresh 后同步布局。
contextMenuHostView.apply(
    state: contextMenuState,
    layoutContext: layoutContext
)

canvasViewportView.apply(snapshot)
let afterViewportApply = ProcessInfo.processInfo.systemUptime
refreshMiniMap()
```

#### 修改后

- 新增 `selectionAccessoryHostView` 并接入 overlay layout pass。
- 新增 `syncSelectionAccessoryPresentation(...)`、`resolvedMarkdownSelectionAccessoryState()`、`markdownSelectionAccessoryAnchorRect(for:)`。
- 在 context menu 更新和 canvas refresh 后同步 accessory，可随着单选 markdown、context menu、编辑器弹出/关闭而显示或隐藏。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: syncSelectionAccessoryPresentation(layoutContext:) / resolvedMarkdownSelectionAccessoryState() / markdownSelectionAccessoryAnchorRect(for:)
// 功能说明: 修改后 controller 会按当前选区、编辑状态和 chrome 布局上下文，实时解析 markdown accessory 的状态与锚点。
private func syncSelectionAccessoryPresentation(
    layoutContext: CanvasChromeLayoutContext? = nil
) {
    guard isViewLoaded else {
        return
    }

    guard let state = resolvedMarkdownSelectionAccessoryState() else {
        selectionAccessoryHostView.dismiss()
        return
    }

    let resolvedLayoutContext =
        layoutContext ?? contextMenuLayoutContextForCurrentChromeState()
    selectionAccessoryHostView.apply(
        state: state,
        layoutContext: resolvedLayoutContext
    )
}

private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    guard
        workspaceMode == .editing,
        isTransitionInteractionFrozen == false,
        contextMenuState == nil,
        presentedViewController == nil,
        presentationInlineEditState == nil,
        let itemID = editorSession.singleSelectedItemID,
        scene.markdownItem(withID: itemID) != nil,
        let anchorRect = markdownSelectionAccessoryAnchorRect(for: itemID)
    else {
        return nil
    }

    let editDescriptor = CanvasCommandDescriptor(
        id: .beginMarkdownEdit,
        title: "Edit Markdown",
        systemImageName: "pencil",
        isEnabled: editorSession.canBeginMarkdownEdit(withID: itemID),
        isActive: false
    )
    let decreaseDescriptor = commandDescriptor(
        for: .decreaseMarkdownContentSize
    )
    let increaseDescriptor = commandDescriptor(
        for: .increaseMarkdownContentSize
    )
    return SelectionAccessoryState.markdown(
        itemID: itemID,
        anchorRect: anchorRect,
        editDescriptor: editDescriptor,
        decreaseDescriptor: decreaseDescriptor,
        increaseDescriptor: increaseDescriptor
    )
}

private func markdownSelectionAccessoryAnchorRect(
    for itemID: CanvasItemID
) -> CGRect? {
    if let editOverlay = lastRenderSnapshot.editOverlay,
       case let .selection(payload) = editOverlay.payload
    {
        switch payload.subject {
        case let .singleItem(selectedItemID) where selectedItemID == itemID:
            return selectionAccessoryHostView.convert(
                editOverlay.activeScreenQuad.boundingRect.standardized,
                from: canvasViewportView
            )
        case .singleItem, .group:
            break
        }
    }

    guard let renderItem = lastRenderSnapshot.items.first(where: {
        $0.id == itemID
    }) else {
        return nil
    }
    return selectionAccessoryHostView.convert(
        renderItem.screenQuad.boundingRect.standardized,
        from: canvasViewportView
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: updateContextMenuPresentation() / performCanvasRefresh(reason:)
// 功能说明: 修改后 accessory 会在 context menu 和 viewport 刷新后同步状态与布局，避免选区变化后悬浮条停留在旧位置。
contextMenuHostView.apply(
    state: contextMenuState,
    layoutContext: layoutContext
)
syncSelectionAccessoryPresentation(layoutContext: layoutContext)

canvasViewportView.apply(snapshot)
let afterViewportApply = ProcessInfo.processInfo.systemUptime
refreshMiniMap()
syncSelectionAccessoryPresentation()
```

### 4.3 新增 iOS markdown 编辑器弹出与错误反馈

#### 修改前

- `iOSViewController` 中不存在 `presentMarkdownEditor(for:)`。
- 选中 markdown 后没有任何最简 source 编辑入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改前 controller 中不存在 markdown 编辑器弹出逻辑。
// 此函数在修改前不存在。
```

#### 修改后

- 新增 `presentMarkdownEditor(for:)`，在展示前取消旋转交互并隐藏 accessory。
- 编辑器 Done 时回调 `editorSession.commitMarkdownEdit(withID:markdownSource:)`，若内容有变化则刷新画布。
- 新增 `presentMarkdownEditorError(message:)` 统一报错。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改后 controller 可以弹出最简 markdown editor，并在 Done 后回写 source、刷新画布。
private func presentMarkdownEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    guard let item = scene.markdownItem(withID: itemID) else {
        presentMarkdownEditorError(message: "Markdown item is no longer available.")
        return
    }

    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    selectionAccessoryHostView.dismiss()

    let editorViewController = iOSCanvasMarkdownEditorViewController(
        markdownSource: item.markdownSource
    ) { [weak self] markdownSource in
        guard let self else {
            return false
        }

        guard let commitResult = self.editorSession.commitMarkdownEdit(
            withID: itemID,
            markdownSource: markdownSource
        ) else {
            self.presentMarkdownEditorError(
                message: "Markdown item is no longer available."
            )
            return false
        }

        if commitResult.didChangeDocument {
            self.requestCanvasRefresh(
                reason: "commit markdown edit \(itemID.uuidString)"
            )
        }
        return true
    }
    present(editorViewController, animated: true)
}
```

## 修改五：新增 iOS 最简 markdown 编辑器

#### 修改前

- 仓库中没有独立的 iOS markdown 编辑器文件。
- controller 无法通过独立 VC 提供 `Done / Cancel + 原始 markdown 文本输入`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift（修改前）
// 函数名: N/A
// 功能说明: 修改前此文件不存在，iOS 端没有最简 markdown source 编辑器。
// 此文件在修改前不存在。
```

#### 修改后

- 新增 `iOSCanvasMarkdownEditorViewController`。
- 该控制器使用 `UITextView` 编辑原始 markdown source，提供 `Cancel / Done`，并通过闭包把提交动作交回 `iOSViewController`。
- 采用 `formSheet` + `medium/large detents`，作为阶段 4 的最简可用编辑器入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift
// 函数名: viewDidLoad() / handleDoneButtonTap()
// 功能说明: 修改后新增最简 iOS markdown 编辑器，负责 source 输入与 Done/Cancel 生命周期。
final class iOSCanvasMarkdownEditorViewController: UIViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textColor = .label
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        return textView
    }()

    init(
        markdownSource: String,
        onCommitMarkdownSource: @escaping (String) -> Bool
    ) {
        self.initialMarkdownSource = markdownSource
        self.onCommitMarkdownSource = onCommitMarkdownSource
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        modalTransitionStyle = .coverVertical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureButtons()
        configureSheetPresentation()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    @objc
    private func handleDoneButtonTap() {
        guard isCommitting == false else {
            return
        }

        isCommitting = true
        let didCommit = onCommitMarkdownSource(textView.text)
        isCommitting = false
        guard didCommit else {
            return
        }

        dismiss(animated: true)
    }
}
```

## 修改六：macOS 侧补齐 follow-up 穷举，保持阶段 4 双端可编译

#### 修改前

- `macOSViewController.handleCommandFollowUp(_:)` 只穷举到手绘编辑器 case。
- 一旦 `CanvasCommandFollowUp` 新增 markdown case，macOS target 会因为 `switch` 不穷举而编译失败。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: handleCommandFollowUp(_:)
// 功能说明: 修改前 macOS controller 只覆盖 hand drawing follow-up。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case .presentHandDrawingEditor:
        return
    }
}
```

#### 修改后

- 增加 `.presentMarkdownEditor` case，当前阶段先保持 no-op，仅用于让阶段 4 代码在 macOS target 下继续通过编译。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleCommandFollowUp(_:)
// 功能说明: 修改后 macOS controller 先以 no-op 方式承接 markdown follow-up，保持阶段 4 的双端编译兼容。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case .presentHandDrawingEditor:
        return
    case .presentMarkdownEditor:
        return
    }
}
```

## 修改七：用测试锁定阶段 4 契约

### 7.1 跟进命令 follow-up 和尺寸重排的测试契约

#### 修改前

- `CanvasCommandPolicyParityTests` 只锁定了 markdown 默认创建尺寸。
- 旧的 `testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()` 仍然断言“字号变化后 size 完全不变”，与阶段 4 的新语义相矛盾。
- 没有测试覆盖 `beginMarkdownEdit` 的 follow-up，也没有测试覆盖“Done 后按当前宽度重算高度”的提交语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift（修改前）
// 函数名: testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()
// 功能说明: 修改前测试仍锁定 markdown +/- 不改容器 size，这与阶段 4 的重排语义不一致。
let resizedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)
XCTAssertEqual(resizedItem.size, originalItem.size)
XCTAssertEqual(resizedItem.markdownSource, originalItem.markdownSource)
```

#### 修改后

- 新增 `testBeginMarkdownEditCommandProducesEditorFollowUp()`，锁定 beginMarkdownEdit 一定会请求 `.presentMarkdownEditor(itemID:)`。
- 旧的 markdown `+/-` 测试改为断言“宽度保持不变，高度按当前宽度重新测量”。
- 新增 `testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()`，锁定 Done 提交时保留当前容器宽度并更新 source / height。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testBeginMarkdownEditCommandProducesEditorFollowUp()
// 功能说明: 修改后新增 beginMarkdownEdit follow-up 测试，锁定 controller 弹出 markdown editor 的命令契约。
func testBeginMarkdownEditCommandProducesEditorFollowUp() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let executor = CanvasCommandExecutor(session: session)
    CanvasCommandPolicyParityTestRetainer.executors.append(executor)
    let item = try XCTUnwrap(session.addMarkdownItem())

    let result = try XCTUnwrap(
        executor.execute(.beginMarkdownEdit(itemID: item.id))
    )
    guard case let .presentMarkdownEditor(followUpItemID)? = result.followUp else {
        XCTFail("Expected beginMarkdownEdit to request markdown editor follow-up.")
        return
    }

    XCTAssertEqual(followUpItemID, item.id)
    XCTAssertEqual(session.singleSelectedItemID, item.id)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()
// 功能说明: 修改后测试锁定 markdown +/- 会保留当前宽度，并按新字号重新测量高度。
let resizedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
let expectedResizedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
    markdownSource: originalItem.markdownSource,
    style: resizedItem.style,
    maxLayoutWidth: originalItem.size.width
)
XCTAssertGreaterThan(resizedItem.style.fontSize, originalItem.style.fontSize)
XCTAssertEqual(resizedItem.size.width, originalItem.size.width)
XCTAssertEqual(resizedItem.size.height, expectedResizedHeight, accuracy: 0.0001)
XCTAssertEqual(resizedItem.markdownSource, originalItem.markdownSource)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()
// 功能说明: 修改后新增 markdown Done 提交测试，锁定 source 回写与“保留当前宽度、重算高度”的阶段 4 语义。
func testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let item = try XCTUnwrap(
        session.addMarkdownItem(
            markdownSource: "Seed",
            style: CanvasTextStyle(fontSize: 18)
        )
    )
    let customizedItem = try XCTUnwrap(
        session.scene.updateMarkdownItem(
            withID: item.id,
            markdownSource: item.markdownSource,
            style: item.style,
            size: CGSize(width: 210, height: 60)
        )
    )
    let updatedSource = """
    ## Updated

    A much longer markdown paragraph that should be reflowed using the current block width.
    """

    let commitResult = try XCTUnwrap(
        session.commitMarkdownEdit(
            withID: item.id,
            markdownSource: updatedSource
        )
    )
    let updatedItem = try XCTUnwrap(session.scene.markdownItem(withID: item.id))
    let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: updatedSource,
        style: customizedItem.style,
        maxLayoutWidth: customizedItem.size.width
    )

    XCTAssertTrue(commitResult.didChangeDocument)
    XCTAssertEqual(updatedItem.size.width, customizedItem.size.width)
    XCTAssertEqual(updatedItem.size.height, expectedHeight, accuracy: 0.0001)
    XCTAssertEqual(updatedItem.markdownSource, updatedSource)
}
```

## 验证结果

- `ReadLints` 检查以下本次改动文件：无新增 lint。
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- 运行 `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests`：
  - 第一次运行暴露了根因问题：`testBeginMarkdownEditCommandProducesEditorFollowUp()` 失败，原因是 `beginMarkdownEdit(withID:)` 在目标 markdown 已经处于单选时返回 `false`。
  - 修正 `CanvasEditorSession.beginMarkdownEdit(withID:)` 的已选中短路分支后，重新运行通过。
- 运行 `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"`：通过。

## 结论

- 阶段 4 的实现不只是把 UI 壳层接上，而是把 markdown block 的编辑入口、内容回写、命令 follow-up、selection accessory、以及尺寸重排语义统一打通。
- 本次真正的根因修复点有两个：
  - `beginMarkdownEdit(withID:)` 不再被 selection no-op 卡死。
  - markdown `+/-` 和 Done 提交都不再沿用旧高度，而是按当前 block 宽度统一重新测量高度。
