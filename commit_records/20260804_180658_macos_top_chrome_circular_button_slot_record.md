# 20260804_180658_macos_top_chrome_circular_button_slot_record

## 记录范围

本记录如实描述刚刚针对 macOS 画布顶部按钮非圆形问题的根因修复。

修复对象：

- 左上角返回按钮。
- 右上角 Group 列表按钮。
- 右上角阅读/编辑模式切换按钮。

本次修复不再直接让 `NSButton.layer` 承担可见背景，而是复用侧边工具栏已经验证过的 slot 模式：固定尺寸的普通 `NSView` 负责布局与可见 chrome，透明 `NSButton` 只负责图标、辅助功能和事件传递。

本次只修改 macOS UI 与对应测试，没有修改 iOS、画布业务数据、history、autosave 或持久化逻辑，也没有执行 Git commit。

## 时间戳与 changes 依据

文件名时间戳来自系统自带 `date` 命令：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: date '+%Y%m%d_%H%M%S'
20260804_180658
```

创建本记录前的工作区状态：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: git status --short
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
```

当前 diff 统计：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: git diff --stat
.../Canvas/macOSCanvasChromeOverlayView.swift     | 104 +++++++++++++++
.../macOS/Canvas/macOSCanvasToolbarHostView.swift |  93 ++------------
.../Platform/macOS/macOSViewController.swift      | 139 +++++++++++++--------
.../macOSCanvasToolbarHostViewTests.swift         |  43 +++++++
4 files changed, 244 insertions(+), 135 deletions(-)
```

`git diff --check` 没有输出，说明当前 changes 不包含空白错误。

## 问题根因

截图中的返回按钮实际呈现为纵向拉长的圆角胶囊，而不是圆形。

macOS Auto Layout 使用 `NSButton` 的 alignment rect 参与约束计算，但原实现把背景色、边框和圆角画在完整 `NSButton.layer` 上。`44 × 44` 约束保证的是 alignment rect，并不保证实际 layer bounds 也是 `44 × 44`。当完整 frame 因 AppKit alignment insets 变成非正方形后，固定 `cornerRadius = 22` 只能得到胶囊形状。

因此，单纯继续增大 `cornerRadius` 无法根治问题；只要可见背景仍然依赖非正方形的 `NSButton.layer`，布局和视觉几何就仍然不一致。

## 修改 1：抽取共享 macOS chrome button slot

### 修改前

侧边工具栏已经有一个私有 `macOSCanvasToolbarButtonSlotView`，通过普通 `NSView` 隔离 `NSButton` alignment rect，但该类型只能在工具栏文件内部使用，也只支持固定圆角。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 类型/函数名: macOSCanvasToolbarButtonSlotView.init(button:)
// 修改前说明: slot 是工具栏私有类型，其他 macOS chrome 按钮无法复用。
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
}
```

### 修改后

将 slot 能力抽到 `macOSCanvasChromeOverlayView.swift`，形成可被侧边工具栏和顶部 chrome 共用的 `macOSCanvasChromeButtonSlotView`。

它提供两种圆角语义：

- `.fixed(CGFloat)`：保持侧边工具栏现有圆角值。
- `.circular`：在每次布局时根据真实 bounds 动态计算半径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 类型/函数名: macOSCanvasChromeButtonCornerStyle / macOSCanvasChromeButtonSlotView.layout()
// 功能说明: slot 独立拥有可见 chrome，并按实际 bounds 计算固定圆角或圆形半径。
enum macOSCanvasChromeButtonCornerStyle {
    case fixed(CGFloat)
    case circular
}

final class macOSCanvasChromeButtonSlotView: NSView {
    let button: NSButton
    var cornerStyle: macOSCanvasChromeButtonCornerStyle

