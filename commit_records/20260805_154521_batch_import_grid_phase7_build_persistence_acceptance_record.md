# 20260805_154521_batch_import_grid_phase7_build_persistence_acceptance_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 7：构建、验收与清理。

本阶段实际修改：

- 扩展 `CanvasImportedMediaPlacementTests.swift`，自动覆盖 1、2、4、5、8、9 项媒体在多种 zoom 下的网格中心、行列位置及无重叠约束。
- 扩展 `CanvasImportedMediaPlacementTests.swift`，验证显式 `.diagonal` 使用现有 24 屏幕点换算时，在不同 zoom 下仍保持 24 屏幕点步长。
- 扩展 `macOSCanvasImportAdapterTests.swift`，增加真实 PNG、animated GIF、H.264 MOV 混合批次的保存、文档检查和新 session 重开闭环。
- 检查生产代码、分享扩展和测试源码中的旧 `staggered` 命名及 session 废弃 helper；没有发现残留，因此没有为了“清理”制造无意义 production diff。
- 顺序执行布局定向测试、导入/history/storage 相关回归、macOS build、iOS Simulator build 和分享扩展 target build。
- 没有修改 production Swift、文档 schema、autosave、UI、平台 adapter 或拖放落点逻辑。

本记录参考了创建记录前的 `git status --short`、`git diff --stat`、`git diff --numstat`、两个测试文件的实际 diff、源码残留搜索、IDE lint、测试输出和构建输出。下文不粘贴原始 git diff，而是按实际代码整理修改前后情况。

## 时间戳来源

文件名前缀和本文标题中的时间戳由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒”格式的阶段 7 记录时间戳。
date "+%Y%m%d_%H%M%S"
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260805_154521
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名阶段 7 修改记录。
20260805_154521_batch_import_grid_phase7_build_persistence_acceptance_record.md
```

目标目录检查：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：确认项目内既有 commit_records 目录存在，本阶段未新建目录。
drwxr-xr-x@ 412 shaun  staff  13184  8  5 15:26 commit_records
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
 M MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
 M MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
```

差异统计：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 7 只增加验收测试，没有 production file diff。
.../CanvasImportedMediaPlacementTests.swift        | 116 +++++++++++++
.../macOSCanvasImportAdapterTests.swift            | 188 +++++++++++++++++++++
2 files changed, 304 insertions(+)
```

`git diff --numstat` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：记录两个测试文件的实际新增行数。
116	0	MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
188	0	MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
```

## 修改一：补齐数量矩阵与 zoom 验收

### 修改前

`CanvasImportedMediaPlacementTests` 已验证 5 项 automatic 导入会形成 4 列网格，但没有在 session 层一次覆盖计划要求的 1、2、4、5、8、9 项，也没有比较不同 zoom 下的 world-space 网格结果。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAppendImportedMediaAutomaticUsesConfiguredFourColumnGrid()
// 功能注释：修改前只用 5 项验证第一行 4 列和第二行首项。
let importedItems = session.appendImportedMedia(
    Array(repeating: .image(image), count: 5),
    placement: .worldPoint(importCenter)
)

XCTAssertEqual(importedItems.count, 5)
```

### 修改后

新增 `testAutomaticGridCountsRemainCenteredAndNonOverlappingAcrossZoomLevels()`：

- item count 固定覆盖 1、2、4、5、8、9。
- zoom 覆盖 0.5、1、2.5。
- 每组都通过真实 `CanvasEditorSession.appendImportedMedia` 落板。
- 独立计算实际列数、自动行数、首格中心和每一项预期中心。
- 每组检查最终 world bounds 不重叠。
- 同一 item count 在不同 zoom 下必须得到相同 world-space centers，确认导入几何不会被相机 zoom 错误地二次换算。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAutomaticGridCountsRemainCenteredAndNonOverlappingAcrossZoomLevels()
// 功能注释：覆盖计划要求的数量矩阵和多种 zoom。
let itemCounts = [1, 2, 4, 5, 8, 9]
let zoomScales: [CGFloat] = [0.5, 1, 2.5]
let importCenter = CGPoint(x: 135, y: -215)
let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid
var baselineCentersByItemCount: [Int: [CGPoint]] = [:]

for zoomScale in zoomScales {
    for itemCount in itemCounts {
        let session = makeImportPlacementTestSession()
        session.camera = CanvasCamera(
            center: importCenter,
            zoomScale: zoomScale,
            viewportSize: CGSize(width: 1200, height: 800)
        )

        let importedItems = session.appendImportedMedia(
            Array(repeating: .image(image), count: itemCount)
        )
        XCTAssertEqual(importedItems.count, itemCount)
    }
}
```

