# 20260518_181516_CST_hand_drawing_kernel_phase9_regression_guardrails_record

## 记录范围

- 记录内容：
  1. 实施阶段 9 的测试、性能与回归收口。
  2. 本轮只扩展 / 新增 hand drawing 相关测试护栏，不修改生产代码实现。
  3. 补齐文档编解码、bundle 存储、preview 正确性、编辑会话重开链路，以及像素橡皮 / 套索 / 移动的边界行为测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_181516_CST`
- 说明：
  - 本记录以阶段 8 完成态为基线，结合当前 `git status`、当前 `git diff`、当前文件内容与本轮测试结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
  - 本轮阶段 9 没有改动 hand drawing 运行时代码，所有新增内容都落在测试文件。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
  - 阶段 8 记录：
    - `commit_records/20260518_175557_CST_hand_drawing_kernel_phase8_host_bridge_record.md`
- 当前 changes 摘要：
  - 阶段 9 本轮改动：
    - `M MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
    - `M MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift`
    - `M MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
  - 当前工作区还存在以下非本轮阶段 9 改动：
    - `M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
  - 处理原则：
    - 上述 `xcuserstate` 属于 IDE 用户界面状态文件，非本轮阶段 9 测试护栏改动，不纳入本记录。
- 验证结果：
  - `xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS,arch=arm64,name=My Mac' -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests -only-testing:MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
  - 命令输出备注：
    - 测试通过；
    - 构建输出里仍可见既有的 Swift 6 actor-isolation warning，本轮未处理该警告收口。
- 本记录不包含：
  - 阶段 10 之后的工作
  - 生产代码修复
  - git commit / push

## 修改一：补齐 `HandDrawingDocumentCodecTests` 与 `HandDrawingDocumentStoreTests` 的编解码 / preview 存储护栏

### 修改前

- `HandDrawingDocumentCodecTests` 只覆盖：
  - 自研文档 round-trip；
  - `formatVersion` 非法时拒绝解码。
- `HandDrawingDocumentStoreTests` 只覆盖：
  - bundle round-trip；
  - typed document round-trip；
  - orphan bundle 清理。
- 阶段 9 计划里明确点到 `DocumentCodec` / `DocumentStore`，但此前还没有把 manifest、preview PNG 编解码、非法 preview 数据、显式 `previewImageData` 写入路径补齐。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
// 函数名: testHandDrawingDocumentCodecRoundTripsCustomDocument() / testHandDrawingDocumentCodecRejectsUnsupportedFormatVersion()
// 功能注释: 修改前 codec tests 只覆盖文档本体 round-trip 与 formatVersion 拒绝，没有覆盖 manifest 与 preview 编解码。
final class HandDrawingDocumentCodecTests: XCTestCase {
    func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
        let document = makeHandDrawingTestDocument(includeEraseMask: true)
        let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)
        XCTAssertEqual(decodedDocument, document)
    }

    func testHandDrawingDocumentCodecRejectsUnsupportedFormatVersion() throws {
        let document = makeHandDrawingTestDocument()
        let encodedData = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        // 功能注释: 其余异常断言省略。
        _ = encodedData
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStorePersistsBundleRoundTrip() / testHandDrawingDocumentStorePersistsTypedDocumentRoundTrip() / testHandDrawingDocumentStoreRemovesOrphanedBundles()
// 功能注释: 修改前 DocumentStore tests 还没有验证 previewImageData 显式写入路径。
final class HandDrawingDocumentStoreTests: XCTestCase {
    func testHandDrawingDocumentStorePersistsBundleRoundTrip() throws {
        // 功能注释: 其余已有测试实现省略。
    }

    func testHandDrawingDocumentStorePersistsTypedDocumentRoundTrip() throws {
        // 功能注释: 其余已有测试实现省略。
    }

    func testHandDrawingDocumentStoreRemovesOrphanedBundles() throws {
        // 功能注释: 其余已有测试实现省略。
    }
}
```

### 修改后

