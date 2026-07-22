# 20260722_094039_BoardList 按需异步统计 Board 大小记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚将 BoardList 菜单里的 board 大小显示，从 catalog 加载阶段同步统计，改为点击 `...` 后异步按需统计的修改。

当前涉及文件：

- `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

## 1. 移除 catalog 阶段的同步大小字段

### 修改前

`BoardDocumentCatalogEntry` 在 catalog 加载时就携带 `storageSizeSummary`，这意味着进入或刷新 BoardList 时会对每个 board 做目录大小统计。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardDocumentCatalogEntry
// 功能说明: 修改前 catalog entry 直接携带大小摘要，容易把目录扫描绑定到列表加载路径。
struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument
    let storageSizeSummary: BoardStorageSizeSummary
}
```

### 修改后

`BoardDocumentCatalogEntry` 不再携带大小摘要，BoardList catalog 加载恢复为只读取文档与预览所需数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardDocumentCatalogEntry
// 功能说明: 修改后移除 storageSizeSummary，避免 BoardList 加载/滚动时批量递归统计目录大小。
struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument
}
```

## 2. 保留显示模型，新增 loading 文案

### 修改前

`BoardStorageSizeSummary` 只有可用和不可用两种展示状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStorageSizeSummary
// 功能说明: 修改前没有 loading 文案，菜单打开时无法先显示占位行。
struct BoardStorageSizeSummary: Hashable, Sendable {
    let byteCount: Int64?

    static let unavailable = BoardStorageSizeSummary(byteCount: nil)
}
```

### 修改后

新增 `loadingDisplayText`，用于菜单立即展示 `Size: Loading...`，不等待后台统计完成。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: BoardStorageSizeSummary
// 功能说明: 修改后提供 loading 文案，支持菜单先显示再异步刷新大小。
struct BoardStorageSizeSummary: Hashable, Sendable {
    let byteCount: Int64?

