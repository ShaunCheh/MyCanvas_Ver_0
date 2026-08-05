# 20260805_115128_batch_import_grid_phase4_gif_grid_center_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 4：修复阶段 3 将显式 grid 改为“整组中心”语义后，GIF 帧导入仍把 placement 当成“第一格中心”所产生的位置偏移。

本阶段实际修改：

- 将 `CanvasGIFFrameImportBuilder.gridOrigin(...)` 正名为 `gridCenter(...)`。
- 将实际导入帧数传入 placement 计算。
- 复用 `CanvasImportLayoutSolver` 的 `contentSize`，不在 GIF builder 中维护第二套行列公式。
- 让 grid center 位于源 GIF 下方既有 top/leading inset 后的完整网格中心。
- 扩展 builder 测试为 3 帧、2 列、2 行，验证去重排序、完整 grid size 和首帧最终位置保持不变。

本记录参考了创建记录前的 `git status --short`、`git diff --stat`、两个变更文件的当前 `git diff`、测试输出和 IDE lint 结果。下文不粘贴原始 diff，而是根据实际代码整理修改前后的情况。

## 时间戳来源

文件名前缀和本文标题中的时间戳由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒”格式的记录时间戳。
date '+%Y%m%d_%H%M%S'
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260805_115128
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名阶段 4 修改记录。
20260805_115128_batch_import_grid_phase4_gif_grid_center_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
 M MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
 M MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
```

`git diff --stat` 的实际统计：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git diff --stat 的实际输出
 .../Canvas/GIF/CanvasGIFFrameImportBuilder.swift   | 21 ++++++++--
 .../CanvasGIFFrameImportBuilderTests.swift         | 49 ++++++++++++++++++----
 2 files changed, 59 insertions(+), 11 deletions(-)
```

## 问题背景

阶段 3 之后，`CanvasEditorSession` 会把 `CanvasImportPlacement.worldPoint` 作为完整 grid 外框的中心，并将 solver 生成的居中 offsets 加到该点。

GIF builder 修改前仍生成旧语义的 placement：

- x 为源 GIF `worldBounds.minX + leading inset + 单格宽度 / 2`。
- y 为源 GIF `worldBounds.maxY + top inset + 单格高度 / 2`。

这个点实际是第一格中心。把它交给阶段 3 的居中 grid 后，solver 还会继续加上第一格的负偏移，导致整组 GIF 帧向左上移动。

## 修改一：请求构造改用 gridCenter 并传入帧数

### 修改前

`makeImportRequest(...)` 调用 `gridOrigin(...)`，但没有把去重、排序后的实际帧数传入 placement 计算。

```swift
// MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 函数名：CanvasGIFFrameImportBuilder.makeImportRequest(from:gifData:selectedFrameIndices:configuration:sourceDescription:)
// 功能注释：修改前 placement 只依赖单格尺寸和 insets，不知道完整网格包含多少帧。
return CanvasImportRequest(
    images: importedImages,
    placement: .worldPoint(
        gridOrigin(
            for: sourceItem,
            presentationSize: presentationTemplate.size,
            gridConfiguration: boardPlacementGrid
        )
    ),
    layout: .grid(
        columns: boardPlacementGrid.columns,
        horizontalSpacing: boardPlacementGrid.horizontalSpacing,
        verticalSpacing: boardPlacementGrid.verticalSpacing
    ),
    presentationTemplate: presentationTemplate,
    sourceDescription: sourceDescription
)
```

### 修改后

请求构造改为调用 `gridCenter(...)`，并传入 `importedImages.count`。该数量已经经过：

1. 选择索引去重。
2. 索引排序。
3. GIF 帧实际解码。

因此 placement 使用的 item count 与最终 request 的 images 数量完全一致。

