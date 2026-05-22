# 20260522_111730_CST_hand_drawing_brush_engine_phase5_compatibility_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 5`，收口 `codec / loader / migration / preview` 的持久化兼容链路。
  - 保持 `HandDrawingDocument.currentFormatVersion` 不变，不引入 `v3`；通过新增回归测试验证“新增 brush dynamics 字段缺失时，旧稿仍可安全 decode”。
  - 将 `preview.png` 明确收口为“由规范化 `documentData` 可重建的派生产物”，而不是 legacy 迁移阶段必须依赖的原始输入资产。
  - 补齐 `HandDrawingDocumentCodecTests`、`HandDrawingDocumentLoaderTests`、`HandDrawingDocumentStoreTests`、`HandDrawingMigrationServiceTests`，覆盖旧稿 decode、PK legacy 输入保留、preview 重建和 migration 恢复链路。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_111730_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次 `phase 5` 相关文件执行 `git diff --stat -- ...`，结果为：`9 files changed, 285 insertions(+), 41 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示 9 个已跟踪修改文件，均属于本次 `phase 5` 变更。
  - 当前工作区还存在 `/.cursor/plans/手绘笔刷引擎_b7888ee9.plan.md` 的现有修改，但该 `.md` 文件不属于本次 phase 5 代码产物，因此不纳入本记录正文。
- 本记录不包含：
  - `phase 4` 的 brush preset / UI 入口升级记录。
  - `phase 6` 的 CPU 路径性能收口。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次 phase 5 markdown 记录文件的时间戳前缀。
20260522_111730_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
# 功能说明: 汇总本次 phase 5 相关已跟踪文件的 diff 统计。
.../HandDrawing/Core/HandDrawingDocument.swift     |  2 +
.../Editing/HandDrawingDocumentLoader.swift        |  4 +-
.../Persistence/HandDrawingDocumentStore.swift     | 29 ++++++-
.../Persistence/HandDrawingMigrationService.swift  | 36 +--------
.../HandDrawingEditorCoordinator.swift             |  4 +-
.../HandDrawingDocumentCodecTests.swift            | 44 ++++++++++
.../HandDrawingDocumentLoaderTests.swift           | 64 +++++++++++++++
.../HandDrawingDocumentStoreTests.swift            | 49 +++++++++++
.../HandDrawingMigrationServiceTests.swift         | 94 ++++++++++++++++++++++
9 files changed, 285 insertions(+), 41 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
# 功能说明: 记录本次 phase 5 相关文件的当前 changes 状态。
M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
M MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
M MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
M MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
```

## 当前 changes 摘要

- `HandDrawingDocumentStore.persistDocument(...)` 不再要求调用方必须传 preview；当 `previewImageData` 与 `previewCGImage` 都缺失时，会直接基于规范化后的 hand drawing document 生成 canonical `preview.png`。
- `HandDrawingMigrationService` 不再把 legacy preview 资产当成迁移前置条件；legacy PKDrawing 只要可解码，就可以迁移进 bundle，并生成与当前 renderer 一致的 preview。
- `HandDrawingDocumentLoader` 在 PK legacy bridge 中继续保留 `force / azimuth / altitude`，同时为迁移出的 brush 补上当前 preset 默认 tilt dynamics，使新引擎下的回放与后续编辑公式一致。
- `HandDrawingBrushStyle` 新增共享 preset 默认 tilt 常量；`HandDrawingEditorCoordinator` 改为引用该常量，避免 UI preset 与 migration bridge 各自硬编码。
- `HandDrawingDocumentCodecTests` 新增“缺少 dynamics 字段的 layered 旧稿仍可 decode”回归，明确当前不需要升级 `formatVersion`。

## 修改一：`HandDrawingDocumentStore` 从“preview 必填”改为“按规范化 document 重建 canonical preview”

### 修改前

- `persistDocument(...)` 只接受两种 preview 来源：
  - 直接传入的 `previewImageData`
  - 直接传入的 `previewCGImage`
