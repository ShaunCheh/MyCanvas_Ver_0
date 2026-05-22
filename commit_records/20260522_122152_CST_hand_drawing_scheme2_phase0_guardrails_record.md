# 20260522_122152_CST_hand_drawing_scheme2_phase0_guardrails_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 0`，冻结“`document/history/persistence` 继续是真相源”的边界，并补齐方案二需要的测试护栏。
  - 本次修改只落在测试层，不改任何生产代码逻辑，也不提前抽 `Realtime / Committed` renderer 契约。
  - 本次新增的护栏重点覆盖两类风险：
    - `draft` 与 `commit` 在 `resolved stamp` 级别仍保持一致。
    - 当前 `draft` 光栅化结果，与抬笔后的 `committed canvas` / `preview renderer` 在关键几何采样点上保持一致。
- 涉及文件：
  - `MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_122152_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次 `phase 0` 相关文件执行 `git diff --stat -- ...`，结果为：`3 files changed, 195 insertions(+)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示仅有 `3` 个已跟踪测试文件发生修改。
  - 本次工作区没有额外的生产代码 changes 混入本记录范围。
- 本记录不包含：
  - 方案二 `phase 1` 的 renderer 契约抽象。
  - 任何 `Metal / GPU` 接线。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次方案二 phase 0 markdown 记录文件的时间戳前缀。
20260522_122152_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 汇总本次方案二 phase 0 测试护栏相关文件的 diff 统计。
.../HandDrawingCanvasRendererTests.swift           | 82 ++++++++++++++++++++++
.../HandDrawingCoreTestFixtures.swift              | 39 ++++++++++
.../HandDrawingStrokeBuilderTests.swift            | 74 +++++++++++++++++++
3 files changed, 195 insertions(+)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 记录本次方案二 phase 0 测试护栏相关文件的当前 changes 状态。
M MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
M MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
```

## 当前 changes 摘要

- `HandDrawingCoreTestFixtures.swift` 新增 `renderHandDrawingStrokeImage(...)`，把单笔 `stroke` 的测试光栅化流程抽成公共 helper，并对齐正式 renderer 的抗锯齿与显示坐标配置。
- `HandDrawingStrokeBuilderTests.swift` 新增 `testHandDrawingStrokeBuilderDraftAndCommittedStrokeStayResolvedStampEquivalent()`，把方案二 phase 0 的样本护栏从 `samplePoints` 等价提升到 `resolvedStamps` 与 `bounds` 等价。
- `HandDrawingCanvasRendererTests.swift` 新增 `testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints()`，用 `resolvedStamps` 的中心点与 `probePoints(...)` 作为采样锚点，验证当前 `draft` / `committed` / `preview` 三条渲染路径在关键几何位置上的一致性。
- 本次修改不触碰 `HandDrawingEditorCoordinator`、`HandDrawingCanvasRenderer`、`HandDrawingPreviewRenderer` 的生产逻辑，目的是先把后续方案二/三升级最容易漂移的合同钉成回归测试。

## 修改一：给测试夹具补统一的单笔光栅化 helper

### 修改前

- 测试夹具里已经有 `sampleRGBA(...)` 与 `sampleDisplayedRGBA(...)`，可以采样像素。
- 但没有一个统一入口，能把单根 `HandDrawingStroke` 按当前正式 renderer 的显示约定直接光栅化成 `CGImage`。
- 因此如果要验证 `draft rasterization` 与 `committed / preview` 的一致性，只能在每个测试里重复拼 `CGContext` 逻辑，测试语义会分散。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift（修改前）
// 函数名: sampleRGBA(...) / sampleDisplayedRGBA(...)
// 功能说明: 修改前测试夹具只有像素采样 helper，没有把单根 stroke 直接光栅化成 image 的公共方法。
func sampleRGBA(
    from image: CGImage,
    x: Int,
    y: Int
) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    // ... 省略无关代码 ...
}

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
#endif
```

### 修改后

