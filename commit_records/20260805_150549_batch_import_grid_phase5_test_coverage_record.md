# 20260805_150549_batch_import_grid_phase5_test_coverage_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 5：补齐纯布局求解器、`CanvasEditorSession` 媒体落板、history 事务和 GIF 帧网格闭环测试。

本阶段实际修改：

- 新增 `CanvasImportLayoutSolverTests.swift`，直接测试纯布局求解器。
- 扩展 `CanvasImportedMediaPlacementTests.swift`，覆盖单图、批量视频、图片视频混合、旋转外包尺寸、board expansion 和整批 undo/redo。
- 扩展 `CanvasGIFFrameImportBuilderTests.swift`，把 GIF request 真正交给 `CanvasCommandExecutor` 和 session 落板。
- 为测试视频增加最小可用的 `CanvasImportedVideoAsset` fixture。
- 为布局测试增加独立的期望网格公式和矩形无重叠断言。
- 没有修改 production Swift 代码。

本记录参考了创建记录前的 `git status --short`、当前 tracked files 的 `git diff`、新增文件的 `git diff --no-index`、差异统计、IDE lint 结果和最终定向测试输出。下文不粘贴原始 diff，而是根据实际代码整理修改前后的情况。

## 时间戳来源

文件名前缀和本文标题中的时间戳由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒”格式的阶段 5 记录时间戳。
date "+%Y%m%d_%H%M%S"
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260805_150549
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名阶段 5 测试记录。
20260805_150549_batch_import_grid_phase5_test_coverage_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
 M MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
 M MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
?? MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
```

两个 tracked test files 的差异统计：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：统计阶段 5 对既有测试文件的修改。
 .../CanvasGIFFrameImportBuilderTests.swift         |  40 +++
 .../CanvasImportedMediaPlacementTests.swift        | 303 +++++++++++++++++++++
 2 files changed, 343 insertions(+)
```

新增 solver test file 的独立差异统计：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：新增纯布局求解器测试文件，共新增 302 行。
 .../CanvasImportLayoutSolverTests.swift            | 302 +++++++++++++++++++++
 1 file changed, 302 insertions(+)
```

## 修改一：新增纯布局求解器测试文件

### 修改前

阶段 2 已新增 `CanvasImportLayoutSolver`，但测试 target 中没有对应的独立测试文件。solver 只能通过 session 和 GIF builder 的间接测试被覆盖。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 测试类：CanvasImportLayoutSolverTests
// 功能注释：修改前该文件和测试类均不存在，没有直接验证纯几何输入输出。
```

### 修改后：覆盖 automatic 的边界数量

新增 `testAutomaticUsesStackedForZeroOrOneAndGridForBatchCounts()`：

- 0 项：解析为 `.stacked`，offsets 为空，content size 为零。
- 1 项：解析为 `.stacked`，唯一 offset 为零，content size 等于 item size。
- 2、4、5、8、9 项：使用普通批量导入配置，并统一交给独立期望值 helper 验证。
- 这些数量覆盖少于一行、刚好一行、最后一行不满、刚好两行和第三行起始。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：CanvasImportLayoutSolverTests.testAutomaticUsesStackedForZeroOrOneAndGridForBatchCounts()
// 功能注释：验证 automatic 的空输入、单项 stacked 和多项固定 4 列动态行规则。
let emptyResult = solver.resolve(
    requestedLayout: .automatic,
    itemBoundingSizes: []
)
XCTAssertEqual(emptyResult.effectiveLayout, .stacked)
XCTAssertEqual(emptyResult.itemOffsets, [])
XCTAssertEqual(emptyResult.contentSize, .zero)

let itemSize = CGSize(width: 100, height: 80)
let singleResult = solver.resolve(
    requestedLayout: .automatic,
    itemBoundingSizes: [itemSize]
)
XCTAssertEqual(singleResult.effectiveLayout, .stacked)
XCTAssertEqual(singleResult.itemOffsets, [.zero])
XCTAssertEqual(singleResult.contentSize, itemSize)

