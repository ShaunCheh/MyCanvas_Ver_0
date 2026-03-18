# 20260318_205342_boardlist_phase1_launch_context_record

## 记录范围

- 记录目标：
  1. 为 `BoardList -> Canvas` 补齐显式启动上下文，区分“打开已有画板”和“新建空白画板”。
  2. 在 `BoardList` 还未进入 `collection + list/grid` 阶段前，为现有按钮补一个可工作的过渡行为。
  3. 保留原有 `restorePersistedBoardIfPossible()` 兜底逻辑，不提前引入阶段 2/3 的目录加载与缩略图能力。
- 涉及文件：
  - `MyCanvas_Ver_0/App/AppLaunchDestination.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - 阶段 2 的 `BoardCatalogLoader` / `BoardPreviewSeed` / 几何预览构建器
  - 阶段 3 的 `collection` 容器与 `list/grid` 切换
  - 阶段 4/5 的混合预览与真实缩略图替换
  - git commit

## 修改一：启动路由从无参 `canvas` 改为显式 `CanvasLaunchContext`

### 修改前

- 路由只有 `boardList` 和无参 `canvas`。
- `BoardList` 无法表达“打开哪个 `boardID`”或“显式新建空白板”。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数名/类型名: AppLaunchDestination
// 功能说明: 修改前 Canvas 路由不携带上下文，BoardList 只能无参跳转到 Canvas。
import Foundation

enum AppLaunchDestination {
    case boardList
    case canvas
}
```

### 修改后

- 新增 `CanvasLaunchContext`。
- `AppLaunchDestination.canvas` 现在必须携带启动上下文。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数名/类型名: CanvasLaunchContext / AppLaunchDestination
// 功能说明: 修改后 Canvas 路由显式区分“打开已有画板”和“新建空白画板”。
import Foundation

enum CanvasLaunchContext {
    case existing(boardID: UUID)
    case newBoard
}

enum AppLaunchDestination {
    case boardList
    case canvas(CanvasLaunchContext)
}
```

## 修改二：`AppRoot` 把 `BoardList` 动作分发为 `existing(boardID)` 或 `newBoard`

### 修改前

- `BoardList` 只有 `onOpenCanvas`，`AppRoot` 只能无参跳到 Canvas。
- 新建板和打开已有板没有分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 AppRoot 只能把 BoardList 的点击动作映射成无参 .canvas。
private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        let viewController = macOSBoardListViewController()
        viewController.onOpenCanvas = { [weak self] in
            self?.display(.canvas)
        }
        return viewController
    case .canvas:
        return macOSViewController()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 iOS 端与 macOS 相同，也只有无参 .canvas 跳转。
private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        let viewController = iOSBoardListViewController()
        viewController.onOpenCanvas = { [weak self] in
            self?.display(.canvas)
        }
        return viewController
    case .canvas:
        return iOSViewController()
    }
}
```

### 修改后

- `BoardList` 回调被拆成 `onOpenBoard` 和 `onCreateBoard`。
- `AppRoot` 负责把回调转成 `.canvas(.existing(boardID: ...))` 或 `.canvas(.newBoard)`。
- `Canvas` controller 创建时会接收到显式 `launchContext`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 macOS AppRoot 负责把 BoardList 的动作转成带上下文的 Canvas 路由。
private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        let viewController = macOSBoardListViewController()
        viewController.onOpenBoard = { [weak self] boardID in
            self?.display(.canvas(.existing(boardID: boardID)))
        }
        viewController.onCreateBoard = { [weak self] in
            self?.display(.canvas(.newBoard))
        }
        return viewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 iOS AppRoot 与 macOS 对齐，统一走带上下文的 Canvas 路由。
private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        let viewController = iOSBoardListViewController()
        viewController.onOpenBoard = { [weak self] boardID in
            self?.display(.canvas(.existing(boardID: boardID)))
        }
        viewController.onCreateBoard = { [weak self] in
            self?.display(.canvas(.newBoard))
        }
        return viewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}
```

## 修改三：双端 `BoardList` 增加阶段 1 过渡行为

### 修改前

- 页面只有“选目录”和“打开 Canvas”两个静态按钮。
- “打开 Canvas”不区分是否已有画板，也不会根据目录状态调整交互。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController / handleOpenCanvasButtonClick()
// 功能说明: 修改前 macOS BoardList 只负责无参打开 Canvas，不参与目录状态分流。
final class macOSBoardListViewController: NSViewController {
    var onOpenCanvas: (() -> Void)?

    private let openCanvasButton: NSButton = {
        let button = NSButton(title: "Open Canvas", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        return button
    }()

    @objc
    private func handleOpenCanvasButtonClick() {
        onOpenCanvas?()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController / handleOpenCanvasButtonTap()
// 功能说明: 修改前 iOS BoardList 与 macOS 一样，按钮文案固定且无目录态分流。
final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()
    var onOpenCanvas: (() -> Void)?

    private let openCanvasButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Open Canvas"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        return button
    }()

    @objc
    private func handleOpenCanvasButtonTap() {
        onOpenCanvas?()
    }
}
```

