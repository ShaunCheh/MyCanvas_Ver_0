# 20260319_214601_macos_boardlist_selection_delay_root_cause_fix_record

## 记录范围

- 记录目标：修复 `macOS BoardList` 单击已有画板后，蓝色高亮延迟约 `0.5s` 才出现的问题。
- 本次目的 1：补充 `BoardList` 点击与选择链路日志，确认延迟发生在状态渲染之前还是事件分发之前。
- 本次目的 2：从根因上修复 `NSClickGestureRecognizer` 对单击选中链路的阻塞。
- 本次目的 3：补齐取消选中后的内部状态收口，避免 `selectedEntryID` 与 UI 选中态脱节。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 本记录不包含：`BoardPreviewProvider` 的缩略图权限错误修复。
- 本记录不包含：git commit。

## 问题定位

- 现象不是 `Grid` 或 `List` 某一套布局独有的问题，而是 `macOS BoardList` 共用的 `NSCollectionView` 选择链路被延迟。
- 诊断日志显示，修改前多次点击都出现了稳定的固定等待窗口：
- `leftMouseUp -> shouldSelectItems`
- `leftMouseUp -> itemIsSelectedChanged`
- 这两段延迟都在约 `500ms` 左右。
- 这说明慢点不在 `selectedEntryID` 写入，也不在 `macOSBoardCollectionItem.updateSelectionAppearance()` 渲染，而是在更前面的鼠标事件投递阶段。
- 根因是：`collectionView` 上挂载的双击 `NSClickGestureRecognizer` 在默认配置下延迟了主鼠标事件，单击选中必须等待双击判定窗口结束后才会进入 `selection pipeline`。
- 同时还发现一个次级问题：当 collection 取消选中后，UI 可以先变成“无选中项”，但内部 `selectedEntryID` 仍可能保留旧值；后续若触发 `reloadBoardList()`，旧选中项有机会再次被同步回去。

## 修改一：补充点击与选中链路日志

### 修改前

- controller 初始化阶段没有注入左键事件日志，无法确认 `mouseDown/mouseUp` 与 `didSelectItemsAt` 之间到底是谁在拖延。
- item 侧只在 `isSelected` 变化时更新外观，没有记录 `highlightState`，因此无法分辨“高亮预态已经来了”还是“选中态根本还没开始”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.viewDidLoad()
// 功能说明: 修改前 controller 只做视图搭建与数据刷新，没有接入左键点击和选择链路日志。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    refreshBookmarkStatus()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.isSelected
// 功能说明: 修改前 item 只在最终选中态变化时刷新外观，无法观察 highlightState 与点击时序。
override var isSelected: Bool {
    didSet {
        updateSelectionAppearance()
    }
}
```

### 修改后

- controller 通过本地事件 monitor 记录 `leftMouseDown` / `leftMouseUp`，并把 `clickCount`、命中的 `indexPath`、命中的 `entry` 一并打到 `SelectionTrace`。
- item 侧补充 `highlightState` 与 `isSelected` 的日志，把 AppKit 的“高亮预态”、“取消高亮”、“最终选中态”全部串起来。
- 这一步不改变交互行为，只增加观测点，用于区分“事件没进来”和“状态已变化但视觉更新晚到”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.viewDidLoad() / setupMouseEventLogging() / logLeftMouseEventTrace(_:)
// 功能说明: 修改后在 BoardList 生命周期中注册 leftMouse 事件监视，并输出命中的 item、点击次数与坐标，定位延迟发生在 selection pipeline 之前。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    setupMouseEventLogging()
    refreshBookmarkStatus()
}

private func setupMouseEventLogging() {
    guard leftMouseEventMonitor == nil else {
        return
    }

    leftMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .leftMouseUp]
    ) { [weak self] event in
        self?.logLeftMouseEventTrace(event)
        return event
    }
}

private func logLeftMouseEventTrace(_ event: NSEvent) {
    guard
        event.window === view.window,
        view.isHiddenOrHasHiddenAncestor == false,
        collectionView.window != nil
    else {
        return
    }

    let locationInCollectionView = collectionView.convert(
        event.locationInWindow,
        from: nil
    )
    guard collectionView.bounds.contains(locationInCollectionView) else {
        return
    }

    let indexPath = collectionView.indexPathForItem(at: locationInCollectionView)
    let entry = indexPath.flatMap(entry(at:))
    let phase: String
    switch event.type {
    case .leftMouseDown:
        phase = "leftMouseDown"
    case .leftMouseUp:
        phase = "leftMouseUp"
    default:
        phase = "leftMouseEvent"
    }

    logSelectionTrace(
        phase,
        extra:
            "clickCount=\(event.clickCount) " +
            "location=\(describeSelectionTracePoint(locationInCollectionView)) " +
            "hitIndexPath=\(indexPath.map(describeSelectionTraceIndexPath) ?? "nil") " +
            "hitEntry=\(describeSelectionTraceEntry(entry))"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.isSelected / macOSBoardCollectionItem.highlightState
// 功能说明: 修改后 item 同时记录 highlightState 和最终 isSelected，帮助确认蓝色高亮延迟不是渲染层慢，而是事件进入选择链路本身变晚。
override var isSelected: Bool {
    didSet {
        logSelectionTrace(
            "itemIsSelectedChanged",
            extra: "oldValue=\(oldValue) newValue=\(isSelected)"
        )
        updateSelectionAppearance()
    }
}

override var highlightState: NSCollectionViewItem.HighlightState {
    didSet {
        logSelectionTrace(
            "itemHighlightStateChanged",
            extra:
                "oldValue=\(describeSelectionTraceHighlightState(oldValue)) " +
                "newValue=\(describeSelectionTraceHighlightState(highlightState))"
        )
    }
}
```

