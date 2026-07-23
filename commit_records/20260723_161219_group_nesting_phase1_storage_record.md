# 20260723_161219_group_nesting_phase1_storage_record

## 记录范围

本记录如实对应刚刚完成的 `group_nesting_78437533.plan.md` 阶段 1：为 group 嵌套增加存储层基础字段，让 group 数据能够持久化直属子 group id，同时保持旧文档兼容。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`

当前 `git status` 显示上述三个文件有修改。本记录基于当前 `git diff` 与工作区 changes 整理，不直接粘贴原始 diff。

## 修改前

### Runtime group 只能保存直属 item

修改前，`CanvasItemGroup` 只有 `itemIDs` 和可选 `frame`，不能表达“一个 group 的直属子 group”。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：修改前 CanvasItemGroup 只能表达 group 到 item 的关系。
// 函数名：CanvasItemGroup.init(id:title:description:itemIDs:frame:)
struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]
    var frame: CGRect?

    init(
        id: CanvasItemGroupID = UUID(),
        title: String,
        description: String = "",
        itemIDs: [CanvasItemID],
        frame: CGRect? = nil
    ) {
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.frame = frame?.standardized
    }
}
```

### 文档 group record 没有 child group 字段

修改前，`BoardGroupRecord` 也只持久化 `itemIDs` 和 `frame`，旧 schema version 是 `13`。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：修改前 BoardGroupRecord 只持久化直属 item 和 group frame。
// 函数名：BoardGroupRecord.init(id:title:description:itemIDs:frame:)
struct BoardGroupRecord: Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var itemIDs: [UUID]
    var frame: BoardRectRecord?
}
```

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：修改前 format version 13 只代表 group frame 持久化。
// 函数名：BoardDocument.currentFormatVersion
static let currentFormatVersion = 13
```

### mapper 只映射 itemIDs

修改前，runtime group 与 document group record 互转时只传递 `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 功能注释：修改前从 BoardGroupRecord 还原 CanvasItemGroup 时不包含 child group。
// 函数名：BoardDocumentMapper.makeGroup(from:)
CanvasItemGroup(
    id: groupRecord.id,
    title: groupRecord.title,
    description: groupRecord.description,
    itemIDs: groupRecord.itemIDs,
    frame: groupRecord.frame?.cgRect
)
```

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 功能注释：修改前从 CanvasItemGroup 生成 BoardGroupRecord 时不包含 child group。
// 函数名：BoardDocumentMapper.makeGroupRecord(from:)
BoardGroupRecord(
    id: group.id,
    title: group.title,
    description: group.description,
    itemIDs: group.itemIDs,
    frame: group.frame.map(BoardRectRecord.init)
)
```

## 修改后

### CanvasItemGroup 新增 childGroupIDs

修改后，`CanvasItemGroup` 新增 `childGroupIDs`，表示直属子 group。初始化时会对 child group id 去重；self/环/单父等不变量仍按计划留到阶段 2 在 session 层集中处理。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：让 runtime group 能表达直属子 group id，并对 child id 去重。
// 函数名：CanvasItemGroup.init(id:title:description:itemIDs:childGroupIDs:frame:)
struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]
    var childGroupIDs: [CanvasItemGroupID]
    var frame: CGRect?

    init(
        id: CanvasItemGroupID = UUID(),
        title: String,
        description: String = "",
        itemIDs: [CanvasItemID],
        childGroupIDs: [CanvasItemGroupID] = [],
        frame: CGRect? = nil
    ) {
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.childGroupIDs = Self.normalizedChildGroupIDs(childGroupIDs)
        self.frame = frame?.standardized
    }
}
```

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：按顺序保留首次出现的 child group id，过滤重复项。
// 函数名：CanvasItemGroup.normalizedChildGroupIDs(_:)
private static func normalizedChildGroupIDs(
    _ childGroupIDs: [CanvasItemGroupID]
) -> [CanvasItemGroupID] {
    var seenGroupIDs = Set<CanvasItemGroupID>()
    return childGroupIDs.filter { groupID in
        seenGroupIDs.insert(groupID).inserted
    }
}
```

### BoardDocument schema 升级到 14

修改后，文档格式版本升级到 `14`，语义是 group record 可以持久化直属 `childGroupIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：format version 14 表示 group 支持持久化直属 child group ids。
// 函数名：BoardDocument.currentFormatVersion
static let currentFormatVersion = 14
```

### BoardGroupRecord 新增 childGroupIDs 并兼容旧文档

修改后，`BoardGroupRecord` 新增 `childGroupIDs`，初始化和 decode 时都会去重。自定义 `init(from:)` 使用 `decodeIfPresent`，旧文档缺少该字段时会默认解码为空数组。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：持久化直属子 group ids，并允许旧文档缺省为空。
// 函数名：BoardGroupRecord.init(id:title:description:itemIDs:childGroupIDs:frame:)
struct BoardGroupRecord: Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var itemIDs: [UUID]
    var childGroupIDs: [UUID]
    var frame: BoardRectRecord?

    init(
        id: UUID,
        title: String,
        description: String,
        itemIDs: [UUID],
        childGroupIDs: [UUID] = [],
        frame: BoardRectRecord? = nil
    ) {
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.childGroupIDs = Self.normalizedChildGroupIDs(childGroupIDs)
        self.frame = frame
    }
}
```

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 功能注释：旧文档没有 childGroupIDs 时默认读取为空数组，避免迁移断档。
// 函数名：BoardGroupRecord.init(from:)
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    description = try container.decode(String.self, forKey: .description)
    itemIDs = Self.normalizedItemIDs(
        try container.decode([UUID].self, forKey: .itemIDs)
    )
    childGroupIDs = Self.normalizedChildGroupIDs(
        try container.decodeIfPresent([UUID].self, forKey: .childGroupIDs) ?? []
    )
    frame = try container.decodeIfPresent(BoardRectRecord.self, forKey: .frame)
}
```

### mapper 双向传递 childGroupIDs

修改后，`BoardDocumentMapper` 在 runtime/document 双向转换中都传递 `childGroupIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 功能注释：从 document group record 还原 runtime group 时保留 child group ids。
// 函数名：BoardDocumentMapper.makeGroup(from:)
CanvasItemGroup(
    id: groupRecord.id,
    title: groupRecord.title,
    description: groupRecord.description,
    itemIDs: groupRecord.itemIDs,
    childGroupIDs: groupRecord.childGroupIDs,
    frame: groupRecord.frame?.cgRect
)
```

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 功能注释：从 runtime group 生成 document group record 时写入 child group ids。
// 函数名：BoardDocumentMapper.makeGroupRecord(from:)
BoardGroupRecord(
    id: group.id,
    title: group.title,
    description: group.description,
    itemIDs: group.itemIDs,
    childGroupIDs: group.childGroupIDs,
    frame: group.frame.map(BoardRectRecord.init)
)
```

