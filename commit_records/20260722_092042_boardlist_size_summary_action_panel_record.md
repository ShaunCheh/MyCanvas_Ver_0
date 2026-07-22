# 20260722_092042_BoardList 菜单显示 Board 存储大小记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚在 BoardList 每个 board 的 `...` 菜单里、`Rename` 上方新增当前 board 总大小概要的实现。

当前涉及文件：

- `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

## 1. BoardStore catalog entry 增加存储大小摘要

### 修改前

`BoardDocumentCatalogEntry` 只携带 board 目录、文档、assets 目录和文档内容。BoardList catalog 阶段没有当前 board 的总文件大小信息。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardDocumentCatalogEntry
// 功能说明: 修改前 catalog entry 不包含 board 目录总大小信息。
struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument

    var summary: BoardSummary {
        document.summary
    }
}
```

### 修改后

新增 `BoardStorageSizeSummary`，支持 `byteCount` 为空时显示 `Size unavailable`，正常情况下用 `ByteCountFormatter` 格式化为 `Size: ...`。`BoardDocumentCatalogEntry` 新增 `storageSizeSummary`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardDocumentCatalogEntry / BoardStorageSizeSummary
// 功能说明: 修改后 catalog entry 携带可展示的 board 存储大小摘要。
struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument
    let storageSizeSummary: BoardStorageSizeSummary

    var summary: BoardSummary {
        document.summary
    }
}

struct BoardStorageSizeSummary: Hashable, Sendable {
    let byteCount: Int64?

    static let unavailable = BoardStorageSizeSummary(byteCount: nil)

    var displayText: String {
        guard let byteCount else {
            return "Size unavailable"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "Size: \(formatter.string(fromByteCount: byteCount))"
    }
}
```

## 2. 统计 board 目录总文件字节数

### 修改前

`makeBoardDocumentCatalogEntry(at:)` 读取 `board.json` 后直接返回 entry，没有扫描 board 目录下的普通文件大小。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: makeBoardDocumentCatalogEntry(at:)
// 功能说明: 修改前只加载 board 文档和 assets 路径，不计算目录体积。
let document = try readBoardDocument(at: boardDocumentURL)
return BoardDocumentCatalogEntry(
    boardDirectoryURL: boardDirectoryURL,
    documentURL: boardDocumentURL,
    assetsDirectoryURL: boardDirectoryURL.appendingPathComponent(
        assetsDirectoryName,
        isDirectory: true
    ),
    document: document
)
```

### 修改后

在 `SelectedFolderAccess.withBoardsDirectoryURL` 作用域内创建 entry 时，递归统计 board 目录下普通文件大小。统计失败不阻断 catalog 加载，而是让 `byteCount` 为 `nil`，UI 显示 `Size unavailable`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: makeBoardDocumentCatalogEntry(at:)
// 功能说明: 修改后在 catalog 阶段计算 board 目录总大小，并把失败降级为 unavailable。
let document = try readBoardDocument(at: boardDocumentURL)
let storageSizeSummary = BoardStorageSizeSummary(
    byteCount: try? boardDirectoryStorageByteCount(at: boardDirectoryURL)
)
return BoardDocumentCatalogEntry(
    boardDirectoryURL: boardDirectoryURL,
    documentURL: boardDocumentURL,
    assetsDirectoryURL: boardDirectoryURL.appendingPathComponent(
        assetsDirectoryName,
        isDirectory: true
    ),
    document: document,
    storageSizeSummary: storageSizeSummary
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: boardDirectoryStorageByteCount(at:fileManager:)
// 功能说明: 递归统计 board 目录下普通文件的 fileSize，覆盖 board.json、assets 和 thumbnail 等文件。
private static func boardDirectoryStorageByteCount(
    at boardDirectoryURL: URL,
    fileManager: FileManager = .default
) throws -> Int64 {
    let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .fileSizeKey
    ]
    guard let enumerator = fileManager.enumerator(
        at: boardDirectoryURL,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [],
        errorHandler: nil
    ) else {
        return 0
    }

    var byteCount: Int64 = 0
    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
        guard resourceValues.isRegularFile == true else {
            continue
        }

        byteCount += Int64(max(resourceValues.fileSize ?? 0, 0))
    }

    return byteCount
}
```

## 3. Catalog item 传递大小摘要

### 修改前

`BoardCatalogItem` 不携带大小摘要，`BoardCatalogLoader` 也不会从 `BoardDocumentCatalogEntry` 传递该信息。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名: BoardCatalogItem
// 功能说明: 修改前 BoardList 层拿不到当前 board 的存储大小摘要。
struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed
}
```