let configuration = CanvasBatchImportLayoutConfiguration.current.grid
for itemCount in [2, 4, 5, 8, 9] {
    let result = solver.resolve(
        requestedLayout: .automatic,
        itemBoundingSizes: Array(
            repeating: itemSize,
            count: itemCount
        )
    )

    try assertGridLayout(
        result,
        itemCount: itemCount,
        cellSize: itemSize,
        configuration: configuration
    )
}
```

### 修改后：覆盖显式列数和不完整行

新增 `testExplicitGridHandlesOneColumnCustomColumnsAndIncompleteRows()`，分别验证：

- 3 项、1 列：每项独占一行。
- 2 项、5 列：实际只使用 2 列，content width 不扩张到 5 个空列。
- 5 项、3 列：形成 2 行，最后一行从 column 0 左对齐。
- 每组都使用不同的 horizontal/vertical spacing，避免测试只绑定默认配置。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：CanvasImportLayoutSolverTests.testExplicitGridHandlesOneColumnCustomColumnsAndIncompleteRows()
// 功能注释：表驱动验证单列、列数大于 item 数量和最后一行不满。
let cases: [
    (
        itemCount: Int,
        configuration: CanvasImportGridConfiguration
    )
] = [
    (
        3,
        CanvasImportGridConfiguration(
            columns: 1,
            horizontalSpacing: 7,
            verticalSpacing: 9
        )
    ),
    (
        2,
        CanvasImportGridConfiguration(
            columns: 5,
            horizontalSpacing: 11,
            verticalSpacing: 13
        )
    ),
    (
        5,
        CanvasImportGridConfiguration(
            columns: 3,
            horizontalSpacing: 17,
            verticalSpacing: 19
        )
    )
]
```

### 修改后：独立计算 content size 和 offsets

新增 `assertGridLayout(...)`，测试侧根据输入重新计算：

- `usedColumnCount`
- `rowCount`
- horizontal/vertical pitch
- 完整 `contentSize`
- 第一格相对完整网格中心的位置
- 每个 index 对应的 row/column offset

这使测试不仅断言 offset 数量，还会验证整个网格关于原点居中，且 offsets 与输入顺序严格一一对应。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：assertGridLayout(_:itemCount:cellSize:configuration:file:line:)
// 功能注释：在测试侧构造完整期望网格，验证 content size、中心和逐项 offset。
let usedColumnCount = min(configuration.columns, itemCount)
let rowCount = ((itemCount - 1) / configuration.columns) + 1
let horizontalPitch =
    cellSize.width + configuration.horizontalSpacing
let verticalPitch =
    cellSize.height + configuration.verticalSpacing
let expectedContentSize = CGSize(
    width: CGFloat(usedColumnCount) * cellSize.width
        + CGFloat(usedColumnCount - 1)
        * configuration.horizontalSpacing,
    height: CGFloat(rowCount) * cellSize.height
        + CGFloat(rowCount - 1)
        * configuration.verticalSpacing
)

let firstCellCenter = CGPoint(
    x: (-expectedContentSize.width + cellSize.width) / 2,
    y: (-expectedContentSize.height + cellSize.height) / 2
)
let expectedOffsets = (0..<itemCount).map { index in
    CGPoint(
        x: firstCellCenter.x
            + CGFloat(index % configuration.columns) * horizontalPitch,
        y: firstCellCenter.y
            + CGFloat(index / configuration.columns) * verticalPitch
    )
}
XCTAssertEqual(result.itemOffsets, expectedOffsets)
```

### 修改后：覆盖横图、竖图、方图与无重叠

新增 `testGridUsesMaximumBoundingSizeWithoutOverlappingMixedAspectItems()`：

- 横图：`320 × 120`
- 竖图：`100 × 300`
- 方图：`200 × 200`
- 期望 cell：`320 × 300`
- 使用 2 列、水平间距 16、垂直间距 20
- 根据每个 item 的实际 size 和 solver offset 生成 frame，逐对断言不相交

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：CanvasImportLayoutSolverTests.testGridUsesMaximumBoundingSizeWithoutOverlappingMixedAspectItems()
// 功能注释：验证 cell 宽高分别取所有媒体外包尺寸的最大值，混合宽高比不会重叠。
let itemBoundingSizes = [
    CGSize(width: 320, height: 120),
    CGSize(width: 100, height: 300),
    CGSize(width: 200, height: 200)
]
let configuration = CanvasImportGridConfiguration(
    columns: 2,
    horizontalSpacing: 16,
    verticalSpacing: 20
)

let result = solver.resolve(
    requestedLayout: .grid(
        columns: configuration.columns,
        horizontalSpacing: configuration.horizontalSpacing,
        verticalSpacing: configuration.verticalSpacing
    ),
    itemBoundingSizes: itemBoundingSizes
)

try assertGridLayout(
    result,
    itemCount: itemBoundingSizes.count,
    cellSize: CGSize(width: 320, height: 300),
    configuration: configuration
)
assertItemsDoNotOverlap(
    sizes: itemBoundingSizes,
    offsets: result.itemOffsets
)
```