### 存储测试覆盖 roundtrip 和旧字段缺省

修改后，`BoardVideoStorageTests` 的 group roundtrip 测试覆盖 parent group 的 `childGroupIDs` 去重和 mapper 往返；新增 legacy decode 测试，确保旧 group record 没有 `childGroupIDs` 字段时可以解码为空数组。

```swift
// MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 功能注释：验证 CanvasItemGroup.childGroupIDs 可以写入 BoardGroupRecord，并在 runtime roundtrip 后保留。
// 函数名：BoardVideoStorageTests.testBoardDocumentMapperRoundTripsCanvasItemGroups()
runtimeState.groups = [
    CanvasItemGroup(
        id: groupID,
        title: "Question Evidence",
        description: "Image answers the markdown question.",
        itemIDs: [itemID],
        childGroupIDs: [childGroupID, childGroupID],
        frame: groupFrame
    ),
    CanvasItemGroup(
        id: childGroupID,
        title: "Detail Evidence",
        description: "Nested supporting group.",
        itemIDs: [],
        frame: childGroupFrame
    )
]
```

```swift
// MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
// 功能注释：验证旧 group JSON 缺少 childGroupIDs 字段时，decode 后默认为空数组。
// 函数名：BoardVideoStorageTests.testBoardGroupRecordDecodesLegacyDocumentWithoutChildGroupIDs()
let groupRecord = try JSONDecoder().decode(BoardGroupRecord.self, from: data)

XCTAssertEqual(groupRecord.id, groupID)
XCTAssertEqual(groupRecord.itemIDs, [itemID])
XCTAssertEqual(groupRecord.childGroupIDs, [])
XCTAssertEqual(
    groupRecord.frame?.cgRect,
    CGRect(x: 10, y: 20, width: 120, height: 80)
)
```

## 行为变化

- 新文档会用 format version `14` 保存。
- group runtime model 和 document record 都能保存直属 child group ids。
- `childGroupIDs` 会按首次出现顺序去重。
- 旧文档没有 `childGroupIDs` 字段时仍能读取，默认值为空数组。
- 本阶段不改变自动归属、拖拽、resize、hit test 或 group list UI 行为；这些属于后续阶段。

## 验证

已执行 lints 检查：

- `ReadLints`：`BoardDocument.swift` 无 linter errors。
- `ReadLints`：`BoardDocumentMapper.swift` 无 linter errors。
- `ReadLints`：`BoardVideoStorageTests.swift` 无 linter errors。

已执行 iOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS 在 group nesting 阶段1存储模型改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

结果：build 成功。

已执行 macOS build。第一次与测试/iOS build 并发执行时，因 DerivedData `build.db` 被锁失败；随后单独重跑通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS 在 group nesting 阶段1存储模型改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

结果：build 成功。

已执行 group 存储相关测试。第一次与 build 并发执行时，因 DerivedData `build.db` 被锁失败；随后单独重跑通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 group childGroupIDs mapper roundtrip 和旧 group record 解码兼容。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests
```

结果：测试通过。