    static let unavailable = BoardStorageSizeSummary(byteCount: nil)
    static let loadingDisplayText = "Size: Loading..."
}
```

## 3. 新增按需统计 API

### 修改前

`makeBoardDocumentCatalogEntry(at:)` 在创建 catalog entry 时直接调用 `boardDirectoryStorageByteCount(at:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: makeBoardDocumentCatalogEntry(at:)
// 功能说明: 修改前列表 catalog 加载阶段同步统计当前 board 目录大小。
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

### 修改后

`makeBoardDocumentCatalogEntry(at:)` 不再统计大小；新增 `loadBoardStorageSizeSummary(id:userDefaults:)`，只在用户点开某个 board 的 `...` 菜单后由 controller 调用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: makeBoardDocumentCatalogEntry(at:)
// 功能说明: 修改后 catalog entry 创建不再触发目录大小扫描。
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

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadBoardStorageSizeSummary(id:userDefaults:)
// 功能说明: 按需进入安全作用域并统计单个 board 目录大小；由菜单打开后的后台任务调用。
static func loadBoardStorageSizeSummary(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws -> BoardStorageSizeSummary {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        let boardDirectoryURL = self.boardDirectoryURL(
            for: id,
            boardsDirectoryURL: boardsDirectoryURL
        )
        guard FileManager.default.fileExists(atPath: boardDirectoryURL.path),
              try isDirectory(boardDirectoryURL)
        else {
            throw BoardStoreError.invalidBoardDirectory
        }

        return BoardStorageSizeSummary(
            byteCount: try boardDirectoryStorageByteCount(at: boardDirectoryURL)
        )
    }
}
```

## 4. BoardCatalogItem / Loader 不再传递大小

### 修改前

`BoardCatalogItem` 和 `BoardCatalogLoader` 会传递 `storageSizeSummary`，导致 catalog item 与大小统计结果绑定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名: BoardCatalogItem
// 功能说明: 修改前 catalog item 携带大小摘要。
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
// 功能说明: 修改前 loader 从 entry 透传 storageSizeSummary。
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

### 修改后

`BoardCatalogItem` 不再包含 `storageSizeSummary`，`BoardCatalogLoader` 也不再接触该字段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名: BoardCatalogItem
// 功能说明: 修改后 catalog item 不再携带大小摘要，列表加载不做大小相关工作。
struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名: makeCatalogItem(from:)
// 功能说明: 修改后 loader 只构造 boardlist 展示和预览需要的数据。
BoardCatalogItem(
    document: entry.document,
    persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
        forBoardDirectoryURL: entry.boardDirectoryURL
    ),
    assetsDirectoryURL: entry.assetsDirectoryURL,
    previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
)
```

## 5. Action panel 支持局部替换 summaryText

### 修改前

`BoardListActionPanelState` 虽有 `summaryText`，但没有便捷方法保留菜单状态并只更新摘要行。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: BoardListActionPanelState
// 功能说明: 修改前更新 summaryText 需要重新手动构造整个 state。
struct BoardListActionPanelState: Hashable, Sendable {
    let boardID: UUID
    let layoutAnchorPoint: CGPoint
    let summaryText: String?
    let actionStates: [BoardListActionState]
}
```

### 修改后

新增 `replacingSummaryText(_:)`，异步统计完成后可保留 `boardID`、anchor 和 action 列表，只替换大小行文本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: replacingSummaryText(_:)
// 功能说明: 后台统计完成后只替换菜单摘要行，保留原菜单动作和定位信息。
func replacingSummaryText(
    _ summaryText: String?
) -> BoardListActionPanelState {
    BoardListActionPanelState(
        boardID: boardID,
        layoutAnchorPoint: layoutAnchorPoint,
        summaryText: summaryText,
        actionStates: actionStates
    )
}
```

## 6. iOS 菜单改为 loading + 异步刷新

### 修改前

iOS 点开 `...` 时，从 `availableBoards` 直接读取已经存在的 `storageSizeSummary.displayText`，然后创建菜单。这依赖 catalog 阶段已经统计完成。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: boardStorageSizeSummaryText(for:) / presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: 修改前菜单大小文本依赖 catalog item 上的同步统计结果。
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

### 修改后

iOS 点开 `...` 时立即显示 `Size: Loading...`，启动后台任务统计单个 board。结果回主线程后用 requestID 与当前 `actionPanelState.boardID` 校验，避免旧请求覆盖新菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: iOS 菜单立即显示 loading，不等待目录大小统计完成。
let requestID = UUID()
boardStorageSizeSummaryRequestID = requestID
actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint,
    summaryText: BoardStorageSizeSummary.loadingDisplayText
)
loadBoardStorageSizeSummary(
    for: boardID,
    requestID: requestID
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: loadBoardStorageSizeSummary(for:requestID:)
// 功能说明: 在后台队列统计单个 board 大小，失败时降级为 unavailable。
private func loadBoardStorageSizeSummary(
    for boardID: UUID,
    requestID: UUID
) {
    DispatchQueue.global(qos: .utility).async {
        let summary = (try? BoardStore.loadBoardStorageSizeSummary(
            id: boardID
        )) ?? .unavailable

        DispatchQueue.main.async { [weak self] in
            self?.applyBoardStorageSizeSummary(
                summary,
                for: boardID,
                requestID: requestID
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: applyBoardStorageSizeSummary(_:for:requestID:)
// 功能说明: 仅当当前菜单仍是同一个 board 且 requestID 匹配时，刷新大小摘要行。
private func applyBoardStorageSizeSummary(
    _ summary: BoardStorageSizeSummary,
    for boardID: UUID,
    requestID: UUID
) {
    guard
        boardStorageSizeSummaryRequestID == requestID,
        let currentState = actionPanelState,
        currentState.boardID == boardID
    else {
        return
    }

    actionPanelState = currentState.replacingSummaryText(
        summary.displayText
    )
}
```

## 7. macOS 菜单同构改造

### 修改前

macOS 同样从 `availableBoards` 的 `storageSizeSummary` 读取菜单大小文本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: boardStorageSizeSummaryText(for:) / presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: 修改前 macOS 菜单大小文本依赖 catalog item 上的同步统计结果。
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

### 修改后

macOS 与 iOS 一致：先显示 loading，再后台按需统计，完成后校验 requestID 与当前菜单 boardID。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: presentRenameActionPanel(for:anchorRect:from:)
// 功能说明: macOS 菜单立即显示 loading，不阻塞更多操作面板弹出。
let requestID = UUID()
boardStorageSizeSummaryRequestID = requestID
actionPanelState = .renameMenu(
    boardID: boardID,
    anchorPoint: anchorPoint,
    summaryText: BoardStorageSizeSummary.loadingDisplayText
)
loadBoardStorageSizeSummary(
    for: boardID,
    requestID: requestID
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: loadBoardStorageSizeSummary(for:requestID:) / applyBoardStorageSizeSummary(_:for:requestID:)
// 功能说明: macOS 后台统计单个 board 大小，并只刷新仍然打开的同一个菜单。
private func loadBoardStorageSizeSummary(
    for boardID: UUID,
    requestID: UUID
) {
    DispatchQueue.global(qos: .utility).async {
        let summary = (try? BoardStore.loadBoardStorageSizeSummary(
            id: boardID
        )) ?? .unavailable

        DispatchQueue.main.async { [weak self] in
            self?.applyBoardStorageSizeSummary(
                summary,
                for: boardID,
                requestID: requestID
            )
        }
    }
}
```

## 8. 测试更新

### 修改前

测试断言 catalog entry 和 catalog item 都直接暴露 `storageSizeSummary`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardCatalogEntryExposesStorageSizeSummary()
// 功能说明: 修改前测试验证大小摘要绑定在 catalog entry/item 上。
let entry = try XCTUnwrap(
    BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).first
)
let byteCount = try XCTUnwrap(entry.storageSizeSummary.byteCount)

let catalogItem = try XCTUnwrap(
    try BoardCatalogLoader(userDefaults: userDefaults)
        .loadCatalogItem(boardID: boardID)
)
XCTAssertEqual(
    catalogItem.storageSizeSummary.byteCount,
    entry.storageSizeSummary.byteCount
)
```

### 修改后

测试改为验证 catalog item 可以正常加载，但大小只通过 `BoardStore.loadBoardStorageSizeSummary(id:userDefaults:)` 按需获取。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 函数名: testBoardStoreLoadsStorageSizeSummaryOnDemand()
// 功能说明: 修改后验证大小摘要通过按需 API 获取，catalog item 不再携带大小字段。
let catalogItem = try XCTUnwrap(
    try BoardCatalogLoader(userDefaults: userDefaults)
        .loadCatalogItem(boardID: boardID)
)
let summary = try BoardStore.loadBoardStorageSizeSummary(
    id: boardID,
    userDefaults: userDefaults
)
let byteCount = try XCTUnwrap(summary.byteCount)

XCTAssertGreaterThan(byteCount, 0)
XCTAssertEqual(catalogItem.boardID, boardID)
XCTAssertTrue(summary.displayText.hasPrefix("Size: "))
```

## 验证情况

已执行并通过：

- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

当前 `git status --short` 在创建本记录前显示本次代码改动为：

- `M MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
- `M MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

本次仅创建记录文件，没有提交 commit。
