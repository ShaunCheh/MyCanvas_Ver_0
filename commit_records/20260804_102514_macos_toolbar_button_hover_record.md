# 20260804_102514_macos_toolbar_button_hover_record

## 背景

本次修改为 macOS 侧边工具条按钮增加 hover 反馈。

鼠标进入可用按钮时，按钮背景色在当前深色或浅色外观下加深 `16%`；鼠标离开后恢复原色。禁用按钮不应用 hover 颜色变化。

本次修改基于已经存在的 `macOSCanvasToolbarButtonSlotView`：slot 继续负责按钮可见背景和边框，同时新增鼠标进入、离开状态追踪。没有修改按钮尺寸、工具条间距、命令 target/action 或 iOS 工具条。

## 时间戳来源

记录文件名使用系统 `date` 命令生成的时间戳。

```shell
# terminal - 获取本次记录使用的系统时间戳
date '+%Y%m%d_%H%M%S'
```

结果：

```text
# terminal - date 命令输出
20260804_102514
```

## 当前 changes

创建本记录前，当前未提交 changes 为：

```shell
# terminal - 查看本次 hover 修改涉及的文件
git status --short
```

结果：

```text
# terminal - 当前源码和测试 changes
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
```

## 修改前：slot 没有 hover 状态

修改前，`macOSCanvasToolbarButtonSlotView` 只负责固定按钮可见几何。它没有 `NSTrackingArea`，也没有鼠标进入和离开状态，因此按钮背景不会随鼠标位置变化。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarButtonSlotView：修改前只负责容纳按钮和同步 frame
private final class macOSCanvasToolbarButtonSlotView: NSView {
    let button: NSButton

    init(button: NSButton) {
        self.button = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }

    override func layout() {
        super.layout()
        button.frame = bounds
    }
}
```

修改前，按钮注册过程只创建 slot 并设置方形尺寸，没有把 hover 状态变化连接到 toolbar appearance。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.registerButtons(_:)：修改前没有 hover 回调
func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
    registeredButtons = buttons
    registeredButtonSlots = buttons.mapValues { button in
        let slot = macOSCanvasToolbarButtonSlotView(button: button)
        ensureSquareSize(for: slot)
        return slot
    }
}
```

修改前，`updateLayerAppearance` 只根据 enabled 状态和 visual role 选择基础背景色。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.updateLayerAppearance(_:on:for:)：修改前不读取 hover 状态
let preservesVisualRole =
    itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
let resolvedBackgroundColor = preservesVisualRole
    ? backgroundColor(for: itemState.visualRole)
    : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)

slot.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
    resolvedBackgroundColor,
    for: appearance
)
```

## 修改后：slot 统一追踪鼠标进入和离开

`macOSCanvasToolbarButtonSlotView` 新增：

- `isHovered`：保存当前 hover 状态。
- `hoverTrackingArea`：保存当前 `NSTrackingArea`。
- `onHoverChange`：把状态变化通知给 toolbar host。
- `updateTrackingAreas()`：使用 `.mouseEnteredAndExited`、`.activeInKeyWindow` 和 `.inVisibleRect` 建立追踪区域。
- `mouseEntered(with:)` / `mouseExited(with:)`：更新 hover 状态。
- `viewDidMoveToWindow()`：slot 离开 window 时清除 hover，防止隐藏或移除后残留高亮。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarButtonSlotView：统一管理 toolbar button hover 状态
private final class macOSCanvasToolbarButtonSlotView: NSView {
    let button: NSButton
    var onHoverChange: ((Bool) -> Void)?
    private(set) var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            setHovered(false)
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else {
            return
        }
        isHovered = hovered
        onHoverChange?(hovered)
    }
}
```

## 修改后：注册阶段连接 hover 与 appearance

`registerButtons(_:)` 现在按 `CanvasToolbarItemID` 创建 slot，并设置弱引用回调。

hover 状态变化后，host 根据对应 item 的最新 `CanvasToolbarItemState` 刷新该 slot，避免复制或绕过原有 enabled、visual role 和 appearance 逻辑。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.registerButtons(_:)：连接 slot hover 与对应 item appearance
func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
    registeredButtons = buttons
    registeredButtonSlots = Dictionary(
        uniqueKeysWithValues: buttons.map { itemID, button in
            let slot = macOSCanvasToolbarButtonSlotView(button: button)
            ensureSquareSize(for: slot)
            slot.onHoverChange = { [weak self, weak slot] _ in
                guard let self, let slot else {
                    return
                }
                self.updateHoverAppearance(for: itemID, on: slot)
            }
            return (itemID, slot)
        }
    )
}
```

## 修改后：基于当前外观加深背景

hover 加深比例集中定义为 `0.16`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.Layout：统一 hover 加深比例
private enum Layout {
    static let buttonHoverDarkeningFraction: CGFloat = 0.16
}
```

`updateLayerAppearance` 先计算原有基础颜色。只有 `itemState.isEnabled == true` 且 `slot.isHovered == true` 时才使用加深后的颜色；禁用按钮继续显示原禁用色。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.updateLayerAppearance(_:on:for:)：合并 enabled 与 hover 状态
let preservesVisualRole =
    itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
