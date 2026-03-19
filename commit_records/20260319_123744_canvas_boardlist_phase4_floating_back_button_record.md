# 20260319_123744_canvas_boardlist_phase4_floating_back_button_record

## 记录范围

- 记录目标：实施 `Canvas` 返回与列表缓存方案的阶段4，在双端 `Canvas` 的 `chromeOverlayView` 上添加左上角悬浮圆形返回按钮。
- 本次目的 1：把阶段3已经接好的 `onBackToBoardList` 回调真正暴露到可点击的 UI 上。
- 本次目的 2：让返回按钮与现有右下角工具区解耦，独立固定在安全区左上角。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：`backButton` 与 minimap / context menu 的避让处理。
- 本记录不包含：overlay 命中层级收口。
- 本记录不包含：git commit。

## 修改一：在 macOS Canvas overlay 上增加左上角圆形返回按钮

### 修改前

- `macOSViewController` 的 overlay 区域只有：
- `miniMapMountView`
- `controlsStackView`
- `contextMenuHostView`
- 没有独立的 `backButton` 属性，也没有对应的 `setupBackButton()` / `handleBackButtonClick()`。
- 这意味着即使阶段3已经把 `onBackToBoardList` 接进 controller，本阶段开始前依然没有任何可视入口能触发它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.setupViewHierarchy() / setupConstraints() / setupCropButton()
// 功能说明: 修改前 macOS Canvas overlay 只挂载 minimap、右下角工具区和 context menu host，左上角还没有返回按钮。
private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        importButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

private func setupCropButton() {
    cropButton.target = self
    cropButton.action = #selector(handleCropButtonClick)
    updateInlineEditButtonsAppearance()
}
```

### 修改后

- 新增 `backButton: NSButton`，样式上做成圆形、半透明底、`chevron.left` 图标。
- 在 `viewDidLoad()` 中补 `setupBackButton()`。
- 在 `setupViewHierarchy()` 中把 `backButton` 挂到 `chromeOverlayView`。
- 在 `setupConstraints()` 中把按钮固定到左上角安全区内，尺寸为 `44 x 44`。
- 点击后通过 `handleBackButtonClick()` 调用阶段3已经注入的 `onBackToBoardList?()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.backButton / setupViewHierarchy() / setupConstraints() / setupBackButton() / handleBackButtonClick()
// 功能说明: 修改后 macOS 在 Canvas overlay 上新增左上角圆形返回按钮，并把点击事件路由到 onBackToBoardList 回调。
private let backButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.title = ""
    button.toolTip = "Back to board list"
    button.wantsLayer = true
    button.layer?.cornerRadius = 22
    button.layer?.masksToBounds = true
    button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
    button.layer?.borderWidth = 1
    button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    button.contentTintColor = .labelColor
    if let image = NSImage(
        systemSymbolName: "chevron.left",
        accessibilityDescription: "Back to board list"
    ) {
        button.image = image
        button.imagePosition = .imageOnly
    } else {
        button.title = "<"
    }
    return button
}()

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        importButton.heightAnchor.constraint(equalToConstant: 44)
    ])
}

private func setupBackButton() {
    backButton.target = self
    backButton.action = #selector(handleBackButtonClick)
}

@objc
private func handleBackButtonClick() {
    onBackToBoardList?()
}
```

## 修改二：在 iOS Canvas overlay 上对称增加左上角圆形返回按钮

### 修改前

- `iOSViewController` 的 overlay 挂载结构与 macOS 一样，左上角没有独立返回按钮。
- `viewDidLoad()` 里只会 setup 现有的导入、保存、裁剪、撤销、重做按钮，不会初始化任何“返回 BoardList”的 UI。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.setupViewHierarchy() / setupConstraints() / viewDidLoad()
// 功能说明: 修改前 iOS Canvas overlay 也没有左上角返回按钮，viewDidLoad 只初始化现有编辑工具按钮。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupUndoButton()
    setupRedoButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        cropButton.heightAnchor.constraint(equalToConstant: 40),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40),
        saveButton.heightAnchor.constraint(equalToConstant: 40),
        importButton.heightAnchor.constraint(equalToConstant: 56)
    ])
}
```

### 修改后

- 新增 `backButton: UIButton`，用 `UIButton.Configuration.filled()` 做成圆形胶囊按钮，并只显示 `chevron.left`。
- 在 `viewDidLoad()` 中增加 `setupBackButton()`。
- 在 `setupViewHierarchy()` 里把 `backButton` 加到 `chromeOverlayView`。
- 在 `setupConstraints()` 中固定到左上角安全区内，尺寸同样是 `44 x 44`。
- `handleBackButtonTap()` 直接调用 `onBackToBoardList?()`，与 macOS 保持一致的回调边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.backButton / viewDidLoad() / setupViewHierarchy() / setupConstraints() / setupBackButton() / handleBackButtonTap()
// 功能说明: 修改后 iOS 在 Canvas overlay 上增加左上角圆形返回按钮，并把点击动作统一转发到 onBackToBoardList 回调。
private let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 17,
        weight: .semibold
    )
    configuration.image = UIImage(systemName: "chevron.left")
    configuration.baseBackgroundColor = .secondarySystemBackground
    configuration.baseForegroundColor = .label
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.accessibilityLabel = "Back to board list"
    return button
}()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
        backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
        backButton.widthAnchor.constraint(equalToConstant: 44),
        backButton.heightAnchor.constraint(equalToConstant: 44),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        cropButton.heightAnchor.constraint(equalToConstant: 40),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40),
        saveButton.heightAnchor.constraint(equalToConstant: 40),
        importButton.heightAnchor.constraint(equalToConstant: 56)
    ])
}

private func setupBackButton() {
    backButton.addTarget(self, action: #selector(handleBackButtonTap), for: .touchUpInside)
}

@objc
private func handleBackButtonTap() {
    onBackToBoardList?()
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 已对照本次实际修改，确认阶段4只包含：
- 双端 `backButton` 属性
- `chromeOverlayView` 中的挂载
- 左上角安全区约束
- `setupBackButton()` 和点击转发到 `onBackToBoardList`
- 本次相关文件的 `ReadLints` 检查结果：无新增错误。
- 本次未执行项目级编译或运行时验证；因此当前验证范围以代码对照和 lint 为主。
