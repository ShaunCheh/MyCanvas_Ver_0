# 20260319_150223_canvas_toolbar_phase_b1_structure_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段B-阶段1` 的实际代码变更。
- 本次实际产物：
- 新增共享停靠枚举 `CanvasToolbarDockEdge`。
- `iOS` 侧将原先混在一个按钮栈中的 `主工具栏按钮` 与 `history 按钮` 做代码结构拆分。
- `macOS` 侧建立统一的 `toolbarDockEdge` 与 `toolbarButtonsStackView` 入口。
- 本次未执行：
- 未引入 `ToolbarHostView` 外壳。
- 未把按钮改成最终的纯图标正方形视觉。
- 未实现四边约束切换。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/Shared/CanvasToolbarDockEdge.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 共享层没有工具栏停靠枚举，`iOS` 与 `macOS` 都没有统一的 `dock edge` 入口。
- `iOS` 只有一个 `controlsStackView`，同时承载 `crop -> undo -> redo -> save -> import` 五个按钮。
- `iOS` 的 `chromeOccupiedRects()` 只把这一个大按钮栈当成 blocker，没有为未来“主工具栏”和“history 组”拆分预留结构。
- `macOS` 只有一个 `controlsStackView`，承载 `crop -> save -> import` 三个按钮，也没有显式的停靠枚举入口。

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.controlsStackView / setupViewHierarchy() / setupConstraints() / chromeOccupiedRects()
// 功能说明: 修改前 iOS 只有一个 controlsStackView，同时承载主工具栏按钮与 history 按钮，并且 overlay 只把这一组 frame 当作 blocker。
private let controlsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private func setupViewHierarchy() {
    // ... 省略与本次 B1 无关的视图挂载代码
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    // ... 省略与本次 B1 无关的约束
    controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: controlsStackView, to: &rects)
    return rects
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.controlsStackView / setupViewHierarchy() / setupConstraints() / chromeOccupiedRects()
// 功能说明: 修改前 macOS 只有一个 controlsStackView，承载三按钮工具栏，且没有统一的 dock edge 入口。
private let controlsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private func setupViewHierarchy() {
    // ... 省略与本次 B1 无关的视图挂载代码
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    // ... 省略与本次 B1 无关的约束
    controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: controlsStackView, to: &rects)
    return rects
}
```

## 修改后

- 共享层新增 `CanvasToolbarDockEdge`，统一表达 `top / bottom / leading / trailing` 四个停靠位，并提供按钮横纵排布偏好。
- `iOS` 新增 `toolbarButtonsStackView` 与 `historyButtonsStackView`，将主工具栏按钮和 history 按钮从结构上拆开。
- `iOS` 新增 `toolbarButtons`、`historyButtons`、`installToolbarButtons()`、`installHistoryButtons()`、`updatePreparedToolbarDockEdge()`，为后续 `B2/B3/B4` 预留稳定接口。
- `iOS` 的 `chromeOccupiedRects()` 现在分别上报 `historyButtonsStackView` 和 `toolbarButtonsStackView`。
- `macOS` 新增 `toolbarDockEdge`、`toolbarButtonsStackView`、`toolbarButtons`、`installToolbarButtons()`、`updatePreparedToolbarDockEdge()`，把停靠入口和工具栏按钮组组织方式统一到和 `iOS` 同一层级。
- `macOS` 的 `chromeOccupiedRects()` 现在上报 `toolbarButtonsStackView`，不再依赖旧的 `controlsStackView` 命名。

### 共享停靠枚举新增代码

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasToolbarDockEdge.swift
// 函数名/类型名: CanvasToolbarDockEdge / prefersHorizontalButtonLayout
// 功能说明: B1 新增共享停靠枚举，先把工具栏停靠位和横纵排布偏好收口到跨平台共享层。
import Foundation

enum CanvasToolbarDockEdge: CaseIterable {
    case top
    case bottom
    case leading
    case trailing

    var prefersHorizontalButtonLayout: Bool {
        switch self {
        case .top, .bottom:
            return true
        case .leading, .trailing:
            return false
        }
    }
}
```

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.toolbarDockEdge / toolbarButtonsStackView / historyButtonsStackView / installToolbarButtons() / installHistoryButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B1 将 iOS 的主工具栏按钮与 history 按钮拆成两个直接挂在 chromeOverlayView 上的组，并为后续停靠方向切换预留入口。
private var toolbarDockEdge: CanvasToolbarDockEdge = .trailing {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarDockEdge()
    }
}
private let toolbarButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()
private let historyButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private var toolbarButtons: [UIButton] {
    [cropButton, saveButton, importButton]
}

