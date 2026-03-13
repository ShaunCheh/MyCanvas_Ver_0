# 20260313_162554_phase6_image_import_record

## 记录范围

- 记录内容：阶段 6 的测试图片接入与平台选图入口实现。
- 目标：在 `iOS` 和 `macOS` 的具体画板页中加入悬浮 `+` 按钮，并分别通过相册/Finder 选图，再把图片解码成 `CGImage` 注入 `CanvasScene`。
- 本次未包含：图片持久化、批量导入布局优化、真实画板列表联动。

## 变更 1：iOS 画板页新增悬浮 `+` 按钮

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前的 iOS 画板页只有 viewport 宿主结构和相机刷新链路，没有屏幕空间固定的导入入口。
final class iOSViewController: UIViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupCanvasViewport()
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
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy() / setupConstraints() / setupImportButton()
// 功能说明: 修改后的 iOS 画板页增加了一个固定在屏幕空间的悬浮加号按钮，用作图片导入入口。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let importButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "plus")
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        return button
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupCanvasViewport()
    }

    private func setupViewHierarchy() {
        view.backgroundColor = .systemBackground
        view.addSubview(canvasHostView)
        view.addSubview(importButton)
    }

    private func setupConstraints() {
        let safeAreaLayoutGuide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            importButton.widthAnchor.constraint(equalToConstant: 56),
            importButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setupImportButton() {
        importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
    }
}
```

## 变更 2：iOS 新增相册选图、解码和图片注入 `CanvasScene`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: refreshCanvas()
// 功能说明: 修改前的 iOS 画板页只能刷新已有场景快照，无法从系统相册选择图片，也没有把图片注入 CanvasScene 的入口。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
    canvasViewportView.apply(snapshot)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handleImportButtonTap() / picker(_:didFinishPicking:) / loadSelectedImage(from:) / appendImportedImage(_:)
// 功能说明: 新增 iOS 相册选图链路，使用 PHPickerViewController 选图并解码成 CGImage，再转换为 CanvasImageItem 注入场景。
@objc
private func handleImportButtonTap() {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1

    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard let result = results.first else {
        return
    }

    loadSelectedImage(from: result)
}

private func loadSelectedImage(from result: PHPickerResult) {
    let itemProvider = result.itemProvider
    guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
        return
    }

    itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
        guard
            let url,
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return
        }

        Task { @MainActor [weak self] in
            self?.appendImportedImage(cgImage)
        }
    }
}

private func appendImportedImage(_ cgImage: CGImage) {
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    refreshCanvas()
}
```

## 变更 3：macOS 画板页新增悬浮 `+` 按钮

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前的 macOS 画板页只有 viewport 宿主结构和相机刷新链路，没有屏幕空间固定的导入入口。
final class macOSViewController: NSViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupCanvasViewport()
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
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: viewDidLoad() / setupViewHierarchy() / setupConstraints() / setupImportButton()
// 功能说明: 修改后的 macOS 画板页增加了一个固定在屏幕空间的悬浮加号按钮，用作 Finder 选图入口。
final class macOSViewController: NSViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let importButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Import image") {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "+"
        }
        return button
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupImportButton()
        setupCanvasViewport()
    }

    private func setupViewHierarchy() {
        view.addSubview(canvasHostView)
        view.addSubview(importButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            importButton.widthAnchor.constraint(equalToConstant: 44),
            importButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupImportButton() {
        importButton.target = self
        importButton.action = #selector(handleImportButtonClick)
    }
}
```

## 变更 4：macOS 新增 Finder 选图、解码和图片注入 `CanvasScene`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: refreshCanvas()
// 功能说明: 修改前的 macOS 画板页只能刷新已有场景快照，无法从 Finder 选择图片，也没有把图片注入 CanvasScene 的入口。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
    canvasViewportView.apply(snapshot)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handleImportButtonClick() / appendImportedImage(_:) / normalizedDisplaySize(for:) / nextImageZIndex()
// 功能说明: 新增 macOS Finder 选图链路，使用 NSOpenPanel 选择图片并解码成 CGImage，再转换为 CanvasImageItem 注入场景。
@objc
private func handleImportButtonClick() {
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image]
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true

    openPanel.beginSheetModal(for: window) { [weak self] response in
        guard
            response == .OK,
            let url = openPanel.url,
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return
        }

        self?.appendImportedImage(cgImage)
    }
}

private func appendImportedImage(_ cgImage: CGImage) {
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    refreshCanvas()
}

private func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
    let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
    let longestSide = max(pixelSize.width, pixelSize.height)
    guard longestSide > 0 else {
        return CGSize(width: 240, height: 240)
    }

    let targetLongestSide: CGFloat = 320
    let scale = targetLongestSide / longestSide
    return CGSize(
        width: pixelSize.width * scale,
        height: pixelSize.height * scale
    )
}

private func nextImageZIndex() -> CGFloat {
    (scene.orderedItems().last?.zIndex ?? -1) + 1
}
```

## 当前阶段结果

- `iOS` 画板页现在有悬浮 `+` 按钮，点击后会打开系统相册选择器。
- `macOS` 画板页现在有悬浮 `+` 按钮，点击后会通过 `NSOpenPanel` 打开 Finder 选图。
- 两端都已经把平台选图结果统一解码为 `CGImage`，再转换成 `CanvasImageItem` 注入 `CanvasScene`。
- 新图片默认插入到当前 `camera.center`，并且会先做显示尺寸归一化，然后立刻通过现有 `refreshCanvas()` 刷新显示。