- 两者都没有时，直接抛 `missingPreviewRepresentation`。
- 这会把 preview 当成迁移或恢复阶段的必备输入，而不是文档的派生产物。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift（修改前）
// 函数名: persistDocument(documentID:paper:contentRevision:isEmpty:drawingData:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)
// 功能说明: 修改前若调用方没有显式提供 preview 数据或 CGImage，store 会直接报错，无法从规范化后的文档自行重建 preview。
let resolvedPreviewImageData: Data
if let previewImageData {
    resolvedPreviewImageData = previewImageData
} else if let previewCGImage {
    resolvedPreviewImageData = try HandDrawingDocumentCodec.makePNGData(
        for: previewCGImage,
        documentID: documentID
    )
} else {
    throw HandDrawingDocumentStoreError.missingPreviewRepresentation(
        documentID: documentID
    )
}
```

### 修改后

- `persistDocument(...)` 在 preview 缺失时，改为调用新的 `makeCanonicalPreviewImageData(...)`。
- `makeCanonicalPreviewImageData(...)` 以已经规范化的 `normalizedDrawingData` 为真相源：
  - 空文档生成透明 preview
  - 非空文档通过 `HandDrawingPreviewRenderer` 重绘当前 canonical preview
- `preview.png` 的 bundle 契约保持不变，只是生成方式统一收口到了规范化文档。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: persistDocument(documentID:paper:contentRevision:isEmpty:drawingData:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:) / makeCanonicalPreviewImageData(for:documentID:)
// 功能说明: 修改后 store 将规范化 documentData 作为真相源，在 preview 缺失时自动重建 canonical preview.png。
let resolvedPreviewImageData: Data
if let previewImageData {
    resolvedPreviewImageData = previewImageData
} else if let previewCGImage {
    resolvedPreviewImageData = try HandDrawingDocumentCodec.makePNGData(
        for: previewCGImage,
        documentID: documentID
    )
} else {
    resolvedPreviewImageData = try makeCanonicalPreviewImageData(
        for: normalizedDrawingData,
        documentID: documentID
    )
}

private static func makeCanonicalPreviewImageData(
    for normalizedDrawingData: Data,
    documentID: HandDrawingDocumentID
) throws -> Data {
    let normalizedDocument = try HandDrawingDocumentCodec.decodeDocument(
        from: normalizedDrawingData
    )
    let previewImage: CGImage
    if normalizedDocument.isEmpty {
        previewImage = try CanvasHandDrawingPreviewAssetFactory
            .makeTransparentPreview(for: normalizedDocument.paper.canvasPaperSpec)
    } else {
        previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: normalizedDocument,
            scale: 1
        )
    }
    return try HandDrawingDocumentCodec.makePNGData(
        for: previewImage,
        documentID: documentID
    )
}
```

## 修改二：`HandDrawingMigrationService` 不再依赖旧 preview 资产才能迁移 / 恢复

### 修改前

- `HandDrawingMigrationServiceError` 里存在 `missingLegacyPreviewAsset`。
- `prepareLegacyDocumentForEditing(...)` 在迁移 legacy PK 资产前会强制读取旧 preview 文件。
- `restoreDocumentFromLegacyBackupIfPossible(...)` 在 bundle 损坏恢复时也会强制读取 bundle 内已有 preview。
- 这意味着 preview 丢失会阻断迁移或恢复，即便 `drawingData` 本身仍然可解码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift（修改前）
// 函数名: HandDrawingMigrationServiceError / prepareLegacyDocumentForEditing(...) / restoreDocumentFromLegacyBackupIfPossible(...) / loadLegacyPreviewImageData(...)
// 功能说明: 修改前 migration 与 bundle 恢复都把 preview 资产当成必需输入，preview 丢失会直接失败。
enum HandDrawingMigrationServiceError: LocalizedError {
    case missingBoardDocument(boardID: UUID)
    case missingHandDrawingRecord(boardID: UUID, itemID: CanvasItemID)
    case invalidLegacyDrawingData(itemID: CanvasItemID)
    case missingLegacyPreviewAsset(itemID: CanvasItemID, filename: String)
}

let legacyPreviewImageData = try loadLegacyPreviewImageData(
    for: record,
    itemID: itemID,
    assetsDirectoryURL: entry.assetsDirectoryURL
)

try HandDrawingDocumentStore.persistDocument(
    documentID: record.documentID,
    paper: record.paper.canvasPaperSpec,
    contentRevision: record.contentRevision,
    isEmpty: record.isEmpty,
    drawingData: legacyDrawingData,
    previewImageData: legacyPreviewImageData,
    previewCGImage: nil,
    boardDirectoryURL: entry.boardDirectoryURL,
    migrationOrigin: .legacyFlatAssetPair,
    legacyBackupDrawingData: legacyDrawingData
)

