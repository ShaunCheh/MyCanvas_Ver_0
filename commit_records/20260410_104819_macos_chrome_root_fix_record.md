# 20260410_104819_macos_chrome_root_fix_record

## 记录说明

本记录基于当前工作区里“刚刚这次 macOS chrome root fix”的实际 `git diff` 与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 3 个业务代码文件：

- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift`
- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前统计：`3 files changed, 40 insertions(+), 10 deletions(-)`

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数: date
# 说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数: git diff --stat / git diff
# 说明: 提取这次 macOS chrome root fix 的真实变更范围，并据此整理“修改前 / 修改后”的代码片段。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift" \
  "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift" \
  "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
```

## 问题背景

这次修改针对的是同一条根因链上的两个 macOS chrome 问题：

1. `阅读模式 -> 编辑模式` 时，工具栏会先从左下角 bootstrap 位置参与动画，再从右边进入。
2. 首次打开画板时，`minimap` 会先按“无 blocker”路径落位，和左上角返回按钮重叠。

排查日志已经确认：

- `chromeOverlayView` 原先是 `non-flipped`，导致 `toolbar` / `minimap` 的视觉上下语义与 `iOS` 和 `viewport` 不一致。
- 首次 overlay layout 发生得过早时，`backButton` / `workspaceModeButton` 的 frame 还没有稳定，`baseChromeBlockersForToolbarLayout()` 会得到空数组。
- `toolbar` 在 `toEditing` 路径上会读取 bootstrap 的 `toolbarHostView.frame == {{0,0},{68,68}}` 作为起点，从而产生错误首跳。

因此，这次不是分别打两个局部补丁，而是直接把 `macOS` chrome 的坐标语义、首次布局时机和 `toolbar` transition 起跳方式一起收敛。