### 修改后

`BoardCatalogItem` 新增 `storageSizeSummary`，`BoardCatalogLoader.makeCatalogItem(from:)` 从 entry 透传该字段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名: BoardCatalogItem
// 功能说明: 修改后 BoardList catalog item 携带可展示的存储大小摘要。
struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
    let storageSizeSummary: BoardStorageSizeSummary
    let previewSeed: BoardPreviewSeed
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名: makeCatalogItem(from:)
// 功能说明: 从 BoardStore entry 透传 storageSizeSummary，避免点开菜单时再做 IO。
BoardCatalogItem(
    document: entry.document,
    persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
        forBoardDirectoryURL: entry.boardDirectoryURL
    ),
    assetsDirectoryURL: entry.assetsDirectoryURL,
    storageSizeSummary: entry.storageSizeSummary,
    previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
)
```

## 4. Action panel state 增加只读摘要文本

### 修改前

`BoardListActionPanelState` 只包含 action 列表，`renameMenu` 固定返回 `Rename` 和 `Delete` 两个按钮，没有非按钮信息行。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: BoardListActionPanelState.renameMenu(...)
// 功能说明: 修改前 action panel 只表达可点击动作，不表达只读摘要。
struct BoardListActionPanelState: Hashable, Sendable {
    let boardID: UUID
    let layoutAnchorPoint: CGPoint
    let actionStates: [BoardListActionState]
}

static func renameMenu(
    boardID: UUID,
    anchorPoint: CGPoint,
    isRenameEnabled: Bool = true,
    isDeleteEnabled: Bool = true
) -> BoardListActionPanelState {
    BoardListActionPanelState(
        boardID: boardID,
        layoutAnchorPoint: anchorPoint,
        actionStates: [
            .rename(isEnabled: isRenameEnabled),
            .delete(isEnabled: isDeleteEnabled)
        ]
    )
}
```

### 修改后

`BoardListActionPanelState` 新增 `summaryText`，`renameMenu` 可接收这行只读文本，仍保留默认 `nil` 兼容现有调用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: BoardListActionPanelState.renameMenu(...)
// 功能说明: 修改后 action panel 可在 Rename 上方展示只读 summaryText。
struct BoardListActionPanelState: Hashable, Sendable {
    let boardID: UUID
    let layoutAnchorPoint: CGPoint
    let summaryText: String?
    let actionStates: [BoardListActionState]
}

static func renameMenu(
    boardID: UUID,
    anchorPoint: CGPoint,
    summaryText: String? = nil,
    isRenameEnabled: Bool = true,
    isDeleteEnabled: Bool = true
) -> BoardListActionPanelState {
    BoardListActionPanelState(
        boardID: boardID,
        layoutAnchorPoint: anchorPoint,
        summaryText: summaryText,
        actionStates: [
            .rename(isEnabled: isRenameEnabled),
            .delete(isEnabled: isDeleteEnabled)
        ]
    )
}
```

## 5. iOS/macOS Action panel 渲染摘要行

### 修改前

`BoardListActionPanelHostView.rebuildActionButtons(for:)` 清空 stack 后只添加 action button，因此菜单第一行就是 `Rename`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: rebuildActionButtons(for:)
// 功能说明: 修改前只渲染按钮，无法在 Rename 上方显示只读大小信息。
actionIDs = []
actionStackView.arrangedSubviews.forEach { arrangedSubview in
    actionStackView.removeArrangedSubview(arrangedSubview)
    arrangedSubview.removeFromSuperview()
}

for actionState in state.actionStates {
    let button = makeActionButton(for: actionState)
    button.tag = actionIDs.count
    actionIDs.append(actionState.id)
    actionStackView.addArrangedSubview(button)
}
```

### 修改后

iOS 侧在按钮前添加 `UILabel`，macOS 侧在按钮前添加 `NSTextField(labelWithString:)`。这行不会加入 `actionIDs`，因此不参与点击分发，只展示总大小概要。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: rebuildActionButtons(for:) / makeSummaryLabel(text:) [iOS]
// 功能说明: iOS 菜单在 action buttons 前渲染一行不可点击的大小摘要。
if let summaryText = state.summaryText,
   summaryText.isEmpty == false {
    actionStackView.addArrangedSubview(
        makeSummaryLabel(text: summaryText)
    )
}

