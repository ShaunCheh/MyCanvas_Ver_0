# 20260515_234755_text_content_driven_phase5_record

## 记录范围

- 记录内容：
  - 实施“文字内容驱动尺寸”计划的 `phase 5`，把旧文档里的 text item 在加载到 runtime 时立即归一到“内容决定尺寸”的新语义。
  - 让 `BoardDocumentMapper` 在恢复 `CanvasTextItem` 时，不再沿用旧固定框 `size`，而是按 `text + style` 重算 intrinsic `size`。
  - 让 runtime `boardState` 在加载后继续包住归一后的 item bounds，避免旧 `boardRect` 无法覆盖变大后的文字。
  - 补一条 migration 回归测试，锁定旧文档 text size 会在加载时被忽略并重算。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 显示上述 `2` 个文件处于修改状态。
  - 生成本记录前，`git diff --stat -- MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift` 显示共 `72 insertions(+), 18 deletions(-)`。
- 本记录不包含：
  - inline text editor 的字号控件与命令层接线
  - 持久化 schema 变更
  - board list 独立预览链路上的旧 text size 归一

## 当前 changes 摘要

- `BoardDocumentMapper.makeRuntimeState(...)` 现在通过新增的 `makeTextItem(from:)` 恢复 text item，运行时 `size` 统一来自共享测量 helper，而不是旧持久化框尺寸。
- `BoardDocumentMapper.makeBoardState(...)` 现在会接收已加载的 `items`，并对每个 item 的 `worldBounds` 做一次 `expandIfNeeded(...)`，让旧文档进入 runtime 后的 board surface 仍然完整覆盖新语义文字。
- `BoardSelectionStateMigrationTests` 新增了 `testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad()`，同时把 `makeBoardDocument(...)` helper 扩展为可注入 `boardBaseSize`、`boardRect` 和 `items`，便于构造 legacy 文档场景。

## 修改一：旧文档 text item 在加载时不再沿用旧固定框 size

### 修改前

- `BoardDocumentMapper.makeRuntimeState(...)` 在恢复 `BoardTextItemRecord` 时，直接把持久化的 `textRecord.size` 写入 runtime `CanvasTextItem.size`。
- 这会让旧文档里的“固定框语义”直接泄漏进当前 runtime，即便主渲染层已经移除了 shrink-to-fit，旧内容仍可能带着过小或过时的 box 尺寸进入交互和渲染。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift（修改前）
// 函数名: makeRuntimeState(from:imageLoader:)
// 功能说明: 修改前 mapper 恢复 text item 时直接采用持久化 size，旧固定框语义会原样进入 runtime。
case let .text(textRecord):
    return CanvasBoardItem.text(
        CanvasTextItem(
            id: textRecord.id,
            text: textRecord.text,
            style: textRecord.style.canvasTextStyle,
            center: textRecord.center.cgPoint,
            size: textRecord.size.cgSize,
            zIndex: CGFloat(textRecord.zIndex),
            rotationRadians: CGFloat(textRecord.rotationRadians ?? 0)
        )
    )
```

### 修改后

- `makeRuntimeState(...)` 把 text item 的恢复收口到 `makeTextItem(from:)`。
- `makeTextItem(from:)` 统一从 `textRecord.text + textRecord.style.canvasTextStyle` 出发，通过 `CanvasTextLayoutMeasurer.intrinsicItemSize(...)` 重算 intrinsic `size`。
- 这样旧文档一旦进入 runtime，就立刻切换到 phase 1~4 已经建立好的共享测量契约。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeTextItem(from:)
// 功能说明: 修改后加载链路统一按 text + style 重算 runtime text item 的 intrinsic size，旧持久化 size 不再参与运行时语义。
case let .text(textRecord):
    return CanvasBoardItem.text(makeTextItem(from: textRecord))

private static func makeTextItem(
    from textRecord: BoardTextItemRecord
) -> CanvasTextItem {
    let style = textRecord.style.canvasTextStyle
    return CanvasTextItem(
        id: textRecord.id,
        text: textRecord.text,
        style: style,
        center: textRecord.center.cgPoint,
        size: CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: textRecord.text,
            style: style
        ),
        zIndex: CGFloat(textRecord.zIndex),
        rotationRadians: CGFloat(textRecord.rotationRadians ?? 0)
    )
}
```

## 修改二：runtime boardState 在加载时吸收归一后的 item bounds

### 修改前

