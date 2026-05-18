# 20260518_173828_CST_hand_drawing_kernel_phase7_lasso_move_record

## 记录范围

- 记录内容：
  1. 实施阶段 7 的套索选择与移动能力。
  2. 把“选择状态 + 选中笔迹平移”正式纳入 `HandDrawingEditorEngine` 的 undo / redo。
  3. 新增套索控制器、移动控制器和共享 stroke 几何判断层。
  4. 接通 iPad 编辑器里的 lasso 工具、选区 overlay、显式取消选择按钮与状态发布。
  5. 补齐阶段 7 的定点测试，并验证 iOS 构建与相关 hand drawing 测试链。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_173828_CST`
- 说明：
  - 本记录以阶段 6 完成态为基线，结合当前 `git status`、当前 `git diff` 和当前文件内容整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
  - 对于新增文件，修改前如实记录为“文件不存在”。
  - 工作区里与阶段 7 无关的其它变更不纳入本记录。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
  - 阶段 6 记录：
    - `commit_records/20260518_172047_CST_hand_drawing_kernel_phase6_pixel_eraser_record.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests"`
    - 通过
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 8 宿主替换与共享链兼容
  - 缩放 / 旋转 / 复制等 V2 选区能力
  - git commit / push

## 修改一：`HandDrawingEditorEngine` 把“选择变更 + 选中移动”纳入可撤销状态

### 修改前

- `selectStrokes(withIDs:)` 只是直接覆盖 `selectedStrokeIDs`，不返回是否变化，也不进入 undo / redo。
- `apply(command:)` 的 `.deselectAll` 只是简单清空选择。
- engine 没有“平移当前选中 strokes”的原子操作，因此阶段 7 无法把移动动作落到历史链路里。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: selectStrokes(withIDs:) / apply(command:)
// 功能说明: 修改前 selection 只是即时覆盖 state，不记录历史，也没有用于对象级移动的 translate 能力。
mutating func selectStrokes(withIDs strokeIDs: Set<UUID>) {
    let existingStrokeIDs = Set(state.document.strokes.map(\.id))
    state.selectedStrokeIDs = strokeIDs.intersection(existingStrokeIDs)
}

mutating func apply(command: HandDrawingEditorCommand) {
    switch command {
    case .deselectAll:
        state.selectedStrokeIDs.removeAll()
    }
}

// 修改前不存在:
// - selectStrokes(withIDs:recordUndo:) -> Bool
// - apply(command:recordUndo:) -> Bool
// - translateSelectedStrokes(by:recordUndo:)
// - translateStrokes(withIDs:by:recordUndo:)
```

### 修改后

- `selectStrokes(withIDs:recordUndo:)` 现在会：
  - 只保留文档里真实存在的 stroke ID；
  - 判断 selection 是否真的变化；
  - 需要时记录 undo snapshot；
  - 返回本次是否实际修改了状态。
- `apply(command:recordUndo:)` 的 `.deselectAll` 改成复用 `selectStrokes(withIDs:[])`。
- 新增 `translateSelectedStrokes(by:recordUndo:)`，把“移动选中对象”正式落到 engine，并按旧 bounds / 新 bounds 并集标记 dirty region。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: selectStrokes(withIDs:recordUndo:) / apply(command:recordUndo:) / translateSelectedStrokes(by:recordUndo:)
// 功能说明: 修改后 selection 和 move 都进入 engine 的状态机与历史系统，
// 阶段 7 的“套索选中 / 取消选择 / 拖动移动 / undo / redo”才真正闭环。
@discardableResult
mutating func selectStrokes(
    withIDs strokeIDs: Set<UUID>,
    recordUndo: Bool = true
) -> Bool {
    let existingStrokeIDs = Set(state.document.strokes.map(\.id))
    let resolvedSelection = strokeIDs.intersection(existingStrokeIDs)
    guard resolvedSelection != state.selectedStrokeIDs else {
        return false
    }
    if recordUndo {
        recordSnapshotForUndo()
    }
    state.selectedStrokeIDs = resolvedSelection
    return true
}

@discardableResult
mutating func apply(
    command: HandDrawingEditorCommand,
    recordUndo: Bool = true
) -> Bool {
    switch command {
    case .deselectAll:
        return selectStrokes(withIDs: [], recordUndo: recordUndo)
    }
}

@discardableResult
mutating func translateSelectedStrokes(
    by delta: CGPoint,
    recordUndo: Bool = true
) -> Set<UUID> {
    translateStrokes(
        withIDs: state.selectedStrokeIDs,
        by: delta,
        recordUndo: recordUndo
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: translateStrokes(withIDs:by:recordUndo:)
// 功能说明: 修改后平移操作会只移动命中的选中笔迹，并用旧/新 bounds 并集推进增量重绘。
@discardableResult
private mutating func translateStrokes(
    withIDs strokeIDs: Set<UUID>,
    by delta: CGPoint,
    recordUndo: Bool
) -> Set<UUID> {
    guard
        strokeIDs.isEmpty == false,
        delta != .zero
    else {
        return []
    }

    let targetStrokeIndexes = state.document.strokes.indices.filter { index in
        strokeIDs.contains(state.document.strokes[index].id)
    }
    guard targetStrokeIndexes.isEmpty == false else {
        return []
    }

    if recordUndo {
        recordSnapshotForUndo()
    }

    var translatedStrokeIDs: Set<UUID> = []
    for index in targetStrokeIndexes {
        let oldBounds = state.document.strokes[index].bounds
        state.document.strokes[index].transform.translationX += Double(delta.x)
        state.document.strokes[index].transform.translationY += Double(delta.y)
        let newBounds = state.document.strokes[index].bounds
        dirtyRegionTracker.markDirty(
            resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds)
        )
        translatedStrokeIDs.insert(state.document.strokes[index].id)
    }

    return translatedStrokeIDs
}
```

