# 20260319_103748_boardlist_placeholder_phase5_copy_and_empty_state_record

## 记录范围

- 记录目标：落实 `BoardList` 占位项方案的阶段 5，把文案、空状态和“真实 board 数”判断统一收口。
- 本阶段目的 1：移除 `Open Board` 按钮后，`subtitle`、未选 folder 提示、storage error 提示不再各写各的。
- 本阶段目的 2：区分“真实 board 数为 0”和“可见 entry 里仍然有 placeholder”这两个不同概念，避免 selection 逻辑继续混用。
- 本阶段目的 3：让 header / subtitle / empty state 在未选 folder 场景下使用同一套文案。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListCopy.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：阶段 4 的 placeholder 交互与 preview 隔离。
- 本记录不包含：git commit。

## 修改一：把 BoardList 文案从双端 controller 的硬编码改为 shared copy

### 修改前

- macOS / iOS 的 `subtitleLabel` 都还在使用 `Select a storage folder, then open the canvas.`。
- 双端 empty state 仍各自硬编码：
- 未选 folder：`Select a storage folder to load boards.`
- storage error：`Storage unavailable: ...`
- 这会导致按钮移除后，页面文案仍残留“open”语义，而且 controller 和 header 之间也容易继续漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.subtitleLabel / updateCollectionVisibility()
// 功能说明: 修改前 macOS controller 直接在本地硬编码 subtitle 和 empty state 文案，无法和 iOS / header 保持统一。
private let subtitleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "Select a storage folder, then open the canvas.")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    return label
}()

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionScrollView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.stringValue = "Storage unavailable: \(storageErrorMessage)"
        return
    }

    emptyStateLabel.stringValue = "Select a storage folder to load boards."
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.subtitleLabel / updateCollectionVisibility()
// 功能说明: 修改前 iOS controller 也各自维护一套文案，双端和 header 的 copy 没有统一来源。
private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Select a storage folder, then open the canvas."
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
}()

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.text = "Storage unavailable: \(storageErrorMessage)"
        return
    }

    emptyStateLabel.text = "Select a storage folder to load boards."
}
```

### 修改后

- 新增 shared 文案源 `BoardListCopy`。
- `subtitle`、未选 folder 提示、storage error 提示统一从 shared copy 获取。
- 双端 controller 不再各自拼接页面语义，后续如果要继续调文案，只需要改 shared copy。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListCopy.swift
// 函数名/类型名: BoardListCopy
// 功能说明: 修改后 shared copy 统一承载 BoardList 的 subtitle、未选 folder 提示和 storage error 提示，避免文案继续散落在双端 controller 里。
import Foundation

enum BoardListCopy {
    static let subtitle = "Select a storage folder to browse or create boards."
    static let selectFolderMessage = "Select a storage folder to browse or create boards."

    static func storageUnavailableMessage(_ description: String) -> String {
        "Storage unavailable: \(description)"
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.subtitleLabel / updateCollectionVisibility()
// 功能说明: 修改后 macOS controller 改为从 shared copy 读取页面文案，不再保留本地硬编码版本。
private let subtitleLabel: NSTextField = {
    let label = NSTextField(labelWithString: BoardListCopy.subtitle)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    return label
}()

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionScrollView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.stringValue = BoardListCopy.storageUnavailableMessage(storageErrorMessage)
        return
    }

    emptyStateLabel.stringValue = BoardListCopy.selectFolderMessage
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.subtitleLabel / updateCollectionVisibility()
// 功能说明: 修改后 iOS controller 与 macOS 共用同一套 BoardListCopy，页面 copy 不再随平台分叉。
private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = BoardListCopy.subtitle
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
}()

private func updateCollectionVisibility() {
    let shouldShowCollection =
        hasSelectedFolder &&
        storageErrorMessage == nil
    collectionView.isHidden = !shouldShowCollection
    emptyStateLabel.isHidden = shouldShowCollection

    if let storageErrorMessage {
        emptyStateLabel.text = BoardListCopy.storageUnavailableMessage(storageErrorMessage)
        return
    }

    emptyStateLabel.text = BoardListCopy.selectFolderMessage
}
```

## 修改二：把 selection 逻辑从内联判断改成“真实 board 数”显式 helper

### 修改前

- 阶段 4 之后，`entries` 已经总是包含 placeholder。
- 但 selection 修复逻辑仍然在用：
- `availableBoards.isEmpty`
- `entries.first(where: { $0.isPlaceholder == false })`
- 这样的写法虽然能跑，但 controller 语义还是分散的，真实 board 数和可见 entry 数没有被正式区分开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.ensureValidSelection() / clearPlaceholderSelectionAfterAction()
// 功能说明: 修改前 macOS 仍然在多个位置内联判断 availableBoards.isEmpty 和 first(where:)，没有把“真实 board 是否存在”抽成显式语义。
private func ensureValidSelection() {
    guard !entries.isEmpty else {
        selectedEntryID = nil
        return
    }

    if let selectedEntryID,
       entries.contains(where: { $0.id == selectedEntryID }) {
        switch selectedEntryID {
        case .newBoard:
            if availableBoards.isEmpty {
                return
            }
        case .board:
            return
        }
    }

    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
}

