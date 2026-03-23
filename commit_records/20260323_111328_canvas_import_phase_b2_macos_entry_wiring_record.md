# 20260323_111328_canvas_import_phase_b2_macos_entry_wiring_record

## 记录范围

- 记录内容：
  1. 为 `macOS` 画板新增平台侧 import adapter，把 open panel、pasteboard、拖拽三种输入统一解析成共享层的 `CanvasResolvedImportImage`。
  2. 为 `Edit` 菜单补上 `Paste`，并让 `macOSViewController` 通过 responder / validation 路径处理 `Command+V`。
  3. 让 `macOSCanvasViewportView` 成为拖拽接收面，并通过 closure 把拖拽判断与落板行为转发给 controller。
  4. 让 toolbar import、paste、drag-and-drop 三个 `macOS` 入口统一汇合到 `importResolvedImages(...) -> editorSession.appendImportedImages(...)`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - `iOS` 入口接入
  - `CanvasCommand` / `CanvasCommandExecutor` 的导入命令化
  - 原始 gif diff
  - git commit / push

## 修改一：新增 `macOS` 平台 import adapter

### 修改前

- `macOS` 平台没有单独的 import adapter。
- `macOSViewController.handleImportButtonClick()` 直接做了 `URL -> CGImage` 解码，pasteboard 和 drag-and-drop 还没有统一入口。
- 这意味着 open panel、剪贴板、Finder 文件粘贴、拖拽如果都要支持，会在 controller 里继续堆重复解析逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 类型名: macOSCanvasImportAdapter
// 功能说明: 修改前该文件不存在；macOS 平台没有统一的图片解析适配层，open panel 解析逻辑散落在 controller。
// 文件状态: 不存在
```

### 修改后

- 新增 `macOSCanvasImportAdapter`，让 `macOS` 入口先统一落到平台适配层，再把结果转成共享 import core 可消费的 `[CanvasResolvedImportImage]`。
- adapter 同时支持：
  - `resolvedImages(from urls: [URL])`
  - `resolvedImages(from pasteboard: NSPasteboard)`
  - `canResolveImages(from pasteboard: NSPasteboard)`
- pasteboard 解析优先尝试图片文件 URL，再回退到系统原生图片对象，兼容 Finder 文件复制和系统图片复制两类来源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 类型名: macOSCanvasImportAdapter
// 功能说明: 修改后平台侧统一负责把 URL / pasteboard 内容解析成共享层的 CanvasResolvedImportImage 数组，避免 controller 重复写解码逻辑。
#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum macOSCanvasImportAdapter {
    private static let imageFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier]
    ]

    static func resolvedImages(from urls: [URL]) -> [CanvasResolvedImportImage] {
        urls.compactMap(makeResolvedImportImage(from:))
    }

    static func resolvedImages(from pasteboard: NSPasteboard) -> [CanvasResolvedImportImage] {
        let imageFileURLs = self.imageFileURLs(from: pasteboard)
        if imageFileURLs.isEmpty == false {
            return resolvedImages(from: imageFileURLs)
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let resolvedImage = makeResolvedImportImage(from: image)
        else {
            return []
        }

        return [resolvedImage]
    }

    static func canResolveImages(from pasteboard: NSPasteboard) -> Bool {
        if imageFileURLs(from: pasteboard).isEmpty == false {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
    }

    private static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: imageFileURLReadingOptions
        ) as? [NSURL] ?? []
        return objects.map { $0 as URL }
    }

    private static func makeResolvedImportImage(
        from url: URL
    ) -> CanvasResolvedImportImage? {
        guard
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        return CanvasResolvedImportImage(cgImage: cgImage)
    }
}
#endif
```

## 修改二：为 `Edit` 菜单补上 `Paste`

### 修改前

