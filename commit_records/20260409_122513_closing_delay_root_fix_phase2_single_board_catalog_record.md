# 20260409_122513_closing_delay_root_fix_phase2_single_board_catalog_record

## 记录范围

- 记录内容：`closing_delay_root_fix` 计划的 `Phase 2` 实施记录。
- 记录目标：在不改现有调用方语义的前提下，为 closing target-ready 链补齐“单板 catalog 读取”能力。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift` 与修改后的源码内容整理。
- 对应计划文件：`.cursor/plans/closing_delay_root_fix_97b39f82.plan.md`
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- 本记录不包含：`Phase 1` 的 closing 入口收口实现。
- 本记录不包含：`Phase 3` 的 `availableBoards` targeted upsert。
- 本记录不包含：`Phase 4` 的 target-ready 快路径接线。
- 本记录不包含：git commit。

## 问题背景

- 在 `Phase 1` 之后，iOS closing 链已经只剩 `prepareTransitionTargetGeometry(...)` 这一条前置同步入口。
- 但此时 `BoardList` 仍然只能调用 `refreshBookmarkStatus() -> loadCatalog()` 走全量目录扫描。
- 要想在后续 `Phase 3/4` 里把 closing target-ready 改成“只更新 returning board”，必须先在存储层和 loader 层提供稳定的单板读取能力。
- `Phase 2` 的设计目标不是直接改 `BoardList` 调用方，而是先把底层 API 补齐，并保证：
  - 全量路径仍然可用
  - 单板路径不复制一份新的映射逻辑
  - 后续可以直接从 `BoardCatalogItem` 粒度接线

## 修改一：`BoardStore` 新增单板 catalog entry 读取能力，并把 entry 构造逻辑统一收口

### 修改前

- `listBoardDocumentEntries(...)` 自己在循环里完成：
  - 目录校验
  - `board.json` 是否存在校验
  - `BoardDocument` 读取
  - `BoardDocumentCatalogEntry` 构造
- 但 `BoardStore` 没有“只读取某一个 board”的 catalog 级接口。
- 这意味着后续如果要做单板路径，只能重新复制一份 entry 构造逻辑，存在未来两条路径漂移的风险。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/符号名: listBoardDocumentEntries(userDefaults:)
// 功能说明: 修改前全量 catalog 枚举直接在循环内拼装 BoardDocumentCatalogEntry，BoardStore 不提供单板 entry 读取接口。
static func listBoardDocumentEntries(
    userDefaults: UserDefaults = .standard
) throws -> [BoardDocumentCatalogEntry] {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        let candidateURLs = try CoordinatedFileIO.contentsOfDirectory(
            at: boardsDirectoryURL
        )

        var entries: [BoardDocumentCatalogEntry] = []
        for candidateURL in candidateURLs {
            guard try isDirectory(candidateURL) else {
                continue
            }

            let boardDocumentURL = candidateURL.appendingPathComponent(boardDocumentFilename)
            guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
                continue
            }

            let document = try readBoardDocument(at: boardDocumentURL)
            entries.append(
                BoardDocumentCatalogEntry(
                    boardDirectoryURL: candidateURL,
                    documentURL: boardDocumentURL,
                    assetsDirectoryURL: candidateURL.appendingPathComponent(
                        assetsDirectoryName,
                        isDirectory: true
                    ),
                    document: document
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.document.updatedAt == rhs.document.updatedAt {
                return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
            }

            return lhs.document.updatedAt > rhs.document.updatedAt
        }
    }
}
```

### 修改后

- 新增 `loadBoardDocumentEntry(id:userDefaults:) -> BoardDocumentCatalogEntry?`，允许存储层直接按 `boardID` 读取单条 catalog entry。
- 把 `BoardDocumentCatalogEntry` 的构造过程抽到 `makeBoardDocumentCatalogEntry(at:)`，统一服务于：
  - `listBoardDocumentEntries(...)`
  - `loadBoardDocumentEntry(id:userDefaults:)`
- 这样全量路径和单板路径现在共享同一份 entry 构造语义，后续不会因为复制逻辑而产生行为漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/符号名: listBoardDocumentEntries(userDefaults:) / loadBoardDocumentEntry(id:userDefaults:) / makeBoardDocumentCatalogEntry(at:)
// 功能说明: 修改后 BoardStore 同时支持全量枚举与单板读取，并把 entry 构造逻辑统一收口到 makeBoardDocumentCatalogEntry(at:)。
static func listBoardDocumentEntries(
    userDefaults: UserDefaults = .standard
) throws -> [BoardDocumentCatalogEntry] {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        let candidateURLs = try CoordinatedFileIO.contentsOfDirectory(
            at: boardsDirectoryURL
        )

        var entries: [BoardDocumentCatalogEntry] = []
        for candidateURL in candidateURLs {
            if let entry = try makeBoardDocumentCatalogEntry(
                at: candidateURL
            ) {
                entries.append(entry)
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.document.updatedAt == rhs.document.updatedAt {
                return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
            }

            return lhs.document.updatedAt > rhs.document.updatedAt
        }
    }
}

