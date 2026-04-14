# 20260414_184439 图板多选阶段2改动记录

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff`、`git diff --stat`、当前文件内容，以及本轮执行过的 `xcodebuild` / `ReadLints` 结果；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”的方式归纳 phase2 实际落地内容。

## 当前 Changes 快照

```bash
# 命令: git status --short
# 说明: 这是创建本记录前工作区里可见的全部 changes
 M .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
```

```bash
# 命令: git diff --stat
# 说明: 这是创建本记录前 diff 体量概览
.../plans/board-multiselect-plan_96ecdbb5.plan.md  |   2 +-
.../Canvas/Core/CanvasContextMenuContext.swift     |  18 ++-
.../Canvas/Core/CanvasContextResolver.swift        |  72 +++++++--
.../Canvas/Core/CanvasEditOverlayHitTester.swift   |  16 +-
.../Canvas/Core/CanvasPointerPressContext.swift    |   6 +
.../Canvas/Core/CanvasRenderSnapshot.swift         |  41 +++++
MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    | 109 +++++++++++--
.../Canvas/Editing/CanvasCommandCatalog.swift      |   2 +
.../Canvas/Editing/CanvasEditorSession.swift       |   5 +-
.../CanvasContextMenuCommandResolver.swift         |   9 ++
.../iOS/Canvas/iOSCanvasViewportView.swift         |  43 ++++++
.../Platform/iOS/iOSViewController.swift           |  16 ++
.../macOS/Canvas/macOSCanvasViewportView.swift     |  43 ++++++
.../Platform/macOS/macOSViewController.swift       |  16 ++
.../CanvasContextMenuActionResolverTests.swift     |  61 ++++++++
.../CanvasEditorSessionAlignmentOverlayTests.swift | 171 ++++++++++++++++++++-
16 files changed, 596 insertions(+), 34 deletions(-)
```

phase2 的主体改动集中在：

- `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
- `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
- `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
- `MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`

当前 changes 里还包含 `.cursor/plans/board-multiselect-plan_96ecdbb5.plan.md` 的阶段状态同步，本记录会在末尾如实登记，但它不是 phase2 生产代码主体。