- `HandDrawingDocumentCodecTests` 新增：
  - `testHandDrawingDocumentCodecRoundTripsManifest()`
  - `testHandDrawingDocumentCodecRoundTripsPreviewPNGData()`
  - `testHandDrawingDocumentCodecRejectsInvalidPreviewImageData()`
- `HandDrawingDocumentStoreTests` 新增：
  - `testHandDrawingDocumentStorePersistsProvidedPreviewImageData()`
- 这样阶段 9 针对 codec / store 的关键公开接口都被直接覆盖，而不是只通过更高层测试间接兜住。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
// 函数名: testHandDrawingDocumentCodecRoundTripsManifest() / testHandDrawingDocumentCodecRoundTripsPreviewPNGData() / testHandDrawingDocumentCodecRejectsInvalidPreviewImageData()
// 功能注释: 修改后 codec tests 把 manifest、preview PNG 编解码和非法 preview 输入全部纳入回归护栏。
func testHandDrawingDocumentCodecRoundTripsManifest() throws {
    let manifest = HandDrawingManifest(
        documentID: UUID(),
        paper: CanvasHandDrawingPaperSpec(
            id: "codec-paper",
            size: CGSize(width: 240, height: 180)
        ),
        contentRevision: UUID(),
        isEmpty: false,
        migrationOrigin: .legacyFlatAssetPair
    )

    let encodedData = try HandDrawingDocumentCodec.makeManifestData(for: manifest)
    let decodedManifest = try HandDrawingDocumentCodec.decodeManifest(
        from: encodedData
    )

    XCTAssertEqual(decodedManifest, manifest)
}

func testHandDrawingDocumentCodecRoundTripsPreviewPNGData() throws {
    let documentID = UUID()
    let previewImage = try makeHandDrawingDocumentCodecTestImage(
        red: 0.85,
        green: 0.25,
        blue: 0.35
    )

    let previewImageData = try HandDrawingDocumentCodec.makePNGData(
        for: previewImage,
        documentID: documentID
    )
    let decodedPreviewImage = try HandDrawingDocumentCodec.decodePreviewImage(
        from: previewImageData,
        documentID: documentID
    )

    XCTAssertEqual(
        BoardThumbnailImageSignature.describe(decodedPreviewImage),
        BoardThumbnailImageSignature.describe(previewImage)
    )
}

