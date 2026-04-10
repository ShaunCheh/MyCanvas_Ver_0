# 20260410_122114_toolbar_history_phase5_shared_blocker_cleanup_record

## 记录说明

本记录基于当前工作区的实际 `changes`、本次对应文件的 `git diff`、`git diff --stat`，以及修改后的当前代码状态整理，不包含原始 `git diff` 文本。

这次记录的是 `toolbar_history_convergence` 阶段 5 的真实落地内容，实际只涉及一个共享层清理点：

- 删除共享枚举 `CanvasChromeBlockerKind.historyButtons`
- 不再让共享布局模型继续背负已经消失的 iOS 私有 history blocker 概念

当前工作区实际变更文件只有 1 个：

- `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`

当前统计：`1 file changed, 1 deletion(-)`

## 时间戳与取证命令

```bash
# 文件路径: /bin/date
# 函数: date
# 说明: 生成本记录文件名前缀使用的时间戳。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: /usr/bin/git
# 函数: git status --short / git diff --stat / git diff
# 说明: 确认本次阶段 5 的真实 changes 只落在共享 blocker 枚举这一处，并据此整理下面的“修改前 / 修改后”代码片段。
git status --short

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift"
```

## 本次修改的真实边界

在阶段 2 和阶段 3 之后，`iOS` 侧的独立 `historyButtonsStackView`、`.historyButtons` blocker 注入，以及对应私有刷新链都已经消失了。

这意味着共享层里还保留的 `CanvasChromeBlockerKind.historyButtons` 已经没有任何消费者，继续留下它只会造成两类问题：

1. 共享布局模型继续携带一个已经不存在的平台私有概念。
2. 后续维护时，容易让人误判“系统里仍然存在独立 history blocker”。

所以这次阶段 5 不再改平台控制器，也不再改 toolbar host，只做共享 dead code 清理。

## 修改一：删除 `CanvasChromeBlockerKind.historyButtons`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数/符号: CanvasChromeBlockerKind
// 说明: 修改前共享 blocker 枚举仍然保留 historyButtons，意味着共享布局层还背着已经废弃的 iOS 私有 blocker 类型。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case historyButtons
    case toolbar
    case miniMap
    case contextMenu
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数/符号: CanvasChromeBlockerKind
// 说明: 修改后移除 historyButtons，只保留当前仍有实际消费者的共享 blocker 类型。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case toolbar
    case miniMap
    case contextMenu
}
```

### 这一处修改的实际效果

- 共享 `CanvasChromeLayoutContext` 不再暴露无用的 `historyButtons` blocker 种类。
- 阶段 2 已经完成的平台收敛结果，终于在共享模型层面被彻底收口。
- 当前 blocker 语义与真实运行时布局参与者保持一致。

## 本次没有修改的内容

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: baseChromeBlockersForToolbarLayout() / makeToolbarState()
// 说明: 这次没有再改 iOS 控制器；iOS 在此前阶段已经不再注入 .historyButtons，并且已经通过共享 toolbar items 渲染 undo/redo。
// 无本次改动。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数: symbolConfiguration(for:) / applyAppearance(_:to:)
// 说明: 这次没有再改 iOS toolbar host；undo/redo 的 icon-only 渲染仍是有效共享逻辑，不属于 dead code。
// 无本次改动。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: toolbarButtonsByID / makeToolbarState()
// 说明: 这次没有再改 macOS；阶段 5 只清理共享层历史遗留，不涉及 macOS toolbar 接线。
// 无本次改动。
```

## 修改后的阶段性结论

这次阶段 5 的真实结果是：

1. 共享 blocker 枚举中的 `historyButtons` 已被删除。
2. 仓库中不再残留任何 `historyButtons` 相关代码引用。
3. 共享布局模型与当前两端 toolbar 架构保持一致，不再含有已经失效的平台私有概念。

## 本次验证

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project ... -scheme ... build
# 说明: 对 macOS 与 iOS Simulator 两个目标做最小构建验证，确认本次共享 dead code 清理没有引入编译错误。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  build
```

验证结果：

- `ReadLints` 检查 `CanvasChromeLayoutContext.swift`，无新增问题。
- `macOS build` 通过。
- `iOS Simulator build` 通过。