### 修改后

- `BoardList` 新增 `availableBoards`、`onOpenBoard`、`onCreateBoard`。
- 按钮根据当前目录状态切换为：
  - `Select Folder First`
  - `Open Latest Board`
  - `Create Board`
- 当前阶段的临时策略是：直接打开 `BoardStore.listBoards()` 排序后的第一个画板，或在空目录进入新建板流程。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController / refreshBookmarkStatus() / updateOpenCanvasButtonState(hasSelectedFolder:) / handleOpenCanvasButtonClick()
// 功能说明: 修改后 macOS BoardList 会根据目录状态决定是打开最新画板还是创建新画板。
final class macOSBoardListViewController: NSViewController {
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private var availableBoards: [BoardSummary] = []

    private let openCanvasButton: NSButton = {
        let button = NSButton(title: "Select Folder First", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.isEnabled = false
        return button
    }()

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

    private func updateOpenCanvasButtonState(hasSelectedFolder: Bool) {
        guard hasSelectedFolder else {
            openCanvasButton.title = "Select Folder First"
            openCanvasButton.isEnabled = false
            return
        }

        openCanvasButton.title = availableBoards.isEmpty
            ? "Create Board"
            : "Open Latest Board"
        openCanvasButton.isEnabled = true
    }

    @objc
    private func handleOpenCanvasButtonClick() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if let latestBoard = availableBoards.first {
            onOpenBoard?(latestBoard.boardID)
        } else {
            onCreateBoard?()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController / refreshBookmarkStatus() / updateOpenCanvasButtonState(hasSelectedFolder:) / handleOpenCanvasButtonTap()
// 功能说明: 修改后 iOS BoardList 与 macOS 保持一致，根据目录状态切换打开/新建行为。
final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private var availableBoards: [BoardSummary] = []

    private let openCanvasButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Select Folder First"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.isEnabled = false
        return button
    }()

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

    private func updateOpenCanvasButtonState(hasSelectedFolder: Bool) {
        var configuration = openCanvasButton.configuration ?? UIButton.Configuration.tinted()
        if hasSelectedFolder {
            configuration.title = availableBoards.isEmpty
                ? "Create Board"
                : "Open Latest Board"
            openCanvasButton.isEnabled = true
        } else {
            configuration.title = "Select Folder First"
            openCanvasButton.isEnabled = false
        }
        openCanvasButton.configuration = configuration
    }

    @objc
    private func handleOpenCanvasButtonTap() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if let latestBoard = availableBoards.first {
            onOpenBoard?(latestBoard.boardID)
        } else {
            onCreateBoard?()
        }
    }
}
```

## 修改四：`CanvasEditorSession` 增加显式加载已有板/新建板入口

### 修改前

- `CanvasEditorSession` 只有 `restorePersistedBoardIfPossible()` 这条恢复入口。
- controller 无法要求 session “打开指定 `boardID`” 或“显式起一个新的空白板”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: CanvasEditorSession.restorePersistedBoardIfPossible()
// 功能说明: 修改前 session 只支持“恢复第一个已有画板或创建空白画板”的兜底流程。
func restorePersistedBoardIfPossible() {
    do {
        let runtimeState = try BoardStore.loadOrCreateInitialBoard()
        applyBoardRuntimeState(runtimeState)
        resetHistory()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("\(boardStoreLogPrefix) Failed to restore board: \(error)")
    }
}
```

### 修改后

- 新增 `loadBoard(id:)`，专门加载显式选中的 `boardID`。
- 新增 `startNewBoard()`，专门建立新的运行态空白板。
- 保留 `restorePersistedBoardIfPossible()` 作为无上下文时的兜底入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: CanvasEditorSession.loadBoard(id:) / startNewBoard(now:) / restorePersistedBoardIfPossible()
// 功能说明: 修改后 session 同时具备“加载指定板”“新建空白板”“旧恢复兜底”三种入口。
func loadBoard(id: UUID) throws {
    let runtimeState = try BoardStore.loadBoard(id: id)
    print(
        "[Canvas Shared][RuntimeRestore] " +
        "action=loadBoard " +
        "boardID=\(runtimeState.boardID.uuidString)"
    )
    applyBoardRuntimeState(runtimeState)
    resetHistory()
}