- `makeBoardState(...)` 只根据持久化的 `boardBaseSize / boardRect` 构造 `CanvasBoardState`。
- 如果旧文档里的文字在归一后比原来的持久化 `size` 更大，旧 `boardRect` 可能不再完整覆盖这些新 bounds。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift（修改前）
// 函数名: makeBoardState(boardBaseSize:boardRect:)
// 功能说明: 修改前 boardState 只复用持久化 boardRect，不会检查归一后的 item bounds 是否超出旧 worldRect。
private static func makeBoardState(
    boardBaseSize: BoardSizeRecord?,
    boardRect: BoardRectRecord?
) -> CanvasBoardState? {
    guard let boardRect else {
        return nil
    }

    let baseSize = boardBaseSize?.cgSize ?? boardRect.size.cgSize
    return CanvasBoardState(
        baseSize: baseSize,
        worldRect: boardRect.cgRect
    )
}
```

### 修改后

- `makeRuntimeState(...)` 在构造 `boardState` 时把已恢复的 `items` 一并传入。
- `makeBoardState(...)` 改为 `makeBoardState(boardBaseSize:boardRect:items:)`，先用旧 `boardRect` 建立基础 board surface，再用每个 item 的 `worldBounds` 做一次 `expandIfNeeded(...)`。
- 这样即便旧文档文字在 runtime 中被归一放大，board surface 仍然能包住它们。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeBoardState(boardBaseSize:boardRect:items:)
// 功能说明: 修改后 runtime boardState 会在载入后继续扩展到包含归一后的 item bounds，避免旧 boardRect 包不住新语义文字。
let runtimeState = BoardRuntimeState(
    boardID: document.boardID,
    title: document.title,
    createdAt: document.createdAt,
    contentUpdatedAt: document.contentUpdatedAt,
    viewStateUpdatedAt: document.viewStateUpdatedAt,
    items: items,
    boardState: makeBoardState(
        boardBaseSize: document.boardBaseSize,
        boardRect: document.boardRect,
        items: items
    ),
    camera: CanvasCamera(
        center: document.cameraCenter.cgPoint,
        zoomScale: CGFloat(document.cameraZoomScale),
        viewportSize: .zero
    ),
    interactionState: CanvasInteractionState(
        selectedItemIDs: document.selectedItemIDs,
        primarySelectedItemID: document.primarySelectedItemID
    ),
    workspaceMode: document.workspaceMode ?? .editing
)

private static func makeBoardState(
    boardBaseSize: BoardSizeRecord?,
    boardRect: BoardRectRecord?,
    items: [CanvasBoardItem]
) -> CanvasBoardState? {
    guard let boardRect else {
        return nil
    }

    let baseSize = boardBaseSize?.cgSize ?? boardRect.size.cgSize
    var boardState = CanvasBoardState(
        baseSize: baseSize,
        worldRect: boardRect.cgRect
    )
    for item in items {
        _ = boardState.expandIfNeeded(toInclude: item.worldBounds)
    }
    return boardState
}
```

## 修改三：补 phase 5 的旧文档迁移回归测试

### 修改前

- `BoardSelectionStateMigrationTests` 已覆盖：
  - 旧 `selectedItemID` 到新多选结构的兼容解码
  - 多选 view state 的 `BoardDocumentMapper` round-trip
- 但它还没有覆盖“旧文档 text size 在加载时必须被忽略并重算”的新需求。
- `makeBoardDocument(...)` helper 也只能构造没有 `boardBaseSize`、没有 `boardRect`、没有 `items` 的最小文档，无法直接搭建本次 phase 5 需要的 legacy text 场景。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift（修改前）
// 函数名: testBoardDocumentDecodesLegacySelectedItemIDIntoSelectionSet() / testBoardDocumentMapperRoundTripsMultiSelectionViewState() / makeBoardDocument(selectedItemIDs:primarySelectedItemID:)
// 功能说明: 修改前 migration 测试只覆盖选区兼容与多选 round-trip，没有锁定旧 text size 归一，也无法直接构造带 boardRect 和 items 的 legacy document。
func testBoardDocumentMapperRoundTripsMultiSelectionViewState() throws {
    let firstItem = CanvasTextItem(
        text: "First",
        center: CGPoint(x: 40, y: 20),
        size: CGSize(width: 120, height: 44),
        zIndex: 0
    )
    let secondItem = CanvasTextItem(
        text: "Second",
        center: CGPoint(x: 180, y: 80),
        size: CGSize(width: 120, height: 44),
        zIndex: 1
    )
    // ...
}

