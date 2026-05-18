# 20260518_175557_CST_hand_drawing_kernel_phase8_host_bridge_record

## 记录范围

- 记录内容：
  1. 实施阶段 8 的宿主桥接收口，把 hand drawing 编辑提交链统一到 engine-agnostic 的 `documentData` 语义。
  2. 保持主画布、thumbnail、minimap 的上层消费契约不变，只调整编辑上下文、暂存 payload、迁移返回值和持久化读写的内部命名与读写口径。
  3. 删除 `CanvasHandDrawingEditingError` 中遗留但未使用的旧错误分支。
  4. 补阶段 8 回归测试，覆盖 transient reopen 与 legacy -> bundle 提交持久化闭环。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_175557_CST`
- 说明：
  - 本记录以阶段 7 完成态为基线，结合当前 `git status`、当前 `git diff`、当前文件内容与本轮测试结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
  - 工作区里与本轮阶段 8 无关的其它历史记录文件不纳入本记录。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - 阶段 7 记录：
    - `commit_records/20260518_173828_CST_hand_drawing_kernel_phase7_lasso_move_record.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift`
  - `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `M MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `M MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
- 验证结果：
  - `xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=iOS Simulator,name=iPad (A16),OS=26.1' ...`
    - 未执行成功，原因是 `MyCanvas_Ver_0Tests` 当前不支持 `iphonesimulator` 平台。
  - `xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS,arch=arm64,name=My Mac' -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests -only-testing:MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 9 的性能与回归收口
  - 新的 UI 功能入口改造
  - git commit / push

## 修改一：把 transient payload 与迁移返回值从 `drawingData` 收口为 `documentData`

### 修改前

- `BoardTransientHandDrawingAssetPayload` 仍然使用 `drawingData` 字段名。
- `HandDrawingPreparedEditingDocument` 也仍然使用 `drawingData` 返回迁移后的编辑文档。
- 这会让阶段 8 的宿主桥接继续保留“旧 PencilKit 原始 bytes”暗示，不利于明确当前提交链传递的是“手绘文档数据”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardTransientHandDrawingAssetPayload.init(itemID:drawingData:previewImageData:) / init(itemID:drawingData:previewCGImage:)
// 功能注释: 修改前 transient payload 仍用 drawingData 命名，语义上还贴着旧 source drawing。
struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let drawingData: Data
    let previewImageData: Data?
    let previewCGImage: CGImage?

    init(
        itemID: CanvasItemID,
        drawingData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.drawingData = drawingData
        self.previewImageData = previewImageData
        previewCGImage = nil
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: HandDrawingPreparedEditingDocument / prepareDocumentForEditing(boardID:itemID:userDefaults:)
// 功能注释: 修改前迁移服务虽然已经返回自研文档数据，但字段命名仍是 drawingData。
struct HandDrawingPreparedEditingDocument {
    let record: BoardHandDrawingItemRecord
    let drawingData: Data
    let didMigrateLegacyDocument: Bool
}
```

### 修改后

