# 20260326_093814_read_mode_phase1_persistence_contract_record

## 记录范围

- 记录内容：
  1. 实施“阅读模式切换”计划的 `Phase 1`，建立共享的模式类型，并把模式状态接入按画板持久化链路。
  2. 确保阅读模式/编辑模式能够随 `BoardRuntimeState -> BoardDocument -> BoardDocumentMapper -> CanvasEditorSession` 闭环保存与恢复。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasWorkspaceMode.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - 阅读模式按钮 UI
  - 输入门控、命令门控、上下文菜单门控

## 修改一：新增共享模式类型

### 修改前

- 工程里还没有“阅读模式/编辑模式”的共享类型。
- 也没有一个可复用的模式符号、显示文案或切换语义载体，后续 UI 与持久化都没有统一依赖点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasWorkspaceMode.swift
// 函数名/符号名: CanvasWorkspaceMode
// 功能说明: 修改前该文件不存在，工程内没有共享的画板模式类型。
// (Phase 1 之前无此文件)
```

### 修改后

- 新增 `CanvasWorkspaceMode`，统一承载：
  - `.editing` / `.reading`
  - 当前模式对应的符号名
  - 显示文案
  - 无障碍文本
  - 模式切换后的 `toggled`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasWorkspaceMode.swift
// 函数名/符号名: CanvasWorkspaceMode
// 功能说明: 新增共享模式类型，作为阅读模式/编辑模式的单一语义来源，供后续 UI、持久化和门控逻辑统一消费。
enum CanvasWorkspaceMode: String, CaseIterable, Codable, Sendable {
    case editing
    case reading

    var systemImageName: String {
        switch self {
        case .editing:
            return "pencil"
        case .reading:
            return "book.closed"
        }
    }

    var displayName: String {
        switch self {
        case .editing:
            return "Editing"
        case .reading:
            return "Reading"
        }
    }

    var accessibilityLabel: String {
        "Canvas mode"
    }

    var accessibilityValue: String {
        displayName
    }

    var toggled: CanvasWorkspaceMode {
        switch self {
        case .editing:
            return .reading
        case .reading:
            return .editing
        }
    }
}
```

### 结果

- 画板模式第一次有了共享层的明确契约。
- 后续按钮图标、持久化字段、命令门控都可以依赖这一处定义，而不是各自发明状态枚举。

## 修改二：把模式接入 `BoardRuntimeState` 与 `BoardDocument`

### 修改前

- `BoardRuntimeState` 只保存 `items`、`boardState`、`camera`、`interactionState`，不保存模式状态。
- `BoardDocument` 也没有任何阅读/编辑模式字段，因此重新打开画板时无法按 board 恢复模式。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名/符号名: BoardRuntimeState / BoardRuntimeState.makeEmpty() / BoardDocument
// 功能说明: 修改前运行时状态和持久化文档都没有 workspaceMode 字段，模式无法进入保存链。
struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState

    static func makeEmpty(
        boardID: UUID = UUID(),
        title: String = BoardDocument.defaultTitle,
        now: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: now,
            updatedAt: now,
            items: [],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState()
        )
    }
}

struct BoardDocument: Codable {
    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var items: [BoardItemRecord]
}
```

### 修改后

- `BoardRuntimeState` 新增 `workspaceMode`
- `makeEmpty()` 默认设为 `.editing`
- `BoardDocument` 新增可选 `workspaceMode`
- 旧文档因为没有这个字段，会自然解码为 `nil`，给后续 mapper 的默认回退留出兼容空间

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名/符号名: BoardRuntimeState / BoardRuntimeState.makeEmpty() / BoardDocument
// 功能说明: 修改后模式被正式纳入运行时状态与持久化文档结构，为“按画板持久化”建立数据基础。
struct BoardRuntimeState {
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CanvasBoardItem]
    var boardState: CanvasBoardState?
    var camera: CanvasCamera
    var interactionState: CanvasInteractionState
    var workspaceMode: CanvasWorkspaceMode

    static func makeEmpty(
        boardID: UUID = UUID(),
        title: String = BoardDocument.defaultTitle,
        now: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: now,
            updatedAt: now,
            items: [],
            boardState: nil,
            camera: CanvasCamera(),
            interactionState: CanvasInteractionState(),
            workspaceMode: .editing
        )
    }
}

struct BoardDocument: Codable {
    let formatVersion: Int
    let boardID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var boardBaseSize: BoardSizeRecord?
    var boardRect: BoardRectRecord?
    var cameraCenter: BoardPointRecord
    var cameraZoomScale: Double
    var selectedItemID: UUID?
    var workspaceMode: CanvasWorkspaceMode?
    var items: [BoardItemRecord]
}
```

### 结果

