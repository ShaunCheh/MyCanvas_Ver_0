# 20260318_211000_boardlist_phase2_catalog_geometry_seed_record

## 记录范围

- 记录目标：
  1. 把 `BoardList` 的目录读取能力从旧的 `BoardStore.listBoards()` 摘出来，形成可复用的 `board document catalog` 层。
  2. 新增 `BoardCatalogItem`、`BoardPreviewSeed`、`BoardGeometryPreviewBuilder`、`BoardCatalogLoader`，为后续 `collection` 与几何预览铺底。
  3. 让双端 `BoardList` 从“只读 summary”切换到“读 catalog item”。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewSeed.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：
  - 阶段 1 的显式 `CanvasLaunchContext` 路由改造
  - 阶段 3 的 `collection` 容器和 `list/grid` 切换
  - 阶段 4/5 的几何预览展示控件与真实缩略图替换
  - git commit

## 修改一：`BoardStore.listBoards()` 的目录扫描逻辑抽成可复用 catalog entry

### 修改前

- `BoardStore.listBoards()` 自己负责扫目录、判断是否为合法 board 目录、读取 `board.json`、再返回 `[BoardSummary]`。
- 这意味着一旦 `BoardList` 想读比 `summary` 更多的数据，就只能重复写一套目录扫描逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/类型名: BoardStore.listBoards(userDefaults:)
// 功能说明: 修改前 listBoards 只返回 summary，且内部自己持有整套目录遍历与 document 读取逻辑。
static func listBoards(
    userDefaults: UserDefaults = .standard
) throws -> [BoardSummary] {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        try CoordinatedFileIO.ensureDirectory(at: boardsDirectoryURL)
        let candidateURLs = try CoordinatedFileIO.contentsOfDirectory(
            at: boardsDirectoryURL
        )

        var summaries: [BoardSummary] = []
        for candidateURL in candidateURLs {
            guard try isDirectory(candidateURL) else {
                continue
            }

            let boardDocumentURL = candidateURL.appendingPathComponent(boardDocumentFilename)
            guard FileManager.default.fileExists(atPath: boardDocumentURL.path) else {
                continue
            }

            let document = try readBoardDocument(at: boardDocumentURL)
            summaries.append(document.summary)
        }

        return summaries.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.boardID.uuidString < rhs.boardID.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
```

### 修改后

- 新增 `BoardDocumentCatalogEntry`，统一承载：
  - `boardDirectoryURL`
  - `documentURL`
  - `assetsDirectoryURL`
  - `document`
- 新增 `BoardStore.listBoardDocumentEntries()`，把原来 `listBoards()` 的目录遍历逻辑提出来。
- `listBoards()` 现在只做 `.map(\\.summary)`，不再自己重复遍历逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名/类型名: BoardDocumentCatalogEntry / BoardStore.listBoards(userDefaults:) / BoardStore.listBoardDocumentEntries(userDefaults:)
// 功能说明: 修改后存储层先产出可复用的 catalog entry，再由 listBoards 做 summary 映射，避免目录扫描逻辑重复。
struct BoardDocumentCatalogEntry {
    let boardDirectoryURL: URL
    let documentURL: URL
    let assetsDirectoryURL: URL
    let document: BoardDocument

    var summary: BoardSummary {
        document.summary
    }
}

static func listBoards(
    userDefaults: UserDefaults = .standard
) throws -> [BoardSummary] {
    try listBoardDocumentEntries(userDefaults: userDefaults).map(\\.summary)
}

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

## 修改二：补齐 `BoardList` 的 shared 目录模型与几何预览种子

### 修改前

- 项目里不存在 `BoardList` 专用的 shared catalog / preview seed 层。
- `BoardList` 拿到的只是 `BoardSummary`，没有地方承接：
  - `BoardDocument`
  - 几何预览 seed
  - revision token
- 阶段 1 的 controller 仍然只能停留在“读 summary -> 打开最新 board”的过渡状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.availableBoards / refreshBookmarkStatus()
// 功能说明: 修改前 BoardList 只能依赖 BoardSummary，无法挂接 document 与预览种子。
final class macOSBoardListViewController: NSViewController {
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private var availableBoards: [BoardSummary] = []

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boards = try BoardStore.listBoards()
            availableBoards = boards
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nBoards available: \(boards.count)"
            updateOpenCanvasButtonState(hasSelectedFolder: true)
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            bookmarkStatusLabel.stringValue = bookmarkText
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        } catch {
            availableBoards = []
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        }
    }
}
```

### 修改后

- 新增 `BoardCatalogItem`：承接 `BoardDocument` 与 `BoardPreviewSeed`，并提供 `boardID`、`title`、`summary`、`revisionToken` 等派生字段。
- 新增 `BoardPreviewSeed`：只保留 `boardWorldRect` 和 `nodes`，明确这是“几何预览输入”，不碰真实图片解码。
- 新增 `BoardGeometryPreviewBuilder`：
  - 从 `BoardDocument.items` 生成 `CanvasMiniMapNode`
  - 用 `center + size + rotationRadians` 重建可见 `worldQuad`
  - 优先使用 `document.boardRect`
  - 没有 `boardRect` 时，回退到 node bounds union
- 新增 `BoardCatalogLoader`：
  - 读取 `BoardStore.listBoardDocumentEntries()`
  - 把 `document` 转成 `BoardCatalogItem`
  - 顺手生成 `previewSeed`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 新增 BoardList shared 目录项，承接 document 与预览种子，并提供常用派生字段。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var title: String {
        document.title
    }

    var createdAt: Date {
        document.createdAt
    }

    var updatedAt: Date {
        document.updatedAt
    }

    var summary: BoardSummary {
        document.summary
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewSeed.swift
// 函数名/类型名: BoardPreviewSeed
// 功能说明: 新增几何预览种子，专门承载 BoardList 首屏预览需要的 geometry-first 数据。
import CoreGraphics
import Foundation

struct BoardPreviewSeed {
    let boardWorldRect: CGRect
    let nodes: [CanvasMiniMapNode]

    static let empty = BoardPreviewSeed(
        boardWorldRect: .zero,
        nodes: []
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名/类型名: BoardGeometryPreviewBuilder.makeSeed(from:) / makeSnapshot(from:)
// 功能说明: 新增几何预览构建器，直接从 persisted document 生成 minimap 风格的 preview seed 与 snapshot，不解码 assets。
import CoreGraphics
import Foundation

struct BoardGeometryPreviewBuilder {
    func makeSeed(from document: BoardDocument) -> BoardPreviewSeed {
        let nodes = makeNodes(from: document.items)
        let boardWorldRect = resolveBoardWorldRect(
            documentBoardRect: document.boardRect?.cgRect,
            nodes: nodes
        )
        return BoardPreviewSeed(
            boardWorldRect: boardWorldRect,
            nodes: nodes
        )
    }

    func makeSnapshot(from seed: BoardPreviewSeed) -> CanvasMiniMapSnapshot {
        CanvasMiniMapSnapshot(
            boardWorldRect: seed.boardWorldRect,
            displayWorldRect: resolveDisplayWorldRect(
                boardWorldRect: seed.boardWorldRect,
                nodes: seed.nodes
            ),
            visibleWorldRect: .zero,
            nodes: seed.nodes
        )
    }

    private func makeNodes(
        from itemRecords: [BoardImageItemRecord]
    ) -> [CanvasMiniMapNode] {
        itemRecords
            .compactMap(makeNode)
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.zIndex < rhs.zIndex
            }
    }

    private func makeNode(
        from itemRecord: BoardImageItemRecord
    ) -> CanvasMiniMapNode? {
        let size = itemRecord.size.cgSize
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return CanvasMiniMapNode(
            id: itemRecord.id,
            kind: .image,
            worldQuad: makeVisibleWorldQuad(from: itemRecord),
            zIndex: CGFloat(itemRecord.zIndex),
            isPreviewActive: false
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/类型名: BoardCatalogLoader.loadCatalog()
// 功能说明: 新增目录加载器，统一把 storage 层的 document entry 转成 BoardList 可直接消费的 catalog item。
import Foundation

struct BoardCatalogLoader {
    private let userDefaults: UserDefaults
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder

    init(
        userDefaults: UserDefaults = .standard,
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder()
    ) {
        self.userDefaults = userDefaults
        self.geometryPreviewBuilder = geometryPreviewBuilder
    }

    func loadCatalog() throws -> [BoardCatalogItem] {
        try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
            BoardCatalogItem(
                document: entry.document,
                previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
            )
        }
    }
}
```

## 修改三：双端 `BoardList` 从 `[BoardSummary]` 切到 `[BoardCatalogItem]`

### 修改前

- 双端 `BoardList` 仍然调用 `BoardStore.listBoards()`。
- controller 只拿到 `[BoardSummary]`，因此当前过渡按钮虽然能打开最新 board，但还接不上阶段 2 的 catalog/preview seed。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.availableBoards / refreshBookmarkStatus()
// 功能说明: 修改前 iOS BoardList 仍然直接读取 BoardSummary，无法保留 document 与 preview seed。
final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private var availableBoards: [BoardSummary] = []

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boards = try BoardStore.listBoards()
            availableBoards = boards
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boards.count)"
            updateOpenCanvasButtonState(hasSelectedFolder: true)
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            bookmarkStatusLabel.text = bookmarkText
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        } catch {
            availableBoards = []
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        }
    }
}
```

### 修改后

- 双端 `BoardList` 都新增 `catalogLoader`。
- `availableBoards` 统一改成 `[BoardCatalogItem]`。
- `refreshBookmarkStatus()` 改用 `catalogLoader.loadCatalog()`。
- 当前阶段的按钮行为不变，但 controller 已经切到了后续阶段所需的数据模型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.catalogLoader / availableBoards / refreshBookmarkStatus()
// 功能说明: 修改后 macOS BoardList 不再直接依赖 BoardSummary，而是接入完整的 catalog item 数据链。
final class macOSBoardListViewController: NSViewController {
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private let catalogLoader = BoardCatalogLoader()
    private var availableBoards: [BoardCatalogItem] = []

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boards = try catalogLoader.loadCatalog()
            availableBoards = boards
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nBoards available: \(boards.count)"
            updateOpenCanvasButtonState(hasSelectedFolder: true)
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            bookmarkStatusLabel.stringValue = bookmarkText
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        } catch {
            availableBoards = []
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.catalogLoader / availableBoards / refreshBookmarkStatus()
// 功能说明: 修改后 iOS BoardList 与 macOS 对齐，统一从 BoardCatalogLoader 获取目录数据。
final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private let catalogLoader = BoardCatalogLoader()
    private var availableBoards: [BoardCatalogItem] = []

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boards = try catalogLoader.loadCatalog()
            availableBoards = boards
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boards.count)"
            updateOpenCanvasButtonState(hasSelectedFolder: true)
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            bookmarkStatusLabel.text = bookmarkText
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        } catch {
            availableBoards = []
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        }
    }
}
```

## 行为结果

- `BoardList` 现在已经具备“目录项 + document + 预览种子”的 shared 数据底座。
- 存储层目录扫描逻辑不再只服务 `summary`，而是可以复用给阶段 3/4/5。
- 虽然当前 UI 仍然是阶段 1 的过渡页，但 controller 已经不再卡死在 `[BoardSummary]`。
- 后续阶段实现 `collection` 时，可以直接消费 `BoardCatalogItem.previewSeed`，不用再回头重做目录层。

## 校验结果

- 已检查本阶段相关文件的 `lints`，结果为无错误。
- 当前改动未包含工程级构建校验；本机 `xcodebuild` 仍不可用，因为系统 `xcode-select` 指向 `CommandLineTools` 而非完整 Xcode。

## 后续衔接

- 下一阶段可在此基础上继续实现：
  - 双端 `collection` 容器
  - `list/grid` 展示模式
  - 基于 `BoardCatalogItem` 的 cell 绑定
  - 首屏几何预览展示