- `BoardTransientHandDrawingAssetPayload` 明确改为 `documentData`。
- `HandDrawingPreparedEditingDocument` 也同步改为 `documentData`。
- 这样从迁移服务到编辑上下文再到 commit bridge，语义统一成“手绘文档”，不再隐含旧引擎来源。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardHandDrawingAssetLocator.swift
// 函数名: BoardTransientHandDrawingAssetPayload.init(itemID:documentData:previewImageData:) / init(itemID:documentData:previewCGImage:)
// 功能注释: 修改后 transient payload 明确持有手绘 documentData，作为宿主层的统一提交缓存。
struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let documentData: Data
    let previewImageData: Data?
    let previewCGImage: CGImage?

    init(
        itemID: CanvasItemID,
        documentData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.documentData = documentData
        self.previewImageData = previewImageData
        previewCGImage = nil
    }

    init(
        itemID: CanvasItemID,
        documentData: Data,
        previewCGImage: CGImage
    ) {
        self.itemID = itemID
        self.documentData = documentData
        previewImageData = nil
        self.previewCGImage = previewCGImage
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingMigrationService.swift
// 函数名: HandDrawingPreparedEditingDocument / prepareBundleDocumentForEditing(record:boardDirectoryURL:) / prepareLegacyDocumentForEditing(boardID:itemID:record:entry:userDefaults:)
// 功能注释: 修改后迁移服务返回值直接以 documentData 命名，和编辑器上下文、提交对象保持一致。
struct HandDrawingPreparedEditingDocument {
    let record: BoardHandDrawingItemRecord
    let documentData: Data
    let didMigrateLegacyDocument: Bool
}

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
```

## 修改二：`CanvasEditorSession` 把编辑上下文、提交判重、复制缓存都统一切到 `documentData`

### 修改前

- `handDrawingEditorContext(for:)` 读取 transient payload 时仍取 `payload.drawingData`。
- `commitHandDrawingEdit(withID:submission:)` 判重时调用的是 `resolvedHandDrawingSourceData(for:)`。
- 复制 hand drawing item 时，辅助方法和局部变量也都还是 `sourceDrawingDataByItemID` / `resolvedHandDrawingSourceData(...)`。
- 新建 hand drawing item 的初始 transient payload 也是 `drawingData: Data()`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:)
// 功能注释: 修改前宿主编辑会话的桥接层虽然已经在传 documentData，但内部实现仍在用 drawingData/sourceData 旧命名。
if let payload = transientHandDrawingAssetPayload(for: itemID) {
    return CanvasHandDrawingEditorContext(
        itemID: itemID,
        documentID: item.documentID,
        paper: item.paper,
        documentData: payload.drawingData,
        isEmpty: item.isEmpty,
        storage: .bundle,
        didMigrateLegacyDocument: false
    )
}

if item.contentRevision == submission.contentRevision,
   item.isEmpty == submission.isEmpty,
   resolvedHandDrawingSourceData(for: item) == submission.documentData
{
    return nil
}

transientHandDrawingAssetPayloads[itemID] =
    BoardTransientHandDrawingAssetPayload(
        itemID: itemID,
        drawingData: submission.documentData,
        previewCGImage: submission.previewCGImage
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: preparedHandDrawingDuplicationSourceData(for:) / resolvedHandDrawingSourceData(for:) / registerDuplicatedHandDrawingPayloads(sourceItems:duplicatedItems:sourceDrawingDataByItemID:)
// 功能注释: 修改前复制链路继续使用 sourceDrawingData 命名，容易把“复制当前文档”误读成“复制旧 source asset”。
private func preparedHandDrawingDuplicationSourceData(
    for sourceItems: [CanvasBoardItem]
) -> [CanvasItemID: Data]? {
    var sourceDrawingDataByItemID: [CanvasItemID: Data] = [:]
    // 功能注释: 其余实现省略，核心是这里继续沿用 sourceDrawingData / resolvedHandDrawingSourceData 命名。
}
```

### 修改后

- `handDrawingEditorContext(for:)` 统一读取 `payload.documentData` 与 `preparedDocument.documentData`。
- `commitHandDrawingEdit(withID:submission:)` 的判重逻辑改成 `resolvedHandDrawingDocumentData(for:)`。
- 复制链路统一改成 `preparedHandDrawingDuplicationDocumentData(...)`、`sourceDocumentDataByItemID` 和 `documentData`。
- 新建 hand drawing item 时的初始 transient payload 也统一成 `documentData: Data()`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:)
// 功能注释: 修改后编辑上下文与提交桥接直接围绕 documentData 运作，宿主层不再传播旧 sourceData 语义。
func handDrawingEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasHandDrawingEditorContext {
    guard let item = scene.handDrawingItem(withID: itemID) else {
        throw CanvasHandDrawingEditingError.invalidHandDrawingItem(itemID: itemID)
    }

    if let payload = transientHandDrawingAssetPayload(for: itemID) {
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            documentID: item.documentID,
            paper: item.paper,
            documentData: payload.documentData,
            isEmpty: item.isEmpty,
            storage: .bundle,
            didMigrateLegacyDocument: false
        )
    }

    let preparedDocument = try HandDrawingMigrationService.prepareDocumentForEditing(
        boardID: activeBoardID,
        itemID: itemID,
        userDefaults: userDefaults
    )
    return CanvasHandDrawingEditorContext(
        itemID: itemID,
        documentID: item.documentID,
        paper: item.paper,
        documentData: preparedDocument.documentData,
        isEmpty: item.isEmpty,
        storage: preparedDocument.record.storage,
        didMigrateLegacyDocument: preparedDocument.didMigrateLegacyDocument
    )
}

