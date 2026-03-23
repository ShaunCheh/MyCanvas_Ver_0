# 20260323_112148_canvas_import_phase_b3_ios_entry_wiring_record

## 记录范围

- 记录内容：
  1. 为 `iOS` 画板新增平台侧 import adapter，把 `PHPickerResult`、`UIPasteboard`、`UIDropSession` 统一解析成共享层的 `CanvasResolvedImportImage`。
  2. 让 `iOSViewController` 成为外接键盘 `Command+V` 的 first responder，并补上 `UIKeyCommand`。
  3. 让 photo picker 从单选改为多选，并把 picker 导入统一收敛到共享批量 import core。
  4. 为画板视图挂上 `UIDropInteraction`，让拖放导入与 pasteboard 导入统一复用 `importResolvedImages(...)`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - `macOS` 入口接入
  - `CanvasCommand` / `CanvasCommandExecutor` 的导入命令化
  - 原始 gif diff
  - git commit / push

## 修改一：新增 `iOS` 平台 import adapter

### 修改前

- `iOS` 侧没有单独的 import adapter。
- `iOSViewController` 里只有 `PHPickerResult -> NSItemProvider -> Data -> CGImage` 的单条解析链。
- 剪贴板和拖放如果要接入，只能继续把解析逻辑直接堆在 controller 里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 类型名: iOSCanvasImportAdapter
// 功能说明: 修改前该文件不存在；iOS 平台没有统一的 picker / pasteboard / drop 图片解析适配层。
// 文件状态: 不存在
```

### 修改后

- 新增 `iOSCanvasImportAdapter`，把 `PHPickerResult`、`UIPasteboard`、`UIDropSession` 全部统一解析成 `[CanvasResolvedImportImage]`。
- adapter 同时支持：
  - `resolvedImages(from results: [PHPickerResult])`
  - `resolvedImages(from pasteboard: UIPasteboard)`
  - `resolvedImages(from dropSession: UIDropSession)`
  - `canResolveImages(...)`
- 解析逻辑优先走 `NSItemProvider.loadDataRepresentation(...)`，并保留 `UIPasteboard.image` 的回退路径，兼容系统图片复制场景。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 类型名: iOSCanvasImportAdapter
// 功能说明: 修改后平台侧统一负责把 picker、pasteboard、drop session 里的图片解析成共享层的 CanvasResolvedImportImage 数组，避免 controller 重复写异步解码逻辑。
#if os(iOS)
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum iOSCanvasImportAdapter {
    static func resolvedImages(
        from results: [PHPickerResult]
    ) async -> [CanvasResolvedImportImage] {
        await resolvedImages(
            from: results.map(\.itemProvider)
        )
    }

    static func resolvedImages(
        from pasteboard: UIPasteboard
    ) async -> [CanvasResolvedImportImage] {
        let imageProviders = pasteboard.itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        if imageProviders.isEmpty == false {
            let resolvedImages = await resolvedImages(from: imageProviders)
            if resolvedImages.isEmpty == false {
                return resolvedImages
            }
        }

        guard
            let image = pasteboard.image,
            let resolvedImage = makeResolvedImportImage(from: image)
        else {
            return []
        }

        return [resolvedImage]
    }

    static func resolvedImages(
        from dropSession: UIDropSession
    ) async -> [CanvasResolvedImportImage] {
        await resolvedImages(
            from: dropSession.items.map(\.itemProvider)
        )
    }

    static func canResolveImages(
        from pasteboard: UIPasteboard
    ) -> Bool {
        if pasteboard.hasImages {
            return true
        }

        return pasteboard.itemProviders.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
    }

    private static func resolvedImages(
        from itemProviders: [NSItemProvider]
    ) async -> [CanvasResolvedImportImage] {
        var resolvedImages: [CanvasResolvedImportImage] = []
        resolvedImages.reserveCapacity(itemProviders.count)

        for itemProvider in itemProviders {
            guard let resolvedImage = await resolvedImage(from: itemProvider) else {
                continue
            }

            resolvedImages.append(resolvedImage)
        }

        return resolvedImages
    }
}
#endif
```

## 修改二：让 controller 成为外接键盘 Paste 的 first responder

### 修改前

- `iOSViewController` 没有 `canBecomeFirstResponder`，也没有 `keyCommands`。
- 这意味着外接键盘的 `Command+V` 没有 controller 级入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: canBecomeFirstResponder / keyCommands / viewDidAppear(_:)
// 功能说明: 修改前 controller 没有 first responder 键盘命令支持，外接键盘 Paste 无法落到画板控制器。
// 代码状态: 不存在这几个 override
```

### 修改后

- `iOSViewController` 现在通过 `canBecomeFirstResponder` 返回 `true`。
- 新增 `keyCommands`，注册 `Command+V` 对应的 `UIKeyCommand`。
- 在 `viewDidAppear(_:)` 主动 `becomeFirstResponder()`，保证画板页展示后可以直接接收外接键盘 paste。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: canBecomeFirstResponder / keyCommands / viewDidAppear(_:)
// 功能说明: 修改后 controller 显式加入 responder chain，并把外接键盘的 Command+V 映射到画板导入动作。
override var canBecomeFirstResponder: Bool {
    true
}

override var keyCommands: [UIKeyCommand]? {
    let pasteCommand = UIKeyCommand(
        input: "v",
        modifierFlags: [.command],
        action: #selector(handlePasteKeyCommand(_:))
    )
    pasteCommand.discoverabilityTitle = "Paste Image"
    return [pasteCommand]
}

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    becomeFirstResponder()
}
```

