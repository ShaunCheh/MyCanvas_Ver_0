# 20260518_183205_CST_hand_drawing_display_coordinate_fix_record

## 记录范围

- 记录内容：
  1. 修复手绘编辑器里“写完第一笔后再写第二笔，第一笔显示位置沿 Y 轴上下颠倒”的问题。
  2. 统一 hand drawing 离屏 renderer 输出到图片显示链路时的坐标语义。
  3. 清理 `brush` 结束时残留的 stale draft overlay，避免第一笔结束后旧草稿层继续盖在 committed image 上。
  4. 补显示语义回归测试，避免只比较原始 `CGImage` 像素导致显示坐标问题被漏检。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_183205_CST`
- 说明：
  - 本记录只覆盖刚刚这一轮手绘显示坐标 bugfix，不重复记录阶段 9 的整体测试收口。
  - 本记录以 `commit_records/20260518_181516_CST_hand_drawing_kernel_phase9_regression_guardrails_record.md` 完成态为基线，结合当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
  - 阶段 9 记录：
    - `commit_records/20260518_181516_CST_hand_drawing_kernel_phase9_regression_guardrails_record.md`
- 当前 changes 摘要：
  - 本轮 bugfix 改动：
    - `M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift`
    - `M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
    - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
  - 当前工作区还存在以下非本轮改动：
    - `M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
  - 处理原则：
    - 上述 `xcuserstate` 属于 IDE 用户态文件，非本轮 bugfix 范围，不纳入本记录。
- 验证结果：
  - `xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS,arch=arm64,name=My Mac' -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests -only-testing:MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests`
    - 通过
  - `xcodebuild build -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS Simulator'`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 9 总体测试收口回顾
  - git commit / push
  - `xcuserstate` 用户态文件

## 问题现象与根因

- 现象：
  - 第一笔书写过程中位置看起来正常；
  - 第一笔结束后，旧的 draft overlay 还短暂留在屏幕上；
  - 第二笔一开始，overlay 切换到第二笔，底下的 committed image 才露出来，于是第一笔看起来像沿 Y 轴翻转了。
- 根因分成两层：
  1. `HandDrawingCanvasRenderer` 与 `HandDrawingPreviewRenderer` 的离屏 `CGContext` 输出到图片显示链路时，坐标系仍然是 bitmap 原生语义，没有统一成最终 UI 显示语义。
  2. `HandDrawingEditorCoordinator.handlePencilStrokeEnded(_:)` 在 `brush` 路径里，是先刷新 / 发布 surface state，再通过 `defer` 清理 `activeStroke`，导致旧 draft overlay 暂时掩盖了 committed image 的真实显示问题。

## 修改一：把 hand drawing 离屏 renderer 的最终输出统一为 display-ready 坐标语义

### 修改前

- `HandDrawingCanvasRenderer.makeBitmapStorage(for:)` 创建 bitmap context 后，只设置抗锯齿，不做显示坐标归一。
- `HandDrawingPreviewRenderer.renderPreviewImage(for:scale:backgroundColor:)` 里的 `compositeContext` 也没有做显示坐标归一。
- 这样在“原始 `CGImage` 像素采样”层面看不出问题，但一旦进入 `UIImage` / `NSImage` 的真实显示语义，就可能表现成沿 Y 轴上下颠倒。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: makeBitmapStorage(for:)
// 功能注释: 修改前 canvas renderer 创建位图上下文后直接返回，没有把最终输出图片统一到显示坐标语义。
context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
return (buffer, context)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: renderPreviewImage(for:scale:backgroundColor:)
// 功能注释: 修改前 preview renderer 的 compositeContext 直接参与 compositing，没有做 Y 轴显示坐标归一。
let compositeContext = try makeBitmapContext(
    width: pixelWidth,
    height: pixelHeight
)
let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
if let backgroundColor {
    compositeContext.setFillColor(backgroundColor.cgColor)
    compositeContext.fill(pixelRect)
}
```

### 修改后

- `HandDrawingCanvasRenderer` 新增 `configureDisplayCoordinateSpace(for:height:)`，在 bitmap context 创建后立即执行 `translateBy` + `scaleBy`。
- `HandDrawingPreviewRenderer` 对最终 `compositeContext` 也做同样的 display-ready 坐标归一。
- 这次没有去翻 `drawStroke(...)` 里的 `strokeContext`，而是只翻最终 composite 输出层，避免 stroke image 再次绘回 composite 时发生双翻转。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: makeBitmapStorage(for:) / configureDisplayCoordinateSpace(for:height:)
// 功能注释: 修改后 canvas renderer 生成的 committed image 直接符合图片显示链路的顶点在上坐标语义。
context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
configureDisplayCoordinateSpace(
    for: context,
    height: CGFloat(height)
)
return (buffer, context)

private static func configureDisplayCoordinateSpace(
    for context: CGContext,
    height: CGFloat
) {
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: renderPreviewImage(for:scale:backgroundColor:) / configureDisplayCoordinateSpace(for:height:)
// 功能注释: 修改后 preview renderer 的最终 composite 输出同样统一成 display-ready 坐标，保证 editor / preview / thumbnail 语义一致。
let compositeContext = try makeBitmapContext(
    width: pixelWidth,
    height: pixelHeight
)
configureDisplayCoordinateSpace(
    for: compositeContext,
    height: CGFloat(pixelHeight)
)
let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
if let backgroundColor {
    compositeContext.setFillColor(backgroundColor.cgColor)
    compositeContext.fill(pixelRect)
}

private func configureDisplayCoordinateSpace(
    for context: CGContext,
    height: CGFloat
) {
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
}
```

