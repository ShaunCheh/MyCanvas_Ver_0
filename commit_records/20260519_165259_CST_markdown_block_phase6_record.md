# 20260519_165259_CST_markdown_block_phase6_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 6。
  - 本阶段没有继续扩 markdown block 新功能，而是对存储兼容、渲染语义、markdown accessory 判定和回归测试做收口。
  - 本次实际改动包括：抽出共享 `CanvasMarkdownSelectionAccessoryResolver`、让 iOS / macOS controller 改为委托共享 resolver、在 `BoardDocument` 明确记录 markdown schema 的前向兼容风险、补齐 `BoardDocument` / `BoardDocumentMapper` / `CanvasMarkdownLayer` / accessory resolver 的回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift`
- 参考现状：
  - 针对本次阶段 6 相关文件，`git status --short` 显示 `5` 个已跟踪修改文件和 `2` 个未跟踪新增文件。
  - 针对本次阶段 6 的已跟踪文件，`git diff --stat` 显示：`5 files changed, 261 insertions(+), 64 deletions(-)`。
  - 上述 `git diff --stat` 不包含本次新增的 `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift` 与 `MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift`。
- 本记录不包含：
  - `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short -- MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
?? MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift
?? MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift
```

```bash
# 命令: git diff --stat -- MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
 MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift  |   3 +
 .../Platform/iOS/iOSViewController.swift           |  46 +++----
 .../Platform/macOS/macOSViewController.swift       |  46 +++----
 .../BoardSelectionStateMigrationTests.swift        |  94 ++++++++++++++
 MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift | 136 +++++++++++++++++++++
 5 files changed, 261 insertions(+), 64 deletions(-)
```

## 当前 changes 摘要

- `CanvasMarkdownSelectionAccessoryResolver` 被抽成共享层，阶段 4/5 分别在 iOS 和 macOS controller 内联维护的 markdown accessory 判定逻辑被收敛到一处。
- `iOSViewController` 与 `macOSViewController` 现在只负责注入平台态环境参数和 anchor rect，不再各自维护一套 markdown accessory 展示条件与 descriptor 拼装。
- `BoardDocument.currentFormatVersion` 旁边明确补充了 markdown schema 的前向兼容风险说明。
- `BoardSelectionStateMigrationTests` 新增 `BoardDocument` encode/decode markdown case 与 legacy board 无 markdown 继续可读的回归测试。
- `CanvasMarkdownLayerTests` 新增“改宽触发重排”和“仅改高不改字号”的渲染语义测试。
- 新增 `CanvasMarkdownSelectionAccessoryResolverTests`，验证 markdown accessory 只对单选 markdown 生效；同时通过 `Retainer` 避免 `CanvasEditorSession` / `CanvasScene` 在测试释放期触发崩溃。

## 修改一：抽出共享 markdown accessory resolver，并收敛双端 controller 判定

### 1.1 修改前

- iOS 和 macOS 的 `resolvedMarkdownSelectionAccessoryState()` 都在各自 controller 里内联维护同一组 guard 条件。
- `Edit Markdown`、`Smaller Markdown`、`Larger Markdown` 的 descriptor 也在两个 controller 内重复拼装。
- 共享层里没有专门的 resolver 文件。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: resolvedMarkdownSelectionAccessoryState()
// 功能说明: 修改前 iOS controller 直接承担 markdown accessory 的展示条件判断与 descriptor 组装；macOS 端也维护了同形逻辑。
private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    guard
        workspaceMode == .editing,
        isTransitionInteractionFrozen == false,
        contextMenuState == nil,
        presentedViewController == nil,
        presentationInlineEditState == nil,
        let itemID = editorSession.singleSelectedItemID,
        scene.markdownItem(withID: itemID) != nil,
        let anchorRect = markdownSelectionAccessoryAnchorRect(for: itemID)
    else {
        return nil
    }

    let editDescriptor = CanvasCommandDescriptor(
        id: .beginMarkdownEdit,
        title: "Edit Markdown",
        systemImageName: "pencil",
        isEnabled: editorSession.canBeginMarkdownEdit(withID: itemID),
        isActive: false
    )
    let decreaseDescriptor = commandDescriptor(
        for: .decreaseMarkdownContentSize
    )
    let increaseDescriptor = commandDescriptor(
        for: .increaseMarkdownContentSize
    )
    return SelectionAccessoryState.markdown(
        itemID: itemID,
        anchorRect: anchorRect,
        editDescriptor: editDescriptor,
        decreaseDescriptor: decreaseDescriptor,
        increaseDescriptor: increaseDescriptor
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift（修改前）
// 函数名: 新文件（修改前不存在）
// 功能说明: 修改前没有共享 resolver，双端只能各自散落维护 markdown accessory 判定逻辑。
//
// 无此文件
```

