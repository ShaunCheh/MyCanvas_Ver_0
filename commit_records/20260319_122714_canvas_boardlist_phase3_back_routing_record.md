# 20260319_122714_canvas_boardlist_phase3_back_routing_record

## 记录范围

- 记录目标：实施 `Canvas` 返回与列表缓存方案的阶段3，为双端 `Canvas` controller 接入返回 `BoardList` 的路由回调。
- 本次目的 1：让 `Canvas` controller 持有一个纯路由回调出口，而不直接依赖 `AppRoot`。
- 本次目的 2：在 `AppRoot` 创建 `Canvas` 页面时，把该回调统一接回 `display(.boardList)`。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 本记录不包含：左上角悬浮返回按钮 UI。
- 本记录不包含：overlay 避让或 context menu 层级处理。
- 本记录不包含：git commit。

## 修改一：给双端 Canvas controller 增加 onBackToBoardList 回调出口

### 修改前

- 双端 `Canvas` controller 只有 `launchContext` 入口，没有任何“返回 `BoardList`”的路由回调属性。
- 这意味着即使后续加上左上角返回按钮，按钮也没有统一的路由出口可以调用。
- 如果直接让 `Canvas` 自己知道 `AppRoot` 或自己去切根页面，会破坏当前容器路由边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.launchContext
// 功能说明: 修改前 macOS Canvas controller 只有启动上下文入口，还没有独立的“返回 BoardList”回调出口。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
var launchContext: CanvasLaunchContext?
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.macOS",
    logPrefix: "[BoardStore][macOS]"
)

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.launchContext
// 功能说明: 修改前 iOS Canvas controller 与 macOS 对称，同样没有用于返回 BoardList 的 callback 注入点。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
var launchContext: CanvasLaunchContext?
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.iOS",
    logPrefix: "[BoardStore][iOS]"
)
```

### 修改后

- 双端 `Canvas` controller 都新增了 `var onBackToBoardList: (() -> Void)?`。
- 这个属性只定义“如果需要返回列表，就通过回调交给外部容器处理”，不承担任何 UI 或路由实现细节。
- 这样后续左上角按钮只需要调用这个 closure，不需要知道 `AppRoot` 或 `AppLaunchDestination`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.onBackToBoardList
// 功能说明: 修改后 macOS Canvas controller 暴露纯路由回调，用于把“返回 BoardList”请求交回外部容器。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
var launchContext: CanvasLaunchContext?
var onBackToBoardList: (() -> Void)?
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.macOS",
    logPrefix: "[BoardStore][macOS]"
)

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.onBackToBoardList
// 功能说明: 修改后 iOS 与 macOS 对齐，也通过独立 callback 暴露“返回 BoardList”能力，供后续按钮层调用。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
var launchContext: CanvasLaunchContext?
var onBackToBoardList: (() -> Void)?
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.iOS",
    logPrefix: "[BoardStore][iOS]"
)
```

## 修改二：在 AppRoot 创建 Canvas 时注入返回 BoardList 的回调

### 修改前

- `AppRoot.makeViewController(for:)` 在命中 `.canvas` 时只负责创建 `Canvas` controller 并注入 `launchContext`。
- 即使阶段1和阶段2已经把 `BoardList` 缓存和刷新链路打通，`Canvas` 这边依然没有一个接回 `.boardList` 的反向出口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改前 macOS 在创建 Canvas controller 时只注入 launchContext，还没有把“返回 BoardList”路由接回 AppRoot。
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
// 功能说明: 修改前 iOS 侧也只负责把 launchContext 交给 Canvas controller，尚未建立返回 BoardList 的 callback 回路。
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

### 修改后

- 双端 `AppRoot` 在创建 `Canvas` controller 时，都新增了 `onBackToBoardList` 注入。
- 这个 closure 统一回到 `self?.display(.boardList)`，让路由切换权继续留在 `AppRoot`。
- 这样阶段4的按钮只要调用 controller 上的 callback，就能进入已经打通的“缓存实例 + prepareForDisplay()”返回链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/类型名: macOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 macOS 在创建 Canvas controller 时把 onBackToBoardList 接回 AppRoot.display(.boardList)，保持路由集中在容器层。
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

// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/类型名: iOSAppRootViewController.makeViewController(for:)
// 功能说明: 修改后 iOS 与 macOS 对齐，在 AppRoot 层统一接管 Canvas -> BoardList 的回退路由。
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

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 已对照本次修改，确认阶段3只包含：
- 双端 `Canvas` controller 的 `onBackToBoardList` 回调属性
- 双端 `AppRoot` 对该回调的注入
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译或运行时验证；因此当前验证范围以代码对照和 lint 为主。