## 修改二：`brush` 结束时先清掉 draft，再提交 committed image

### 修改前

- `HandDrawingEditorCoordinator.handlePencilStrokeEnded(_:)` 的 `brush` 分支使用 `defer { clearActiveStroke() }`。
- 这意味着 `refreshCommittedImageAndPublishState()` 发布 surface state 时，旧的 `draftStroke` 还在。
- 所以第一笔结束后，屏幕上仍可能先看到旧 draft overlay；到第二笔开始时，旧 draft 被替换，底下的 committed image 才暴露出来，看起来像“第一笔在第二笔开始时突然翻了”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: handlePencilStrokeEnded(_:)
// 功能注释: 修改前在 publish surface state 之后才通过 defer 清 draft，旧 overlay 会短暂滞留。
appendStrokeSamples(samples)
defer {
    clearActiveStroke()
}
guard activeStrokeSamples.isEmpty == false else {
    publishSurfaceState()
    return
}
_ = engine.appendStroke(
    brush: activeStrokeBrush,
    samples: activeStrokeSamples
)
refreshCommittedImageAndPublishState()
```

### 修改后

- 先把 `activeStrokeSamples` 拷到局部变量 `committedStrokeSamples`。
- 立刻 `clearActiveStroke()`，再把 stroke append 进 engine，并刷新 committed image。
- 这样 surface state 发布时，旧 draft overlay 已经清干净，不会再短暂盖住 committed image。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: handlePencilStrokeEnded(_:)
// 功能注释: 修改后先清掉 active draft，再提交最终 stroke，避免 stale draft overlay 干扰显示。
appendStrokeSamples(samples)
guard activeStrokeSamples.isEmpty == false else {
    clearActiveStroke()
    publishSurfaceState()
    return
}
let committedStrokeSamples = activeStrokeSamples
clearActiveStroke()
_ = engine.appendStroke(
    brush: activeStrokeBrush,
    samples: committedStrokeSamples
)
refreshCommittedImageAndPublishState()
```

## 修改三：测试从“原始 `CGImage` 像素采样”升级为“真实显示语义采样”

### 修改前

- `HandDrawingPreviewRendererTests`、`HandDrawingDocumentLoaderTests`、`HandDrawingCanvasRendererTests` 都直接用 `sampleRGBA(...)` 去读原始 `CGImage` 像素。
- `HandDrawingCanvasRendererTests` 之前只在“两个离屏 renderer 之间”做一致性比较。
- 这种测试能证明两个 renderer 彼此一致，但如果两边都用同一种错误显示语义，测试依然会过，挡不住 UI 实际显示时的上下翻转。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() / testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask()
// 功能注释: 修改前 preview tests 直接按原始 CGImage 像素采样，没经过真实图片显示语义。
let image = try renderer.renderPreviewImage(for: document, scale: 1)
let centerPixel = sampleRGBA(from: image, x: 60, y: 60)

