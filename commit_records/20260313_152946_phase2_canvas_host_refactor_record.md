# 20260313_152946_phase2_canvas_host_refactor_record

## 记录范围

- 记录内容：阶段 2 的宿主控制器重定位改造。
- 目标：把当前 `iOSViewController` 和 `macOSViewController` 从 `Hello world` 占位页，改造成具体画板页的宿主控制器。
- 本次未包含：`CanvasScene`、`CanvasCamera`、`CanvasRenderer`、`CanvasViewportView`、图片显示层和自定义平移缩放。

## 变更 1：iOS 宿主控制器从占位页面改造成画板宿主容器

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前的 iOSViewController 直接负责渲染 Hello world，占位页面和未来画板宿主职责混在一起。
private let helloLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Hello world"
    label.font = .systemFont(ofSize: 32, weight: .semibold)
    label.textColor = .label
    label.textAlignment = .center
    return label
}()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(helloLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        helloLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        helloLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: installCanvasContentView(_:) / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后的 iOSViewController 不再渲染占位文本，而是提供全屏 canvasHostView 和统一的画布内容挂载入口。
private let canvasHostView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .systemBackground
    view.clipsToBounds = true
    return view
}()
private var canvasContentView: UIView?

// 后续真正的 CanvasViewportView 应统一通过这个入口挂载到宿主容器中。
func installCanvasContentView(_ contentView: UIView) {
    loadViewIfNeeded()
    canvasContentView?.removeFromSuperview()

    contentView.translatesAutoresizingMaskIntoConstraints = false
    canvasHostView.addSubview(contentView)
    NSLayoutConstraint.activate([
        contentView.topAnchor.constraint(equalTo: canvasHostView.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: canvasHostView.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: canvasHostView.trailingAnchor),
        contentView.bottomAnchor.constraint(equalTo: canvasHostView.bottomAnchor)
    ])

    canvasContentView = contentView
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}
```

## 变更 2：macOS 宿主控制器从占位页面改造成画板宿主容器

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: loadView() / viewDidLoad() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前的 macOSViewController 直接负责渲染 Hello world，占位页面和未来画板宿主职责混在一起。
private let helloLabel: NSTextField = {
    let label = NSTextField(labelWithString: "Hello world")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 32, weight: .semibold)
    label.textColor = .labelColor
    label.alignment = .center
    return label
}()

override func loadView() {
    view = NSView()
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}

private func setupViewHierarchy() {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view.addSubview(helloLabel)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        helloLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        helloLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: loadView() / installCanvasContentView(_:) / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后的 macOSViewController 不再渲染占位文本，而是提供全屏 canvasHostView 和统一的画布内容挂载入口。
private let canvasHostView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view.layer?.masksToBounds = true
    return view
}()
private var canvasContentView: NSView?

override func loadView() {
    let rootView = NSView()
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view = rootView
}

// 后续真正的 CanvasViewportView 应统一通过这个入口挂载到宿主容器中。
func installCanvasContentView(_ contentView: NSView) {
    _ = view
    canvasContentView?.removeFromSuperview()

    contentView.translatesAutoresizingMaskIntoConstraints = false
    canvasHostView.addSubview(contentView)
    NSLayoutConstraint.activate([
        contentView.topAnchor.constraint(equalTo: canvasHostView.topAnchor),
        contentView.leadingAnchor.constraint(equalTo: canvasHostView.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: canvasHostView.trailingAnchor),
        contentView.bottomAnchor.constraint(equalTo: canvasHostView.bottomAnchor)
    ])

    canvasContentView = contentView
}

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
}
```

## 当前阶段结果

- `iOSViewController` 不再有“首页占位页”的语义，而是一个纯宿主控制器。
- `macOSViewController` 不再直接负责文本占位显示，而是为未来固定视口画布提供挂载面。
- 两端都已经具备统一的 `installCanvasContentView(_:)` 入口，后续可以直接挂 `CanvasViewportView`，不需要再次重构控制器层级。
- 当前应用默认进入 `canvas` 场景时，看到的是空白宿主页，而不是 `Hello world` 占位页；这属于阶段 2 的预期结果。