### 1.2 修改后

- 新增共享 `CanvasMarkdownSelectionAccessoryResolver`，把 workspace mode、transition freeze、context menu、overlay editor、inline edit、选中 item 类型、anchor rect sanitize 统一收敛。
- iOS / macOS controller 只保留平台差异化环境输入，具体是否展示 accessory 以及 action descriptor 如何构造，都委托共享 resolver。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/CanvasMarkdownSelectionAccessoryResolver.swift
// 函数名: resolveState(session:environment:anchorRect:)
// 功能说明: 新增共享 resolver，统一校验 markdown accessory 的展示前提，并在通过后返回标准化 SelectionAccessoryState。
struct CanvasMarkdownSelectionAccessoryResolver {
    struct Environment {
        let workspaceMode: CanvasWorkspaceMode
        let isTransitionInteractionFrozen: Bool
        let hasContextMenu: Bool
        let hasPresentedOverlayEditor: Bool
        let hasInlineEditPresentation: Bool
    }

    private let commandCatalog = CanvasCommandCatalog()

    func resolveState(
        session: CanvasEditorSession,
        environment: Environment,
        anchorRect: CGRect?
    ) -> SelectionAccessoryState? {
        guard
            environment.workspaceMode == .editing,
            environment.isTransitionInteractionFrozen == false,
            environment.hasContextMenu == false,
            environment.hasPresentedOverlayEditor == false,
            environment.hasInlineEditPresentation == false,
            let item = session.selectedMarkdownItem,
            let anchorRect,
            let sanitizedAnchorRect = CanvasChromeLayoutGeometry.sanitizedRect(
                anchorRect
            )
        else {
            return nil
        }

        let editDescriptor = commandCatalog.descriptor(
            for: .beginMarkdownEdit,
            session: session
        )
        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseMarkdownContentSize,
            session: session
        )
        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseMarkdownContentSize,
            session: session
        )
        return SelectionAccessoryState.markdown(
            itemID: item.id,
            anchorRect: sanitizedAnchorRect,
            editDescriptor: editDescriptor,
            decreaseDescriptor: decreaseDescriptor,
            increaseDescriptor: increaseDescriptor
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resolvedMarkdownSelectionAccessoryState()
// 功能说明: 修改后 iOS controller 只负责注入平台态环境和 anchor rect，再委托共享 resolver 生成 markdown accessory 状态。
private let markdownSelectionAccessoryResolver =
    CanvasMarkdownSelectionAccessoryResolver()

private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    markdownSelectionAccessoryResolver.resolveState(
        session: editorSession,
        environment: CanvasMarkdownSelectionAccessoryResolver.Environment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: isTransitionInteractionFrozen,
            hasContextMenu: contextMenuState != nil,
            hasPresentedOverlayEditor: presentedViewController != nil,
            hasInlineEditPresentation: presentationInlineEditState != nil
        ),
        anchorRect: editorSession.singleSelectedItemID.flatMap {
            markdownSelectionAccessoryAnchorRect(for: $0)
        }
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resolvedMarkdownSelectionAccessoryState()
// 功能说明: 修改后 macOS controller 与 iOS 共用同一个 resolver，只保留 presentedViewControllers 判定的 macOS 差异输入。
private let markdownSelectionAccessoryResolver =
    CanvasMarkdownSelectionAccessoryResolver()

private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    markdownSelectionAccessoryResolver.resolveState(
        session: editorSession,
        environment: CanvasMarkdownSelectionAccessoryResolver.Environment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: isTransitionInteractionFrozen,
            hasContextMenu: contextMenuState != nil,
            hasPresentedOverlayEditor: !(presentedViewControllers?.isEmpty ?? true),
            hasInlineEditPresentation: presentationInlineEditState != nil
        ),
        anchorRect: editorSession.singleSelectedItemID.flatMap {
            markdownSelectionAccessoryAnchorRect(for: $0)
        }
    )
}
```

## 修改二：在 `BoardDocument` 明确记录 markdown schema 的前向兼容风险

### 2.1 修改前

- `BoardDocument.currentFormatVersion` 已经是 `9`，但注释里没有把 `type: "markdown"` 的前向不兼容风险说清楚。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift（修改前）
// 函数名: BoardDocument
// 功能说明: 修改前只说明 board schema 和 image asset internals 解耦，没有指出 markdown schema 对旧客户端的前向兼容限制。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    static let currentFormatVersion = 9
    static let defaultTitle = "Untitled Board"
}
```

