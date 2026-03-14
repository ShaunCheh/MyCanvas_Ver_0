# 20260314_230545_boardlist_bookmark_path_and_ios_folderpicker_fix_record

## 记录范围

- 记录内容：
  1. App 启动后，如果 `UserDefaults` 里已经有文件夹 bookmark，则在 `BoardList` 主界面显示具体文件夹路径。
  2. 修复 iOS 上通过 `UIDocumentPicker` 选择文件夹后，创建 bookmark 失败的问题。
- 重点问题：iOS 之前会打印如下错误，导致 bookmark 无法写入 `UserDefaults`。

```text
[FolderBookmark][iOS] Failed to create bookmark: Error Domain=NSCocoaErrorDomain Code=260 "The file couldn’t be opened because it doesn’t exist."
```

- 涉及文件：
  - `MyCanvas_Ver_0/App/FolderBookmarkStore.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/FolderPicker.swift`
- 本记录不包含：原始 gif diff、额外的提交流程。

## 修改一：启动时在主界面显示已保存的文件夹路径

### 修改前

- `FolderBookmarkStore` 只能判断是否存在 bookmark 数据，不能把 bookmark 解析回具体路径。
- `BoardList` 页面只会显示“有无 bookmark”，不会显示实际文件夹路径。

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数名: hasStoredBookmarkData(userDefaults:) / logStoredBookmarkPresence(userDefaults:)
// 功能说明: 修改前只负责判断 UserDefaults 里是否已有 bookmark 数据，不解析路径。
enum FolderBookmarkStore {
    private static let bookmarkDefaultsKey = "SelectedFolderBookmarkData"

    static func save(_ bookmarkData: Data, userDefaults: UserDefaults = .standard) {
        userDefaults.set(bookmarkData, forKey: bookmarkDefaultsKey)
    }

    static func storedBookmarkData(userDefaults: UserDefaults = .standard) -> Data? {
        userDefaults.data(forKey: bookmarkDefaultsKey)
    }

    static func hasStoredBookmarkData(userDefaults: UserDefaults = .standard) -> Bool {
        storedBookmarkData(userDefaults: userDefaults) != nil
    }

