# 20260323_114609_canvas_import_phase_d1_transfer_domain_record

## 记录范围

- 记录内容：
  1. 在共享层新增 `Canvas/Transfer` 领域，引入 `CanvasTransferItem`、`CanvasTransferRequest`。
  2. 新增 transfer -> import command 的 lowering 层，把 transfer request 下沉回当前稳定的 `.importImages(...)` 命令链。
  3. 将 `macOS` / `iOS` 平台 adapter 的公开输出从“已解析图片数组”升级为 `CanvasTransferRequest`。
  4. 将 `macOS` / `iOS` controller 的导入末端从“直接构造 `CanvasImportRequest`”升级为“执行 `CanvasTransferRequest`”。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferCommandLowerer.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - `CanvasImageItem` 运行时模型泛化
  - `BoardDocument` / `BoardDocumentMapper` / `BoardStore` 持久化格式改动
  - 第二种非图片 transfer item 的落地
  - 原始 gif diff
  - git commit / push

## 修改一：新增共享 transfer domain 类型

### 修改前

- 共享层只有 `CanvasImportRequest` 这类 image-import 语义对象。
- 仓库里还没有 `Canvas/Transfer` 目录，平台输入边界仍然停留在“已解析图片数组”。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名: N/A（新文件）
// 功能说明: 修改前仓库中不存在 transfer domain 类型；平台层无法用统一的 transfer request 语义承载 paste / drop / import。
[文件不存在]
```

### 修改后

- 新增 `CanvasTransferItem`，当前只实现 `.image(...)` 一种 item。
- 新增 `CanvasTransferRequest`，用来承载 `items`、`placement`、`layout`、`sourceDescription`，并保留从图片数组快速构造的兼容入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名: N/A（类型定义文件）
// 功能说明: 修改后共享层拥有独立的 transfer request 边界，平台输入先汇聚到 transfer，再决定如何下沉到当前导入命令链。
enum CanvasTransferItem {
    case image(CanvasResolvedImportImage)
}

struct CanvasTransferRequest {
    let items: [CanvasTransferItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        items: [CanvasTransferItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.items = items
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.init(
            items: images.map { .image($0) },
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }
}
```

## 修改二：新增 transfer -> import command lowering 层

### 修改前

- `CanvasCommandExecutor` 虽然已经能执行 `.importImages(...)`，但共享层还没有“把 transfer request lower 回 import request”的中间层。
- controller 只能直接构造 `CanvasImportRequest`，还不能把 transfer 作为一等输入语义。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferCommandLowerer.swift
// 函数名: N/A（新文件）
// 功能说明: 修改前不存在 transfer lowering 层，因此平台 controller 无法把 transfer request 统一下沉回既有 import command。
[文件不存在]
```

### 修改后

- 新增 `CanvasTransferCommandLowerer`，把 `CanvasTransferRequest` 转成现有的 `CanvasCommand.importImages(...)`。
- 当前只处理 `.image(...)` item，这样 `D-1` 先升级输入边界，不提前改运行时和文档模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferCommandLowerer.swift
// 函数名: loweredCommand(for:) / loweredImportRequest(for:)
// 功能说明: 修改后 transfer 层可以把 image-only transfer request 下沉成既有 import command，复用 C 阶段已经稳定的执行路径。
enum CanvasTransferCommandLowerer {
    static func loweredCommand(
        for request: CanvasTransferRequest
    ) -> CanvasCommand? {
        guard let importRequest = loweredImportRequest(for: request) else {
            return nil
        }

        return .importImages(importRequest)
    }

    static func loweredImportRequest(
        for request: CanvasTransferRequest
    ) -> CanvasImportRequest? {
        guard request.isEmpty == false else {
            return nil
        }

        var resolvedImages: [CanvasResolvedImportImage] = []
        resolvedImages.reserveCapacity(request.itemCount)

        for item in request.items {
            switch item {
            case let .image(image):
                resolvedImages.append(image)
            }
        }

        return CanvasImportRequest(
            images: resolvedImages,
            placement: request.placement,
            layout: request.layout,
            sourceDescription: request.sourceDescription
        )
    }
}
```

## 修改三：平台 adapter 的公开输出升级为 `CanvasTransferRequest`

### 修改前