行列与整体中心验收：

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAutomaticGridCountsRemainCenteredAndNonOverlappingAcrossZoomLevels()
// 功能注释：按固定列数和自动行数计算首格中心，并逐项验证 left-to-right、top-to-bottom 位置。
let usedColumnCount = min(
    gridConfiguration.columns,
    itemCount
)
let rowCount =
    ((itemCount - 1) / gridConfiguration.columns) + 1
let expectedFirstCenter = CGPoint(
    x: importCenter.x
        - CGFloat(usedColumnCount - 1) * horizontalPitch / 2,
    y: importCenter.y
        - CGFloat(rowCount - 1) * verticalPitch / 2
)

for (index, importedItem) in importedItems.enumerated() {
    XCTAssertEqual(
        importedItem.center,
        CGPoint(
            x: expectedFirstCenter.x
                + CGFloat(index % gridConfiguration.columns)
                * horizontalPitch,
            y: expectedFirstCenter.y
                + CGFloat(index / gridConfiguration.columns)
                * verticalPitch
        )
    )
}
assertImportPlacementItemsDoNotOverlap(importedItems)
```

不同 zoom 的 world-space 稳定性验收：

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testAutomaticGridCountsRemainCenteredAndNonOverlappingAcrossZoomLevels()
// 功能注释：同一数量在不同 zoom 下保持相同 world-space 布局，屏幕缩放只由 camera transform 负责。
let centers = importedItems.map(\.center)
if let baselineCenters = baselineCentersByItemCount[itemCount] {
    XCTAssertEqual(centers, baselineCenters)
} else {
    baselineCentersByItemCount[itemCount] = centers
}
```

## 修改二：验收显式 diagonal 的 24 屏幕点节奏

### 修改前

阶段 5 已验证 solver 的 `.diagonal(stepInWorld:)` 使用 `index × step`，但 session 测试没有把现有 `duplicateOffsetInWorld()` 与 camera transform 串起来验证不同 zoom 下的屏幕步长。

```swift
// MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests.swift
// 函数名：testDiagonalPreservesZeroPositiveAndNegativeIndexTimesStepFormula()
// 功能注释：修改前已有纯 solver 的 world-space 公式测试，但没有 viewport-space 验收。
XCTAssertEqual(
    result.itemOffsets,
    [
        .zero,
        step,
        CGPoint(x: step.x * 2, y: step.y * 2)
    ]
)
```

### 修改后

新增 `testExplicitDiagonalUsingDuplicateOffsetKeepsTwentyFourPointViewportStep()`：

