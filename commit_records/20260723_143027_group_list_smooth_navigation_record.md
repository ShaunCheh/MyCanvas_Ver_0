# 20260723_143027_group_list_smooth_navigation_record

## 记录范围

本记录如实对应刚刚完成的 group 列表导航平滑移动修改：点击 group 列表中的 group 后，镜头不再直接切换到 group frame 中心，而是平滑移动到目标中心点。当前阶段仍不处理自动缩放。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 显示上述两个 Swift 文件有修改。本记录基于当前 `git diff` 与工作区 changes 整理，不直接粘贴原始 diff。

## 修改前

### iOS group 导航直接切换 camera center

修改前，iOS 点击 group 后，`navigateToGroup(withID:)` 直接把 `camera.center` 设置为 group frame 中心点，并立即刷新画布、保存 view state。这会造成镜头瞬间跳转。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前点击 group 后直接切换 camera center，没有平滑过渡。
// 函数名：iOSViewController.navigateToGroup(withID:)
camera.center = targetCenter
requestCanvasRefresh(reason: "navigate group list to \(groupID.uuidString)")
scheduleAutosave(
    reason: "navigate canvas via group list",
    updateKind: .viewStateOnly
)
```

### macOS group 导航同样直接切换 camera center

修改前，macOS 与 iOS 一样，点击 group 后直接设置 `camera.center`，刷新画布并保存 view state。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前点击 group 后直接切换 camera center，没有平滑过渡。
// 函数名：macOSViewController.navigateToGroup(withID:)
camera.center = targetCenter
refreshCanvas(reason: "navigate group list to \(groupID.uuidString)")
scheduleAutosave(
    reason: "navigate canvas via group list",
    updateKind: .viewStateOnly
)
```

### 手动相机输入不需要取消 group 导航动画

修改前没有 group 导航动画状态，因此 pinch、pan、minimap navigate 等手动相机输入入口没有相关取消逻辑。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS pan 只执行用户拖拽相机，不需要取消 group 导航动画。
// 函数名：iOSViewController.applyCanvasPan(_:refreshReason:)
let cameraCenterBeforePan = camera.center
camera.pan(by: translation)
requestCanvasRefresh(reason: refreshReason)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS indirect pan 只执行用户滚轮/触控板平移，不需要取消 group 导航动画。
// 函数名：macOSViewController.handleIndirectPan(_:at:)
camera.pan(by: remainingTranslation)
refreshCanvas(reason: "indirect pan \(describe(point: remainingTranslation))")
```

## 修改后

### iOS 增加 display link 动画状态

修改后，iOS 引入 `QuartzCore` 和 `CADisplayLink`，通过 `CameraCenterAnimationState` 保存起点、终点、开始时间、刷新原因和 autosave 原因。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：引入 CADisplayLink 和 CACurrentMediaTime，用于驱动 iOS camera center 平滑插值。
// 函数名：iOSViewController 文件 import 区域
import PhotosUI
import QuartzCore
import UIKit
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：记录一次 camera center 动画的起点、终点、时间和收尾原因。
// 函数名：iOSViewController.CameraCenterAnimationState
private struct CameraCenterAnimationState {
    let startCenter: CGPoint
    let targetCenter: CGPoint
    let startTimestamp: CFTimeInterval
    let refreshReason: String
    let autosaveReason: String
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group 导航动画时长和 display link 运行时状态。
// 函数名：iOSViewController group list navigation animation properties
private static let groupListNavigationAnimationDuration: TimeInterval = 0.28
private var groupListNavigationDisplayLink: CADisplayLink?
private var groupListNavigationAnimationState: CameraCenterAnimationState?
```

### iOS group 导航改为启动平滑动画

修改后，`navigateToGroup(withID:)` 不再直接写 `camera.center`，而是调用 `beginGroupListNavigationAnimation(...)`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：点击 group 后启动 camera center 平滑移动，不直接跳转。
// 函数名：iOSViewController.navigateToGroup(withID:)
beginGroupListNavigationAnimation(
    to: targetCenter,
    refreshReason: "navigate group list to \(groupID.uuidString)",
    autosaveReason: "navigate canvas via group list"
)
```

### iOS 每帧插值 camera center，结束后保存 view state

动画期间每帧使用 ease-out cubic 插值 `camera.center` 并刷新画布；到达终点后精确设置目标中心，取消 display link，并执行一次 `viewStateOnly` autosave。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：创建 iOS group 导航 display link，并记录动画状态。
// 函数名：iOSViewController.beginGroupListNavigationAnimation(to:refreshReason:autosaveReason:)
groupListNavigationAnimationState = CameraCenterAnimationState(
    startCenter: startCenter,
    targetCenter: targetCenter,
    startTimestamp: CACurrentMediaTime(),
    refreshReason: refreshReason,
    autosaveReason: autosaveReason
)
let displayLink = CADisplayLink(
    target: self,
    selector: #selector(handleGroupListNavigationDisplayLink(_:))
)
groupListNavigationDisplayLink = displayLink
displayLink.add(to: .main, forMode: .common)
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS display link 每帧推进 camera center，动画结束后刷新并保存 view state。
// 函数名：iOSViewController.handleGroupListNavigationDisplayLink(_:)
let easedProgress = Self.easeOutCubic(rawProgress)
camera.center = CGPoint(
    x: animationState.startCenter.x +
        (animationState.targetCenter.x - animationState.startCenter.x) * easedProgress,
    y: animationState.startCenter.y +
        (animationState.targetCenter.y - animationState.startCenter.y) * easedProgress
)
requestCanvasRefresh(reason: animationState.refreshReason)
```

