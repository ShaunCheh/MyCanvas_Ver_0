# 20260518_204920_CST_hand_drawing_multilayer_phase3_engine_history_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 3：`Engine 状态、历史栈与图层命令`。
  2. 在 `HandDrawingDocument` 补齐 layer 级原子操作，给 engine 提供稳定的底层变更入口。
  3. 在 `HandDrawingEditorEngine` / `HandDrawingHistoryController` 中接入 `HandDrawingLayerCommand`、当前层历史语义、切层清选区约束。
  4. 在 `HandDrawingEditorCoordinator` 新增 layer 命令入口，统一在切层/图层操作前结束 transient interaction 并强制刷新 committed image。
  5. 补阶段 3 的 editor engine 回归测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_204920_CST`
- 说明：
  - 本记录只覆盖刚刚实施的多 layer 阶段 3，不包含阶段 4 之后“工具只作用当前 layer”的收敛、iPad layer UI 和宿主兼容收口。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M .cursor/plans/手绘多图层_1e238dea.plan.md`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - `.cursor/plans/手绘多图层_1e238dea.plan.md`
    - 当前工作区里该文件处于修改状态，但不属于本轮阶段 3 代码实现本身的记录对象
  - 阶段 4 的 brush / pixel eraser / lasso / move 仅作用当前 layer
  - 阶段 5 的 iPad layer 面板与交互 UI
  - git commit / push

## 修改一：`HandDrawingDocument` 补齐 layer 级原子操作与“至少保留 1 层”兜底

### 修改前

- `HandDrawingDocument` 在阶段 1 只有这些和 layer 直接相关的入口：
  - `setActiveLayer(withID:)`
  - `ensureActiveLayerExists()`
  - `replaceStrokesInActiveLayer(with:)`
- 这意味着 engine 想做“新增层 / 删层 / 重命名 / 重排 / 显隐 / 锁定”时，还没有一套正式的文档层原子操作可以复用。
- “至少保留 1 个 layer”“删除当前层后自动切到相邻 layer”这样的不变量，也还没有真正落在文档层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.setActiveLayer(withID:) / ensureActiveLayerExists() / replaceStrokesInActiveLayer(with:)
// 功能注释: 修改前文档层只有 active layer 维护入口，没有完整的 layer 级变更原语。
@discardableResult
mutating func setActiveLayer(withID layerID: UUID) -> Bool {
    guard layers.contains(where: { $0.id == layerID }) else {
        return false
    }
    activeLayerID = layerID
    return true
}

@discardableResult
mutating func ensureActiveLayerExists() -> UUID {
    if let activeLayerIndex {
        return layers[activeLayerIndex].id
    }
    if layers.isEmpty {
        let defaultLayer = Self.makeDefaultLayer(at: 1)
        layers = [defaultLayer]
        activeLayerID = defaultLayer.id
        return defaultLayer.id
    }
    activeLayerID = layers[0].id
    return activeLayerID
}

mutating func replaceStrokesInActiveLayer(with strokes: [HandDrawingStroke]) {
    ensureActiveLayerExists()
    layers[activeLayerIndex ?? 0].strokes = strokes
}
```

### 修改后

- 文档层新增了完整的 layer 原子操作：
  - `insertLayer(named:afterLayerID:)`
  - `removeLayer(withID:)`
  - `renameLayer(withID:to:)`
  - `moveLayer(withID:toIndex:)`
  - `setLayerVisibility(withID:isVisible:)`
  - `setLayerLock(withID:isLocked:)`
- 新约束也一起落下：
  - 删除最后一层会失败，文档层直接拒绝
  - 删除当前层后会自动切到相邻 layer
  - 新建层默认成为当前层
  - 空名称会自动走 `Layer N` 命名规则，并通过 `resolvedLayerName(...)` 避免默认名冲突

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.insertLayer(named:afterLayerID:) / removeLayer(withID:) / renameLayer(withID:to:) / moveLayer(withID:toIndex:) / setLayerVisibility(withID:isVisible:) / setLayerLock(withID:isLocked:)
// 功能注释: 修改后文档层正式提供 layer 级原子操作，并把“至少保留 1 层”“删除当前层后切相邻层”收口在模型内部。
@discardableResult
mutating func insertLayer(
    named proposedName: String? = nil,
    afterLayerID anchorLayerID: UUID? = nil
) -> HandDrawingLayer {
    ensureActiveLayerExists()
    let resolvedAnchorLayerID = anchorLayerID ?? activeLayerID
    let insertionIndex: Int
    if let anchorIndex = layers.firstIndex(where: { $0.id == resolvedAnchorLayerID }) {
        insertionIndex = min(anchorIndex + 1, layers.count)
    } else {
        insertionIndex = layers.count
    }
    let layer = HandDrawingLayer(
        name: Self.resolvedLayerName(
            proposedName,
            fallbackIndex: insertionIndex + 1,
            existingLayers: layers
        )
    )
    layers.insert(layer, at: insertionIndex)
    activeLayerID = layer.id
    return layer
}

@discardableResult
mutating func removeLayer(withID layerID: UUID) -> HandDrawingLayer? {
    guard
        layers.count > 1,
        let removedIndex = layers.firstIndex(where: { $0.id == layerID })
    else {
        return nil
    }
    let removedLayer = layers.remove(at: removedIndex)
    if activeLayerID == layerID {
        let fallbackIndex = min(removedIndex, layers.count - 1)
        activeLayerID = layers[fallbackIndex].id
    } else {
        _ = ensureActiveLayerExists()
    }
    return removedLayer
}

@discardableResult
mutating func setLayerVisibility(
    withID layerID: UUID,
    isVisible: Bool
) -> Bool {
    updateLayer(withID: layerID) { layer in
        layer.isVisible = isVisible
    }
}

@discardableResult
mutating func setLayerLock(
    withID layerID: UUID,
    isLocked: Bool
) -> Bool {
    updateLayer(withID: layerID) { layer in
        layer.isLocked = isLocked
    }
}

private static func resolvedLayerName(
    _ proposedName: String?,
    fallbackIndex: Int,
    existingLayers: [HandDrawingLayer],
    excludingLayerID: UUID? = nil
) -> String {
    let trimmedName = (proposedName ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedName.isEmpty else {
        return trimmedName
    }
    // ... 默认层命名冲突规避逻辑 ...
}
```