- 新增 `renderHandDrawingStrokeImage(...)`，专门负责把单根 `stroke` 按当前正式 renderer 的显示约定渲染成 `CGImage`。
- helper 里显式补齐：
  - `interpolationQuality = .high`
  - `setAllowsAntialiasing(true)`
  - `setShouldAntialias(true)`
  - 与正式 canvas renderer 对齐的 display coordinate space
- 后续方案二如果引入 `CPU fallback draft renderer`，这段 helper 可以继续作为测试基准复用。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: renderHandDrawingStrokeImage(_:paperSize:backgroundColor:)
// 功能说明: 修改后统一提供单笔 stroke 的测试光栅化入口，用于比对 draft、committed 与 preview 三条渲染路径。
func renderHandDrawingStrokeImage(
    _ stroke: HandDrawingStroke,
    paperSize: CGSize,
    backgroundColor: HandDrawingColor? = nil
) -> CGImage {
    let width = max(Int(ceil(paperSize.width)), 1)
    let height = max(Int(ceil(paperSize.height)), 1)
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
        fatalError("Expected hand drawing test bitmap context.")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    if let backgroundColor {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    HandDrawingStrokeRasterizer.draw(stroke, in: context)
    guard let image = context.makeImage() else {
        fatalError("Expected rasterized hand drawing test image.")
    }
    return image
}
```

## 修改二：把 draft/commit 护栏从 sample 等价升级到 resolved stamp 等价

### 修改前

- 现有 `testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent()` 只能证明：
  - `draftStroke`
  - `engine.appendStroke(...)` 产生的 `committedStroke`
  - 在 `samplePoints` 级别是一致的
- 但方案二/三真正要共享的是 `BrushDynamics.resolvedStamps(...)` 的输出语义，而不是只看原始 sample 是否一样。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift（修改前）
// 函数名: testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent()
// 功能说明: 修改前只验证 draft 与 committed 在 samplePoints 级别一致，尚未把 resolved stamp 语义钉成护栏。
func testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent() throws {
    // ... 构造 rawSamples / normalizedSamples / draftStroke / committedStroke ...

    XCTAssertEqual(draftStroke.brush, committedStroke.brush)
    XCTAssertEqual(draftStroke.transform, committedStroke.transform)
    XCTAssertEqual(draftStroke.samplePoints, committedStroke.samplePoints)
}
```

### 修改后

- 新增 `testHandDrawingStrokeBuilderDraftAndCommittedStrokeStayResolvedStampEquivalent()`。
- 测试不再只比较 `samplePoints`，而是直接比较：
  - `HandDrawingBrushDynamics.resolvedStamps(for:)`
  - `stroke.bounds`
- 这样后续即便引入 GPU realtime renderer，只要它继续消费当前 `BrushDynamics` 产物，这个护栏就能直接防止“`draft` 和 `commit` 的 stamp 语义漂移”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
// 函数名: testHandDrawingStrokeBuilderDraftAndCommittedStrokeStayResolvedStampEquivalent()
// 功能说明: 修改后把方案二需要共享的 resolved stamp 与 bounds 语义钉成测试护栏，而不只停留在 samplePoints 等价。
func testHandDrawingStrokeBuilderDraftAndCommittedStrokeStayResolvedStampEquivalent() throws {
    let brush = HandDrawingBrushStyle(
        kind: .pen,
        color: HandDrawingColor(red: 0.27, green: 0.41, blue: 0.86, alpha: 1),
        baseSize: 14,
        opacity: 0.92,
        pressureCurveExponent: 1.35,
        minSizeRatio: 0.14,
        maxSizeRatio: 0.96,
        tiltSizeInfluence: 0.72,
        tiltOpacityInfluence: 0.18
    )
    let rawSamples = [
        HandDrawingInputSample(location: CGPoint(x: 20, y: 26), force: 0.28, timestamp: 1),
        HandDrawingInputSample(location: CGPoint(x: 20.4, y: 26.2), force: 0.31, timestamp: 0.95),
        HandDrawingInputSample(
            location: CGPoint(x: 56, y: 48),
            force: 0.76,
            timestamp: 1.1,
            azimuthRadians: 0.35,
            altitudeRadians: .pi / 3
        ),
        HandDrawingInputSample(
            location: CGPoint(x: 92, y: 54),
            force: 0.92,
            timestamp: 1.2,
            azimuthRadians: 0.72,
            altitudeRadians: .pi / 5
        )
    ]
    let normalization = HandDrawingStrokePerformanceProfile
        .brushStroke(for: brush)
        .inputNormalization
    let normalizedSamples = HandDrawingInputNormalizer.normalized(
        rawSamples,
        configuration: normalization
    )
    let draftStroke = try XCTUnwrap(
        HandDrawingStrokeBuilder.makeStroke(
            brush: brush,
            normalizedSamples: normalizedSamples
        )
    )
    var engine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "phase2-stamp-paper",
                size: CGSize(width: 120, height: 120)
            )
        )
    )
    let committedStroke = try XCTUnwrap(
        engine.appendStroke(
            brush: brush,
            samples: rawSamples
        )
    )

    XCTAssertEqual(
        HandDrawingBrushDynamics.resolvedStamps(for: draftStroke),
        HandDrawingBrushDynamics.resolvedStamps(for: committedStroke)
    )
    XCTAssertEqual(draftStroke.bounds, committedStroke.bounds)
}
```

## 修改三：补齐 draft / committed / preview 三条渲染路径的关键点 parity 测试

### 修改前

- `HandDrawingCanvasRendererTests.swift` 已经覆盖了：
  - `canvas vs preview` 的 pressure parity
  - `canvas vs preview` 的 tilt parity
  - `canvas vs preview` 的 layer order / partial erase parity
- 但还没有任何测试直接回答一个关键问题：
  - 当前 `draft` 的 `HandDrawingStrokeRasterizer.draw(...)`
  - 和抬笔后的 `HandDrawingCanvasRenderer`
  - 以及 `HandDrawingPreviewRenderer`
  - 在关键几何位置上是不是一致

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift（修改前）
// 函数名: testHandDrawingCanvasRendererMatchesPreviewRendererForTiltAwareStampOrientation() / assertPixelsEqual(...)
// 功能说明: 修改前文件只验证 committed canvas 与 preview renderer 的一致性，尚无 draft 光栅路径的 parity 测试。
func testHandDrawingCanvasRendererMatchesPreviewRendererForTiltAwareStampOrientation() throws {
    // ... 省略无关代码 ...
}

private func assertPixelsEqual(
    _ lhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
    _ rhs: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8),
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.red, rhs.red, file: file, line: line)
    XCTAssertEqual(lhs.green, rhs.green, file: file, line: line)
    XCTAssertEqual(lhs.blue, rhs.blue, file: file, line: line)
    XCTAssertEqual(lhs.alpha, rhs.alpha, file: file, line: line)
}
```