- 模式现在已经能进入 board 的保存载体。
- 旧数据兼容性保留，因为 `BoardDocument.workspaceMode` 是可选字段。

## 修改三：把模式接入 `BoardDocumentMapper`

### 修改前

- `makeDocument(from:)` 不会把模式写入文档。
- `makeRuntimeState(from:)` 也不会把模式从文档恢复到运行时状态。
- 这样即使 `BoardDocument` / `BoardRuntimeState` 本身有字段，也不会真正打通保存闭环。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改前 mapper 只处理 camera、selection 和 items，不处理 workspaceMode。
static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
    return BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: runtimeState.boardID,
        title: runtimeState.title,
        createdAt: runtimeState.createdAt,
        updatedAt: runtimeState.updatedAt,
        boardBaseSize: runtimeState.boardState.map { BoardSizeRecord($0.baseSize) },
        boardRect: runtimeState.boardState.map { BoardRectRecord($0.worldRect) },
        cameraCenter: BoardPointRecord(runtimeState.camera.center),
        cameraZoomScale: Double(runtimeState.camera.zoomScale),
        selectedItemID: runtimeState.interactionState.selectedItemID,
        items: runtimeState.items.map(makeItemRecord)
    )
}

static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    // ...
    let runtimeState = BoardRuntimeState(
        boardID: document.boardID,
        title: document.title,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
        items: items,
        boardState: makeBoardState(
            boardBaseSize: document.boardBaseSize,
            boardRect: document.boardRect
        ),
        camera: CanvasCamera(
            center: document.cameraCenter.cgPoint,
            zoomScale: CGFloat(document.cameraZoomScale),
            viewportSize: .zero
        ),
        interactionState: CanvasInteractionState(
            selectedItemID: document.selectedItemID
        )
    )
    return runtimeState
}
```

### 修改后

- `makeDocument(from:)` 会把 `runtimeState.workspaceMode` 写入文档
- `makeRuntimeState(from:)` 会读取 `document.workspaceMode ?? .editing`
- 这样旧文档自动回退编辑模式，新文档则完整保留每个 board 的上次模式

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeDocument(from:) / makeRuntimeState(from:imageLoader:)
// 功能说明: 修改后 mapper 正式承担 workspaceMode 的双向映射，并通过 nil 回退保证旧文档兼容。
static func makeDocument(from runtimeState: BoardRuntimeState) -> BoardDocument {
    return BoardDocument(
        formatVersion: BoardDocument.currentFormatVersion,
        boardID: runtimeState.boardID,
        title: runtimeState.title,
        createdAt: runtimeState.createdAt,
        updatedAt: runtimeState.updatedAt,
        boardBaseSize: runtimeState.boardState.map { BoardSizeRecord($0.baseSize) },
        boardRect: runtimeState.boardState.map { BoardRectRecord($0.worldRect) },
        cameraCenter: BoardPointRecord(runtimeState.camera.center),
        cameraZoomScale: Double(runtimeState.camera.zoomScale),
        selectedItemID: runtimeState.interactionState.selectedItemID,
        workspaceMode: runtimeState.workspaceMode,
        items: runtimeState.items.map(makeItemRecord)
    )
}

static func makeRuntimeState(
    from document: BoardDocument,
    imageLoader: (BoardImageItemRecord) throws -> CGImage
) throws -> BoardRuntimeState {
    // ...
    let runtimeState = BoardRuntimeState(
        boardID: document.boardID,
        title: document.title,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
        items: items,
        boardState: makeBoardState(
            boardBaseSize: document.boardBaseSize,
            boardRect: document.boardRect
        ),
        camera: CanvasCamera(
            center: document.cameraCenter.cgPoint,
            zoomScale: CGFloat(document.cameraZoomScale),
            viewportSize: .zero
        ),
        interactionState: CanvasInteractionState(
            selectedItemID: document.selectedItemID
        ),
        workspaceMode: document.workspaceMode ?? .editing
    )
    return runtimeState
}
```

### 结果

- 模式状态的保存/恢复闭环已经打通。
- “按画板持久化”真正开始成立，而不是只停留在内存态。

## 修改四：把模式接入 `CanvasEditorSession`

### 修改前

- `CanvasEditorSession` 还没有共享的模式真源。
- `applyBoardRuntimeState(...)` 和 `currentBoardRuntimeState(...)` 也不会恢复或导出模式。
- 这意味着即便底层数据结构接好了，session 仍然无法真正携带模式状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession / applyBoardRuntimeState(_:preserveTransientImageAssetPayloads:) / currentBoardRuntimeState(createBoardIfNeeded:)
// 功能说明: 修改前 session 只负责 items、camera、selection 等运行时状态，不持有 workspaceMode，也不通过 runtimeState 保存或恢复它。
final class CanvasEditorSession {
    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?
}