private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
    syncCollectionSelection()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.ensureValidSelection() / clearPlaceholderSelectionAfterAction()
// 功能说明: 修改前 iOS 也在 controller 内部重复内联同一套判断，placeholder 引入后的 selection 边界仍不够稳定。
private func ensureValidSelection() {
    guard !entries.isEmpty else {
        selectedEntryID = nil
        return
    }

    if let selectedEntryID,
       entries.contains(where: { $0.id == selectedEntryID }) {
        switch selectedEntryID {
        case .newBoard:
            if availableBoards.isEmpty {
                return
            }
        case .board:
            return
        }
    }

    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
}

private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = entries.first(where: { $0.isPlaceholder == false })?.id
    syncCollectionSelection()
}
```

### 修改后

- 双端 controller 都新增：
- `hasRealBoards`
- `firstRealBoardEntryID`
- `ensureValidSelection()` 和 `clearPlaceholderSelectionAfterAction()` 统一改成依赖这两个 helper。
- 这样 controller 真正知道自己在判断“真实 board 是否存在”，而不是继续拿 `entries` 和 `availableBoards` 的局部条件拼语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.hasRealBoards / firstRealBoardEntryID / ensureValidSelection() / clearPlaceholderSelectionAfterAction()
// 功能说明: 修改后 macOS 把“真实 board 是否存在”和“首个真实 board 的 entryID”显式抽出，selection 修复逻辑不再混用 placeholder 与 board 的数量概念。
private var hasRealBoards: Bool {
    availableBoards.isEmpty == false
}

private var firstRealBoardEntryID: BoardListEntryID? {
    entries.first(where: { $0.isPlaceholder == false })?.id
}

private func ensureValidSelection() {
    guard !entries.isEmpty else {
        selectedEntryID = nil
        return
    }

    if let selectedEntryID,
       entries.contains(where: { $0.id == selectedEntryID }) {
        switch selectedEntryID {
        case .newBoard:
            if hasRealBoards == false {
                return
            }
        case .board:
            return
        }
    }

    selectedEntryID = firstRealBoardEntryID
}

private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = firstRealBoardEntryID
    syncCollectionSelection()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.hasRealBoards / firstRealBoardEntryID / ensureValidSelection() / clearPlaceholderSelectionAfterAction()
// 功能说明: 修改后 iOS 使用和 macOS 相同的 helper 语义，把“0 个真实 board，但仍有 placeholder entry”这一场景从 controller 逻辑层面分离出来。
private var hasRealBoards: Bool {
    availableBoards.isEmpty == false
}

private var firstRealBoardEntryID: BoardListEntryID? {
    entries.first(where: { $0.isPlaceholder == false })?.id
}

private func ensureValidSelection() {
    guard !entries.isEmpty else {
        selectedEntryID = nil
        return
    }

    if let selectedEntryID,
       entries.contains(where: { $0.id == selectedEntryID }) {
        switch selectedEntryID {
        case .newBoard:
            if hasRealBoards == false {
                return
            }
        case .board:
            return
        }
    }

    selectedEntryID = firstRealBoardEntryID
}

private func clearPlaceholderSelectionAfterAction() {
    selectedEntryID = firstRealBoardEntryID
    syncCollectionSelection()
}
```

## 修改三：同步 `BoardListHeaderState` 的未选 folder 文案，消除 header 与 subtitle 漂移

### 修改前

- `subtitle` 和 empty state 改完之后，shared 的 `BoardListHeaderStateBuilder` 里仍保留旧文案：
- `Select a storage folder to load boards.`
- 这会让“未选 folder”场景下，header detail 和页面主体文案再次分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift
// 函数名/类型名: BoardListHeaderStateBuilder.make(bookmarkStatus:boardCount:storageErrorDescription:)
// 功能说明: 修改前 missing bookmark 分支仍返回旧版的 load boards 文案，和新的 BoardList 页面语义不一致。
case .missing:
    return BoardListHeaderState(
        title: "No Folder Selected",
        detail: "Select a storage folder to load boards.",
        fullPath: nil,
        isError: false
    )
```

### 修改后

- `BoardListHeaderStateBuilder` 在 `.missing` 分支也改为复用 `BoardListCopy.selectFolderMessage`。
- 至此 header、subtitle、empty state 在“未选 folder”场景下使用同一套 browse/create 文案，不再互相打架。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift
// 函数名/类型名: BoardListHeaderStateBuilder.make(bookmarkStatus:boardCount:storageErrorDescription:)
// 功能说明: 修改后 missing bookmark 分支也复用 shared copy，让 header detail 与页面主体文案保持完全一致。
case .missing:
    return BoardListHeaderState(
        title: "No Folder Selected",
        detail: BoardListCopy.selectFolderMessage,
        fullPath: nil,
        isError: false
    )
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListCopy.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `ReadLints` 结果：无新增 lint 错误。
- 已搜索清理旧文案：
- `Select a storage folder, then open the canvas.`
- `Select a storage folder to load boards.`
- `No boards yet. Create one to get started.`
- 当前在代码搜索中均无残留。
- 本次未执行项目级编译；因此这里的验证范围以代码审查、diff 对照和 lint 为主。
