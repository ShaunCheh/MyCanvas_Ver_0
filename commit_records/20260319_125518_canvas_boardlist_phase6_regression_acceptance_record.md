# 20260319_125518_canvas_boardlist_phase6_regression_acceptance_record

## 记录范围

- 记录目标：为 `Canvas` 返回与 `BoardList` 缓存方案的阶段6补齐回归验证与验收记录。
- 本次实际产物：新增本 markdown 记录文件。
- 本次实际执行：双端构建验证、工作区清洁检查、关键验收点代码对照。
- 本次未执行：git commit。
- 本次未新增：任何 `.swift` 源码修改。

## 修改前

- 阶段1到阶段5的实现已经落地，但阶段6“回归验证与验收清单”还没有形成独立记录。
- 仓库里还没有一份专门说明本轮双端构建、lint 结论、工作区状态、以及验收点与当前实现之间映射关系的阶段6文档。
- 因此在“功能已做完”和“功能已完成验收归档”之间，还缺最后一份收口记录。

## 修改后

- 新增文件：`commit_records/20260319_125518_canvas_boardlist_phase6_regression_acceptance_record.md`
- 已完成 `macOS Debug` 与 `iOS Simulator Debug` 的 `xcodebuild` 构建验证，结果均为 `BUILD SUCCEEDED`。
- 已确认在新增本记录文件前，`git status --short` 为空，工作区未被本次构建污染。
- 已复核阶段6关心的关键链路：
- `AppRoot` 复用缓存的 `BoardListViewController`
- `Canvas` 返回路由回到 `display(.boardList)`
- `prepareForDisplay()` 在显示前刷新数据但不重置实例态
- `ensureValidSelection()` 对失效选中做兜底修正
- `revisionToken` 参与缩略图缓存 key，确保 board 更新后切到新缓存槽位
- 本阶段没有新增源码改动，因此本记录中的代码片段均为“验收时核对的现状实现”，不是新的代码 diff。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: 阶段6回归验证命令
# 功能说明: 本阶段通过双端 xcodebuild 和工作区状态检查，补齐回归验证与验收证据。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath ".build/macos" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ".build/ios-sim" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO

git status --short
```

## 核验一：返回列表时复用同一个 BoardList controller，而不是重新 new

### 验收结论

- `AppRoot` 在双端都持有 `lazy var boardListViewController`。
- 再次进入 `.boardList` 时，直接返回缓存实例，而不是重新创建新的列表 controller。
- `Canvas` 返回按钮最终走的是 `onBackToBoardList -> display(.boardList)`，因此这条返回链会命中缓存对象。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.boardListViewController / makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 阶段6核验时确认 macOS 仍然复用同一个 BoardList controller，并把 Canvas 返回路由接回 display(.boardList)。
private lazy var boardListViewController: macOSBoardListViewController = {
    let viewController = macOSBoardListViewController()
    configureBoardListViewController(viewController)
    return viewController
}()

private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        viewController.onBackToBoardList = { [weak self] in
            self?.display(.boardList)
        }
        return viewController
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.boardListViewController / makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 阶段6核验时确认 iOS 与 macOS 对齐，也是在 AppRoot 层复用缓存列表页，并将 Canvas 返回出口接回 display(.boardList)。
private lazy var boardListViewController: iOSBoardListViewController = {
    let viewController = iOSBoardListViewController()
    configureBoardListViewController(viewController)
    return viewController
}()

private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        viewController.onBackToBoardList = { [weak self] in
            self?.display(.boardList)
        }
        return viewController
    }
}
```

## 核验二：返回列表时刷新数据，但不重置 displayMode 等实例态

### 验收结论

- 双端 `prepareForDisplay()` 都只调用 `refreshBookmarkStatus()`。
- `displayMode` 仍是 controller 实例属性，没有在显示前刷新阶段被重置。
- 这意味着返回列表时可以刷新 board 数据、header、empty/error 状态，同时保留实例级展示模式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.prepareForDisplay() / refreshBookmarkStatus()
// 功能说明: 阶段6核验时确认 macOS 显示前刷新只刷新数据链路，不会重置 displayMode 或重新 new 预览提供器。
private var displayMode: BoardListDisplayMode = .grid {
    didSet {
        guard oldValue != displayMode else {
            return
        }

        updateCollectionLayout()
        collectionView.reloadData()
        syncCollectionSelection()
    }
}