### macOS 增加 Timer 动画状态

macOS 使用 main run loop `Timer` 驱动同样的 camera center 插值。动画状态结构与 iOS 对齐。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：记录一次 macOS camera center 动画的起点、终点、时间和收尾原因。
// 函数名：macOSViewController.CameraCenterAnimationState
private struct CameraCenterAnimationState {
    let startCenter: CGPoint
    let targetCenter: CGPoint
    let startTimestamp: CFTimeInterval
    let refreshReason: String
    let autosaveReason: String
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group 导航动画时长和 Timer 运行时状态。
// 函数名：macOSViewController group list navigation animation properties
private static let groupListNavigationAnimationDuration: TimeInterval = 0.28
private var groupListNavigationTimer: Timer?
private var groupListNavigationAnimationState: CameraCenterAnimationState?
```

### macOS group 导航改为 Timer 平滑动画

修改后，macOS `navigateToGroup(withID:)` 也只负责计算目标中心并启动动画，不再直接跳转。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：点击 group 后启动 macOS camera center 平滑移动，不直接跳转。
// 函数名：macOSViewController.navigateToGroup(withID:)
beginGroupListNavigationAnimation(
    to: targetCenter,
    refreshReason: "navigate group list to \(groupID.uuidString)",
    autosaveReason: "navigate canvas via group list"
)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：创建 macOS group 导航 Timer，并挂到 common run loop mode。
// 函数名：macOSViewController.beginGroupListNavigationAnimation(to:refreshReason:autosaveReason:)
let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
    self?.handleGroupListNavigationTimer(timer)
}
groupListNavigationTimer = timer
RunLoop.main.add(timer, forMode: .common)
```

### iOS/macOS 共用 ease-out cubic 节奏

两个平台都使用 ease-out cubic，让镜头开始移动更快、接近 group 时减速，避免直接切换的突兀感。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：将线性 progress 转换为 ease-out cubic progress，用于 camera center 平滑插值。
// 函数名：iOSViewController.easeOutCubic(_:)
private static func easeOutCubic(_ progress: CGFloat) -> CGFloat {
    let clampedProgress = min(max(progress, 0), 1)
    let inverseProgress = 1 - clampedProgress
    return 1 - inverseProgress * inverseProgress * inverseProgress
}
```

### 手动相机输入会取消 group 导航动画

修改后，pinch、direct touch transform、pan、minimap navigate 等手动相机输入入口会先取消 group 导航动画，避免用户操作过程中又被未完成的自动动画拉回。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：用户 pinch 开始时取消 group 导航动画，后续缩放不被自动移动覆盖。
// 函数名：iOSViewController.handleZoomGestureBegan()
private func handleZoomGestureBegan() {
    cancelGroupListNavigationAnimation()
    didMutateCameraDuringPinchGesture = false
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：用户 macOS indirect pan 时取消 group 导航动画，避免滚轮/触控板平移后被动画拉回。
// 函数名：macOSViewController.handleIndirectPan(_:at:)
cancelGroupListNavigationAnimation()
camera.pan(by: remainingTranslation)
refreshCanvas(reason: "indirect pan \(describe(point: remainingTranslation))")
```

### controller 释放时清理动画资源

iOS/macOS controller 释放时都会取消 group 导航动画，避免 display link 或 timer 继续持有运行状态。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS controller 释放时取消 group 导航 display link。
// 函数名：iOSViewController.deinit
deinit {
    cancelGroupListNavigationAnimation()
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS controller 释放时取消 group 导航 Timer，并保留原有 keyboard shortcut observer 清理。
// 函数名：macOSViewController.deinit
deinit {
    cancelGroupListNavigationAnimation()
    removeKeyboardShortcutObservationIfNeeded()
}
```

## 行为变化

- 点击 group 列表行后，镜头平滑移动到 group frame 中心，不再瞬间切换。
- 当前阶段仍不改变 zoom，不做自动 fit-to-view。
- 动画过程中持续刷新画布，动画结束后执行一次 `viewStateOnly` autosave。
- 重复点击其他 group 会取消上一段 group 导航动画并启动新的动画。
- 用户手动 pan、zoom 或 minimap navigate 会取消当前 group 导航动画，避免动画覆盖用户输入。

## 验证

已执行 lints 检查：

- `ReadLints`：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 无 linter errors。
- `ReadLints`：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 无 linter errors。

已执行 macOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS group 列表平滑导航改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

结果：build 成功。

已执行 iOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS group 列表平滑导航改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

结果：build 成功。
