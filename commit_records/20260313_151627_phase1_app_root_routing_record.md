# 20260313_151627_phase1_app_root_routing_record

## 记录范围

- 记录内容：阶段 1 的根路由层改造。
- 目标：将启动链路从 `AppDelegate -> 直接进入画板控制器` 调整为 `AppDelegate -> AppRoot -> 目标场景`。
- 本次未包含：`CanvasCamera`、`CanvasRenderer`、图片显示层、自定义平移缩放、存储逻辑。

## 变更 1：iOS 启动入口从直接进入画板页，改为先进入 AppRoot

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift
// 函数: application(_:didFinishLaunchingWithOptions:)
// 功能说明: AppDelegate 直接把 iOSViewController 挂成根控制器，启动后没有统一的场景路由层。
let window = UIWindow(frame: UIScreen.main.bounds)
window.rootViewController = iOSViewController()
window.backgroundColor = .white
window.makeKeyAndVisible()
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift
// 函数: application(_:didFinishLaunchingWithOptions:)
// 功能说明: AppDelegate 继续只负责创建窗口，但根控制器改为 iOSAppRootViewController，由 AppRoot 负责场景分发。
let window = UIWindow(frame: UIScreen.main.bounds)
window.rootViewController = iOSAppRootViewController()
window.backgroundColor = .white
window.makeKeyAndVisible()
```

## 变更 2：macOS 启动入口从直接进入画板页，改为先进入 AppRoot

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数: applicationDidFinishLaunching(_:)
// 功能说明: AppDelegate 直接创建并挂载 macOSViewController，窗口启动后没有统一的场景路由层。
let viewController = macOSViewController()
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.contentViewController = viewController
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数: applicationDidFinishLaunching(_:)
// 功能说明: AppDelegate 继续只负责创建窗口，但内容控制器改为 macOSAppRootViewController，由 AppRoot 负责场景分发。
let viewController = macOSAppRootViewController()
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.contentViewController = viewController
```

## 变更 3：新增统一的启动目标枚举

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数: AppLaunchDestination
// 功能说明: 修改前文件不存在，应用内没有统一表达“启动后进入哪个场景”的共享类型。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数: AppLaunchDestination
// 功能说明: 定义应用启动后的平行目标场景，当前预留画板列表页和具体画板页两个入口。
enum AppLaunchDestination {
    case boardList
    case canvas
}
```

## 变更 4：新增启动协调器，统一决定默认进入哪个场景

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchCoordinator.swift
// 函数: initialDestination()
// 功能说明: 修改前文件不存在，启动后进入列表还是进入画板没有统一决策入口。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchCoordinator.swift
// 函数: initialDestination()
// 功能说明: 当前阶段先默认返回 .canvas，后续可以在这里接入“恢复上次打开画板”或“进入列表首页”的真实规则。
struct AppLaunchCoordinator {
    func initialDestination() -> AppLaunchDestination {
        .canvas
    }
}
```

## 变更 5：新增 iOS AppRoot，用于承接启动后的场景装配

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数: display(_:) / makeViewController(for:)
// 功能说明: 修改前文件不存在，iOS 端没有专门的根场景宿主来承接列表页和画板页的平行关系。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数: display(_:) / makeViewController(for:)
// 功能说明: iOS 根场景宿主接收启动目标，并在 BoardListPage 与 CanvasHostPage 之间切换当前子控制器。
func display(_ destination: AppLaunchDestination) {
    let viewController = makeViewController(for: destination)
    setCurrentViewController(viewController)
}

private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        return iOSBoardListViewController()
    case .canvas:
        return iOSViewController()
    }
}
```

## 变更 6：新增 macOS AppRoot，用于承接启动后的场景装配

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数: display(_:) / makeViewController(for:)
// 功能说明: 修改前文件不存在，macOS 端没有专门的根场景宿主来承接列表页和画板页的平行关系。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数: display(_:) / makeViewController(for:)
// 功能说明: macOS 根场景宿主接收启动目标，并在 BoardListPage 与 CanvasHostPage 之间切换当前子控制器。
func display(_ destination: AppLaunchDestination) {
    let viewController = makeViewController(for: destination)
    setCurrentViewController(viewController)
}

private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        return macOSBoardListViewController()
    case .canvas:
        return macOSViewController()
    }
}
```

## 变更 7：新增 iOS 画板列表占位页

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy()
// 功能说明: 修改前文件不存在，iOS 端没有独立的画板列表场景占位实现。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy()
// 功能说明: 新增 iOS 端列表占位页，用最小界面把“未来的 BoardListPage”作为真实场景保留下来。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
}
```

## 变更 8：新增 macOS 画板列表占位页

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy()
// 功能说明: 修改前文件不存在，macOS 端没有独立的画板列表场景占位实现。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy()
// 功能说明: 新增 macOS 端列表占位页，用最小界面把“未来的 BoardListPage”作为真实场景保留下来。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}

private func setupViewHierarchy() {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
}
```

## 当前阶段结果

- 当前根链路已经变成：
  - iOS：`iOSAppDelegate -> iOSAppRootViewController -> iOSViewController`
  - macOS：`macOSAppDelegate -> macOSAppRootViewController -> macOSViewController`
- `BoardListPage` 现在已经作为平行场景存在，但当前默认策略仍然是进入 `canvas`。
- `iOSViewController` 和 `macOSViewController` 本轮没有继续改造成真正的 `CanvasHostPage`，它们仍然保留现有的占位内容，留待下一阶段处理。
- 这次修改的重点只是把应用级场景层级搭正，而不是开始做图片显示链路。
