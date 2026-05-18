# 20260518_172047_CST_hand_drawing_kernel_phase6_pixel_eraser_record

## 记录范围

- 记录内容：
  1. 实施阶段 6 的 pressure 驱动像素橡皮内核。
  2. 把像素擦除写入 stroke-local `eraseMask`，接入 `HandDrawingEditorEngine` 的 undo / dirty region。
  3. 在 iPad 手绘编辑器里接通 `.pixelEraser` 工具选择、Pencil 输入路由、提交预览与增量重绘。
  4. 补齐像素橡皮与增量渲染测试，并修正 `HandDrawingCanvasRenderer` 的 bitmap 生命周期问题。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_172047_CST`
- 说明：
  - 本记录以阶段 5 完成态为基线，结合当前 `git status`、当前 `git diff` 和当前文件内容整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实描述。
  - 对于新增文件，修改前如实记录为“文件不存在”。
  - 工作区里与本阶段无关的其它文件不纳入本记录。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
  - 阶段 5 记录：
    - `commit_records/20260518_163518_hand_drawing_kernel_phase5_ipad_editor_shell_record.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - git commit / push
  - 阶段 7 套索选择

## 修改一：`HandDrawingEditorEngine` 新增像素擦除回写入口，并把局部擦除纳入 dirty region

### 修改前

- engine 只有普通命令、笔迹追加、undo / redo。
- 没有专门的 API 可以把 `eraseMask` 回写到已有 stroke，也没有“旧 bounds / 新 bounds”并集级别的局部脏区标记。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: apply(command:) 邻近区域
// 功能说明: 修改前 engine 只有命令分发与历史操作，缺少把擦除路径写回 stroke.eraseMask 的专用入口。
mutating func apply(command: HandDrawingEditorCommand) {
    switch command {
    case .deselectAll:
        state.selectedStrokeIDs.removeAll()
    }
}

// 修改前不存在:
// - upsertErasePaths(_:recordUndo:)
// - resolvedDirtyRegion(oldBounds:newBounds:)
// - upsertErasePath(_:into:)
```

### 修改后

- 新增 `upsertErasePaths(_:recordUndo:)`，把一组 `HandDrawingErasePath` 按 stroke ID 写回 `eraseMask`。
- 首次擦除写入时才记录 undo snapshot，连续移动过程中复用同一次历史快照。
- 用旧 bounds 与新 bounds 的并集标记 dirty region，避免整张纸全量重绘。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: upsertErasePaths(_:recordUndo:) / resolvedDirtyRegion(oldBounds:newBounds:) / upsertErasePath(_:into:)
// 功能说明: 修改后 engine 可以把像素橡皮生成的局部擦除路径写进 stroke.eraseMask，
// 同时精确标记旧/新包围盒并集，供增量渲染链只刷新受影响区域。
@discardableResult
mutating func upsertErasePaths(
    _ pathsByStrokeID: [UUID: [HandDrawingErasePath]],
    recordUndo: Bool = true
) -> Set<UUID> {
    let targetStrokeIndexes = state.document.strokes.indices.filter { index in
        let strokeID = state.document.strokes[index].id
        guard let paths = pathsByStrokeID[strokeID] else {
            return false
        }
        return paths.isEmpty == false
    }
    guard targetStrokeIndexes.isEmpty == false else {
        return []
    }

    if recordUndo {
        recordSnapshotForUndo()
    }

    var mutatedStrokeIDs: Set<UUID> = []
    for index in targetStrokeIndexes {
        let oldBounds = state.document.strokes[index].bounds
        for path in pathsByStrokeID[state.document.strokes[index].id] ?? [] {
            upsertErasePath(path, into: &state.document.strokes[index])
        }
        let newBounds = state.document.strokes[index].bounds
        dirtyRegionTracker.markDirty(
            resolvedDirtyRegion(oldBounds: oldBounds, newBounds: newBounds)
        )
        mutatedStrokeIDs.insert(state.document.strokes[index].id)
    }

    return mutatedStrokeIDs
}
```

## 修改二：新增 `HandDrawingPixelEraserToolController`，正式生成 pressure 驱动的 stroke-local 擦除路径

### 修改前