if item.contentRevision == submission.contentRevision,
   item.isEmpty == submission.isEmpty,
   resolvedHandDrawingDocumentData(for: item) == submission.documentData
{
    return nil
}

transientHandDrawingAssetPayloads[itemID] =
    BoardTransientHandDrawingAssetPayload(
        itemID: itemID,
        documentData: submission.documentData,
        previewCGImage: submission.previewCGImage
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: preparedHandDrawingDuplicationDocumentData(for:) / resolvedHandDrawingDocumentData(for:) / registerDuplicatedHandDrawingPayloads(sourceItems:duplicatedItems:sourceDocumentDataByItemID:)
// 功能注释: 修改后复制链路明确在复制 documentData，避免宿主层内部继续残留 sourceDrawing 命名。
private func preparedHandDrawingDuplicationDocumentData(
    for sourceItems: [CanvasBoardItem]
) -> [CanvasItemID: Data]? {
    var sourceDocumentDataByItemID: [CanvasItemID: Data] = [:]
    for sourceItem in sourceItems {
        guard let handDrawingItem = sourceItem.handDrawingItem else {
            continue
        }
        guard let documentData = resolvedHandDrawingDocumentData(
            for: handDrawingItem
        ) else {
            return nil
        }
        sourceDocumentDataByItemID[handDrawingItem.id] = documentData
    }
    return sourceDocumentDataByItemID
}

private func resolvedHandDrawingDocumentData(
    for item: CanvasHandDrawingItem
) -> Data? {
    if let payload = transientHandDrawingAssetPayload(for: item.id) {
        return payload.documentData
    }
    guard let activeBoardID else {
        return nil
    }
    return try? BoardStore.loadHandDrawingDocumentData(
        boardID: activeBoardID,
        documentID: item.documentID,
        userDefaults: userDefaults
    )
}
```

## 修改三：`BoardStore` 的读写桥接改为 `loadHandDrawingDocumentData(...)`，持久化按 `documentData` 统一落盘

### 修改前

- `BoardStore` 对外仍提供 `loadHandDrawingSourceData(...)`。
- 保存 legacy flat asset 时写入 `payload.drawingData`。
- 保存 bundle 文档时也把 `payload.drawingData` 传给 `HandDrawingDocumentStore.persistDocument(...)`。
- 虽然功能上能工作，但阶段 8 要把宿主桥接语义收口为“文档数据”，这里的命名会造成保存层语义滞后。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadHandDrawingSourceData(boardID:documentID:userDefaults:) / persistLegacyHandDrawingAssetsIfNeeded(for:snapshot:in:) / persistBundleHandDrawingDocumentIfNeeded(for:snapshot:boardDirectoryURL:)
// 功能注释: 修改前持久化层仍沿用 sourceData / drawingData 命名，和阶段 8 的 documentData bridge 不完全一致。
static func loadHandDrawingSourceData(
    boardID: UUID,
    documentID: HandDrawingDocumentID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    // 功能注释: 其余读取逻辑省略。
}

if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
    try CoordinatedFileIO.writeData(payload.drawingData, to: sourceDrawingURL)
}

try HandDrawingDocumentStore.persistDocument(
    documentID: item.documentID,
    paper: item.paper,
    contentRevision: item.contentRevision,
    isEmpty: item.isEmpty,
    drawingData: payload.drawingData,
    previewImageData: payload.previewImageData,
    previewCGImage: payload.previewCGImage,
    boardDirectoryURL: boardDirectoryURL
)
```

### 修改后

- `BoardStore.loadHandDrawingDocumentData(...)` 成为统一读取入口：
  - bundle 存在时优先读 `document.hdraw`；
  - 否则再回退 legacy flat asset。
- legacy flat asset 持久化与 bundle 持久化都明确写 `payload.documentData`。
- 主画布、thumbnail、minimap 的上层契约没有变化，因为 preview 图与 item 几何更新逻辑保持不变，只是宿主内部读写语义被统一。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadHandDrawingDocumentData(boardID:documentID:userDefaults:)
// 功能注释: 修改后对外读取入口明确返回 hand drawing documentData，同时保留 legacy flat asset fallback。
static func loadHandDrawingDocumentData(
    boardID: UUID,
    documentID: HandDrawingDocumentID,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        let boardDirectoryURL = self.boardDirectoryURL(
            for: boardID,
            boardsDirectoryURL: boardsDirectoryURL
        )
        let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
            assetsDirectoryName,
            isDirectory: true
        )
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
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: persistLegacyHandDrawingAssetsIfNeeded(for:snapshot:in:) / persistBundleHandDrawingDocumentIfNeeded(for:snapshot:boardDirectoryURL:)
// 功能注释: 修改后无论写 legacy flat asset 还是写 bundle，都明确落 payload.documentData。
if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
    try CoordinatedFileIO.writeData(payload.documentData, to: sourceDrawingURL)
    // 功能注释: previewImageData / previewCGImage 的编码逻辑保持原样。
}