    override func layout() {
        super.layout()
        button.frame = bounds
        switch cornerStyle {
        case let .fixed(cornerRadius):
            layer?.cornerRadius = max(cornerRadius, 0)
        case .circular:
            layer?.cornerRadius = max(
                min(bounds.width, bounds.height) / 2,
                0
            )
        }
    }
}
```

初始化时会主动清除 `NSButton.layer` 的背景、边框和圆角，并让按钮通过 frame/autoresizing 精确填满 slot：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数名: macOSCanvasChromeButtonSlotView.init(button:cornerStyle:)
// 功能说明: NSButton 不再参与 chrome 几何，只负责图标、辅助功能与事件。
button.translatesAutoresizingMaskIntoConstraints = true
button.autoresizingMask = [.width, .height]
button.isBordered = false
button.wantsLayer = true
button.layer?.backgroundColor = NSColor.clear.cgColor
button.layer?.borderWidth = 0
button.layer?.cornerRadius = 0
addSubview(button)
```

原工具栏 slot 的 hover tracking、移出窗口重置和回调能力也一起迁入共享类型，没有删除既有 hover 行为。

## 修改 2：侧边工具栏改用共享 slot

### 修改前

`macOSCanvasToolbarHostView` 直接构造文件内私有的 toolbar slot，并在应用按钮样式时设置固定圆角。

### 修改后

工具栏注册按钮时改为构造共享 slot，并显式选择 `.fixed(Layout.buttonCornerRadius)`，因此侧边工具栏仍保留原有圆角、尺寸、间距和 hover 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: macOSCanvasToolbarHostView.registerButtons(_:)
// 功能说明: 侧边工具栏复用共享 slot，但继续使用原固定圆角。
let slot = macOSCanvasChromeButtonSlotView(
    button: button,
    cornerStyle: .fixed(Layout.buttonCornerRadius)
)
ensureSquareSize(for: slot)
```

工具栏原有 `registeredButtonSlots`、hover appearance 和 square-size 逻辑只替换类型名，没有改变 toolbar state、按钮角色或交互命令。

## 修改 3：顶部三个按钮由圆形 slot 承载

### 修改前

三个顶部按钮都直接设置 `NSButton.layer.cornerRadius = 22`，并把背景和边框画在按钮自身 layer 上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 属性/函数名: backButton 初始化闭包
// 修改前说明: 44 × 44 约束作用于 alignment rect，可见背景却画在完整 NSButton.layer。
private let backButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.wantsLayer = true
    button.layer?.cornerRadius = 22
    button.layer?.masksToBounds = true
    button.layer?.borderWidth = 1
    return button
}()
```

### 修改后

返回、Group 和模式切换按钮分别创建 `.circular` slot。slot 承担背景、边框和裁剪，原 `NSButton` 通过计算属性继续供 target/action、图标和 tooltip 代码使用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 属性/函数名: backButtonSlot / backButton
// 功能说明: 固定正方形 slot 绘制圆形，透明按钮精确填满 slot。
private let backButtonSlot: macOSCanvasChromeButtonSlotView = {
    let button = NSButton()
    button.isBordered = false
    button.title = ""
    button.toolTip = "Back to board list"

    let slot = macOSCanvasChromeButtonSlotView(
        button: button,
        cornerStyle: .circular
    )
    slot.layer?.masksToBounds = true
    slot.layer?.borderWidth = 1
    return slot
}()

private var backButton: NSButton {
    backButtonSlot.button
}
```

三个 slot 都由 Auto Layout 直接约束为真实的 `44 × 44`：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupConstraints()
// 功能说明: 约束普通 NSView slot，而不是 NSButton alignment rect。
backButtonSlot.widthAnchor.constraint(equalToConstant: 44)
backButtonSlot.heightAnchor.constraint(equalToConstant: 44)
workspaceModeButtonSlot.widthAnchor.constraint(equalToConstant: 44)
workspaceModeButtonSlot.heightAnchor.constraint(equalToConstant: 44)
groupListButtonSlot.widthAnchor.constraint(equalToConstant: 44)
groupListButtonSlot.heightAnchor.constraint(equalToConstant: 44)
```