    static func logStoredBookmarkPresence(userDefaults: UserDefaults = .standard) {
        print("[FolderBookmark] UserDefaults has bookmark data: \(hasStoredBookmarkData(userDefaults: userDefaults))")
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus()
// 功能说明: 修改前 macOS 主界面只显示是否已保存 bookmark，不显示具体路径。
private func refreshBookmarkStatus() {
    bookmarkStatusLabel.stringValue = FolderBookmarkStore.hasStoredBookmarkData()
        ? "Bookmark data is stored in UserDefaults."
        : "No bookmark data stored in UserDefaults."
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus()
// 功能说明: 修改前 iOS 主界面只显示是否已保存 bookmark，不显示具体路径。
private func refreshBookmarkStatus() {
    bookmarkStatusLabel.text = FolderBookmarkStore.hasStoredBookmarkData()
        ? "Bookmark data is stored in UserDefaults."
        : "No bookmark data stored in UserDefaults."
}
```

### 修改后

- `FolderBookmarkStore` 新增 `storedFolderPath(userDefaults:)`，尝试把 `bookmarkData` 解析成 `URL.path`。
- 再新增 `statusText(userDefaults:)`，统一给 macOS / iOS 的 `BoardList` 生成显示文案。
- `BoardList` 进入页面时仍然调用 `refreshBookmarkStatus()`，但现在如果 bookmark 能解析成功，就会直接显示路径。

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数名: storedFolderPath(userDefaults:) / statusText(userDefaults:) / bookmarkResolutionOptions
// 功能说明: 修改后新增 bookmark 解析与状态文案拼装逻辑；macOS 解析时继续使用 security-scoped 选项。
enum FolderBookmarkStore {
    private static let bookmarkDefaultsKey = "SelectedFolderBookmarkData"

    static func storedFolderPath(userDefaults: UserDefaults = .standard) -> String? {
        guard let bookmarkData = storedBookmarkData(userDefaults: userDefaults) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                print("[FolderBookmark] Resolved bookmark is stale.")
            }
            return url.path
        } catch {
            print("[FolderBookmark] Failed to resolve bookmark path: \(error)")
            return nil
        }
    }

    static func statusText(userDefaults: UserDefaults = .standard) -> String {
        if let path = storedFolderPath(userDefaults: userDefaults) {
            return "Saved folder path:\n\(path)"
        }

        if hasStoredBookmarkData(userDefaults: userDefaults) {
            return "Bookmark data exists in UserDefaults, but the path could not be resolved."
        }

        return "No bookmark data stored in UserDefaults."
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus()
// 功能说明: 修改后 macOS 主界面直接复用共享状态文案；若已有 bookmark，会显示具体路径。
private func refreshBookmarkStatus() {
    bookmarkStatusLabel.stringValue = FolderBookmarkStore.statusText()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: refreshBookmarkStatus()
// 功能说明: 修改后 iOS 主界面直接复用共享状态文案；若已有 bookmark，会显示具体路径。
private func refreshBookmarkStatus() {
    bookmarkStatusLabel.text = FolderBookmarkStore.statusText()
}
```

### 结果

- App 启动进入 `BoardList` 时，如果之前已经把 bookmark 保存进 `UserDefaults`，页面会显示具体文件夹路径。
- 如果 bookmark 存在但解析失败，界面会明确提示“有 bookmark，但路径解析失败”，避免误以为没有保存。

## 修改二：修复 iOS 上选择文件夹后 bookmark 创建失败

### 问题现象

- macOS 上通过 `NSOpenPanel` 选择文件夹后，可以正常创建 bookmark 并保存。
- iOS 上通过 `UIDocumentPicker` 选择文件夹后，之前经常在生成 bookmark 时直接失败，并打印：

```text
[FolderBookmark][iOS] Failed to create bookmark: Error Domain=NSCocoaErrorDomain Code=260 "The file couldn’t be opened because it doesn’t exist."
```

### 根因分析

- `UIDocumentPicker` 在 iOS 上返回的目录 URL 往往来自 `Files` / `iCloud Drive` / 文件提供方，属于 security-scoped 访问模型。
- 修改前的实现是：拿到 `url` 后，立即直接调用 `url.bookmarkData(...)`。
- 这个时机下，URL 还没有先 `startAccessingSecurityScopedResource()`，也没有通过 `NSFileCoordinator` 协调访问。
- 对某些 provider 来说，这会导致 bookmark 生成阶段就被判定为目标不可直接访问，最终抛出 `NSCocoaErrorDomain Code=260`。

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/FolderPicker.swift
// 函数名: documentPicker(_:didPickDocumentsAt:)
// 功能说明: 修改前在拿到 UIDocumentPicker 返回的目录 URL 后，直接生成 bookmark，没有先开启 security scope，也没有做文件协调。
func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
) {
    let selectionHandler = selectionHandler
    self.selectionHandler = nil

    guard let url = urls.first else {
        return
    }

    do {
        let bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        selectionHandler?(.success(bookmarkData))
    } catch {
        selectionHandler?(.failure(error))
    }
}
```

### 修改后

- 新增 `makeBookmarkData(for:)`，把 iOS 生成 bookmark 的流程集中到一个函数里。
- 先 `startAccessingSecurityScopedResource()`，确保当前 app 拿到对所选目录的临时访问权限。
- 再使用 `NSFileCoordinator` 对该目录 URL 做一次受控读取。
- 最后在 `coordinatedURL` 上生成 bookmark，并在结束时调用 `stopAccessingSecurityScopedResource()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/FolderPicker.swift
// 函数名: documentPicker(_:didPickDocumentsAt:) / makeBookmarkData(for:)
// 功能说明: 修改后先开启 security-scoped 访问，再通过 NSFileCoordinator 协调读取，最后在协调后的 URL 上生成 bookmark。
func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
) {
    let selectionHandler = selectionHandler
    self.selectionHandler = nil

    guard let url = urls.first else {
        return
    }

    do {
        let bookmarkData = try makeBookmarkData(for: url)
        selectionHandler?(.success(bookmarkData))
    } catch {
        selectionHandler?(.failure(error))
    }
}

private func makeBookmarkData(for url: URL) throws -> Data {
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var coordinatedBookmarkData: Data?
    var bookmarkError: Error?
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator()

    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        do {
            coordinatedBookmarkData = try coordinatedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmarkError = error
        }
    }

    if let coordinationError {
        throw coordinationError
    }

    if let bookmarkError {
        throw bookmarkError
    }

    if let coordinatedBookmarkData {
        return coordinatedBookmarkData
    }

    throw CocoaError(.fileReadUnknown)
}
```

### 修复结果

- iOS 不再直接对 `UIDocumentPicker` 返回的目录 URL 做裸调用 `bookmarkData(...)`。
- 通过 security-scoped access + `NSFileCoordinator` 后，bookmark 生成流程更符合 iOS 文件提供方的访问模型。
- 这次修复的目标不是改变 UI，而是确保 iOS 上“选择文件夹 -> 生成 bookmark -> 存入 `UserDefaults` -> 启动时可显示路径”这条链路能正常工作。

## 当前链路总结

1. 用户在 `BoardList` 点击 `Select Folder`。
2. macOS 通过 `NSOpenPanel + .withSecurityScope` 创建 bookmark。
3. iOS 通过 `UIDocumentPicker` 选中文件夹后，先开启 security-scoped access，再协调读取并创建 bookmark。
4. `BookmarkData` 存入 `UserDefaults`。
5. App 启动时会在 console 打印 `UserDefaults` 中是否已有 bookmark。
6. `BoardList` 主界面会把已保存 bookmark 解析为具体路径并显示出来。
