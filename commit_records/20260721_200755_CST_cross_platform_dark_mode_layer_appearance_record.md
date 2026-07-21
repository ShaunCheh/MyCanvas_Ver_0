# 20260721_200755_CST_cross_platform_dark_mode_layer_appearance_record

## 记录范围

- 本记录如实整理 macOS 与 iOS 深色模式适配的当前实现结果。
- 记录依据：
  - 生成记录前的 `git status --short`。
  - 当前 tracked changes 的 `git diff`、`git diff --stat` 与 `git diff --numstat`。
  - 两个新增未跟踪 Swift 文件的实际内容。
  - 已执行的 macOS、iOS Simulator 构建和测试结果。
- 本记录不粘贴原始 `git diff`，而是按问题、修改前、修改后、文件范围和验证结果重新整理。
- 本次代码目标是修复动态 `NSColor` / `UIColor` 被过早转换成静态 `CGColor` 后，`CALayer` 在系统浅色、深色外观切换时不刷新的根因。
- 本次没有提交代码。
- 本记录文件：
  - `commit_records/20260721_200755_CST_cross_platform_dark_mode_layer_appearance_record.md`

## 时间戳与 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统自带的 date 命令生成本记录开头及文件名中的时间戳。
20260721_200755_CST
```

生成本记录文件前，工作区共有 28 个已跟踪修改文件和 2 个新增未跟踪 Swift 文件：

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录 Markdown 创建前的完整工作区 changes。
 M .cursor/plans/cross-platform-dark-mode_18734292.plan.md
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
 M MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
 M MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
 M MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift
 M MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
 M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
 M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/PlatformLayerAppearance.swift
?? MyCanvas_Ver_0Tests/PlatformLayerAppearanceTests.swift
```

已跟踪文件的统计结果如下；该统计不包含两个尚未跟踪的新增 Swift 文件：

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat
# 功能说明: 汇总 tracked changes 的文件数和增删规模，不展开原始 diff。
28 files changed, 953 insertions(+), 207 deletions(-)
```

其中 `.cursor/plans/cross-platform-dark-mode_18734292.plan.md` 只有 5 个 todo 状态由 `pending` 更新为 `completed`；其余 tracked changes 是 27 个 Swift 文件。

## 问题根因

`NSColor` 与 `UIColor` 的系统语义色可以随外观动态解析，但 `CALayer.backgroundColor`、`borderColor`、`fillColor`、`strokeColor` 以及 `CATextLayer.foregroundColor` 保存的是静态 `CGColor`。

原实现大量在初始化阶段直接执行：

```swift
// 文件路径: 多个 macOS / iOS 视图文件（修改前的通用模式）
// 函数名: 视图初始化、updateAppearance()、updateSelectionAppearance() 或 renderRuler()
// 功能说明: 动态系统色在赋给 CALayer 前直接转换为一次性 CGColor。
layer.borderColor = UIColor.separator.cgColor
view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
```

这会产生两个问题：

1. 动态颜色只在调用 `.cgColor` 的当时解析，`CALayer` 不会继续保留 `UIColor` / `NSColor` 的动态语义。
2. 系统外观改变后，如果没有外观生命周期回调重新解析并写回颜色，layer 会继续使用旧的浅色或深色 `CGColor`。

macOS 还存在一个额外约束：

- `viewDidChangeEffectiveAppearance()` 是 `NSView` 的生命周期方法，不是 `NSViewController` 可直接 override 的方法。
- 因此根控制器、列表控制器、编辑器控制器不能把该方法直接写在 `NSViewController` 子类中。
- 本次通过一个专门的 `macOSAppearanceAwareView` 把 `NSView` 的外观变化转发给控制器。

## 修改前

### 1. macOS 根视图只在创建时保存一次背景色

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift（修改前）
// 函数名: loadView()
// 功能说明: 创建根视图时直接把动态 windowBackgroundColor 转成静态 CGColor，之后没有外观刷新入口。
override func loadView() {
    let rootView = NSView()
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view = rootView
}
```

