# 20260323_175025_boardlist_rename_phase1_storage_record

## 记录范围

- 记录内容：
  1. 为 `BoardStore` 新增 BoardList Phase 1 所需的轻量重命名持久化路径 `renameBoard(...)`。
  2. 在同一存储层内补充标题规范化 helper，统一处理首尾空白和空标题回退。
  3. 同步更新 BoardList rename 实施计划中的 Phase 1 状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md`
- 本记录不包含：
  - BoardList 的三点按钮 UI
  - 自定义 action panel
  - Grid/List 内联编辑接线
  - git commit / push

## 修改一：在 `BoardStore` 中新增轻量 rename 持久化路径

### 修改前

- `BoardStore` 只有整板 `saveBoard(...)` 和删除 `deleteBoard(...)` 路径。
- 如果后续 BoardList 要做 rename，修改前并没有一个“只更新 `board.json` 元数据、不重写 assets / thumbnail”的专用入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(...) / deleteBoard(...)
// 功能说明: 修改前存储层只有整板保存与删除接口；saveBoard 会更新 updatedAt、重写 document、同步图片资源并尝试持久化 thumbnail，但没有 metadata-only 的 rename API。
static func saveBoard(
    _ runtimeState: BoardRuntimeState,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)

        let boardDirectoryURL = self.boardDirectoryURL(
            for: runtimeState.boardID,
            boardsDirectoryURL: boardsDirectoryURL
        )
        let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
            assetsDirectoryName,
            isDirectory: true
        )
        try CoordinatedFileIO.ensureDirectory(at: boardDirectoryURL)
        try CoordinatedFileIO.ensureDirectory(at: assetsDirectoryURL)

        var persistedState = runtimeState
        persistedState.updatedAt = Date()
        let document = BoardDocumentMapper.makeDocument(from: persistedState)

        for item in persistedState.imageItems {
            let assetURL = assetsDirectoryURL.appendingPathComponent(
                "\(item.id.uuidString).png"
            )
            let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
            try CoordinatedFileIO.writeData(pngData, to: assetURL)
        }

        try removeOrphanedAssets(
            keeping: Set(document.imageItemRecords.map(\.assetFilename)),
            in: assetsDirectoryURL
        )

        let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
        let encodedDocument = try makeDocumentData(for: document)
        try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
        persistBoardThumbnailIfPossible(
            from: persistedState,
            boardDirectoryURL: boardDirectoryURL
        )
    }
}

static func deleteBoard(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        let boardDirectoryURL = self.boardDirectoryURL(
            for: id,
            boardsDirectoryURL: boardsDirectoryURL
        )
        try CoordinatedFileIO.removeItemIfExists(at: boardDirectoryURL)
    }
}
```

### 修改后

- 新增 `renameBoard(id:title:userDefaults:)`。
- 该路径只会：
  - 进入 boards 目录；
  - 读取目标 board 的 `board.json`；
  - 规范化标题；
  - 更新 `document.title` 与 `document.updatedAt`；
  - 写回 document。
- 这意味着后续 BoardList 接 UI 时，rename 不会误触整板资源重写，也能通过 `updatedAt` 更新自然触发“改名后置顶”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: renameBoard(id:title:userDefaults:)
// 功能说明: 修改后新增 metadata-only 的 board rename 路径；它只更新 board.json 中的 title 和 updatedAt，不复用整板 saveBoard() 的资产/thumbnail 写入链路。
static func renameBoard(
    id: UUID,
    title: String,
    userDefaults: UserDefaults = .standard
) throws {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)

        let boardDirectoryURL = self.boardDirectoryURL(
            for: id,
            boardsDirectoryURL: boardsDirectoryURL
        )
        let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
        var document = try readBoardDocument(at: boardDocumentURL)
        let normalizedTitle = normalizedBoardTitle(title)
        document.title = normalizedTitle
        document.updatedAt = Date()

        let encodedDocument = try makeDocumentData(for: document)
        try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
        print(
            "[BoardStore] " +
            "action=renameBoard " +
            "boardID=\(id.uuidString) " +
            "title=\"\(normalizedTitle)\""
        )
    }
}
```

## 修改二：补充统一的标题规范化 helper

### 修改前

- `BoardStore` 内部没有单独的 board title 规范化 helper。
- rename 场景下如果直接把外部输入写回 document，就会把首尾空白和空字符串规则分散到调用方处理。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: isDirectory(...)
// 功能说明: 修改前 BoardStore 在私有 helper 区域只包含目录判断等基础函数，没有 board title 归一化逻辑。
private static func isDirectory(
    _ url: URL
) throws -> Bool {
    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
    return resourceValues.isDirectory == true
}
```

### 修改后

- 新增 `normalizedBoardTitle(_:)`。
- 规则很简单：
  - `trim` 掉 `whitespacesAndNewlines`
  - 如果结果为空，则回退到 `BoardDocument.defaultTitle`
- 这样后续不管是 BoardList inline rename、还是未来其他入口改标题，都能复用同一套兜底规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: normalizedBoardTitle(_:)
// 功能说明: 修改后 BoardStore 内部统一负责 title 输入规整；避免调用方各自处理空白字符与空标题回退。
private static func normalizedBoardTitle(_ title: String) -> String {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedTitle.isEmpty == false else {
        return BoardDocument.defaultTitle
    }

    return normalizedTitle
}
```

## 修改三：同步计划文件中的 Phase 1 完成状态

### 修改前

- BoardList rename 计划里，`storage-rename-path` 仍是 `pending`。
- 这会让实施计划与实际代码状态不一致。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改前，Phase 1 的存储层 rename 任务还未标记完成。
todos:
  - id: storage-rename-path
    content: 新增 BoardStore.renameBoard，并让 rename 同时更新 title 与 updatedAt
    status: pending
```

### 修改后

- 将 `storage-rename-path` 标记为 `completed`。
- 这只是计划同步，不影响产品运行逻辑，但能保持阶段进度与当前代码一致。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改后，Phase 1 的存储层 rename 任务已与实际实现同步为 completed。
todos:
  - id: storage-rename-path
    content: 新增 BoardStore.renameBoard，并让 rename 同时更新 title 与 updatedAt
    status: completed
```

## 关联说明：为什么本次无需修改排序逻辑

- `BoardStore.listBoardDocumentEntries(...)` 原本就按 `updatedAt` 倒序返回 catalog。
- 因此本次只要在 rename 时更新 `document.updatedAt`，后续 BoardList 重新加载时就会自然把改名后的 board 排到最前。
- 这一点属于“依赖现有行为”，不是本次新增代码，所以此处只做说明，不额外改动实现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: listBoardDocumentEntries(userDefaults:)
// 功能说明: 现有 catalog 排序本就以 updatedAt 为主；rename 更新 updatedAt 后，BoardList 刷新即可得到“改名后置顶”的结果。
return entries.sorted { lhs, rhs in
    if lhs.document.updatedAt == rhs.document.updatedAt {
        return lhs.document.boardID.uuidString < rhs.document.boardID.uuidString
    }

    return lhs.document.updatedAt > rhs.document.updatedAt
}
```

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift` 无新增 linter 问题。
- 类型检查：
  - 已执行 `xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift`
  - 结果通过。

## 当前阶段结论

- Phase 1 已完成：BoardList 后续只要接入 UI 层的 rename 入口，就可以直接调用 `BoardStore.renameBoard(...)`。
- 当前尚未开始 Phase 2，因此项目里还没有三点按钮、自定义 action panel 和标题内联编辑。
