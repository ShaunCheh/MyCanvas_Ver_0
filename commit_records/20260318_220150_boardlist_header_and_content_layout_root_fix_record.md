# 20260318_220150_boardlist_header_and_content_layout_root_fix_record

## 记录范围

- 记录目标 1：修复 `BoardList` 头部使用自由文本状态串，导致完整路径进入主布局流、头部高度失控的问题。
- 记录目标 2：修复 `emptyStateLabel` 虽然隐藏但仍通过约束链影响 header 垂直布局，导致缩略图区被整体挤到下方的问题。
- 涉及文件：`MyCanvas_Ver_0/App/FolderBookmarkStore.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：阶段 3 主体的 `collection/list/grid` 初次落地。
- 本记录不包含：git commit。

## 修改一：把 `FolderBookmarkStore.statusText()` 自由文本链路改为结构化状态 + 紧凑 header

### 修改前

- `FolderBookmarkStore` 直接返回 UI 文本 `statusText()`。
- 当 bookmark 可解析时，这段文本会直接带上完整路径，并且包含换行。
- 双端 `BoardList` controller 再把这段字符串和 `Boards available: N` 拼接到一个无限换行的 `bookmarkStatusLabel` 上。
- 结果是：存储层自由文本直接驱动 UI 布局，路径越长，头部越高。

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数名/类型名: FolderBookmarkStore.statusText(userDefaults:)
// 功能说明: 修改前 FolderBookmarkStore 直接向 UI 返回自由文本状态串，其中可解析状态会把完整路径塞进多行字符串。
import Foundation

enum FolderBookmarkStore {
    static func statusText(userDefaults: UserDefaults = .standard) -> String {
        if let path = storedFolderPath(userDefaults: userDefaults) {
            return "Saved folder path:\n\(path)"
        }

        if hasStoredBookmarkData(userDefaults: userDefaults) {
            return "Bookmark data exists in UserDefaults, but the path could not be resolved."
        }

        return "No bookmark data stored in UserDefaults."
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.bookmarkStatusLabel / refreshBookmarkStatus()
// 功能说明: 修改前 iOS BoardList 直接展示自由文本 bookmark 状态，并允许无限换行，导致完整路径进入主布局流。
private let bookmarkStatusLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
}()

private func refreshBookmarkStatus() {
    let bookmarkText = FolderBookmarkStore.statusText()
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        hasSelectedFolder = true
        ensureValidSelection()
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boards.count)"
        reloadBoardList()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        availableBoards = []
        selectedBoardID = nil
        hasSelectedFolder = false
        bookmarkStatusLabel.text = bookmarkText
        reloadBoardList()
    } catch {
        availableBoards = []
        selectedBoardID = nil
        hasSelectedFolder = false
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
        reloadBoardList()
    }
}
```

### 修改后

- `FolderBookmarkStore` 不再给 `BoardList` 返回自由文本，而是提供结构化 `BookmarkStatus`。
- 新增 `BoardListHeaderState` / `BoardListHeaderStateBuilder`，由 `BoardList` 自己决定如何把 bookmark 状态映射成紧凑头部文案。
- 双端 controller 改成两行头部：
- `bookmarkTitleLabel`
- `bookmarkDetailLabel`
- 完整路径不再参与主布局高度：
- `macOS` 放到 `toolTip`
- `iOS` 放到 `accessibilityHint`
- storage error 也被结构化进 header 状态，不再拼到大段多行字符串里。

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数名/类型名: FolderBookmarkStore.BookmarkStatus / FolderBookmarkStore.bookmarkStatus(userDefaults:)
// 功能说明: 修改后 FolderBookmarkStore 只负责提供结构化 bookmark 状态，不再直接给 UI 返回长文本。
import Foundation

enum FolderBookmarkStore {
    struct ResolvedFolderBookmark {
        let url: URL
        let isStale: Bool
    }

    enum BookmarkStatus {
        case missing
        case resolved(ResolvedFolderBookmark)
        case unresolved

        var hasSelectedFolder: Bool {
            if case .resolved = self {
                return true
            }

            return false
        }
    }