func startNewBoard(now: Date = Date()) {
    let runtimeState = BoardRuntimeState.makeEmpty(now: now)
    print(
        "[Canvas Shared][RuntimeRestore] " +
        "action=startNewBoard " +
        "boardID=\(runtimeState.boardID.uuidString)"
    )
    applyBoardRuntimeState(runtimeState)
    resetHistory()
}

func restorePersistedBoardIfPossible() {
    do {
        let runtimeState = try BoardStore.loadOrCreateInitialBoard()
        applyBoardRuntimeState(runtimeState)
        resetHistory()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("\(boardStoreLogPrefix) Failed to restore board: \(error)")
    }
}
```

## 修改五：双端 Canvas controller 按 `launchContext` 决定启动路径

### 修改前

- 双端 controller 在 `viewDidLoad()` 里都直接调用 `restorePersistedBoardIfPossible()`。
- 即使 `BoardList` 将来能选中某个 `boardID`，controller 也没有消费该上下文的位置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.viewDidLoad() / restorePersistedBoardIfPossible()
// 功能说明: 修改前 macOS controller 只会恢复默认画板，不会读取外部启动上下文。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restorePersistedBoardIfPossible()
    setupCanvasViewport()
}

private func restorePersistedBoardIfPossible() {
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.viewDidLoad() / restorePersistedBoardIfPossible()
// 功能说明: 修改前 iOS controller 与 macOS 一样，入口固定为默认恢复流程。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupUndoButton()
    setupRedoButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restorePersistedBoardIfPossible()
    setupCanvasViewport()
}

private func restorePersistedBoardIfPossible() {
    editorSession.restorePersistedBoardIfPossible()
    updateInlineEditButtonsAppearance()
}
```

### 修改后

- 双端 controller 都新增 `launchContext`。
- `viewDidLoad()` 先走 `restoreInitialBoardState()`，再进入现有视口装配流程。
- `restoreInitialBoardState()` 内部分三路：
  - `.existing(boardID)` -> `restoreBoard(withID:)`
  - `.newBoard` -> `startNewBoard()`
  - `nil` -> `restorePersistedBoardIfPossible()`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.launchContext / viewDidLoad() / restoreInitialBoardState()
// 功能说明: 修改后 macOS controller 会先消费外部启动上下文，再继续原有视口与交互装配流程。
var launchContext: CanvasLaunchContext?

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func restoreInitialBoardState() {
    switch launchContext {
    case let .existing(boardID):
        restoreBoard(withID: boardID)
    case .newBoard:
        startNewBoard()
    case .none:
        restorePersistedBoardIfPossible()
    }
}

private func restoreBoard(withID boardID: UUID) {
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas macOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateInlineEditButtonsAppearance()
}

private func startNewBoard() {
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.launchContext / viewDidLoad() / restoreInitialBoardState()
// 功能说明: 修改后 iOS controller 与 macOS 对齐，启动时优先消费 BoardList 传入的上下文。
var launchContext: CanvasLaunchContext?

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupUndoButton()
    setupRedoButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func restoreInitialBoardState() {
    switch launchContext {
    case let .existing(boardID):
        restoreBoard(withID: boardID)
    case .newBoard:
        startNewBoard()
    case .none:
        restorePersistedBoardIfPossible()
    }
}

private func restoreBoard(withID boardID: UUID) {
    do {
        try editorSession.loadBoard(id: boardID)
    } catch {
        print(
            "[Canvas iOS][RuntimeRestore] " +
            "action=controllerLoadBoard.failed " +
            "boardID=\(boardID.uuidString) " +
            "error=\(error)"
        )
    }
    updateInlineEditButtonsAppearance()
}

private func startNewBoard() {
    editorSession.startNewBoard()
    updateInlineEditButtonsAppearance()
}
```

## 行为结果

- `BoardList -> Canvas` 现在已经具备显式语义：
  - 有画板时，当前过渡按钮会打开最近更新的画板
  - 无画板时，会进入空白画板启动路径
- 双端 `Canvas` 不再被迫只能走“恢复第一个画板/自动创建空白板”的默认流程
- 阶段 2 以后只需要把“当前按钮触发”换成“collection 选中项触发”，无需再重做启动链路

## 校验结果

- 已检查最近修改文件的 `lints`，结果为无错误。
- 尝试执行 `xcodebuild -list -project "MyCanvas_Ver_0.xcodeproj"`，但当前系统 `xcode-select` 指向 `CommandLineTools`，无法完成工程级构建校验。

## 后续衔接

- 下一阶段可在此基础上继续实现：
  - `BoardCatalogLoader`
  - `BoardPreviewSeed`
  - `BoardGeometryPreviewBuilder`
  - 双端 `collection` 容器与 `list/grid` 切换