func testHandDrawingDocumentCodecRejectsInvalidPreviewImageData() throws {
    let documentID = UUID()
    XCTAssertThrowsError(
        try HandDrawingDocumentCodec.decodePreviewImage(
            from: Data("not-a-preview".utf8),
            documentID: documentID
        )
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStorePersistsProvidedPreviewImageData()
// 功能注释: 修改后直接验证 persistDocument(previewImageData:) 路径，确保 bundle 里保存的是调用方给定的 preview 数据。
func testHandDrawingDocumentStorePersistsProvidedPreviewImageData() throws {
    try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
        let documentID = UUID()
        let contentRevision = UUID()
        let previewImage = try makeHandDrawingDocumentStoreTestImage(
            red: 0.25,
            green: 0.7,
            blue: 0.35
        )
        let previewImageData = try HandDrawingDocumentCodec.makePNGData(
            for: previewImage,
            documentID: documentID
        )

        try HandDrawingDocumentStore.persistDocument(
            documentID: documentID,
            paper: .square,
            contentRevision: contentRevision,
            isEmpty: false,
            drawingData: Data("preview-image-data-round-trip".utf8),
            previewImageData: previewImageData,
            previewCGImage: nil,
            boardDirectoryURL: boardDirectoryURL
        )

        let storedPreviewImageData = try HandDrawingDocumentStore
            .loadPreviewImageData(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        let loadedPreviewImage = try HandDrawingDocumentStore.loadPreviewImage(
            documentID: documentID,
            boardDirectoryURL: boardDirectoryURL
        )

        XCTAssertEqual(storedPreviewImageData, previewImageData)
        XCTAssertEqual(
            BoardThumbnailImageSignature.describe(loadedPreviewImage),
            BoardThumbnailImageSignature.describe(previewImage)
        )
    }
}
```

## 修改二：补齐 `HandDrawingPreviewRendererTests` 与 `BoardHandDrawingStorageTests` 的 preview / thumbnail 一致性护栏

### 修改前

- `HandDrawingPreviewRendererTests` 只验证：
  - stroke 会产生可见像素；
  - erase mask 会影响局部 alpha。
- `BoardHandDrawingStorageTests` 已经覆盖通用保存 / 覆盖 / 空 preview / duplication，但还没有直接验证“局部擦除后 persisted preview 与 thumbnail 一起刷新”。
- 阶段 9 手工验收清单里明确要求：
  - 颜色与粗细切换后 preview 正确；
  - 像素橡皮局部擦除后主画布 / thumbnail 一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() / testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask()
// 功能注释: 修改前 preview tests 只覆盖“能画出来”和“eraseMask 生效”，没有覆盖颜色与线宽差异。
final class HandDrawingPreviewRendererTests: XCTestCase {
    func testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument()
        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let centerPixel = sampleRGBA(from: image, x: 60, y: 60)
        XCTAssertGreaterThan(centerPixel.alpha, 0)
    }

    func testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument(includeEraseMask: true)
        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let erasedPixel = sampleRGBA(from: image, x: 60, y: 60)
        let preservedPixel = sampleRGBA(from: image, x: 35, y: 60)
        XCTAssertLessThan(erasedPixel.alpha, preservedPixel.alpha)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail()
// 功能注释: 修改前 storage tests 能验证普通覆盖写入，但没有把“局部擦除导致 preview / thumbnail 双更新”单独钉住。
func testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail() throws {
    // 功能注释: 其余已有测试实现省略。
}
```

### 修改后

- `HandDrawingPreviewRendererTests` 新增 `testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences()`。
- `BoardHandDrawingStorageTests` 新增 `testBoardStoreRefreshesHandDrawingPreviewAndThumbnailAfterLocalEraseUpdate()`。
- 这样 preview 正确性和 persisted preview / thumbnail 一致性从“间接覆盖”变成了“显式回归护栏”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences()
// 功能注释: 修改后直接验证 preview 对颜色与线宽差异的响应，覆盖阶段 9 的颜色/粗细验收点。
func testHandDrawingPreviewRendererReflectsBrushColorAndLineWidthDifferences() throws {
    let renderer = HandDrawingPreviewRenderer()
    let thinStroke = makePreviewRendererTestStroke(
        y: 34,
        baseSize: 6,
        color: HandDrawingColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)
    )
    let thickStroke = makePreviewRendererTestStroke(
        y: 86,
        baseSize: 24,
        color: HandDrawingColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1)
    )
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(id: "preview-paper", size: CGSize(width: 120, height: 120)),
        strokes: [thinStroke, thickStroke]
    )

    let image = try renderer.renderPreviewImage(for: document, scale: 1)
    let thinCenterPixel = sampleRGBA(from: image, x: 60, y: 34)
    let thickCenterPixel = sampleRGBA(from: image, x: 60, y: 86)
    let thinEdgePixel = sampleRGBA(from: image, x: 60, y: 42)
    let thickEdgePixel = sampleRGBA(from: image, x: 60, y: 94)

    XCTAssertGreaterThan(thinCenterPixel.red, thinCenterPixel.green)
    XCTAssertGreaterThan(thickCenterPixel.green, thickCenterPixel.red)
    XCTAssertLessThan(thinEdgePixel.alpha, 16)
    XCTAssertGreaterThan(thickEdgePixel.alpha, 64)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStoreRefreshesHandDrawingPreviewAndThumbnailAfterLocalEraseUpdate()
