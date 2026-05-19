# 20260519_083638_CST_hand_drawing_multilayer_phase6_host_compat_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 6：`宿主兼容与提交流水线对齐`。
  2. 把宿主链路里手绘文档的读取、迁移、保存统一收口到“规范化后的 `documentData`”，避免把空字节、legacy flat 数据、`PKDrawing` 原始字节直接传递到 bundle / board / reopen 链路。
  3. 保持 `CanvasHandDrawingEditSubmission`、board runtime、preview、thumbnail、minimap、macOS preview-only 契约不变。
  4. 补阶段 6 的宿主链路定向测试，并完成 macOS 定向测试和 iOS Simulator 构建验证。
- 时间戳来源：
  - `date '+%Y%m%d_%H%M%S_CST'` -> `20260519_083638_CST`
- 说明：
  - 本记录只覆盖刚刚实施的阶段 6，不包含阶段 7 的总回归收口。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `M MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - `M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
    - 这是 IDE 会话状态文件，不属于本次阶段 6 代码实现，本记录不展开。
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64,id=00006040-001C099034A0801C' -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests`
    - 通过
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322'`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 7 的测试总收口
  - git commit / push

## 修改一：新增“原始 source data -> 规范化 documentData”的统一入口

### 修改前

- `HandDrawingDocumentLoader` 只有 `loadDocument(from:paper:)`。
- 调用方如果拿到的是空字节、legacy `PKDrawing` 数据或旧格式 flat 数据，只能各自决定要不要转成标准 `HandDrawingDocument`。
- 结果是宿主层容易把“能加载”与“已经规范化可持久化”混为一谈。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
// 函数名: HandDrawingDocumentLoader.loadDocument(from:paper:)
// 功能注释: 修改前 loader 只负责把各种来源加载成内存文档，没有直接提供“输出规范化 documentData”的入口。
static func loadDocument(
    from data: Data,
    paper: CanvasHandDrawingPaperSpec
) throws -> HandDrawingDocument {
    if data.isEmpty {
        return HandDrawingDocument(paper: HandDrawingPaper(paper))
    }

    if let document = try? HandDrawingDocumentCodec.decodeDocument(from: data) {
        return document
    }

    if let legacyDrawing = try? PKDrawing(data: data) {
        return HandDrawingLegacyPencilKitBridge.makeDocument(
            from: legacyDrawing,
            paper: paper
        )
    }

    throw HandDrawingDocumentLoaderError.invalidSourceData
}
```

### 修改后

- 在 `HandDrawingDocumentLoader` 新增 `normalizeDocumentData(from:paper:)`。
- 所有宿主侧需要“标准化文档字节”的位置，都通过它先走一遍：
  - 空白 `Data()`
  - legacy `PKDrawing`
  - 已存在的标准文档
- 阶段 6 的核心收口点就是这里，后续 `store / migration / session / board store` 都围绕它工作。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
// 函数名: HandDrawingDocumentLoader.normalizeDocumentData(from:paper:)
// 功能注释: 修改后 loader 直接提供标准化字节出口，宿主链不再到处传“原始来源数据”。
static func normalizeDocumentData(
    from data: Data,
    paper: CanvasHandDrawingPaperSpec
) throws -> Data {
    try HandDrawingDocumentCodec.makeDocumentData(
        for: loadDocument(from: data, paper: paper)
    )
}
```

## 修改二：`HandDrawingDocumentStore` 不再把原始字节直接写入 bundle，而是统一写入标准文档

### 修改前

- `persistDocument(...)` 直接把传入的 `drawingData` 原样写到 bundle 的 `document.json`。
- `loadDocument(...)` 直接 `decodeDocument(from: loadDocumentData(...))`，默认假设 bundle 里保存的一定已经是标准文档。
- `validateBundleExists(...)` 也只是确认组件存在并能被标准 codec 解码，没有先利用 manifest 的 paper 信息做兼容加载。
- 这意味着：
  - 如果传入的是 `Data()`，bundle 里就是空字节。
  - 如果传入的是 legacy `PKDrawing` 原始数据，bundle 里就不是标准文档。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: HandDrawingDocumentStore.loadDocument(documentID:boardDirectoryURL:) / persistDocument(documentID:paper:contentRevision:isEmpty:drawingData:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)
