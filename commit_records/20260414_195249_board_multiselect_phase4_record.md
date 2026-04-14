# 20260414_195249 图板多选阶段4改动记录

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff --stat`、当前文件内容、定向 `xcodebuild` 结果与本轮 phase4 实际改动；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”的方式归纳组选框平移、缩放、旋转、对齐 solver 与渲染链路的真实落地情况。

## 当前 Changes 快照

```bash
# 路径: 工作区根目录
# 命令: date "+%Y%m%d_%H%M%S"
# 说明: 本记录文件名使用的时间戳
20260414_195249
```

```bash
# 路径: 工作区根目录
# 命令: git status --short
# 说明: 创建本记录前工作区中的全部 changes；其中 .cursor/plans 文件是当前工作区里同时存在的旧变更，本记录下面的代码说明聚焦 phase4 本轮实际代码修改
 M .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
 M MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
?? MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
?? MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
```

```bash
# 路径: 工作区根目录
# 命令: git diff --stat
# 说明: tracked 文件的 diff 体量概览；这条命令不会显示新增未跟踪文件
.../plans/board-multiselect-plan_96ecdbb5.plan.md  |   2 +-
.../Canvas/Core/CanvasAlignmentGuideSolver.swift   | 126 ++++---
.../Core/CanvasImagePresentationResolver.swift     |   9 +-
.../Canvas/Core/CanvasInlineEditState.swift        | 112 +++++-
MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    |  80 ++++-
MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift       |  48 +++
.../Platform/iOS/iOSViewController.swift           | 386 ++++++++++++++++++--
.../Platform/macOS/macOSViewController.swift       | 387 +++++++++++++++++++--
.../CanvasAlignmentGuideSolverTests.swift          |  53 +++
.../CanvasEditorSessionAlignmentOverlayTests.swift | 117 +++++++
10 files changed, 1178 insertions(+), 142 deletions(-)
```

当前 `git diff --stat` 不会显示的 phase4 新增文件：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
- `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`

## 1. 从“单对象拖拽状态”升级为共享的 selection transform 快照

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectedItemDragState.swift
// 函数: CanvasSelectedItemDragState / proposedCenter(for:)
// 说明: 旧状态只记录一个 item 的起点世界坐标和起点中心点，无法为组选框保存成员几何快照。
struct CanvasSelectedItemDragState: Equatable {
    let itemID: CanvasItemID
    let dragStartWorldLocation: CGPoint
    let dragStartCenter: CGPoint
    var alignmentLock: CanvasAlignmentLockState

    func proposedCenter(
        for currentWorldLocation: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: dragStartCenter.x + (currentWorldLocation.x - dragStartWorldLocation.x),
            y: dragStartCenter.y + (currentWorldLocation.y - dragStartWorldLocation.y)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handlePrimaryPointerMove(to:from:)
// 说明: 旧 group handle 分支直接退出，组选框命中后不会进入任何真实的平移 / 缩放 / 旋转链路。
switch pressContext.targetKind {
case .groupRotateHandle:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .groupSelectionHandle:
    editorSession.cancelPendingHistoryTransaction()
    pointerDragState = .idle
case .selectedItemBody:
    guard let dragState = makeSelectedItemDragState(
        itemID: itemID,
        initialViewportLocation: pressedLocation
    ) else {
        pointerDragState = .idle
        return
    }
    ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数: CanvasSelectionTransformSnapshot / translatedMemberGeometries(by:) / resizedMemberGeometries(handleRole:draggedWorldCorner:minimumScale:) / rotatedMemberGeometries(by:)
// 说明: 新增共享几何快照，统一保存 primary item、成员几何、组选框 bounds，并把组平移 / 组缩放 / 组旋转的数学收口到同一层。
struct CanvasSelectionTransformSnapshot: Equatable {
    let primaryItemID: CanvasItemID
    let memberGeometries: [CanvasBoardItemGeometry]
    let selectionBounds: CGRect

    init?(
        scene: CanvasScene,
        interactionState: CanvasInteractionState
    ) {
        let memberItems = interactionState.selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }
        guard
            memberItems.isEmpty == false,
            let primaryItemID = interactionState.primarySelectedItemID
        else {
            return nil
        }

        self.init(
            primaryItemID: primaryItemID,
            memberGeometries: memberItems.map(CanvasBoardItemGeometry.init(item:)),
            selectionBounds: Self.selectionBounds(
                for: memberItems.map(CanvasBoardItemGeometry.init(item:))
            )
        )
    }

    func translatedMemberGeometries(
        by translation: CGPoint
    ) -> [CanvasBoardItemGeometry] {
        memberGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: CGPoint(
                    x: geometry.center.x + translation.x,
                    y: geometry.center.y + translation.y
                ),
                size: geometry.size,
                rotationRadians: geometry.rotationRadians
            )
        }
    }

    func resizedMemberGeometries(
        handleRole: CanvasSelectionHandleRole,
        draggedWorldCorner: CGPoint,
        minimumScale: CGFloat
    ) -> [CanvasBoardItemGeometry]? {
        ...
    }

    func rotatedMemberGeometries(
        by rotationDeltaRadians: CGFloat
    ) -> [CanvasBoardItemGeometry] {
        memberGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: canvasRotatePoint(
                    geometry.center,
                    around: selectionCenter,
                    by: rotationDeltaRadians
                ),
                size: geometry.size,
                rotationRadians: geometry.rotationRadians + rotationDeltaRadians
            )
        }
    }
}

struct CanvasSelectionDragState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let dragStartWorldLocation: CGPoint
    var alignmentLock: CanvasAlignmentLockState
}

struct CanvasSelectionResizeState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let handleRole: CanvasSelectionHandleRole
    let minimumScale: CGFloat
}

struct CanvasSelectionRotateState: Equatable {
    let snapshot: CanvasSelectionTransformSnapshot
    let rotationOffsetToPointerAngle: CGFloat
}
```