```swift
// MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 函数名：CanvasGIFFrameImportBuilder.makeImportRequest(from:gifData:selectedFrameIndices:configuration:sourceDescription:)
// 功能注释：用最终导入帧数计算完整 grid center，layout 配置和 presentation template 保持不变。
return CanvasImportRequest(
    images: importedImages,
    placement: .worldPoint(
        gridCenter(
            for: sourceItem,
            itemCount: importedImages.count,
            presentationSize: presentationTemplate.size,
            gridConfiguration: boardPlacementGrid
        )
    ),
    layout: .grid(
        columns: boardPlacementGrid.columns,
        horizontalSpacing: boardPlacementGrid.horizontalSpacing,
        verticalSpacing: boardPlacementGrid.verticalSpacing
    ),
    presentationTemplate: presentationTemplate,
    sourceDescription: sourceDescription
)
```

## 修改二：从第一格中心改为完整网格中心

### 修改前

`gridOrigin(...)` 只使用单个 presentation size：

```swift
// MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 函数名：CanvasGIFFrameImportBuilder.gridOrigin(for:presentationSize:gridConfiguration:)
// 功能注释：修改前返回源 GIF 下方第一格的中心，而不是完整 grid 的中心。
private static func gridOrigin(
    for sourceItem: CanvasImageItem,
    presentationSize: CGSize,
    gridConfiguration: CanvasGIFFrameImportGridConfiguration
) -> CGPoint {
    let sourceBounds = sourceItem.worldBounds
    return CGPoint(
        x: sourceBounds.minX
            + gridConfiguration.contentInsets.leading
            + presentationSize.width / 2,
        y: sourceBounds.maxY
            + gridConfiguration.contentInsets.top
            + presentationSize.height / 2
    )
}
```

该函数的名称是 `gridOrigin`，但返回值不是网格左上角，也不是新语义下的完整网格中心，本身容易产生歧义。

### 修改后

`gridCenter(...)` 使用与 session 相同的 `CanvasImportLayoutSolver`：

- requested layout 使用 GIF 自己的 columns 和 spacing。
- item bounding sizes 使用 `itemCount` 份相同的 presentation size。
- solver 负责推导实际列数、自动行数和完整 `contentSize`。
- builder 只负责把该 content size 放在源 GIF 下方的既有 inset 后。

```swift
// MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
// 函数名：CanvasGIFFrameImportBuilder.gridCenter(for:itemCount:presentationSize:gridConfiguration:)
// 功能注释：复用统一 solver 计算完整网格尺寸，再返回源 GIF 下方网格外框的中心。
private static func gridCenter(
    for sourceItem: CanvasImageItem,
    itemCount: Int,
    presentationSize: CGSize,
    gridConfiguration: CanvasGIFFrameImportGridConfiguration
) -> CGPoint {
    let resolvedLayout = CanvasImportLayoutSolver().resolve(
        requestedLayout: .grid(
            columns: gridConfiguration.columns,
            horizontalSpacing: gridConfiguration.horizontalSpacing,
            verticalSpacing: gridConfiguration.verticalSpacing
        ),
        itemBoundingSizes: Array(
            repeating: presentationSize,
            count: itemCount
        )
    )
    let sourceBounds = sourceItem.worldBounds
    return CGPoint(
        x: sourceBounds.minX
            + gridConfiguration.contentInsets.leading
            + resolvedLayout.contentSize.width / 2,
        y: sourceBounds.maxY
            + gridConfiguration.contentInsets.top
            + resolvedLayout.contentSize.height / 2
    )
}
```

没有在 GIF builder 内重新实现：

- `usedColumnCount`
- `rowCount`
- grid width/height
- 最后一行规则

这些语义继续以 `CanvasImportLayoutSolver` 为单一来源。

## 首帧位置保持不变的原因

设完整网格宽度为 `gridWidth`，单格宽度为 `cellWidth`：

- builder 返回的中心 x：`sourceMinX + leadingInset + gridWidth / 2`
- solver 返回的第一格 offset x：`(-gridWidth + cellWidth) / 2`
- 两者相加：`sourceMinX + leadingInset + cellWidth / 2`

结果正好等于修改前的第一格中心。

y 方向同理：