// 功能注释: 修改后直接验证局部擦除后的新 documentData、新 preview 和新 thumbnail 会一起持久化。
func testBoardStoreRefreshesHandDrawingPreviewAndThumbnailAfterLocalEraseUpdate() throws {
    try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
        let boardID = UUID()
        let itemID = UUID()
        let initialDocument = makeHandDrawingTestDocument()
        let erasedDocument = makeHandDrawingTestDocument(includeEraseMask: true)
        let initialPreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: initialDocument,
            scale: 1
        )
        let erasedPreviewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
            for: erasedDocument,
            scale: 1
        )

        // 功能注释: 先保存初始态，再保存局部擦除后的新文档。
        // 功能注释: 其余 setup 省略。

        XCTAssertNotEqual(initialThumbnailSignature, erasedThumbnailSignature)
        XCTAssertEqual(
            BoardThumbnailImageSignature.describe(persistedPreviewImage),
            BoardThumbnailImageSignature.describe(erasedPreviewImage)
        )
        XCTAssertEqual(
            try BoardStore.loadHandDrawingDocumentData(
                boardID: boardID,
                documentID: initialItem.documentID,
                userDefaults: userDefaults
            ),
            erasedDocumentData
        )
    }
}
```

## 修改三：扩展 `CanvasHandDrawingEditingSessionTests`，把“新建立即打开 / 保存后重开”链路补成闭环测试

### 修改前

- `CanvasHandDrawingEditingSessionTests` 只覆盖：
  - 提交编辑后更新 item；
  - undo / redo；
  - transient `documentData` reopen。
- 还没有单独验证：
  - 新建 hand drawing 后，立刻打开编辑器应该拿到空文档上下文；
  - 保存到 board 后，重启 session / reload board 还能拿到同一份文档数据。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo() / testHandDrawingEditorContextReopensFromTransientDocumentData()
// 功能注释: 修改前 editing session tests 还没有把“立即打开”和“持久化后重开”作为独立回归用例。
final class CanvasHandDrawingEditingSessionTests: XCTestCase {
    func testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo() throws {
        // 功能注释: 其余已有测试实现省略。
    }

    func testHandDrawingEditorContextReopensFromTransientDocumentData() throws {
        // 功能注释: 其余已有测试实现省略。
    }
}
```

### 修改后

- 新增 `testAddHandDrawingItemProvidesImmediateEmptyEditorContext()`。
- 新增 `testHandDrawingEditPersistsAcrossBoardReload()`。
- 同时新增临时 workspace 辅助函数，让测试不依赖全局 `UserDefaults.standard`。
- 这组测试直接覆盖了阶段 9 手工验收清单里的：
  - 新建 -> 立即打开；
  - 返回后再次编辑；
  - 重启项目后再次进入编辑器。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testAddHandDrawingItemProvidesImmediateEmptyEditorContext() / testHandDrawingEditPersistsAcrossBoardReload()
// 功能注释: 修改后 editing session tests 把“新建立即打开”和“保存后重开”补成显式回归闭环。
func testAddHandDrawingItemProvidesImmediateEmptyEditorContext() throws {
    let session = makeHandDrawingEditingTestSession()
    let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))

    let editorContext = try session.handDrawingEditorContext(for: item.id)
    XCTAssertEqual(editorContext.itemID, item.id)
    XCTAssertTrue(editorContext.documentData.isEmpty)
    XCTAssertTrue(editorContext.isEmpty)
    XCTAssertEqual(editorContext.storage, .bundle)
    XCTAssertFalse(editorContext.didMigrateLegacyDocument)
}