func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        boardID: activeBoardID,
        title: activeBoardTitle,
        createdAt: activeBoardCreatedAt,
        updatedAt: Date(),
        items: scene.orderedBoardItems(),
        boardState: boardState,
        camera: camera,
        interactionState: interactionState
    )
}
```

### 修改后

- `CanvasEditorSession` 新增 `workspaceMode`
- 增加便于后续门控使用的 `isReadingModeActive` / `isEditingModeActive`
- `applyBoardRuntimeState(...)` 恢复模式
- `currentBoardRuntimeState(...)` 导出模式

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession / applyBoardRuntimeState(_:preserveTransientImageAssetPayloads:) / currentBoardRuntimeState(createBoardIfNeeded:)
// 功能说明: 修改后 session 成为阅读/编辑模式的运行时真源，并负责把该状态纳入 runtimeState 的保存与恢复闭环。
final class CanvasEditorSession {
    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
    var workspaceMode: CanvasWorkspaceMode = .editing
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?

    var isReadingModeActive: Bool {
        workspaceMode == .reading
    }

    var isEditingModeActive: Bool {
        workspaceMode == .editing
    }
}

func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    activeBoardID = runtimeState.boardID
    activeBoardTitle = runtimeState.title
    activeBoardCreatedAt = runtimeState.createdAt
    scene.setItems(runtimeState.items)
    boardState = runtimeState.boardState
    camera = runtimeState.camera
    interactionState = runtimeState.interactionState
    workspaceMode = runtimeState.workspaceMode
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
}

func currentBoardRuntimeState(
    createBoardIfNeeded: Bool = false
) -> BoardRuntimeState? {
    // ...
    return BoardRuntimeState(
        boardID: activeBoardID,
        title: activeBoardTitle,
        createdAt: activeBoardCreatedAt,
        updatedAt: Date(),
        items: scene.orderedBoardItems(),
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        workspaceMode: workspaceMode
    )
}
```

### 结果

- 模式现在不只是持久化字段，也成为了 session 层的共享真源。
- 后续 Phase 2-5 的 UI、工具条、命令、输入门控都可以统一依赖 `editorSession.workspaceMode`。

## 修改五：保持 history/document 替换链不丢失模式

### 修改前

- `BoardHistorySnapshot.replacingDocumentState(...)` 在回组 `BoardRuntimeState` 时不会携带模式。
- 这样一旦某些路径经由 `historySnapshot -> replacingDocumentState` 回写运行时状态，模式就可能丢失。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: replacingDocumentState(with:updatedAt:)
// 功能说明: 修改前 history/document 替换链只保留 document 相关状态，不会把 workspaceMode 带回新的 runtimeState。
func replacingDocumentState(
    with snapshot: BoardHistorySnapshot,
    updatedAt: Date = Date()
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: boardID,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: snapshot.items,
        boardState: snapshot.boardState,
        camera: camera,
        interactionState: snapshot.interactionState
    )
}
```

### 修改后

- `replacingDocumentState(...)` 会保留原有 `workspaceMode`
- 这样历史回放与文档状态替换路径不会把模式意外抹掉

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: replacingDocumentState(with:updatedAt:)
// 功能说明: 修改后 history/document 替换链会保留既有 workspaceMode，避免模式在中间状态重建时被丢失。
func replacingDocumentState(
    with snapshot: BoardHistorySnapshot,
    updatedAt: Date = Date()
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: boardID,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        items: snapshot.items,
        boardState: snapshot.boardState,
        camera: camera,
        interactionState: snapshot.interactionState,
        workspaceMode: workspaceMode
    )
}
```

### 结果

- 模式字段不会在 history/restore 相关路径上丢失。
- 持久化链不再只有“主保存路径”正确，而是把替换路径也一起补齐了。

## 结构变化总结

- `Phase 1` 完成后，阅读模式/编辑模式已经拥有完整的数据闭环：
  1. `CanvasWorkspaceMode` 定义模式语义
  2. `CanvasEditorSession.workspaceMode` 持有运行时真源
  3. `currentBoardRuntimeState()` 把模式导出到 `BoardRuntimeState`
  4. `BoardDocumentMapper.makeDocument(from:)` 把模式写入 `BoardDocument`
  5. `BoardDocumentMapper.makeRuntimeState(from:)` 把模式从文档恢复回来
  6. `applyBoardRuntimeState(...)` 把模式重新灌回 session

- 当前还没有任何 UI 或行为变化；这一步只是把后续阶段赖以生效的模式基础设施先搭好。

## 验证记录

- `ReadLints` 检查以下文件，结果为无错误：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasWorkspaceMode.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `swiftc -frontend -parse` 解析以下文件通过：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasWorkspaceMode.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