## 修改一：`macOSCanvasChromeOverlayView.swift` 显式收敛为 flipped 坐标语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数: macOSCanvasChromeOverlayView
// 说明: 修改前没有显式声明 isFlipped，默认沿用 NSView 的 non-flipped 坐标语义。
final class macOSCanvasChromeOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数: isFlipped / override init(frame:)
// 说明: 修改后把 chrome overlay 明确收敛为 flipped，让 toolbar、minimap、button blocker 使用同一套 top-left 几何语义。
final class macOSCanvasChromeOverlayView: NSView {
    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
```

## 修改二：`macOSViewController.swift` 把 chrome 求解链统一到 overlay 坐标系，并补齐首次稳定布局

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: viewDidAppear() / updatePreparedToolbarPlacement() / updateChromeOverlayLayout() / toolbarLayoutSafeBounds()
// 说明: 修改前 overlay layout 的 safeBounds 直接取根 view，且不会在 chrome 子树布局稳定后再补一轮 layout。
override func viewDidAppear() {
    super.viewDidAppear()
    updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
}

private func updatePreparedToolbarPlacement() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func updateChromeOverlayLayout() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

private func toolbarLayoutSafeBounds() -> CGRect {
    CGRect(
        x: view.bounds.minX + view.safeAreaInsets.left,
        y: view.bounds.minY + view.safeAreaInsets.top,
        width: max(
            view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
            0
        ),
        height: max(
            view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom,
            0
        )
    ).standardized
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: viewDidAppear() / updatePreparedToolbarPlacement() / updateChromeOverlayLayout() / toolbarLayoutSafeBounds()
// 说明: 修改后 chrome 求解统一以 chromeOverlayView 为几何真源，并在首次显示和每次 pass 前补齐 overlay 子树布局，避免 blocker 还是零尺寸时就提前求解 minimap。
override func viewDidAppear() {
    super.viewDidAppear()
    updateCameraViewportSizeIfNeeded(trigger: "viewDidAppear")
    updateChromeOverlayLayout()
}

private func updatePreparedToolbarPlacement() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        if chromeOverlayView.bounds.isEmpty == false {
            chromeOverlayView.layoutSubtreeIfNeeded()
        }
        updateChromeOverlayLayout()
    }
}

private func updateChromeOverlayLayout() {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    if chromeOverlayView.bounds.isEmpty == false {
        chromeOverlayView.layoutSubtreeIfNeeded()
    }
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

private func toolbarLayoutSafeBounds() -> CGRect {
    CGRect(
        x: chromeOverlayView.bounds.minX + chromeOverlayView.safeAreaInsets.left,
        y: chromeOverlayView.bounds.minY + chromeOverlayView.safeAreaInsets.top,
        width: max(
            chromeOverlayView.bounds.width -
                chromeOverlayView.safeAreaInsets.left -
                chromeOverlayView.safeAreaInsets.right,
            0
        ),
        height: max(
            chromeOverlayView.bounds.height -
                chromeOverlayView.safeAreaInsets.top -
                chromeOverlayView.safeAreaInsets.bottom,
            0
        )
    ).standardized
}
```

### 修改意图

这一步解决的是两件事情：

- `safeBounds`、button blocker、`toolbar`、`minimap` 最终 frame 全部落到同一个 overlay 坐标系里，不再混用根 `view` 与 overlay 子视图的语义。
- 首次打开画板时，`backButton` / `workspaceModeButton` 一旦在 `viewDidAppear` 后变成有效 frame，就会立刻触发一轮新的 overlay layout，避免 `minimap` 停在“无 blocker”路径下的错误位置。

## 修改三：`macOSCanvasToolbarHostView.swift` / `macOSViewController.swift` 拆分 “初始摆位” 和 “正式动画”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数: renderTransition(_:)
// 说明: 修改前 Host 只能依据 NSAnimationContext.current.duration 猜测当前是不是动画写入，控制器无法显式要求“先摆位、后动画”。
func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
    let shouldAnimate = shouldAnimateTransitionChanges
    if shouldAnimate == false {
        clearTransitionAnimations()
    }
    logTransitionRenderRequest(
        presentation: presentation,
        animated: shouldAnimate
    )
    applyTransitionFrame(presentation.frame, animated: shouldAnimate)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: beginToolbarModeTransition(to:) / cancelAndRebaseToolbarTransitionIfNeeded(targetMode:) / animateToolbarTransition(to:duration:completion:)
// 说明: 修改前控制器无论是初始 presentation、反向重基线还是正式阶段动画，都统一调用 renderTransition(...)，导致 toEditing 时会把 bootstrap 的 {{0,0},{68,68}} 也带进动画。
toolbarHostView.renderTransition(initialPresentation)

toolbarHostView.renderTransition(runtime.currentPresentation)

if duration <= 0 {
    toolbarHostView.renderTransition(targetPresentation)
    completion()
    return
}

NSAnimationContext.runAnimationGroup { context in
    context.duration = duration
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    self.toolbarHostView.renderTransition(targetPresentation)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数: renderTransition(_:animated:)
// 说明: 修改后 Host 允许控制器显式声明这次 renderTransition 是“非动画摆位”还是“正式动画”，把初始落位和中途重基线从动画链里剥离出来。
func renderTransition(
    _ presentation: CanvasToolbarTransitionPresentation,
    animated explicitAnimated: Bool? = nil
) {
    let shouldAnimate = explicitAnimated ?? shouldAnimateTransitionChanges
    if shouldAnimate == false {
        clearTransitionAnimations()
    }
    logTransitionRenderRequest(
        presentation: presentation,
        animated: shouldAnimate
    )
    applyTransitionFrame(presentation.frame, animated: shouldAnimate)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: beginToolbarModeTransition(to:) / cancelAndRebaseToolbarTransitionIfNeeded(targetMode:) / animateToolbarTransition(to:duration:completion:)
// 说明: 修改后 initialPresentation、runtime rebase 和零时长路径都强制走非动画摆位；只有真正的 NSAnimationContext 阶段动画才显式传 animated: true。
toolbarHostView.renderTransition(
    initialPresentation,
    animated: false
)

toolbarHostView.renderTransition(
    runtime.currentPresentation,
    animated: false
)

if duration <= 0 {
    toolbarHostView.renderTransition(
        targetPresentation,
        animated: false
    )
    completion()
    return
}

NSAnimationContext.runAnimationGroup { context in
    context.duration = duration
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    self.toolbarHostView.renderTransition(
        targetPresentation,
        animated: true
    )
}
```

### 修改意图

这一步修的是 `toEditing` 的错误首跳：

- 初始 `offscreen` presentation 现在会先“瞬时摆到位”
- 真正进入动画时，Host 才从 `offscreenFrame -> collapsedFrame -> visibleFrame` 开始跑
- bootstrap 的 `{{0,0},{68,68}}` 不再被错误地拿来参与动画

## 修改影响

这次根因修复把 `macOS chrome` 的两类异常收口到同一条结构化链路：

- `chromeOverlayView` 的上下语义与 `viewport/context menu` 对齐
- `toolbar` / `minimap` / chrome blocker 的几何输入统一到 overlay 自身坐标系
- 首次开板时，`minimap` 不再只依赖过早的一轮空 blocker 求解
- `toolbar` 的进入动画不再从左下角 bootstrap 位置起跳

## 验证

已完成：

- IDE lints：无新增错误
- 编译验证：

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数: xcodebuild
# 说明: 对这次 macOS chrome root fix 执行平台构建校验，确认坐标系与 transition API 调整没有破坏工程编译。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-macos-chrome-root-fix" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- 结果：`BUILD SUCCEEDED`

尚未在本记录中完成：

- 再次人工复测运行时，确认：
  - 首次打开画板时 `minimap` 不再与左上角返回按钮重叠
  - `阅读模式 -> 编辑模式` 时工具栏不再先从左下角参与动画

## 补充说明

本记录只覆盖这次 `macOS chrome root fix` 的真实代码改动，不重复展开此前的 `toolbar bootstrap constraint fix`、`toolbar frame sanitize guard fix` 等历史记录内容。