### 修改后：覆盖 diagonal 旧公式

新增 `testDiagonalPreservesZeroPositiveAndNegativeIndexTimesStepFormula()`，用 zero、positive、negative 三种 step 验证：

`offset[index] = stepInWorld × index`

这直接保护由旧 `.staggered` 保留下来的 diagonal 行为。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：CanvasImportLayoutSolverTests.testDiagonalPreservesZeroPositiveAndNegativeIndexTimesStepFormula()
// 功能注释：验证 diagonal 对零、正、负 step 都严格保持 index × step 公式。
let steps = [
    CGPoint.zero,
    CGPoint(x: 12, y: 18),
    CGPoint(x: -12, y: -18)
]

for step in steps {
    let result = solver.resolve(
        requestedLayout: .diagonal(stepInWorld: step),
        itemBoundingSizes: itemBoundingSizes
    )

    XCTAssertEqual(
        result.itemOffsets,
        [
            .zero,
            step,
            CGPoint(x: step.x * 2, y: step.y * 2)
        ]
    )
}
```

### 修改后：覆盖无效尺寸和空输入

新增 `testAllLayoutsReturnOneFiniteOffsetPerInputAndHandleEmptyInput()`：

- 对 `.automatic`、`.stacked`、`.diagonal`、`.grid` 全部执行相同契约检查。
- 输入包含 zero、`CGFloat.nan` 和 `CGFloat.infinity`。
- 断言每种布局返回的 offsets 数量与输入数量一致。
- 断言 offset 与 content size 均为有限值。
- 对每种布局再验证空输入返回空 offsets 和零 content size。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：CanvasImportLayoutSolverTests.testAllLayoutsReturnOneFiniteOffsetPerInputAndHandleEmptyInput()
// 功能注释：验证输入数量契约以及 solver 对零值、NaN、Infinity 和空输入的清洗行为。
let invalidSizes = [
    CGSize.zero,
    CGSize(width: CGFloat.nan, height: CGFloat.infinity)
]

for layout in layouts {
    let result = solver.resolve(
        requestedLayout: layout,
        itemBoundingSizes: invalidSizes
    )
    XCTAssertEqual(result.itemOffsets.count, invalidSizes.count)
    XCTAssertTrue(
        result.itemOffsets.allSatisfy {
            $0.x.isFinite && $0.y.isFinite
        }
    )

    let emptyResult = solver.resolve(
        requestedLayout: layout,
        itemBoundingSizes: []
    )
    XCTAssertEqual(emptyResult.itemOffsets, [])
    XCTAssertEqual(emptyResult.contentSize, .zero)
}
```

## 修改二：扩展 Session 媒体落板回归

### 修改前

阶段 4 基线中的 `CanvasImportedMediaPlacementTests` 已覆盖：

- presentation template 几何
- 显式 grid 居中
- 5 张图片的 automatic 4 列网格
- command executor 透传 presentation template

但没有覆盖：

