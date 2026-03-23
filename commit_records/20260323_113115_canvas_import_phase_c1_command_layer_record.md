# 20260323_113115_canvas_import_phase_c1_command_layer_record

## 记录范围

- 记录内容：
  1. 为共享导入层新增 `CanvasImportRequest`，把“已解析图片批次 + placement/layout + 来源描述”封装成命令层可消费的 payload。
  2. 为 `CanvasCommandID` / `CanvasCommand` 新增 `importImages` case，并让其进入 rotation-cancel 语义。
  3. 为 `CanvasCommandExecutor` 新增 import command 的 `canExecute` / `execute` 分支。
  4. 为 `CanvasCommandCatalog`、`CanvasContextMenuCommandResolver`、`macOSViewController.performCommand(withID:)` 补齐新增命令后的兼容分支。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `macOS` / `iOS` controller 全面迁移到 `performCommand(.importImages(...))`
  - import command 加入 context menu 或 descriptor-driven toolbar enablement
  - 原始 gif diff
  - git commit / push

## 修改一：为导入命令新增共享 payload `CanvasImportRequest`

### 修改前

- `Canvas/Import` 层只有 `CanvasResolvedImportImage`、`CanvasImportPlacement`、`CanvasImportLayout`。
- 共享层虽然已经能批量导入图片，但命令层还没有一个正式的请求对象来承载“图片数组 + placement/layout + 来源描述”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名: CanvasResolvedImportImage / CanvasImportPlacement / CanvasImportLayout
// 功能说明: 修改前 import contract 只定义了已解析图片、插入位置和排布策略，还没有命令层可直接消费的导入请求对象。
struct CanvasResolvedImportImage {
    let cgImage: CGImage
}

enum CanvasImportPlacement: Equatable {
    case cameraCenter
    case worldPoint(CGPoint)
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
}
```

### 修改后

- 新增 `CanvasImportRequest`，把 `images`、`placement`、`layout`、`sourceDescription` 封装成共享 payload。
- 同时补了 `imageCount` 和 `isEmpty`，让 executor 在执行前可以直接做轻量判断。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名: CanvasImportRequest
// 功能说明: 修改后命令层可以直接接收一个共享导入请求，而不用把多段参数零散塞进 command case。
struct CanvasImportRequest {
    let images: [CanvasResolvedImportImage]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.images = images
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    // 让命令执行层快速判断批次规模和空请求。
    var imageCount: Int {
        images.count
    }

    var isEmpty: Bool {
        images.isEmpty
    }
}
```

## 修改二：把 import 正式纳入 `CanvasCommand`

### 修改前

- `CanvasCommandID` 和 `CanvasCommand` 只覆盖 crop、undo/redo、选择、复制、删除、层级调整。
- 导入还不属于命令层，因此也不会自动进入 `shouldCancelActiveRotation` 的统一行为。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 类型名: CanvasCommandID / CanvasCommand
// 功能说明: 修改前命令层没有 importImages case，导入仍然停留在 controller 直调 session 的模式。
enum CanvasCommandID: String {
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
    case duplicateItem
    case deleteItem
    case bringItemForward
    case sendItemBackward
    case bringItemToFront
    case sendItemToBack
}