let previewImageData = try HandDrawingDocumentStore.loadPreviewImageData(
    documentID: record.documentID,
    boardDirectoryURL: boardDirectoryURL
)
```

### 修改后

- 删除了 `missingLegacyPreviewAsset` 这条错误分支。
- legacy 迁移与 legacy backup 恢复都改为只要求 `drawingData` 可解码。
- 调用 `HandDrawingDocumentStore.persistDocument(...)` 时，统一传 `previewImageData: nil`、`previewCGImage: nil`，把 preview 重建责任交给 store 的 canonical preview 生成逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: HandDrawingMigrationServiceError / prepareLegacyDocumentForEditing(...) / restoreDocumentFromLegacyBackupIfPossible(...)
// 功能说明: 修改后 migration 与 bundle 恢复只依赖可解码的 drawingData，preview 缺失时由 store 自动重建 canonical preview。
enum HandDrawingMigrationServiceError: LocalizedError {
    case missingBoardDocument(boardID: UUID)
    case missingHandDrawingRecord(boardID: UUID, itemID: CanvasItemID)
    case invalidLegacyDrawingData(itemID: CanvasItemID)
}

try HandDrawingDocumentStore.persistDocument(
    documentID: record.documentID,
    paper: record.paper.canvasPaperSpec,
    contentRevision: record.contentRevision,
    isEmpty: record.isEmpty,
    drawingData: legacyDrawingData,
    previewImageData: nil,
    previewCGImage: nil,
    boardDirectoryURL: entry.boardDirectoryURL,
    migrationOrigin: .legacyFlatAssetPair,
    legacyBackupDrawingData: legacyDrawingData
)

try HandDrawingDocumentStore.persistDocument(
    documentID: record.documentID,
    paper: manifest?.paper.canvasPaperSpec ?? record.paper.canvasPaperSpec,
    contentRevision: manifest?.contentRevision ?? record.contentRevision,
    isEmpty: manifest?.isEmpty ?? record.isEmpty,
    drawingData: legacyBackupDrawingData,
    previewImageData: nil,
    previewCGImage: nil,
    boardDirectoryURL: boardDirectoryURL,
    migrationOrigin: resolvedMigrationOrigin,
    legacyBackupDrawingData: legacyBackupDrawingData
)
```

## 修改三：统一 legacy bridge 与编辑器 preset 的默认 tilt 常量

### 修改前

