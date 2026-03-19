# 20260319_124904_canvas_boardlist_phase5_overlay_occlusion_record

## 记录范围

- 记录目标：实施 `Canvas` 返回与列表缓存方案的阶段5，收口左上角返回按钮与 minimap / context menu 的避让与命中层级问题。
- 本次目的 1：让 `backButton` 正式进入 `chromeOccupiedRects()`，使 overlay 布局系统知道左上角也存在 chrome 占位。
- 本次目的 2：在点击返回前先关闭可能存在的 context menu，避免带着浮层状态直接切页。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：按钮视觉样式本体。
- 本记录不包含：git commit。

## 修改一：把 backButton 纳入双端 chrome occupied rect 计算

### 修改前

- 双端 `chromeOccupiedRects()` 只会返回右下角 `controlsStackView` 的 frame。
- `backButton` 虽然已经挂到 `chromeOverlayView`，但 minimap 与 context menu 的布局计算并不知道左上角也有一个需要避让的 chrome 区域。
- 这会让阶段4后的返回按钮继续处在“视觉上存在，但布局系统不感知”的状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.chromeOccupiedRects()
// 功能说明: 修改前 macOS 的 chrome occupied rect 只包含右下角 controlsStackView，左上角 backButton 不参与避让计算。
private func chromeOccupiedRects() -> [CGRect] {
    guard
        controlsStackView.bounds.width > 0,
        controlsStackView.bounds.height > 0
    else {
        return []
    }

    return [controlsStackView.frame.standardized]
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.chromeOccupiedRects()
// 功能说明: 修改前 iOS 与 macOS 对称，同样只把右下角工具区当作 chrome blocker，忽略了左上角返回按钮。
private func chromeOccupiedRects() -> [CGRect] {
    guard
        controlsStackView.bounds.width > 0,
        controlsStackView.bounds.height > 0
    else {
        return []
    }

    return [controlsStackView.frame.standardized]
}
```

### 修改后

- 双端 `chromeOccupiedRects()` 改为同时收集：
- `backButton`
- `controlsStackView`
- 新增 `appendChromeOccupiedRect(...)` 辅助方法，统一处理 `isHidden` 和 `frame.isEmpty` 过滤逻辑。
- `contextMenuOccupiedRects()` 本来就是从 `chromeOccupiedRects()` 继续扩展 minimap，因此这一步改完后，返回按钮会自动进入 minimap / context menu 的避让链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.chromeOccupiedRects() / appendChromeOccupiedRect(for:to:)
// 功能说明: 修改后 macOS 会把 backButton 和 controlsStackView 一起纳入 chrome occupied rect，供 minimap 与 context menu 共用避让信息。
private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: controlsStackView, to: &rects)
    return rects
}

private func appendChromeOccupiedRect(
    for view: NSView,
    to rects: inout [CGRect]
) {
    guard view.isHidden == false else {
        return
    }

    let standardizedRect = view.frame.standardized
    guard standardizedRect.isEmpty == false else {
        return
    }

    rects.append(standardizedRect)
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.chromeOccupiedRects() / appendChromeOccupiedRect(for:to:)
// 功能说明: 修改后 iOS 与 macOS 对齐，左上角 backButton 也会参与 chrome blocker 计算，避免 overlay 布局继续只感知右下角工具区。
private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: controlsStackView, to: &rects)
    return rects
}

private func appendChromeOccupiedRect(
    for view: UIView,
    to rects: inout [CGRect]
) {
    guard view.isHidden == false else {
        return
    }

    let standardizedRect = view.frame.standardized
    guard standardizedRect.isEmpty == false else {
        return
    }

    rects.append(standardizedRect)
}
```

## 修改二：返回前主动关闭 context menu，避免带着浮层状态切页

### 修改前

- 阶段4里的返回按钮点击处理只会直接触发 `onBackToBoardList?()`。
- 如果此时 `CanvasContextMenuHostView` 仍处于已展示状态，页面切换会发生在带菜单浮层的瞬间，留下不必要的状态耦合风险。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.handleBackButtonClick()
// 功能说明: 修改前 macOS 返回按钮点击后直接切回 BoardList，没有先清理 context menu 状态。
@objc
private func handleBackButtonClick() {
    onBackToBoardList?()
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.handleBackButtonTap()
// 功能说明: 修改前 iOS 返回按钮也会直接触发回退路由，未对可能存在的菜单浮层做收口。
@objc
private func handleBackButtonTap() {
    onBackToBoardList?()
}
```

### 修改后

- 双端返回按钮点击都会先执行 `dismissContextMenu()`。
- 再调用 `onBackToBoardList?()`，保证页面切换发生前，当前 `Canvas` 的浮层菜单状态已经收口。
- 这一步不改变路由边界，只是把切换前的 transient UI 状态清理干净。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.handleBackButtonClick()
// 功能说明: 修改后 macOS 在返回 BoardList 前先关闭当前 context menu，避免带着菜单浮层状态直接切页。
@objc
private func handleBackButtonClick() {
    dismissContextMenu()
    onBackToBoardList?()
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.handleBackButtonTap()
// 功能说明: 修改后 iOS 与 macOS 对齐，也会先清空 context menu 状态，再执行返回列表的回调。
@objc
private func handleBackButtonTap() {
    dismissContextMenu()
    onBackToBoardList?()
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 已对照本次修改，确认阶段5只包含：
- `backButton` 进入双端 `chromeOccupiedRects()`
- 双端新增 `appendChromeOccupiedRect(...)` 辅助方法
- 返回前 `dismissContextMenu()`
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译或运行时验证；因此当前验证范围以代码对照和 lint 为主。