## 修改 4：所有视觉与布局语义统一切换到 slot

为了避免只修复外观、却留下 blocker 或锚点继续使用错误 button frame，本次同步调整了以下路径：

- `updateAppearance()`：背景和边框颜色应用到三个 slot。
- `setupChromeHierarchy()`：挂载 slot，不再直接挂载按钮。
- `setupConstraints()`：安全区定位、按钮间距和 Group 面板锚点全部基于 slot。
- `baseChromeBlockersForToolbarLayout()`：toolbar placement blocker 使用 slot frame。
- `updateGroupListPresentation()`：Group 展开/收起背景状态绘制在 Group slot。
- `collapseGroupListForOutsidePointerIfNeeded()`：Group 按钮外部点击判断使用 slot bounds。
- 模式切换失败的 shake 动画：动画对象改为整个模式 slot。
- chrome layout diagnostics：记录 slot frame，而不是内部按钮 frame。

代表性的 blocker 修正：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: baseChromeBlockersForToolbarLayout()
// 功能说明: toolbar 避让区域与用户实际看到的圆形 slot 几何保持一致。
appendChromeBlocker(
    kind: .backButton,
    for: backButtonSlot,
    to: &chromeBlockers
)
appendChromeBlocker(
    kind: .modeToggle,
    for: workspaceModeButtonSlot,
    to: &chromeBlockers
)
appendChromeBlocker(
    kind: .groupList,
    for: groupListButtonSlot,
    to: &chromeBlockers
)
```

## 修改 5：新增几何回归测试

新增测试使用一个故意返回非零 `alignmentRectInsets` 的 `NSButton`，验证 slot 不受按钮 alignment rect 影响：

```swift
// 文件路径: MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests.swift
// 函数名: testCircularChromeSlotIgnoresButtonAlignmentRectInsets()
// 功能说明: 44 × 44 slot 必须产生 22pt 圆角，内部按钮 frame 必须等于 slot bounds。
let button = macOSCanvasAlignmentInsetTestButton()
let slot = macOSCanvasChromeButtonSlotView(
    button: button,
    cornerStyle: .circular
)
slot.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
slot.layoutSubtreeIfNeeded()

XCTAssertEqual(slot.bounds.size, CGSize(width: 44, height: 44))
XCTAssertEqual(button.frame, slot.bounds)
XCTAssertEqual(
    try XCTUnwrap(slot.layer?.cornerRadius),
    22,
    accuracy: 0.001
)
```

同时新增 `testFixedChromeSlotKeepsToolbarCornerRadius()`，确保共享抽取后侧边工具栏的固定圆角语义没有被 `.circular` 逻辑污染。

## 验证结果

### macOS slot 与工具栏回归测试

```shell
# 文件路径: 无（终端命令）
# 函数/命令: xcodebuild test；验证圆形 slot、固定圆角、间距和 hover
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:"MyCanvas_Ver_0Tests/macOSCanvasToolbarHostViewTests"
```

结果：退出码为 `0`，以下 5 条测试全部通过：

- `testCircularChromeSlotIgnoresButtonAlignmentRectInsets`
- `testFixedChromeSlotKeepsToolbarCornerRadius`
- `testVerticalButtonsUseUniformVisibleFramesAndSpacing`
- `testEnabledButtonDarkensOnHoverAndRestoresOnExit`
- `testDisabledButtonDoesNotChangeBackgroundOnHover`

### macOS 构建

```shell
# 文件路径: 无（终端命令）
# 函数/命令: xcodebuild build；验证 macOS 顶部 chrome 与共享 slot 编译集成
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS,arch=arm64"
```

结果：`BUILD SUCCEEDED`，命令退出码为 `0`。

### 静态检查

- 4 个本次修改文件的 IDE diagnostics 均无 linter error。
- `git diff --check` 通过。
- 当前 changes 仅包含本次 macOS slot 修复、测试和本记录文件。