### 修改后

- 新增 `testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints()`。
- 这条测试没有粗暴地扫整块 `stroke bounds`，而是显式使用：
  - `HandDrawingBrushDynamics.resolvedStamps(for:)`
  - `resolvedStamp.point`
  - `resolvedStamp.probePoints(sampleCount: 4)`
- 也就是说，phase 0 最终冻结的是“当前几何语义定义下的关键采样点 parity”，而不是一个容易因抗锯齿边缘抖动而误报的粗粒度 bounding box 扫描。
- 同时新增 `assertImagesEqual(_:_:at:)`，复用现有 `sampleDisplayedRGBA(...)` 做关键点对比。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests.swift
// 函数名: testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints() / assertImagesEqual(_:_:at:)
// 功能说明: 修改后新增方案二 phase 0 的核心护栏，直接比较 draft、committed、preview 三条渲染路径在 resolved stamp 关键采样点上的显示一致性。
func testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints() throws {
    let stroke = makeHandDrawingTestStroke(
        baseSize: 18,
        samplePoints: [
            CGPoint(x: 20, y: 34),
            CGPoint(x: 60, y: 60),
            CGPoint(x: 100, y: 74)
        ],
        sampleForces: [0.32, 0.78, 0.94],
        sampleAzimuths: [0.18, 0.52, 0.84],
        sampleAltitudes: [.pi / 3, .pi / 5, .pi / 4],
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0.12
    )
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "draft-parity-paper",
            size: CGSize(width: 120, height: 120)
        ),
        strokes: [stroke]
    )
    let draftImage = renderHandDrawingStrokeImage(
        stroke,
        paperSize: document.paper.size
    )
    let renderer = try HandDrawingCanvasRenderer(
        paperSize: document.paper.size
    )
    let canvasImage = try renderer.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
    let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
        for: document,
        scale: 1
    )
    let resolvedStamps = HandDrawingBrushDynamics.resolvedStamps(for: stroke)
    let sampledIndexes = Set([
        0,
        resolvedStamps.count / 2,
        max(resolvedStamps.count - 1, 0)
    ])
    let sampledPoints = sampledIndexes
        .sorted()
        .flatMap { index in
            let resolvedStamp = resolvedStamps[index]
            return [resolvedStamp.point] + resolvedStamp.probePoints(
                sampleCount: 4
            )
        }

    assertImagesEqual(draftImage, canvasImage, at: sampledPoints)
    assertImagesEqual(draftImage, previewImage, at: sampledPoints)
}