### 2.2 修改后

- 在 `currentFormatVersion = 9` 旁边显式标注：一旦保存了 `type: "markdown"` 记录，旧客户端无法前向解码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument
// 功能说明: 修改后在 schema 版本定义旁边明确记录 markdown record 的前向兼容风险，避免后续误判旧客户端可读性。
struct BoardDocument: Codable {
    // Board schema now evolves independently from image asset internals.
    // Format version 9 adds `type: "markdown"` records. Older clients that do
    // not understand markdown items cannot forward-decode documents once such
    // records have been saved.
    static let currentFormatVersion = 9
    static let defaultTitle = "Untitled Board"
}
```

## 修改三：补齐 `BoardDocument` / `BoardDocumentMapper` 的 markdown 存储兼容回归测试

### 3.1 修改前

- `BoardSelectionStateMigrationTests` 已经覆盖了 markdown item 的 mapper round-trip。
- 但还没有直接验证 `BoardDocument` 的 `markdown` case encode/decode，也没有验证 legacy board（无 markdown）在当前 mapper 下继续可读。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift（修改前）
// 函数名: testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize() / testBoardHandDrawingItemRecordDecodesLegacyAssetIdentityFromItemID()
// 功能说明: 修改前测试直接从 markdown mapper round-trip 跳到 hand drawing legacy decode，中间缺失 BoardDocument 级别的 markdown schema 测试。
func testBoardDocumentMapperRoundTripsMarkdownItemPreservingExplicitContainerSize() throws {
    let document = BoardDocumentMapper.makeDocument(from: runtimeState)
    XCTAssertEqual(document.formatVersion, BoardDocument.currentFormatVersion)
    let markdownRecord = try XCTUnwrap(document.markdownItemRecords.first)
    // ... 校验 markdown mapper round-trip ...
}

func testBoardHandDrawingItemRecordDecodesLegacyAssetIdentityFromItemID() throws {
    let legacyPayload: [String: Any] = [
        "id": itemID.uuidString,
        "center": ["x": 48, "y": 72]
    ]
    // ... hand drawing legacy decode ...
}
```

### 3.2 修改后

- 新增 `testBoardDocumentCodableRoundTripsMarkdownItemRecords()`，直接锁定 `type: "markdown"` 和 `markdown` payload 在 `BoardDocument` 层的 encode/decode 契约。
- 新增 `testBoardDocumentMapperLoadsLegacyBoardWithoutMarkdownItems()`，验证 format version 8 且无 markdown 的旧 board 仍可被当前 runtime 正常读取。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentCodableRoundTripsMarkdownItemRecords() / testBoardDocumentMapperLoadsLegacyBoardWithoutMarkdownItems()
// 功能说明: 修改后新增 markdown schema codable 回归与 legacy board 无 markdown 可读性回归，补齐阶段 6 的数据/存储收口。
func testBoardDocumentCodableRoundTripsMarkdownItemRecords() throws {
    let markdownRecord = BoardMarkdownItemRecord(
        id: UUID(),
        center: BoardPointRecord(CGPoint(x: 160, y: 96)),
        size: BoardSizeRecord(CGSize(width: 280, height: 180)),
        zIndex: 3,
        markdownSource: "## Title\n\nBody",
        style: BoardTextStyleRecord(CanvasTextStyle(fontSize: 22)),
        rotationRadians: Double.pi / 10
    )
    let document = makeBoardDocument(
        selectedItemIDs: [markdownRecord.id],
        primarySelectedItemID: markdownRecord.id,
        items: [.markdown(markdownRecord)]
    )
    let encodedDocument = try JSONEncoder().encode(document)
    let payload = try XCTUnwrap(
        JSONSerialization.jsonObject(with: encodedDocument) as? [String: Any]
    )
    let itemPayload = try XCTUnwrap((payload["items"] as? [[String: Any]])?.first)

    XCTAssertEqual(itemPayload["type"] as? String, "markdown")
    XCTAssertNotNil(itemPayload["markdown"])

    let decodedDocument = try JSONDecoder().decode(
        BoardDocument.self,
        from: encodedDocument
    )
    let decodedRecord = try XCTUnwrap(decodedDocument.markdownItemRecords.first)
    XCTAssertEqual(decodedRecord, markdownRecord)
}