## 1. 渲染契约升级为“成员高亮 + 单一 active overlay”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 符号: CanvasEditSelectionOverlayPayload / CanvasRenderSnapshot
// 说明: 旧契约只有一个 selection payload 和一个 editOverlay，没有多选成员高亮，也没有组选框主题。
struct CanvasEditSelectionOverlayPayload {
    let rotateAffordance: CanvasEditRotateOverlayPayload
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let items: [CanvasRenderItem]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 符号: CanvasSelectionHighlight / CanvasEditSelectionOverlaySubject / CanvasRenderSnapshot
// 说明: 新契约显式区分“单选 overlay”与“组选框 overlay”，并单独提供 passive member highlights。
struct CanvasSelectionHighlight: Equatable {
    let itemID: CanvasItemID
    let screenQuad: CanvasQuad
    let isPrimary: Bool
}

enum CanvasEditSelectionOverlaySubject: Equatable {
    case singleItem(itemID: CanvasItemID)
    case group(primaryItemID: CanvasItemID, memberItemIDs: [CanvasItemID])
}

struct CanvasEditSelectionOverlayPayload {
    let subject: CanvasEditSelectionOverlaySubject
    let rotateAffordance: CanvasEditRotateOverlayPayload
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionHighlights: [CanvasSelectionHighlight]
    let editOverlay: CanvasEditRenderOverlay?
    let interactionOverlay: CanvasInteractionRenderOverlay?
}
```

这里的核心变化不是“再多画一层”，而是把渲染数据源本身从“单选唯一视图”提升成“多选成员态 + 单一活跃编辑态”的双通道模型，后续 hit-testing 和 controller 才能在不破坏裁剪流的前提下识别组选框。

## 2. Renderer 从“单对象 overlay”升级为“单选直出 / 多选合成”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:)
// 说明: 旧实现只读取 interactionState.selectedItemID，并直接为单个对象生成 selection overlay。
guard
    let selectedItemID = interactionState.selectedItemID,
    let selectedItem = scene.boardItem(withID: selectedItemID)
else {
    return nil
}

let effectiveItem = effectiveBoardItem(
    from: selectedItem,
    rotationPreviewState: rotationPreviewState
)
let worldQuad = effectiveItem.worldQuad
let screenQuad = camera.worldToViewport(worldQuad)
let selectionPayload = CanvasEditSelectionOverlayPayload(
    rotateAffordance: makeRotateAffordance(
        screenCenter: camera.worldToViewport(effectiveItem.center),
        screenQuad: screenQuad
    )
)

return CanvasEditRenderOverlay(
    itemID: effectiveItem.id,
    kind: .selection,
    activeWorldQuad: worldQuad,
    activeScreenQuad: screenQuad,
    handles: makeCornerEditHandles(for: screenQuad),
    payload: .selection(selectionPayload)
)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:) / makeSelectionHighlights(...) / selectedOverlayItems(...) / groupSelectionWorldBounds(...)
// 说明: 新实现先收集整个选择集；单选仍走原 geometry，多选时按所有成员 world bounds 合成组选框，并额外输出 selectionHighlights。
let selectedItems = selectedOverlayItems(
    scene: scene,
    interactionState: interactionState,
    rotationPreviewState: rotationPreviewState
)
guard
    let primarySelectedItemID = interactionState.primarySelectedItemID,
    selectedItems.isEmpty == false
else {
    return nil
}

let subject: CanvasEditSelectionOverlaySubject
let worldQuad: CanvasQuad
let screenQuad: CanvasQuad
let screenCenter: CGPoint
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
} else {
    let groupWorldBounds = groupSelectionWorldBounds(for: selectedItems)
    subject = .group(
        primaryItemID: resolvedPrimarySelectedItemID,
        memberItemIDs: selectedItems.map(\.id)
    )
    worldQuad = CanvasQuad(rect: groupWorldBounds)
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(
        CGPoint(x: groupWorldBounds.midX, y: groupWorldBounds.midY)
    )
}

private func makeSelectionHighlights(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> [CanvasSelectionHighlight] {
    guard inlineEditState == nil, interactionState.selectionCount > 1 else {
        return []
    }

    return selectedOverlayItems(
        scene: scene,
        interactionState: interactionState,
        rotationPreviewState: rotationPreviewState
    ).map { item in
        CanvasSelectionHighlight(
            itemID: item.id,
            screenQuad: camera.worldToViewport(item.worldQuad),
            isPrimary: item.id == interactionState.primarySelectedItemID
        )
    }
}
```

除了组选框本身，`rotationInteractionState` / `alignmentInteractionState` 的入口判断也从 `selectedItemID` 改成了 `singleSelectedItemID`。这一步是为了保证：多选下只显示组选框，不错误复用单对象的旋转 HUD 和对齐 HUD。

## 3. 命中与上下文解析从“单句柄”扩展到“组句柄 + 集合 membership”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数: CanvasEditOverlayHitTargetKind / resolveSelectionHitTarget(at:editOverlay:metrics:)
// 说明: 旧命中模型只认识单对象 rotateHandle 和 selectionHandle。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
}

