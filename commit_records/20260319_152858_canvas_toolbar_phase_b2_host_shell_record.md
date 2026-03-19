# 20260319_152858_canvas_toolbar_phase_b2_host_shell_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段B-阶段2` 的实际代码变更。
- 本次实际产物：
- 新增 `iOS` 工具栏宿主视图 `iOSCanvasToolbarHostView`。
- 新增 `macOS` 工具栏宿主视图 `macOSCanvasToolbarHostView`。
- `iOS` 与 `macOS` 控制器不再直接把主工具栏按钮挂到裸 `stackView` 上，而是改为挂到 `toolbarHostView`。
- `chromeOccupiedRects()` 从上报裸工具栏按钮栈，改为上报宿主视图 `toolbarHostView`。
- 本次未执行：
- 未实现 `B3` 的纯图标正方形最终按钮视觉。
- 未实现 `B4` 的四边停靠约束切换。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- 新增：`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前（B1完成后）

- `iOS` 与 `macOS` 虽然已经有了 `toolbarDockEdge` 和按钮分组边界，但主工具栏本体仍然只是一个裸 `stackView`。
- 背景、圆角、阴影、内边距、命中透传外壳都还没有独立宿主承接。
- 控制器仍然直接约束 `toolbarButtonsStackView`，`occupied rect` 也直接取这个裸栈的 frame。

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.toolbarButtonsStackView / setupViewHierarchy() / setupConstraints() / installToolbarButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B2 修改前，iOS 主工具栏还是一个直接挂在 chromeOverlayView 上的裸 stackView，没有独立外壳承接背景、内边距和命中边界。
private let toolbarButtonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private func setupViewHierarchy() {
    // ... 省略与本次 B2 无关的视图挂载代码
    chromeOverlayView.addSubview(historyButtonsStackView)
    chromeOverlayView.addSubview(toolbarButtonsStackView)
    installHistoryButtons()
    installToolbarButtons()
}

private func setupConstraints() {
    // ... 省略与本次 B2 无关的约束
    toolbarButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    toolbarButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    historyButtonsStackView.bottomAnchor.constraint(equalTo: toolbarButtonsStackView.topAnchor, constant: -12)
}

private func installToolbarButtons() {
    toolbarButtons.forEach { button in
        toolbarButtonsStackView.addArrangedSubview(button)
    }
}

private func updatePreparedToolbarDockEdge() {
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

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.toolbarButtonsStackView / setupViewHierarchy() / setupConstraints() / installToolbarButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B2 修改前，macOS 主工具栏同样直接使用裸 stackView，控制器自身负责主工具栏的承载与占位。
private let toolbarButtonsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()

private func setupViewHierarchy() {
    // ... 省略与本次 B2 无关的视图挂载代码
    chromeOverlayView.addSubview(toolbarButtonsStackView)
    installToolbarButtons()
}

private func setupConstraints() {
    // ... 省略与本次 B2 无关的约束
    toolbarButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    toolbarButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
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

## 修改后（B2完成后）

- 新增跨平台各自原生实现的 `ToolbarHostView`，形成“外层宿主 + 内层按钮栈”的结构。
- 宿主视图开始负责：
- 工具栏背景
- 圆角
- 边框
- 阴影
- 内边距
- 空白区域点击透传
- 按钮横排/竖排切换
- 控制器只负责把按钮安装进去，并把 `dockEdge` 转发给 host。
- `occupied rect` 改成以 `toolbarHostView` 为单位上报，为下一步 `B3/B4` 继续演进留出稳定边界。

### iOS 新增宿主视图代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: iOSCanvasToolbarHostView / installButtons(_:) / updateDockEdgeLayout() / hitTest(_:with:)
// 功能说明: B2 为 iOS 新增独立工具栏宿主，用外层视图承接背景和命中透传，用内层 stack 承接按钮排布和 dock edge 驱动的方向切换。
final class iOSCanvasToolbarHostView: UIView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: iOSCanvasChromeOverlayView = {
        let view = iOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.92)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Layout.shadowOpacity
        view.layer.shadowRadius = Layout.shadowRadius
        view.layer.shadowOffset = Layout.shadowOffset
        return view
    }()

    private let buttonsStackView: iOSCanvasChromeStackView = {
        let stackView = iOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = Layout.spacing
        return stackView
    }()

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    func installButtons(_ buttons: [UIButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    private func updateDockEdgeLayout() {
        buttonsStackView.axis = dockEdge.prefersHorizontalButtonLayout
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
            ? .center
            : .trailing
    }
}
```