## 修改二：抽出共享 `HandDrawingStrokeGeometry`，把“橡皮命中 / 套索包围 / 选中拖动命中”统一到一层

### 修改前

- 阶段 6 的 `HandDrawingPixelEraserToolController` 自己持有整套几何命中逻辑：
  - stroke bounds 扩展；
  - 点到圆 / 点到线段距离；
  - segment 命中判断。
- 阶段 7 如果继续在 lasso / move controller 里各写一套，会把 stroke 几何判断拆成三份实现。
- 项目里还没有统一的 `HandDrawingStrokeGeometry.swift`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: strokeIntersectsEraseSample(_:eraseSample:) / distanceBetween(_:_) / distanceFromPoint(_:toSegmentFrom:to:)
// 功能说明: 修改前像素橡皮自己维护完整的 stroke 几何命中实现，阶段 7 新功能无法直接复用。
private func strokeIntersectsEraseSample(
    _ stroke: HandDrawingStroke,
    eraseSample: HandDrawingEraseSamplePoint
) -> Bool {
    guard let strokeBounds = stroke.bounds else {
        return false
    }

    let expandedSampleBounds = CGRect(
        x: eraseSample.cgPoint.x - eraseSample.resolvedRadius,
        y: eraseSample.cgPoint.y - eraseSample.resolvedRadius,
        width: eraseSample.resolvedRadius * 2,
        height: eraseSample.resolvedRadius * 2
    )
    guard strokeBounds.intersects(expandedSampleBounds) else {
        return false
    }

    // 功能注释: 修改前此处后面还包含 transformed points、segment 遍历、
    // 点到线段距离与半径叠加判断等完整私有命中逻辑。
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前项目里没有统一的 stroke 几何辅助层。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingStrokeGeometry.swift`，集中提供四类能力：
  - `intersectsCircle(...)`：给橡皮 / 命中热区复用；
  - `contains(_:in:padding:)`：给选中拖动命中复用；
  - `isStroke(_:enclosedBy:)`：给套索整笔包围判断复用；
  - `unionBounds(...)`：给选区 overlay 计算统一 bounds。
- `HandDrawingPixelEraserToolController` 改成直接复用 `HandDrawingStrokeGeometry.intersectsCircle(...)`，删除自己那套私有距离函数。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeGeometry.swift
// 函数名: intersectsCircle(_:center:radius:) / contains(_:in:padding:) / isStroke(_:enclosedBy:) / unionBounds(forStrokeIDs:in:)
// 功能说明: 修改后 stroke 几何判断被收口到共享层，阶段 6 的像素橡皮与阶段 7 的套索/移动使用同一套判断标准。
enum HandDrawingStrokeGeometry {
    static func intersectsCircle(
        _ stroke: HandDrawingStroke,
        center: CGPoint,
        radius: CGFloat
    ) -> Bool {
        guard let strokeBounds = stroke.bounds else {
            return false
        }

        let resolvedRadius = max(radius, 0.25)
        let expandedBounds = CGRect(
            x: center.x - resolvedRadius,
            y: center.y - resolvedRadius,
            width: resolvedRadius * 2,
            height: resolvedRadius * 2
        )
        guard strokeBounds.intersects(expandedBounds) else {
            return false
        }

        let transformedPoints = stroke.transformedSamplePoints
        if transformedPoints.isEmpty {
            return false
        }

        for (index, point) in transformedPoints.enumerated() {
            let strokeRadius = stroke.radiusForSample(at: index)
            if distanceBetween(point, center) <= strokeRadius + resolvedRadius {
                return true
            }
        }

        guard transformedPoints.count > 1 else {
            return false
        }

        for index in 1..<transformedPoints.count {
            let startPoint = transformedPoints[index - 1]
            let endPoint = transformedPoints[index]
            let strokeRadius = max(
                stroke.radiusForSample(at: index - 1),
                stroke.radiusForSample(at: index)
            )
            let distanceToSegment = distanceFromPoint(
                center,
                toSegmentFrom: startPoint,
                to: endPoint
            )
            if distanceToSegment <= strokeRadius + resolvedRadius {
                return true
            }
        }

        return false
    }

    static func contains(
        _ point: CGPoint,
        in stroke: HandDrawingStroke,
        padding: CGFloat = 0
    ) -> Bool {
        intersectsCircle(
            stroke,
            center: point,
            radius: max(padding, 0.25)
        )
    }

    static func isStroke(
        _ stroke: HandDrawingStroke,
        enclosedBy polygonPoints: [CGPoint]
    ) -> Bool {
        let resolvedPolygonPoints = normalizedPolygonPoints(polygonPoints)
        guard
            resolvedPolygonPoints.count >= 3,
            let strokeBounds = stroke.bounds
        else {
            return false
        }

        let polygonBounds = bounds(for: resolvedPolygonPoints)
        guard polygonBounds.intersects(strokeBounds) else {
            return false
        }

        let transformedPoints = stroke.transformedSamplePoints
        guard transformedPoints.isEmpty == false else {
            return false
        }

        for (index, point) in transformedPoints.enumerated() {
            let radius = stroke.radiusForSample(at: index)
            guard probePoints(around: point, radius: radius).allSatisfy({
                contains($0, inPolygon: resolvedPolygonPoints)
            }) else {
                return false
            }
        }

        guard transformedPoints.count > 1 else {
            return true
        }

        // 功能注释: 修改后这里还会继续检查每段线段上的插值采样点，
        // 阶段 7 V1 要求整笔 stroke 被 polygon 包围，而不是只看个别采样点。
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: strokeIntersectsEraseSample(_:eraseSample:)
// 功能说明: 修改后像素橡皮不再自带一份几何实现，而是复用共享 stroke geometry。
private func strokeIntersectsEraseSample(
    _ stroke: HandDrawingStroke,
    eraseSample: HandDrawingEraseSamplePoint
) -> Bool {
    HandDrawingStrokeGeometry.intersectsCircle(
        stroke,
        center: eraseSample.cgPoint,
        radius: eraseSample.resolvedRadius
    )
}
```

## 修改三：新增 `HandDrawingLassoToolController` 与 `HandDrawingMoveSelectionController`

### 修改前

- 项目里没有 lasso controller，也没有 move selection controller。
- 编辑器虽然已有 `selectedStrokeIDs` 状态字段，但没有负责“采样闭环 -> 选整笔”和“选中后拖动连续位移”的会话控制器。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前不存在套索控制器，Apple Pencil 的 lasso 路径无法转换成选中的整笔 stroke。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前不存在选中移动控制器，选中笔迹后也没有连续拖动会话。
// 修改前不存在该文件。
```

### 修改后

- `HandDrawingLassoToolController`：
  - 记录 Pencil 套索路径点；
  - 过滤过密采样；
  - 判断路径长度和包围盒是否足以构成有效 lasso；
  - 结束时用 `HandDrawingStrokeGeometry.isStroke(... enclosedBy:)` 只选整笔 stroke。
- `HandDrawingMoveSelectionController`：
  - 只允许从已选 stroke 上开始拖动；
  - 通过 `HandDrawingStrokeGeometry.contains(... padding:)` 做命中热区；
  - 只在第一次有效位移时记录 undo；
  - cancel 时回滚本次移动。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLassoToolController.swift
// 函数名: beginLasso(with:) / appendSamples(_:) / endLasso(engine:)
// 功能说明: 修改后 lasso controller 负责管理闭环前的采样轨迹，并在结束时把套索路径转换成整笔选区。
struct HandDrawingLassoToolController {
    private(set) var points: [CGPoint] = []

    mutating func beginLasso(
        with sample: HandDrawingInputSample
    ) {
        points = [sample.location]
    }

    mutating func appendSamples(
        _ samples: [HandDrawingInputSample]
    ) {
        for sample in samples {
            if let lastPoint = points.last,
               hypot(lastPoint.x - sample.location.x, lastPoint.y - sample.location.y) < 1
            {
                continue
            }
            points.append(sample.location)
        }
    }

    @discardableResult
    mutating func endLasso(
        engine: inout HandDrawingEditorEngine
    ) -> Bool {
        let selectedStrokeIDs: Set<UUID> = Set(
            engine.state.document.strokes.compactMap { stroke in
                guard HandDrawingStrokeGeometry.isStroke(stroke, enclosedBy: points) else {
                    return nil
                }
                return stroke.id
            }
        )
        return engine.selectStrokes(withIDs: selectedStrokeIDs)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingMoveSelectionController.swift
// 函数名: beginMoving(with:engine:) / appendSamples(_:engine:) / cancelMoving(engine:)
// 功能说明: 修改后 move controller 负责管理“从已选对象上开始拖动”的会话，
// 并把连续采样转成对 engine.translateSelectedStrokes(by:) 的增量调用。
struct HandDrawingMoveSelectionController {
    private var lastSampleLocation: CGPoint?
    private var hasAppliedMutation = false

    mutating func beginMoving(
        with sample: HandDrawingInputSample,
        engine: HandDrawingEditorEngine
    ) -> Bool {
        let selectedStrokeIDs = engine.state.selectedStrokeIDs
        let selectedStrokes = engine.state.document.strokes.filter {
            selectedStrokeIDs.contains($0.id)
        }
        let didHitSelectedStroke = selectedStrokes.contains { stroke in
            HandDrawingStrokeGeometry.contains(
                sample.location,
                in: stroke,
                padding: 12
            )
        }
        guard didHitSelectedStroke else {
            return false
        }

        lastSampleLocation = sample.location
        hasAppliedMutation = false
        return true
    }

    mutating func appendSamples(
        _ samples: [HandDrawingInputSample],
        engine: inout HandDrawingEditorEngine
    ) {
        for sample in samples {
            let delta = CGPoint(
                x: sample.location.x - (lastSampleLocation?.x ?? sample.location.x),
                y: sample.location.y - (lastSampleLocation?.y ?? sample.location.y)
            )
            let movedStrokeIDs = engine.translateSelectedStrokes(
                by: delta,
                recordUndo: hasAppliedMutation == false
            )
            if movedStrokeIDs.isEmpty == false {
                hasAppliedMutation = true
            }
            lastSampleLocation = sample.location
        }
    }
}
```

## 修改四：`HandDrawingEditorCoordinator` 与 iPad 编辑器 UI 正式接通 lasso / move / deselect / overlay

### 修改前

- `HandDrawingEditorCoordinator` 里虽然有 `.lasso` 工具枚举，但实际流程里直接 `return`，没有任何 lasso 会话。
- `HandDrawingToolPaletteState.isLassoEnabled` 固定为 `false`。
- `HandDrawingCanvasSurfaceState` 只携带 `committedImage` 和 `draftStroke`，没有 lasso path 或选区 bounds。
- `HandDrawingToolPaletteView` 没有 “Deselect” 按钮。
- `HandDrawingCanvasSurfaceView` 的 overlay 只会画当前草稿 stroke，不会画套索路径和已选 bounds。
- `iOSHandDrawingEditorViewController` 的提示文案仍然只强调“画笔”，没有把 lasso 能力暴露出来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: selectTool(_:) / handlePencilStrokeBegan(_:) / handlePencilStrokeMoved(_:) / handlePencilStrokeEnded(_:)
// 功能说明: 修改前 coordinator 对 lasso 分支一律直接返回，工具按钮存在，但功能链路未接通。
func selectTool(_ tool: HandDrawingEditorTool) {
    switch tool {
    case .brush, .pixelEraser:
        selectedTool = tool
        clearActiveStroke()
        pixelEraserToolController.endErasing()
    case .lasso:
        return
    }
}

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    switch selectedTool {
    case .brush:
        // 画笔逻辑
    case .pixelEraser:
        // 橡皮逻辑
    case .lasso:
        return
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: setupViewHierarchy() / bindActions()
// 功能说明: 修改前 palette 没有显式取消选择按钮。
[undoButton, redoButton].forEach(historyStackView.addArrangedSubview)

// 修改前不存在:
// - onDeselectSelection
// - deselectButton
// - handleDeselectButtonTap()
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCanvasDraftOverlayView.draw(_:)
// 功能说明: 修改前 overlay 只渲染 draftStroke，不显示选区外观与 lasso 轨迹。
override func draw(_ rect: CGRect) {
    super.draw(rect)
    guard
        let draftStroke,
        let context = UIGraphicsGetCurrentContext()
    else {
        return
    }
    context.saveGState()
    HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
    context.restoreGState()
}
```

### 修改后

- `HandDrawingCanvasSurfaceState` 新增：
  - `lassoPathPoints`
  - `selectedStrokeBounds`
- `HandDrawingToolPaletteState` 新增：
  - `canDeselectSelection`
- coordinator 里新增：
  - `lassoToolController`
  - `moveSelectionController`
  - `deselectSelection()`
  - `selectedStrokeBounds` 计算
  - `endTransientInteractionState()`，统一切工具 / undo / redo 前的瞬时状态收口
- lasso 工具行为：
  - 若起点命中当前已选 stroke，则进入 move session；
  - 否则进入 lasso session；
  - 结束时根据当前会话走“结束移动”或“套索选中”。
- palette 新增 `Deselect` 按钮。
- surface overlay 新增套索轨迹和选区 bounds 渲染。
- iOS 编辑器提示文案更新为 “Draw or lasso with Apple Pencil. Use fingers to pan and zoom.”

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingCanvasSurfaceState / HandDrawingToolPaletteState / selectTool(_:) / deselectSelection()
// 功能说明: 修改后 coordinator 正式发布 lasso path、selected bounds 和 canDeselectSelection，
// 同时把 lasso 变成真正可切换、可取消的编辑工具。
struct HandDrawingCanvasSurfaceState {
    var paperSize: CGSize
    var committedImage: CGImage?
    var draftStroke: HandDrawingStroke?
    var lassoPathPoints: [CGPoint]
    var selectedStrokeBounds: CGRect?
}

struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedLineWidth: CGFloat
    var availableColors: [HandDrawingColor]
    var availableLineWidths: [CGFloat]
    var canUndo: Bool
    var canRedo: Bool
    var isPixelEraserEnabled: Bool
    var isLassoEnabled: Bool
    var canDeselectSelection: Bool
}

func selectTool(_ tool: HandDrawingEditorTool) {
    endTransientInteractionState()
    switch tool {
    case .brush, .pixelEraser:
        selectedTool = tool
        clearActiveStroke()
    case .lasso:
        selectedTool = .lasso
    }
    publishSurfaceState()
    publishPaletteState()
}

func deselectSelection() {
    endTransientInteractionState()
    if engine.apply(command: .deselectAll) {
        publishSurfaceState()
        publishPaletteState()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: handlePencilStrokeBegan(_:) / handlePencilStrokeMoved(_:) / handlePencilStrokeEnded(_:)
// 功能说明: 修改后 lasso 分支会先尝试进入 move session，只有未命中已选对象时才开始新套索。
case .lasso:
    if moveSelectionController.beginMoving(with: sample, engine: engine) {
        publishSurfaceState()
        return
    }
    lassoToolController.beginLasso(with: sample)
    publishSurfaceState()

case .lasso:
    if moveSelectionController.isActive {
        moveSelectionController.appendSamples(samples, engine: &engine)
        refreshCommittedImageAndPublishState()
        return
    }
    lassoToolController.appendSamples(samples)
    publishSurfaceState()

case .lasso:
    if moveSelectionController.isActive {
        moveSelectionController.appendSamples(samples, engine: &engine)
        moveSelectionController.endMoving()
        refreshCommittedImageAndPublishState()
        return
    }
    lassoToolController.appendSamples(samples)
    _ = lassoToolController.endLasso(engine: &engine)
    publishSurfaceState()
    publishPaletteState()
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: apply(state:) / setupViewHierarchy() / handleDeselectButtonTap()
// 功能说明: 修改后 palette 新增 Deselect 按钮，并根据 canDeselectSelection 决定是否可用。
var onDeselectSelection: (() -> Void)?
private let deselectButton = HandDrawingToolPaletteView.makeActionButton(title: "Deselect")

func apply(state: HandDrawingToolPaletteState) {
    updateToolButtonSelection(
        lassoButton,
        isSelected: state.selectedTool == .lasso,
        isEnabled: state.isLassoEnabled
    )
    updateToolButtonSelection(
        deselectButton,
        isSelected: false,
        isEnabled: state.canDeselectSelection
    )
}

[deselectButton, undoButton, redoButton].forEach(historyStackView.addArrangedSubview)

@objc
private func handleDeselectButtonTap() {
    onDeselectSelection?()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingCanvasPageView.apply(state:) / HandDrawingCanvasDraftOverlayView.draw(_:) / drawSelectedStrokeBoundsIfNeeded(in:) / drawLassoPathIfNeeded(in:)
// 功能说明: 修改后 surface overlay 会同时绘制 committed image 上方的 draftStroke、选区 bounds 和 lasso path。
func apply(state: HandDrawingCanvasSurfaceState) {
    if let committedImage = state.committedImage {
        committedImageView.image = UIImage(cgImage: committedImage)
    } else {
        committedImageView.image = nil
    }
    draftOverlayView.draftStroke = state.draftStroke
    draftOverlayView.lassoPathPoints = state.lassoPathPoints
    draftOverlayView.selectedStrokeBounds = state.selectedStrokeBounds
}

override func draw(_ rect: CGRect) {
    super.draw(rect)
    guard let context = UIGraphicsGetCurrentContext() else {
        return
    }
    context.saveGState()
    if let draftStroke {
        HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
    }
    drawSelectedStrokeBoundsIfNeeded(in: context)
    drawLassoPathIfNeeded(in: context)
    context.restoreGState()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: hintLabel 初始化闭包 / configurePaletteView()
// 功能说明: 修改后编辑器文案和 palette 回调都显式接通 lasso / deselect。
label.text = "Draw or lasso with Apple Pencil. Use fingers to pan and zoom."

paletteView.onDeselectSelection = { [weak self] in
    self?.coordinator.deselectSelection()
}
```

## 修改五：补齐阶段 7 测试，并调整已有 engine 断言以匹配新的历史语义

### 修改前

- 没有 `HandDrawingLassoSelectionTests`。
- 没有 `HandDrawingMoveSelectionTests`。
- `HandDrawingEditorEngineTests.testHandDrawingEditorEngineUndoRedoAndDeselect()` 还把 undo 行为理解成“回到少一条 stroke 的历史态”，并没有覆盖“deselect 本身进入历史”的新语义。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前没有套索整笔选择与 undo / redo 的专门测试。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前没有选中后拖动平移与撤销恢复位置的专门测试。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineUndoRedoAndDeselect()
// 功能说明: 修改前现有测试没有把“selection 变化也进入历史”这件事编码进断言里。
engine.selectStrokes(withIDs: [firstStroke.id, secondStroke.id])
engine.apply(command: .deselectAll)

XCTAssertTrue(engine.undo())
XCTAssertEqual(engine.state.document.strokes.count, 1)
```

### 修改后

- 新增 `HandDrawingLassoSelectionTests`：
  - 验证只选中 lasso 区域完全包围的 stroke；
  - 验证 undo / redo 会正确恢复 / 重做 selection。
- 新增 `HandDrawingMoveSelectionTests`：
  - 验证移动后 `transform.translationX / Y` 更新；
  - 验证 undo 会恢复位移前的位置，同时 selection 仍保留。
- 更新 `HandDrawingEditorEngineTests`：
  - selection 变化本身进入历史；
  - undo 后应恢复原有 selection；
  - redo 后应重新回到 deselect 状态，而不是误退回笔迹数量变化。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo()
// 功能说明: 修改后测试验证 V1 套索只选整笔 stroke，且选择状态跟随 undo / redo。
controller.beginLasso(
    with: HandDrawingInputSample(
        location: CGPoint(x: 18, y: 44),
        timestamp: 0
    )
)
controller.appendSamples(
    [
        HandDrawingInputSample(location: CGPoint(x: 102, y: 44), timestamp: 0.1),
        HandDrawingInputSample(location: CGPoint(x: 102, y: 78), timestamp: 0.2),
        HandDrawingInputSample(location: CGPoint(x: 18, y: 78), timestamp: 0.3)
    ]
)

XCTAssertTrue(controller.endLasso(engine: &engine))
XCTAssertEqual(engine.state.selectedStrokeIDs, [enclosedStroke.id])
XCTAssertTrue(engine.undo())
XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
XCTAssertTrue(engine.redo())
XCTAssertEqual(engine.state.selectedStrokeIDs, [enclosedStroke.id])
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition()
// 功能说明: 修改后测试验证选中拖动会修改 stroke transform，
// 且 undo 会恢复原位，不会丢失 selection。
XCTAssertTrue(engine.selectStrokes(withIDs: [stroke.id]))
XCTAssertTrue(
    controller.beginMoving(
        with: HandDrawingInputSample(
            location: CGPoint(x: 60, y: 60),
            timestamp: 0
        ),
        engine: engine
    )
)

controller.appendSamples(
    [
        HandDrawingInputSample(
            location: CGPoint(x: 76, y: 72),
            timestamp: 0.1
        )
    ],
    engine: &engine
)

let movedStroke = engine.state.document.strokes[0]
XCTAssertEqual(movedStroke.transform.translationX, 16, accuracy: 0.001)
XCTAssertEqual(movedStroke.transform.translationY, 12, accuracy: 0.001)

XCTAssertTrue(engine.undo())
let restoredStroke = engine.state.document.strokes[0]
XCTAssertEqual(restoredStroke.transform.translationX, 0, accuracy: 0.001)
XCTAssertEqual(restoredStroke.transform.translationY, 0, accuracy: 0.001)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift
// 函数名: testHandDrawingEditorEngineUndoRedoAndDeselect()
// 功能说明: 修改后测试按新的历史语义断言“deselect 本身可撤销”，不再把 undo 错误理解成回退笔迹数量。
XCTAssertTrue(
    engine.selectStrokes(withIDs: [firstStroke.id, secondStroke.id])
)
XCTAssertTrue(
    engine.apply(command: .deselectAll)
)

XCTAssertTrue(engine.undo())
XCTAssertEqual(
    engine.state.selectedStrokeIDs,
    [firstStroke.id, secondStroke.id]
)
XCTAssertEqual(engine.state.document.strokes.count, 2)

XCTAssertTrue(engine.redo())
XCTAssertTrue(engine.state.selectedStrokeIDs.isEmpty)
XCTAssertEqual(engine.state.document.strokes.count, 2)
```

## 最终结果

- 阶段 7 当前工作区已经覆盖：
  - 套索整笔选择；
  - 选中后拖动移动；
  - 显式取消选择；
  - 选择状态进入 engine state；
  - 选择 / 移动与 undo / redo 联动；
  - iPad 编辑器 lasso 工具、overlay 与 palette 接线；
  - 阶段 7 相关测试与 iOS 构建检查。
- 当前仍未提交，工作区保持可继续检查 / 继续推进阶段 8 的状态。