let image = try renderer.renderPreviewImage(for: document, scale: 1)
let erasedPixel = sampleRGBA(from: image, x: 60, y: 60)
let preservedPixel = sampleRGBA(from: image, x: 35, y: 60)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate()
// 功能注释: 修改前只比较 canvas renderer 和 preview renderer 的原始像素，一旦两边同错，测试仍然通过。
assertPixelsEqual(
    sampleRGBA(from: canvasImage, x: 60, y: 60),
    sampleRGBA(from: previewImage, x: 60, y: 60)
)
assertPixelsEqual(
    sampleRGBA(from: canvasImage, x: 35, y: 60),
    sampleRGBA(from: previewImage, x: 35, y: 60)
)
```

### 修改后

- 在 `HandDrawingCoreTestFixtures.swift` 里新增 `sampleDisplayedRGBA(...)`：
  - 先通过 `NSImage` + flipped graphics context 走一遍真实显示链路；
  - 再调用原有 `sampleRGBA(...)` 去采样。
- `HandDrawingPreviewRendererTests`、`HandDrawingDocumentLoaderTests`、`HandDrawingCanvasRendererTests` 全部切到 `sampleDisplayedRGBA(...)`。
- 额外新增 `testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates()`，把 stroke 放到画布顶部附近，显式验证最终显示语义不是倒的。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: sampleDisplayedRGBA(from:x:y:) / renderDisplayedImage(from:)
// 功能注释: 修改后测试先走一遍真实图片显示语义，再读像素，避免原始 bitmap 方向掩盖 UI 显示问题。
#if canImport(AppKit)
func sampleDisplayedRGBA(
    from image: CGImage,
    x: Int,
    y: Int
) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    sampleRGBA(
        from: renderDisplayedImage(from: image),
        x: x,
        y: y
    )
}

private func renderDisplayedImage(from image: CGImage) -> CGImage {
    // 功能注释: 其余 context setup 省略，核心是把 CGImage 先绘制到 flipped 的 NSGraphicsContext 再采样。
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(
        cgContext: context,
        flipped: true
    )
    _ = NSImage(
        cgImage: image,
        size: NSSize(width: width, height: height)
    ).draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return displayedImage
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() / testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() / testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences()
// 功能注释: 修改后 preview tests 全部改为按 display-ready 语义采样，验证点和 UI 实际显示保持一致。
let image = try renderer.renderPreviewImage(for: document, scale: 1)
let centerPixel = sampleDisplayedRGBA(from: image, x: 60, y: 60)

let image = try renderer.renderPreviewImage(for: document, scale: 1)
let erasedPixel = sampleDisplayedRGBA(from: image, x: 60, y: 60)
let preservedPixel = sampleDisplayedRGBA(from: image, x: 35, y: 60)

let image = try renderer.renderPreviewImage(for: document, scale: 1)
let thinCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 34)
let thickCenterPixel = sampleDisplayedRGBA(from: image, x: 60, y: 86)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing()
// 功能注释: 修改后 legacy PencilKit -> 自研 document 的 preview 校验也改成显示语义采样。
let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
    for: loadedDocument,
    scale: 1
)
let sampledPixel = sampleDisplayedRGBA(from: previewImage, x: 54, y: 54)
XCTAssertGreaterThan(sampledPixel.alpha, 0)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererAfterPartialEraseUpdate() / testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates()
// 功能注释: 修改后不仅比较 canvas / preview 的显示结果一致，还新增了顶端笔迹的定点测试，直接钉住 Y 轴不能翻转。
assertPixelsEqual(
    sampleDisplayedRGBA(from: canvasImage, x: 60, y: 60),
    sampleDisplayedRGBA(from: previewImage, x: 60, y: 60)
)

func testHandDrawingCanvasRendererProducesDisplayReadyImageWithTopOriginCoordinates() throws {
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "canvas-display-paper",
            size: CGSize(width: 120, height: 120)
        ),
        strokes: [
            HandDrawingStroke(
                brush: HandDrawingBrushStyle(
                    kind: .pen,
                    color: HandDrawingColor(red: 0.82, green: 0.16, blue: 0.18, alpha: 1),
                    baseSize: 12,
                    opacity: 1
                ),
                samplePoints: [
                    HandDrawingSamplePoint(point: CGPoint(x: 24, y: 20), force: 1, timestamp: 0),
                    HandDrawingSamplePoint(point: CGPoint(x: 60, y: 20), force: 1, timestamp: 0.1),
                    HandDrawingSamplePoint(point: CGPoint(x: 96, y: 20), force: 1, timestamp: 0.2)
                ]
            )
        ]
    )
    let image = try renderer.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
    let topPixel = sampleDisplayedRGBA(from: image, x: 60, y: 20)
    let bottomPixel = sampleDisplayedRGBA(from: image, x: 60, y: 100)

    XCTAssertGreaterThan(topPixel.alpha, 0)
    XCTAssertLessThan(bottomPixel.alpha, 16)
}
```

## 结果小结

- 这次 bugfix 没有修改 hand drawing 数据模型和编辑命令语义，修的都是“最终显示坐标”和“surface state 发布时间点”。
- 修复后的目标状态是：
  - 第一笔结束后，committed image 与 draft overlay 的坐标语义一致；
  - 第二笔开始时，不会再因为旧 overlay 消失而露出倒置的第一笔；
  - preview / legacy loader / renderer 测试都按真实显示语义校验，后续同类问题更容易被直接挡住。