### macOS 新增宿主视图代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: macOSCanvasToolbarHostView / installButtons(_:) / updateDockEdgeLayout() / hitTest(_:)
// 功能说明: B2 为 macOS 新增独立工具栏宿主，用 AppKit 原生外壳承接背景、阴影和内边距，并继续保持空白区域事件透传。
final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: macOSCanvasChromeOverlayView = {
        let view = macOSCanvasChromeOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        view.layer?.cornerRadius = Layout.cornerRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = Layout.shadowOpacity
        view.layer?.shadowRadius = Layout.shadowRadius
        view.layer?.shadowOffset = Layout.shadowOffset
        return view
    }()

    private let buttonsStackView: macOSCanvasChromeStackView = {
        let stackView = macOSCanvasChromeStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .trailing
        stackView.distribution = .fill
        stackView.spacing = Layout.spacing
        return stackView
    }()

    var dockEdge: CanvasToolbarDockEdge = .trailing {
        didSet {
            updateDockEdgeLayout()
        }
    }

    func installButtons(_ buttons: [NSButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    private func updateDockEdgeLayout() {
        buttonsStackView.orientation = dockEdge.prefersHorizontalButtonLayout
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
            ? .centerY
            : .trailing
    }
}
```

### iOS 控制器接入宿主后的代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.toolbarHostView / setupViewHierarchy() / setupConstraints() / installToolbarButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B2 之后，iOS 控制器不再直接承载主工具栏 stack，而是把按钮安装到 toolbarHostView，并让 blocker rect 以宿主视图为单位参与 overlay 布局。
private let toolbarHostView = iOSCanvasToolbarHostView()

private func setupViewHierarchy() {
    // ... 省略与本次 B2 无关的视图挂载代码
    chromeOverlayView.addSubview(historyButtonsStackView)
    chromeOverlayView.addSubview(toolbarHostView)
    installHistoryButtons()
    installToolbarButtons()
}

private func setupConstraints() {
    // ... 省略与本次 B2 无关的约束
    toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    historyButtonsStackView.bottomAnchor.constraint(equalTo: toolbarHostView.topAnchor, constant: -12)
}

private func installToolbarButtons() {
    toolbarHostView.installButtons(toolbarButtons)
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: historyButtonsStackView, to: &rects)
    appendChromeOccupiedRect(for: toolbarHostView, to: &rects)
    return rects
}
```

### macOS 控制器接入宿主后的代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.toolbarHostView / setupViewHierarchy() / setupConstraints() / installToolbarButtons() / updatePreparedToolbarDockEdge() / chromeOccupiedRects()
// 功能说明: B2 之后，macOS 控制器也改成把主工具栏按钮挂入独立宿主视图，使主工具栏承载方式与 iOS 对齐。
private let toolbarHostView = macOSCanvasToolbarHostView()

private func setupViewHierarchy() {
    // ... 省略与本次 B2 无关的视图挂载代码
    chromeOverlayView.addSubview(toolbarHostView)
    installToolbarButtons()
}

private func setupConstraints() {
    // ... 省略与本次 B2 无关的约束
    toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
    toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
}

private func installToolbarButtons() {
    toolbarHostView.installButtons(toolbarButtons)
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: toolbarHostView, to: &rects)
    return rects
}
```

## 阶段B2完成情况

- 已完成：`iOS/macOS` 主工具栏宿主外壳。
- 已完成：背景、圆角、边框、阴影、内边距下沉到宿主视图。
- 已完成：宿主内部按钮栈随 `dockEdge` 切换横竖方向。
- 已完成：主工具栏 blocker rect 以宿主视图为单位参与 overlay 占位。
- 未完成：按钮最终纯图标正方形视觉。
- 未完成：四边停靠约束切换。
- 未完成：history 组宿主化。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 B2 记录文件名，并对 B2 宿主外壳改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_B2_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_B2_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_152858`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `B2` 的核心不是按钮视觉，而是先把“主工具栏承载层”从控制器中剥离出来。
- 到这一阶段为止，控制器已经不再直接承担主工具栏的外壳职责，后续 `B3` 可以直接在 `ToolbarHostView` 内继续做按钮纯图标化和尺寸统一，而不需要再次重拆主工具栏承载结构。