func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.prepareForDisplay() / refreshBookmarkStatus()
// 功能说明: 阶段6核验时确认 iOS 的显示前刷新策略与 macOS 一致，只刷新数据与 UI，不清空实例级 displayMode。
private var displayMode: BoardListDisplayMode = .grid {
    didSet {
        guard oldValue != displayMode else {
            return
        }

        updateCollectionLayout()
        collectionView.reloadData()
        syncCollectionSelection()
    }
}

func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}
```

## 核验三：真实 board 选中失效时会自动修正

### 验收结论

- 双端 `refreshBookmarkStatus()` 都会在拿到最新 catalog 后调用 `ensureValidSelection()`。
- 如果之前选中的 board 还存在，则保留选中。
- 如果之前选中已经失效，或当前只剩 placeholder，则会切回第一个有效真实 board。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.ensureValidSelection()
// 功能说明: 阶段6核验时确认 macOS 会在返回列表刷新后自动修正失效选中，避免删除 board 后仍保留悬空 selectedEntryID。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.ensureValidSelection()
// 功能说明: 阶段6核验时确认 iOS 与 macOS 对齐，也会在 catalog 刷新后把失效选中修正为第一个有效真实 board。
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
```

## 核验四：返回后缩略图优先复用内存缓存，revision 变化仍会生效

### 验收结论

- `BoardCatalogItem.revisionToken` 由 `boardID + updatedAt` 组成。
- `BoardThumbnailCacheKey` 把 `revisionToken` 纳入 key，因此 board 更新后会自动切到新的缓存 key。
- `BoardListViewController` 持有的是实例级 `BoardPreviewProvider`，当 controller 被复用时，其内存缓存也会随之保留。
- collection item / collection view cell 在回调时还会校验 `representedRevisionToken == item.revisionToken`，避免旧异步回调把过期图片刷回当前 cell。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem.revisionToken
// 功能说明: 阶段6核验时确认 revisionToken 与 boardID、updatedAt 绑定，为缩略图缓存失效提供版本依据。
var revisionToken: String {
    "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift
// 函数名/类型名: BoardThumbnailCacheKey.init(item:targetPixelSize:) / cacheKey
// 功能说明: 阶段6核验时确认缩略图缓存 key 包含 revisionToken，board 更新后不会继续复用旧版本缓存图。
init?(
    item: BoardCatalogItem,
    targetPixelSize: CGSize
) {
    let normalizedPixelSize = targetPixelSize.normalizedBoardThumbnailPixelSize
    guard normalizedPixelSize.width > 0, normalizedPixelSize.height > 0 else {
        return nil
    }

    boardID = item.boardID
    revisionToken = item.revisionToken
    pixelWidth = Int(normalizedPixelSize.width)
    pixelHeight = Int(normalizedPixelSize.height)
}

var cacheKey: NSString {
    "\(boardID.uuidString)-\(revisionToken)-\(pixelWidth)x\(pixelHeight)" as NSString
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:previewContent:displayMode:) / requestThumbnail(using:for:displayMode:)
// 功能说明: 阶段6核验时确认 macOS cell 会保存 representedRevisionToken，并在异步缩略图回调时校验版本，避免旧图回刷。
func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    view.layoutSubtreeIfNeeded()
}

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.previewView.apply(content: previewContent)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.configure(with:previewContent:displayMode:) / requestThumbnail(using:for:displayMode:)
// 功能说明: 阶段6核验时确认 iOS 与 macOS 对齐，也会在异步缩略图回调时比对 representedRevisionToken，避免旧缩略图回刷。
func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.text = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    contentView.layoutIfNeeded()
}

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.previewView.apply(content: previewContent)
    }
}
```

## 验证结果

- 本阶段无新增源码修改，只有验证行为与记录文件新增。
- `ReadLints` 检查的相关文件范围包括：
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- lint 结果：无新增错误。
- `xcodebuild` 结果：
- `macOS Debug`：`BUILD SUCCEEDED`
- `iOS Simulator Debug`：`BUILD SUCCEEDED`
- 工作区状态：
- 在新增本记录文件前：`git status --short` 为空。
- 新增本记录文件后：当前工作区只多出本文件本身。
- 阶段6仍然保留一项人工交互确认建议：实际手点验证“返回列表后可见位置是否完全不跳”。从当前代码看，没有显式重置滚动位置的逻辑；但这项结论最终仍以真实 UI 交互为准。

## 收口说明

- 到本记录为止，`Canvas` 左上角返回按钮与 `BoardList` 缓存复用方案的阶段1到阶段6，已经全部具备独立记录文件。
- 本次记录只负责“验收归档”，不包含新的实现提交。