enum CanvasCommand {
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasImageItemID, recordHistory: Bool)
}
```

### 修改后

- `CanvasCommandID` 新增 `importImages`。
- `CanvasCommand` 新增 `case importImages(CanvasImportRequest)`。
- `id` 映射和 `shouldCancelActiveRotation` 也同步把 import 纳入，保证导入命令和其他会改变画板内容的命令共享同一套 rotation cancel 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 类型名: CanvasCommandID / CanvasCommand / shouldCancelActiveRotation
// 功能说明: 修改后导入正式成为共享命令层的一员，并自动享受旋转态清理等命令通用行为。
enum CanvasCommandID: String {
    case importImages
    case crop
    case undo
    case redo
    case selectItem
    case clearSelection
    case duplicateItem
    case deleteItem
    case bringItemForward
    case sendItemBackward
    case bringItemToFront
    case sendItemToBack
}

enum CanvasCommand {
    case importImages(CanvasImportRequest)
    case crop
    case undo
    case redo
    case selectItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case clearSelection(recordHistory: Bool)
    case duplicateItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case deleteItem(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemForward(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemBackward(itemID: CanvasImageItemID, recordHistory: Bool)
    case bringItemToFront(itemID: CanvasImageItemID, recordHistory: Bool)
    case sendItemToBack(itemID: CanvasImageItemID, recordHistory: Bool)

    var id: CanvasCommandID {
        switch self {
        case .importImages:
            return .importImages
        case .crop:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            return .selectItem
        case .clearSelection:
            return .clearSelection
        case .duplicateItem:
            return .duplicateItem
        case .deleteItem:
            return .deleteItem
        case .bringItemForward:
            return .bringItemForward
        case .sendItemBackward:
            return .sendItemBackward
        case .bringItemToFront:
            return .bringItemToFront
        case .sendItemToBack:
            return .sendItemToBack
        }
    }

    var shouldCancelActiveRotation: Bool {
        switch self {
        case .importImages,
             .crop,
             .undo,
             .redo,
             .selectItem,
             .clearSelection,
             .duplicateItem,
             .deleteItem,
             .bringItemForward,
             .sendItemBackward,
             .bringItemToFront,
             .sendItemToBack:
            return true
        }
    }
}
```

## 修改三：让 `CanvasCommandExecutor` 能真正执行 import command

### 修改前

- `CanvasCommandExecutor.canExecute(_:)` 和 `execute(_:)` 里都没有 import 分支。
- 即使外层未来构造了 import command，executor 也无法判断是否可执行，更无法调用共享导入核心。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改前 executor 对导入命令一无所知，只能处理编辑类命令。
func canExecute(_ command: CanvasCommand) -> Bool {
    switch command {
    case .crop:
        return session.isInlineCropModeActive || session.canBeginCropMode
    case .undo:
        return session.canUndoCommand
    case .redo:
        return session.canRedoCommand
    case let .selectItem(itemID, _):
        return session.canSelectItem(withID: itemID)
    // ... existing edit commands only ...
    }
}

func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
    guard canExecute(command) else {
        return nil
    }

    switch command {
    case .crop:
        // ... existing crop flow ...
        return CanvasCommandExecutionResult(refreshReason: "enter crop mode")
    // ... existing edit commands only ...
    }
}
```

### 修改后

- `canExecute(_:)` 为 `.importImages(request)` 增加了非空批次判断。
- `execute(_:)` 为 import command 直接复用 `session.appendImportedImages(...)`。
- executor 在成功导入后返回标准化 `refreshReason`，为后续 `C-2` 的 controller 统一迁移铺平路径。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改后 executor 已经能够校验并执行共享导入命令，把 import payload 正式桥接到 session 的批量导入核心。
func canExecute(_ command: CanvasCommand) -> Bool {
    switch command {
    case let .importImages(request):
        return request.isEmpty == false
    case .crop:
        return session.isInlineCropModeActive || session.canBeginCropMode
    case .undo:
        return session.canUndoCommand
    case .redo:
        return session.canRedoCommand
    case let .selectItem(itemID, _):
        return session.canSelectItem(withID: itemID)
    // ... existing edit commands ...
    }
}

func execute(_ command: CanvasCommand) -> CanvasCommandExecutionResult? {
    guard canExecute(command) else {
        return nil
    }

    switch command {
    case let .importImages(request):
        let importedItems = session.appendImportedImages(
            request.images,
            placement: request.placement,
            layout: request.layout
        )
        let imageCount = importedItems.count
        let imageLabel = imageCount == 1 ? "image" : "images"
        let sourceDescription = request.sourceDescription.isEmpty
            ? ""
            : " from \(request.sourceDescription)"
        return CanvasCommandExecutionResult(
            refreshReason: "import \(imageCount) \(imageLabel)\(sourceDescription)"
        )
    case .crop:
        // ... existing crop flow ...
        return CanvasCommandExecutionResult(refreshReason: "enter crop mode")
    // ... existing edit commands ...
    }
}
```