static func loadBoardDocumentEntry(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws -> BoardDocumentCatalogEntry? {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        return try makeBoardDocumentCatalogEntry(
            at: boardDirectoryURL(
                for: id,
                boardsDirectoryURL: boardsDirectoryURL
            )
        )
    }
}

private static func makeBoardDocumentCatalogEntry(
    at boardDirectoryURL: URL
) throws -> BoardDocumentCatalogEntry? {
    guard FileManager.default.fileExists(atPath: boardDirectoryURL.path) else {
        return nil
    }

    guard try isDirectory(boardDirectoryURL) else {
        return nil
    }

    let boardDocumentURL = boardDirectoryURL.appendingPathComponent(
        boardDocumentFilename
    )
    guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
        return nil
    }

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
}
```

## 修改二：`BoardCatalogLoader` 新增单板 `BoardCatalogItem` 读取能力，并统一 item 映射逻辑

### 修改前

- `BoardCatalogLoader` 只有 `loadCatalog()`。
- `loadCatalog()` 里直接把 `BoardDocumentCatalogEntry` 映射成 `BoardCatalogItem`。
- 这意味着如果后面要补 `loadCatalogItem(boardID:)`，要么复制一份映射逻辑，要么重构一次。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/符号名: loadCatalog()
// 功能说明: 修改前 loader 只支持全量 catalog 加载，并直接在 loadCatalog() 内完成 entry 到 item 的映射。
func loadCatalog() throws -> [BoardCatalogItem] {
    try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
        BoardCatalogItem(
            document: entry.document,
            persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: entry.boardDirectoryURL
            ),
            assetsDirectoryURL: entry.assetsDirectoryURL,
            previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
        )
    }
}
```

### 修改后

- 新增 `loadCatalogItem(boardID:) -> BoardCatalogItem?`，直接消费 `BoardStore.loadBoardDocumentEntry(id:userDefaults:)`。
- 把 entry 到 item 的映射提取成私有 `makeCatalogItem(from:)`。
- 这样：
  - `loadCatalog()` 继续服务全量路径
  - `loadCatalogItem(boardID:)` 服务后续 closing target-only 路径
  - 两条路径共享同一份 `BoardCatalogItem` 组装逻辑

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/符号名: loadCatalog() / loadCatalogItem(boardID:) / makeCatalogItem(from:)
// 功能说明: 修改后 loader 同时支持全量与单板 item 加载，并统一复用 makeCatalogItem(from:) 进行 BoardCatalogItem 映射。
func loadCatalog() throws -> [BoardCatalogItem] {
    try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map {
        makeCatalogItem(from: $0)
    }
}

func loadCatalogItem(
    boardID: UUID
) throws -> BoardCatalogItem? {
    guard
        let entry = try BoardStore.loadBoardDocumentEntry(
            id: boardID,
            userDefaults: userDefaults
        )
    else {
        return nil
    }

    return makeCatalogItem(from: entry)
}

private func makeCatalogItem(
    from entry: BoardDocumentCatalogEntry
) -> BoardCatalogItem {
    BoardCatalogItem(
        document: entry.document,
        persistedThumbnailURL: BoardPersistedThumbnailStore.thumbnailURL(
            forBoardDirectoryURL: entry.boardDirectoryURL
        ),
        assetsDirectoryURL: entry.assetsDirectoryURL,
        previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
    )
}
```

## 接口语义说明

- `BoardStore.loadBoardDocumentEntry(id:userDefaults:)`：
  - board 目录不存在时返回 `nil`
  - 路径不是目录时返回 `nil`
  - 缺少 `board.json` 时返回 `nil`
  - 文件存在但读取 / 解码失败时继续 `throw`
- `BoardCatalogLoader.loadCatalogItem(boardID:)`：
  - 语义上是“按 boardID 读取单条 `BoardCatalogItem`”
  - 底层 entry 不存在时返回 `nil`
  - entry 存在但构造失败时继续 `throw`

## 对后续阶段的影响

- `Phase 3` 可以直接在 `iOSBoardListViewController` 内调用 `loadCatalogItem(boardID:)`，把单板 item 接进 `availableBoards` 的 targeted upsert。
- `Phase 4` 可以基于这条单板读取路径，把 `prepareTransitionTargetGeometry(...)` 从全量 `refreshBookmarkStatus()` 改成真正的 closing target-only 准备链。
- 由于 entry 构造和 item 映射都已经统一抽取，后面不需要再重构一轮存储层 / loader 层。

## 验证

- 已检查当前工作树中本次修改的 `git diff`，只涉及以上两个文件。
- 已用 IDE 诊断检查：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- 结果：`No linter errors found`
- 已执行语法校验：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift" "MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift"`
- 结果：通过
- 本次未修改 `BoardList` 调用方，因此尚未产生用户可见行为变化。