这一层的意义是：controller 不再自己分别维护三套 group move / resize / rotate 的初始态，phase4 之后三种组选变换都复用同一个 `CanvasSelectionTransformSnapshot`。

## 2. `CanvasScene` 新增批量几何写入入口，防止 controller 逐项散写

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数: moveItem(withID:by:) / resizeBoardItem(withID:toCenter:size:) / rotateBoardItem(withID:to:)
// 说明: 旧 Scene 只有单对象入口；如果 controller 想做组变换，只能自己循环逐项改写，无法保证每个 tick 用同一份共享几何快照提交。
func moveItem(withID id: CanvasImageItemID, by deltaInWorld: CGPoint) {
    guard deltaInWorld != .zero else {
        return
    }

    updateBoardItem(withID: id) { item in
        item.center.x += deltaInWorld.x
        item.center.y += deltaInWorld.y
    }
}

@discardableResult
func resizeBoardItem(
    withID id: CanvasItemID,
    toCenter center: CGPoint,
    size: CGSize
) -> CanvasBoardItem? {
    ...
}

@discardableResult
func rotateBoardItem(
    withID id: CanvasItemID,
    to rotationRadians: CGFloat
) -> CanvasBoardItem? {
    ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数: applyBoardItemGeometries(_:)
// 说明: Scene 新增批量写入 API，对几何去重、尺寸合法性、item 存在性做统一校验，再一次性提交成员更新后的结果。
@discardableResult
func applyBoardItemGeometries(
    _ geometries: [CanvasBoardItemGeometry]
) -> [CanvasBoardItem]? {
    guard geometries.isEmpty == false else {
        return []
    }

    var geometryByItemID: [CanvasItemID: CanvasBoardItemGeometry] = [:]
    for geometry in geometries {
        guard
            geometry.size.width > 0,
            geometry.size.height > 0,
            geometryByItemID[geometry.itemID] == nil
        else {
            return nil
        }
        geometryByItemID[geometry.itemID] = geometry
    }

    for geometry in geometries {
        guard items.contains(where: { $0.id == geometry.itemID }) else {
            return nil
        }
    }

    var updatedItems = items
    var updatedBoardItems: [CanvasBoardItem] = []
    for geometry in geometries {
        guard
            let index = updatedItems.firstIndex(where: { $0.id == geometry.itemID }),
            let updatedItem = updatedItems[index].applyingGeometry(geometry)
        else {
            return nil
        }

        updatedItems[index] = updatedItem
        updatedBoardItems.append(updatedItem)
    }

    items = updatedItems
    return updatedBoardItems
}
```

这里对应了计划里“不要让 controller 自己逐项散写”的要求：组平移、组缩放、组旋转都统一落到 `Scene`。

## 3. 对齐 solver 从“移动一个 item”升级为“移动一个 selection bounds”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数: CanvasAlignmentSolveRequest / solve(_:) / alignmentReferences(in:boardState:searchRect:excluding:)
// 说明: 旧 solver 只知道 movingItemID + proposedCenter，并且只能排除一个 item，自然无法按组选框做吸附。
struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let lockState: CanvasAlignmentLockState
}

func solve(
    _ request: CanvasAlignmentSolveRequest
) -> CanvasAlignmentSolveResult {
    guard let movingItem = request.scene.boardItem(withID: request.movingItemID) else {
        return CanvasAlignmentSolveResult.passthrough(
            proposedCenter: request.proposedCenter,
            lockState: .none
        )
    }

    let proposedFrame = worldFrame(
        size: movingItem.size,
        centeredAt: request.proposedCenter
    )
    let references = alignmentReferences(
        in: request.scene,
        boardState: request.boardState,
        searchRect: searchRect,
        excluding: request.movingItemID
    )
    ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数: CanvasAlignmentSolveRequest / CanvasAlignmentSolveResult / solve(_:)
// 说明: 新请求模型携带 primaryMovingItemID、movingItemIDs、movingBounds；solver 以组选框 bounds 为参考求解，并排除整组选中成员。
struct CanvasAlignmentSolveRequest {
    let primaryMovingItemID: CanvasItemID
    let movingItemIDs: [CanvasItemID]
    let movingBounds: CGRect
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let lockState: CanvasAlignmentLockState

    var excludedItemIDs: Set<CanvasItemID> {
        Set(movingItemIDs)
    }
}

struct CanvasAlignmentSolveResult {
    let resolvedBounds: CGRect
    let interactionState: CanvasAlignmentInteractionState?
    let lockState: CanvasAlignmentLockState

    var resolvedCenter: CGPoint {
        CGPoint(
            x: resolvedBounds.midX,
            y: resolvedBounds.midY
        )
    }
}

func solve(
    _ request: CanvasAlignmentSolveRequest
) -> CanvasAlignmentSolveResult {
    guard let movingItem = request.scene.boardItem(withID: request.primaryMovingItemID) else {
        return CanvasAlignmentSolveResult.passthrough(
            proposedBounds: request.movingBounds,
            lockState: .none
        )
    }

    let proposedFrame = request.movingBounds
    let references = alignmentReferences(
        in: request.scene,
        boardState: request.boardState,
        searchRect: searchRect,
        excluding: request.excludedItemIDs
    )
    ...
    let resolvedFrame = proposedFrame.offsetBy(
        dx: xCandidate?.deltaInWorld ?? 0,
        dy: yCandidate?.deltaInWorld ?? 0
    ).standardized
    let interactionState = CanvasAlignmentInteractionState(
        primaryItemID: request.primaryMovingItemID,
        memberItemIDs: request.movingItemIDs,
        guides: guides,
        xMatch: xCandidate?.match,
        yMatch: yCandidate?.match
    )
    return CanvasAlignmentSolveResult(
        resolvedBounds: resolvedFrame,
        interactionState: interactionState.isActive ? interactionState : nil,
        lockState: lockState
    )
}
```

phase4 的对齐线不再围绕单个成员，而是围绕整个组选框；同时 `interactionState` 也升级成了可携带 member IDs 的 group 语义。

## 4. transient rotation / alignment / preview 状态升级为 group 语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数: CanvasRotationPreviewState / CanvasRotationInteractionState / CanvasAlignmentInteractionState
// 说明: 旧 transient state 只有一个 itemID，renderer 也因此把 HUD 绑定死在单选对象上。
struct CanvasRotationPreviewState {
    let itemID: CanvasItemID
    var draftRotationRadians: CGFloat
}

struct CanvasRotationInteractionState {
    let itemID: CanvasItemID
}

struct CanvasAlignmentInteractionState: Equatable {
    let itemID: CanvasItemID
    let guides: [CanvasAlignmentGuide]
    let xMatch: CanvasAlignmentMatch?
    let yMatch: CanvasAlignmentMatch?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeRotationInteractionOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:rotationInteractionState:)
// 说明: 旧 renderer 明确要求 singleSelectedItemID == rotationInteractionState.itemID，只能渲染单对象旋转 HUD。
guard
    let rotationInteractionState,
    interactionState.singleSelectedItemID == rotationInteractionState.itemID,
    let item = scene.boardItem(withID: rotationInteractionState.itemID)
else {
    return nil
}

let effectiveItem = effectiveBoardItem(
    from: item,
    rotationPreviewState: rotationPreviewState
)
let screenQuad = camera.worldToViewport(effectiveItem.worldQuad)
let screenCenter = camera.worldToViewport(effectiveItem.center)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数: CanvasRotationPreviewState / CanvasRotationInteractionState / CanvasAlignmentInteractionState
// 说明: 新 transient state 同时保存 primary item、memberItemIDs、draftGeometries；这样 renderer 才能同时预览多个成员的旋转后几何。
struct CanvasRotationPreviewState {
    let primaryItemID: CanvasItemID
    let memberItemIDs: [CanvasItemID]
    let draftGeometries: [CanvasBoardItemGeometry]
    let displayRotationRadians: CGFloat

    init(
        snapshot: CanvasSelectionTransformSnapshot,
        draftGeometries: [CanvasBoardItemGeometry],
        displayRotationRadians: CGFloat
    ) {
        self.primaryItemID = snapshot.primaryItemID
        self.memberItemIDs = snapshot.memberItemIDs
        self.draftGeometries = draftGeometries
        self.displayRotationRadians = displayRotationRadians
    }

    func geometry(
        for itemID: CanvasItemID
    ) -> CanvasBoardItemGeometry? {
        draftGeometries.first(where: { $0.itemID == itemID })
    }
}

struct CanvasRotationInteractionState {
    let primaryItemID: CanvasItemID
    let memberItemIDs: [CanvasItemID]
}

struct CanvasAlignmentInteractionState: Equatable {
    let primaryItemID: CanvasItemID
    let memberItemIDs: [CanvasItemID]
    let guides: [CanvasAlignmentGuide]
    let xMatch: CanvasAlignmentMatch?
    let yMatch: CanvasAlignmentMatch?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数: resolve(item:inlineEditState:rotationPreviewState:)
// 说明: 旧逻辑只覆写 rotation；现在 rotation preview 会同时覆写 center / size / rotation，保证组选框旋转预览时成员渲染与 overlay 一致。
let previewGeometry = rotationPreviewState?.geometry(for: item.id)
let isRotationPreviewActive = previewGeometry != nil

var effectiveItem = item
if let previewGeometry {
    effectiveItem.center = previewGeometry.center
    effectiveItem.size = previewGeometry.size
    effectiveItem.rotationRadians = previewGeometry.rotationRadians
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeRotationInteractionOverlay(...) / makeAlignmentInteractionOverlay(...) / effectiveBoardItem(from:rotationPreviewState:)
// 说明: renderer 现在按 transient memberItemIDs 校验选择集；多选时改用 groupSelectionWorldBounds 计算 HUD 中心与 ring，单选时仍保留旧路径。
guard
    let rotationInteractionState,
    interactionStateMatchesTransientSelection(
        selectedItemIDs: interactionState.selectedItemIDs,
        transientItemIDs: rotationInteractionState.memberItemIDs
    )
else {
    return nil
}

let effectiveItems = rotationInteractionState.memberItemIDs.compactMap { itemID in
    scene.boardItem(withID: itemID)
}.map { item in
    effectiveBoardItem(
        from: item,
        rotationPreviewState: rotationPreviewState
    )
}

if effectiveItems.count == 1, let effectiveItem = effectiveItems.first {
    screenQuad = camera.worldToViewport(effectiveItem.worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
    currentRotationRadians = normalizedCanvasAngle(
        effectiveItem.rotationRadians
    )
    overlayItemID = effectiveItem.id
} else {
    let interactionBounds = groupSelectionWorldBounds(for: effectiveItems)
    screenQuad = camera.worldToViewport(
        CanvasQuad(rect: interactionBounds)
    )
    screenCenter = camera.worldToViewport(
        CGPoint(
            x: interactionBounds.midX,
            y: interactionBounds.midY
        )
    )
    currentRotationRadians = normalizedCanvasAngle(
        rotationPreviewState?.displayRotationRadians ?? 0
    )
    overlayItemID = rotationInteractionState.primaryItemID
}
```

## 5. iOS / macOS controller 正式接入组选框拖移、缩放、旋转与单事务 history

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: PointerDragState / handlePrimaryPointerMove(to:from:)
// 说明: 旧状态机只有单对象 draggingSelectedItem / resizingSelectedItem / rotatingSelectedItem，没有 selection 级状态。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: beginPointerHistoryTransactionIfNeeded(for:)
// 说明: 旧 macOS history 入口对 groupRotateHandle / groupSelectionHandle 直接 return，因此组选框手势就算后面补上也无法自然形成单条事务。
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

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: PointerDragState / handlePrimaryPointerMove(to:from:)
// 说明: iOS 状态机新增 rotatingSelection / draggingSelection / resizingSelection；group handle 与多选成员 body 都会进入新的 selection 级变换链路。
private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressContext: CanvasPointerPressContext,
        pointerModifiers: CanvasPointerModifiers
    )
    case croppingSelectedItem(PointerCropState)
    case movingCropFrame(PointerCropTranslationState)
    case rotatingSelectedItem(PointerRotateState)
    case rotatingSelection(CanvasSelectionRotateState)
    case draggingSelectedItem(CanvasSelectedItemDragState)
    case draggingSelection(CanvasSelectionDragState)
    case resizingSelectedItem(PointerResizeState)
    case resizingSelection(CanvasSelectionResizeState)
    case draggingCanvas
}

switch pressContext.targetKind {
case .groupRotateHandle:
    guard let rotateState = makeSelectionRotateState(
        initialViewportLocation: pressedLocation
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .rotatingSelection(rotateState)
    beginRotationInteraction(for: rotateState.snapshot)
    updateSelectionRotationDraft(using: rotateState, to: location)
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(
        handleRole: handleRole
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectedItemBody:
    if interactionState.selectionCount > 1 {
        guard let dragState = makeSelectionDragState(
            initialViewportLocation: pressedLocation
        ) else {
            pointerDragState = .idle
            return
        }

        guard let updatedDragState = moveSelection(
            using: dragState,
            to: location
        ) else {
            pointerDragState = .idle
            return
        }

        pointerDragState = .draggingSelection(updatedDragState)
    } else {
        ...
    }
default:
    ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: moveSelection(using:to:) / resizeSelection(using:to:) / commitRotationDraftIfNeeded()
// 说明: 组三类变换都从 selection snapshot 出发，使用 Scene 批量写入和对齐 solver resolvedBounds；提交 history 时按 selection 维度落一条事务。
private func moveSelection(
    using dragState: CanvasSelectionDragState,
    to location: CGPoint
) -> CanvasSelectionDragState? {
    let proposedBounds = dragState.proposedBounds(
        for: camera.viewportToWorld(location)
    )
    let solveResult = alignmentGuideSolver.solve(
        CanvasAlignmentSolveRequest(
            primaryMovingItemID: dragState.snapshot.primaryItemID,
            movingItemIDs: dragState.snapshot.memberItemIDs,
            movingBounds: proposedBounds,
            scene: scene,
            boardState: boardState,
            camera: camera,
            lockState: dragState.alignmentLock
        )
    )
    let resolvedTranslation = CGPoint(
        x: solveResult.resolvedBounds.midX - dragState.snapshot.selectionBounds.midX,
        y: solveResult.resolvedBounds.midY - dragState.snapshot.selectionBounds.midY
    )
    let movedItems = scene.applyBoardItemGeometries(
        dragState.snapshot.translatedMemberGeometries(by: resolvedTranslation)
    )
    ...
}

private func resizeSelection(
    using resizeState: CanvasSelectionResizeState,
    to viewportLocation: CGPoint
) {
    let resizedGeometries = resizeState.resizedMemberGeometries(
        for: camera.viewportToWorld(viewportLocation)
    )
    let resizedItems = scene.applyBoardItemGeometries(resizedGeometries)
    ...
}

private func commitRotationDraftIfNeeded() {
    let needsCommit = rotationPreviewState.draftGeometries.contains { geometry in
        ...
    }
    let rotatedItems = scene.applyBoardItemGeometries(
        rotationPreviewState.draftGeometries
    )
    commitPendingPointerHistoryTransaction(
        autosaveReason: rotationPreviewState.memberItemIDs.count > 1
            ? "rotate selection"
            : "rotate item"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handlePrimaryPointerMove(to:from:) / beginPointerHistoryTransactionIfNeeded(for:)
// 说明: macOS 做了与 iOS 对称的组变换接线，并把 group history reason 改成 rotate selection / resize selection / move selection。
switch pressContext.targetKind {
case .groupRotateHandle:
    guard let rotateState = makeSelectionRotateState(
        initialViewportLocation: pressedLocation
    ) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
    pointerDragState = .rotatingSelection(rotateState)
    beginRotationInteraction(for: rotateState.snapshot)
    updateSelectionRotationDraft(using: rotateState, to: location)
case let .groupSelectionHandle(handleRole):
    guard let resizeState = makeSelectionResizeState(handleRole: handleRole) else {
        editorSession.cancelPendingHistoryTransaction()
        pointerDragState = .idle
        return
    }
    pointerDragState = .resizingSelection(resizeState)
    resizeSelection(using: resizeState, to: location)
case .selectedItemBody:
    if interactionState.selectionCount > 1 {
        ...
    } else {
        ...
    }
default:
    ...
}

switch pressContext.targetKind {
case .rotateHandle:
    reason = "rotate item"
case .groupRotateHandle:
    reason = "rotate selection"
case .selectionHandle:
    reason = "resize item"
case .groupSelectionHandle:
    reason = "resize selection"
case .selectedItemBody:
    reason = interactionState.selectionCount > 1
        ? "move selection"
        : "move item"
case .unselectedItemBody, .blank:
    return
}
```

这一段落实后，iOS 和 macOS 两端的组选框拖移、组选框缩放、组选框旋转都走上了同一套共享几何 / solver / history 语义。

## 6. 新增 / 补强测试，覆盖 group transform 与 group overlay

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数: testSolveCanSnapAgainstBoardReference()
// 说明: 旧 solver 测试只有 movingItemID + proposedCenter 的单对象路径，没有“selection bounds + excluded IDs”的断言。
let result = solver.solve(
    CanvasAlignmentSolveRequest(
        movingItemID: movingItem.id,
        proposedCenter: CGPoint(x: -182, y: 0),
        scene: scene,
        boardState: boardState,
        camera: makeAlignmentTestCamera()
    )
)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数: testTranslatedMemberGeometriesApplySharedWorldDelta() / testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner() / testRotatedMemberGeometriesRotateCentersAndItemAnglesAroundSelectionCenter()
// 说明: 新增纯几何测试，直接验证组平移、组缩放、组旋转的数学结果，而不是只靠 controller 级联测试间接覆盖。
final class CanvasSelectionTransformStateTests: XCTestCase {
    func testTranslatedMemberGeometriesApplySharedWorldDelta() throws {
        ...
        XCTAssertEqual(firstGeometry.center, CGPoint(x: 25, y: 12))
        XCTAssertEqual(secondGeometry.center, CGPoint(x: 85, y: 42))
    }

    func testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner() throws {
        ...
        XCTAssertEqual(firstGeometry.size, CGSize(width: 30, height: 30))
        XCTAssertEqual(secondGeometry.size, CGSize(width: 60, height: 30))
    }

    func testRotatedMemberGeometriesRotateCentersAndItemAnglesAroundSelectionCenter() throws {
        ...
        XCTAssertEqual(firstGeometry.rotationRadians, .pi / 2, accuracy: 0.0001)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests.swift
// 函数: testSolveSupportsGroupSelectionBoundsAndSelectionExclusions()
// 说明: 新增组对齐测试，验证 solver 会用 movingBounds 代表组选框，并排除 selection 成员自身，避免成员和成员之间相互打架。
func testSolveSupportsGroupSelectionBoundsAndSelectionExclusions() {
    ...
    let result = solver.solve(
        CanvasAlignmentSolveRequest(
            primaryMovingItemID: secondMovingItem.id,
            movingItemIDs: [firstMovingItem.id, secondMovingItem.id],
            movingBounds: CGRect(
                x: 154,
                y: -20,
                width: 100,
                height: 40
            ),
            scene: scene,
            boardState: nil,
            camera: makeAlignmentTestCamera()
        )
    )

    XCTAssertEqual(result.resolvedBounds.midX, 200)
    XCTAssertEqual(result.interactionState?.itemID, secondMovingItem.id)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数: testMakeCanvasSnapshotProducesAlignmentOverlayForGroupSelection() / testMakeCanvasSnapshotAppliesGroupRotationPreviewToOverlayBounds()
// 说明: 新增 renderer / snapshot 侧测试，确保 group alignment overlay 与 group rotation preview 都会正确出现在 transient snapshot 中。
func testMakeCanvasSnapshotProducesAlignmentOverlayForGroupSelection() throws {
    ...
    session.alignmentInteractionState = CanvasAlignmentInteractionState(
        primaryItemID: secondItem.id,
        memberItemIDs: [firstItem.id, secondItem.id],
        guides: [...],
        xMatch: ...,
        yMatch: nil
    )
    ...
    XCTAssertEqual(interactionOverlay.itemID, secondItem.id)
    XCTAssertTrue(payload.isActive)
}

func testMakeCanvasSnapshotAppliesGroupRotationPreviewToOverlayBounds() throws {
    ...
    session.rotationPreviewState = CanvasRotationPreviewState(
        snapshot: transformSnapshot,
        draftGeometries: rotatedGeometries,
        displayRotationRadians: .pi / 2
    )
    ...
    XCTAssertEqual(payload.currentRotationRadians, .pi / 2, accuracy: 0.0001)
}
```

## 7. 验证结果

```bash
# 路径: 工作区根目录
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests
# 说明: 正常 test 流程可以完成本轮代码编译，但依然会撞上项目里已有的 macOS ValidateEmbeddedBinary 问题；这不是 phase4 新引入的问题
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
Testing failed:
    Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
    Testing cancelled because the build failed.
```

```bash
# 路径: 工作区根目录
# 命令: xcodebuild test-without-building -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests
# 说明: 使用 test-without-building 绕过上面的工程级校验后，本轮相关定向测试全部通过
** TEST EXECUTE SUCCEEDED **

Test suite 'CanvasAlignmentGuideSolverTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasAlignmentGuideSolverTests.testSolveSupportsGroupSelectionBoundsAndSelectionExclusions()' passed

Test suite 'CanvasEditorSessionAlignmentOverlayTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasEditorSessionAlignmentOverlayTests.testMakeCanvasSnapshotProducesAlignmentOverlayForGroupSelection()' passed
Test case 'CanvasEditorSessionAlignmentOverlayTests.testMakeCanvasSnapshotAppliesGroupRotationPreviewToOverlayBounds()' passed

Test suite 'CanvasSelectionTransformStateTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'CanvasSelectionTransformStateTests.testTranslatedMemberGeometriesApplySharedWorldDelta()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner()' passed
Test case 'CanvasSelectionTransformStateTests.testRotatedMemberGeometriesRotateCentersAndItemAnglesAroundSelectionCenter()' passed
```

补充检查：

- `ReadLints` 已检查本轮改动文件，未发现新的 linter 错误。
- 本记录未创建 git commit。

## 8. 本轮 phase4 实际落地点汇总

- 新增 `CanvasSelectionTransformState.swift`，把组选框的 geometry snapshot、group move、group resize、group rotate 全部收口为共享 helper。
- `CanvasScene` 新增 `applyBoardItemGeometries(_:)`，保证组选几何提交是一次性批量写入，而不是 controller 自己散写。
- `CanvasAlignmentGuideSolver` 升级到 `movingBounds + movingItemIDs + excludedItemIDs` 语义，组拖移时按组选框吸附。
- `CanvasInlineEditState`、`CanvasImagePresentationResolver`、`CanvasRenderer` 升级到 group transient state，组选旋转和组对齐 overlay 能稳定出现在 snapshot 中。
- `iOSViewController` 与 `macOSViewController` 对称接入组选框拖移、缩放、旋转和 selection 级 history reason。
- 新增 / 更新测试，覆盖共享几何、group solver、group overlay 三个层面。
