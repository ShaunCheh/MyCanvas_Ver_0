# 20260414_170925 图板多选阶段0改动记录

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff` 和当前文件内容；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”方式归纳。

## 当前 Changes 快照

```bash
# 来源: git status --short
# 说明: 这是生成本记录时工作区中可见的全部 changes
 M .gitignore
 M MyCanvas_Ver_0.xcodeproj/project.pbxproj
 M MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
 M MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
?? MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
```

其中，阶段 0 主体代码改动集中在：

- `MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- `MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift`
- `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`

当前工作区还同时存在 `.gitignore` 与 `MyCanvas_Ver_0.xcodeproj/project.pbxproj` 的附带变化，后文也一并登记。

## 1. 选择状态从“单选ID”升级为“选择集 + 主选中项”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 结构/函数: CanvasInteractionState / init(selectedItemID:)
// 说明: 旧实现只有一个选中项字段，整个画布交互层天然是单选模型
struct CanvasInteractionState {
    // 旧实现: 只能保存一个选中对象
    var selectedItemID: CanvasItemID?

    init(selectedItemID: CanvasItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 结构/函数: CanvasInteractionState / init(selectedItemIDs:primarySelectedItemID:)
// 说明: 新实现把选择状态升级为多选集合，并保留 selectedItemID 兼容别名
struct CanvasInteractionState: Equatable {
    // 新实现: 保存完整选择集
    private var storedSelectedItemIDs: [CanvasItemID]
    // 新实现: 保存主选中项，供后续单对象编辑链路平滑过渡
    private var storedPrimarySelectedItemID: CanvasItemID?

    var selectedItemIDs: [CanvasItemID] { ... }
    var primarySelectedItemID: CanvasItemID? { ... }

    // 兼容层: 旧代码仍可读写 selectedItemID，但底层会被映射到选择集
    var selectedItemID: CanvasItemID? { ... }

    var hasSelection: Bool { ... }
    var selectionCount: Int { ... }
    var singleSelectedItemID: CanvasItemID? { ... }

    init(
        selectedItemIDs: [CanvasItemID] = [],
        primarySelectedItemID: CanvasItemID? = nil
    ) { ... }
}

// 归一化函数:
// 1. 去重
// 2. 保证 primary 一定属于 selectedItemIDs
// 3. 当 selectedItemIDs 为空时，primary 强制归零
func normalizeCanvasSelectionState<ItemID: Hashable>(...) -> CanvasNormalizedSelectionState<ItemID> { ... }
```

### 本次效果

- 选择状态不再依赖单个 `selectedItemID`。
- 为后续阶段的 `primary selection`、组选框、批量命令打下统一数据契约。
- 当前仍保留 `selectedItemID` 兼容入口，避免一次性打爆后续调用点。

## 2. Session 层补充多选派生接口，但暂不改命令语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 结构/函数: CanvasEditorSession / canBeginCropMode / canClearSelection / selectedBoardItem
// 说明: 旧实现直接依赖 interactionState.selectedItemID，属于单选思维
var canBeginCropMode: Bool {
    guard inlineEditState == nil else { return false }
    guard let selectedItemID = interactionState.selectedItemID else { return false }
    return scene.item(withID: selectedItemID) != nil
}

var canClearSelection: Bool {
    interactionState.selectedItemID != nil
}

var selectedBoardItem: CanvasBoardItem? {
    guard let selectedItemID = interactionState.selectedItemID else { return nil }
    return scene.boardItem(withID: selectedItemID)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 结构/函数: CanvasEditorSession / hasSelection / selectionCount / selectedBoardItems / singleSelectedItemID
// 说明: 阶段0只增加派生只读接口，并把单对象判断收敛到 singleSelectedItemID
var hasSelection: Bool {
    interactionState.hasSelection
}

var selectionCount: Int {
    interactionState.selectionCount
}

var selectedItemIDs: [CanvasItemID] {
    interactionState.selectedItemIDs
}

var primarySelectedItemID: CanvasItemID? {
    interactionState.primarySelectedItemID
}

var singleSelectedItemID: CanvasItemID? {
    interactionState.singleSelectedItemID
}

var selectedBoardItems: [CanvasBoardItem] {
    // 新实现: 用选择集派生出实际 board items
    selectedItemIDs.compactMap { itemID in
        scene.boardItem(withID: itemID)
    }
}

var canBeginCropMode: Bool {
    guard inlineEditState == nil else { return false }
    // 新实现: 只有“恰好单选”时才允许进入 crop
    guard let selectedItemID = singleSelectedItemID else { return false }
    return scene.item(withID: selectedItemID) != nil
}
```

### 本次效果

- 阶段 0 先把 Session 暴露面铺好，后续阶段可以逐步把旧逻辑迁移到 `selectedItemIDs` / `primarySelectedItemID`。
- 当前仍未改写批量选择命令，这属于阶段 1 的工作。

## 3. 历史快照不再只比较单个 selectedItemID

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数: static func == (lhs:rhs:)
// 说明: 旧实现只比较 interactionState.selectedItemID，多选变化会被吞掉
extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
        lhs.interactionState.selectedItemID == rhs.interactionState.selectedItemID
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数: static func == (lhs:rhs:)
// 说明: 新实现直接比较完整 interactionState，后续选择集变化可以进入历史
extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
        lhs.interactionState == rhs.interactionState
    }
}
```

### 本次效果

- 历史快照与新选择契约对齐。
- 后续多选的 undo/redo 不会因为仍在比较单个 `selectedItemID` 而丢失状态变化。

## 4. 文档存储层升级到多选 view-state，并兼容旧文档

### 4.1 BoardDocument 主体字段

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 结构/函数: BoardDocument / 成员字段 / init(...)
// 说明: 旧版文档只保存一个 selectedItemID
struct BoardDocument: Codable {
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 结构/函数: BoardDocument / 成员字段 / init(...)
// 说明: 新版文档保存选择集和主选中项，并保留 selectedItemID 兼容别名
struct BoardDocument: Codable {
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double

    // 新实现: 真实存储层
    private var storedSelectedItemIDs: [UUID]
    private var storedPrimarySelectedItemID: UUID?

    // 新实现: 对外暴露完整 view-state
    var selectedItemIDs: [UUID] { ... }
    var primarySelectedItemID: UUID? { ... }

    // 兼容层: 老调用点仍可读到一个 selectedItemID
    var selectedItemID: UUID? { ... }

    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]
}
```