### 2. iOS Cell 的选中边框只按选中状态更新

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift（修改前）
// 函数名: updateSelectionAppearance()
// 功能说明: separator 等动态颜色直接转换为 CGColor；外观切换不会重新执行该逻辑。
private func updateSelectionAppearance() {
    contentView.backgroundColor = isSelected
        ? UIColor.systemBlue.withAlphaComponent(0.14)
        : UIColor.secondarySystemBackground
    contentView.layer.borderColor = (isSelected
        ? UIColor.systemBlue
        : UIColor.separator.withAlphaComponent(0.55)).cgColor
    contentView.layer.borderWidth = isSelected ? 2 : 1
}
```

### 3. 时间线刻度与文字在绘制时直接取当前 `.cgColor`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift（修改前）
// 函数名: renderRuler()
// 功能说明: 新建刻度和文字 layer 时直接保存静态 separator、secondaryLabel 颜色。
let tickLayer = CALayer()
tickLayer.backgroundColor = UIColor.separator.cgColor

let labelLayer = CATextLayer()
labelLayer.foregroundColor = UIColor.secondaryLabel.cgColor
```

macOS 时间线同样直接使用 `NSColor.separatorColor.cgColor` 和 `NSColor.secondaryLabelColor.cgColor`。

### 4. iOS Window 使用固定白色背景

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift（修改前）
// 函数名: application(_:didFinishLaunchingWithOptions:)
// 功能说明: Window 背景固定为白色，无法跟随系统深色外观。
window.backgroundColor = .white
```

### 5. 各组件各自管理 CATransaction

部分 Preview、MiniMap 和 Timeline 自行重复以下事务代码：

```swift
// 文件路径: 多个 Preview、MiniMap、Timeline 文件（修改前的通用模式）
// 函数名: performWithoutLayerActions(_:) 或 renderRuler()
// 功能说明: 各组件重复关闭隐式动画，但没有统一动态颜色解析入口。
CATransaction.begin()
CATransaction.setDisableActions(true)
updates()
CATransaction.commit()
```

## 修改后

### 1. 新增跨平台 layer 外观基础设施

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/PlatformLayerAppearance.swift（新增）
// 函数名: resolvedCGColor(_:for:)、performWithoutAnimations(_:)、macOSAppearanceAwareView 生命周期方法
// 功能说明: 按明确外观解析动态颜色，集中关闭 layer 隐式动画，并为 macOS 控制器转发 NSView 外观变化。
import QuartzCore

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PlatformLayerAppearance {
    #if os(macOS)
    static func resolvedCGColor(
        _ color: NSColor,
        for appearance: NSAppearance
    ) -> CGColor {
        var resolvedColor = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor
    }
    #elseif os(iOS)
    static func resolvedCGColor(
        _ color: UIColor,
        for traitCollection: UITraitCollection
    ) -> CGColor {
        color.resolvedColor(with: traitCollection).cgColor
    }
    #endif

    static func performWithoutAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}

#if os(macOS)
final class macOSAppearanceAwareView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onEffectiveAppearanceChange?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
#endif
```

实现要点：

- macOS 使用 `NSAppearance.performAsCurrentDrawingAppearance`，保证 `NSColor.cgColor` 在传入的具体 appearance 上下文中解析。
- iOS 使用 `UIColor.resolvedColor(with:)`，按当前 `UITraitCollection` 得到静态 `CGColor`。
- 统一通过 `CATransaction.setDisableActions(true)` 写入外观颜色，避免主题切换时出现 layer 隐式补间和闪烁。
- `macOSAppearanceAwareView` 同时覆盖首次挂载窗口和后续 effective appearance 改变。

### 2. macOS 控制器通过根 NSView 接收外观变化

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift（修改后）
// 函数名: loadView()、updateAppearance()
// 功能说明: 由 NSView 转发外观变化，重新解析根背景，并同步正在进行的转场载体。
override func loadView() {
    let rootView = macOSAppearanceAwareView()
    rootView.wantsLayer = true
    rootView.onEffectiveAppearanceChange = { [weak self] in
        self?.updateAppearance()
    }
    view = rootView
    updateAppearance()
}

