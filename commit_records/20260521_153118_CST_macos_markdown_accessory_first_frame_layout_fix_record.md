# 20260521_153118_CST_macos_markdown_accessory_first_frame_layout_fix_record

## 记录范围

- 记录内容：
  - 修复 macOS markdown selection accessory 在首次展示时内部按钮可能保持 `0x0`、导致悬浮工具条不可见的问题。
  - 在 `SelectionAccessoryHostView` 的 macOS 分支中，为手动 `frame` 更新后的 AppKit 视图树补一次同步布局推进。
  - 回收上一轮定位问题时临时打开的 trace logging，避免修复完成后继续输出无关调试日志。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 参考现状：
  - 生成本记录前，执行 `date +"%Y%m%d_%H%M%S_%Z"` 得到时间戳：`20260521_153118_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次修复相关文件执行 `git diff --stat -- ...`，结果为：`2 files changed, 13 insertions(+), 2 deletions(-)`。
  - 生成本记录前，针对本次修复相关文件执行 `git status --short -- ...`，结果为：`M MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`、`M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`。
- 本记录不包含：
  - 上一轮为定位该问题而临时加入 trace logging 的分析过程。
  - markdown selection accessory 的 state 解析链路说明与日志样本本身。

## 当前 changes 摘要

- `SelectionAccessoryHostView` 的 macOS `updateLayout(layoutContext:)` 在解析出 accessory frame 后，不再只更新 `containerView.frame`，而是会立即同步刷新 AppKit 子树布局。
- 新增 `synchronizeLayoutAfterFrameChange()`，把 `host`、`containerView`、`stackView` 都标记为需要布局，并立刻调用 `layoutSubtreeIfNeeded()`，从根因上消除“外框位置对了，但内部按钮首帧还是 0x0”的状态不同步。
- `SelectionAccessoryHostView` 与 `macOSViewController` 中为本次诊断打开的 trace logging 默认值均已恢复为 `false`。

## 修改一：修复 macOS accessory 首帧按钮布局未及时生效

### 修改前

- `SelectionAccessoryHostView.updateLayout(layoutContext:)` 能正确算出 `accessoryFrame`，但在 macOS 分支里只设置了 `containerView.frame`。
- 这意味着外层宿主位置虽然已经更新，内部 `NSStackView` / `NSButton` 的约束布局却没有被立即推进，首次展示时仍可能保留 `0x0` 尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift（修改前）
// 函数名: updateLayout(layoutContext:)
// 功能说明: 修改前只更新 accessory 外层容器的 frame，没有在手动 frame 变更后同步推进 AppKit 子树布局。
func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredAccessorySize()
    let resolvedAccessoryFrame = layoutSolver.resolveAccessoryFrame(
        anchorRect: currentState.anchorRect,
        preferredSize: preferredSize,
        layoutContext: layoutContext
    )
    logLayout(
        state: currentState,
        layoutContext: layoutContext,
        preferredSize: preferredSize,
        resolvedAccessoryFrame: resolvedAccessoryFrame
    )
    guard let accessoryFrame = resolvedAccessoryFrame else {
        containerView.frame = .zero
        return
    }

    // 这里只更新了外层 frame，内部 stack / button 的首帧布局不会被立即刷新。
    containerView.frame = accessoryFrame.integral
}
```

### 修改后

- `updateLayout(layoutContext:)` 在设置 `containerView.frame` 后，立即调用 `synchronizeLayoutAfterFrameChange()`。
- 新 helper 会同步刷新 AppKit 视图树，确保内部 `NSStackView` 和按钮在 accessory 首次出现时就拿到正确尺寸，而不是等下一次系统布局机会。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift
// 函数名: updateLayout(layoutContext:) / synchronizeLayoutAfterFrameChange()
// 功能说明: 修改后在 accessory 外层 frame 更新完成后，立刻同步刷新 AppKit 子树布局，保证 markdown 工具条首帧可见。
func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredAccessorySize()
    let resolvedAccessoryFrame = layoutSolver.resolveAccessoryFrame(
        anchorRect: currentState.anchorRect,
        preferredSize: preferredSize,
        layoutContext: layoutContext
    )
    logLayout(
        state: currentState,
        layoutContext: layoutContext,
        preferredSize: preferredSize,
        resolvedAccessoryFrame: resolvedAccessoryFrame
    )
    guard let accessoryFrame = resolvedAccessoryFrame else {
        containerView.frame = .zero
        return
    }

    containerView.frame = accessoryFrame.integral

    // 手动 frame 更新后立即推进一次 AppKit 子树布局，避免内部按钮仍停留在 0x0。
    synchronizeLayoutAfterFrameChange()
}

private func synchronizeLayoutAfterFrameChange() {
    // AppKit 在手动 frame 更新后不会保证立刻刷新整个子树，所以这里主动触发布局同步。
    needsLayout = true
    containerView.needsLayout = true
    stackView.needsLayout = true
    layoutSubtreeIfNeeded()
    containerView.layoutSubtreeIfNeeded()
}
```

## 修改二：关闭定位期 trace logging

### 修改前

- 为了确认问题是否发生在 state 解析、frame 求解还是 host 内部布局阶段，之前临时把两处 trace logging 开关打成了 `true`。
- 修复已经落地后，如果继续保留这些日志，会让正常交互期间持续刷屏，掩盖真正有价值的运行信息。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift（修改前）
// 函数名: 无（类型级日志开关）
// 功能说明: 修改前 host view 会继续输出 markdown accessory 定位日志。
final class SelectionAccessoryHostView: NSView {
    private static let isTraceLoggingEnabled = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: 无（类型级日志开关，以下摘录类声明与成员）
// 功能说明: 修改前 controller 仍保留 markdown selection accessory 的诊断日志开关。
final class macOSViewController: NSViewController, NSUserInterfaceValidations, NSTextViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
    private static let isMarkdownSelectionAccessoryTraceLoggingEnabled = true
}
```

### 修改后

- 两处日志开关都恢复为 `false`。
- 这样既保留了必要的调试代码入口，也避免在问题已经确认并修复后继续产生运行时噪音。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift
// 函数名: 无（类型级日志开关）
// 功能说明: 修改后 host view 默认不再输出 accessory 诊断日志。
final class SelectionAccessoryHostView: NSView {
    private static let isTraceLoggingEnabled = false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 无（类型级日志开关，以下摘录类声明与成员）
// 功能说明: 修改后 controller 默认关闭 markdown selection accessory trace logging。
final class macOSViewController: NSViewController, NSUserInterfaceValidations, NSTextViewDelegate, macOSBoardListCanvasTransitionInteractionControlling {
    private static let isMarkdownSelectionAccessoryTraceLoggingEnabled = false
}
```

## 验证情况

- `ReadLints` 检查以下文件，未发现新增问题：
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已执行构建验证并通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build`

## 结论

- 这次修复不是通过延后显示、重复刷新或额外兜底重建来“碰运气”解决，而是直接补齐了 macOS accessory host 在手动 frame 更新后的布局同步缺口。
- accessory 的 anchor 解析与 frame 求解链路保持不变，变化点集中在 host 内部布局时机，因此修复范围小，但命中的是根因。