### 4.2 BoardDocument 解码兼容

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数: init(from decoder:)
// 说明: 旧解码逻辑只读取 selectedItemID
selectedItemID = try container.decodeIfPresent(
    UUID.self,
    forKey: .selectedItemID
)
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数: init(from decoder:)
// 说明: 新解码逻辑优先读取 selectedItemIDs / primarySelectedItemID，同时兼容旧字段
let legacySelectedItemID = try container.decodeIfPresent(
    UUID.self,
    forKey: .selectedItemID
)

let decodedSelectedItemIDs = try container.decodeIfPresent(
    [UUID].self,
    forKey: .selectedItemIDs
) ?? legacySelectedItemID.map { [$0] } ?? []

let decodedPrimarySelectedItemID = try container.decodeIfPresent(
    UUID.self,
    forKey: .primarySelectedItemID
) ?? legacySelectedItemID

// 最后统一走归一化，保证存储态合法
applyNormalizedSelection(
    selectedItemIDs: decodedSelectedItemIDs,
    primarySelectedItemID: decodedPrimarySelectedItemID
)
```

### 4.3 BoardDocumentViewState 同步升级

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 结构/函数: BoardDocumentViewState
// 说明: 旧 view-state 仍然是单选字段
struct BoardDocumentViewState: Equatable {
    var boardBaseSize: BoardSizeRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var workspaceMode: CanvasWorkspaceMode?
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 结构/函数: BoardDocumentViewState / init(selectedItemIDs:primarySelectedItemID:)
// 说明: view-state 与运行时选择契约保持一致
struct BoardDocumentViewState: Equatable {
    var boardBaseSize: BoardSizeRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double

    private var storedSelectedItemIDs: [UUID]
    private var storedPrimarySelectedItemID: UUID?

    var selectedItemIDs: [UUID] { ... }
    var primarySelectedItemID: UUID? { ... }
    var selectedItemID: UUID? { ... }  // 兼容入口
    var workspaceMode: CanvasWorkspaceMode?
}
```

### 本次效果

- 文档 view-state 已经具备多选存储能力。
- 老文档如果只带 `selectedItemID`，仍然可以正常恢复成“单元素选择集 + 同值 primary”。
- 当前仍保留 `selectedItemID` 编码输出，方便阶段 0 到阶段 1 期间的平滑过渡。

## 5. Mapper 从单选映射升级为多选映射

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 说明: 旧 mapper 只传递 selectedItemID
selectedItemID: runtimeState.interactionState.selectedItemID

interactionState: CanvasInteractionState(
    selectedItemID: document.selectedItemID
)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 说明: 新 mapper 显式传递选择集和主选中项
selectedItemIDs: runtimeState.interactionState.selectedItemIDs,
primarySelectedItemID: runtimeState.interactionState.primarySelectedItemID

interactionState: CanvasInteractionState(
    selectedItemIDs: document.selectedItemIDs,
    primarySelectedItemID: document.primarySelectedItemID
)
```

### 本次效果

- runtime state 和 document state 的选择语义已经对齐。
- 阶段 0 完成后，选择契约可以在“运行时 -> 存档 -> 恢复”链路上闭环。

## 6. 文档格式版本提升

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift
// 结构/函数: CanvasImageAssetContract.current
// 说明: 旧文档格式版本为 4
static let current = CanvasImageAssetContract(
    playbackMode: .autoplayWhenVisible,
    editPolicy: .geometryOnlyNonDestructiveCrop,
    duplicationMode: .shareUnderlyingAssetReference,
    historyMode: .trackDocumentStateExcludingPlaybackProgress,
    targetDocumentFormatVersion: 4
)
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift
// 结构/函数: CanvasImageAssetContract.current
// 说明: 由于 view-state 契约变更，文档格式版本提升到 5
static let current = CanvasImageAssetContract(
    playbackMode: .autoplayWhenVisible,
    editPolicy: .geometryOnlyNonDestructiveCrop,
    duplicationMode: .shareUnderlyingAssetReference,
    historyMode: .trackDocumentStateExcludingPlaybackProgress,
    targetDocumentFormatVersion: 5
)
```