private func updateAppearance() {
    let appearance = view.effectiveAppearance
    PlatformLayerAppearance.performWithoutAnimations {
        view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: appearance
        )
    }
    activeTransitionSession?.carrier.updateAppearance(appearance)
}
```

同一模式应用到：

- `macOSBoardListViewController`
- `macOSBoardCollectionItem`
- `macOSViewController`
- `macOSCanvasMarkdownEditorViewController`
- `macOSGIFFrameImportViewController`
- `macOSGIFFrameImportCollectionItem`
- `macOSVideoDisplayFrameEditorViewController`

### 3. macOS 转场中的临时快照壳同步外观

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift（修改后）
// 函数名: updateAppearance(_:)
// 功能说明: 缓存当前 appearance，并立即刷新转场 shell，避免主题切换时临时转场视图保持旧色。
func updateAppearance(_ appearance: NSAppearance) {
    currentAppearance = appearance
    guard let shellContentView else {
        return
    }

    PlatformLayerAppearance.performWithoutAnimations {
        shellContentView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: appearance
        )
    }
}
```

创建新的 shell 时，优先使用缓存 appearance，其次使用 overlay host 或 content view 的 effective appearance；转场结束时清空缓存。

### 4. macOS Toolbar 同时刷新容器和现有按钮

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift（修改后）
// 函数名: updateAppearance()、updateLayerAppearance(_:on:for:)
// 功能说明: 保存最近的 item state，主题切换时按原视觉角色重新解析每个已注册按钮的 layer 颜色。
private func updateAppearance() {
    let appearance = effectiveAppearance
    PlatformLayerAppearance.performWithoutAnimations {
        backgroundView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.controlBackgroundColor.withAlphaComponent(0.92),
            for: appearance
        )
        backgroundView.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.35),
            for: appearance
        )
        for itemState in latestItemStates {
            guard let button = registeredButtons[itemState.id] else {
                continue
            }
            updateLayerAppearance(itemState, on: button, for: appearance)
        }
    }
}
```

`latestItemStates` 的加入不是新业务状态；它仅用于在 appearance 改变时恢复按钮已有的视觉角色、启用状态和 disabled 保色规则。

### 5. iOS 视图在 trait 变化时重新解析 layer 颜色

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift（修改后）
// 函数名: didMoveToWindow()、traitCollectionDidChange(_:)、updateSelectionAppearance()
// 功能说明: 首次挂载和颜色外观变化时都刷新选中/未选中边框，且写入时关闭隐式动画。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateSelectionAppearance()
}

override func traitCollectionDidChange(
    _ previousTraitCollection: UITraitCollection?
) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.hasDifferentColorAppearance(
        comparedTo: traitCollection
    ) != false else {
        return
    }
    updateSelectionAppearance()
}

private func updateSelectionAppearance() {
    contentView.backgroundColor = isSelected
        ? UIColor.systemBlue.withAlphaComponent(0.14)
        : UIColor.secondarySystemBackground
    let borderColor = isSelected
        ? UIColor.systemBlue
        : UIColor.separator.withAlphaComponent(0.55)
    PlatformLayerAppearance.performWithoutAnimations {
        contentView.layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
            borderColor,
            for: traitCollection
        )
        contentView.layer.borderWidth = isSelected ? 2 : 1
    }
}
```

iOS 侧统一遵循：

- 初始化或 `didMoveToWindow()` 时建立正确初值。
- `traitCollectionDidChange(_:)` 只在颜色外观确实改变时刷新。
- `UIView.backgroundColor` 等本身支持动态颜色的属性继续保留动态 `UIColor`。
- 只有必须进入 Core Animation / Core Graphics 的颜色才显式解析成 `CGColor`。

### 6. iOS 手绘交互层在主题切换后重绘

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改后）
// 函数名: HandDrawingCanvasInteractionOverlayView.traitCollectionDidChange(_:)、drawSelection(in:)
// 功能说明: 外观变化时触发重绘，选择框的描边和填充按当前 traitCollection 解析。
override func traitCollectionDidChange(
    _ previousTraitCollection: UITraitCollection?
) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.hasDifferentColorAppearance(
        comparedTo: traitCollection
    ) != false else {
        return
    }
    setNeedsDisplay()
}