private var historyButtons: [UIButton] {
    [undoButton, redoButton]
}

private func setupViewHierarchy() {
    // ... 省略与本次 B1 无关的视图挂载代码
    chromeOverlayView.addSubview(historyButtonsStackView)
    chromeOverlayView.addSubview(toolbarButtonsStackView)
    installHistoryButtons()
    installToolbarButtons()
}

private func installToolbarButtons() {
    toolbarButtons.forEach { button in
        toolbarButtonsStackView.addArrangedSubview(button)
    }
}

private func installHistoryButtons() {
    historyButtons.forEach { button in
        historyButtonsStackView.addArrangedSubview(button)
    }
}

private func updatePreparedToolbarDockEdge() {
    // 这里只切换主工具栏按钮的排布方向，history 组仍维持当前纵向结构。
    toolbarButtonsStackView.axis = toolbarDockEdge.prefersHorizontalButtonLayout
        ? .horizontal
        : .vertical
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: historyButtonsStackView, to: &rects)
    appendChromeOccupiedRect(for: toolbarButtonsStackView, to: &rects)
    return rects
}
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.toolbarDockEdge / toolbarButtonsStackView / installToolbarButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B1 在 macOS 侧建立统一的 toolbar stack 与 dock edge 入口，使后续 B2/B4 可以和 iOS 走同一套演进方向。
private var toolbarDockEdge: CanvasToolbarDockEdge = .trailing {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarDockEdge()
    }
}
private let toolbarButtonsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private var toolbarButtons: [NSButton] {
    [cropButton, saveButton, importButton]
}

private func setupViewHierarchy() {
    // ... 省略与本次 B1 无关的视图挂载代码
    chromeOverlayView.addSubview(toolbarButtonsStackView)
    installToolbarButtons()
}

private func installToolbarButtons() {
    toolbarButtons.forEach { button in
        toolbarButtonsStackView.addArrangedSubview(button)
    }
}

private func updatePreparedToolbarDockEdge() {
    toolbarButtonsStackView.orientation = toolbarDockEdge.prefersHorizontalButtonLayout
        ? .horizontal
        : .vertical
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: toolbarButtonsStackView, to: &rects)
    return rects
}
```

## 阶段B1完成情况

- 已完成：工具栏停靠枚举入口。
- 已完成：`iOS` 主工具栏组与 history 组的结构拆分。
- 已完成：`macOS` 统一的工具栏停靠入口与按钮组组织入口。
- 已完成：overlay blocker rect 对新分组结构的接入。
- 未完成：`ToolbarHostView` 外壳。
- 未完成：四边停靠约束切换。
- 未完成：按钮纯图标正方形最终视觉。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild / ReadLints
# 功能说明: 使用系统时间生成记录文件名，并对本次 B1 改动执行双端构建与静态检查。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_B1_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_B1_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_150223`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- 本次 `B1` 的定位是“工具栏结构准备层”，核心价值是先把 `主工具栏`、`history`、`dock edge` 这些后续会持续演进的结构边界固定下来。
- 这一阶段没有直接交付最终视觉形态，但已经把 `B2` 的宿主外壳、`B3` 的按钮迁移与视觉统一、`B4` 的四边停靠切换所需入口全部准备好。