### 本次效果

- 新文档格式与多选 view-state 改动绑定。
- 旧数据仍通过 `BoardDocument.init(from:)` 的兼容路径继续可读。

## 7. 新增迁移测试文件

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 文件/函数: 新文件（修改前不存在）
// 说明: 仓库中原本没有覆盖“旧 selectedItemID -> 新选择集”迁移路径的专项测试
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数: testCanvasInteractionStateAppendsMissingPrimarySelection
// 说明: 验证 primary 不在 selection 中时，会被自动补入并保持状态合法
func testCanvasInteractionStateAppendsMissingPrimarySelection() {
    let interactionState = CanvasInteractionState(
        selectedItemIDs: [firstItemID],
        primarySelectedItemID: secondItemID
    )

    XCTAssertEqual(
        interactionState.selectedItemIDs,
        [firstItemID, secondItemID]
    )
    XCTAssertEqual(interactionState.primarySelectedItemID, secondItemID)
}

// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数: testBoardDocumentDecodesLegacySelectedItemIDIntoSelectionSet
// 说明: 验证旧 selectedItemID 文档可以迁移成新选择集结构
func testBoardDocumentDecodesLegacySelectedItemIDIntoSelectionSet() throws {
    legacyPayload["formatVersion"] = 4
    legacyPayload["selectedItemID"] = legacySelectedItemID.uuidString
    legacyPayload.removeValue(forKey: "selectedItemIDs")
    legacyPayload.removeValue(forKey: "primarySelectedItemID")
    ...
}

// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数: testBoardDocumentMapperRoundTripsMultiSelectionViewState
// 说明: 验证多选 view-state 可以从 runtimeState 正确写入并读回
func testBoardDocumentMapperRoundTripsMultiSelectionViewState() throws {
    let runtimeState = BoardRuntimeState(
        ...,
        interactionState: CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        ),
        workspaceMode: .editing
    )
    ...
}
```

### 本次效果

- 新增了选择状态归一化测试。
- 新增了旧文档迁移测试。
- 新增了 mapper 的多选 round-trip 测试。

## 8. 当前工作区附带 Changes（非阶段0主体逻辑）

### 8.1 `.gitignore`

#### 修改前

```bash
# 文件路径: .gitignore
# 文件/函数: 顶层忽略规则
# 说明: 旧规则只写了一个模糊的 .build* 模式
.build*
```

#### 修改后

```bash
# 文件路径: .gitignore
# 文件/函数: 顶层忽略规则
# 说明: 当前工作区中，这里被扩成了更明确的 build 忽略路径
.build/
.build*/
build/
```

### 8.2 `project.pbxproj`

#### 修改前

```text
# 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
# 文件/函数: PBXGroup / fileSystemSynchronizedGroups / buildSettings
# 说明: 修改前没有 Recovered References，部分 group 注释名更短，entitlements 路径带引号
- 组名: App / Canvas / BoardList / Rendering
- 无 Recovered References 组
- CODE_SIGN_ENTITLEMENTS = "MyCanvas_Ver_0/MyCanvas_Ver_0.entitlements";
```

#### 修改后

```text
# 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
# 文件/函数: PBXGroup / fileSystemSynchronizedGroups / buildSettings
# 说明: 当前工作区中，这里出现了工程分组重命名、Recovered References 以及 entitlements 引号调整
- 组名: MyCanvas_Ver_0/App / MyCanvas_Ver_0/Canvas / ...
- 新增 Recovered References 组
- CODE_SIGN_ENTITLEMENTS = MyCanvas_Ver_0/MyCanvas_Ver_0.entitlements;
```

> 上述两项属于当前工作区可见 changes，本记录只如实登记，不将其视为“图板多选阶段0”核心逻辑改动。

## 9. 本轮验证情况

### 9.1 静态检查

- 已对本轮修改文件执行 `ReadLints`。
- 结果：本轮修改文件没有新增 linter 报错。

### 9.2 测试尝试

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests
# 说明: 测试未真正跑到新增用例，先被仓库里既有测试辅助代码拦下
CanvasEditorSessionAlignmentOverlayTests.swift:320:20: error: extra argument 'updatedAt' in call
CanvasEditorSessionAlignmentOverlayTests.swift:316:22: error: missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
```

### 9.3 构建尝试

```bash
# 命令: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -target "MyCanvas_Ver_0" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
# 说明: 构建在现有工程装配阶段失败，失败原因不是本轮阶段0业务代码语义错误
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
```

## 10. 阶段0完成度结论

- 已完成选择契约升级：`single selected item -> selection set + primary selection`。
- 已完成存储迁移与旧文档兼容解码。
- 已完成历史快照对新选择态的对齐。
- 已补充阶段 0 所需迁移测试文件。
- 尚未进入阶段 1 的批量命令与选择行为改写。