    static func bookmarkStatus(userDefaults: UserDefaults = .standard) -> BookmarkStatus {
        do {
            return .resolved(try resolveStoredFolderBookmark(userDefaults: userDefaults))
        } catch FolderBookmarkStoreError.missingBookmarkData {
            return .missing
        } catch {
            print("[FolderBookmark] Failed to resolve bookmark status: \(error)")
            return .unresolved
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift
// 函数名/类型名: BoardListHeaderState / BoardListHeaderStateBuilder.make(bookmarkStatus:boardCount:storageErrorDescription:)
// 功能说明: 修改后 shared header state 统一负责把 bookmark 状态、board 数量和 storage error 组装成可控的两行头部文案。
import Foundation

struct BoardListHeaderState {
    let title: String
    let detail: String
    let fullPath: String?
    let isError: Bool
}

enum BoardListHeaderStateBuilder {
    static func make(
        bookmarkStatus: FolderBookmarkStore.BookmarkStatus,
        boardCount: Int? = nil,
        storageErrorDescription: String? = nil
    ) -> BoardListHeaderState {
        switch bookmarkStatus {
        case .missing:
            return BoardListHeaderState(
                title: "No Folder Selected",
                detail: "Select a storage folder to load boards.",
                fullPath: nil,
                isError: false
            )

        case .unresolved:
            return BoardListHeaderState(
                title: "Folder Bookmark Unavailable",
                detail: storageErrorDescription
                    ?? "Bookmark exists, but the folder path could not be resolved.",
                fullPath: nil,
                isError: true
            )

        case let .resolved(resolvedBookmark):
            let folderPath = resolvedBookmark.url.path
            let folderName = resolvedBookmark.url.lastPathComponent.isEmpty
                ? folderPath
                : resolvedBookmark.url.lastPathComponent

            if let storageErrorDescription {
                return BoardListHeaderState(
                    title: "Folder: \(folderName)",
                    detail: "Storage error: \(storageErrorDescription)",
                    fullPath: folderPath,
                    isError: true
                )
            }

            var detailComponents: [String] = []
            if let boardCount {
                let boardText = boardCount == 1 ? "1 board" : "\(boardCount) boards"
                detailComponents.append(boardText)
            } else {
                detailComponents.append("Folder selected")
            }

            if resolvedBookmark.isStale {
                detailComponents.append("Bookmark stale")
            }

            return BoardListHeaderState(
                title: "Folder: \(folderName)",
                detail: detailComponents.joined(separator: " | "),
                fullPath: folderPath,
                isError: false
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.bookmarkTitleLabel / bookmarkDetailLabel / applyHeaderState(_:) / refreshBookmarkStatus()
// 功能说明: 修改后 macOS BoardList 用两行紧凑 header 展示目录摘要和数量，完整路径只挂在 tooltip 上，不再撑高主布局。
private let bookmarkTitleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingMiddle
    label.maximumNumberOfLines = 1
    return label
}()

private let bookmarkDetailLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    return label
}()

private func applyHeaderState(_ headerState: BoardListHeaderState) {
    bookmarkTitleLabel.stringValue = headerState.title
    bookmarkDetailLabel.stringValue = headerState.detail
    bookmarkTitleLabel.toolTip = headerState.fullPath
    bookmarkDetailLabel.toolTip = headerState.fullPath
    bookmarkDetailLabel.textColor = headerState.isError
        ? .systemRed
        : .secondaryLabelColor
}

private func refreshBookmarkStatus() {
    let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        hasSelectedFolder = true
        storageErrorMessage = nil
        ensureValidSelection()
        applyHeaderState(
            BoardListHeaderStateBuilder.make(
                bookmarkStatus: bookmarkStatus,
                boardCount: boards.count
            )
        )
        reloadBoardList()
    } catch {
        // ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.bookmarkTitleLabel / bookmarkDetailLabel / applyHeaderState(_:) / refreshBookmarkStatus()
// 功能说明: 修改后 iOS BoardList 同样改成两行紧凑 header，完整路径只保留在 accessibility hint，不再进入主布局高度。
private let bookmarkTitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .label
    label.textAlignment = .center
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingMiddle
    return label
}()

private let bookmarkDetailLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    return label
}()

private func applyHeaderState(_ headerState: BoardListHeaderState) {
    bookmarkTitleLabel.text = headerState.title
    bookmarkDetailLabel.text = headerState.detail
    bookmarkTitleLabel.accessibilityHint = headerState.fullPath
    bookmarkDetailLabel.accessibilityHint = headerState.fullPath
    bookmarkDetailLabel.textColor = headerState.isError
        ? .systemRed
        : .secondaryLabel
}

private func refreshBookmarkStatus() {
    let bookmarkStatus = FolderBookmarkStore.bookmarkStatus()
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        hasSelectedFolder = true
        storageErrorMessage = nil
        ensureValidSelection()
        applyHeaderState(
            BoardListHeaderStateBuilder.make(
                bookmarkStatus: bookmarkStatus,
                boardCount: boards.count
            )
        )
        reloadBoardList()
    } catch {
        // ...
    }
}
```

## 修改二：把 `emptyStateLabel` 从 header 约束链里隔离出来，避免隐藏视图继续把缩略图区往下拽

### 修改前

- 即便完成了修改一，controller 里仍然存在一条跨层约束链：
- `collectionView / collectionScrollView` 顶在 header 下面
- `emptyStateLabel` 同时既贴着 header 下方，又垂直居中于 collection
- 这意味着哪怕 `emptyStateLabel.isHidden = true`，它的约束仍然会参与求解，把 header 区整体往下拉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.setupViewHierarchy() / setupConstraints()
// 功能说明: 第二次修复前，collection 和 empty state 都直接挂在根 view 上，emptyStateLabel 的跨层约束会继续影响 header 布局。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground

    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
    actionStackView.addArrangedSubview(openCanvasButton)

    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(actionStackView)
    view.addSubview(bookmarkTitleLabel)
    view.addSubview(bookmarkDetailLabel)
    view.addSubview(collectionView)
    view.addSubview(emptyStateLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        bookmarkDetailLabel.topAnchor.constraint(equalTo: bookmarkTitleLabel.bottomAnchor, constant: 4),
        bookmarkDetailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        bookmarkDetailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        collectionView.topAnchor.constraint(equalTo: bookmarkDetailLabel.bottomAnchor, constant: 16),
        collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        emptyStateLabel.topAnchor.constraint(equalTo: bookmarkDetailLabel.bottomAnchor, constant: 32),
        emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
    ])
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.setupViewHierarchy() / setupConstraints()
// 功能说明: 第二次修复前，macOS 也让 emptyStateLabel 同时绑定 header 下边和 collection 中心，隐藏后仍会影响整体布局求解。
private func setupViewHierarchy() {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
    actionStackView.addArrangedSubview(openCanvasButton)

    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(actionStackView)
    view.addSubview(bookmarkStatusLabel)
    view.addSubview(collectionScrollView)
    view.addSubview(emptyStateLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        bookmarkStatusLabel.topAnchor.constraint(equalTo: actionStackView.bottomAnchor, constant: 12),
        bookmarkStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        bookmarkStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        collectionScrollView.topAnchor.constraint(equalTo: bookmarkStatusLabel.bottomAnchor, constant: 16),
        collectionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        collectionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        collectionScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        emptyStateLabel.topAnchor.constraint(equalTo: bookmarkStatusLabel.bottomAnchor, constant: 32),
        emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        emptyStateLabel.centerYAnchor.constraint(equalTo: collectionScrollView.centerYAnchor)
    ])
}
```

### 修改后

- 新增独立的 `contentContainerView`。
- `collectionView / collectionScrollView` 和 `emptyStateLabel` 都移动到这个内容容器内。
- header 区现在只负责：
- 标题
- 副标题
- 操作按钮
- 两行目录摘要
- `emptyStateLabel` 的居中约束现在只在内容区内部生效，不再反向影响 header 区高度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.contentContainerView / setupViewHierarchy() / setupConstraints()
// 功能说明: 第二次修复后，iOS 把 collection 和 empty state 包进独立内容容器，彻底切断 emptyStateLabel 对 header 的约束串扰。
private let contentContainerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground

    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
    actionStackView.addArrangedSubview(openCanvasButton)

    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(actionStackView)
    view.addSubview(bookmarkTitleLabel)
    view.addSubview(bookmarkDetailLabel)
    view.addSubview(contentContainerView)

    contentContainerView.addSubview(collectionView)
    contentContainerView.addSubview(emptyStateLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        bookmarkDetailLabel.topAnchor.constraint(equalTo: bookmarkTitleLabel.bottomAnchor, constant: 4),
        bookmarkDetailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        bookmarkDetailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        contentContainerView.topAnchor.constraint(equalTo: bookmarkDetailLabel.bottomAnchor, constant: 16),
        contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        collectionView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
        collectionView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
        collectionView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        emptyStateLabel.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 24),
        emptyStateLabel.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -24),
        emptyStateLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
        emptyStateLabel.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor)
    ])
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.contentContainerView / setupViewHierarchy() / setupConstraints()
// 功能说明: 第二次修复后，macOS 也把 collectionScrollView 和 emptyStateLabel 收进独立内容容器，避免隐藏 empty state 继续把头部往下拉。
private let contentContainerView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private func setupViewHierarchy() {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    actionStackView.addArrangedSubview(selectFolderButton)
    actionStackView.addArrangedSubview(displayModeControl)
    actionStackView.addArrangedSubview(openCanvasButton)

    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(actionStackView)
    view.addSubview(bookmarkTitleLabel)
    view.addSubview(bookmarkDetailLabel)
    view.addSubview(contentContainerView)

    contentContainerView.addSubview(collectionScrollView)
    contentContainerView.addSubview(emptyStateLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        bookmarkDetailLabel.topAnchor.constraint(equalTo: bookmarkTitleLabel.bottomAnchor, constant: 4),
        bookmarkDetailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        bookmarkDetailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        contentContainerView.topAnchor.constraint(equalTo: bookmarkDetailLabel.bottomAnchor, constant: 16),
        contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        collectionScrollView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
        collectionScrollView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
        collectionScrollView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
        collectionScrollView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        emptyStateLabel.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 24),
        emptyStateLabel.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -24),
        emptyStateLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
        emptyStateLabel.centerYAnchor.constraint(equalTo: contentContainerView.centerYAnchor)
    ])
}
```

## 验证情况

- 已检查以下文件的 IDE lints：
- `MyCanvas_Ver_0/App/FolderBookmarkStore.swift`
- `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本轮结果：`No linter errors found`。
- 本记录未执行 git commit。
- 本记录未执行完整 Xcode build。