- `macOS` / `iOS` adapter 对外公开的仍是 `resolvedImages(...)` 与 `canResolveImages(...)`。
- 它们能做图片解码，但语义上还停留在“图片导入”，不能表达更宽的 transfer pipeline。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: resolvedImages(from:) / canResolveImages(from:)
// 功能说明: 修改前 macOS adapter 只把平台输入解析成已解析图片数组，对外没有 transfer request API。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: resolvedImages(from:) / canResolveImages(from:)
// 功能说明: 修改前 iOS adapter 对外仍直接暴露已解析图片数组，picker / pasteboard / drop session 尚未统一升格为 transfer request。
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
    // ... 省略 unchanged decode helpers ...
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
```

### 修改后

- `macOS` / `iOS` adapter 现在对外公开 `transferRequest(...)` 和 `canResolveTransfer(...)`。
- 图片解码 helper 仍然保留在 adapter 内部，但平台层已经不再把 `[CanvasResolvedImportImage]` 暴露为顶层输出契约。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: transferRequest(from:sourceDescription:placement:layout:) / canResolveTransfer(from:)
// 功能说明: 修改后 macOS adapter 先把平台输入提升为 transfer request，再由共享 transfer 层决定如何下沉。
static func transferRequest(
    from urls: [URL],
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> CanvasTransferRequest? {
    makeTransferRequest(
        from: resolvedImages(from: urls),
        sourceDescription: sourceDescription,
        placement: placement,
        layout: layout
    )
}

static func transferRequest(
    from pasteboard: NSPasteboard,
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> CanvasTransferRequest? {
    // ... 省略 unchanged decode helpers ...
}

static func canResolveTransfer(from pasteboard: NSPasteboard) -> Bool {
    if imageFileURLs(from: pasteboard).isEmpty == false {
        return true
    }

    return NSImage(pasteboard: pasteboard) != nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: transferRequest(from:sourceDescription:placement:layout:) / canResolveTransfer(from:)
// 功能说明: 修改后 iOS adapter 把 picker、pasteboard、drop session 统一包装成 transfer request，对外隐藏 resolved image 数组细节。
static func transferRequest(
    from results: [PHPickerResult],
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) async -> CanvasTransferRequest? {
    let resolvedImages = await resolvedImages(
        from: results.map(\.itemProvider)
    )

    return makeTransferRequest(
        from: resolvedImages,
        sourceDescription: sourceDescription,
        placement: placement,
        layout: layout
    )
}

static func transferRequest(
    from pasteboard: UIPasteboard,
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) async -> CanvasTransferRequest? {
    // ... 省略 unchanged decode helpers ...
}

static func canResolveTransfer(
    from pasteboard: UIPasteboard
) -> Bool {
    if pasteboard.hasImages {
        return true
    }

    return pasteboard.itemProviders.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    }
}
```

## 修改四：平台 controller 改为执行 transfer request

### 修改前

- `macOS` / `iOS` controller 在平台 adapter 解码完成后，仍然直接构造 `CanvasImportRequest` 或调用 `importResolvedImages(...)`。
- 这意味着 controller 末端的架构语义仍然是“image import”，而不是更中性的 transfer pipeline。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick() / handlePasteRequest() / handleImportDrop(pasteboard:) / importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改前 macOS controller 直接拿 resolved images 构造 import command，transfer request 尚未成为平台末端语义。
let resolvedImages = macOSCanvasImportAdapter.resolvedImages(
    from: openPanel.urls
)
_ = self.importResolvedImages(
    resolvedImages,
    source: "open panel"
)

private func canImportImages(from pasteboard: NSPasteboard) -> Bool {
    macOSCanvasImportAdapter.canResolveImages(from: pasteboard)
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: dropInteraction(_:performDrop:) / picker(_:didFinishPicking:) / handlePasteRequest() / importResolvedImages(_:source:placement:layout:)
// 功能说明: 修改前 iOS controller 在 adapter 解析成功后，仍然把 resolved images 直接塞进 import command。
let resolvedImages = await iOSCanvasImportAdapter.resolvedImages(
    from: session
)
_ = self.importResolvedImages(
    resolvedImages,
    source: "drag and drop"
)

private func canImportImages(from pasteboard: UIPasteboard) -> Bool {
    iOSCanvasImportAdapter.canResolveImages(from: pasteboard)
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

### 修改后

- `macOS` / `iOS` controller 现在统一向 adapter 请求 `CanvasTransferRequest`，并通过 `performTransferRequest(_:)` 调用 `CanvasTransferCommandLowerer`。
- controller 末端语义已经升级成 transfer pipeline，但 lower 之后仍然复用当前稳定的 `.importImages(...)` 执行路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleImportButtonClick() / handlePasteRequest() / handleImportDrop(pasteboard:) / performTransferRequest(_:)
// 功能说明: 修改后 macOS controller 先获取 transfer request，再通过 lowerer 下沉到既有 import command。
guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
    from: openPanel.urls,
    sourceDescription: "open panel"
) else {
    return
}

_ = self.performTransferRequest(transferRequest)

private func canTransferContent(from pasteboard: NSPasteboard) -> Bool {
    macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: dropInteraction(_:performDrop:) / picker(_:didFinishPicking:) / handlePasteRequest() / performTransferRequest(_:)
// 功能说明: 修改后 iOS controller 把 picker、pasteboard、drop session 全部视为 transfer request，再统一走 lowerer。
guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
    from: session,
    sourceDescription: "drag and drop"
) else {
    return
}

_ = self.performTransferRequest(transferRequest)

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

@discardableResult
private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}
```

## 结果

- 到 `D-1` 为止，`paste` / `drop` / `import` 在输入边界上已经统一收敛为 transfer pipeline。
- 共享层新增了 transfer domain，但当前仍只支持 `.image(...)` 一种 item，并通过 lowerer 回落到既有 import command。
- `CanvasImageItem`、`BoardDocument`、`BoardDocumentMapper`、`BoardStore` 保持不变；这一步只升级 API 边界，不泛化运行时与持久化。

## 验证

```text
// 验证说明: 本阶段完成后，对 transfer 层及相关 adapter/controller 执行 IDE lints 检查，并对全部 Swift 源文件执行 swiftc typecheck。
- ReadLints:
  - `MyCanvas_Ver_0/Canvas/Transfer/`
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - 结果：无错误

- swiftc -typecheck:
  - 范围：`MyCanvas_Ver_0` 下全部 `.swift` 源文件
  - 结果：通过
```