- `HandDrawingBrushStyle` 中没有“preset 默认 tilt 语义”的共享常量。
- PK legacy bridge 在 `makeBrushStyle(...)` 里只还原 `color / baseSize / opacity`，没有给 legacy 转换结果补上当前编辑器 preset 的默认 tilt 参数。
- `HandDrawingEditorCoordinator` 里使用的是 `0.85 / 0` 字面量。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift（修改前）
// 函数名: HandDrawingBrushStyle.defaultPen
// 功能说明: 修改前 BrushStyle 只有默认笔刷定义，没有共享的 preset 默认 tilt 常量。
static let defaultPen = HandDrawingBrushStyle(
    kind: .pen,
    color: .black,
    baseSize: 6,
    opacity: 1
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift（修改前）
// 函数名: makeBrushStyle(from:using:)
// 功能说明: 修改前 PK legacy bridge 只恢复宽度和透明度，不会把当前 brush preset 的默认 tilt 语义补进迁移后的文档。
return HandDrawingBrushStyle(
    kind: .pen,
    color: color,
    baseSize: resolvedBaseSize,
    opacity: averageOpacity
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: defaultBrushPresets
// 功能说明: 修改前 coordinator 仍然直接硬编码默认 preset 的 tilt 参数。
static let defaultBrushPresets: [HandDrawingBrushPreset] =
    HandDrawingBrushPresetCatalog.defaultPenPresets(
        lineWidths: defaultLineWidths,
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
```

### 修改后

- 在 `HandDrawingBrushStyle` 里新增 `defaultPresetTiltSizeInfluence` 与 `defaultPresetTiltOpacityInfluence`。
- PK legacy bridge 与 iOS coordinator 都改成引用同一套共享常量。
- 这样 phase 5 之后：
  - legacy PK 转文档
  - 新建 iOS preset
  - reopen 后继续编辑  
  会围绕同一套默认 dynamics 语义工作，不会出现不同入口各自硬编码的漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingBrushStyle.defaultPresetTiltSizeInfluence / HandDrawingBrushStyle.defaultPresetTiltOpacityInfluence
// 功能说明: 修改后把 preset 默认 tilt 语义抽成共享常量，供 legacy bridge 与 editor preset 统一复用。
static let defaultPresetTiltSizeInfluence = 0.85
static let defaultPresetTiltOpacityInfluence = 0.0
static let defaultPen = HandDrawingBrushStyle(
    kind: .pen,
    color: .black,
    baseSize: 6,
    opacity: 1
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
// 函数名: makeBrushStyle(from:using:)
// 功能说明: 修改后 legacy PK bridge 在还原基础笔刷参数时，会补入与当前 editor preset 一致的默认 tilt dynamics。
return HandDrawingBrushStyle(
    kind: .pen,
    color: color,
    baseSize: resolvedBaseSize,
    opacity: averageOpacity,
    tiltSizeInfluence: HandDrawingBrushStyle.defaultPresetTiltSizeInfluence,
    tiltOpacityInfluence: HandDrawingBrushStyle.defaultPresetTiltOpacityInfluence
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: defaultBrushPresets
// 功能说明: 修改后 coordinator 不再直接写字面量，而是复用 BrushStyle 层的共享默认 tilt 常量。
static let defaultBrushPresets: [HandDrawingBrushPreset] =
    HandDrawingBrushPresetCatalog.defaultPenPresets(
        lineWidths: defaultLineWidths,
        tiltSizeInfluence: HandDrawingBrushStyle.defaultPresetTiltSizeInfluence,
        tiltOpacityInfluence: HandDrawingBrushStyle.defaultPresetTiltOpacityInfluence
    )
```

## 修改四：补齐 `codec / loader / store / migration` 回归测试，确认不升格式版本也能安全兼容

### 修改前

- `HandDrawingDocumentCodecTests` 已覆盖：
  - brush dynamics round trip
  - legacy flat v1 decode
- 但没有明确覆盖“当前 layered 文档缺少新增 dynamics 字段”的解码兼容。
- `HandDrawingDocumentLoaderTests` 只验证 legacy PKDrawing 能转成可预览文档，没有锁定 `force / azimuth / altitude` 和默认 tilt 参数。
- `HandDrawingDocumentStoreTests` 只验证“提供 preview 时能按原样持久化”，没有覆盖“省略 preview 时会自动重建 canonical preview”。
- `HandDrawingMigrationServiceTests` 只覆盖 legacy 资产正常迁移、invalid PK 回滚和 legacy backup 恢复，没有覆盖“preview 缺失仍可迁移”和“恢复时 preview 丢失仍可重建”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift（修改前）
// 函数名: testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument()
// 功能说明: 修改前 codec 测试停留在 legacy flat v1 与完整动态参数 round trip，没有显式锁定 layered 旧稿缺少新字段时的 decode 兼容。
func testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument() throws {
    let legacyDocument = makeHandDrawingTestDocument(includeEraseMask: true)
    let legacyData = try makeLegacyFlatDocumentData(
        paper: legacyDocument.paper,
        strokes: legacyDocument.strokes
    )
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift（修改前）
// 函数名: testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing()
// 功能说明: 修改前 loader 测试只验证 legacy PKDrawing 能转成可见笔迹，没有锁定 force / azimuth / altitude 与默认 tilt 语义。
func testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing() throws {
    let legacyDrawing = makeLegacyDrawing()
    let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
        from: legacyDrawing.dataRepresentation(),
        paper: .square
    )
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift（修改前）
// 函数名: testHandDrawingDocumentStorePersistsProvidedPreviewImageData()
// 功能说明: 修改前 store 测试只覆盖“外部已提供 preview”路径，还没有 canonical preview 自动重建回归。
func testHandDrawingDocumentStorePersistsProvidedPreviewImageData() throws {
    try HandDrawingDocumentStore.persistDocument(
        documentID: documentID,
        paper: .square,
        contentRevision: contentRevision,
        isEmpty: false,
        drawingData: drawingData,
        previewImageData: previewImageData,
        previewCGImage: nil,
        boardDirectoryURL: boardDirectoryURL
    )
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift（修改前）
// 函数名: testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() / testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup()
// 功能说明: 修改前 migration 测试没有覆盖 preview 缺失场景，也没有验证恢复后 preview 是否按当前 renderer 重新生成。
func testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() throws {
    let fixture = try makeLegacyHandDrawingFixture(
        selectedFolderURL: selectedFolderURL,
        drawingData: PKDrawing().dataRepresentation()
    )
    // ...
}

func testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup() throws {
    try HandDrawingDocumentStore.persistDocument(
        documentID: documentID,
        paper: .square,
        contentRevision: bundleRecord.contentRevision,
        isEmpty: true,
        drawingData: legacyBackupData,
        previewImageData: previewImageData,
        previewCGImage: nil,
        boardDirectoryURL: boardDirectoryURL,
        migrationOrigin: .legacyFlatAssetPair,
        legacyBackupDrawingData: legacyBackupData
    )
    // ...
}
```

### 修改后

- `HandDrawingDocumentCodecTests` 新增 `testHandDrawingDocumentCodecDecodesLayeredDocumentWithoutBrushDynamicsFields()`，明确锁定当前 layered 旧稿即便缺少 pressure / tilt 新字段也能正常 decode，因此 phase 5 不需要升级 `formatVersion`。
- `HandDrawingDocumentLoaderTests` 新增 `testHandDrawingDocumentLoaderNormalizesLegacyPencilKitDrawingPreservingRawInputs()`，锁定 PK legacy 归一化后：
  - `force / azimuth / altitude` 不丢
  - 默认 tilt dynamics 已补入
- `HandDrawingDocumentStoreTests` 新增 `testHandDrawingDocumentStoreGeneratesCanonicalPreviewWhenPreviewIsOmitted()`，锁定 preview 自动重建路径。
- `HandDrawingMigrationServiceTests` 新增：
  - `testHandDrawingMigrationServiceMigratesLegacyDrawingWithoutPreviewAssetAndRebuildsCanonicalPreview()`
  - 并扩展 `testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup()` 去验证 preview 缺失时的重建结果

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
// 函数名: testHandDrawingDocumentCodecDecodesLayeredDocumentWithoutBrushDynamicsFields()
// 功能说明: 修改后新增 layered 旧稿兼容回归，明确当前不需要因新增可选 brush dynamics 字段而升级文档格式版本。
func testHandDrawingDocumentCodecDecodesLayeredDocumentWithoutBrushDynamicsFields() throws {
    let stroke = HandDrawingStroke(
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.28, green: 0.36, blue: 0.88, alpha: 1),
            baseSize: 14,
            opacity: 0.72
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 24, y: 38),
                force: 0.35,
                timestamp: 0,
                azimuthRadians: 0.7,
                altitudeRadians: .pi / 4
            )
        ]
    )
    // ... 断言 decodedStroke.brush 的新增 dynamics 字段均为 nil，同时原始 sample 输入不丢 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: testHandDrawingDocumentLoaderNormalizesLegacyPencilKitDrawingPreservingRawInputs()
// 功能说明: 修改后新增 legacy PK 输入归一化回归，锁定 force / azimuth / altitude 与默认 tilt preset 常量都会进入规范化文档。
func testHandDrawingDocumentLoaderNormalizesLegacyPencilKitDrawingPreservingRawInputs() throws {
    let legacyDrawing = makeLegacyTiltDrawing()
    let normalizedData = try HandDrawingDocumentLoader.normalizeDocumentData(
        from: legacyDrawing.dataRepresentation(),
        paper: .square
    )
    let normalizedDocument = try HandDrawingDocumentCodec.decodeDocument(
        from: normalizedData
    )
    let normalizedStroke = try XCTUnwrap(normalizedDocument.strokes.first)
    let normalizedSample = try XCTUnwrap(normalizedStroke.samplePoints.first)
    // ... 断言 tilt 默认值、force、azimuth、altitude 与 preview 可见性 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStoreGeneratesCanonicalPreviewWhenPreviewIsOmitted()
// 功能说明: 修改后新增 store 自动补 preview 回归，锁定 bundle 中生成的 preview.png 与当前 preview renderer 输出一致。
func testHandDrawingDocumentStoreGeneratesCanonicalPreviewWhenPreviewIsOmitted() throws {
    let drawingData = try HandDrawingDocumentCodec.makeDocumentData(for: document)
    let expectedPreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
        for: document,
        scale: 1
    )

    try HandDrawingDocumentStore.persistDocument(
        documentID: documentID,
        paper: document.paper.canvasPaperSpec,
        contentRevision: contentRevision,
        isEmpty: false,
        drawingData: drawingData,
        previewImageData: nil,
        previewCGImage: nil,
        boardDirectoryURL: boardDirectoryURL
    )

    let storedPreviewImage = try HandDrawingDocumentStore.loadPreviewImage(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
    XCTAssertEqual(
        BoardThumbnailImageSignature.describe(storedPreviewImage),
        BoardThumbnailImageSignature.describe(expectedPreviewImage)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testHandDrawingMigrationServiceMigratesLegacyDrawingWithoutPreviewAssetAndRebuildsCanonicalPreview() / testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup()
// 功能说明: 修改后 migration 回归明确锁定两件事：legacy preview 缺失不会阻断迁移；bundle 恢复后 preview 会按当前 canonical renderer 重建。
func testHandDrawingMigrationServiceMigratesLegacyDrawingWithoutPreviewAssetAndRebuildsCanonicalPreview() throws {
    let legacyDrawing = makeTiltedLegacyMigrationDrawing()
    let fixture = try makeLegacyHandDrawingFixture(
        selectedFolderURL: selectedFolderURL,
        drawingData: legacyDrawing.dataRepresentation()
    )
    try CoordinatedFileIO.removeItemIfExists(at: legacyPreviewURL)
    let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
        boardID: fixture.boardID,
        itemID: fixture.itemID,
        userDefaults: userDefaults
    )
    // ... 断言 migrated document 保留 force / azimuth / altitude，且 stored preview 与 expected preview 一致 ...
}

func testHandDrawingMigrationServiceRestoresBundleDocumentFromLegacyBackup() throws {
    try CoordinatedFileIO.removeItemIfExists(
        at: HandDrawingBundleLocator(documentID: documentID).documentURL(
            in: boardDirectoryURL
        )
    )
    try CoordinatedFileIO.removeItemIfExists(
        at: HandDrawingBundleLocator(documentID: documentID).previewImageURL(
            in: boardDirectoryURL
        )
    )
    let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
        boardID: boardID,
        itemID: itemID,
        userDefaults: userDefaults
    )
    // ... 断言 bundle 恢复成功，且恢复后的 preview 与透明 canonical preview 一致 ...
}
```

## 验证结果

- 目标 macOS 测试通过：
  - `HandDrawingDocumentCodecTests`
  - `HandDrawingDocumentLoaderTests`
  - `HandDrawingDocumentStoreTests`
  - `HandDrawingMigrationServiceTests`
- iOS Simulator 构建通过：`MyCanvas_Ver_0` scheme
- `ReadLints` 检查本次 9 个修改文件，结果为空

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -derivedDataPath "/tmp/MyCanvasPhase5MacTests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests
# 功能说明: 运行本次 phase 5 的持久化兼容回归测试，确认 codec / loader / store / migration 收口后的行为保持正确。
Test session results, code coverage, and logs:
	/tmp/MyCanvasPhase5MacTests/Logs/Test/Test-MyCanvas_Ver_0-2026.05.22_11-15-10-+0800.xcresult

** TEST SUCCEEDED **
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322" -derivedDataPath "/tmp/MyCanvasPhase5IOSBuild"
# 功能说明: 验证 phase 5 改动后的 iOS 编辑器工程编译链路，确保 shared hand drawing 持久化逻辑接入后不会破坏 iOS 构建。
** BUILD SUCCEEDED **
```

## 结论

- `phase 5` 的根因收口不在于再加一个格式版本，而在于把 hand drawing 的兼容真相源统一回 `normalized documentData`。
- `preview.png` 现在仍然是 board 侧展示契约，但不再是 legacy 迁移必须依赖的源资产；缺失时可按当前文档和 renderer 可靠重建。
- 旧 layered 文档缺少新增 dynamics 字段仍可 decode，legacy PKDrawing 的 `force / azimuth / altitude` 也能进入当前文档模型并继续编辑，因此 phase 5 完成后，旧稿打开、迁移、预览与提交这四条链路已经对齐。