let accentColor = PlatformLayerAppearance.resolvedCGColor(
    .systemBlue,
    for: traitCollection
)
let accentFillColor = PlatformLayerAppearance.resolvedCGColor(
    UIColor.systemBlue.withAlphaComponent(0.08),
    for: traitCollection
)
context.setStrokeColor(accentColor)
context.setFillColor(accentFillColor)
```

这里不仅修复持久 layer 的边框，也覆盖 Core Graphics 即时绘制的套索、选区和路径颜色。

### 7. 双平台时间线在外观变化时重建 ruler layer

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift（修改后）
// 函数名: updateAppearance()、renderRuler()
// 功能说明: 重新解析轨道边框，并重建已经保存静态颜色的刻度及文字 layer。
private func updateAppearance() {
    PlatformLayerAppearance.performWithoutAnimations {
        trackView.layer.borderColor = PlatformLayerAppearance.resolvedCGColor(
            .separator,
            for: traitCollection
        )
    }
    renderRuler()
}

private func renderRuler() {
    let tickColor = PlatformLayerAppearance.resolvedCGColor(
        .separator,
        for: traitCollection
    )
    let labelColor = PlatformLayerAppearance.resolvedCGColor(
        .secondaryLabel,
        for: traitCollection
    )

    PlatformLayerAppearance.performWithoutAnimations {
        rulerTickLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        rulerLabelLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        // 后续新建的 CALayer 与 CATextLayer 分别使用 tickColor 和 labelColor。
    }
}
```

macOS 时间线采用相同策略，并额外刷新：

- 根时间线背景。
- track 背景和边框。
- playhead 与 handle 的系统红色。
- ruler tick 与 label。

### 8. 共享浮层按平台刷新动态 layer 色

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift（修改后，macOS 分支）
// 函数名: macOSCanvasInputIndicatorItemView.updateAppearance()
// 功能说明: 输入提示卡片背景和边框按 effectiveAppearance 重新解析。
private func updateAppearance() {
    PlatformLayerAppearance.performWithoutAnimations {
        backgroundView.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.controlBackgroundColor.withAlphaComponent(0.94),
            for: effectiveAppearance
        )
        backgroundView.layer?.borderColor = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.3),
            for: effectiveAppearance
        )
    }
}
```

同一共享文件的 iOS 分支通过 `traitCollectionDidChange(_:)` 更新 separator 边框。

`CanvasContextMenuHostView` 与 `SelectionAccessoryHostView` 的 macOS 分支把按钮颜色集中到 `applyAppearance`：

- 外观切换时遍历当前 state 对应的现有按钮。
- 保留 active、enabled、disabled 的业务语义。
- 只重新解析 active 背景等 layer 色，不重建业务状态。

### 9. iOS Window 改用系统动态背景

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift（修改后）
// 函数名: application(_:didFinishLaunchingWithOptions:)
// 功能说明: Window 背景从固定白色改为随系统外观变化的语义背景。
window.backgroundColor = .systemBackground
```

### 10. 新增动态颜色解析测试

```swift
// 文件路径: MyCanvas_Ver_0Tests/PlatformLayerAppearanceTests.swift（新增）
// 函数名: testWindowBackgroundResolvesAgainstProvidedAppearance()、testResolvedColorPreservesRequestedAlpha()
// 功能说明: 验证同一动态系统背景在 aqua/darkAqua 下解析结果不同，并验证解析后保留指定 alpha。
#if os(macOS)
import AppKit
import XCTest
@testable import MyCanvas_Ver_0

final class PlatformLayerAppearanceTests: XCTestCase {
    func testWindowBackgroundResolvesAgainstProvidedAppearance() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let lightColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: lightAppearance
        )
        let darkColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: darkAppearance
        )

        XCTAssertGreaterThan(
            try brightness(of: lightColor),
            try brightness(of: darkColor)
        )
    }

    func testResolvedColorPreservesRequestedAlpha() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let color = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.24),
            for: appearance
        )

        XCTAssertEqual(color.alpha, 0.24, accuracy: 0.001)
    }

    private func brightness(of color: CGColor) throws -> CGFloat {
        let convertedColor = try XCTUnwrap(
            NSColor(cgColor: color)?.usingColorSpace(.deviceRGB)
        )
        return convertedColor.brightnessComponent
    }
}
#endif
```

测试文件当前只在 macOS 编译分支中执行。iOS 分支通过 iOS Simulator 完整构建验证其 API 与调用点可编译，但本次没有新增独立 iOS XCTest。

## 文件级修改清单

### 基础设施与测试