## 修改三：把 photo picker 从单选改成多选，并统一走共享批量导入核心

### 修改前

- `handleImportButtonTap()` 把 `selectionLimit` 写死为 `1`。
- `picker(_:didFinishPicking:)` 只取 `results.first`。
- controller 通过 `loadSelectedImage(from:)` 和 `appendImportedImage(_:)` 走单图导入路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleImportButtonTap() / picker(_:didFinishPicking:) / loadSelectedImage(from:) / appendImportedImage(_:)
// 功能说明: 修改前 picker 只支持单选，并且 controller 末端只会导入单张图片。
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

private func appendImportedImage(_ cgImage: CGImage) {
    let item = editorSession.appendImportedImage(cgImage)
    requestCanvasRefresh(
        reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
    )
    updateHistoryButtonsAppearance()
}
```

### 修改后

- `selectionLimit = 0`，picker 改成支持多选。
- `picker(_:didFinishPicking:)` 不再只取第一项，而是把整个 `results` 交给 `iOSCanvasImportAdapter`。
- controller 新增统一收口函数 `importResolvedImages(...)`，让 picker 导入直接复用 `B-1` 的共享批量导入核心。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleImportButtonTap() / picker(_:didFinishPicking:) / importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改后 photo picker 支持多选，并且导入末端统一走共享批量 import core，而不是单图专用路径。
@objc
private func handleImportButtonTap() {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 0

    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard results.isEmpty == false else {
        return
    }

    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        let resolvedImages = await iOSCanvasImportAdapter.resolvedImages(
            from: results
        )
        _ = self.importResolvedImages(
            resolvedImages,
            source: "photo picker"
        )
        self.becomeFirstResponder()
    }
}

@discardableResult
private func importResolvedImages(
    _ images: [CanvasResolvedImportImage],
    source: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> Bool {
    guard images.isEmpty == false else {
        return false
    }

    dismissContextMenu()
    let importedItems = editorSession.appendImportedImages(
        images,
        placement: placement,
        layout: layout
    )
    let imageCount = importedItems.count
    let imageLabel = imageCount == 1 ? "image" : "images"
    requestCanvasRefresh(
        reason: "import \(imageCount) \(imageLabel) from \(source)"
    )
    updateHistoryButtonsAppearance()
    return true
}
```

## 修改四：为 Paste 和拖放接入统一的 `iOS` 导入链路

### 修改前

- `iOSViewController` 没有 `handlePasteKeyCommand(_:)`、没有 `handlePasteRequest()`。
- `canvasViewportView` 也没有挂 `UIDropInteraction`。
- 也就是说，`iOS` 端只有 picker 导入，没有外接键盘 paste，也没有 drag-and-drop 的画板入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport() / handlePasteKeyCommand(_:) / dropInteraction(...)
// 功能说明: 修改前 controller 没有 pasteboard 和 drop 的统一入口，canvas viewport 也没有挂 UIDropInteraction。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}
```

### 修改后

- 在 `setupCanvasViewport()` 里给 `canvasViewportView` 挂上 `UIDropInteraction(delegate: self)`。
- controller 新增 `handlePasteKeyCommand(_:)`、`handlePasteRequest()`，把外接键盘 paste 转成统一的 `UIPasteboard -> iOSCanvasImportAdapter -> importResolvedImages(...)` 链路。
- controller 同时实现 `UIDropInteractionDelegate`，让 drag-and-drop 也复用同一条导入末端。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport() / handlePasteKeyCommand(_:) / handlePasteRequest() / dropInteraction(_:canHandle:) / dropInteraction(_:sessionDidUpdate:) / dropInteraction(_:performDrop:)
// 功能说明: 修改后外接键盘 Paste 和 iOS 拖放都统一通过平台 adapter 解析图片，再交给共享批量 import core。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }
    canvasViewportView.addInteraction(
        UIDropInteraction(delegate: self)
    )

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handlePasteRequest()
}

private func handlePasteRequest() {
    guard canImportImages(from: .general) else {
        return
    }

    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        let resolvedImages = await iOSCanvasImportAdapter.resolvedImages(
            from: .general
        )
        _ = self.importResolvedImages(
            resolvedImages,
            source: "pasteboard"
        )
        self.becomeFirstResponder()
    }
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    iOSCanvasImportAdapter.canResolveImages(from: session)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    sessionDidUpdate session: UIDropSession
) -> UIDropProposal {
    if iOSCanvasImportAdapter.canResolveImages(from: session) {
        return UIDropProposal(operation: .copy)
    }

    return UIDropProposal(operation: .cancel)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    performDrop session: UIDropSession
) {
    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        let resolvedImages = await iOSCanvasImportAdapter.resolvedImages(
            from: session
        )
        _ = self.importResolvedImages(
            resolvedImages,
            source: "drag and drop"
        )
        self.becomeFirstResponder()
    }
}
```

## 影响说明

- `iOS` 的 photo picker 现在支持多选，并且会统一走共享批量导入核心。
- 外接键盘 `Command+V` 现在可以把剪贴板里的图片导入到画板。
- 画板现在支持 `UIDropInteraction`，拖放图片也会统一复用同一条导入链路。
- 这次 `B-3` 仍然保持“默认导入到画板中心”，没有在本阶段引入按拖放落点插入。

## 校验说明

- 已检查 `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift` 与 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`，当前未发现新增 lint 报错。
- 已使用 `swiftc -typecheck` 对全量 Swift 源码集合进行静态类型检查，当前通过。
- 本次未运行完整 iOS 模拟器 / 真机交互验证；当前记录基于代码差异、lints 与静态类型检查结果。