- 项目里没有像素橡皮控制器。
- 编辑链路虽然已有 `eraseMask` 数据结构，但没有 controller 把 Pencil 采样转换成可持续追加的 `HandDrawingErasePath`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前项目里没有像素橡皮控制器，Pencil 输入无法生成 pressure 驱动的 stroke-local eraseMask。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingPixelEraserToolController`。
- `makeEraseSample(...)` 根据 `sample.force` 动态放大/缩小橡皮半径。
- `process(...)` 负责：
  - 命中检测；
  - 连续命中时复用同一路径 ID；
  - 离开后重新命中时拆分成新的 `erasePath`；
  - 把本次更新交给 `engine.upsertErasePaths(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingPixelEraserToolController.swift
// 函数名: process(samples:baseSize:engine:) / makeEraseSample(from:baseSize:) / strokeIntersectsEraseSample(_:eraseSample:)
// 功能说明: 修改后像素橡皮控制器负责把 Pencil 采样转换成带压力半径的擦除点，
// 并按命中结果维护连续/离散 erasePath，再写回每一笔 stroke 的局部 eraseMask。
private mutating func process(
    samples: [HandDrawingInputSample],
    baseSize: CGFloat,
    engine: inout HandDrawingEditorEngine
) {
    guard samples.isEmpty == false else {
        return
    }

    var updatedPathsByStrokeID: [UUID: [HandDrawingErasePath]] = [:]
    let document = engine.state.document

    for sample in samples {
        let eraseSample = makeEraseSample(from: sample, baseSize: baseSize)
        let hitStrokeIDs: Set<UUID> = Set(
            document.strokes.compactMap { stroke in
                guard strokeIntersectsEraseSample(stroke, eraseSample: eraseSample) else {
                    return nil
                }
                return stroke.id
            }
        )

        // 功能注释: 当前采样未命中的笔迹，结束其“开放中的” erasePath，避免下一次重新命中时错误续写。
        for strokeID in openPathIDByStrokeID.keys where hitStrokeIDs.contains(strokeID) == false {
            openPathIDByStrokeID.removeValue(forKey: strokeID)
        }

        for strokeID in hitStrokeIDs {
            let pathID = resolvedPathID(
                for: strokeID,
                hitInPreviousSample: previousSampleHitStrokeIDs.contains(strokeID)
            )
            var strokePaths = strokePathsByID[strokeID] ?? [:]
            var erasePath = strokePaths[pathID] ?? HandDrawingErasePath(id: pathID, samplePoints: [])
            if erasePath.samplePoints.last != eraseSample {
                erasePath.samplePoints.append(eraseSample)
            }
            strokePaths[pathID] = erasePath
            strokePathsByID[strokeID] = strokePaths
            updatedPathsByStrokeID[strokeID, default: []].append(erasePath)
        }

        previousSampleHitStrokeIDs = hitStrokeIDs
    }

    _ = engine.upsertErasePaths(
        updatedPathsByStrokeID,
        recordUndo: hasAppliedMutation == false
    )
}

private func makeEraseSample(
    from sample: HandDrawingInputSample,
    baseSize: CGFloat
) -> HandDrawingEraseSamplePoint {
    let clampedForce = min(max(sample.force, 0.05), 1)
    let pressureScale = 0.5 + clampedForce
    let radius = max((baseSize * pressureScale) / 2, 0.25)
    return HandDrawingEraseSamplePoint(
        point: sample.location,
        radius: Double(radius),
        opacity: 1
    )
}
```

## 修改三：`HandDrawingEditorCoordinator` 接通像素橡皮工具、Pencil 输入路由与提交预览

### 修改前

- `selectedTool` 虽然枚举里已有 `.pixelEraser`，但 coordinator 实际只支持 brush。
- `handlePencilStrokeBegan / Moved / Ended` 只处理画笔。
- 撤销、重做、取消时没有橡皮会话状态。
- `committedImage` 走 full preview render 路径；空白提交依赖 `document.isEmpty`，不能覆盖“笔迹全被局部擦空但文档仍有 stroke”这一类情况。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: selectTool(_:) / handlePencilStrokeBegan(_:) / refreshCommittedImageAndPublishState()
// 功能说明: 修改前 coordinator 只把 brush 当作真正可用工具，像素橡皮按钮虽存在，但没有输入路由和增量重绘链路。
func selectTool(_ tool: HandDrawingEditorTool) {
    switch tool {
    case .brush:
        selectedTool = tool
    case .pixelEraser, .lasso:
        return
    }
    publishPaletteState()
}

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    guard selectedTool == .brush else {
        return
    }
    activeStrokeBrush = currentBrushStyle
    activeStrokeSamples = [sample]
    publishSurfaceState()
}

// 修改前 committedImage 通过 previewRenderer 全量生成，
// 提交时空白判断直接依赖 currentDocument.isEmpty。
```

### 修改后

- `selectTool(_:)` 正式接通 `.pixelEraser`，切工具时清理草稿笔迹与橡皮会话。
- Pencil 输入按 `selectedTool` 分流到 brush 或 pixel eraser controller。
- undo / redo / cancel / commit 统一收口活跃的橡皮状态。
- `refreshCommittedImageAndPublishState(...)` 读取 dirty region，只做局部刷新。
- 提交阶段用 preview 图像的 alpha 是否全空来决定 `isEmpty`，避免“文档结构不空但视觉已空”的误判。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: selectTool(_:) / handlePencilStrokeBegan(_:) / handlePencilStrokeMoved(_:) / handlePencilStrokeEnded(_:)
// 功能说明: 修改后 coordinator 正式把像素橡皮作为编辑工具接入，
// Pencil 采样会按当前工具分流到 brush 或 pixelEraser controller。
func selectTool(_ tool: HandDrawingEditorTool) {
    switch tool {
    case .brush, .pixelEraser:
        selectedTool = tool
        clearActiveStroke()
        pixelEraserToolController.endErasing()
    case .lasso:
        return
    }
    publishSurfaceState()
    publishPaletteState()
}

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    switch selectedTool {
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
        refreshCommittedImageAndPublishState()
    case .lasso:
        return
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: refreshCommittedImageAndPublishState(forceFullRender:) / makeCommitPreviewImage(for:)
// 功能说明: 修改后 committedImage 走增量 canvasRenderer，
// 提交预览仍走 previewRenderer，但空白判断改成“实际像素是否全透明”。
private func refreshCommittedImageAndPublishState(
    forceFullRender: Bool = false
) {
    let dirtyRegion = forceFullRender
        ? engine.state.document.paperBounds
        : engine.consumeDirtyRegion()
    guard forceFullRender || dirtyRegion != nil else {
        return
    }
    committedImage = try canvasRenderer.render(
        document: engine.state.document,
        dirtyRegion: dirtyRegion
    )
}

private func makeCommitPreviewImage(
    for document: HandDrawingDocument
) throws -> CGImage {
    guard document.isEmpty == false else {
        return try CanvasHandDrawingPreviewAssetFactory
            .makeTransparentPreview(for: editorContext.paper)
    }
    return try previewRenderer.renderPreviewImage(for: document, scale: 1)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: isPreviewVisuallyEmpty(_:)
// 功能说明: 修改后新增“按 alpha 扫描 preview 图像”的空白判断，
// 解决 stroke 仍存在但已被局部 eraseMask 全部擦空时 document.isEmpty 不准确的问题。
static func isPreviewVisuallyEmpty(
    _ image: CGImage
) -> Bool {
    guard
        let dataProvider = image.dataProvider,
        let data = dataProvider.data,
        let bytes = CFDataGetBytePtr(data)
    else {
        return false
    }

    let bytesPerPixel = 4
    let pixelCount = image.width * image.height
    for pixelIndex in 0..<pixelCount {
        let alphaOffset = (pixelIndex * bytesPerPixel) + 3
        if bytes[alphaOffset] > 0 {
            return false
        }
    }
    return true
}
```

## 修改四：新增 `HandDrawingCanvasRenderer`，实现脏区重绘，并修正 bitmap 所有权根因

### 修改前

- 项目里没有增量 canvas renderer。
- `committedImage` 只能通过 preview renderer 全量生成。
- 没有专门的持久 bitmap canvas，自然也没有 dirty region 局部清理、局部重绘和输出图像所有权控制。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前阶段 5 完成态下，还不存在专门服务编辑器 committedImage 的增量 canvas renderer。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingCanvasRenderer` 作为编辑器 committedImage 的位图内核。
- 当前定稿版不是让 Quartz 隐式持有 backing store，而是 renderer 自己持有 `bitmapBuffer`：
  - `makeBitmapStorage(...)` 分配像素缓冲区并让 `CGContext` 借用；
  - `deinit` 显式 `free(bitmapBuffer)`；
  - `render(...)` 只清理 dirty rect，并裁剪后重绘相交 stroke；
  - `makeOwnedImage(...)` 再拷贝一份输出图像，避免返回图像和内部持久缓冲共享所有权。
- 这一版是为了解决定点测试中暴露出的 renderer 析构期 `pointer being freed was not allocated` 根因。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: init(paperSize:backgroundColor:) / deinit / render(document:dirtyRegion:)
// 功能说明: 修改后 renderer 持有一块长期存在的 bitmapBuffer，
// 每次只清理 dirty rect，并把与脏区相交的 stroke 重绘进同一张 committed canvas。
final class HandDrawingCanvasRenderer {
    private let backgroundColor: HandDrawingColor?
    private var paperSize: CGSize
    private var bitmapBuffer: UnsafeMutableRawPointer
    private var bitmapContext: CGContext

    init(
        paperSize: CGSize,
        backgroundColor: HandDrawingColor? = nil
    ) throws {
        self.backgroundColor = backgroundColor
        self.paperSize = paperSize
        let resolvedStorage = try Self.makeBitmapStorage(for: paperSize)
        bitmapBuffer = resolvedStorage.buffer
        bitmapContext = resolvedStorage.context
        clear(region: CGRect(origin: .zero, size: paperSize))
    }

    deinit {
        free(bitmapBuffer)
    }

    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect? = nil
    ) throws -> CGImage {
        let renderRegion = resolvedRenderRegion(dirtyRegion, paperBounds: document.paperBounds)
        clear(region: renderRegion)
        bitmapContext.saveGState()
        bitmapContext.addRect(renderRegion)
        bitmapContext.clip()

        for stroke in document.strokes where stroke.isEmpty == false {
            guard let strokeBounds = stroke.bounds, strokeBounds.intersects(renderRegion) else {
                continue
            }
            HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
        }

        bitmapContext.restoreGState()
        return try Self.makeOwnedImage(from: bitmapContext)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: makeBitmapStorage(for:) / makeOwnedImage(from:)
// 功能说明: 修改后 renderer 主动管理 bitmap 内存和输出图像拷贝，
// 避免 CGContext / CGImage 在析构阶段共享不透明 backing store 导致双重释放或非法释放。
private static func makeBitmapStorage(
    for size: CGSize
) throws -> (buffer: UnsafeMutableRawPointer, context: CGContext) {
    let width = max(Int(ceil(size.width)), 1)
    let height = max(Int(ceil(size.height)), 1)
    let bytesPerRow = width * 4
    let byteCount = bytesPerRow * height
    guard let buffer = calloc(byteCount, 1) else {
        throw HandDrawingCanvasRendererError.failedToAllocateBitmapBuffer(
            width: width,
            height: height
        )
    }

    guard let context = CGContext(
        data: buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        free(buffer)
        throw HandDrawingCanvasRendererError.failedToCreateBitmapContext(
            width: width,
            height: height
        )
    }

    return (buffer, context)
}

private static func makeOwnedImage(
    from context: CGContext
) throws -> CGImage {
    let byteCount = context.bytesPerRow * context.height
    guard let copiedBuffer = malloc(byteCount) else {
        throw HandDrawingCanvasRendererError.failedToAllocateImageBuffer
    }
    memcpy(copiedBuffer, context.data, byteCount)
    // 功能注释: 返回图像单独持有一份 buffer，避免和 renderer 内部持久 canvas 共用同一块内存。
    let releaseData: CGDataProviderReleaseDataCallback = { _, data, _ in
        free(UnsafeMutableRawPointer(mutating: data))
    }
    guard let provider = CGDataProvider(
        dataInfo: nil,
        data: copiedBuffer,
        size: byteCount,
        releaseData: releaseData
    ) else {
        free(copiedBuffer)
        throw HandDrawingCanvasRendererError.failedToCreateImageDataProvider
    }

    return CGImage(
        width: context.width,
        height: context.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: context.bytesPerRow,
        space: context.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: context.bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )!
}
```

## 修改五：补齐测试与测试夹具，覆盖像素橡皮和增量渲染一致性

### 修改前

- 没有专门测试 `HandDrawingPixelEraserToolController`。
- 没有专门测试增量 renderer 与 preview renderer 是否在局部擦除后保持像素一致。
- `sampleRGBA(...)` 直接读取 `image.dataProvider.data`，对由 context 生成的 `CGImage` 不够稳健。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前没有“增量 renderer 与 preview renderer 像素一致性”的专门定点测试。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: 无（文件不存在）
// 功能说明: 修改前没有 pressure 半径、命中筛选、离散路径切分等像素橡皮专门测试。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: sampleRGBA(from:x:y:)
// 功能说明: 修改前夹具直接从 dataProvider 取 bytes，对某些 CGContext.makeImage() 返回图像的 provider 生命周期不够稳健。
guard
    let dataProvider = image.dataProvider,
    let data = dataProvider.data
else {
    fatalError("Expected RGBA data provider.")
}
let bytes = CFDataGetBytePtr(data)
```

### 修改后

- 新增 `HandDrawingPixelEraserToolControllerTests`：
  - 验证 pressure 半径；
  - 验证只命中目标 stroke；
  - 验证离散命中会拆成多条 erasePath。
- 新增 `HandDrawingCanvasRendererTests`：
  - 先做一次完整渲染；
  - 再在局部 dirty rect 中执行擦除更新；
  - 与 preview renderer 在定点像素处做 RGBA 对比。
- `sampleRGBA(...)` 改成先把 `CGImage` 画入自建 RGBA context，再取 `context.data`，测试夹具不再依赖外部 provider 的内部实现。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke()
// 功能说明: 修改后测试会验证 force=1 时半径被放大到预期值，
// 同时保证未命中的 stroke 不会被错误写入 eraseMask。
controller.beginErasing(
    with: HandDrawingInputSample(
        location: CGPoint(x: 60, y: 60),
        force: 1,
        timestamp: 0
    ),
    baseSize: 20,
    engine: &engine
)
controller.endErasing()

XCTAssertEqual(mutatedTargetStroke.eraseMask.count, 1)
XCTAssertTrue(untouchedResultStroke.eraseMask.isEmpty)
XCTAssertEqual(
    mutatedTargetStroke.eraseMask[0].samplePoints[0].radius,
    15,
    accuracy: 0.001
)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate()
// 功能说明: 修改后测试会先准备 committed canvas，再只更新一块 dirty rect，
// 最后把 canvasRenderer 输出和 previewRenderer 输出做定点 RGBA 比较，确保增量重绘结果一致。
let renderer = try HandDrawingCanvasRenderer(
    paperSize: initialDocument.paper.size
)
_ = try renderer.render(
    document: initialDocument,
    dirtyRegion: initialDocument.paperBounds
)

let canvasImage = try renderer.render(
    document: updatedDocument,
    dirtyRegion: CGRect(x: 48, y: 48, width: 24, height: 24)
)
let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
    for: updatedDocument,
    scale: 1
)

assertPixelsEqual(
    sampleRGBA(from: canvasImage, x: 60, y: 60),
    sampleRGBA(from: previewImage, x: 60, y: 60)
)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: sampleRGBA(from:x:y:)
// 功能说明: 修改后夹具总是先把输入图像画进自建 RGBA context，
// 再从 context.data 读取像素，规避直接依赖外部 dataProvider 带来的不稳定性。
let bitmapInfo =
    CGImageAlphaInfo.premultipliedLast.rawValue
    | CGBitmapInfo.byteOrder32Big.rawValue
guard
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    )
else {
    fatalError("Expected RGBA bitmap context.")
}
context.draw(
    image,
    in: CGRect(x: 0, y: 0, width: width, height: height)
)
```

## 最终结果

- 阶段 6 当前工作区落地内容已经覆盖：
  - pressure 驱动像素橡皮；
  - `stroke.eraseMask` 局部写回；
  - engine dirty region；
  - iPad 编辑器像素橡皮接线；
  - committedImage 增量重绘；
  - preview / thumbnail / 主画布一致性定点测试；
  - 渲染器 bitmap 生命周期根因修正。
- 当前未提交，工作区仍保持可继续检查 / 提交状态。