private func makeBoardDocument(
    selectedItemIDs: [UUID],
    primarySelectedItemID: UUID?
) -> BoardDocument {
    BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: UUID(),
        title: "Legacy Selection",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        boardBaseSize: nil,
        boardRect: nil,
        cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 34)),
        cameraZoomScale: 1.5,
        selectedItemIDs: selectedItemIDs,
        primarySelectedItemID: primarySelectedItemID,
        workspaceMode: .editing,
        items: []
    )
}
```

### 修改后

- 新增 `testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad()`：
  - 手工构造带旧 `size` 的 `BoardTextItemRecord`
  - 让 mapper 加载后断言 runtime `textItem.size == intrinsicItemSize(text, style)`
  - 同时断言 runtime `boardState.worldRect.contains(textItem.worldBounds)`
- 同时把 `makeBoardDocument(...)` helper 扩展为可注入 `boardBaseSize`、`boardRect` 和 `items`，便于后续继续补 migration 相关测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad() / makeBoardDocument(selectedItemIDs:primarySelectedItemID:boardBaseSize:boardRect:items:)
// 功能说明: 修改后新增旧文档文字尺寸归一回归测试，并扩展测试 helper 以便直接构造带 boardRect 和 item records 的 legacy 文档。
func testBoardDocumentMapperNormalizesLegacyTextItemSizeOnLoad() throws {
    let legacyStyle = CanvasTextStyle(fontSize: 28)
    let legacyTextRecord = BoardTextItemRecord(
        id: UUID(),
        center: BoardPointRecord(CGPoint(x: 40, y: 30)),
        size: BoardSizeRecord(CGSize(width: 64, height: 24)),
        zIndex: 2,
        text: "Legacy text should expand",
        style: BoardTextStyleRecord(legacyStyle),
        rotationRadians: 0
    )
    let document = makeBoardDocument(
        selectedItemIDs: [legacyTextRecord.id],
        primarySelectedItemID: legacyTextRecord.id,
        boardBaseSize: CGSize(width: 64, height: 64),
        boardRect: CGRect(x: 0, y: 0, width: 64, height: 64),
        items: [.text(legacyTextRecord)]
    )

    let runtimeState = try BoardDocumentMapper.makeRuntimeState(
        from: document
    ) { _ in
        throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
    }
    let textItem = try XCTUnwrap(runtimeState.textItems.first)
    let boardState = try XCTUnwrap(runtimeState.boardState)
    let expectedSize = CanvasTextLayoutMeasurer.intrinsicItemSize(
        for: legacyTextRecord.text,
        style: legacyStyle
    )

    XCTAssertEqual(textItem.id, legacyTextRecord.id)
    XCTAssertEqual(textItem.style, legacyStyle)
    XCTAssertEqual(textItem.center, legacyTextRecord.center.cgPoint)
    XCTAssertEqual(textItem.size, expectedSize)
    XCTAssertNotEqual(textItem.size, legacyTextRecord.size.cgSize)
    XCTAssertTrue(boardState.worldRect.contains(textItem.worldBounds))
}

private func makeBoardDocument(
    selectedItemIDs: [UUID],
    primarySelectedItemID: UUID?,
    boardBaseSize: CGSize? = nil,
    boardRect: CGRect? = nil,
    items: [BoardItemRecord] = []
) -> BoardDocument {
    BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: UUID(),
        title: "Legacy Selection",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        boardBaseSize: boardBaseSize.map(BoardSizeRecord.init),
        boardRect: boardRect.map(BoardRectRecord.init),
        cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 34)),
        cameraZoomScale: 1.5,
        selectedItemIDs: selectedItemIDs,
        primarySelectedItemID: primarySelectedItemID,
        workspaceMode: .editing,
        items: items
    )
}
```

## 验证情况

- `ReadLints` 检查结果：本次改动未引入新的诊断问题。
- `macOS` 定向测试通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests test`
- `iOS` scheme 构建通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS' build`
- 验证过程说明：
  - 首次将 `macOS test` 与 `iOS build` 并发执行时，`xcodebuild` 因同一份 DerivedData 的 `build.db` 被占用而失败一次；随后改为顺序重跑，测试与构建均通过。

## 当前阶段结论

- `phase 5` 已把“旧文档 text item 进入 runtime 时立即切换到内容驱动尺寸语义”的职责，收口到 shared `BoardDocumentMapper` 加载链路。
- 旧持久化 `size` 不再直接驱动 runtime text item；runtime `boardState` 也会同步兜住归一后的文字 bounds，避免只修了 text item 却让 board surface 留下裁剪风险。
- 这次没有改动存储 schema，也没有改动 inline editor；下一阶段可以直接继续做 `phase 6` 的字号入口与命令层接线。
