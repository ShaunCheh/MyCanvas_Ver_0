# 20260518_210129_CST_hand_drawing_multilayer_phase4_active_layer_tool_scoping_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 4：`画笔 / 橡皮 / 套索 / 移动全部收敛到 active layer`。
  2. 把 `brush`、像素橡皮、套索、移动对“当前活动层”的作用域从隐式兼容语义收口为显式代码约束。
  3. 禁止在 `hidden` / `locked` 当前层上开始 `brush / eraser / lasso / move` 交互。
  4. 补阶段 4 的多 layer / hidden / locked 回归测试，并做 macOS 定向测试与 iOS Simulator 构建验证。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_210129_CST`
- 说明：
  - 本记录只覆盖刚刚实施的多 layer 阶段 4，不包含阶段 5 的 iPad layer UI 和阶段 6 的宿主兼容收口。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests"`
    - 通过
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 5 的 iPad layer 管理 UI
  - 阶段 6 的 board / preview / thumbnail / minimap 宿主兼容收口
  - git commit / push

## 修改一：把 active layer 作用域与“当前层可交互”从隐式别名收口为显式契约

### 修改前

- `HandDrawingDocument` 虽然已经有 `activeLayer`，但工具层大多还是依赖 `document.strokes` 这个兼容入口来“隐式地”只看当前层。
- `HandDrawingStrokeGeometry.unionBounds(forStrokeIDs:in:)` 直接吃整个 `document`，内部再用 `document.strokes` 做过滤。
- `EditorState` / `HistorySnapshot` 的选区合法性修正也还是 `Set(document.strokes.map(\.id))`。
- 这种写法在行为上大致能工作，但阶段 4 目标要求的是“显式接收 active layer 范围”，而不是继续靠兼容别名偷偷成立。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.activeLayer / strokes
// 功能注释: 修改前文档层有 active layer 概念，但没有提供显式的 active layer strokes / strokeIDs / interactive 契约。
var strokes: [HandDrawingStroke] {
    get {
        activeLayer?.strokes ?? []
    }
    set {
        replaceStrokesInActiveLayer(with: newValue)
    }
}