- automatic 单项的 camera center
- 批量视频
- 图片和视频混合
- 媒体顺序及连续 zIndex
- rotation 后的外包尺寸避让
- board expansion
- 整批一次 undo/redo

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 测试类：CanvasImportedMediaPlacementTests
// 功能注释：修改前没有视频、混合媒体、旋转避让、扩板和 history 的批量导入测试。
```

### 修改后：单项 automatic 保持 camera center

新增 `testAppendImportedMediaAutomaticSingleItemUsesCameraCenter()`，设置非零 camera center 和非 1 倍 zoom，调用默认 `.automatic` 与默认 `.cameraCenter`，断言单项仍直接位于 camera center。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaAutomaticSingleItemUsesCameraCenter()
// 功能注释：防止批量网格规则影响单项 automatic 导入。
let cameraCenter = CGPoint(x: -240, y: 360)
session.camera = CanvasCamera(
    center: cameraCenter,
    zoomScale: 2,
    viewportSize: CGSize(width: 900, height: 700)
)

let importedItems = session.appendImportedMedia([.image(image)])

XCTAssertEqual(importedItems.count, 1)
XCTAssertEqual(importedItems[0].center, cameraCenter)
```

### 修改后：批量视频使用 camera-centered 4 列网格

新增 `testAppendImportedMediaAutomaticVideoBatchUsesCameraCenteredGrid()`：

- 构造 5 个不同 filename 和 poster time 的视频。
- 不传 placement 和 layout，走默认 `.cameraCenter + .automatic`。
- 断言 5 项都保持 video identity。
- 断言 filename 和 poster time 与输入顺序一致。
- 断言前 4 项在第一行，第 5 项回到 column 0。
- 断言完整网格水平和垂直中心等于 camera center。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaAutomaticVideoBatchUsesCameraCenteredGrid()
// 功能注释：验证视频元数据不被网格求解改变，并且完整视频网格以 camera center 为锚点。
let importedItems = session.appendImportedMedia(
    videos.map(CanvasImportItem.video)
)

XCTAssertEqual(importedItems.count, videos.count)
XCTAssertTrue(importedItems.allSatisfy(\.isVideo))
XCTAssertEqual(
    importedItems.compactMap(\.sourceVideoFilename),
    videos.map(\.videoSource.sourceVideoFilename)
)
XCTAssertEqual(
    importedItems.compactMap(\.posterTimeSeconds),
    videos.map(\.posterTimeSeconds)
)
XCTAssertEqual(
    (importedItems[0].center.x + importedItems[3].center.x) / 2,
    importCenter.x
)
XCTAssertEqual(
    (importedItems[0].center.y + importedItems[4].center.y) / 2,
    importCenter.y
)
```

### 修改后：混合媒体保持顺序、zIndex 与 worldPoint 中心

新增 `testAppendImportedMediaAutomaticMixedBatchPreservesOrderAndZIndexes()`：

- 输入顺序为图片、视频、图片、视频、图片。
- 媒体包含横向、纵向、方形宽高比。
- 使用 `.worldPoint` 作为完整网格中心。
- 断言 `isVideo` 序列与输入一致。
- 断言两个视频 filename 顺序一致。
- 断言 zIndex 为连续的 `0...4`。
- 断言 scene ordered item IDs 与 import 返回顺序一致。
- 按实际最大宽高计算 pitch，验证 4 列、第二行、整体居中和无重叠。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaAutomaticMixedBatchPreservesOrderAndZIndexes()
// 功能注释：验证混合媒体共享同一个 4 列 grid，同时保留媒体身份、输入顺序和层级。
let importItems: [CanvasImportItem] = [
    .image(portraitImage),
    .video(firstVideo),
    .image(squareImage),
    .video(secondVideo),
    .image(portraitImage)
]

let importedItems = session.appendImportedMedia(
    importItems,
    placement: .worldPoint(importCenter)
)

XCTAssertEqual(
    importedItems.map(\.isVideo),
    [false, true, false, true, false]
)
XCTAssertEqual(
    importedItems.map(\.zIndex),
    [0, 1, 2, 3, 4]
)
XCTAssertEqual(
    session.scene.orderedItems().map(\.id),
    importedItems.map(\.id)
)
assertImportPlacementItemsDoNotOverlap(importedItems)
```