// 功能注释: 修改前 store 对 documentData 的假设过于乐观，持久化和加载都直接把输入当成已规范化文档。
static func loadDocument(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> HandDrawingDocument {
    try HandDrawingDocumentCodec.decodeDocument(
        from: loadDocumentData(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
    )
}

try CoordinatedFileIO.writeData(
    drawingData,
    to: locator.documentURL(in: boardDirectoryURL)
)
```

### 修改后

- `persistDocument(...)` 会先通过 `HandDrawingDocumentLoader.normalizeDocumentData(from:paper:)` 生成 `normalizedDrawingData`，再写入 bundle。
- `loadDocument(...)` 会先读 manifest，再用 manifest 里的 paper 走 `HandDrawingDocumentLoader.loadDocument(...)`，兼容标准文档、空文档和 legacy 数据。
- 新增 `loadNormalizedDocumentData(...)`，统一给宿主层返回标准化后的文档字节。
- `validateBundleExists(...)` 现在校验的是“可加载成合法文档”，而不是“存在一个字节文件”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: HandDrawingDocumentStore.loadDocument(documentID:boardDirectoryURL:) / loadNormalizedDocumentData(documentID:boardDirectoryURL:) / validateBundleExists(documentID:boardDirectoryURL:)
// 功能注释: 修改后 store 加载 bundle 时会显式结合 manifest.paper 做兼容解析，并对外暴露标准化 documentData。
static func loadDocument(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> HandDrawingDocument {
    let manifest = try loadManifest(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
    return try HandDrawingDocumentLoader.loadDocument(
        from: loadDocumentData(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        ),
        paper: manifest.paper.canvasPaperSpec
    )
}

static func loadNormalizedDocumentData(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws -> Data {
    try HandDrawingDocumentCodec.makeDocumentData(
        for: loadDocument(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )
    )
}

static func validateBundleExists(
    documentID: HandDrawingDocumentID,
    boardDirectoryURL: URL
) throws {
    _ = try loadManifest(documentID: documentID, boardDirectoryURL: boardDirectoryURL)
    _ = try loadDocument(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
    _ = try loadPreviewImage(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: HandDrawingDocumentStore.persistDocument(documentID:paper:contentRevision:isEmpty:drawingData:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)
// 功能注释: 修改后写盘前先规范化 documentData，bundle 里的 document 组件始终是标准文档。
let normalizedDrawingData = try HandDrawingDocumentLoader.normalizeDocumentData(
    from: drawingData,
    paper: paper
)

try CoordinatedFileIO.writeData(
    normalizedDrawingData,
    to: locator.documentURL(in: boardDirectoryURL)
)
```

## 修改三：`BoardStore` 和宿主 reopen 链不再返回原始手绘源字节，而是统一返回规范化文档

### 修改前

- `BoardStore.loadHandDrawingDocumentData(...)`：
  - bundle 存储时直接读 bundle 内字节返回
  - legacy 资产时直接读 `sourceDrawingURL` 返回
- 调用方拿到的到底是标准文档、空字节还是 legacy 数据，取决于底层存的是什么。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStore.loadHandDrawingDocumentData(boardID:documentID:userDefaults:)
// 功能注释: 修改前 board store 只是“搬运字节”，没有保证返回的一定是规范化 documentData。
if HandDrawingDocumentStore.bundleExists(
    documentID: documentID,
    boardDirectoryURL: boardDirectoryURL
) {
    return try HandDrawingDocumentStore.loadDocumentData(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
}

let sourceURL = BoardHandDrawingAssetLocator(documentID: documentID)
    .sourceDrawingURL(in: assetsDirectoryURL)
return try CoordinatedFileIO.readData(at: sourceURL)
```

### 修改后

- 如果是 bundle 存储，返回 `HandDrawingDocumentStore.loadNormalizedDocumentData(...)`。
- 如果还是 legacy flat 资产，会先读取 `board.json` 找到对应 `record.paper`，再通过 `HandDrawingDocumentLoader.normalizeDocumentData(from:paper:)` 返回规范化结果。
- 这保证 reopen 链只感知“手绘标准文档数据”，不感知内部来源差异。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStore.loadHandDrawingDocumentData(boardID:documentID:userDefaults:)
// 功能注释: 修改后 board store 统一返回规范化 documentData，宿主 reopen 链不再关心底层来源是 bundle 还是 legacy flat 资产。
if HandDrawingDocumentStore.bundleExists(
    documentID: documentID,
    boardDirectoryURL: boardDirectoryURL
) {
    return try HandDrawingDocumentStore.loadNormalizedDocumentData(
        documentID: documentID,
        boardDirectoryURL: boardDirectoryURL
    )
}

let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
    boardDocumentFilename
)
let boardDocument = try readBoardDocument(at: boardDocumentURL)
let sourceURL = BoardHandDrawingAssetLocator(documentID: documentID)
    .sourceDrawingURL(in: assetsDirectoryURL)
let sourceData = try CoordinatedFileIO.readData(at: sourceURL)
guard
    let record = boardDocument.handDrawingItemRecords.first(where: {
        $0.documentID == documentID
    })
else {
    return sourceData
}
return try HandDrawingDocumentLoader.normalizeDocumentData(
    from: sourceData,
    paper: record.paper.canvasPaperSpec
)
```

## 修改四：legacy 迁移和空白手绘项的提交链，改成直接使用规范化文档

### 修改前

- `HandDrawingMigrationService` 在多个分支里直接返回 `legacyDrawingData` 或 `loadDocumentData(...)` 的原始结果。
- `CanvasEditorSession.addHandDrawingItem(...)` 在新建空白手绘项时，把 `Data()` 直接塞进 `transientHandDrawingAssetPayloads`。
- 这会导致：
  - 迁移后的 reopen 链表面可工作，但上下游拿到的文档字节契约不统一。
  - 空白手绘项如果立刻保存，bundle 里可能出现空字节文档组件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: HandDrawingMigrationService.prepareBundleDocumentForEditing(record:boardDirectoryURL:) / prepareLegacyDocumentForEditing(boardID:itemID:record:entry:userDefaults:) / resumeLegacyMigrationIfNeeded(boardID:itemID:record:boardDirectoryURL:userDefaults:)
// 功能注释: 修改前 migration service 返回的是“来源字节”，而不是统一规范化后的 documentData。
return HandDrawingPreparedEditingDocument(
    record: record,
    documentData: try HandDrawingDocumentStore.loadDocumentData(
        documentID: record.documentID,
        boardDirectoryURL: boardDirectoryURL
    ),
    didMigrateLegacyDocument: false
)

return HandDrawingPreparedEditingDocument(
    record: record.replacingStorage(with: .bundle),
    documentData: legacyDrawingData,
    didMigrateLegacyDocument: true
)

return legacyBackupDrawingData
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession.addHandDrawingItem(paper:)
// 功能注释: 修改前新建空白手绘项时直接把 Data() 当成文档数据挂到 transient payload。
transientHandDrawingAssetPayloads[item.id] =
    BoardTransientHandDrawingAssetPayload(
        itemID: item.id,
        documentData: Data(),
        previewCGImage: previewImage
    )
```

### 修改后

- `HandDrawingMigrationService` 统一通过 `HandDrawingDocumentStore.loadNormalizedDocumentData(...)` 返回迁移/恢复后的标准文档数据。
- `CanvasEditorSession.addHandDrawingItem(...)` 先生成 `emptyDocumentData`，再挂到 transient payload。
- 这样“旧文档打开 -> 编辑 -> 保存 -> 再打开”和“空白文档新建 -> 不绘制直接保存 -> 再打开”都走同一条标准化数据链。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: HandDrawingMigrationService.prepareBundleDocumentForEditing(record:boardDirectoryURL:) / prepareLegacyDocumentForEditing(boardID:itemID:record:entry:userDefaults:) / resumeLegacyMigrationIfNeeded(boardID:itemID:record:boardDirectoryURL:userDefaults:) / restoreDocumentFromLegacyBackupIfPossible(for:boardDirectoryURL:)
// 功能注释: 修改后 migration service 输出的是标准文档字节，不再把 legacy 原始数据直接暴露给宿主层。
return HandDrawingPreparedEditingDocument(
    record: record,
    documentData: try HandDrawingDocumentStore.loadNormalizedDocumentData(
        documentID: record.documentID,
        boardDirectoryURL: boardDirectoryURL
    ),
    didMigrateLegacyDocument: false
)

return HandDrawingPreparedEditingDocument(
    record: record.replacingStorage(with: .bundle),
    documentData: try HandDrawingDocumentStore.loadNormalizedDocumentData(
        documentID: record.documentID,
        boardDirectoryURL: entry.boardDirectoryURL
    ),
    didMigrateLegacyDocument: true
)

return try HandDrawingDocumentStore.loadNormalizedDocumentData(
    documentID: record.documentID,
    boardDirectoryURL: boardDirectoryURL
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession.addHandDrawingItem(paper:)
// 功能注释: 修改后新建空白手绘项时直接生成规范化空文档，避免把空字节写进 bundle 或 reopen 链。
guard
    let emptyDocumentData = try? HandDrawingDocumentLoader
        .normalizeDocumentData(from: Data(), paper: paper),
    let previewImage = try? CanvasHandDrawingPreviewAssetFactory
        .makeTransparentPreview(for: paper)
else {
    return nil
}

transientHandDrawingAssetPayloads[item.id] =
    BoardTransientHandDrawingAssetPayload(
        itemID: item.id,
        documentData: emptyDocumentData,
        previewCGImage: previewImage
    )
```

## 修改五：阶段 6 核对后确认无需改动的宿主契约

### 核对结论

- `CanvasHandDrawingEditSubmission` 仍保持 `documentData + previewCGImage + isEmpty + contentRevision` 契约，不需要新增 layer 维度字段。
- `CanvasRenderer` 仍只消费 `previewCGImage`、`paper`、`isEmpty`，不需要理解 layer 内部结构。
- 这也是阶段 6 的目标之一：多 layer 在宿主侧只表现为“更复杂的 `documentData` + 更准确的 preview”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditSubmission
// 功能注释: 阶段 6 核对后保持不变，提交链继续只提交文档数据、preview、empty 标记和 revision。
struct CanvasHandDrawingEditSubmission {
    let documentData: Data
    let previewCGImage: CGImage
    let isEmpty: Bool
    let contentRevision: UUID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: CanvasRenderer.makeHandDrawingRenderItem(for:camera:rotationPreviewState:)
// 功能注释: 阶段 6 核对后保持不变，画布渲染仍只消费 hand drawing preview，不感知 layer 内部结构。
payload: .handDrawing(
    CanvasHandDrawingRenderPayload(
        previewAssetReference: effectiveHandDrawingItem.previewAsset.reference,
        previewCGImage: effectiveHandDrawingItem.previewAsset.posterCGImage,
        paper: effectiveHandDrawingItem.paper,
        isEmpty: effectiveHandDrawingItem.isEmpty
    )
)
```

## 修改六：测试从“原始字节相等”调整为“可解码且语义正确”，并补空白文档重开链路

### 修改前

- 一部分测试默认认为：
  - 新建空白手绘项时 `editorContext.documentData.isEmpty == true`
  - legacy 迁移后返回的 `documentData` 要与原始 `PKDrawing` 字节完全相等
  - store 测试可以随便塞一段字符串字节当 `drawingData`
- 阶段 6 改成“统一规范化”后，这些断言都不再成立：
  - 标准空白文档不是空字节
  - 规范化过程会重新编码文档结构，不能再拿原始字节做硬比

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: CanvasHandDrawingEditingSessionTests.testAddHandDrawingItemProvidesImmediateEmptyEditorContext()
// 功能注释: 修改前测试把“空白文档”误等同于 documentData.isEmpty。
let editorContext = try session.handDrawingEditorContext(for: item.id)
XCTAssertEqual(editorContext.itemID, item.id)
XCTAssertTrue(editorContext.documentData.isEmpty)
XCTAssertTrue(editorContext.isEmpty)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: HandDrawingMigrationServiceTests.testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand()
// 功能注释: 修改前测试直接拿迁移后的 documentData 和 legacy 原始字节做相等比较。
XCTAssertEqual(preparedDocument.record.storage, .bundle)
XCTAssertTrue(preparedDocument.didMigrateLegacyDocument)
XCTAssertEqual(preparedDocument.documentData, fixture.drawingData)
```

### 修改后

- `CanvasHandDrawingEditingSessionTests` 改为先 `decodeDocument(from:)`，再断言：
  - `paper` 正确
  - `isEmpty == true`
  - `layers.count == 1`
- 新增 `testAddHandDrawingItemPersistsCanonicalBlankDocumentAcrossBoardReload()`，覆盖“空白手绘项直接保存再重开”的链路。
- `HandDrawingDocumentStoreTests` 改成传入真实可规范化的手绘文档数据，不再塞任意字符串字节。
- `HandDrawingMigrationServiceTests` 新增 `assertNormalizedEmptyDocumentData(...)`，统一验证“迁移后的空白文档语义正确”，而不是要求字节完全一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: CanvasHandDrawingEditingSessionTests.testAddHandDrawingItemProvidesImmediateEmptyEditorContext() / testAddHandDrawingItemPersistsCanonicalBlankDocumentAcrossBoardReload()
// 功能注释: 修改后测试验证的是空白文档的可解码语义，并补齐保存后再打开链路。
let editorContext = try session.handDrawingEditorContext(for: item.id)
let document = try HandDrawingDocumentCodec.decodeDocument(
    from: editorContext.documentData
)
XCTAssertEqual(document.paper, HandDrawingPaper(.square))
XCTAssertTrue(document.isEmpty)
XCTAssertEqual(document.layers.count, 1)

let persistedDocument = try HandDrawingDocumentCodec.decodeDocument(
    from: BoardStore.loadHandDrawingDocumentData(
        boardID: boardID,
        documentID: item.documentID,
        userDefaults: userDefaults
    )
)
XCTAssertTrue(persistedDocument.isEmpty)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: HandDrawingMigrationServiceTests.testHandDrawingMigrationServiceMigratesLegacyFlatAssetsOnDemand() / assertNormalizedEmptyDocumentData(_:file:line:)
// 功能注释: 修改后迁移测试统一校验“迁移结果是可解码且语义正确的空白标准文档”，不再依赖原始字节完全相等。
try assertNormalizedEmptyDocumentData(preparedDocument.documentData)
try assertNormalizedEmptyDocumentData(storedDocumentData)
try assertNormalizedEmptyDocumentData(
    BoardStore.loadHandDrawingDocumentData(
        boardID: fixture.boardID,
        documentID: fixture.documentID,
        userDefaults: userDefaults
    )
)

private func assertNormalizedEmptyDocumentData(
    _ data: Data,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let document = try HandDrawingDocumentCodec.decodeDocument(from: data)
    XCTAssertEqual(document.paper, HandDrawingPaper(.square), file: file, line: line)
    XCTAssertTrue(document.isEmpty, file: file, line: line)
    XCTAssertEqual(document.layers.count, 1, file: file, line: line)
    XCTAssertEqual(document.activeLayerStrokes.count, 0, file: file, line: line)
}
```

## 结果小结

- 阶段 6 完成后，宿主侧不再把手绘“原始来源字节”当成长期契约。
- 空白文档、legacy `PKDrawing`、bundle 文档在 reopen / save / migration / board store 链路上都统一收敛成标准化 `documentData`。
- `CanvasHandDrawingEditSubmission`、board runtime、preview、thumbnail、minimap、macOS preview-only 行为保持原契约不变，宿主侧不需要理解 layer 内部结构。
