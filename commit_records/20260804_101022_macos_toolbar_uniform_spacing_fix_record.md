# 20260804_101022_macos_toolbar_uniform_spacing_fix_record

## 背景

本次修改修复 macOS 侧边工具条中按钮可见间距不一致的问题。

修改前，`NSStackView` 直接排列 `NSButton`。虽然代码为按钮设置了统一尺寸和统一 `spacing`，但 AppKit 使用按钮的 alignment rect 参与布局，而按钮背景、边框和圆角绘制在完整的 `NSButton.layer` 上。布局矩形与实际可见绘制矩形不一致，导致按钮背景侵入 stack 的逻辑间距，最终出现可见间隙不均匀。

本次采用结构性修复：让零 alignment inset 的普通 `NSView` slot 参与 stack 布局并承载可见 chrome，`NSButton` 只负责图标和点击事件。

## 时间戳来源

记录文件名开头使用系统 `date` 命令生成的时间戳。

```shell
# terminal - 获取本记录使用的系统时间戳
date '+%Y%m%d_%H%M%S'
```

结果：

```text
# terminal - date 命令输出
20260804_101022
```

## 当前 changes

创建本记录前，工作区中与本次修复相关的 changes 为：

```shell
# terminal - 查看当前未提交变更
git status --short
```

结果：

```text
# terminal - 本次源码和测试变更
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
?? MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
```

没有修改 iOS 工具条实现，也没有修改 shared toolbar metrics。

## 修改前：NSButton 直接参与 stack 布局

修改前，`registerButtons(_:)` 直接把固定宽高约束加在 `NSButton` 上。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.registerButtons(_:)：修改前由 NSButton 自身承担布局尺寸
func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
    registeredButtons = buttons
    buttons.values.forEach { button in
        ensureSquareSize(for: button)
    }
}
```

`syncButtons(with:)` 也直接将按钮作为 `NSStackView` 的 arranged subview。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.syncButtons(with:)：修改前 stack 直接排列 NSButton
let orderedButtons: [NSButton] = itemStates.compactMap { itemState in
    guard let button = registeredButtons[itemState.id] else {
        return nil
    }
    applyAppearance(itemState, to: button)
    return button
}

orderedButtons.forEach { button in
    buttonsStackView.addArrangedSubview(button)
}
```

按钮背景、边框和圆角直接绘制在 `NSButton.layer` 上，因此可见边界使用的是按钮完整 frame，而 stack 间距基于 AppKit alignment rect。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.applyAppearance(_:to:)：修改前可见 chrome 位于 NSButton.layer
button.wantsLayer = true
button.layer?.cornerRadius = Layout.buttonCornerRadius
button.layer?.borderWidth = 1
PlatformLayerAppearance.performWithoutAnimations {
    updateLayerAppearance(
        itemState,
        on: button,
        for: effectiveAppearance
    )
}
```

## 修改后：使用固定方形 slot 统一布局与绘制几何

新增 `macOSCanvasToolbarButtonSlotView`。该 slot 是普通 `NSView`，负责参与 stack 布局和承载按钮背景；内部 `NSButton` 使用 autoresizing 精确填满 slot，不再通过 Auto Layout alignment rect 决定工具条间距。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarButtonSlotView：隔离 NSButton alignment rect，统一可见 frame
private final class macOSCanvasToolbarButtonSlotView: NSView {
    let button: NSButton

    init(button: NSButton) {
        self.button = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // NSButton 只负责图标绘制和事件投递，不参与 stack 的尺寸计算。
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        button.frame = bounds
    }
}
```

`registerButtons(_:)` 现在为每个按钮创建独立 slot，并把固定方形约束加在 slot 上。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.registerButtons(_:)：注册按钮及其固定尺寸 slot
func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
    registeredButtons = buttons
    registeredButtonSlots = buttons.mapValues { button in
        let slot = macOSCanvasToolbarButtonSlotView(button: button)
        ensureSquareSize(for: slot)
        return slot
    }
}
```

`syncButtons(with:)` 改为排列 slot。按钮顺序和原有 `CanvasToolbarItemState` 顺序保持不变。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.syncButtons(with:)：stack 改为排列零 inset 的 slot
let orderedButtonSlots: [macOSCanvasToolbarButtonSlotView] = itemStates.compactMap { itemState in
    guard
        let button = registeredButtons[itemState.id],
        let slot = registeredButtonSlots[itemState.id]
    else {
        return nil
    }
    applyAppearance(itemState, to: button, in: slot)
    return slot
}

orderedButtonSlots.forEach { slot in
    buttonsStackView.addArrangedSubview(slot)
}
```

