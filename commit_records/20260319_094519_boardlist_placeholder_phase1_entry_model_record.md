# 20260319_094519_boardlist_placeholder_phase1_entry_model_record

## 记录范围

- 记录目标：落实 `BoardList` 占位项方案的阶段 1，只新增 shared 的 UI entry 语义层。
- 本阶段目的：把“真实画板数据”和“New Board 占位项语义”分开，避免后续直接污染 `BoardCatalogItem`、`BoardPreviewProvider`、`BoardThumbnailRenderer` 这条真实画板链路。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift`
- 本记录不包含：双端 controller 改造。
- 本记录不包含：占位项样式绘制。
- 本记录不包含：交互行为改造。
- 本记录不包含：git commit。

## 修改一：新增 shared 的 `BoardListEntryID` 与 `BoardListEntry`，建立占位项与真实画板的 UI 语义分层

### 修改前

- `BoardList` shared 层还没有单独的 entry 模型。
- 当前 `BoardList` 相关 shared 数据模型里，`BoardCatalogItem` 只表达真实画板，不表达占位项。
- 如果后续直接把占位项硬塞进 `BoardCatalogItem`，会把真实画板的 `boardID`、`revisionToken`、preview / thumbnail 请求链一起污染。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift
// 函数名/类型名: BoardListEntryID / BoardListEntry
// 功能说明: 修改前文件不存在，BoardList 还没有“占位项 vs 真实画板”的 shared UI 语义分层。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 修改前 BoardCatalogItem 只描述真实 board，本身并不适合承载 New Board 占位项语义。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var title: String {
        document.title
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
```

### 修改后

- 新增 `BoardListEntryID`：
- `.newBoard`
- `.board(UUID)`
- 新增 `BoardListEntry`：
- `.newBoardPlaceholder`
- `.board(BoardCatalogItem)`
- 在同一文件内补齐下一阶段会直接复用的派生属性：
- `id`
- `title`
- `isPlaceholder`
- `boardID`
- `catalogItem`
- `canRequestPreview`
- `revisionToken`
- 这样后续 controller 可以先组装：
- `entries = [.newBoardPlaceholder] + availableBoards.map { .board($0) }`
- 同时又不需要修改 `BoardCatalogItem`、`BoardPreviewProvider` 或 thumbnail renderer 的真实 board 假设。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift
// 函数名/类型名: BoardListEntryID / BoardListEntry
// 功能说明: 修改后 shared entry 层把 New Board 占位项和真实画板分开表达，为后续 controller / cell / 交互改造提供稳定边界。
import Foundation

enum BoardListEntryID: Hashable {
    case newBoard
    case board(UUID)
}

enum BoardListEntry {
    static let newBoardTitle = "New Board"

    case newBoardPlaceholder
    case board(BoardCatalogItem)

    var id: BoardListEntryID {
        switch self {
        case .newBoardPlaceholder:
            return .newBoard
        case let .board(item):
            return .board(item.boardID)
        }
    }

    var title: String {
        switch self {
        case .newBoardPlaceholder:
            return Self.newBoardTitle
        case let .board(item):
            return item.title
        }
    }

    var isPlaceholder: Bool {
        if case .newBoardPlaceholder = self {
            return true
        }

        return false
    }

    var boardID: UUID? {
        switch self {
        case .newBoardPlaceholder:
            return nil
        case let .board(item):
            return item.boardID
        }
    }

    var catalogItem: BoardCatalogItem? {
        switch self {
        case .newBoardPlaceholder:
            return nil
        case let .board(item):
            return item
        }
    }

    var canRequestPreview: Bool {
        catalogItem != nil
    }

    var revisionToken: String? {
        catalogItem?.revisionToken
    }
}
```

## 阶段结果

- 阶段 1 完成后，`BoardList` 已经有了独立于真实 board 数据的 UI entry 语义层。
- 后续阶段 2 可以直接把双端 controller 从 `[BoardCatalogItem]` 驱动，平滑过渡到 `[BoardListEntry]` 驱动，而不需要再回头重构 shared preview / thumbnail 管线。

## 验证情况

- 已对 `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift` 执行 lint 检查，未发现新增问题。
- 本次没有执行工程级编译验证。