- `macOSAppDelegate` 里的手写 `Edit` 菜单只有 `Undo` / `Redo`。
- `Command+V` 在应用菜单层没有入口，系统菜单也不会把 `Paste` 意图分发给当前画板 responder。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名: makeEditMenuItem()
// 功能说明: 修改前 Edit 菜单只暴露 Undo / Redo，没有 Paste 菜单项，也没有 Command+V 的标准入口。
private func makeEditMenuItem() -> NSMenuItem {
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")

    let undoItem = NSMenuItem(
        title: "Undo",
        action: #selector(handleUndoMenuItem(_:)),
        keyEquivalent: "z"
    )
    undoItem.target = self
    undoItem.keyEquivalentModifierMask = [.command]
    editMenu.addItem(undoItem)

    let redoItem = NSMenuItem(
        title: "Redo",
        action: #selector(handleRedoMenuItem(_:)),
        keyEquivalent: "Z"
    )
    redoItem.target = self
    redoItem.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redoItem)

    editMenuItem.submenu = editMenu
    return editMenuItem
}
```

### 修改后

- 在 `Undo` / `Redo` 后插入分隔线，并补上 `Paste` 菜单项。
- `Paste` 的 action 直接指向 `#selector(macOSViewController.paste(_:))`，配合 responder chain 和 controller validation，让 `Command+V` 能落到当前 canvas controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名: makeEditMenuItem()
// 功能说明: 修改后 Edit 菜单新增标准 Paste 项，为 Command+V 提供菜单层入口，并把响应转交给当前 canvas controller。
private func makeEditMenuItem() -> NSMenuItem {
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")

    let undoItem = NSMenuItem(
        title: "Undo",
        action: #selector(handleUndoMenuItem(_:)),
        keyEquivalent: "z"
    )
    undoItem.target = self
    undoItem.keyEquivalentModifierMask = [.command]
    editMenu.addItem(undoItem)

    let redoItem = NSMenuItem(
        title: "Redo",
        action: #selector(handleRedoMenuItem(_:)),
        keyEquivalent: "Z"
    )
    redoItem.target = self
    redoItem.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redoItem)

    editMenu.addItem(.separator())

    let pasteItem = NSMenuItem(
        title: "Paste",
        action: #selector(macOSViewController.paste(_:)),
        keyEquivalent: "v"
    )
    pasteItem.keyEquivalentModifierMask = .command
    editMenu.addItem(pasteItem)

    editMenuItem.submenu = editMenu
    return editMenuItem
}
```

## 修改三：让 controller 统一收口 open panel / paste / drop 的导入流程

### 修改前

- `handleImportButtonClick()` 只支持单选 open panel，内部直接解单个 URL。
- controller 没有 `paste(_:)`、没有 `validateUserInterfaceItem(...)`，也没有统一的“已解析图片批次 -> 共享导入核心”收口函数。
- 如果继续叠加 paste 和 drop，controller 里会出现多条并行且重复的导入路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick() / appendImportedImage(_:)
// 功能说明: 修改前 toolbar import 只支持单选 open panel，并且 controller 没有 paste/drop 收口能力。
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
    _ = editorSession.appendImportedImage(cgImage)
    refreshCanvas()
}
```

### 修改后

- `macOSViewController` 现在实现 `NSUserInterfaceValidations`，通过 `validateUserInterfaceItem(...)` 控制 `Paste` 的 enablement。
- 新增 `paste(_:)`、`handlePasteRequest()`、`canImportImages(from:)`、`dragOperation(for:)`、`handleImportDrop(...)`、`importResolvedImages(...)`。
- `handleImportButtonClick()` 现在改成多选 open panel，并通过 adapter 先解析成 `[CanvasResolvedImportImage]`，再统一走 `importResolvedImages(...)`。
- 三个入口现在全部汇合到 `editorSession.appendImportedImages(...)`，保证和 `B-1` 的共享批量 import core 一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: validateUserInterfaceItem(_:) / paste(_:) / handleImportButtonClick() / handlePasteRequest() / handleImportDrop(pasteboard:) / importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改后 controller 统一承接 macOS 导入入口，把 open panel、Paste、drag-and-drop 全部收敛到共享批量导入核心。
final class macOSViewController: NSViewController, NSUserInterfaceValidations {
    func validateUserInterfaceItem(
        _ item: any NSValidatedUserInterfaceItem
    ) -> Bool {
        switch item.action {
        case #selector(macOSViewController.paste(_:)):
            return canImportImages(from: .general)
        default:
            return true
        }
    }

    @objc
    func paste(_ sender: Any?) {
        handlePasteRequest()
    }

