# 20260319_121646_canvas_boardlist_phase2_prepare_for_display_record

## 记录范围

- 记录目标：实施 `Canvas` 返回与列表缓存方案的阶段2，为复用的 `BoardListViewController` 增加显示前刷新入口。
- 本次目的 1：避免 `AppRoot` 复用同一个 `BoardList` 实例后仍保留过期的 board 列表快照。
- 本次目的 2：让 `AppRoot` 在再次显示 `.boardList` 时显式触发刷新，而不是依赖 `viewDidLoad()` 的一次性初始化。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 本记录不包含：`Canvas` 到 `BoardList` 的返回回调。
- 本记录不包含：左上角悬浮返回按钮。
- 本记录不包含：git commit。

## 修改一：给双端 BoardList 增加可重入的 prepareForDisplay()

### 修改前

- 双端 `BoardListViewController` 只有首次 `viewDidLoad()` 时才会调用 `refreshBookmarkStatus()`。
- 如果 controller 被 `AppRoot` 缓存复用，再次显示列表页时不会自动重新读 bookmark、catalog、header 和 selection 有效性。
- 这会让“缓存实例”只保住 UI 壳子，但列表数据仍可能停留在旧快照。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.viewDidLoad()
// 功能说明: 修改前 macOS 只在首次加载时刷新一次 BoardList 数据，后续复用实例重新显示时没有显式刷新入口。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    refreshBookmarkStatus()
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.viewDidLoad()
// 功能说明: 修改前 iOS 与 macOS 对称，同样把列表数据刷新绑定在 viewDidLoad 的一次性初始化路径上。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupActions()
    refreshBookmarkStatus()
}
```

### 修改后

- 双端 `BoardListViewController` 都新增了 `prepareForDisplay()`。
- 该方法先检查 `isViewLoaded`，避免在视图尚未创建前提前触发 UI 访问。
- 当实例已经加载过视图时，重新走 `refreshBookmarkStatus()` 链路，刷新：
- 当前 bookmark 状态
- `availableBoards`
- header / empty / error UI
- `ensureValidSelection()` 相关的选中有效性

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.prepareForDisplay()
// 功能说明: 修改后 macOS 在 BoardList 再次显示前提供可重入刷新入口，只在视图已加载时重新同步 bookmark 和列表快照。
func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.prepareForDisplay()
// 功能说明: 修改后 iOS 与 macOS 对齐，在复用列表页实例时显式刷新 catalog 与 UI 状态，而不重置实例级展示模式。
func prepareForDisplay() {
    guard isViewLoaded else {
        return
    }

    refreshBookmarkStatus()
}
```

## 修改二：让 AppRoot 在返回缓存的 BoardList 实例前主动调用 prepareForDisplay()

### 修改前

- 阶段1之后，`AppRoot` 已经会复用 `boardListViewController`，但 `.boardList` 分支只是直接返回这个缓存实例。
- 如果不在这个切换点补刷新，复用 controller 只能保住旧状态，却拿不到新的 `BoardCatalogItem`、bookmark header 或 storage error 状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 macOS 在 .boardList 路由命中时直接返回缓存实例，还没有在切换前主动刷新 BoardList 数据。
private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 iOS 同样只返回缓存的 BoardList controller，没有在重新显示列表页前显式同步最新数据。
private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}
```

### 修改后

- 双端 `AppRoot` 的 `.boardList` 分支都在返回缓存实例前先调用 `boardListViewController.prepareForDisplay()`。
- 这样复用 controller 的同时，最新的列表数据会在切换回列表页之前刷新完成。
- `displayMode`、已存在的 controller 实例、以及 `BoardPreviewProvider` 的实例级缓存仍然保留，因为这里没有重建 controller，也没有重置这些状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 macOS 在返回缓存的 BoardList controller 前先触发 prepareForDisplay，形成“实例复用 + 显示前刷新”的闭环。
private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 iOS 与 macOS 对齐，在复用 BoardList controller 的同时显式刷新最新 bookmark 和 board catalog。
private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        return viewController
    }
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 已对照本次修改，确认阶段2只包含：
- `BoardList.prepareForDisplay()` 的引入
- `AppRoot` 对 `prepareForDisplay()` 的接入
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译或运行时验证；因此当前验证范围以代码对照和 lint 为主。
