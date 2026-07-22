# 20260722_163509_macos_toolbar_scale_80_percent_record

## 背景

本次修改将 macOS 画布右侧工具条整体缩减到原来的 `80%`。

这次只影响 macOS 工具条，不修改 shared 的 `CanvasToolbarChromeMetrics`，因此不会影响 iOS 工具条。修改同时覆盖视觉尺寸和布局测量，避免出现“看起来变小，但 placement solver 仍按旧尺寸占位”的问题。

## 修改 1：新增 macOS 专属 toolbar metrics

修改前，`macOSCanvasToolbarHostView` 直接使用 shared metrics：按钮 `44pt`、间距 `12pt`、内边距 `12pt`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 位置：文件顶部；修改前，没有 macOS 专属缩放 metrics
import AppKit
import QuartzCore

final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }
}
```

修改后，新增 `macOSCanvasToolbarChromeMetrics`，以 `scale = 0.8` 派生出 macOS 专属的 button / spacing / inset / measured size。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 位置：文件顶部；修改后，新增 macOS 专属 80% toolbar metrics
enum macOSCanvasToolbarChromeMetrics {
    static let scale: CGFloat = 0.8
    static let spacing = CanvasToolbarChromeMetrics.spacing * scale
    static let horizontalInset = CanvasToolbarChromeMetrics.horizontalInset * scale
    static let verticalInset = CanvasToolbarChromeMetrics.verticalInset * scale
    static let buttonEdge = CanvasToolbarChromeMetrics.buttonEdge * scale

    static func measuredContentSize(
        forMeasuredStackSize stackSize: CGSize
    ) -> CGSize {
        CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: stackSize.width + (horizontalInset * 2),
                height: stackSize.height + (verticalInset * 2)
            )
        )
    }
}
```

## 修改 2：缩放 toolbar 背景与 bootstrap 尺寸

修改前，toolbar 背景圆角、阴影和 bootstrap 尺寸使用未缩放值。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 类型：macOSCanvasToolbarHostView.Layout；修改前，背景和 bootstrap 尺寸未缩放
private enum Layout {
    static let cornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowOffset = CGSize(width: 0, height: 4)
    static let minimumBootstrapSize = CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: CGSize(
            width: CanvasToolbarChromeMetrics.buttonEdge,
            height: CanvasToolbarChromeMetrics.buttonEdge
        )
    )
}
```

修改后，圆角、阴影半径、阴影偏移、button 圆角和 bootstrap size 都按 0.8 的 macOS metrics 计算。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 类型：macOSCanvasToolbarHostView.Layout；修改后，背景和 bootstrap 尺寸按 80% 缩放
private enum Layout {
    static let cornerRadius: CGFloat = 18 * macOSCanvasToolbarChromeMetrics.scale
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10 * macOSCanvasToolbarChromeMetrics.scale
    static let shadowOffset = CGSize(
        width: 0,
        height: 4 * macOSCanvasToolbarChromeMetrics.scale
    )
    static let buttonCornerRadius: CGFloat = 12 * macOSCanvasToolbarChromeMetrics.scale
    static let minimumBootstrapSize = macOSCanvasToolbarChromeMetrics.measuredContentSize(
        forMeasuredStackSize: CGSize(
            width: macOSCanvasToolbarChromeMetrics.buttonEdge,
            height: macOSCanvasToolbarChromeMetrics.buttonEdge
        )
    )
}
```

## 修改 3：缩放 stack 间距和内容内边距

修改前，按钮 stack 的 spacing 和约束内边距都直接使用 shared metrics。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：buttonsStackView 初始化与 init(frame:)；修改前，间距和内边距使用 shared metrics
stackView.spacing = CanvasToolbarChromeMetrics.spacing

buttonsStackView.topAnchor.constraint(
    equalTo: contentClipView.topAnchor,
    constant: CanvasToolbarChromeMetrics.verticalInset
)
buttonsStackView.leadingAnchor.constraint(
    equalTo: contentClipView.leadingAnchor,
    constant: CanvasToolbarChromeMetrics.horizontalInset
)
buttonsStackView.trailingAnchor.constraint(
    equalTo: contentClipView.trailingAnchor,
    constant: -CanvasToolbarChromeMetrics.horizontalInset
)
```

修改后，stack spacing 和内容内边距都使用 macOS 专属 80% metrics。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：buttonsStackView 初始化与 init(frame:)；修改后，间距和内边距按 80% 缩放
stackView.spacing = macOSCanvasToolbarChromeMetrics.spacing

buttonsStackView.topAnchor.constraint(
    equalTo: contentClipView.topAnchor,
    constant: macOSCanvasToolbarChromeMetrics.verticalInset
)
buttonsStackView.leadingAnchor.constraint(
    equalTo: contentClipView.leadingAnchor,
    constant: macOSCanvasToolbarChromeMetrics.horizontalInset
)
buttonsStackView.trailingAnchor.constraint(
    equalTo: contentClipView.trailingAnchor,
    constant: -macOSCanvasToolbarChromeMetrics.horizontalInset
)
```