private func makeSummaryLabel(text: String) -> UILabel {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .secondaryLabel
    label.text = text
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    return label
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: rebuildActionButtons(for:) / makeSummaryLabel(text:) [macOS]
// 功能说明: macOS 菜单在 action buttons 前渲染一行不可点击的大小摘要。
if let summaryText = state.summaryText,
   summaryText.isEmpty == false {
    actionStackView.addArrangedSubview(
        makeSummaryLabel(text: summaryText)
    )
}

private func makeSummaryLabel(text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
    return label
}
```

## 6. iOS/macOS BoardList 传入当前 board 大小

### 修改前

iOS 与 macOS 展示 `...` 菜单时，只把 `boardID` 和 anchor 传给 `renameMenu`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: 修改前 iOS 菜单没有传入 board 大小摘要。
actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: 修改前 macOS 菜单没有传入 board 大小摘要。
actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint
)
```

### 修改后

iOS 和 macOS 都根据当前 `availableBoards` 查找对应 board 的 `storageSizeSummary.displayText`，找不到时使用 `BoardStorageSizeSummary.unavailable.displayText`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: boardStorageSizeSummaryText(for:) / presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: iOS 从当前 catalog cache 中取出 board 大小摘要，并传给 action panel。
private func boardStorageSizeSummaryText(for boardID: UUID) -> String {
    guard
        let boardIndex = availableBoardIndexByID[boardID],
        availableBoards.indices.contains(boardIndex)
    else {
        return BoardStorageSizeSummary.unavailable.displayText
    }

    return availableBoards[boardIndex].storageSizeSummary.displayText
}

actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint,
    summaryText: boardStorageSizeSummaryText(for: boardID)
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: boardStorageSizeSummaryText(for:) / presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: macOS 从当前 catalog cache 中取出 board 大小摘要，并传给 action panel。
private func boardStorageSizeSummaryText(for boardID: UUID) -> String {
    availableBoards.first { $0.boardID == boardID }?
        .storageSizeSummary
        .displayText
        ?? BoardStorageSizeSummary.unavailable.displayText
}

actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint,
    summaryText: boardStorageSizeSummaryText(for: boardID)
)
```

## 7. 测试补充

### 修改前

现有 `BoardVideoStorageTests` 覆盖视频 poster/source asset 保存、缩略图刷新等，但没有验证 catalog entry 与 catalog item 是否暴露 board 总大小。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: 无
// 功能说明: 修改前没有 storageSizeSummary 的回归测试。
// 修改前此处无 testBoardCatalogEntryExposesStorageSizeSummary()。
```

### 修改后

新增测试：保存带视频 source/poster 的 board 后，`BoardStore.listBoardDocumentEntries` 返回的 entry 应有非零 `byteCount`，展示文本以 `Size: ` 开头；`BoardCatalogLoader.loadCatalogItem` 应透传同一 byteCount。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardCatalogEntryExposesStorageSizeSummary()
// 功能说明: 验证 BoardStore catalog entry 与 BoardCatalogItem 都能暴露非零 board 总大小摘要。
func testBoardCatalogEntryExposesStorageSizeSummary() throws {
    try withTemporaryBoardWorkspace { _, userDefaults in
        let boardID = UUID()
        let sourceVideoFilename = "source-video.mov"
        let posterImage = try makeSolidColorImage(red: 0.2, green: 0.4, blue: 1)
        let item = makeVideoItem(
            id: UUID(),
            posterAsset: .transientStaticImage(
                cgImage: posterImage,
                assetID: UUID()
            ),
            sourceVideoFilename: sourceVideoFilename,
            posterTimeSeconds: 4.5
        )
        let runtimeState = makeRuntimeState(
            boardID: boardID,
            now: Date(timeIntervalSince1970: 1_710_000_300),
            item: item
        )

        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        try writeDummyVideoAsset(
            to: assetsDirectoryURL.appendingPathComponent(sourceVideoFilename)
        )
        try BoardStore.saveBoard(runtimeState, userDefaults: userDefaults)

        let entry = try XCTUnwrap(
            BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
        )
        let byteCount = try XCTUnwrap(entry.storageSizeSummary.byteCount)

        XCTAssertGreaterThan(byteCount, 0)
        XCTAssertTrue(entry.storageSizeSummary.displayText.hasPrefix("Size: "))

        let catalogItem = try XCTUnwrap(
            try BoardCatalogLoader(userDefaults: userDefaults)
                .loadCatalogItem(boardID: boardID)
        )
        XCTAssertEqual(
            catalogItem.storageSizeSummary.byteCount,
            entry.storageSizeSummary.byteCount
        )
    }
}
```

## 验证情况

已执行并通过：

- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

当前 `git status --short` 在创建本记录前显示本次代码改动为：

- `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
- `M MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

本次仅创建记录文件，没有提交 commit。