var activeLayer: HandDrawingLayer? {
    guard let index = activeLayerIndex else {
        return nil
    }
    return layers[index]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: HandDrawingStrokeGeometry.unionBounds(forStrokeIDs:in:)
// 功能注释: 修改前几何层仍接收整个 document，再隐式依赖 document.strokes 的当前层兼容语义。
static func unionBounds(
    forStrokeIDs strokeIDs: Set<UUID>,
    in document: HandDrawingDocument
) -> CGRect? {
    unionBounds(
        for: document.strokes.filter { strokeIDs.contains($0.id) }
    )
}
```

### 修改后

- `HandDrawingLayer` 新增 `isInteractive`，显式表达 `visible && !locked`。
- `HandDrawingDocument` 新增：
  - `activeLayerStrokes`
  - `activeLayerStrokeIDs`
  - `isActiveLayerInteractive`
- `HandDrawingStrokeGeometry.unionBounds(forStrokeIDs:in:)` 改成显式接收 `strokes: [HandDrawingStroke]`。
- `EditorState` / `HistorySnapshot` 的选区修正也同步改成 `document.activeLayerStrokeIDs`。
- 这样阶段 4 的工具层就不再靠 `document.strokes` 的兼容别名吃隐式红利，而是正式依赖 active layer 作用域。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingLayer.isInteractive / HandDrawingDocument.activeLayerStrokes / activeLayerStrokeIDs / isActiveLayerInteractive
// 功能注释: 修改后文档层显式暴露当前层的 strokes、stroke IDs 和交互资格。
var isInteractive: Bool {
    isVisible && isLocked == false
}

var activeLayerStrokes: [HandDrawingStroke] {
    activeLayer?.strokes ?? []
}

var activeLayerStrokeIDs: Set<UUID> {
    Set(activeLayerStrokes.map(\.id))
}

var isActiveLayerInteractive: Bool {
    activeLayer?.isInteractive ?? false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: HandDrawingStrokeGeometry.unionBounds(forStrokeIDs:in:)
// 功能注释: 修改后几何层显式接收 stroke 范围，避免默认扫 document.strokes。
static func unionBounds(
    forStrokeIDs strokeIDs: Set<UUID>,
    in strokes: [HandDrawingStroke]
) -> CGRect? {
    unionBounds(
        for: strokes.filter { strokeIDs.contains($0.id) }
    )
}
```

## 修改二：`HandDrawingEditorEngine` 把 brush / selection / erase / move 正式收敛到 active layer

### 修改前

- `appendStroke(_:)` 一定会写入，不会检查当前层是否 `hidden/locked`。
- `selectStrokes(withIDs:)` 还是通过 `state.document.strokes` 做过滤。
- `upsertErasePaths(...)` 和 `translateSelectedStrokes(...)` 都直接在 `state.document.strokes` 上找 index 并原地修改。
- 这意味着“只作用当前层”更多还是靠 `document.strokes` 的兼容语义撑着，且没有把 `hidden/locked` 当前层排除在外。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: HandDrawingEditorEngine.appendStroke(_:) / selectStrokes(withIDs:recordUndo:) / upsertErasePaths(_:recordUndo:) / translateStrokes(withIDs:by:recordUndo:)
// 功能注释: 修改前 engine 仍通过 document.strokes 隐式限定当前层，且 append/erase/move 没有 hidden/locked 当前层门禁。
@discardableResult
mutating func appendStroke(_ stroke: HandDrawingStroke) -> HandDrawingStroke {
    recordSnapshotForUndo()
    state.document.appendStroke(stroke)
    dirtyRegionTracker.markDirty(stroke.bounds ?? state.document.paperBounds)
    return stroke
}

let existingStrokeIDs = Set(state.document.strokes.map(\.id))

let targetStrokeIndexes = state.document.strokes.indices.filter { index in
    let strokeID = state.document.strokes[index].id
    // ...
}

let targetStrokeIndexes = state.document.strokes.indices.filter { index in
    strokeIDs.contains(state.document.strokes[index].id)
}
```

### 修改后

- 新增 `canInteractWithActiveLayer`，统一表达“当前层是否允许开始/继续交互”。
- `appendStroke(_:)` 改为返回 `HandDrawingStroke?`，当前层 `hidden/locked` 时直接返回 `nil`，不进历史、不产 dirty region。
- `selectStrokes(withIDs:)` 改成显式使用 `state.document.activeLayerStrokeIDs`。
- `upsertErasePaths(...)` / `translateSelectedStrokes(...)` 现在都先复制 `activeLayerStrokes`，只在当前层范围内求 index 并修改，再通过 `replaceStrokesInActiveLayer(with:)` 回写。
- `sanitizedSelection(...)` 也改成只允许 `document.activeLayerStrokeIDs`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: HandDrawingEditorEngine.canInteractWithActiveLayer / appendStroke(_:) / selectStrokes(withIDs:recordUndo:) / upsertErasePaths(_:recordUndo:) / translateStrokes(withIDs:by:recordUndo:) / sanitizedSelection(_:in:)
// 功能注释: 修改后 engine 把工具层的作用域和 hidden/locked 门禁统一收口到 active layer 契约。
var canInteractWithActiveLayer: Bool {
    state.document.isActiveLayerInteractive
}

@discardableResult
mutating func appendStroke(_ stroke: HandDrawingStroke) -> HandDrawingStroke? {
    guard canInteractWithActiveLayer else {
        return nil
    }
    recordSnapshotForUndo()
    state.document.appendStroke(stroke)
    dirtyRegionTracker.markDirty(stroke.bounds ?? state.document.paperBounds)
    return stroke
}

let existingStrokeIDs = state.document.activeLayerStrokeIDs

guard canInteractWithActiveLayer else {
    return []
}
var activeLayerStrokes = state.document.activeLayerStrokes
let targetStrokeIndexes = activeLayerStrokes.indices.filter { index in
    let strokeID = activeLayerStrokes[index].id
    // ...
}

state.document.replaceStrokesInActiveLayer(with: activeLayerStrokes)

private func sanitizedSelection(
    _ selection: Set<UUID>,
    in document: HandDrawingDocument
) -> Set<UUID> {
    selection.intersection(document.activeLayerStrokeIDs)
}
```

## 修改三：像素橡皮 / 套索 / 移动 / 协调器入口都增加当前层门禁

### 修改前

- `HandDrawingPixelEraserToolController` 的命中遍历直接看 `document.strokes`。
- `HandDrawingLassoToolController.beginLasso(...)` 不知道 engine 状态，无法在开始前拒绝 `hidden/locked` 当前层；`endLasso(...)` 也直接扫 `document.strokes`。
- `HandDrawingMoveSelectionController.beginMoving(...)` 直接从 `document.strokes` 取选中 stroke。
- `HandDrawingEditorCoordinator.handlePencilStrokeBegan(...)` 对 `brush / pixelEraser / lasso` 都没有当前层是否可交互的 UI 入口门禁，所以即使 engine 最终可能拒绝，草稿/套索仍可能先开始。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: HandDrawingPixelEraserToolController.process(samples:baseSize:engine:)
// 功能注释: 修改前橡皮命中遍历仍依赖 document.strokes 的兼容语义，没有 hidden/locked 当前层门禁。
let document = engine.state.document
let hitStrokeIDs: Set<UUID> = Set(
    document.strokes.compactMap { stroke in
        guard strokeIntersectsEraseSample(stroke, eraseSample: eraseSample) else {
            return nil
        }
        return stroke.id
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift
// 函数名: HandDrawingLassoToolController.beginLasso(with:) / endLasso(engine:)
// 功能注释: 修改前套索开始时没有 engine 上下文，结束时仍扫描 document.strokes。
mutating func beginLasso(
    with sample: HandDrawingInputSample
) {
    points = [sample.location]
}

let selectedStrokeIDs: Set<UUID> = Set(
    engine.state.document.strokes.compactMap { stroke in
        guard HandDrawingStrokeGeometry.isStroke(stroke, enclosedBy: points) else {
            return nil
        }
        return stroke.id
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift
// 函数名: HandDrawingMoveSelectionController.beginMoving(with:engine:)
// 功能注释: 修改前移动命中从 document.strokes 取选中笔迹，没有 hidden/locked 当前层门禁。
let selectedStrokes = engine.state.document.strokes.filter {
    selectedStrokeIDs.contains($0.id)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.handlePencilStrokeBegan(_:) / handlePencilStrokeEnded(_:)
// 功能注释: 修改前 coordinator 在 brush / eraser / lasso 开始时不检查当前层是否允许交互。
case .brush:
    activeStrokeBrush = currentBrushStyle
    activeStrokeSamples = [sample]
    publishSurfaceState()
case .pixelEraser:
    pixelEraserToolController.beginErasing(
        with: sample,
        baseSize: selectedLineWidth,
        engine: &engine
    )
case .lasso:
    if moveSelectionController.beginMoving(with: sample, engine: engine) {
        // ...
    }
    lassoToolController.beginLasso(with: sample)
```

### 修改后

- 像素橡皮：
  - `process(...)` 一进来就 `guard engine.canInteractWithActiveLayer`
  - 命中集合显式改为 `engine.state.document.activeLayerStrokes`
- 套索：
  - `beginLasso(with:engine:) -> Bool`
  - 不能在 `hidden/locked` 当前层开始
  - `appendSamples(...)` 只有已经开始后才继续累积
  - `endLasso(...)` 显式只扫 `activeLayerStrokes`
- 移动：
  - `beginMoving(...)` 一开始就校验 `engine.canInteractWithActiveLayer`
  - 命中集合改为 `activeLayerStrokes`
- 协调器：
  - `handlePencilStrokeBegan(_:)` 的 `brush / pixelEraser / lasso` 入口统一 `guard engine.canInteractWithActiveLayer`
  - `brush` 在提交时也显式检查 `engine.appendStroke(...) != nil`
  - `selectedStrokeBounds` 改成显式传 `engine.state.document.activeLayerStrokes`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: HandDrawingPixelEraserToolController.process(samples:baseSize:engine:)
// 功能注释: 修改后像素橡皮只在可交互的 active layer 上开始，并且命中遍历只看 activeLayerStrokes。
guard
    samples.isEmpty == false,
    engine.canInteractWithActiveLayer
else {
    return
}

let activeLayerStrokes = engine.state.document.activeLayerStrokes
let hitStrokeIDs: Set<UUID> = Set(
    activeLayerStrokes.compactMap { stroke in
        guard strokeIntersectsEraseSample(stroke, eraseSample: eraseSample) else {
            return nil
        }
        return stroke.id
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift
// 函数名: HandDrawingLassoToolController.beginLasso(with:engine:) / appendSamples(_:) / endLasso(engine:)
// 功能注释: 修改后套索只有在 active layer 可交互时才能开始，且 enclosure 只发生在 activeLayerStrokes 上。
@discardableResult
mutating func beginLasso(
    with sample: HandDrawingInputSample,
    engine: HandDrawingEditorEngine
) -> Bool {
    guard engine.canInteractWithActiveLayer else {
        return false
    }
    points = [sample.location]
    return true
}

guard
    samples.isEmpty == false,
    points.isEmpty == false
else {
    return
}

let selectedStrokeIDs: Set<UUID> = Set(
    engine.state.document.activeLayerStrokes.compactMap { stroke in
        guard HandDrawingStrokeGeometry.isStroke(stroke, enclosedBy: points) else {
            return nil
        }
        return stroke.id
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift
// 函数名: HandDrawingMoveSelectionController.beginMoving(with:engine:)
// 功能注释: 修改后移动只允许命中 active layer 内的选中笔迹，并禁止在 hidden/locked 当前层开始。
guard engine.canInteractWithActiveLayer else {
    return false
}

let selectedStrokes = engine.state.document.activeLayerStrokes.filter {
    selectedStrokeIDs.contains($0.id)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.handlePencilStrokeBegan(_:) / handlePencilStrokeEnded(_:) / selectedStrokeBounds
// 功能注释: 修改后 coordinator 在工具开始前就阻止 hidden/locked 当前层启动交互，并显式按 active layer 计算选区包围盒。
case .brush:
    guard engine.canInteractWithActiveLayer else {
        return
    }
    activeStrokeBrush = currentBrushStyle
    activeStrokeSamples = [sample]
    publishSurfaceState()
case .pixelEraser:
    guard engine.canInteractWithActiveLayer else {
        return
    }
    pixelEraserToolController.beginErasing(
        with: sample,
        baseSize: selectedLineWidth,
        engine: &engine
    )
case .lasso:
    guard engine.canInteractWithActiveLayer else {
        return
    }
    guard lassoToolController.beginLasso(with: sample, engine: engine) else {
        return
    }

guard engine.appendStroke(
    brush: activeStrokeBrush,
    samples: committedStrokeSamples
) != nil else {
    publishSurfaceState()
    publishPaletteState()
    return
}

HandDrawingStrokeGeometry.unionBounds(
    forStrokeIDs: engine.state.selectedStrokeIDs,
    in: engine.state.document.activeLayerStrokes
)
```

## 修改四：补阶段 4 多 layer / hidden / locked 回归测试

### 修改前

- `HandDrawingEditorEngineTests` 只验证阶段 3 的 layer 命令与历史语义，没有直接覆盖“当前层不可交互时 brush 拒绝落笔”。
- `HandDrawingPixelEraserToolControllerTests` / `HandDrawingLassoSelectionTests` / `HandDrawingMoveSelectionTests` 都还是单层场景，缺少这些断言：
  - 重叠多 layer 时只作用当前层
  - `hidden/locked` 当前层时不能开始交互

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() / testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument()
// 功能注释: 修改前橡皮测试只覆盖单层命中与撤销，不覆盖 active layer 作用域和 hidden/locked 门禁。
func testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() {
    // ...
}

func testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument() {
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo() / testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke()
// 功能注释: 修改前套索测试只覆盖 enclosure 结果，不覆盖 active layer 与 hidden/locked 当前层门禁。
func testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo() {
    // ...
}

func testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke() {
    // ...
}
```

### 修改后

- `HandDrawingEditorEngineTests`
  - 新增 `testHandDrawingEditorEngineAppendStrokeRequiresInteractiveActiveLayer`
- `HandDrawingPixelEraserToolControllerTests`
  - 新增 `testHandDrawingPixelEraserToolControllerOnlyMutatesActiveLayerStroke`
  - 新增 `testHandDrawingPixelEraserToolControllerDoesNotStartOnHiddenOrLockedActiveLayer`
- `HandDrawingLassoSelectionTests`
  - 新增 `testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke`
  - 新增 `testHandDrawingLassoToolControllerDoesNotBeginOnHiddenOrLockedActiveLayer`
  - 原有测试同步更新到新的 `beginLasso(with:engine:)`
- `HandDrawingMoveSelectionTests`
  - 新增 `testHandDrawingMoveSelectionControllerOnlyMovesActiveLayerSelection`
  - 新增 `testHandDrawingMoveSelectionControllerCannotBeginOnHiddenOrLockedActiveLayer`

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineAppendStrokeRequiresInteractiveActiveLayer()
// 功能注释: 修改后 engine 测试直接锁定 brush 在 hidden/locked 当前层上不会落笔、不会进历史、不会产生 dirty region。
func testHandDrawingEditorEngineAppendStrokeRequiresInteractiveActiveLayer() {
    var hiddenEngine = makeEngine(isVisible: false, isLocked: false)
    XCTAssertNil(
        hiddenEngine.appendStroke(
            brush: .defaultPen,
            samples: [
                HandDrawingInputSample(location: CGPoint(x: 20, y: 20), timestamp: 0),
                HandDrawingInputSample(location: CGPoint(x: 80, y: 80), timestamp: 0.2)
            ]
        )
    )
    XCTAssertTrue(hiddenEngine.state.document.activeLayerStrokes.isEmpty)
    XCTAssertFalse(hiddenEngine.canUndo)
    XCTAssertNil(hiddenEngine.consumeDirtyRegion())
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerOnlyMutatesActiveLayerStroke() / testHandDrawingPixelEraserToolControllerDoesNotStartOnHiddenOrLockedActiveLayer()
// 功能注释: 修改后橡皮测试同时验证“只影响 active layer”和“hidden/locked 当前层无法开始”。
func testHandDrawingPixelEraserToolControllerOnlyMutatesActiveLayerStroke() throws {
    // inactive / active 两层都放一笔重叠笔迹，只允许 active layer 被写入 eraseMask。
    XCTAssertEqual(mutatedActiveStroke.eraseMask.count, 1)
    XCTAssertTrue(untouchedInactiveStroke.eraseMask.isEmpty)
}

func testHandDrawingPixelEraserToolControllerDoesNotStartOnHiddenOrLockedActiveLayer() {
    // 当前层 hidden 或 locked 时，controller 不进入 active，不写历史，不产 dirty region。
    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(engine.state.document.activeLayerStrokes[0].eraseMask.isEmpty)
    XCTAssertFalse(engine.canUndo)
    XCTAssertNil(engine.consumeDirtyRegion())
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke() / testHandDrawingLassoToolControllerDoesNotBeginOnHiddenOrLockedActiveLayer()
// 功能注释: 修改后套索测试锁定“重叠多 layer 只选 active layer”和“hidden/locked 当前层不允许 beginLasso”。
func testHandDrawingLassoToolControllerOnlySelectsActiveLayerStroke() {
    XCTAssertTrue(controller.endLasso(engine: &engine))
    XCTAssertEqual(engine.state.selectedStrokeIDs, [activeStroke.id])
    XCTAssertFalse(engine.state.selectedStrokeIDs.contains(inactiveStroke.id))
}

func testHandDrawingLassoToolControllerDoesNotBeginOnHiddenOrLockedActiveLayer() {
    XCTAssertFalse(
        controller.beginLasso(
            with: HandDrawingInputSample(location: CGPoint(x: 18, y: 44), timestamp: 0),
            engine: engine
        )
    )
    XCTAssertTrue(controller.points.isEmpty)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerOnlyMovesActiveLayerSelection() / testHandDrawingMoveSelectionControllerCannotBeginOnHiddenOrLockedActiveLayer()
// 功能注释: 修改后移动测试验证只能移动 active layer 选中内容，且 hidden/locked 当前层无法开始拖动。
func testHandDrawingMoveSelectionControllerOnlyMovesActiveLayerSelection() throws {
    XCTAssertTrue(engine.selectStrokes(withIDs: [inactiveStroke.id, activeStroke.id]))
    XCTAssertEqual(engine.state.selectedStrokeIDs, [activeStroke.id])

    XCTAssertEqual(movedActiveStroke.transform.translationX, 10, accuracy: 0.001)
    XCTAssertEqual(movedActiveStroke.transform.translationY, 8, accuracy: 0.001)
    XCTAssertEqual(untouchedInactiveStroke.transform.translationX, 0, accuracy: 0.001)
    XCTAssertEqual(untouchedInactiveStroke.transform.translationY, 0, accuracy: 0.001)
}

func testHandDrawingMoveSelectionControllerCannotBeginOnHiddenOrLockedActiveLayer() {
    XCTAssertFalse(
        controller.beginMoving(
            with: HandDrawingInputSample(location: CGPoint(x: 60, y: 60), timestamp: 0),
            engine: engine
        )
    )
    XCTAssertFalse(controller.isActive)
}
```

## 结果小结

- 阶段 4 已把工具层语义真正收口到 active layer：
  - `brush` 只允许在可交互的当前层落笔
  - 像素橡皮命中与写入只作用当前层
  - 套索 enclosure 只发生在当前层
  - 移动只平移当前层选中的笔迹
- `selectedStrokeIDs` 继续沿用全局 UUID，但 engine 现在明确保证它始终是当前层 `activeLayerStrokeIDs` 的子集。
- `hidden` / `locked` 当前层现在无法开始 `brush / eraser / lasso / move`。
- 几何层也已经去掉对 `document.strokes` 隐式作用域的依赖，改成显式接收当前层的 stroke 范围。