if let payload = snapshot.transientHandDrawingAssetPayload(for: item.id) {
    try HandDrawingDocumentStore.persistDocument(
        documentID: item.documentID,
        paper: item.paper,
        contentRevision: item.contentRevision,
        isEmpty: item.isEmpty,
        drawingData: payload.documentData,
        previewImageData: payload.previewImageData,
        previewCGImage: payload.previewCGImage,
        boardDirectoryURL: boardDirectoryURL
    )
}
```

## 修改四：删除未使用的 `missingSourceDrawing` 错误分支，去掉旧 source asset 语义残留

### 修改前

- `CanvasHandDrawingEditingError` 里还有 `missingSourceDrawing(itemID:)`。
- 但当前 `CanvasEditorSession.handDrawingEditorContext(for:)` 与 `commitHandDrawingEdit(...)` 并没有实际抛出这条错误。
- 这个分支只会继续暗示“编辑器必须依赖旧 source drawing asset”，不符合阶段 8 的 bridge 收口目标。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditingError.errorDescription
// 功能注释: 修改前错误枚举里还保留了 missingSourceDrawing，属于未使用的旧语义残留。
enum CanvasHandDrawingEditingError: LocalizedError {
    case invalidHandDrawingItem(itemID: CanvasItemID)
    case missingBoardIdentity
    case missingSourceDrawing(itemID: CanvasItemID)
    case failedToCreateBlankPreview(paperID: String)

    var errorDescription: String? {
        switch self {
        case let .invalidHandDrawingItem(itemID):
            return "The selected item is not a valid hand drawing item: \(itemID.uuidString)"
        case .missingBoardIdentity:
            return "Unable to resolve the active board for hand drawing editing."
        case let .missingSourceDrawing(itemID):
            return "The hand drawing source asset is missing for item \(itemID.uuidString)."
        case let .failedToCreateBlankPreview(paperID):
            return "Unable to create a blank preview image for paper \(paperID)."
        }
    }
}
```

### 修改后

- `missingSourceDrawing(itemID:)` 已删除。
- `CanvasHandDrawingEditingError` 只保留当前宿主桥接真实还会发生的错误类型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditingError.errorDescription
// 功能注释: 修改后错误枚举与当前宿主桥接真实路径对齐，不再保留未使用的旧 source asset 分支。
enum CanvasHandDrawingEditingError: LocalizedError {
    case invalidHandDrawingItem(itemID: CanvasItemID)
    case missingBoardIdentity
    case failedToCreateBlankPreview(paperID: String)