private func assertImagesEqual(
    _ lhs: CGImage,
    _ rhs: CGImage,
    at points: [CGPoint],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for point in points {
        let x = min(max(Int(point.x.rounded()), 0), lhs.width - 1)
        let y = min(max(Int(point.y.rounded()), 0), lhs.height - 1)
        assertPixelsEqual(
            sampleDisplayedRGBA(from: lhs, x: x, y: y),
            sampleDisplayedRGBA(from: rhs, x: x, y: y),
            file: file,
            line: line
        )
    }
}
```

## 验证结果

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0.xcodeproj" -scheme MyCanvas_Ver_0 -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 功能说明: 运行方案二 phase 0 的定点护栏回归，验证 sample/stamp 等价、draft/committed/preview parity、以及几何/工具合同未被破坏。
** TEST SUCCEEDED **
Test case 'HandDrawingCanvasRendererTests.testHandDrawingDraftRasterizationMatchesCommittedCanvasAndPreviewAtResolvedStampProbePoints()' passed
Test case 'HandDrawingStrokeBuilderTests.testHandDrawingStrokeBuilderDraftAndCommittedStrokeStayResolvedStampEquivalent()' passed
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent()' passed
Test case 'HandDrawingPixelEraserToolControllerTests.testHandDrawingPixelEraserToolControllerHitTestingUsesTiltedStampFootprint()' passed
Test case 'HandDrawingLassoSelectionTests.testHandDrawingLassoToolControllerUsesTiltedStampFootprintForEnclosure()' passed
Test case 'HandDrawingMoveSelectionTests.testHandDrawingMoveSelectionControllerHitTestingUsesTiltedStampFootprintWithPadding()' passed
```

## 附加检查

- 最近修改文件已执行 `ReadLints`，结果为无报错。
- 本次 phase 0 最终变更面仅限测试文件，未提前引入生产代码重构，因此可以直接作为后续 `phase 1` 抽象 renderer 契约前的稳定基线。

## 结论

- 本次 `phase 0` 没有提前改生产实现，而是先把方案二最容易漂移的合同压成测试。
- 最终形成的护栏分三层：
  - `samplePoints` 等价
  - `resolvedStamps + bounds` 等价
  - `draft / committed / preview` 在 `resolved stamp probe points` 上的像素级一致
- 这样后续进入方案二 `phase 1` 时，就能明确知道：任何 `Realtime / Committed` 后端抽象，只要破坏了这三层中的任一层，都会被当前测试第一时间打出来。
