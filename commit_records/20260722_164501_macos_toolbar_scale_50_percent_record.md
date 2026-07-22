# 20260722_164501_macos_toolbar_scale_50_percent_record

## 背景

本次修改将 macOS 画布右侧工具条整体缩放比例从 `80%` 改为 `50%`。

该比例由 `macOSCanvasToolbarChromeMetrics.scale` 统一派生，因此按钮尺寸、间距、内边距、圆角、阴影和 layout 测量都会随同变为原始 shared toolbar metrics 的一半。

## 修改 1：将 macOS toolbar scale 从 0.8 改为 0.5

修改前，macOS 专属 toolbar metrics 的缩放系数是 `0.8`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 类型：macOSCanvasToolbarChromeMetrics；修改前，macOS 工具条按 80% 缩放
enum macOSCanvasToolbarChromeMetrics {
    static let scale: CGFloat = 0.8
    static let spacing = CanvasToolbarChromeMetrics.spacing * scale
    static let horizontalInset = CanvasToolbarChromeMetrics.horizontalInset * scale
    static let verticalInset = CanvasToolbarChromeMetrics.verticalInset * scale
    static let buttonEdge = CanvasToolbarChromeMetrics.buttonEdge * scale
}
```

修改后，缩放系数改为 `0.5`。其它派生属性不需要逐项改动，会自动按 50% 重新计算。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 类型：macOSCanvasToolbarChromeMetrics；修改后，macOS 工具条按 50% 缩放
enum macOSCanvasToolbarChromeMetrics {
    static let scale: CGFloat = 0.5
    static let spacing = CanvasToolbarChromeMetrics.spacing * scale
    static let horizontalInset = CanvasToolbarChromeMetrics.horizontalInset * scale
    static let verticalInset = CanvasToolbarChromeMetrics.verticalInset * scale
    static let buttonEdge = CanvasToolbarChromeMetrics.buttonEdge * scale
}
```

## 影响范围

因为 macOS toolbar host 和 macOS controller 的 placement 测量都使用 `macOSCanvasToolbarChromeMetrics`，本次改动会同步影响：

- `macOSCanvasToolbarHostView` 中按钮的视觉尺寸。
- toolbar stack 的 spacing。
- toolbar content inset。
- toolbar 背景和按钮圆角。
- toolbar 阴影半径和偏移。
- `macOSViewController.measuredToolbarHostSize(for:)` 的 layout 占位测量。

本次没有修改 shared 的 `CanvasToolbarChromeMetrics`，因此不影响 iOS 工具条。

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查本次修改相关的 macOS toolbar host 和 controller
ReadLints(paths: [
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift",
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
])
```

结果：无 linter 错误。

已执行 macOS build：

```shell
# terminal
# 验证命令：macOS arm64 build
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'
```

结果：build 通过。

## 当前状态

当前 changes：

```shell
# terminal
# 命令：git status --short，显示 macOS 工具条 50% 缩放代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
?? commit_records/20260722_164501_macos_toolbar_scale_50_percent_record.md
```

本次没有提交代码。