func testHandDrawingEditPersistsAcrossBoardReload() throws {
    try withTemporaryHandDrawingEditingWorkspace { _, userDefaults in
        let session = makeHandDrawingEditingTestSession(userDefaults: userDefaults)
        session.startNewBoard(now: Date(timeIntervalSince1970: 1_720_300_000))

        let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
        let boardID = try XCTUnwrap(session.activeBoardID)
        let previewImage = try makeHandDrawingEditingTestImage(
            red: 0.1,
            green: 0.6,
            blue: 0.85
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

        let saveSnapshot = try XCTUnwrap(session.currentBoardSaveSnapshot())
        try BoardStore.saveBoard(saveSnapshot, userDefaults: userDefaults)

        let restartedSession = makeHandDrawingEditingTestSession(
            userDefaults: userDefaults
        )
        try restartedSession.loadBoard(id: boardID)

        let editorContext = try restartedSession.handDrawingEditorContext(
            for: item.id
        )
        XCTAssertEqual(editorContext.documentData, documentData)
        XCTAssertFalse(editorContext.isEmpty)
        XCTAssertEqual(editorContext.storage, .bundle)
        XCTAssertFalse(editorContext.didMigrateLegacyDocument)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: withTemporaryHandDrawingEditingWorkspace(_:) / makeHandDrawingEditingTestSession(userDefaults:)
// 功能注释: 修改后测试使用独立 workspace 和独立 UserDefaults，避免把持久化重开测试污染到全局环境。
private func makeHandDrawingEditingTestSession(
    userDefaults: UserDefaults = .standard
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasHandDrawingEditingSessionTests",
        logPrefix: "[CanvasHandDrawingEditingSessionTests]",
        userDefaults: userDefaults
    )
    CanvasHandDrawingEditingSessionTestRetainer.sessions.append(session)
    return session
}

private func withTemporaryHandDrawingEditingWorkspace(
    _ body: (URL, UserDefaults) throws -> Void
) throws {
    // 功能注释: 其余目录准备逻辑省略，核心是为 board reload 测试提供独立 bookmark + workspace。
}
```

## 修改四：补齐像素橡皮、套索、移动三类控制器的取消与边界行为测试

### 修改前

- `HandDrawingPixelEraserToolControllerTests` 只覆盖：
  - pressure 缩放后的命中；
  - 不连续命中拆分多个 erase path。
- `HandDrawingLassoSelectionTests` 只覆盖：
  - 完整包围选中 + undo / redo。
- `HandDrawingMoveSelectionTests` 只覆盖：
  - 平移后位置更新 + undo 恢复。
- 还没有把这些交互状态机里最容易回归的边界行为补进测试：
  - 橡皮取消应回滚文档；
  - 套索对部分包围 stroke 不应误选；
  - 移动取消应恢复位置。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() / testHandDrawingPixelEraserToolControllerSplitsDisjointHitSequencesIntoSeparateErasePaths()
// 功能注释: 修改前像素橡皮 tests 还没有覆盖 cancel 回滚。
final class HandDrawingPixelEraserToolControllerTests: XCTestCase {
    func testHandDrawingPixelEraserToolControllerAppliesPressureScaledEraseMaskOnlyToHitStroke() {
        // 功能注释: 其余已有测试实现省略。
    }

    func testHandDrawingPixelEraserToolControllerSplitsDisjointHitSequencesIntoSeparateErasePaths() {
        // 功能注释: 其余已有测试实现省略。
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo()
// 功能注释: 修改前套索 tests 还没有把“部分包围不能选中”单独钉住。
func testHandDrawingLassoToolControllerSelectsOnlyEnclosedStrokeAndSupportsUndoRedo() {
    // 功能注释: 其余已有测试实现省略。
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition()
// 功能注释: 修改前移动 tests 只覆盖 undo 恢复，不覆盖交互中 cancel 恢复。
func testHandDrawingMoveSelectionControllerTranslatesSelectedStrokeAndUndoRestoresPosition() {
    // 功能注释: 其余已有测试实现省略。
}
```

### 修改后

- `HandDrawingPixelEraserToolControllerTests` 新增 `testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument()`。
- `HandDrawingLassoSelectionTests` 新增 `testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke()`。
- `HandDrawingMoveSelectionTests` 新增 `testHandDrawingMoveSelectionControllerCancelRestoresPosition()`。
- 这样阶段 6 / 7 的交互控制器不只验证 happy path，也把 cancel / boundary behavior 锁住了。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests.swift
// 函数名: testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument()
// 功能注释: 修改后像素橡皮 tests 直接验证 cancelErasing(engine:) 会 undo 已应用的本次擦除。
func testHandDrawingPixelEraserToolControllerCancelRestoresOriginalDocument() {
    let stroke = makeHandDrawingTestStroke(id: UUID())
    var engine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "cancel-paper",
                size: CGSize(width: 120, height: 120)
            ),
            strokes: [stroke]
        )
    )
    var controller = HandDrawingPixelEraserToolController()

    controller.beginErasing(
        with: HandDrawingInputSample(
            location: CGPoint(x: 60, y: 60),
            force: 1,
            timestamp: 0
        ),
        baseSize: 18,
        engine: &engine
    )

    XCTAssertTrue(controller.isActive)
    XCTAssertEqual(engine.state.document.strokes[0].eraseMask.count, 1)

    controller.cancelErasing(engine: &engine)

    XCTAssertFalse(controller.isActive)
    XCTAssertTrue(engine.state.document.strokes[0].eraseMask.isEmpty)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests.swift