- `MyCanvas_Ver_0/Platform/Shared/Rendering/PlatformLayerAppearance.swift`
  - 新增 macOS / iOS 动态颜色解析。
  - 新增统一无隐式动画事务。
  - 新增 macOS 控制器使用的 appearance-aware 根视图。
- `MyCanvas_Ver_0Tests/PlatformLayerAppearanceTests.swift`
  - 新增明暗背景解析差异测试。
  - 新增 alpha 保留测试。

### Shared

- `Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - macOS Context Menu 在挂载和 effective appearance 改变时刷新现有按钮。
- `Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift`
  - iOS 输入提示边框跟随 trait。
  - macOS 输入提示背景和边框跟随 effective appearance。
- `Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - macOS Selection Accessory 在 appearance 改变时刷新 active/disabled 按钮外观。

### iOS

- `Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - Cell 选中边框跟随 trait。
- `Platform/iOS/BoardList/iOSBoardPreviewView.swift`
  - occupancy fill/stroke 与预览边框统一刷新。
- `Platform/iOS/Canvas/iOSCanvasMiniMapView.swift`
  - occupancy、viewport 和外框颜色统一刷新。
- `Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift`
  - 编辑器浮层边框随 trait 刷新。
- `Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - Toolbar 浮层边框随 trait 刷新。
- `Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - 画布页边框刷新。
  - 手绘交互 overlay 在外观变化后重绘选择框和路径。
- `Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
  - 图层面板边框随 trait 刷新。
- `Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - 工具面板边框和颜色 swatch 选中边框随 trait 刷新。
- `Platform/iOS/iOSAppDelegate.swift`
  - Window 背景由 `.white` 改为 `.systemBackground`。
- `Platform/iOS/iOSGIFFrameImportViewController.swift`
  - GIF Cell 的选中/未选中边框随 trait 刷新。
- `Platform/iOS/iOSVideoTimelineView.swift`
  - track 边框和 ruler 的刻度、文字随 trait 刷新。

### macOS

- `Platform/macOS/AppRoot/macOSAppRootViewController.swift`
  - 根背景刷新并向活动转场传播 appearance。
- `Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
  - 转场 shell 缓存并刷新当前 appearance。
- `Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - Cell 背景、边框按选中状态和 appearance 共同刷新。
- `Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - 列表根背景随 appearance 刷新。
- `Platform/macOS/BoardList/macOSBoardPreviewView.swift`
  - Preview 的 occupancy 和外框刷新，并复用统一无动画事务。
- `Platform/macOS/Canvas/macOSCanvasMiniMapView.swift`
  - MiniMap 的 occupancy、viewport 和外框刷新。
- `Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift`
  - 文本编辑浮层背景和边框刷新。
- `Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - Toolbar 容器及所有现有按钮的 layer 色刷新。
- `Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift`
  - Markdown 编辑器根背景刷新。
- `Platform/macOS/macOSGIFFrameImportViewController.swift`
  - GIF 编辑器根背景、Cell 选中状态及 preview container 背景刷新。
- `Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
  - 视频帧编辑器根背景刷新。
- `Platform/macOS/macOSVideoTimelineView.swift`
  - 时间线根背景、track、playhead、刻度与文字刷新。
- `Platform/macOS/macOSViewController.swift`
  - Canvas 根背景、host 背景、返回按钮和工作区模式按钮刷新。

### 计划状态

```yaml
# 文件路径: .cursor/plans/cross-platform-dark-mode_18734292.plan.md（修改后）
# 函数名: YAML frontmatter.todos
# 功能说明: 代码实施及自动化验证完成后，将五个计划项从 pending 更新为 completed。
todos:
  - id: appearance-foundation
    status: completed
  - id: macos-appearance
    status: completed
  - id: ios-appearance
    status: completed
  - id: shared-overlays
    status: completed
  - id: verify-themes
    status: completed
```

## 保留不变的视觉边界

本次没有机械替换所有 `.cgColor`：

- 阴影使用的固定黑色仍保持固定效果色。
- 画布内容色、白纸语义、视频内容黑底等不应随系统主题变化的颜色保持不变。
- UIKit / AppKit 本身支持动态颜色的 `backgroundColor`、`textColor`、`contentTintColor` 等属性优先继续保存动态颜色对象。
- 修复重点是必须跨越到 `CALayer`、`CATextLayer` 或 Core Graphics 的动态系统语义色。