let baseBackgroundColor = preservesVisualRole
    ? backgroundColor(for: itemState.visualRole)
    : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
let resolvedBackgroundColor =
    itemState.isEnabled && slot.isHovered
        ? darkenedBackgroundColor(
            baseBackgroundColor,
            for: appearance
        )
        : baseBackgroundColor

slot.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
    resolvedBackgroundColor,
    for: appearance
)
```

`darkenedBackgroundColor(_:for:)` 先在当前 `NSAppearance` 下解析动态系统色，再转换到 device RGB 与黑色混合。这样 `.controlAccentColor`、`.controlBackgroundColor` 及其他动态颜色在深色和浅色模式下都从当前实际颜色出发。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.darkenedBackgroundColor(_:for:)：按当前外观生成 hover 色
private func darkenedBackgroundColor(
    _ color: NSColor,
    for appearance: NSAppearance
) -> NSColor {
    var resolvedColor = color
    appearance.performAsCurrentDrawingAppearance {
        resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
    }
    return resolvedColor.blended(
        withFraction: Layout.buttonHoverDarkeningFraction,
        of: .black
    ) ?? resolvedColor
}
```

hover 刷新继续通过 `PlatformLayerAppearance.performWithoutAnimations` 写入 layer，避免触发非预期的 Core Animation 隐式动画。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.updateHoverAppearance(for:on:)：刷新单个 hover slot
private func updateHoverAppearance(
    for itemID: CanvasToolbarItemID,
    on slot: macOSCanvasToolbarButtonSlotView
) {
    guard let itemState = latestItemStates.first(where: { $0.id == itemID }) else {
        return
    }
    PlatformLayerAppearance.performWithoutAnimations {
        updateLayerAppearance(
            itemState,
            on: slot,
            for: effectiveAppearance
        )
    }
}
```

## 新增回归测试

### 可用按钮 hover

新增 `testEnabledButtonDarkensOnHoverAndRestoresOnExit()`：

- 记录正常状态背景色。
- 模拟 `.mouseEntered`。
- 验证 hover 背景亮度低于正常背景。
- 模拟 `.mouseExited`。
- 验证背景恢复为原始颜色。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
// macOSCanvasToolbarHostViewTests.testEnabledButtonDarkensOnHoverAndRestoresOnExit()
let slot = try XCTUnwrap(button.superview)
let regularBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
let enteredEvent = try XCTUnwrap(
    makeToolbarHoverTestEvent(type: .mouseEntered)
)
slot.mouseEntered(with: enteredEvent)
let hoveredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)

// 可用按钮 hover 后背景亮度必须降低。
XCTAssertLessThan(
    toolbarHoverTestLuminance(hoveredBackgroundColor),
    toolbarHoverTestLuminance(regularBackgroundColor)
)

let exitedEvent = try XCTUnwrap(
    makeToolbarHoverTestEvent(type: .mouseExited)
)
slot.mouseExited(with: exitedEvent)
let restoredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
XCTAssertEqual(restoredBackgroundColor, regularBackgroundColor)
```

### 禁用按钮 hover

新增 `testDisabledButtonDoesNotChangeBackgroundOnHover()`，验证 disabled 按钮收到 mouse entered 后仍保持原背景色。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
// macOSCanvasToolbarHostViewTests.testDisabledButtonDoesNotChangeBackgroundOnHover()
let slot = try XCTUnwrap(button.superview)
let regularBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
let enteredEvent = try XCTUnwrap(
    makeToolbarHoverTestEvent(type: .mouseEntered)
)
slot.mouseEntered(with: enteredEvent)
let hoveredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)

// 禁用按钮不显示 hover 反馈，继续保持禁用背景色。
XCTAssertEqual(hoveredBackgroundColor, regularBackgroundColor)
```

## 修改前后行为对比

修改前：

- 工具条按钮 slot 不追踪鼠标进入和离开。
- 正常、hover 状态使用同一背景色。
- enabled 和 disabled 按钮都没有 hover 视觉反馈。

修改后：

- key window 中可见 slot 使用 `NSTrackingArea` 追踪鼠标。
- 可用按钮 hover 时，当前背景色加深 `16%`。
- 鼠标移出后恢复基础背景色。
- 禁用按钮背景不随 hover 改变。
- slot 离开 window 时主动清除 hover 状态。
- 深色、浅色模式分别基于当前解析后的系统颜色计算 hover 色。
- 按钮尺寸、相邻间距、图标、点击行为和 toolbar transition 入口保持不变。

## 验证结果

### Lints

检查以下文件，没有发现 linter errors：

```text
# Cursor ReadLints - 本次检查范围
MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift

No linter errors found.
```

### hover 与间距回归测试

```shell
# terminal - 运行 macOS toolbar host 全部几何与 hover 回归测试
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests
```

结果：测试通过，命令退出码为 `0`。

### macOS build

```shell
# terminal - 验证 hover 修改后的 macOS 工程可以完整编译
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS'
```

结果：build 通过，命令退出码为 `0`。

### Diff 格式检查

```shell
# terminal - 检查当前源码与测试 diff 的空白格式
git diff --check
```

结果：无输出，命令退出码为 `0`。

## 提交状态

本次只修改 hover 实现、补充测试并创建本记录，没有执行 `git commit`。
