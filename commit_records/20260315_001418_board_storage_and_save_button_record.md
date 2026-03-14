# 20260315_001418_board_storage_and_save_button_record

## 记录范围

- 记录内容：
  1. 实施统一的画板存储方案，把 bookmark 解析、security-scoped 目录访问、文件协调、`board.json + assets` 读写下沉到共享层。
  2. 在 iOS / macOS 的 `canvas` 页面新增悬浮 `Save` 按钮，提供显式手动保存入口和状态反馈。
- 涉及文件：
  - `MyCanvas_Ver_0/App/FolderBookmarkStore.swift`
  - `MyCanvas_Ver_0/App/SelectedFolderAccess.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0.xcodeproj/project.pbxproj`
- 本记录不包含：原始 gif diff、额外的提交流程。

## 修改一：实施统一画板存储

### 修改前

- 目录 bookmark 只用于状态展示，缺少一个共享的“可访问工作目录”入口。
- `canvas` 里的 `scene / boardState / camera / interactionState` 只存在控制器内存中，没有统一的 `BoardStore` 负责读写。
- `BoardList` 仍是占位入口，只能选目录，不能打开画布，也不会显示已存画板数量。
- macOS 工程对用户选择目录的权限还是 `readonly`，不适合向所选目录写 `board.json` 和图片资产。

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数名: storedFolderPath(userDefaults:) / statusText(userDefaults:)
// 功能说明: 修改前只有 bookmark 路径展示逻辑，没有对外提供统一的已解析目录 URL。
enum FolderBookmarkStore {
    private static let bookmarkDefaultsKey = "SelectedFolderBookmarkData"

    static func storedFolderPath(userDefaults: UserDefaults = .standard) -> String? {
        guard let bookmarkData = storedBookmarkData(userDefaults: userDefaults) else {
            return nil
        }

        // 这里只把 bookmark 解析成 path 文本，后续存储层还无法直接复用它做目录访问。
        return nil
    }