- zoom 覆盖 0.5、1、2.5、4。
- 使用 `session.duplicateOffsetInWorld()` 生成当前默认 world-space step。
- 显式传入 `.diagonal(stepInWorld:)`。
- 将最终媒体中心转换为 viewport 坐标。
- 连续项 x/y 方向均严格相差 24 屏幕点。

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testExplicitDiagonalUsingDuplicateOffsetKeepsTwentyFourPointViewportStep()
// 功能注释：在多种 zoom 下走 session 和 camera 的完整 diagonal 几何路径。
for zoomScale: CGFloat in [0.5, 1, 2.5, 4] {
    let session = makeImportPlacementTestSession()
    session.camera = CanvasCamera(
        center: CGPoint(x: 40, y: -60),
        zoomScale: zoomScale,
        viewportSize: CGSize(width: 1000, height: 700)
    )
    let diagonalStep = session.duplicateOffsetInWorld()

    let importedItems = session.appendImportedMedia(
        Array(repeating: .image(image), count: 3),
        layout: .diagonal(stepInWorld: diagonalStep)
    )
    let viewportCenters = importedItems.map {
        session.camera.worldToViewport($0.center)
    }
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
// 函数名：testExplicitDiagonalUsingDuplicateOffsetKeepsTwentyFourPointViewportStep()
// 功能注释：验证连续 diagonal 项在 viewport x/y 方向都维持 24 点。
XCTAssertEqual(
    viewportCenters[1].x - viewportCenters[0].x,
    24,
    accuracy: 0.0001
)
XCTAssertEqual(
    viewportCenters[1].y - viewportCenters[0].y,
    24,
    accuracy: 0.0001
)
XCTAssertEqual(
    viewportCenters[2].x - viewportCenters[1].x,
    24,
    accuracy: 0.0001
)
XCTAssertEqual(
    viewportCenters[2].y - viewportCenters[1].y,
    24,
    accuracy: 0.0001
)
```

## 修改三：增加真实混合媒体保存与重开闭环

### 修改前

阶段 6 的 macOS 混合媒体测试已经使用真实 PNG、MOV 和 GIF，能够验证 adapter、import service 和 session 的即时落板结果，但测试在落板后结束，没有写入 `BoardStore`，也没有创建新 session 重开。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testMixedAdapterRequestStaysAutomaticThroughImportServiceAndSession()
// 功能注释：修改前验证 mixed media 当次 session 的媒体身份、中心和无重叠。
let importedItems = session.appendImportedMedia(
    importRequest.items,
    placement: importRequest.placement,
    layout: importRequest.layout,
    presentationTemplate: importRequest.presentationTemplate
)

XCTAssertEqual(importedItems.count, 3)
XCTAssertEqual(
    importedItems.map(\.isVideo),
    [false, true, false]
)
assertmacOSImportAdapterItemsDoNotOverlap(importedItems)
```

### 修改后：构造五项真实媒体批次

新增 `testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()`。

测试生成真实 PNG、animated GIF 和 H.264 MOV，并按以下顺序组成 5 项批次：

1. PNG
2. MOV
3. animated GIF
4. MOV
5. PNG

这会同时覆盖：

- 4 列加第二行。
- 图片、视频、GIF 混合顺序。
- 两个独立持久化视频源。
- camera center 锚点。
- zoom 2.25 下的保存与恢复。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：创建真实媒体 fixture，并生成五项 automatic transfer request。
try writemacOSImportAdapterTestPNG(to: imageURL)
try writemacOSImportAdapterTestVideo(to: videoURL)
try writemacOSImportAdapterTestGIF(to: gifURL)

let transferRequest = try XCTUnwrap(
    macOSCanvasImportAdapter.transferRequest(
        from: [
            imageURL,
            videoURL,
            gifURL,
            videoURL,
            imageURL
        ],
        sourceDescription: "persistence acceptance batch"
    )
)
```

### 修改后：落板前后媒体语义

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：确认 request 仍为 cameraCenter + automatic，并验证五项最终顺序、层级和视频源。
XCTAssertEqual(importRequest.placement, .cameraCenter)
XCTAssertEqual(importRequest.layout, .automatic)
let importedItems = session.appendImportedMedia(
    importRequest.items,
    placement: importRequest.placement,
    layout: importRequest.layout,
    presentationTemplate: importRequest.presentationTemplate
)

XCTAssertEqual(importedItems.count, 5)
XCTAssertEqual(
    importedItems.map(\.isVideo),
    [false, true, false, true, false]
)
XCTAssertEqual(
    importedItems.map(\.zIndex),
    [0, 1, 2, 3, 4]
)
XCTAssertEqual(
    Set(importedItems.compactMap(\.sourceVideoFilename)).count,
    2
)
assertmacOSImportAdapterItemsDoNotOverlap(importedItems)
```

### 修改后：使用正式立即保存入口

测试调用 `saveBoardNow`，而不是让 delayed autosave 与断言竞争。该入口会取消 pending autosave，再由既有 `BoardSaveCoordinator` 串行写入当前 snapshot。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：等待正式立即保存完成后再读取 board document，避免异步保存竞态。
let saveExpectation = expectation(
    description: "Persist automatic import batch"
)
var saveError: Error?
session.saveBoardNow(reason: "persistence acceptance batch") {
    result in
    if case let .failure(error) = result {
        saveError = error
    }
    saveExpectation.fulfill()
}
wait(for: [saveExpectation], timeout: 10)
if let saveError {
    throw saveError
}
```

### 修改后：检查 document record 与资源文件

读取 `BoardStore.loadBoardDocumentEntry` 后逐项验证：

- format version 使用当前 schema。
- ID 和导入顺序不变。
- center 不变。
- size 不变。
- zIndex 不变。
- `sourceVideoFilename` 不变。
- poster 文件实际存在。
- 视频源文件实际存在。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：直接检查持久化 document record 的几何、层级、视频源和资源文件。
let persistedRecords = persistedEntry.document.imageItemRecords
XCTAssertEqual(
    persistedRecords.map(\.id),
    importedItems.map(\.id)
)
for (importedItem, persistedRecord) in zip(
    importedItems,
    persistedRecords
) {
    XCTAssertEqual(
        persistedRecord.center.cgPoint,
        importedItem.center
    )
    XCTAssertEqual(
        persistedRecord.size.cgSize,
        importedItem.size
    )
    XCTAssertEqual(
        persistedRecord.zIndex,
        Double(importedItem.zIndex)
    )
    XCTAssertEqual(
        persistedRecord.sourceVideoFilename,
        importedItem.sourceVideoFilename
    )
}
```

### 修改后：新 session 重开

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：用新的 CanvasEditorSession 载入同一 board，模拟保存、关闭和重开。
let reopenedSession = CanvasEditorSession(
    saveQueueLabel:
        "macOSCanvasImportAdapterTests.Persistence.Reopened",
    logPrefix:
        "[macOSCanvasImportAdapterTests][Persistence][Reopened]",
    userDefaults: userDefaults
)
try reopenedSession.loadBoard(id: boardID)
let reopenedItems = reopenedSession.scene.orderedItems()

XCTAssertEqual(
    reopenedItems.map(\.id),
    importedItems.map(\.id)
)
```

重开后的逐项验收：

```swift
// MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
// 函数名：testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload()
// 功能注释：确认重开后的 center、size、zIndex、视频源以及 camera 状态不变。
for (importedItem, reopenedItem) in zip(
    importedItems,
    reopenedItems
) {
    XCTAssertEqual(reopenedItem.center, importedItem.center)
    XCTAssertEqual(reopenedItem.size, importedItem.size)
    XCTAssertEqual(reopenedItem.zIndex, importedItem.zIndex)
    XCTAssertEqual(
        reopenedItem.sourceVideoFilename,
        importedItem.sourceVideoFilename
    )
}
XCTAssertEqual(reopenedSession.camera.center, cameraCenter)
XCTAssertEqual(reopenedSession.camera.zoomScale, 2.25)
assertmacOSImportAdapterItemsDoNotOverlap(reopenedItems)
```

## 旧命名和废弃 helper 清理检查

检查范围：

- `MyCanvas_Ver_0/**/*.swift`
- `Add To Canvas/**/*.swift`
- `MyCanvas_Ver_0Tests/**/*.swift`

检查关键字：

- `staggered`
- `stagger`
- `resolvedImportLayout`
- `importOffset`
- `gridCellSize`

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查 production Swift 是否还存在旧命名或 session 废弃布局 helper。
rg -i "staggered|stagger|resolvedImportLayout|importOffset|gridCellSize" \
  "MyCanvas_Ver_0" \
  --glob "*.swift"
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查分享扩展和测试 Swift 是否还存在旧命名或废弃 helper。
rg -i "staggered|stagger|resolvedImportLayout|importOffset|gridCellSize" \
  "Add To Canvas" \
  "MyCanvas_Ver_0Tests" \
  --glob "*.swift"
```

实际结果：三个可编译源码范围均无匹配。

历史 `commit_records` 和 `.cursor/plans` 中保留了修改前语义的文字记录；这些不是当前可编译源码，本阶段没有篡改历史记录或计划文件。

## production、schema、autosave、UI 与拖放检查

阶段 7 当前 diff 只有两个测试文件，因此：

- 没有修改 `BoardDocument.swift`，当前文档 schema 没有变化。
- 没有修改 `CanvasEditorSession.swift`，没有新增 autosave 调用。
- 没有修改 iOS/macOS controller 或 adapter。
- 没有修改 `ShareImportViewModel.swift`。
- 没有新增布局切换 UI。
- 没有修改拖放落点语义。
- 没有修改对象复制的 24 屏幕点偏移实现。

阶段 1 至阶段 6 对 `CanvasEditorSession.appendImportedMedia` 的改动只替换布局求解部分；整批导入末尾仍只调用一次既有 history/autosave 路径。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：appendImportedMedia(_:placement:layout:presentationTemplate:)
// 功能注释：整批媒体创建完成后，继续只记录一次 history，并只调度一次 autosave。
let changeReason = importedMediaChangeReason(
    for: importedItems.count
)
_ = recordImmediateHistoryChange(
    from: beforeSnapshot,
    reason: changeReason,
    autosaveReason: changeReason
)
return importedItems
```

## 自动验证

### 布局模型、solver、session placement 与 GIF 定向测试

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行阶段 7 要求的布局模型、solver、session placement 和 GIF builder 定向测试。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasImportLayoutSolverTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests"
```

实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- `CanvasImportRequestModelTests`：5 个测试通过。
- `CanvasImportLayoutSolverTests`：5 个测试通过。
- `CanvasImportedMediaPlacementTests`：12 个测试通过。
- `CanvasGIFFrameImportBuilderTests`：5 个测试通过。
- 合计 27 个测试通过。
- 本阶段新增的数量/zoom 测试和 diagonal 24 点测试均通过。

### 导入、history、board state 与 storage 相关回归

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行导入入口、命令/history、group state、selection migration 和 video storage 相关回归。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasImportTypeIdentifierResolutionTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasTransferImportPipelineTests" \
  -only-testing:"MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasPlatformImportSourceContractTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests" \
  -only-testing:"MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests" \
  -only-testing:"MyCanvas_Ver_0Tests/BoardVideoStorageTests"
```

实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- 所有选定的导入、history、board state 和 video storage 测试通过。
- 新增持久化闭环测试在该组合中通过。

### 持久化闭环单独复验

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：单独运行真实混合媒体保存和新 session 重开测试。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests/testAutomaticGridPersistsGeometryZIndexesAndVideoSourcesAcrossReload"
```

实际结果：

- 命令退出码为 `0`。
- `TEST SUCCEEDED`。
- 测试通过，耗时约 `0.269` 秒。

### 完整 macOS 测试的实际状态

执行：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行完整 macOS XCTest suite，检查阶段 7 之外的仓库级回归状态。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64"
```

实际结果不是全绿：

- 命令退出码为 `65`。
- `TEST FAILED`。
- 本阶段新增的持久化测试在该次完整并行执行中通过，耗时约 `0.492` 秒。
- 网格相关定向测试全部通过。
- `BoardHandDrawingStorageTests` 有多个测试失败；后续串行复验观察到测试进程发生 `pointer being freed was not allocated`。
- `CanvasInputIndicatorQueueTests` 发生同类测试进程 invalid-free 崩溃。
- `CanvasToolbarStateBuilderTests` 有两个既有断言仍期望不包含 `.group`，而当前 production toolbar 实际包含 `.group`。

串行复验上述失败组后，toolbar 的两个旧预期仍失败，InputIndicator 测试进程仍发生 invalid-free。它们对应的 production/test 文件均不在阶段 7 diff 中，本阶段没有把这些无关问题伪报为网格回归。

另一次排除上述三个已知失败组的长串行执行，在运行到新增持久化测试时，测试进程同样发生 invalid-free；该测试没有产生 XCTest 断言失败，并且在以下三种执行方式中均已通过：

1. 单独执行。
2. 导入/history/storage 相关组合执行。
3. 完整并行 suite 执行。

因此当前事实是：阶段 7 相关测试通过，但仓库完整 macOS XCTest 门禁仍被既有测试进程内存崩溃和 toolbar 旧预期阻塞，不能记录为“完整 suite 全绿”。

### macOS 应用构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：构建 macOS Debug 应用。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64"
```

实际结果：

- 命令退出码为 `0`。
- `BUILD SUCCEEDED`。

### iOS Simulator 应用构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：构建 iOS Simulator Debug 应用；scheme 依赖图同时包含分享扩展。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator"
```

实际结果：

- 命令退出码为 `0`。
- `BUILD SUCCEEDED`。
- target dependency graph 包含 `Add To Canvas`。
- 输出仍包含工程既有的 `CanvasEditorSession.swift` actor-isolation warning，以及没有 AppIntents dependency 时跳过 metadata extraction 的 warning。
- 没有 Swift 编译 error。

### 分享扩展 target 单独构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：单独构建 Add To Canvas 分享扩展的 iOS Simulator target。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -target "Add To Canvas" \
  -configuration Debug \
  -sdk iphonesimulator
```

实际结果：

- 命令退出码为 `0`。
- `BUILD SUCCEEDED`。
- 输出包含没有 AppIntents dependency 时跳过 metadata extraction 的 warning。
- 输出包含 `ONLY_ACTIVE_ARCH=YES` 与多 architecture 构建组合的 warning。
- 没有 Swift 编译 error。

### IDE lint

检查文件：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 7 IDE lint 检查范围。
MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
```

实际结果：`No linter errors found.`。

### 差异格式检查

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查当前 tracked diff 是否包含空白错误。
git diff --check
```

实际结果：命令退出码为 `0`，没有输出。

## 阶段 7 最终验收结论

已通过：

- automatic 的 1、2、4、5、8、9 项 session 落板。
- 固定 4 列、行数自动增长。
- left-to-right、top-to-bottom 行列位置。
- 不完整末行从 column 0 开始。
- 网格整体围绕 import/camera center。
- zoom 0.5、1、2.5 下 world-space 网格中心稳定。
- 所有数量和 zoom 组合无重叠。
- 显式 diagonal 在 zoom 0.5、1、2.5、4 下保持 24 viewport points 步长。
- 图片、GIF、视频混合五项 automatic 导入。
- 保存前后 center、size、zIndex 和 `sourceVideoFilename` 一致。
- poster 和视频源文件实际存在。
- 新 session 重开后媒体顺序、几何、层级、视频源和 camera 状态一致。
- macOS build。
- iOS Simulator build。
- 分享扩展 target build。
- 当前可编译 Swift 中只保留 `automatic/stacked/diagonal/grid` 四种布局语义。

未宣称通过：

- 仓库完整 macOS XCTest suite 不是全绿，实际仍存在阶段 7 diff 之外的 invalid-free 测试进程崩溃和 toolbar 旧预期。
- 本阶段没有进行真实 UI 人眼操作；计划中的数量/zoom/diagonal 几何验收由可重复的 session 自动测试代替。

## 明确未修改的范围

- 未修改 production Swift。
- 未修改 `BoardDocument` schema 或 format version。
- 未修改 storage mapper。
- 未修改 autosave 实现或调用次数。
- 未修改 iOS controller。
- 未修改 macOS controller。
- 未修改 iOS/macOS import adapter。
- 未修改 pasteboard resolver。
- 未修改分享扩展 production 代码。
- 未新增布局切换 UI。
- 未修改拖放落点语义。
- 未修改对象复制逻辑。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。
- 未改写既有 commit record。

## 创建记录后的工作区状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态。
 M MyCanvas_Ver_0Tests/CanvasImportedMediaPlacementTests.swift
 M MyCanvas_Ver_0Tests/macOSCanvasImportAdapterTests.swift
?? commit_records/20260805_154521_batch_import_grid_phase7_build_persistence_acceptance_record.md
```

本次没有创建 Git commit，也没有暂存文件。