// 函数名: testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke()
// 功能注释: 修改后套索 tests 直接验证 V1 只选“整笔 / 整 stroke”，部分包围不应误选。
func testHandDrawingLassoToolControllerExcludesPartiallyEnclosedStroke() {
    let enclosedStroke = makeHandDrawingTestStroke(id: UUID())
    let partiallyOverlappingStroke = makeHandDrawingTestStroke(
        id: UUID(),
        transform: HandDrawingStrokeTransform(translationX: 20)
    )
    var engine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "lasso-partial-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [enclosedStroke, partiallyOverlappingStroke]
        )
    )
    var controller = HandDrawingLassoToolController()

    // 功能注释: 其余套索采样过程省略。

    XCTAssertTrue(controller.endLasso(engine: &engine))
    XCTAssertEqual(engine.state.selectedStrokeIDs, [enclosedStroke.id])
    XCTAssertFalse(
        engine.state.selectedStrokeIDs.contains(partiallyOverlappingStroke.id)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests.swift
// 函数名: testHandDrawingMoveSelectionControllerCancelRestoresPosition()
// 功能注释: 修改后移动 tests 直接验证 cancelMoving(engine:) 会恢复平移前位置并结束交互状态。
func testHandDrawingMoveSelectionControllerCancelRestoresPosition() {
    let stroke = makeHandDrawingTestStroke(id: UUID())
    var engine = HandDrawingEditorEngine(
        document: HandDrawingDocument(
            paper: HandDrawingPaper(
                id: "move-cancel-paper",
                size: CGSize(width: 140, height: 140)
            ),
            strokes: [stroke]
        )
    )
    XCTAssertTrue(engine.selectStrokes(withIDs: [stroke.id]))

    var controller = HandDrawingMoveSelectionController()
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
                location: CGPoint(x: 74, y: 68),
                timestamp: 0.1
            )
        ],
        engine: &engine
    )
    controller.cancelMoving(engine: &engine)

    let restoredStroke = engine.state.document.strokes[0]
    XCTAssertEqual(restoredStroke.transform.translationX, 0, accuracy: 0.001)
    XCTAssertEqual(restoredStroke.transform.translationY, 0, accuracy: 0.001)
    XCTAssertEqual(engine.state.selectedStrokeIDs, [stroke.id])
    XCTAssertFalse(controller.isActive)
}
```

## 结果小结

- 阶段 9 这轮没有继续扩写生产代码，而是把前 1-8 阶段已经落地的 hand drawing 主链补成更密的回归网。
- 本轮新增测试重点分别对应计划里的三类核心风险：
  - 数据边界：`DocumentCodec` / `DocumentStore`
  - 渲染契约：`PreviewRenderer` / `BoardHandDrawingStorage`
  - 编辑行为：`CanvasHandDrawingEditingSession` / 像素橡皮 / 套索 / 移动
- 本轮回归跑批里还复用了未修改但计划点名的测试：
  - `HandDrawingMigrationServiceTests`
  - `HandDrawingCanvasRendererTests`
  - `HandDrawingPreviewPipelineTests`
  - `HandDrawingDocumentLoaderTests`