    var errorDescription: String? {
        switch self {
        case let .invalidHandDrawingItem(itemID):
            return "The selected item is not a valid hand drawing item: \(itemID.uuidString)"
        case .missingBoardIdentity:
            return "Unable to resolve the active board for hand drawing editing."
        case let .failedToCreateBlankPreview(paperID):
            return "Unable to create a blank preview image for paper \(paperID)."
        }
    }
}
```

## 修改五：补阶段 8 回归测试，锁定 transient reopen 与 legacy -> bundle 提交保存闭环

### 修改前

- `CanvasHandDrawingEditingSessionTests` 只验证提交后 transient payload 非空，没有验证 payload 里到底保存了什么，也没有验证重新打开编辑器时会优先读取 transient 文档。
- `HandDrawingMigrationServiceTests` 只验证 `prepareDocumentForEditing(...)` 能迁移 legacy 文档，还没有覆盖“session 打开 -> commit -> saveBoard -> bundle 持久化”的完整宿主闭环。
- `BoardHandDrawingStorageTests` 的读取断言也仍使用旧的 `loadHandDrawingSourceData(...)` 名称。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo()
// 功能注释: 修改前测试只检查 transient payload 存在，不检查其中保存的文档内容。
XCTAssertEqual(result.refreshReason, "commit hand drawing edit")
let updatedItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
XCTAssertFalse(updatedItem.isEmpty)
XCTAssertEqual(updatedItem.contentRevision, updatedRevision)
XCTAssertNotNil(session.transientHandDrawingAssetPayload(for: item.id))
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen()
// 功能注释: 修改前 migration tests 只覆盖“打开前迁移”，没有覆盖提交后 saveBoard 的 bundle 持久化闭环。
let firstContext = try session.handDrawingEditorContext(for: fixture.itemID)
let secondContext = try session.handDrawingEditorContext(for: fixture.itemID)

XCTAssertEqual(firstContext.storage, .bundle)
XCTAssertTrue(firstContext.didMigrateLegacyDocument)
XCTAssertEqual(firstContext.documentData, fixture.drawingData)

XCTAssertEqual(secondContext.storage, .bundle)
XCTAssertFalse(secondContext.didMigrateLegacyDocument)
```

### 修改后

- `CanvasHandDrawingEditingSessionTests` 新增：
  - 提交后断言 `transientPayload.documentData == documentData`；
  - `testHandDrawingEditorContextReopensFromTransientDocumentData()`，验证重新打开编辑器时优先回读 transient 文档。
- `HandDrawingMigrationServiceTests` 新增：
  - `testCanvasEditorSessionCommitHandDrawingEditPersistsMigratedDocumentAsBundle()`，完整验证 legacy item 迁移后提交、自定义 `documentData` 保存、bundle 落盘，以及旧 flat asset 被清理。
- `BoardHandDrawingStorageTests` 的读取断言同步改到 `loadHandDrawingDocumentData(...)`，和阶段 8 语义保持一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo() / testHandDrawingEditorContextReopensFromTransientDocumentData()
// 功能注释: 修改后 editing session tests 不只验证“payload 存在”，还验证 transient documentData 内容与 reopen 行为。
let transientPayload = try XCTUnwrap(
    session.transientHandDrawingAssetPayload(for: item.id)
)
XCTAssertEqual(transientPayload.documentData, documentData)