    static func statusText(userDefaults: UserDefaults = .standard) -> String {
        if let path = storedFolderPath(userDefaults: userDefaults) {
            return "Saved folder path:\n\(path)"
        }
        return "No bookmark data stored in UserDefaults."
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: viewDidLoad()
// 功能说明: 修改前画布控制器只初始化 UI 和 viewport，没有恢复已保存画板，也没有持久化状态字段。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private var boardState: CanvasBoardState?
    private var interactionState = CanvasInteractionState()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupCanvasViewport()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus()
// 功能说明: 修改前 BoardList 只显示 bookmark 状态，没有打开画布入口，也不会读取已保存画板数量。
private func refreshBookmarkStatus() {
    bookmarkStatusLabel.text = FolderBookmarkStore.statusText()
}
```

```swift
// 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
// 函数名: Debug / Release buildSettings
// 功能说明: 修改前用户选择目录权限是只读，不能稳定向所选目录落盘画板文件。
ENABLE_USER_SELECTED_FILES = readonly;
```

### 修改后

- `FolderBookmarkStore` 新增 `FolderBookmarkStoreError` 和 `resolveStoredFolderBookmark(userDefaults:)`，把 bookmark 解析错误和已解析 URL 统一封装起来。
- 新增 `SelectedFolderAccess`，统一处理 `startAccessingSecurityScopedResource()`、`stopAccessingSecurityScopedResource()`，并约定工作目录为 `<selected-folder>/MyCanvasData/boards/`。
- 新增 `BoardStore`，统一提供 `listBoards` / `loadBoard` / `saveBoard` / `deleteBoard` / `loadOrCreateInitialBoard`。
- `CanvasBoardState` 新增 `init(baseSize:worldRect:)`，支持从持久化的 `worldRect` 恢复。
- `BoardList` 新增 `Open Canvas` 入口，并在状态文案里显示已存画板数量。
- `iOS / macOS` `canvas` 控制器进入时会尝试恢复画板，交互后通过 `scheduleAutosave(...)` 自动保存。
- 工程权限改为 `readwrite`，允许向用户选择目录写入画板数据。

```swift
// 文件路径: MyCanvas_Ver_0/App/SelectedFolderAccess.swift
// 函数名: withSelectedFolderURL(userDefaults:_:) / withBoardsDirectoryURL(userDefaults:_:)
// 功能说明: 修改后把 bookmark 解析、security-scoped 生命周期和工作目录拼接统一下沉到共享层。
enum SelectedFolderAccess {
    static let workspaceDirectoryName = "MyCanvasData"
    static let boardsDirectoryName = "boards"

    static func withSelectedFolderURL<T>(
        userDefaults: UserDefaults = .standard,
        _ body: (URL) throws -> T
    ) throws -> T {
        let resolvedBookmark = try FolderBookmarkStore.resolveStoredFolderBookmark(
            userDefaults: userDefaults
        )
        let url = resolvedBookmark.url
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try body(url)
    }

    static func withBoardsDirectoryURL<T>(
        userDefaults: UserDefaults = .standard,
        _ body: (URL) throws -> T
    ) throws -> T {
        try withWorkspaceURL(userDefaults: userDefaults) { workspaceURL in
            let boardsDirectoryURL = workspaceURL.appendingPathComponent(
                boardsDirectoryName,
                isDirectory: true
            )
            return try body(boardsDirectoryURL)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:userDefaults:) / loadOrCreateInitialBoard(userDefaults:)
// 功能说明: 修改后统一把画板写进 board.json 和 assets 目录，并在首次进入时自动创建空画板。
enum BoardStore {
    private static let boardDocumentFilename = "board.json"
    private static let assetsDirectoryName = "assets"

    static func saveBoard(
        _ runtimeState: BoardRuntimeState,
        userDefaults: UserDefaults = .standard
    ) throws {
        try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
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

            // 逐个写入图片资产，再写 board.json。
            for item in runtimeState.items {
                let assetURL = assetsDirectoryURL.appendingPathComponent(
                    "\(item.id.uuidString).png"
                )
                let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
                try CoordinatedFileIO.writeData(pngData, to: assetURL)
            }

            let boardDocumentURL = boardDirectoryURL.appendingPathComponent(boardDocumentFilename)
            let encodedDocument = try makeDocumentData(for: document)
            try CoordinatedFileIO.writeData(encodedDocument, to: boardDocumentURL)
        }
    }

    static func loadOrCreateInitialBoard(
        userDefaults: UserDefaults = .standard
    ) throws -> BoardRuntimeState {
        let existingBoards = try listBoards(userDefaults: userDefaults)
        if let firstBoard = existingBoards.first {
            return try loadBoard(id: firstBoard.boardID, userDefaults: userDefaults)
        }

        let runtimeState = BoardRuntimeState.makeEmpty()
        try saveBoard(runtimeState, userDefaults: userDefaults)
        return runtimeState
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: restorePersistedBoardIfPossible() / scheduleAutosave(reason:) / persistBoardNow(reason:createBoardIfNeeded:)
// 功能说明: 修改后进入画布会优先恢复已保存数据，后续交互通过自动保存写回 BoardStore。
private func restorePersistedBoardIfPossible() {
    do {
        applyBoardRuntimeState(try BoardStore.loadOrCreateInitialBoard())
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("[BoardStore][iOS] Failed to restore board: \(error)")
    }
}

private func scheduleAutosave(reason: String) {
    guard currentBoardRuntimeState() != nil else {
        return
    }

    pendingAutosaveWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.performAutosave(reason: reason)
    }
    pendingAutosaveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
}

@discardableResult
private func persistBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false
) throws -> Bool {
    guard let runtimeState = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        return false
    }

    try BoardStore.saveBoard(runtimeState)
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus() / handleOpenCanvasButtonTap()
// 功能说明: 修改后 BoardList 会读取已存画板数量，并提供进入 canvas 的按钮。
private func refreshBookmarkStatus() {
    let bookmarkText = FolderBookmarkStore.statusText()
    do {
        let boardCount = try BoardStore.listBoards().count
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boardCount)"
    } catch FolderBookmarkStoreError.missingBookmarkData {
        bookmarkStatusLabel.text = bookmarkText
    } catch {
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
    }
}

@objc
private func handleOpenCanvasButtonTap() {
    onOpenCanvas?()
}
```

```swift
// 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
// 函数名: Debug / Release buildSettings
// 功能说明: 修改后把用户选择目录权限改为可读写，允许向选中文件夹写 board 数据。
ENABLE_USER_SELECTED_FILES = readwrite;
```

### 结果

- 现在 iOS 和 macOS 除了目录选择器本身外，实际的目录访问与画板文件读写都复用了同一套共享逻辑。
- 画板会被写到 `<selected-folder>/MyCanvasData/boards/<boardID>/board.json` 和 `assets/*.png`。
- `BoardList` 不再只是占位页，而是能显示已存画板数量并进入 `canvas`。
- 进入 `canvas` 时会优先恢复已存画板，没有现成画板时则自动创建一个空画板。

## 修改二：在 canvas 上添加悬浮保存按钮

### 修改前

- 统一存储实现完成后，`canvas` 已具备自动保存链路，但界面上没有显式的手动保存入口。
- 右下角只有导入图片按钮；用户无法主动确认“现在立刻保存一次”。
- 保存成功、失败、未选择目录这三种状态都没有直接的界面反馈。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupViewHierarchy() / setupConstraints() / setupImportButton()
// 功能说明: 修改前 iOS canvas 页面只有导入图片的悬浮按钮，没有 Save 按钮。
private let importButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: "plus")
    configuration.baseBackgroundColor = .systemBlue
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    return button
}()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(importButton)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick()
// 功能说明: 修改前 macOS canvas 也只有导入入口，没有手动保存处理函数。
@objc
private func handleImportButtonClick() {
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image]
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
}
```

### 修改后

- iOS / macOS 的 `canvas` 页面都新增了一个悬浮 `Save` 按钮，位置放在右下角导入按钮上方。
- 点击后会直接调用已有的 `persistBoardNow(reason:createBoardIfNeeded:)`。
- 保存成功时按钮临时变成 `Saved`；失败时变成 `Failed`；未选目录时变成 `No Folder` 并弹出提示。
- 自动保存逻辑保留不变，手动保存只是额外增加一个显式入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupViewHierarchy() / setupConstraints() / setupSaveButton()
// 功能说明: 修改后在 iOS canvas 右下角新增 Save 悬浮按钮，并放在导入按钮上方。
private let saveButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: "square.and.arrow.down")
    configuration.imagePlacement = .leading
    configuration.title = "Save"
    configuration.baseBackgroundColor = .systemGreen
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    return button
}()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
        importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    ])
}

private func setupSaveButton() {
    saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleSaveButtonTap() / showSaveButtonFeedback(...) / presentSaveError(message:)
// 功能说明: 修改后 iOS 支持手动保存，并针对成功、失败、未选目录给出即时反馈。
@objc
private func handleSaveButtonTap() {
    pendingAutosaveWorkItem?.cancel()

    do {
        guard try persistBoardNow(reason: "manual save", createBoardIfNeeded: true) else {
            throw FolderBookmarkStoreError.missingBookmarkData
        }

        showSaveButtonFeedback(
            title: "Saved",
            systemImageName: "checkmark",
            backgroundColor: .systemGreen
        )
    } catch FolderBookmarkStoreError.missingBookmarkData {
        showSaveButtonFeedback(
            title: "No Folder",
            systemImageName: "exclamationmark.triangle",
            backgroundColor: .systemOrange
        )
        presentSaveError(
            message: "Select a folder from the board list before saving."
        )
    } catch {
        showSaveButtonFeedback(
            title: "Failed",
            systemImageName: "xmark",
            backgroundColor: .systemRed
        )
        presentSaveError(message: error.localizedDescription)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupSaveButton() / handleSaveButtonClick() / applySaveButtonAppearance(...)
// 功能说明: 修改后 macOS 也提供同样的 Save 按钮和状态反馈，保持跨平台交互一致。
private func setupSaveButton() {
    saveButton.target = self
    saveButton.action = #selector(handleSaveButtonClick)
}

@objc
private func handleSaveButtonClick() {
    pendingAutosaveWorkItem?.cancel()

    do {
        guard try persistBoardNow(reason: "manual save", createBoardIfNeeded: true) else {
            throw FolderBookmarkStoreError.missingBookmarkData
        }

        showSaveButtonFeedback(
            title: "Saved",
            systemImageName: "checkmark",
            tintColor: .systemGreen
        )
    } catch FolderBookmarkStoreError.missingBookmarkData {
        showSaveButtonFeedback(
            title: "No Folder",
            systemImageName: "exclamationmark.triangle",
            tintColor: .systemOrange
        )
        presentSaveError(
            message: "Select a folder from the board list before saving."
        )
    } catch {
        showSaveButtonFeedback(
            title: "Failed",
            systemImageName: "xmark",
            tintColor: .systemRed
        )
        presentSaveError(message: error.localizedDescription)
    }
}
```

### 结果

- 用户现在不必依赖隐藏的自动保存时机，可以在 `canvas` 上手动点击 `Save` 立即落盘。
- iOS 和 macOS 的保存入口、布局位置、交互反馈基本一致。
- 当用户还没选存储目录时，界面会明确提示先回 `BoardList` 选择文件夹，避免“点了没反应”的体验。