    @objc
    private func handleImportButtonClick() {
        guard let window = view.window else {
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let self
            else {
                return
            }

            let resolvedImages = macOSCanvasImportAdapter.resolvedImages(
                from: openPanel.urls
            )
            _ = self.importResolvedImages(
                resolvedImages,
                source: "open panel"
            )
        }
    }

    private func handlePasteRequest() {
        let resolvedImages = macOSCanvasImportAdapter.resolvedImages(
            from: .general
        )
        _ = importResolvedImages(
            resolvedImages,
            source: "pasteboard"
        )
    }

    private func handleImportDrop(
        pasteboard: NSPasteboard
    ) -> Bool {
        let didImport = importResolvedImages(
            macOSCanvasImportAdapter.resolvedImages(from: pasteboard),
            source: "drag and drop"
        )
        if didImport {
            view.window?.makeFirstResponder(canvasViewportView)
        }

        return didImport
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
        refreshCanvas(
            reason: "import \(imageCount) \(imageLabel) from \(source)"
        )
        return true
    }
}
```

## 修改四：让 viewport 成为拖拽接收面，但把业务继续留在 controller

### 修改前

- `macOSCanvasViewportView` 只负责鼠标、滚轮和缩放。
- 视图没有注册 drag types，也没有 `NSDraggingDestination` 相关 override。
- 这意味着 Finder 图片拖到画板时，没有任何接收入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: mouseDown(with:) / rightMouseDown(with:) / scrollWheel(with:) / magnify(with:)
// 功能说明: 修改前 viewport 只暴露 pointer / pan / zoom 回调，没有 drag-and-drop 的 closure 或 NSDraggingDestination 支持。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onSecondaryClick: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?
```

### 修改后

- viewport 新增 `importDragTypes`、`onImportDragOperation`、`onImportDrop`。
- 在 `init(frame:)` 里 `registerForDraggedTypes(...)`。
- 视图实现 `draggingEntered(_:)`、`draggingUpdated(_:)`、`prepareForDragOperation(_:)`、`performDragOperation(_:)`，但自身只负责把 drag 信息转成 closure 回调，不在 view 内部做导入业务判断。
- 这样 drag surface 仍然在画板视图上，但解析和落板决策继续由 controller 驱动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: init(frame:) / draggingEntered(_:) / draggingUpdated(_:) / prepareForDragOperation(_:) / performDragOperation(_:) / resolvedImportDragOperation(for:)
// 功能说明: 修改后 viewport 变成 Finder 拖拽的接收表面，但具体是否允许导入、如何导入，仍通过 closure 回交给 controller。
private static let importDragTypes: [NSPasteboard.PasteboardType] = [
    .fileURL,
    .tiff
]

var onImportDragOperation: ((CGPoint, NSPasteboard) -> NSDragOperation)?
var onImportDrop: ((CGPoint, NSPasteboard) -> Bool)?

override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupLayers()
    registerForDraggedTypes(Self.importDragTypes)
}

override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    resolvedImportDragOperation(for: sender)
}

override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    resolvedImportDragOperation(for: sender)
}

override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    resolvedImportDragOperation(for: sender) != []
}

override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let location = convert(sender.draggingLocation, from: nil)
    return onImportDrop?(location, sender.draggingPasteboard) ?? false
}

private func resolvedImportDragOperation(
    for sender: NSDraggingInfo
) -> NSDragOperation {
    let location = convert(sender.draggingLocation, from: nil)
    return onImportDragOperation?(location, sender.draggingPasteboard) ?? []
}
```

## 影响说明

- `macOS` 的 toolbar import 现在支持多选，并统一走 `B-1` 的批量导入核心。
- `Command+V` 现在可通过 `Edit > Paste` 和 responder 路径触发，controller 会根据剪贴板内容动态决定是否启用 Paste。
- Finder 里的图片文件拖拽到画板时，viewport 会接住拖拽并回调给 controller 统一导入。
- 这次 B-2 仍然保持“默认导入到画板中心”，没有在本阶段引入按拖拽落点插入或按最后点击点插入。

## 校验说明

- 已检查 `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`，当前未发现新增 lint 报错。
- 已使用 `swiftc -typecheck` 对非 iOS Swift 源码集合进行静态类型检查，当前通过。
- 本次未运行完整 `xcodebuild` / UI 实机验证；当前记录基于代码差异、lints 与静态类型检查结果。