### 修改后：旋转后的 axis-aligned bounds 不重叠

新增 `testAppendImportedMediaGridUsesRotatedBoundingSizeWithoutOverlap()`：

- 两项 presentation size 都为 `220 × 100`。
- 两项 rotation 都为 45 度。
- 显式 grid 使用 2 列和水平间距 18。
- 期望中心距离使用旋转后外包宽度，而不是未旋转 width。
- 最终再用两个 item 的实际 `worldBounds` 验证不相交。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaGridUsesRotatedBoundingSizeWithoutOverlap()
// 功能注释：验证 session 把旋转后的轴对齐外包尺寸传给 solver。
let expectedBoundingWidth =
    template.size.width * abs(cos(rotationRadians))
    + template.size.height * abs(sin(rotationRadians))
XCTAssertEqual(
    importedItems[1].center.x - importedItems[0].center.x,
    expectedBoundingWidth + spacing,
    accuracy: 0.0001
)
assertImportPlacementItemsDoNotOverlap(importedItems)
```

### 修改后：完整网格触发 board expansion

新增 `testAppendImportedMediaExpandsBoardToContainEntireGrid()`：

- 初始 board 为以原点为中心的 `100 × 100`。
- 将 5 项 automatic 网格导入到远离原点的 world point。
- 断言 board width 和 height 都发生扩张。
- 逐项断言最终 board world rect 包含所有 imported item 的实际 world bounds。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaExpandsBoardToContainEntireGrid()
// 功能注释：验证批量网格中的每个 cell 都参与扩板，不能只包含 placement 或第一项。
let importedItems = session.appendImportedMedia(
    Array(repeating: .image(image), count: 5),
    placement: .worldPoint(CGPoint(x: 500, y: -400))
)

let expandedBoardState = try XCTUnwrap(session.boardState)
XCTAssertGreaterThan(
    expandedBoardState.worldRect.width,
    initialBoardState.worldRect.width
)
XCTAssertGreaterThan(
    expandedBoardState.worldRect.height,
    initialBoardState.worldRect.height
)
for item in importedItems {
    XCTAssertTrue(
        expandedBoardState.worldRect.contains(item.worldBounds)
    )
}
```

### 修改后：整批只占一个 history step

新增 `testAppendImportedMediaBatchUsesSingleUndoAndRedoHistoryStep()`：

- reset history 后一次导入 5 项。
- 第一次 undo snapshot 恢复空 scene。
- 第二次 undo 返回 `nil`，证明没有每个 cell 单独记录。
- 一次 redo 恢复全部 5 个原 item IDs。
- 第二次 redo 返回 `nil`。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaBatchUsesSingleUndoAndRedoHistoryStep()
// 功能注释：验证批量导入事务仍是一条 history 记录。
let importedItems = session.appendImportedMedia(
    Array(repeating: .image(image), count: 5),
    placement: .worldPoint(CGPoint(x: 100, y: 200))
)
let importedItemIDs = importedItems.map(\.id)

let undoSnapshot = try XCTUnwrap(session.undoHistorySnapshot())
session.applyBoardHistorySnapshot(undoSnapshot)
XCTAssertTrue(session.scene.orderedItems().isEmpty)
XCTAssertNil(session.undoHistorySnapshot())