## 构建与测试结果

### macOS Debug 构建

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild ... -destination "platform=macOS" build
# 功能说明: 编译 macOS 分支、共享 helper、所有 macOS appearance 回调及调用点。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS" \
  build

** BUILD SUCCEEDED **
```

### iOS Simulator Debug 构建

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild ... -destination "generic/platform=iOS Simulator" build
# 功能说明: 编译 iOS 分支、traitCollection 调用点及 shared helper 的 UIKit 实现。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  build

** BUILD SUCCEEDED **
```

### 单元测试

专项 `PlatformLayerAppearanceTests` 两项均通过：

```text
# 文件路径: MyCanvas_Ver_0Tests/PlatformLayerAppearanceTests.swift
# 函数名: PlatformLayerAppearanceTests
# 功能说明: 记录新增外观解析测试的实际结果。
testResolvedColorPreservesRequestedAlpha() passed
testWindowBackgroundResolvesAgainstProvidedAppearance() passed
```

全量 macOS 测试命令已执行，但测试套件整体没有通过：

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test
# 功能说明: 记录全量测试的真实状态；不能把专项测试通过写成全量测试通过。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS"
```

全量运行中失败的是以下 9 项：

- `BoardHandDrawingStorageTests`
  - `testBoardStoreLoadHandDrawingSourceDataFallsBackToLegacyFlatAssets`
  - `testBoardStoreOverwritesHandDrawingAssetsAndRefreshesPersistedThumbnail`
  - `testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths`
  - `testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing`
  - `testBoardStoreSaveLoadAndCleanupPersistsHandDrawingAssets`
- `CanvasInputIndicatorQueueTests`
  - `testEnqueueKeepsNewestVisibleItems`
  - `testSnapshotAppliesFadeOutNearLifetimeEnd`
  - `testSnapshotPurgesExpiredEntries`
  - `testSnapshotUsesStackOpacityForOlderEntries`

这些失败不位于本次新增的颜色解析测试中；本次没有修改 `BoardHandDrawingStorage` 或 `CanvasInputIndicatorQueue` 的实现。记录仍明确保留“全量测试未通过”的状态，不将其写成成功。

### 静态检查

- `ReadLints` 检查本次 Platform 与测试文件，没有发现本次新增的 lint error。
- `git diff --check` 通过。
- 构建仍输出若干既有 warning，包括：
  - `macOSVideoTimelineView` 的 `copiesOnScroll` 废弃警告。
  - `macOSViewController` 的 Swift 6 actor-isolated `Equatable` 警告。
  - `iOSCanvasTextEditorOverlayView` 的 main actor 初始化警告。
  - App Intents metadata 未引用框架的提示。
- 对应 warning 所在代码不属于本次外观改动片段，本次没有顺带修改。

## 尚未完成的人工验证

自动化检查不能替代运行时视觉检查。当前仍需人工在真机或 Simulator/App 中确认：

- macOS App 运行时在浅色与深色之间来回切换。
- iOS App 运行时在浅色与深色之间来回切换。
- Board List、Canvas、MiniMap、Toolbar、文本编辑器、GIF、视频时间线和手绘界面均立即刷新。
- 切换期间没有错误的淡入淡出、边框补间或旧色残留。
- macOS Board List 到 Canvas 的转场进行中切换主题时，临时 shell 不残留旧背景。
- 复用 Cell 在选中/未选中状态下切换主题后仍保持正确状态。

因此，本记录结论是：代码实施、双平台编译、专项测试和静态检查已完成；完整运行时明暗模式视觉回归仍需人工确认。

## 最终结论

- 根因已从“逐点改固定颜色”收敛为“动态系统色进入 layer 前按当前外观显式解析，并在外观生命周期变化后统一重写”。
- macOS 使用 `effectiveAppearance` 与 `NSAppearance.performAsCurrentDrawingAppearance`。
- iOS 使用 `traitCollection` 与 `UIColor.resolvedColor(with:)`。
- layer 更新统一关闭隐式动画。
- 控制器、普通视图、复用 Cell、转场临时视图、时间线动态子 layer 和 Core Graphics 手绘 overlay 均建立了对应刷新入口。
- 未执行 Git 提交。