func testHandDrawingEditorContextReopensFromTransientDocumentData() throws {
    let session = makeHandDrawingEditingTestSession()
    let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
    let previewImage = try makeHandDrawingEditingTestImage(
        red: 0.75,
        green: 0.2,
        blue: 0.45
    )
    let documentData = try HandDrawingDocumentCodec.makeDocumentData(
        for: makeHandDrawingTestDocument(includeEraseMask: true)
    )

    _ = try session.commitHandDrawingEdit(
        withID: item.id,
        submission: CanvasHandDrawingEditSubmission(
            documentData: documentData,
            previewCGImage: previewImage,
            isEmpty: false,
            contentRevision: UUID()
        )
    )

    let editorContext = try session.handDrawingEditorContext(for: item.id)
    XCTAssertEqual(editorContext.documentData, documentData)
    XCTAssertEqual(editorContext.storage, .bundle)
    XCTAssertFalse(editorContext.didMigrateLegacyDocument)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testCanvasEditorSessionCommitHandDrawingEditPersistsMigratedDocumentAsBundle()
// 功能注释: 修改后新增阶段 8 闭环测试，覆盖 legacy -> migrate -> commit -> saveBoard -> bundle 落盘。
func testCanvasEditorSessionCommitHandDrawingEditPersistsMigratedDocumentAsBundle() throws {
    try withTemporaryHandDrawingMigrationWorkspace { selectedFolderURL, userDefaults in
        let fixture = try makeLegacyHandDrawingFixture(
            selectedFolderURL: selectedFolderURL,
            drawingData: PKDrawing().dataRepresentation()
        )
        let session = CanvasEditorSession(
            saveQueueLabel: "HandDrawingMigrationServiceTests.Commit",
            logPrefix: "[HandDrawingMigrationServiceTests]",
            userDefaults: userDefaults
        )

        try session.loadBoard(id: fixture.boardID)
        let editorContext = try session.handDrawingEditorContext(for: fixture.itemID)
        let updatedDocumentData = try HandDrawingDocumentCodec.makeDocumentData(
            for: makeHandDrawingTestDocument(includeEraseMask: true)
        )
        let updatedPreviewImage = try makeHandDrawingMigrationTestImage(alpha: 1)
        let updatedRevision = UUID()

        XCTAssertTrue(editorContext.didMigrateLegacyDocument)

        let commitResult = try XCTUnwrap(
            session.commitHandDrawingEdit(
                withID: fixture.itemID,
                submission: CanvasHandDrawingEditSubmission(
                    documentData: updatedDocumentData,
                    previewCGImage: updatedPreviewImage,
                    isEmpty: false,
                    contentRevision: updatedRevision
                )
            )
        )
        let saveSnapshot = try XCTUnwrap(session.currentBoardSaveSnapshot())
        try BoardStore.saveBoard(saveSnapshot, userDefaults: userDefaults)
        let entry = try XCTUnwrap(
            BoardStore.loadBoardDocumentEntry(
                id: fixture.boardID,
                userDefaults: userDefaults
            )
        )

        XCTAssertEqual(commitResult.refreshReason, "commit hand drawing edit")
        XCTAssertEqual(entry.document.handDrawingItemRecords.first?.storage, .bundle)
        XCTAssertEqual(
            try BoardStore.loadHandDrawingDocumentData(
                boardID: fixture.boardID,
                documentID: fixture.documentID,
                userDefaults: userDefaults
            ),
            updatedDocumentData
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail()
// 功能注释: 修改后 storage tests 也使用 loadHandDrawingDocumentData，和阶段 8 的统一宿主桥接命名保持一致。
XCTAssertEqual(
    try BoardStore.loadHandDrawingDocumentData(
        boardID: boardID,
        documentID: runtimeState.handDrawingItems[0].documentID,
        userDefaults: userDefaults
    ),
    secondDrawingData
)
```

## 结果小结

- 阶段 8 这轮实际没有改主画布、thumbnail、minimap 的消费接口，而是把宿主编辑桥接、迁移返回值、暂存缓存和持久化读写的内部语义统一到了 `documentData`。
- `legacyFlatAssetPair` 的兼容能力仍然保留，但新的编辑与保存闭环已经明确以 bundle 文档为主。
- 本轮回归测试已经覆盖：
  - transient documentData reopen；
  - legacy -> bundle 提交保存；
  - documentData 读取命名统一；
  - 宿主命令 / context menu / toolbar 的相关验证链未回归失败。