按钮本身的 layer 改为透明且无边框；背景、边框、圆角和深浅色外观全部迁移至 slot layer。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.applyAppearance(_:to:in:)：可见 chrome 由 slot 统一承载
button.wantsLayer = true
button.layer?.backgroundColor = NSColor.clear.cgColor
button.layer?.borderWidth = 0
slot.layer?.cornerRadius = Layout.buttonCornerRadius
slot.layer?.borderWidth = 1
PlatformLayerAppearance.performWithoutAnimations {
    updateLayerAppearance(
        itemState,
        on: slot,
        for: effectiveAppearance
    )
}
```

尺寸约束也从 `NSButton` 转移至 slot。当前 macOS scale 为 `0.5`，因此每个 slot 的边长为 `22pt`，stack spacing 为 `6pt`。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// macOSCanvasToolbarHostView.ensureSquareSize(for:)：约束 stack 实际排列的 slot
private func ensureSquareSize(for slot: macOSCanvasToolbarButtonSlotView) {
    if slot.constraints.contains(where: {
        $0.identifier == "canvasToolbarHost.buttonWidth"
    }) == false {
        let widthConstraint = slot.widthAnchor.constraint(
            equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge
        )
        widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
        widthConstraint.isActive = true
    }

    if slot.constraints.contains(where: {
        $0.identifier == "canvasToolbarHost.buttonHeight"
    }) == false {
        let heightConstraint = slot.heightAnchor.constraint(
            equalToConstant: macOSCanvasToolbarChromeMetrics.buttonEdge
        )
        heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
        heightConstraint.isActive = true
    }
}
```

## 新增回归测试

新增 `macOSCanvasToolbarHostViewTests`，使用 undo、multi-select、save、import 四种不同 toolbar item 创建侧边工具条。

测试读取按钮转换到 host 坐标系后的真实可见 frame，验证：

- 所有按钮宽度都等于 `macOSCanvasToolbarChromeMetrics.buttonEdge`。
- 所有按钮高度都等于 `macOSCanvasToolbarChromeMetrics.buttonEdge`。
- 任意相邻按钮之间的间距都等于 `macOSCanvasToolbarChromeMetrics.spacing`。

```swift
// MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
// macOSCanvasToolbarHostViewTests.testVerticalButtonsUseUniformVisibleFramesAndSpacing()
let visibleButtonFrames = itemIDs.compactMap { itemID -> CGRect? in
    guard let button = buttonsByID[itemID] else {
        return nil
    }
    return hostView.convert(button.bounds, from: button)
}

for frame in visibleButtonFrames {
    // 所有按钮使用相同的可见宽高，而不只是相同的 alignment rect。
    XCTAssertEqual(
        frame.width,
        macOSCanvasToolbarChromeMetrics.buttonEdge,
        accuracy: 0.001
    )
    XCTAssertEqual(
        frame.height,
        macOSCanvasToolbarChromeMetrics.buttonEdge,
        accuracy: 0.001
    )
}

let verticallyOrderedFrames = visibleButtonFrames.sorted {
    $0.minY < $1.minY
}
for (currentFrame, nextFrame) in zip(
    verticallyOrderedFrames,
    verticallyOrderedFrames.dropFirst()
) {
    // 验证每一对相邻按钮的真实可见间距完全一致。
    XCTAssertEqual(
        nextFrame.minY - currentFrame.maxY,
        macOSCanvasToolbarChromeMetrics.spacing,
        accuracy: 0.001
    )
}
```

## 修改前后行为对比

修改前：

- stack 直接排列 `NSButton`。
- 尺寸约束作用于按钮的 alignment rect。
- 可见背景绘制在完整按钮 frame 上。
- 逻辑 spacing 统一，但可见按钮背景会侵入间距，截图中间隙不一致。

修改后：

- stack 排列固定尺寸的普通 `NSView` slot。
- slot 的布局矩形就是可见背景矩形。
- `NSButton` 精确填满 slot，只处理图标和点击。
- 所有可见按钮均为 `22×22pt`，任意相邻按钮间距均为 `6pt`。
- 按钮顺序、命令 target/action、启用状态、颜色角色和 toolbar transition 入口保持不变。

## 验证结果

### Lints

检查修改后的源码和新增测试，未发现 linter errors。

```text
# Cursor ReadLints - 检查 macOS toolbar host 和对应测试
No linter errors found.
```

### macOS build

```shell
# terminal - 验证 macOS 工程可以完整编译
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS'
```

结果：build 通过，命令退出码为 `0`。

### 工具条几何回归测试

```shell
# terminal - 只运行 macOS 侧边工具条可见尺寸和间距回归测试
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests
```

结果：测试通过，命令退出码为 `0`。

### Diff 格式检查

```shell
# terminal - 检查当前 diff 中的空白和格式问题
git diff --check
```

结果：无输出，命令退出码为 `0`。

## 提交状态

本次只修改源码、增加测试并创建本记录，没有执行 `git commit`。