- builder center y 使用完整 `gridHeight / 2`
- solver 第一行 offset y 使用 `(-gridHeight + cellHeight) / 2`
- 最终首帧中心仍为 `sourceMaxY + topInset + cellHeight / 2`

因此变化的是 request placement 的语义，不是首帧在画布上的最终位置。

## 修改三：测试从单行两帧扩展为两行三帧

### 修改前

测试输入 `[2, 0, 2]` 去重排序后只导入 frame 0 和 frame 2：

- 导入数量为 2。
- 2 列 grid 只有一行。
- 只采样红色和蓝色。
- placement 断言仍按第一格中心计算。

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：修改前只覆盖两帧单行网格，并把 request placement 断言为第一格中心。
let request = try CanvasGIFFrameImportBuilder.makeImportRequest(
    from: sourceItem,
    gifData: gifData,
    selectedFrameIndices: [2, 0, 2],
    configuration: configuration
)

let importedImages = try request.resolvedImagesForTesting()
XCTAssertEqual(importedImages.count, 2)

let expectedPlacement = CGPoint(
    x: sourceItem.worldBounds.minX + 12 + sourceItem.size.width / 2,
    y: sourceItem.worldBounds.maxY + 18 + sourceItem.size.height / 2
)
```

### 修改后：去重、排序和三帧颜色

输入改为 `[2, 0, 1, 2]`：

- 去重排序结果为 `[0, 1, 2]`。
- 导入数量为 3。
- 第 0、1、2 帧依次验证红、绿、蓝。
- 重复的 frame 2 仍只导入一次。

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：验证乱序加重复索引被规范化为三个有序静态帧。
let request = try CanvasGIFFrameImportBuilder.makeImportRequest(
    from: sourceItem,
    gifData: gifData,
    selectedFrameIndices: [2, 0, 1, 2],
    configuration: configuration
)

let importedImages = try request.resolvedImagesForTesting()
XCTAssertEqual(importedImages.count, 3)
XCTAssertEqual(importedImages[0].assetKind, .staticImage)
XCTAssertEqual(importedImages[1].assetKind, .staticImage)
XCTAssertEqual(importedImages[2].assetKind, .staticImage)

let firstPixel = try sampleGIFFrameImportPixelColor(
    in: importedImages[0].cgImage
)
let secondPixel = try sampleGIFFrameImportPixelColor(
    in: importedImages[1].cgImage
)
let thirdPixel = try sampleGIFFrameImportPixelColor(
    in: importedImages[2].cgImage
)

XCTAssertGreaterThan(firstPixel.red, firstPixel.green)
XCTAssertGreaterThan(firstPixel.red, firstPixel.blue)
XCTAssertGreaterThan(secondPixel.green, secondPixel.red)
XCTAssertGreaterThan(secondPixel.green, secondPixel.blue)
XCTAssertGreaterThan(thirdPixel.blue, thirdPixel.red)
XCTAssertGreaterThan(thirdPixel.blue, thirdPixel.green)
```

### 修改后：断言两列两行完整 grid center

测试配置：

- presentation size：`180 × 120`
- columns：`2`
- horizontal spacing：`30`
- vertical spacing：`40`
- item count：`3`

因此：

- grid width：`180 × 2 + 30 = 390`
- grid height：`120 × 2 + 40 = 280`