## 修改四：为周边命令系统补齐新增 case 的兼容分支

### 修改前

- `CanvasCommandCatalog`、`CanvasContextMenuCommandResolver`、`macOSViewController.performCommand(withID:)` 都是基于旧的命令枚举写的 exhaustive switch。
- 一旦加上 `importImages`，这些地方要么编译不过，要么会把 import 错误地暴露到不该出现的位置。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名: descriptor(for:session:context:)
// 功能说明: 修改前 command catalog 没有 importImages descriptor。
switch commandID {
case .crop:
    // ...
case .undo:
    // ...
case .redo:
    // ...
// ... existing edit commands only ...
}

// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: command(for:context:)
// 功能说明: 修改前 context menu resolver 也没有 importImages 分支。
switch commandID {
case .crop:
    return .crop
case .undo:
    return .undo
case .redo:
    return .redo
// ... existing edit commands only ...
}
```

### 修改后

- `CanvasCommandCatalog` 为 `importImages` 补了 descriptor 占位，但先保持 `isEnabled = false`，避免在 `C-1` 就把 import 暴露到 descriptor-driven UI。
- `CanvasContextMenuCommandResolver` 对 `importImages` 明确返回 `nil`，防止 context menu 误生成导入命令。
- `macOSViewController.performCommand(withID:)` 也显式补上 `.importImages` 分支，先保持 `break`，仅用于命令枚举补全与编译稳定。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名: descriptor(for:session:context:)
// 功能说明: 修改后先为 importImages 提供禁用态 descriptor，占住命令层位置，但暂时不让它进入 UI 驱动流。
switch commandID {
case .importImages:
    return CanvasCommandDescriptor(
        id: .importImages,
        title: "Import Images",
        systemImageName: "photo.on.rectangle.angled",
        isEnabled: false,
        isActive: false
    )
case .crop:
    // ...
case .undo:
    // ...
case .redo:
    // ...
// ... existing edit commands ...
}

// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: command(for:context:)
// 功能说明: 修改后 context menu 明确忽略 importImages，避免导入命令在 C-1 阶段误入上下文菜单。
switch commandID {
case .importImages:
    return nil
case .crop:
    return .crop
case .undo:
    return .undo
case .redo:
    return .redo
// ... existing edit commands ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: performCommand(withID:)
// 功能说明: 修改后 macOS controller 的 commandID switch 显式补齐 importImages case，保持编译稳定，但暂不在这里触发导入行为。
func performCommand(withID commandID: CanvasCommandID) {
    switch commandID {
    case .importImages:
        break
    case .crop:
        performCommand(CanvasCommand.crop)
    case .undo:
        performCommand(CanvasCommand.undo)
    case .redo:
        performCommand(CanvasCommand.redo)
    case .selectItem,
         .clearSelection,
         .duplicateItem,
         .deleteItem,
         .bringItemForward,
         .sendItemBackward,
         .bringItemToFront,
         .sendItemToBack:
        break
    }
}
```

## 影响说明

- 这次 `C-1` 完成后，共享命令层已经具备“承载导入请求并执行导入”的能力。
- 当前 `macOS` / `iOS` controller 还没有全部改成 `performCommand(.importImages(...))`，所以现有平台入口行为保持不变。
- `CanvasCommandCatalog` 对 `importImages` 先是禁用 descriptor，占位但不暴露到 UI；这是刻意把“命令支持”与“UI 接入”拆成两个阶段。
- `CanvasContextMenuCommandResolver` 对 `importImages` 返回 `nil`，也是为了避免在 `C-1` 阶段把导入误塞进上下文菜单。

## 校验说明

- 已检查 `CanvasImportTypes.swift`、`CanvasCommand.swift`、`CanvasCommandExecutor.swift`、`CanvasCommandCatalog.swift`、`CanvasContextMenuCommandResolver.swift`、`macOSViewController.swift`，当前未发现新增 lint 报错。
- 已使用 `swiftc -typecheck` 对全量 Swift 源码集合进行静态类型检查，当前通过。
- 本次未进行完整 UI 运行验证；当前记录基于代码差异、lints 与静态类型检查结果。