if rotateHitRect.contains(viewportPoint) {
    return CanvasEditOverlayHitTarget(
        kind: .rotateHandle,
        itemID: editOverlay.itemID,
        anchorRect: rotateHitRect
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数: resolvePointerTarget(...) / resolveContext(...) / resolveTarget(...)
// 说明: 旧解析链路把 selectedItemID 当作唯一选中项，无法把“已选中的其他成员”识别为 selected body。
func resolvePointerTarget(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isReadingModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext

let targetKind: CanvasPointerTargetKind =
    itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数: CanvasEditOverlayHitTargetKind / resolveSelectionHitTarget(at:editOverlay:metrics:)
// 说明: 新命中模型为组选框新增 groupRotateHandle / groupSelectionHandle，避免与单对象变换语义混淆。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
}

let rotateHitTargetKind: CanvasEditOverlayHitTargetKind = payload.subject.isGroupSelection
    ? .groupRotateHandle
    : .rotateHandle

let handleHitTargetKind: CanvasEditOverlayHitTargetKind = payload.subject.isGroupSelection
    ? .groupSelectionHandle(role: role)
    : .selectionHandle(role: role)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数: resolvePointerTarget(...) / resolveContext(...) / resolveTarget(...) / contextMenuTargetKind(for:)
// 说明: 解析链路改为接收 selectedItemIDs + primarySelectedItemID，并把 scene 命中改为集合 membership 判断。
func resolvePointerTarget(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemIDs: [CanvasItemID],
    isInlineEditModeActive: Bool,
    isReadingModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext

func resolveContext(
    at viewportPoint: CGPoint,
    scene: CanvasScene,
    camera: CanvasCamera,
    renderSnapshot: CanvasRenderSnapshot,
    selectedItemIDs: [CanvasItemID],
    primarySelectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool,
    isReadingModeActive: Bool,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext

let targetKind: CanvasPointerTargetKind =
    selectedItemIDs.contains(itemID)
    ? .selectedItemBody
    : .unselectedItemBody

case .groupRotateHandle:
    return .groupRotateHandle
case let .groupSelectionHandle(role):
    return .groupSelectionHandle(role: role)
```

同一轮里，`CanvasPointerPressContext.swift` 和 `CanvasContextMenuContext.swift` 也同步补上了 `groupRotateHandle` / `groupSelectionHandle`，保证 pointer state、context menu 和 hit target 三层枚举保持一致，不会出现一层能识别、另一层丢语义的情况。

## 4. 视图层把“单选 outline”升级为“成员高亮 + 组选框”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数: setupLayers() / refreshSelectionChrome(from:) / hideSelectionOverlay()
// 说明: 旧实现只有 selectionOutlineLayer，没有被动成员高亮层。
private let overlayLayer = CALayer()
private let selectionOutlineLayer = CAShapeLayer()

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .selection(payload) = editOverlay.payload else {
        hideSelectionOverlay()
        return
    }

    selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    // 这里继续绘制 selection handles 和 rotate affordance
    refreshRotateAffordance(payload.rotateAffordance)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数: setupLayers() / configureSelectionHighlightsLayer() / refreshSelectionHighlights() / hideSelectionOverlay()
// 说明: iOS 端新增 selectionHighlightsLayer，在绘制组选框前先把所有已选成员的 screenQuad 轻量描边。
private static let selectionHighlightStrokeColor = CGColor(
    red: 0,
    green: 122.0 / 255.0,
    blue: 1,
    alpha: 0.35
)
private static let selectionHighlightLineWidth: CGFloat = 1.5

private let overlayLayer = CALayer()
private let selectionHighlightsLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .selection(payload) = editOverlay.payload else {
        hideSelectionOverlay()
        return
    }
    refreshSelectionHighlights()

    selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    refreshRotateAffordance(payload.rotateAffordance)
}

private func refreshSelectionHighlights() {
    guard snapshot.selectionHighlights.isEmpty == false else {
        selectionHighlightsLayer.path = nil
        selectionHighlightsLayer.isHidden = true
        return
    }

    let path = CGMutablePath()
    for highlight in snapshot.selectionHighlights {
        path.addPath(Self.quadPath(for: highlight.screenQuad))
    }
    selectionHighlightsLayer.frame = bounds
    selectionHighlightsLayer.path = path
    selectionHighlightsLayer.isHidden = false
    selectionHighlightsLayer.contentsScale = currentContentsScale
}

private func hideSelectionOverlay() {
    selectionHighlightsLayer.path = nil
    selectionHighlightsLayer.isHidden = true
    selectionOutlineLayer.path = nil
    selectionOutlineLayer.isHidden = true
}
```

`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 同步做了对称改动：同样新增 `selectionHighlightsLayer`、`configureSelectionHighlightsLayer()`、`refreshSelectionHighlights()` 和 `hideSelectionOverlay()` 的清理逻辑，两端渲染结构保持一致。

## 5. Controller / 菜单接线把组句柄与旧单对象变换隔离开

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 说明: 旧状态机只认识单对象的 rotateHandle / selectionHandle；如果直接把组选框复用成旧命中类型，会误走单对象缩放/旋转。
switch pressContext.targetKind {
case .rotateHandle:
    pointerDragState = .rotatingSelectedItem(rotateState)
    beginRotationInteraction(for: itemID)
case let .selectionHandle(handleRole):
    pointerDragState = .resizingSelectedItem(resizeState)
    resizeSelectedItem(using: resizeState, to: location)
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .selectionHandle:
    reason = "resize item"
case .selectedItemBody:
    reason = "move item"
case .unselectedItemBody, .blank:
    return
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / beginPointerHistoryTransactionIfNeeded(for:)
// 说明: phase2 先把组选框命中单独接出来并显式 no-op，避免过早落到 phase4 才该接入的组变换逻辑。
switch pressContext.targetKind {
case .rotateHandle:
    pointerDragState = .rotatingSelectedItem(rotateState)
    beginRotationInteraction(for: itemID)
case .groupRotateHandle:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case let .selectionHandle(handleRole):
    pointerDragState = .resizingSelectedItem(resizeState)
    resizeSelectedItem(using: resizeState, to: location)
case .groupSelectionHandle:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    // ...
case .unselectedItemBody, .blank:
    // ...
}

switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    return
case .cropHandle, .cropTranslationArea:
    reason = "crop item"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    return
case .selectedItemBody:
    reason = "move item"
case .unselectedItemBody, .blank:
    return
}
```

`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 同步做了同样的分支隔离：`groupRotateHandle` / `groupSelectionHandle` 会被识别、记录点击目标，但不会误触发旧的单对象变换状态机。

### 菜单与 Session 接线同步补齐

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: resolveContext(at:interactionMetrics:) / resolvePointerTarget(at:interactionMetrics:)
// 说明: Session 不再只把 selectedItemID 传给 resolver，而是改为传整组选择和 primary。
contextResolver.resolveContext(
    at: viewportPoint,
    scene: scene,
    camera: camera,
    renderSnapshot: lastRenderSnapshot,
    selectedItemIDs: interactionState.selectedItemIDs,
    primarySelectedItemID: interactionState.primarySelectedItemID,
    isInlineEditModeActive: isInlineEditModeActive,
    isInlineCropModeActive: isInlineCropModeActive,
    isReadingModeActive: isReadingModeActive,
    interactionMetrics: interactionMetrics
)

contextResolver.resolvePointerTarget(
    at: viewportPoint,
    scene: scene,
    camera: camera,
    renderSnapshot: lastRenderSnapshot,
    selectedItemIDs: interactionState.selectedItemIDs,
    isInlineEditModeActive: isInlineEditModeActive,
    isReadingModeActive: isReadingModeActive,
    interactionMetrics: interactionMetrics
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数: candidateActionIDs(for:session:) / operatesOnCurrentSelection(in:)
// 说明: 组选框 handle 上下文默认仍然作用于当前选择集，但显式去掉单对象专属动作，避免出现 Crop / Edit Text 这类错误菜单。
case .groupSelectionHandle, .groupRotateHandle:
    return selectedItemActionIDs(
        includeCropCommand: false,
        includeBeginTextEditCommand: false,
        includeVideoDisplayFrameAction: false,
        includeGIFFrameImportAction: false
    )

case .selectedItemBody,
     .selectionHandle,
     .groupSelectionHandle,
     .rotateHandle,
     .groupRotateHandle,
     .cropHandle,
     .cropOutline:
    return true
```

同类接线也同步补到了 `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`，让 group handle targetKind 仍然被视为“作用于当前选择集”的上下文。

## 6. 测试从“单对象 overlay”补到“组选框 / 组命中 / 组菜单”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: 旧覆盖范围摘录
// 说明: 修改前测试主要覆盖 alignment / rotation overlay 的单对象语义，没有多选组选框和组命中断言。
func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws
func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws
func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit()
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: 旧覆盖范围摘录
// 说明: 修改前菜单测试只覆盖 selected / unselected body 和多选文本编辑隐藏，没有组选框手柄上下文。
func testSelectedContextResolvesDuplicateToSelectionCommand()
func testUnselectedContextResolvesDuplicateToTargetCommand()
func testMultiSelectionTextContextHidesBeginTextEditAction()
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: testMakeCanvasSnapshotProducesSelectionHighlightsAndGroupOverlayForMultiSelection() 等
// 说明: 新增的测试直接覆盖 phase2 的三个关键结果：组选框、成员 body membership、组 handle / rotate hit target。
func testMakeCanvasSnapshotProducesSelectionHighlightsAndGroupOverlayForMultiSelection() {
    XCTAssertEqual(snapshot.selectionHighlights.map(\.itemID), [firstItem.id, secondItem.id])
    guard
        let editOverlay,
        case let .selection(payload) = editOverlay.payload,
        case let .group(primaryItemID, memberItemIDs) = payload.subject
    else {
        XCTFail("Expected multi-selection snapshot to expose a group selection overlay.")
        return
    }
    XCTAssertEqual(primaryItemID, secondItem.id)
    XCTAssertEqual(memberItemIDs, [firstItem.id, secondItem.id])
}

func testResolvePointerTargetTreatsEverySelectedMemberBodyAsSelected()
func testResolvePointerTargetHitsGroupSelectionHandleForMultiSelection() throws
func testResolvePointerTargetHitsGroupRotateHandleForMultiSelection() throws
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数: testGroupSelectionHandleContextExposesBatchActionsWithoutSingleItemEditActions()
// 说明: 新增菜单测试，确保组选框 handle 上下文只暴露批量动作，不错误显示 crop / beginTextEdit。
func testGroupSelectionHandleContextExposesBatchActionsWithoutSingleItemEditActions() {
    let context = makeContextMenuContext(
        targetKind: .groupSelectionHandle(role: .topLeading),
        targetItemID: secondItem.id,
        selectedItemID: secondItem.id
    )

    XCTAssertFalse(
        actionStates.contains { actionState in
            if case .command(.crop) = actionState.actionID { return true }
            if case .command(.beginTextEdit) = actionState.actionID { return true }
            return false
        }
    )
    guard case let .duplicateSelection(recordHistory)? = duplicateCommand else {
        XCTFail("Expected group handle duplicate to resolve to duplicateSelection.")
        return
    }
    XCTAssertTrue(recordHistory)
}
```

## 7. 计划文件状态同步

这条改动出现在当前工作区的 changes 里，因此一并如实记录；它反映的是阶段状态同步，不属于 phase2 主体生产代码。

### 修改前

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 符号: todos.phase2-render-hit-testing
# 说明: 记录 phase2 实施前的计划状态。
- id: phase2-render-hit-testing
  content: 实现成员高亮、组选框、组手柄与对应命中模型。
  status: pending
```

### 修改后

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 符号: todos.phase2-render-hit-testing
# 说明: 当前工作区里 phase2 已同步标记为 completed。
- id: phase2-render-hit-testing
  content: 实现成员高亮、组选框、组手柄与对应命中模型。
  status: completed
```

## 8. 验证结果

```text
# 检查方式: ReadLints
# 说明: 本轮修改涉及文件未发现新增 IDE 诊断。
No linter errors found.
```

```bash
# 命令: xcodebuild build -scheme MyCanvas_Ver_0 -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'
# 说明: 用于确认 iOS 端的 viewport / controller / menu 改动至少能通过构建。
** BUILD SUCCEEDED **
```

```bash
# 命令: xcodebuild test -scheme MyCanvas_Ver_0 -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests
# 说明: 新增的两个 phase2 测试文件已经进入 SwiftCompile；最终仍被既有工程配置问题阻塞。
SwiftCompile normal arm64 Compiling CanvasContextMenuActionResolverTests.swift, CanvasEditorSessionAlignmentOverlayTests.swift
SwiftCompile normal arm64 MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
SwiftCompile normal arm64 MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
** TEST FAILED **
```

结论：

- phase2 的核心代码已经落到渲染契约、renderer、hit-testing、context resolver、双端 viewport、双端 controller 和测试层。
- iOS 构建通过，说明双端共享代码和 iOS 侧接线是通的。
- macOS 定向测试没有暴露新的 phase2 代码级编译错误，但最终依旧被已知的 `Add To Canvas.appex` 平台嵌入配置问题拦住。
- 当前未提交。