request placement 现在断言为完整 `390 × 280` 网格的中心。

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：验证三帧两列形成两行，placement 使用完整 grid size 的中心。
let expectedGridSize = CGSize(
    width: sourceItem.size.width * 2 + 30,
    height: sourceItem.size.height * 2 + 40
)
let expectedPlacement = CGPoint(
    x: sourceItem.worldBounds.minX + 12 + expectedGridSize.width / 2,
    y: sourceItem.worldBounds.maxY + 18 + expectedGridSize.height / 2
)
guard case let .worldPoint(actualPlacement) = request.placement else {
    return XCTFail("Expected worldPoint placement.")
}
XCTAssertEqual(actualPlacement, expectedPlacement)
```

### 修改后：组合 placement 与 solver offset 验证首帧兼容

测试使用 request 的实际 layout 再求解一次 offsets，将 request placement 与第一帧 offset 相加，断言最终首帧中心仍位于旧位置：

```swift
// MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 函数名：testBuilderCreatesStaticGridRequestFromSelectedGIFFrames()
// 功能注释：验证新 grid center 与第一格负 offset 组合后，首帧仍从源 GIF 下方既有 inset 开始。
let resolvedLayout = CanvasImportLayoutSolver().resolve(
    requestedLayout: request.layout,
    itemBoundingSizes: Array(
        repeating: sourceItem.size,
        count: importedImages.count
    )
)
let firstFrameOffset = try XCTUnwrap(
    resolvedLayout.itemOffsets.first
)
XCTAssertEqual(
    CGPoint(
        x: actualPlacement.x + firstFrameOffset.x,
        y: actualPlacement.y + firstFrameOffset.y
    ),
    CGPoint(
        x: sourceItem.worldBounds.minX
            + 12
            + sourceItem.size.width / 2,
        y: sourceItem.worldBounds.maxY
            + 18
            + sourceItem.size.height / 2
    )
)
```

源 GIF 测试项仍带 `.pi / 6` rotation，因此锚点继续基于旋转后的 `sourceItem.worldBounds`，不是未旋转的 `worldFrame`。

## 实际行为变化

- GIF 帧 request 的 `.worldPoint` 从“第一格中心”改为“完整网格中心”。
- 进入阶段 3 的 session 后，首帧最终中心保持修改前位置。
- 多行网格仍从源 GIF 下方 top inset 后开始，不再因居中 offsets 向上偏移。
- leading/top insets 的语义保持不变。
- 帧顺序仍为去重后的升序 frame indices。
- frame presentation size、crop rect 和 `.fixed(0)` rotation policy 没有变化。
- request 仍显式使用 GIF 自己的 `.grid(columns:horizontalSpacing:verticalSpacing:)`。
- `contentInsets.bottom/trailing` 和此前一样，不参与起始 placement 计算。

## 配置保持独立

[`CanvasGIFFrameImportConfiguration.swift`](MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportConfiguration.swift) 没有修改：

- `sharedDefaultColumnCount` 仍为 4。
- selection grid 仍使用 spacing 12、insets 16。
- board placement grid 仍使用 spacing 24、insets 24。
- 普通批量导入的 `CanvasBatchImportLayoutConfiguration` 没有替代 GIF 专用配置。

## 自动验证

### GIF builder 与 session placement 回归

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行 GIF request 构造、GIF 数据来源和阶段 3 session placement 回归。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests"
```

实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- `CanvasGIFFrameImportBuilderTests`：5 个测试通过。
- `CanvasImportedMediaPlacementTests`：4 个测试通过。
- 共 9 个测试通过。

当前 builder 测试已经组合 request placement 与 solver 第一帧 offset 验证位置兼容；完整 request 经 command/session 真正落板的多行闭环测试仍按计划在阶段 5 补齐。

### 差异格式与 IDE 诊断

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查阶段 4 当前差异是否包含空白错误。
git diff --check
```

实际结果：命令退出码为 `0`，没有输出。

IDE lint 检查文件：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 4 IDE lint 检查范围。
MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
```

实际结果：`No linter errors found.`。

## 明确未修改的范围

- 未修改 `CanvasImportLayoutSolver.swift`。
- 未修改 `CanvasEditorSession.swift`。
- 未修改普通批量导入的 4 列配置。
- 未修改 GIF frame service 的解码逻辑。
- 未修改 GIF 编辑器 UI 或选择器布局。
- 未修改 iOS/macOS controller。
- 未修改 history、autosave、storage 或文档格式。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。

## 当前状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态
 M MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameImportBuilder.swift
 M MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
?? commit_records/20260805_115128_batch_import_grid_phase4_gif_grid_center_record.md
```

本次没有创建 Git commit，也没有修改或暂存其他文件。