let redoSnapshot = try XCTUnwrap(session.redoHistorySnapshot())
session.applyBoardHistorySnapshot(redoSnapshot)
XCTAssertEqual(
    session.scene.orderedItems().map(\.id),
    importedItemIDs
)
XCTAssertNil(session.redoHistorySnapshot())
```

### 修改后：增加视频 fixture 和通用重叠断言

新增 `makeImportPlacementTestVideo(...)`，使用 transient static poster 和 persisted video filename 构造测试视频；不需要真实解码视频文件即可验证导入布局和元数据。

新增 `assertImportPlacementItemsDoNotOverlap(...)`，逐对比较实际 `worldBounds`。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：makeImportPlacementTestVideo(width:height:filename:posterTimeSeconds:)
// 功能注释：构造带 poster、video source 和 poster time 的最小测试视频资产。
private func makeImportPlacementTestVideo(
    width: Int,
    height: Int,
    filename: String,
    posterTimeSeconds: Double
) throws -> CanvasImportedVideoAsset {
    let posterImage = try makeImportPlacementTestImage(
        width: width,
        height: height
    )
    return CanvasImportedVideoAsset(
        asset: CanvasImageAsset.transientStaticImage(
            cgImage: posterImage
        ),
        videoSource: CanvasVideoSource(
            assetReference: .persisted(filename: filename)
        ),
        posterTimeSeconds: posterTimeSeconds
    )
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：assertImportPlacementItemsDoNotOverlap(_:file:line:)
// 功能注释：使用最终落板项的旋转后 world bounds 逐对验证没有重叠。
for firstIndex in items.indices {
    for secondIndex in items.indices where secondIndex > firstIndex {
        XCTAssertFalse(
            items[firstIndex].worldBounds.intersects(
                items[secondIndex].worldBounds
            )
        )
    }
}
```

## 修改三：补齐 GIF request 到 Session 的落板闭环

### 修改前

阶段 4 的 `testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()` 已验证：

- 选中帧去重和排序
- 静态帧颜色
- request grid center
- request layout 配置
- presentation template
- request placement 加 solver 第一格 offset 后的理论首帧位置

但测试在 request/model 层结束，没有执行 `.importMedia(request)`，因此没有证明 command executor 和 session 真正落板后仍得到相同位置。

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：修改前测试在 request 和 solver 断言后结束，没有执行真正的 import command。
let template = try XCTUnwrap(request.presentationTemplate)
XCTAssertEqual(template.size, sourceItem.size)
XCTAssertEqual(template.cropRectNormalized, cropRect)
```

### 修改后

同一个测试继续：

1. 创建 `CanvasEditorSession`。
2. 创建 `CanvasCommandExecutor`。
3. 执行 `.importMedia(request)`。
4. 从 session scene 读取最终 imported items。
5. 断言首帧仍位于源 GIF 下方既有 leading/top inset 后。
6. 断言第二帧位于第一帧右侧一个 horizontal pitch。
7. 断言第三帧回到第一列并向下一个 vertical pitch。
8. 断言 size、crop、rotation 和非视频身份均保持 request template 语义。

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：把 builder request 经 command executor 真正导入 session，验证最终三帧两行位置。
let session = makeGIFFrameImportTestSession()
let executor = CanvasCommandExecutor(session: session)
CanvasGIFFrameImportBuilderTestRetainer.executors.append(executor)
XCTAssertNotNil(executor.execute(.importMedia(request)))

let importedItems = session.scene.orderedItems()
XCTAssertEqual(importedItems.count, importedImages.count)
let expectedFirstFrameCenter = CGPoint(
    x: sourceItem.worldBounds.minX
        + 12
        + sourceItem.size.width / 2,
    y: sourceItem.worldBounds.maxY
        + 18
        + sourceItem.size.height / 2
)
XCTAssertEqual(importedItems[0].center, expectedFirstFrameCenter)
XCTAssertEqual(
    importedItems[1].center,
    CGPoint(
        x: expectedFirstFrameCenter.x + sourceItem.size.width + 30,
        y: expectedFirstFrameCenter.y
    )
)
XCTAssertEqual(
    importedItems[2].center,
    CGPoint(
        x: expectedFirstFrameCenter.x,
        y: expectedFirstFrameCenter.y + sourceItem.size.height + 40
    )
)
```

### Executor 生命周期处理

首次增加闭环时，executor 仅由测试函数局部变量持有。在当前 macOS 12.4 deployment target 的测试 back-deploy 环境中，测试结束析构 `CanvasCommandExecutor` 时触发 Swift concurrency runtime 的 invalid free，崩溃栈位于 `CanvasCommandExecutor.__deallocating_deinit`，不是布局断言失败。

项目既有 `CanvasImportedMediaPlacementTests` 已使用静态 retainer 避免同一测试运行器生命周期问题。因此 GIF 测试采用相同模式，增加 executor retainer。

