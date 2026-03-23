# 20260323_113657_canvas_import_phase_c2_controller_command_dispatch_record

## 记录范围

- 记录内容：
  1. 将 `macOS` controller 的导入终点从“平台层直调 `editorSession.appendImportedImages(...)`”迁移到 `performCommand(.importImages(...))`。
  2. 将 `iOS` controller 的导入终点做同样迁移，并移除导入 helper 内部重复的刷新/历史按钮更新逻辑。
  3. 保持 open panel、pasteboard、drag and drop、photo picker、外接键盘粘贴这些平台入口不变，只调整导入末端收口方式。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - `CanvasImportRequest`、`CanvasCommand`、`CanvasCommandExecutor` 的新增与改造
  - transfer domain 的引入
  - 原始 gif diff
  - git commit / push

## 修改一：`macOS` 导入终点迁移到命令分发

### 修改前

- `macOSViewController.importResolvedImages(...)` 在 controller 内部直接调用 `editorSession.appendImportedImages(...)`。
- controller 自己负责 `dismissContextMenu()` 和 `refreshCanvas(reason:)`，导入行为还没有完全收口到 `performCommand(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改前 macOS 平台层直接调用 session 执行图片导入，并在 controller 内手动处理 context menu 收起和 refresh reason。
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
```

### 修改后

- `macOS` 导入 helper 现在只负责做空数组保护和构造 `CanvasImportRequest`。
- 真正的导入执行、旋转态取消、context menu 收起、刷新触发，统一交给 `performCommand(.importImages(...))` 以及其背后的 `CanvasCommandExecutor`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改后 macOS 平台层只负责组装共享 import request，然后统一走命令分发层执行导入。
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

    performCommand(
        .importImages(
            CanvasImportRequest(
                images: images,
                placement: placement,
                layout: layout,
                sourceDescription: source
            )
        )
    )
    return true
}
```

## 修改二：`iOS` 导入终点迁移到命令分发

### 修改前

- `iOSViewController.importResolvedImages(...)` 同样在 controller 里直接调用 `editorSession.appendImportedImages(...)`。
- 导入后由该 helper 自己调用 `requestCanvasRefresh(reason:)` 和 `updateHistoryButtonsAppearance()`，导致导入路径没有完全复用命令层已有的统一收口逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改前 iOS 平台层直接执行 session 导入，并在 helper 内自行刷新画布与 undo/redo 按钮状态。
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

### 修改后

- `iOS` 导入 helper 也改为只组装 `CanvasImportRequest` 并调用 `performCommand(.importImages(...))`。
- `requestCanvasRefresh(reason:)`、toolbar/undo/redo 按钮更新等 UI 收尾，改为复用 `performCommand(_:)` 已有的统一路径，避免 controller 导入 helper 和命令执行层同时持有一份刷新逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改后 iOS 平台层统一把已解析图片批次封装成命令 payload，再交由命令分发层处理刷新和状态同步。
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

    performCommand(
        .importImages(
            CanvasImportRequest(
                images: images,
                placement: placement,
                layout: layout,
                sourceDescription: source
            )
        )
    )
    return true
}
```

## 结果

- 到 `C-2` 为止，平台层导入入口仍然各自保留，但导入终点已经统一改成命令分发。
- 仓库内平台层对 `editorSession.appendImportedImages(...)` 的直接调用已移除，当前只保留 `CanvasCommandExecutor` 作为共享导入执行入口。

## 验证

```text
// 验证说明: 本阶段完成后，对最近修改文件执行 IDE lints 检查，并对全部 Swift 源文件执行 swiftc typecheck。
- ReadLints:
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - 结果：无错误

- swiftc -typecheck:
  - 范围：`MyCanvas_Ver_0` 下全部 `.swift` 源文件
  - 结果：通过
```