## 修改 4：缩放按钮尺寸与按钮圆角

修改前，按钮宽高约束为 shared `buttonEdge = 44`，按钮圆角为 `12`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyAppearance(_:to:) 与 ensureSquareSize(for:)；修改前，按钮使用原尺寸
button.layer?.cornerRadius = 12

let widthConstraint = button.widthAnchor.constraint(
    equalToConstant: CanvasToolbarChromeMetrics.buttonEdge
)
let heightConstraint = button.heightAnchor.constraint(
    equalToConstant: CanvasToolbarChromeMetrics.buttonEdge
)
```

修改后，按钮宽高使用 `44 * 0.8 = 35.2`，按钮圆角也按 80% 缩放。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：applyAppearance(_:to:) 与 ensureSquareSize(for:)；修改后，按钮使用 80% 尺寸
button.layer?.cornerRadius = Layout.buttonCornerRadius

let widthConstraint = button.widthAnchor.constraint(
    equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge
)
let heightConstraint = button.heightAnchor.constraint(
    equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge
)
```

## 修改 5：同步 macOS host 的 measuredContentSize

修改前，`macOSCanvasToolbarHostView.measuredContentSize()` 使用 shared measurement，返回的是原尺寸工具条内容大小。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：measuredContentSize()；修改前，host 自测使用 shared measurement
func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.fittingSize
    return CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: stackSize
    )
}
```

修改后，host 自测使用 macOS 专属 80% metrics。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数：measuredContentSize()；修改后，host 自测使用 macOS 80% measurement
func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.fittingSize
    return macOSCanvasToolbarChromeMetrics.measuredContentSize(
        forMeasuredStackSize: stackSize
    )
}
```

## 修改 6：同步 macOS controller 的 placement 测量

修改前，`macOSViewController.measuredToolbarHostSize(for:)` 用 shared button / spacing / measurement 计算 placement solver 的 toolbarMeasuredSize。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：measuredToolbarHostSize(for:)；修改前，placement 仍按原尺寸测量
let itemCount = CGFloat(state.items.count)
let stackedLength = (itemCount * CanvasToolbarChromeMetrics.buttonEdge)
    + (max(itemCount - 1, 0) * CanvasToolbarChromeMetrics.spacing)

switch state.preferredAxis {
case .horizontal:
    measuredStackSize = CGSize(
        width: stackedLength,
        height: CanvasToolbarChromeMetrics.buttonEdge
    )
case .vertical:
    measuredStackSize = CGSize(
        width: CanvasToolbarChromeMetrics.buttonEdge,
        height: stackedLength
    )
}

return CanvasChromeLayoutGeometry.sanitizedSize(
    CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: measuredStackSize
    )
)
```

修改后，controller 的 placement 测量也改用 macOS 专属 80% metrics，保证视觉尺寸和布局占位一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：measuredToolbarHostSize(for:)；修改后，placement 按 macOS 80% 尺寸测量
let itemCount = CGFloat(state.items.count)
let stackedLength = (itemCount * macOSCanvasToolbarChromeMetrics.buttonEdge)
    + (max(itemCount - 1, 0) * macOSCanvasToolbarChromeMetrics.spacing)

switch state.preferredAxis {
case .horizontal:
    measuredStackSize = CGSize(
        width: stackedLength,
        height: macOSCanvasToolbarChromeMetrics.buttonEdge
    )
case .vertical:
    measuredStackSize = CGSize(
        width: macOSCanvasToolbarChromeMetrics.buttonEdge,
        height: stackedLength
    )
}

return CanvasChromeLayoutGeometry.sanitizedSize(
    macOSCanvasToolbarChromeMetrics.measuredContentSize(
        forMeasuredStackSize: measuredStackSize
    )
)
```

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查本次修改的 macOS toolbar host 和 controller
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
# 命令：git status --short，显示 macOS 工具条 80% 缩放代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_163509_macos_toolbar_scale_80_percent_record.md
```

本次没有提交代码。