func testBoardDocumentMapperLoadsLegacyBoardWithoutMarkdownItems() throws {
    let legacyTextRecord = BoardTextItemRecord(
        id: UUID(),
        center: BoardPointRecord(CGPoint(x: 72, y: 40)),
        size: BoardSizeRecord(CGSize(width: 160, height: 48)),
        zIndex: 1,
        text: "Legacy board",
        style: BoardTextStyleRecord(CanvasTextStyle(fontSize: 20)),
        rotationRadians: 0
    )
    let legacyDocument = BoardDocument(
        formatVersion: 8,
        boardID: UUID(),
        title: "Legacy Without Markdown",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        contentUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        viewStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        boardBaseSize: nil,
        boardRect: nil,
        cameraCenter: BoardPointRecord(CGPoint(x: 12, y: 18)),
        cameraZoomScale: 1,
        selectedItemIDs: [legacyTextRecord.id],
        primarySelectedItemID: legacyTextRecord.id,
        workspaceMode: .editing,
        items: [.text(legacyTextRecord)]
    )
    let runtimeState = try BoardDocumentMapper.makeRuntimeState(
        from: legacyDocument,
        imageLoader: { _ in
            throw BoardSelectionStateMigrationTestError.unexpectedImageDecode
        }
    )

    XCTAssertEqual(runtimeState.textItems.map(\.id), [legacyTextRecord.id])
    XCTAssertTrue(runtimeState.markdownItems.isEmpty)
}
```

## 修改四：补齐 markdown layer 的宽高变化语义测试

### 4.1 修改前

- `CanvasMarkdownLayerTests` 只验证了 zoom scale 下 attributed markdown 会生成不同字号层级。
- 对“改宽触发重排”和“仅改高不改字号”这两个阶段 6 明确要求的语义没有自动化覆盖。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前）
// 函数名: testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts() / makeMarkdownLayerRenderItem(...)
// 功能说明: 修改前只校验 markdown layer 能生成带缩放字号的 attributed text，没有覆盖宽度重排和高度变化语义。
final class CanvasMarkdownLayerTests: XCTestCase {
    func testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts() throws {
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: "## Title\n\nBody with `code`",
            style: CanvasTextStyle(fontSize: 18),
            zoomScale: 1.5
        )
        // ... 只验证 title/body 字号层级 ...
    }
}

private func makeMarkdownLayerRenderItem(
    itemID: CanvasItemID,
    size: CGSize,
    payload: CanvasMarkdownRenderPayload
) -> CanvasRenderItem {
    // ... helper ...
}
```

### 4.2 修改后

