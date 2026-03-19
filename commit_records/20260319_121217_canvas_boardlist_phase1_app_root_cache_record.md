# 20260319_121217_canvas_boardlist_phase1_app_root_cache_record

## 记录范围

- 记录目标：实施 `Canvas` 返回与列表缓存方案的阶段1，在 `AppRoot` 层缓存并复用 `BoardListViewController`。
- 本次目的 1：消除 `.boardList` 路由每次重新创建 controller 的行为。
- 本次目的 2：把 `BoardList` 的实例创建和回调注入收敛到单一路径，为后续返回按钮与 `prepareForDisplay()` 铺路。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 本记录不包含：`BoardList` 显示前刷新入口 `prepareForDisplay()`。
- 本记录不包含：`Canvas` 左上角悬浮返回按钮。
- 本记录不包含：git commit。

## 修改一：在 macOS AppRoot 中缓存并复用 BoardList controller

### 修改前

- `macOSAppRootViewController.makeViewController(for:)` 每次命中 `.boardList` 都会新建一个 `macOSBoardListViewController`。
- `onOpenBoard` 和 `onCreateBoard` 的回调绑定逻辑与 controller 创建逻辑混在同一个分支里。
- 这意味着后续即使从 `Canvas` 返回 `BoardList`，也只能拿到一个全新的列表页实例，无法保留实例级状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 macOS 每次进入 .boardList 都重新创建 BoardList controller，并在同一处重复注入打开/新建回调。
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

### 修改后

- `macOSAppRootViewController` 新增 `lazy var boardListViewController`，首次创建后持续由 `AppRoot` 持有。
- 新增 `configureBoardListViewController(_:)`，把回调注入从路由分支里拆出来，只绑定一次。
- `.boardList` 分支改为直接返回缓存实例，后续显示 `BoardList` 时复用同一个 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.boardListViewController / makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 修改后 macOS 在 AppRoot 层缓存 BoardList controller，并把路由回调绑定收敛到单独方法，避免每次进入 .boardList 都重新 new 实例。
private lazy var boardListViewController: macOSBoardListViewController = {
    let viewController = macOSBoardListViewController()
    configureBoardListViewController(viewController)
    return viewController
}()

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

private func configureBoardListViewController(
    _ viewController: macOSBoardListViewController
) {
    viewController.onOpenBoard = { [weak self] boardID in
        self?.display(.canvas(.existing(boardID: boardID)))
    }
    viewController.onCreateBoard = { [weak self] in
        self?.display(.canvas(.newBoard))
    }
}
```

## 修改二：在 iOS AppRoot 中同步缓存 BoardList controller

### 修改前

- `iOSAppRootViewController.makeViewController(for:)` 也和 macOS 一样，在 `.boardList` 分支内直接 new 一个 `iOSBoardListViewController`。
- 双端若不对齐，后续即使 `Canvas` 加上返回按钮，也会出现“平台一边保状态、一边每次重建”的结构分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 iOS 每次命中 .boardList 路由都会新建 BoardList controller，并在该分支内重复配置打开/新建回调。
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

### 修改后

- `iOSAppRootViewController` 同步新增 `lazy var boardListViewController`，由 `AppRoot` 长持有。
- 新增 `configureBoardListViewController(_:)`，把列表页回调注入提到独立方法。
- `.boardList` 分支改为直接返回缓存实例，让双端的根路由缓存策略保持一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.boardListViewController / makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 修改后 iOS 与 macOS 对齐，在 AppRoot 层缓存 BoardList controller，并复用同一个列表页实例承载后续返回路径。
private lazy var boardListViewController: iOSBoardListViewController = {
    let viewController = iOSBoardListViewController()
    configureBoardListViewController(viewController)
    return viewController
}()

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

private func configureBoardListViewController(
    _ viewController: iOSBoardListViewController
) {
    viewController.onOpenBoard = { [weak self] boardID in
        self?.display(.canvas(.existing(boardID: boardID)))
    }
    viewController.onCreateBoard = { [weak self] in
        self?.display(.canvas(.newBoard))
    }
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 已对照本次实际修改，确认阶段1只包含 `AppRoot` 层的缓存属性引入和列表页回调绑定收敛。
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译或运行时验证；因此当前验证范围以代码对照和 lint 为主。
