# 20260318_214236_macos_boardlist_collectionview_doubleclick_fix_record

## 记录范围

- 记录目标：修复 `macOS BoardList` 在阶段 3 落地后出现的编译错误。
- 错误信息：`Value of type 'NSCollectionView' has no member 'target'`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 本记录不包含：阶段 3 的其余 `collection/list/grid` 主体改造。
- 本记录不包含：git commit。

## 问题定位

- 这次错误不是业务逻辑问题，而是 `AppKit API` 使用方式错误。
- `NSCollectionView` 不是 `NSControl` 风格控件，不能像 `NSButton` 那样直接挂 `target` / `doubleAction`。
- 因此阶段 3 里把双击打开逻辑接到 `collectionView.target` / `collectionView.doubleAction` 上，会直接触发编译失败。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView
// 功能说明: 修改前错误地把 NSCollectionView 当作带 target/doubleAction 的控件使用，导致编译报错。
private lazy var collectionView: NSCollectionView = {
    let collectionView = NSCollectionView()
    collectionView.backgroundColors = [.clear]
    collectionView.collectionViewLayout = collectionViewLayout
    collectionView.delegate = self
    collectionView.dataSource = self
    collectionView.isSelectable = true
    collectionView.autoresizingMask = [.width]
    collectionView.register(
        macOSBoardCollectionItem.self,
        forItemWithIdentifier: macOSBoardCollectionItem.reuseIdentifier
    )
    collectionView.target = self
    collectionView.doubleAction = #selector(handleCollectionViewDoubleClick)
    return collectionView
}()
```

## 修改前

- 双击打开的思路本身没有问题，但接线位置错了。
- controller 中也因此把双击处理函数设计成了不带参数的 selector 形式，和后续手势驱动模型不匹配。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.handleCollectionViewDoubleClick()
// 功能说明: 修改前双击处理函数依赖 doubleAction 触发，没有点击位置上下文，也无法主动校正选中项。
@objc
private func handleCollectionViewDoubleClick() {
    guard !availableBoards.isEmpty else {
        return
    }

    openSelectedBoardIfNeeded()
}
```

## 修改后

- 改为给 `NSCollectionView` 添加 `NSClickGestureRecognizer`。
- 双击时通过 `gestureRecognizer.location(in:)` 获取点击位置。
- 再通过 `collectionView.indexPathForItem(at:)` 解析被双击的 cell。
- 先同步 `selectedBoardID` 和 collection 选中态，再调用 `openSelectedBoardIfNeeded()`。
- 这样修复后既消除了编译错误，也让“双击打开的是当前被双击的 board”这件事更明确。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView
// 功能说明: 修改后通过 NSClickGestureRecognizer 处理双击，而不是错误使用 NSCollectionView 的 target/doubleAction。
private lazy var collectionView: NSCollectionView = {
    let collectionView = NSCollectionView()
    collectionView.backgroundColors = [.clear]
    collectionView.collectionViewLayout = collectionViewLayout
    collectionView.delegate = self
    collectionView.dataSource = self
    collectionView.isSelectable = true
    collectionView.autoresizingMask = [.width]
    collectionView.register(
        macOSBoardCollectionItem.self,
        forItemWithIdentifier: macOSBoardCollectionItem.reuseIdentifier
    )

    let doubleClickGestureRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(handleCollectionViewDoubleClick(_:))
    )
    doubleClickGestureRecognizer.numberOfClicksRequired = 2
    collectionView.addGestureRecognizer(doubleClickGestureRecognizer)
    return collectionView
}()
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.handleCollectionViewDoubleClick(_:)
// 功能说明: 修改后双击处理函数会先解析被点击的 item，再同步选中状态，最后打开该 board。
@objc
private func handleCollectionViewDoubleClick(_ gestureRecognizer: NSClickGestureRecognizer) {
    guard
        gestureRecognizer.state == .ended,
        !availableBoards.isEmpty
    else {
        return
    }

    let location = gestureRecognizer.location(in: collectionView)
    guard let indexPath = collectionView.indexPathForItem(at: location) else {
        return
    }

    selectedBoardID = availableBoards[indexPath.item].boardID
    collectionView.selectItems(
        at: Set([indexPath]),
        scrollPosition: []
    )
    openSelectedBoardIfNeeded()
}
```

## 结果

- `macOS BoardList` 的这处编译错误已消除。
- 双击打开行为从“依赖错误 API”修正为“基于手势 + 命中 item 定位”的 AppKit 合法实现。

## 验证情况

- 已检查 `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift` 的 IDE lints。
- 本轮结果：`No linter errors found`。
- 本记录未执行 git commit。
- 本记录未执行完整 Xcode build。