- 新增 `testUpdateReflowsAttributedMarkdownWhenLayoutWidthChanges()`：当 block 变窄时，排版高度必须变大，并且和 `CanvasMarkdownLayoutMeasurer` 的测量结果一致。
- 新增 `testUpdateKeepsMarkdownFontSizesWhenOnlyHeightChanges()`：当仅拉高容器时，title/body 的字体 point size 不应发生变化。
- 同时补了 `markdownLayerTestFonts(...)` 和 `measureMarkdownAttributedTextHeight(...)` 两个测试 helper。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: testUpdateReflowsAttributedMarkdownWhenLayoutWidthChanges() / testUpdateKeepsMarkdownFontSizesWhenOnlyHeightChanges()
// 功能说明: 修改后补齐阶段 6 要求的 markdown layer 宽高语义回归，锁住“改宽重排、改高不改字号”的行为。
func testUpdateReflowsAttributedMarkdownWhenLayoutWidthChanges() throws {
    let payload = CanvasMarkdownRenderPayload(
        markdownSource: """
        ## Title

        A long markdown paragraph that should wrap onto additional lines when the block becomes narrower.
        """,
        style: CanvasTextStyle(fontSize: 18),
        zoomScale: 1
    )
    let wideRenderItem = makeMarkdownLayerRenderItem(
        itemID: itemID,
        size: CGSize(width: 260, height: 120),
        payload: payload
    )
    layer.update(with: wideRenderItem, markdownPayload: payload, contentsScale: 2)
    let wideAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
    let wideRenderedHeight = measureMarkdownAttributedTextHeight(
        wideAttributedText,
        width: wideRenderItem.screenBoundsSize.width
    )

    let narrowRenderItem = makeMarkdownLayerRenderItem(
        itemID: itemID,
        size: CGSize(width: 140, height: 120),
        payload: payload
    )
    layer.update(with: narrowRenderItem, markdownPayload: payload, contentsScale: 2)
    let narrowAttributedText = try XCTUnwrap(layer.string as? NSAttributedString)
    let narrowRenderedHeight = measureMarkdownAttributedTextHeight(
        narrowAttributedText,
        width: narrowRenderItem.screenBoundsSize.width
    )
    let expectedNarrowHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: payload.markdownSource,
        style: payload.style,
        maxLayoutWidth: narrowRenderItem.screenBoundsSize.width,
        scale: payload.zoomScale
    )

    XCTAssertGreaterThan(narrowRenderedHeight, wideRenderedHeight)
    XCTAssertEqual(narrowRenderedHeight, expectedNarrowHeight, accuracy: 1)
}