修改前：

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型名：CanvasGIFFrameImportBuilderTestRetainer
// 功能注释：修改前只延长 session 生命周期，没有保存 command executor。
private enum CanvasGIFFrameImportBuilderTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}
```

修改后：

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型名：CanvasGIFFrameImportBuilderTestRetainer
// 功能注释：在测试进程内延长 executor 生命周期，规避 back-deploy 析构运行时问题。
private enum CanvasGIFFrameImportBuilderTestRetainer {
    static var sessions: [CanvasEditorSession] = []
    static var executors: [CanvasCommandExecutor] = []
}
```

## 验证过程中修正的问题

### `nan` 类型推断歧义

solver 测试初稿使用 `.nan` 和 `.infinity`。Swift 同时可见 `CGFloat` 与 `Double` 的静态成员，`CGSize` 初始化位置出现 `ambiguous use of 'nan'` 编译错误。

修改前：

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：testAllLayoutsReturnOneFiniteOffsetPerInputAndHandleEmptyInput()
// 功能注释：未显式指定浮点类型，Swift 无法确定 nan/infinity 属于 CGFloat 还是 Double。
CGSize(width: .nan, height: .infinity)
```

修改后：

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：testAllLayoutsReturnOneFiniteOffsetPerInputAndHandleEmptyInput()
// 功能注释：显式使用 CGFloat，匹配 CGSize 的参数类型。
CGSize(width: CGFloat.nan, height: CGFloat.infinity)
```

同时为读取 main-actor isolated import layout 类型的两个测试 helper 增加 `@MainActor`，消除 Swift 6 actor isolation 警告。

## 自动验证

### 最终导入布局相关回归

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行布局模型、纯 solver、session placement/history 和 GIF builder/落板闭环测试。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests"
```

最终实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- `CanvasImportRequestModelTests`：5 个测试通过。
- `CanvasImportLayoutSolverTests`：5 个测试通过。
- `CanvasImportedMediaPlacementTests`：10 个测试通过。
- `CanvasGIFFrameImportBuilderTests`：5 个测试通过。
- 共 25 个测试通过。

### 差异格式检查

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查 tracked 阶段 5 差异是否包含空白错误。
git diff --check
```

实际结果：命令退出码为 `0`，没有输出。

### IDE lint

检查文件：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 5 IDE lint 检查范围。
MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
```

实际结果：`No linter errors found.`。

## 阶段 5 最终覆盖的业务契约

- automatic 0 项不产生无效坐标。
- automatic 1 项继续 stacked，位于 placement。
- automatic 2、4、5、8、9 项使用固定 4 列和自动行数。
- 少于配置列数时只使用实际列数。
- 最后一行不满时从 column 0 左对齐。
- 完整 grid 以 camera center 或 world point 为中心。
- 单列和显式自定义列数保持可用。
- 横图、竖图、方图及不同尺寸共用最大 cell，不发生重叠。
- session 使用旋转后 axis-aligned bounding size 避免旋转项碰撞。
- diagonal 的 zero、positive、negative step 都保持 `index × step`。
- 图片、视频和混合媒体共用 automatic grid。
- 视频 filename、poster time、媒体顺序和 zIndex 保持不变。
- board expansion 包含完整网格中的每个 item。
- 整批导入只产生一个 undo/redo history step。
- GIF request 经 command 和 session 真正落板后，首帧仍位于源 GIF 下方既有 inset 位置。

## 明确未修改的范围

- 未修改 `CanvasImportLayoutSolver.swift` production 实现。
- 未修改 `CanvasEditorSession.swift` production 实现。
- 未修改 `CanvasImportTypes.swift` 和普通批量导入 4 列配置。
- 未修改 `CanvasGIFFrameImportBuilder.swift` production 实现。
- 未修改 GIF 解码、选择器或编辑器 UI。
- 未修改 iOS/macOS controller 或分享扩展。
- 未修改 storage mapper、文档格式或持久化版本。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。

## 当前状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态
 M MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
 M MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
?? MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
?? commit_records/20260805_150549_batch_import_grid_phase5_test_coverage_record.md
```

本次没有创建 Git commit，也没有暂存文件。