## 修改二：`HandDrawingEditorEngine` / `HandDrawingHistoryController` 把 layer 状态正式纳入统一历史语义

### 修改前

- `HandDrawingEditorCommand` 只有 `.deselectAll`。
- `HandDrawingEditorState` 只有 `document + selectedStrokeIDs`，没有明确暴露当前层状态。
- `HandDrawingHistorySnapshot` 也只是简单保存 `document + selectedStrokeIDs`，没有显式的 `activeLayerID` 语义入口。
- engine 还没有一个统一的“文档变更 + 选区修正 + dirty region 标记 + undo snapshot”管道来承接 layer 操作。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: HandDrawingEditorCommand / HandDrawingEditorState.init(document:selectedStrokeIDs:) / HandDrawingEditorEngine.apply(command:recordUndo:)
// 功能注释: 修改前 engine 只支持 deselectAll，尚未有 layer 命令和当前层历史语义。
enum HandDrawingEditorCommand: Equatable {
    case deselectAll
}

struct HandDrawingEditorState: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs
    }
}

@discardableResult
mutating func apply(
    command: HandDrawingEditorCommand,
    recordUndo: Bool = true
) -> Bool {
    switch command {
    case .deselectAll:
        return selectStrokes(
            withIDs: [],
            recordUndo: recordUndo
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift
// 函数名: HandDrawingHistorySnapshot
// 功能注释: 修改前历史快照没有显式暴露 activeLayerID，也没有在快照层修正选区与 active layer 的一致性。
struct HandDrawingHistorySnapshot: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>
}
```

### 修改后

- 新增 `HandDrawingLayerCommand`，并接入 `HandDrawingEditorCommand.layer(...)`。
- `HandDrawingEditorState` 现在显式暴露 `activeLayerID`，并且在初始化时把 `selectedStrokeIDs` 约束在当前 active layer 的 `document.strokes` 范围内。
- `HandDrawingHistorySnapshot` 新增了：
  - 自定义 `init(document:selectedStrokeIDs:)`
  - `activeLayerID` 只读入口
  - 选区修正逻辑，保证恢复快照时不会拿到跨层脏选区
- `HandDrawingEditorEngine` 新增 `apply(layerCommand:recordUndo:)` 和 `applyDocumentMutation(recordUndo:mutation:)`：
  - 所有 layer 操作统一走一条文档变更管道
  - 切层时清空选区
  - 同层属性变更时保留当前层内仍然合法的选区
  - 统一标记 `paperBounds` 为 dirty，保证 committed image 能完整恢复

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: HandDrawingLayerCommand / HandDrawingEditorCommand / HandDrawingEditorState.activeLayerID / HandDrawingEditorEngine.apply(layerCommand:recordUndo:) / applyDocumentMutation(recordUndo:mutation:)
// 功能注释: 修改后 engine 把 layer 命令、当前层状态和统一历史语义全部接入同一条变更管道。
enum HandDrawingLayerCommand: Equatable {
    case addLayer(name: String?)
    case deleteLayer(id: UUID)
    case renameLayer(id: UUID, name: String)
    case moveLayer(id: UUID, toIndex: Int)
    case setVisibility(id: UUID, isVisible: Bool)
    case setLocked(id: UUID, isLocked: Bool)
    case setActive(id: UUID)
}

enum HandDrawingEditorCommand: Equatable {
    case deselectAll
    case layer(HandDrawingLayerCommand)
}

struct HandDrawingEditorState: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs.intersection(
            Set(document.strokes.map(\.id))
        )
    }

    var activeLayerID: UUID {
        document.activeLayerID
    }
}

@discardableResult
mutating func apply(
    layerCommand: HandDrawingLayerCommand,
    recordUndo: Bool = true
) -> Bool {
    applyDocumentMutation(recordUndo: recordUndo) { document in
        switch layerCommand {
        case let .addLayer(name):
            _ = document.insertLayer(named: name)
        case let .deleteLayer(id):
            _ = document.removeLayer(withID: id)
        case let .renameLayer(id, name):
            _ = document.renameLayer(withID: id, to: name)
        case let .moveLayer(id, toIndex):
            _ = document.moveLayer(withID: id, toIndex: toIndex)
        case let .setVisibility(id, isVisible):
            _ = document.setLayerVisibility(withID: id, isVisible: isVisible)
        case let .setLocked(id, isLocked):
            _ = document.setLayerLock(withID: id, isLocked: isLocked)
        case let .setActive(id):
            _ = document.setActiveLayer(withID: id)
        }
    }
}

@discardableResult
private mutating func applyDocumentMutation(
    recordUndo: Bool,
    mutation: (inout HandDrawingDocument) -> Void
) -> Bool {
    let originalDocument = state.document
    let originalSelection = state.selectedStrokeIDs
    var updatedDocument = originalDocument
    mutation(&updatedDocument)
    guard updatedDocument != originalDocument else {
        return false
    }
    if recordUndo {
        recordSnapshotForUndo()
    }
    state.document = updatedDocument
    if updatedDocument.activeLayerID != originalDocument.activeLayerID {
        state.selectedStrokeIDs = []
    } else {
        state.selectedStrokeIDs = sanitizedSelection(
            originalSelection,
            in: updatedDocument
        )
    }
    dirtyRegionTracker.markDirty(updatedDocument.paperBounds)
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift
// 函数名: HandDrawingHistorySnapshot.init(document:selectedStrokeIDs:) / HandDrawingHistorySnapshot.activeLayerID
// 功能注释: 修改后 history snapshot 显式保存当前层语义，并在快照层修正选区与当前层的一致性。
struct HandDrawingHistorySnapshot: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>

    init(
        document: HandDrawingDocument,
        selectedStrokeIDs: Set<UUID> = []
    ) {
        self.document = document
        self.selectedStrokeIDs = selectedStrokeIDs.intersection(
            Set(document.strokes.map(\.id))
        )
    }

    var activeLayerID: UUID {
        document.activeLayerID
    }
}
```

## 修改三：`HandDrawingEditorCoordinator` 新增正式 layer 命令入口

### 修改前

- coordinator 里已经有 `undo()` / `redo()`，也会在这两个入口前调用 `endTransientInteractionState()`。
- 但还没有一条正式的 layer 命令入口，所以阶段 3 计划里的“切换当前层时先结束 transient interaction”还只是 engine 能承接，coordinator 没有对应的调用点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.undo() / redo()
// 功能注释: 修改前 coordinator 只对 undo/redo 做 transient interaction 收口，没有 layer 命令入口。
func undo() {
    endTransientInteractionState()
    guard engine.undo() else {
        return
    }
    refreshCommittedImageAndPublishState(forceFullRender: true)
}

func redo() {
    endTransientInteractionState()
    guard engine.redo() else {
        return
    }
    refreshCommittedImageAndPublishState(forceFullRender: true)
}
```

### 修改后

- 新增 `applyLayerCommand(_:)`。
- 入口行为统一为：
  - 先 `endTransientInteractionState()`
  - 再执行 `engine.apply(layerCommand:)`
  - 成功后强制全量刷新 committed image
  - 如果命令无效，则只重新发布 surface / palette 状态
- 这样阶段 5 接 UI 时，不需要再分散补“切层前清草稿/结束拖动/结束橡皮”的热修。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.applyLayerCommand(_:)
// 功能注释: 修改后 coordinator 提供正式 layer 命令入口，并在执行前统一结束 transient interaction。
func applyLayerCommand(_ command: HandDrawingLayerCommand) {
    endTransientInteractionState()
    guard engine.apply(layerCommand: command) else {
        publishSurfaceState()
        publishPaletteState()
        return
    }
    refreshCommittedImageAndPublishState(forceFullRender: true)
}
```

## 修改四：补阶段 3 回归测试，锁定当前层/选区/文档内容的一致恢复

### 修改前

- `HandDrawingEditorEngineTests` 只有两条基础测试：
  - 追加 stroke、导出并重载文档
  - `undo/redo + deselectAll`
- 还没有直接验证这些阶段 3 目标：
  - 切层时选区被清空
  - layer 操作全部可 undo/redo
  - 删除当前层后自动切相邻层
  - 最后一层不可删除

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() / testHandDrawingEditorEngineUndoRedoAndDeselect()
// 功能注释: 修改前 engine 测试只覆盖基础 stroke/history 行为，不覆盖 layer 命令历史语义。
func testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() throws {
    // ...
}

func testHandDrawingEditorEngineUndoRedoAndDeselect() {
    // ...
}
```

### 修改后

- 新增了 4 条阶段 3 直接相关的回归测试：
  - `testHandDrawingEditorEngineLayerSwitchClearsSelectionAndRestoresOnUndoRedo`
  - `testHandDrawingEditorEngineLayerMutationsRoundTripThroughUndoRedo`
  - `testHandDrawingEditorEngineDeleteCurrentLayerSwitchesToAdjacentLayer`
  - `testHandDrawingEditorEnginePreventsDeletingLastLayer`
- 测试关注点直接对齐阶段 3 完成标志：
  - 当前层、选区、文档内容三者在 undo/redo 后一起恢复
  - 新增/重命名/重排/显隐/锁定都会进历史
  - 最后一层删除被拒绝且不会产生脏 dirty region

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineLayerSwitchClearsSelectionAndRestoresOnUndoRedo() / testHandDrawingEditorEngineLayerMutationsRoundTripThroughUndoRedo() / testHandDrawingEditorEngineDeleteCurrentLayerSwitchesToAdjacentLayer() / testHandDrawingEditorEnginePreventsDeletingLastLayer()
// 功能注释: 修改后测试直接锁定阶段 3 的核心语义：切层清选区、layer 操作进历史、删当前层切相邻层、最后一层不可删。
func testHandDrawingEditorEngineLayerSwitchClearsSelectionAndRestoresOnUndoRedo() {
    // 切到 Base 层后，Detail 层选区会被清空；undo/redo 后当前层与选区一起恢复。
    XCTAssertTrue(
        engine.apply(command: .layer(.setActive(id: baseLayer.id)))
    )
    XCTAssertEqual(engine.state.activeLayerID, baseLayer.id)
    XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)

    XCTAssertTrue(engine.undo())
    XCTAssertEqual(engine.state.activeLayerID, detailLayer.id)
    XCTAssertEqual(engine.state.selectedStrokeIDs, [detailStroke.id])
}

func testHandDrawingEditorEngineLayerMutationsRoundTripThroughUndoRedo() throws {
    // 新建层后自动切到新层，并在 rename / visibility / lock / reorder 后都可逐步 undo / redo。
    XCTAssertTrue(engine.apply(command: .layer(.addLayer(name: nil))))
    XCTAssertTrue(
        engine.apply(
            command: .layer(.renameLayer(id: newLayerID, name: "Notes"))
        )
    )
    XCTAssertTrue(
        engine.apply(
            command: .layer(.setVisibility(id: newLayerID, isVisible: false))
        )
    )
    XCTAssertTrue(
        engine.apply(
            command: .layer(.setLocked(id: newLayerID, isLocked: true))
        )
    )
}

func testHandDrawingEditorEngineDeleteCurrentLayerSwitchesToAdjacentLayer() {
    // 删除当前 Detail 层后，当前层自动切到相邻 Overlay 层。
    XCTAssertTrue(
        engine.apply(command: .layer(.deleteLayer(id: detailLayer.id)))
    )
    XCTAssertEqual(engine.state.activeLayerID, overlayLayer.id)
    XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
}

func testHandDrawingEditorEnginePreventsDeletingLastLayer() {
    // 最后一层删除失败，不写历史，也不会产生新的 dirty region。
    XCTAssertFalse(
        engine.apply(command: .layer(.deleteLayer(id: onlyLayer.id)))
    )
    XCTAssertFalse(engine.canUndo)
    XCTAssertNil(engine.consumeDirtyRegion())
}
```

## 结果小结

- 阶段 3 已把 layer 状态正式纳入 engine / history：
  - 图层操作全部共享统一 undo/redo 语义
  - 当前层已成为正式状态，而不是只靠 UI 热修
  - 切层清选区、不允许删最后一层、删当前层切相邻层都落在代码约束里
- 阶段 4 还没有实施：
  - brush / pixel eraser / lasso / move 仍然沿用阶段 1 的兼容入口
  - “工具只作用当前 layer”会在下一阶段继续收口