func testUpdateKeepsMarkdownFontSizesWhenOnlyHeightChanges() throws {
    let compactRenderItem = makeMarkdownLayerRenderItem(
        itemID: itemID,
        size: CGSize(width: 220, height: 80),
        payload: payload
    )
    layer.update(with: compactRenderItem, markdownPayload: payload, contentsScale: 2)
    let compactFonts = try markdownLayerTestFonts(
        in: try XCTUnwrap(layer.string as? NSAttributedString)
    )

    let tallerRenderItem = makeMarkdownLayerRenderItem(
        itemID: itemID,
        size: CGSize(width: 220, height: 180),
        payload: payload
    )
    layer.update(with: tallerRenderItem, markdownPayload: payload, contentsScale: 2)
    let tallerFonts = try markdownLayerTestFonts(
        in: try XCTUnwrap(layer.string as? NSAttributedString)
    )

    XCTAssertEqual(tallerFonts.title.pointSize, compactFonts.title.pointSize)
    XCTAssertEqual(tallerFonts.body.pointSize, compactFonts.body.pointSize)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名: markdownLayerTestFonts(in:) / measureMarkdownAttributedTextHeight(_:width:)
// 功能说明: 修改后新增测试 helper，用于抽取 title/body font 和测量 attributed markdown 的实际绘制高度。
private func markdownLayerTestFonts(
    in attributedText: NSAttributedString
) throws -> (title: MarkdownLayerTestFont, body: MarkdownLayerTestFont) {
    let rendered = attributedText.string as NSString
    let titleFont = try XCTUnwrap(
        attributedText.attribute(.font, at: 0, effectiveRange: nil)
            as? MarkdownLayerTestFont
    )
    let bodyRange = rendered.range(of: "Body")
    let bodyFont = try XCTUnwrap(
        attributedText.attribute(.font, at: bodyRange.location, effectiveRange: nil)
            as? MarkdownLayerTestFont
    )
    return (title: titleFont, body: bodyFont)
}

private func measureMarkdownAttributedTextHeight(
    _ attributedText: NSAttributedString,
    width: CGFloat
) -> CGFloat {
    attributedText.boundingRect(
        with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    ).height
}
```

## 修改五：新增 accessory resolver 回归测试，并修复测试释放期崩溃

### 5.1 修改前

- 没有独立的 `CanvasMarkdownSelectionAccessoryResolverTests.swift`。
- 阶段 6 计划里要求的“markdown accessory 只对 markdown 出现，text / handDrawing 不误显示”没有自动化测试锁住。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift（修改前）
// 函数名: 新文件（修改前不存在）
// 功能说明: 修改前 accessory resolver 没有独立测试文件，markdown / text / handDrawing 的展示边界没有单独回归覆盖。
//
// 无此文件
```

### 5.2 修改后

- 新增 `CanvasMarkdownSelectionAccessoryResolverTests`，覆盖：
  - 单选 markdown 返回 markdown accessory。
  - 单选 text 返回 `nil`。
  - 单选 handDrawing 返回 `nil`。
  - inline edit presentation 激活时返回 `nil`。
- 在初版新测试运行时，`CanvasEditorSession` / `CanvasScene` 在 XCTest 释放期与后台 `BoardPreviewProvider.renderQueue` 发生生命周期冲突，出现 `abort()`；最终通过 `MarkdownSelectionAccessoryResolverTestRetainer.sessions.append(session)` 显式 retain session 收口。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift
// 函数名: testResolveStateReturnsMarkdownAccessoryForSingleMarkdownSelection() / testResolveStateReturnsNilForSingleTextSelection() / testResolveStateReturnsNilForSingleHandDrawingSelection() / testResolveStateReturnsNilWhenInlineEditPresentationIsActive()
// 功能说明: 修改后新增 accessory resolver 定向测试，锁住 markdown accessory 的正向展示条件和反向屏蔽条件。
@MainActor
final class CanvasMarkdownSelectionAccessoryResolverTests: XCTestCase {
    private let resolver = CanvasMarkdownSelectionAccessoryResolver()

    func testResolveStateReturnsMarkdownAccessoryForSingleMarkdownSelection() throws {
        let session = makeMarkdownSelectionAccessoryResolverTestSession(
            items: [.markdown(item)],
            selectedItemID: item.id
        )
        let state = try XCTUnwrap(
            resolver.resolveState(
                session: session,
                environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
                anchorRect: CGRect(x: 24, y: 40, width: 180, height: 96)
            )
        )

        XCTAssertEqual(
            state.actionStates.map(\.commandID),
            [.beginMarkdownEdit, .decreaseMarkdownContentSize, .increaseMarkdownContentSize]
        )
    }

    func testResolveStateReturnsNilForSingleTextSelection() {
        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
            anchorRect: CGRect(x: 24, y: 40, width: 160, height: 48)
        )
        XCTAssertNil(state)
    }

    func testResolveStateReturnsNilForSingleHandDrawingSelection() throws {
        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(),
            anchorRect: CGRect(x: 12, y: 24, width: 120, height: 120)
        )
        XCTAssertNil(state)
    }

    func testResolveStateReturnsNilWhenInlineEditPresentationIsActive() {
        let state = resolver.resolveState(
            session: session,
            environment: makeMarkdownSelectionAccessoryResolverEnvironment(
                hasInlineEditPresentation: true
            ),
            anchorRect: CGRect(x: 24, y: 40, width: 180, height: 96)
        )
        XCTAssertNil(state)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests.swift
// 函数名: makeMarkdownSelectionAccessoryResolverTestSession(...) / MarkdownSelectionAccessoryResolverTestRetainer
// 功能说明: 修改后新增 Retainer，避免 CanvasEditorSession / CanvasScene 在 XCTest 释放阶段提前析构，触发测试运行时 abort。
private func makeMarkdownSelectionAccessoryResolverTestSession(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID?
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "MyCanvas.Tests.MarkdownSelectionAccessoryResolver",
        logPrefix: "[Tests][MarkdownSelectionAccessoryResolver]"
    )
    for item in items {
        session.scene.append(item)
    }
    if let selectedItemID {
        session.interactionState = CanvasInteractionState(
            selectedItemIDs: [selectedItemID],
            primarySelectedItemID: selectedItemID
        )
    }
    MarkdownSelectionAccessoryResolverTestRetainer.sessions.append(session)
    return session
}

private enum MarkdownSelectionAccessoryResolverTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}
```

## 验证记录

- `ReadLints` 检查本次新增 / 修改文件，无新增 linter 问题。
- 定向测试通过：`BoardSelectionStateMigrationTests`、`CanvasMarkdownLayerTests`、`CanvasMarkdownSelectionAccessoryResolverTests`。
- iOS simulator 通用构建通过，说明共享 resolver 接线没有破坏 iOS 端编译。

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:"MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownSelectionAccessoryResolverTests"
** TEST SUCCEEDED **
```

```bash
# 命令: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'
** BUILD SUCCEEDED **
```