## 修改二：从根因上修复双击手势导致的单击选中延迟

### 修改前

- `BoardList` 为了支持“双击打开已有 board”，在整个 `collectionView` 上挂了 `numberOfClicksRequired = 2` 的 `NSClickGestureRecognizer`。
- 但这里没有关闭主鼠标事件延迟，因此单击选中会被迫等待双击识别窗口结束后，才继续往 `shouldSelectItems` / `didSelectItemsAt` 传播。
- 这就是日志里稳定约 `500ms` 的固定等待窗口来源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView
// 功能说明: 修改前 collectionView 上的双击手势没有关闭主鼠标事件延迟，单击选中会被双击判定窗口拖慢。
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

### 修改后

- 双击打开能力保留不变。
- 但明确把 `delaysPrimaryMouseButtonEvents` 设为 `false`，让单击选中事件不再被双击识别器阻塞。
- 这样 `leftMouseUp` 之后就能立即进入 `shouldSelectItems`、`didSelectItemsAt` 与 `itemIsSelectedChanged`，不再出现之前那种稳定约 `500ms` 的卡顿。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView
// 功能说明: 修改后保留双击打开 board 的能力，但关闭主鼠标事件延迟，让单击选中链路立即继续向下游分发。
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
    // Keep single-click selection responsive while still recognizing double-click open.
    doubleClickGestureRecognizer.delaysPrimaryMouseButtonEvents = false
    collectionView.addGestureRecognizer(doubleClickGestureRecognizer)
    return collectionView
}()
```

## 修改三：取消选中后同步清理 `selectedEntryID`

### 修改前

- controller 只在 `didSelectItemsAt` 里把 `selectedEntryID` 写成当前选中的 board。
- 当用户点击其他地方触发取消选中时，UI 会先变成空选中，但内部 `selectedEntryID` 仍可能保留旧值。
- 这会让后续某些同步路径在重新加载 collection 时，把旧 board 再次同步回选中态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:didSelectItemsAt:)
// 功能说明: 修改前 controller 只在选中路径写入 selectedEntryID，没有在取消选中后回收内部状态。
func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
        clearPlaceholderSelectionAfterAction()
    }
}
```

### 修改后

- 保留原有 `didSelectItemsAt` 逻辑。
- 新增 `didDeselectItemsAt`，当这次取消选中不是程序主动同步造成，且 collection 当前已经没有任何选中项时，显式把 `selectedEntryID` 置空。
- 这样 UI 选中态和内部状态会在“空选中”场景下一起归零。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:didSelectItemsAt:) / collectionView(_:didDeselectItemsAt:)
// 功能说明: 修改后选中路径继续写入 selectedEntryID，取消选中路径在空选中时同步清空内部状态，避免 reload 时旧选中项回流。
func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
) {
    guard
        isSyncingSelection == false,
        let indexPath = indexPaths.first,
        let entry = entry(at: indexPath)
    else {
        return
    }

    logSelectionTrace(
        "didSelectItems",
        extra:
            "syncing=\(isSyncingSelection) " +
            describeSelectionTraceItems(at: indexPaths)
    )
    selectedEntryID = entry.id
    if entry.isPlaceholder {
        performPrimaryAction(for: entry)
        clearPlaceholderSelectionAfterAction()
    }
}

func collectionView(
    _ collectionView: NSCollectionView,
    didDeselectItemsAt indexPaths: Set<IndexPath>
) {
    let shouldClearSelectedEntryID =
        isSyncingSelection == false &&
        collectionView.selectionIndexPaths.isEmpty
    if shouldClearSelectedEntryID {
        selectedEntryID = nil
    }
    logSelectionTrace(
        "didDeselectItems",
        extra:
            "syncing=\(isSyncingSelection) " +
            "clearedSelectedEntryID=\(shouldClearSelectedEntryID) " +
            describeSelectionTraceItems(at: indexPaths)
    )
}
```

## 验证结果

- 修改前的诊断日志显示，多次点击都出现了稳定的固定等待窗口：
- `leftMouseUp -> shouldSelectItems` 约 `500ms`
- `leftMouseUp -> itemIsSelectedChanged` 约 `500ms`
- 修改后的验证日志显示，固定等待窗口已经消失：
- `2079801.482 -> 2079801.483`
- `2079802.877 -> 2079802.878`
- `2079802.877 -> 2079802.879`
- 也就是说，单击选中链路已经从之前的约 `500ms` 延迟，恢复到约 `1ms` 量级。
- 同一轮验证中还能看到 `didDeselectItems` 输出 `clearedSelectedEntryID=true`，说明空选中时的内部状态收口也已生效。
- 本轮验证的日志证据来自 `Grid` 视图；`List` 视图与 `Grid` 共用同一套 `NSCollectionView` 手势与选中链路，因此修复点位于两者共用层。
- 已检查相关文件的 `ReadLints` 结果，本次未发现新增错误。
- 本记录未执行完整 Xcode build。
- 本记录未执行 git commit。
