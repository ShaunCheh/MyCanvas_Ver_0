# 20260324_103646_gif_phase2_import_pipeline_record

## 记录范围

- 记录内容：
  1. 扩展导入模型，让导入结果除了首帧 `CGImage` 之外，还能携带原始图片数据、类型标识、文件名提示和 GIF 动画元数据入口。
  2. 改造 iOS / macOS 导入适配器，优先保留原始图片数据，而不是只解第一帧后立刻丢失源资源。
  3. 在 `CanvasEditorSession` 内为 transient 导入资源增加会话级挂账表，并处理历史回放时的保留策略。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 本记录不包含：
  - 阶段 0 契约记录
  - 阶段 1 资产模型切换记录
  - GIF 持久化到 `assets/`
  - `board.json` v4 存储迁移
  - GIF 自动播放实现
  - git commit / push

## 修改一：导入结果从“只有首帧”扩展为“首帧 + 原始资源 + 动画元数据入口”

### 修改前

- `CanvasResolvedImportImage` 只包含一个 `cgImage`。
- 导入层拿到图片后，只能把首帧像素带进后续链路，原始资源和 GIF 信息没有入口继续往下传。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: init(cgImage:) / makeTransientImageAsset()
// 功能说明: 修改前导入结果只包装首帧 cgImage，导入链路没有原始数据、类型标识或 GIF 帧信息的承载结构。
struct CanvasResolvedImportImage {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    var logicalPixelSize: CGSize {
        CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
    }

    func makeTransientImageAsset() -> CanvasImageAsset {
        CanvasImageAsset.transientStaticImage(cgImage: cgImage)
    }
}
```

### 修改后

- 新增 `CanvasImportedImageSource`、`CanvasAnimatedImageMetadata`、`CanvasTransientImageAssetPayload`、`CanvasTransientImageAssetRegistration`。
- `CanvasResolvedImportImage` 现在除了 `cgImage` 之外，还携带：
  - `assetKind`
  - `importedSource`
  - `animatedMetadata`
  - `logicalPixelSize`
- 新增 `init?(data:typeIdentifier:filenameHint:)`，让导入链路可以从原始二进制直接构造导入结果，并自动识别 GIF、多帧数量、帧延迟和循环次数。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: init(data:typeIdentifier:filenameHint:) / makeTransientImageAssetRegistration(assetID:) / animatedMetadata(from:contentType:)
// 功能说明: 修改后导入模型可以同时保留首帧、原始数据和 GIF 动画元数据入口，而不是只把一张静态首帧带进后续链路。
struct CanvasImportedImageSource: Equatable {
    let data: Data
    let typeIdentifier: String?
    let filenameHint: String?
}

struct CanvasAnimatedImageMetadata: Equatable {
    let frameCount: Int
    let frameDelayTimes: [TimeInterval]
    let loopCount: Int?
}

struct CanvasTransientImageAssetPayload: Equatable {
    let assetReference: CanvasImageAssetReference
    let source: CanvasImportedImageSource?
    let animatedMetadata: CanvasAnimatedImageMetadata?
}

struct CanvasTransientImageAssetRegistration {
    let asset: CanvasImageAsset
    let payload: CanvasTransientImageAssetPayload?
}

struct CanvasResolvedImportImage {
    let cgImage: CGImage
    let assetKind: CanvasImageAssetKind
    let importedSource: CanvasImportedImageSource?
    let animatedMetadata: CanvasAnimatedImageMetadata?
    let logicalPixelSize: CGSize

    init?(
        data: Data,
        typeIdentifier: String? = nil,
        filenameHint: String? = nil
    ) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
            explicitTypeIdentifier: typeIdentifier,
            imageSource: imageSource
        )
        let contentType = resolvedTypeIdentifier.map { UTType(importedAs: $0) }
        let animatedMetadata = Self.animatedMetadata(
            from: imageSource,
            contentType: contentType
        )
        let assetKind: CanvasImageAssetKind =
            contentType?.conforms(to: .gif) == true &&
            animatedMetadata != nil
            ? .animatedGIF
            : .staticImage

        self.init(
            cgImage: cgImage,
            assetKind: assetKind,
            importedSource: CanvasImportedImageSource(
                data: data,
                typeIdentifier: resolvedTypeIdentifier,
                filenameHint: filenameHint
            ),
            animatedMetadata: animatedMetadata
        )
    }

    func makeTransientImageAssetRegistration(
        assetID: UUID = UUID()
    ) -> CanvasTransientImageAssetRegistration {
        let asset = CanvasImageAsset.transientImage(
            kind: assetKind,
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize,
            assetID: assetID
        )
        let payload: CanvasTransientImageAssetPayload?
        if importedSource != nil || animatedMetadata != nil {
            payload = CanvasTransientImageAssetPayload(
                assetReference: asset.reference,
                source: importedSource,
                animatedMetadata: animatedMetadata
            )
        } else {
            payload = nil
        }

        return CanvasTransientImageAssetRegistration(
            asset: asset,
            payload: payload
        )
    }
}
```

## 修改二：图片资产工厂从“只有静态图助手”扩展为“按 kind 建 transient / persisted asset”

### 修改前

- `CanvasImageAssetReference` 和 `CanvasImageAsset` 只有静态图的辅助工厂。
- 导入层还不能直接按 `kind` 创建 `.animatedGIF` 类型的 transient 资产。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: transientStaticImage(...) / persistedStaticImage(...)
// 功能说明: 修改前资产工厂主要围绕 static image 设计，GIF 资源类型还没有统一的 transient / persisted 构造入口。
struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage

    static func transientStaticImage(
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: .staticImage,
            storage: .transient(assetID)
        )
    }

    static func persistedStaticImage(
        filename: String
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: .staticImage,
            storage: .persisted(filename: filename)
        )
    }
}

struct CanvasImageAsset {
    static func transientStaticImage(
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        // ...
    }

    static func persistedStaticImage(
        filename: String,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil
    ) -> CanvasImageAsset {
        // ...
    }
}
```

### 修改后

- `CanvasImageAssetReference` 增加通用 `transient(kind:)` / `persisted(kind:)` 工厂，并补了 `transientAnimatedGIF(...)`、`persistedAnimatedGIF(...)`。
- `CanvasImageAsset` 增加通用 `transientImage(kind:...)` / `persistedImage(kind:...)` 工厂，并补了 `transientAnimatedGIF(...)`。
- 阶段 2 的导入模型可以直接按识别出的 `assetKind` 生成正确的 transient asset。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: transient(kind:assetID:) / persisted(kind:filename:) / transientImage(kind:cgImage:logicalPixelSize:assetID:) / transientAnimatedGIF(...)
// 功能说明: 修改后图片资产工厂可以按资源种类构造 static image 或 animated GIF，为导入阶段保留 GIF 类型打通桥接入口。
struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage

    static func transient(
        kind: CanvasImageAssetKind,
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .transient(assetID)
        )
    }

    static func persisted(
        kind: CanvasImageAssetKind,
        filename: String
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .persisted(filename: filename)
        )
    }

    static func transientAnimatedGIF(
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        transient(kind: .animatedGIF, assetID: assetID)
    }
}

struct CanvasImageAsset {
    static func transientImage(
        kind: CanvasImageAssetKind,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .transient(kind: kind, assetID: assetID),
            poster: CanvasImagePoster(cgImage: cgImage),
            logicalPixelSize: logicalPixelSize
        )
    }

    static func transientAnimatedGIF(
        posterCGImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        transientImage(
            kind: .animatedGIF,
            cgImage: posterCGImage,
            logicalPixelSize: logicalPixelSize,
            assetID: assetID
        )
    }
}
```

## 修改三：iOS 导入适配器从“只解首帧”改为“优先保留原始数据”

### 修改前

- `iOSCanvasImportAdapter.resolvedImage(from:)` 直接 `loadDataRepresentation(forTypeIdentifier: UTType.image.identifier)`，然后创建 `CGImageSourceCreateImageAtIndex(..., 0, ...)`，只保留首帧。
- 这样 GIF 导入到这一层后，原始 GIF 数据和帧时间信息都丢了。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: resolvedImage(from:) / loadImageData(from:)
// 功能说明: 修改前 iOS 导入适配器只把 itemProvider 的图片数据解成首帧 CGImage，没有继续保留原始资源信息。
private static func resolvedImage(
    from itemProvider: NSItemProvider
) async -> CanvasResolvedImportImage? {
    guard
        itemProvider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ),
        let data = await loadImageData(from: itemProvider),
        let imageSource = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ),
        let cgImage = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            nil
        )
    else {
        return nil
    }

    return CanvasResolvedImportImage(cgImage: cgImage)
}

private static func loadImageData(
    from itemProvider: NSItemProvider
) async -> Data? {
    await withCheckedContinuation { continuation in
        itemProvider.loadDataRepresentation(
            forTypeIdentifier: UTType.image.identifier
        ) { data, _ in
            continuation.resume(returning: data)
        }
    }
}
```

### 修改后

- 先通过 `preferredImageTypeIdentifier(from:)` 选择更具体的图片类型标识，优先拿到 GIF 等原始类型。
- `resolvedImage(from:)` 直接用原始 `Data` 构造 `CanvasResolvedImportImage(data:typeIdentifier:filenameHint:)`。
- 对于只能拿到 `UIImage` 的降级路径，优先转为 PNG data 再走统一导入模型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: resolvedImage(from:) / loadImageData(from:typeIdentifier:) / preferredImageTypeIdentifier(from:)
// 功能说明: 修改后 iOS 导入适配器优先保留 itemProvider 的原始图片数据和具体类型标识，而不是只保留首帧 CGImage。
private static func resolvedImage(
    from itemProvider: NSItemProvider
) async -> CanvasResolvedImportImage? {
    let preferredTypeIdentifier =
        preferredImageTypeIdentifier(from: itemProvider) ??
        UTType.image.identifier
    guard
        itemProvider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ),
        let data = await loadImageData(
            from: itemProvider,
            typeIdentifier: preferredTypeIdentifier
        ),
        let resolvedImage = CanvasResolvedImportImage(
            data: data,
            typeIdentifier: preferredTypeIdentifier,
            filenameHint: itemProvider.suggestedName
        )
    else {
        return nil
    }

    return resolvedImage
}

private static func loadImageData(
    from itemProvider: NSItemProvider,
    typeIdentifier: String
) async -> Data? {
    await withCheckedContinuation { continuation in
        itemProvider.loadDataRepresentation(
            forTypeIdentifier: typeIdentifier
        ) { data, _ in
            continuation.resume(returning: data)
        }
    }
}

private static func preferredImageTypeIdentifier(
    from itemProvider: NSItemProvider
) -> String? {
    let specificImageTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
        $0 != UTType.image.identifier &&
            UTType(importedAs: $0).conforms(to: .image)
    }
    if let specificImageTypeIdentifier {
        return specificImageTypeIdentifier
    }

    guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
        return nil
    }

    return UTType.image.identifier
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasImportAdapter.swift
// 函数名: makeResolvedImportImage(from:)
// 功能说明: 修改后 iOS 的 UIImage 降级路径会优先编码为 PNG Data，再复用统一的导入模型。
private static func makeResolvedImportImage(
    from image: UIImage
) -> CanvasResolvedImportImage? {
    if let pngData = image.pngData(),
       let resolvedImage = CanvasResolvedImportImage(
           data: pngData,
           typeIdentifier: UTType.png.identifier
       ) {
        return resolvedImage
    }

    if let cgImage = image.cgImage {
        return CanvasResolvedImportImage(cgImage: cgImage)
    }

    // ...
}
```

## 修改四：macOS 导入适配器从“读 URL 后只解首帧”改为“优先保留原始文件数据”

### 修改前

- `macOSCanvasImportAdapter.makeResolvedImportImage(from url:)` 直接对 `URL` 创建 `CGImageSource`，然后取第 `0` 帧。
- 对于文件导入的 GIF，这一步同样会把原始资源退化成静态首帧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: makeResolvedImportImage(from url:)
// 功能说明: 修改前 macOS 文件导入路径直接从 URL 解出第 0 帧 CGImage，原始 GIF 资源没有继续保留。
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
```

### 修改后

- 文件 URL 路径先读原始 `Data`，再交给 `CanvasResolvedImportImage(data:typeIdentifier:filenameHint:)`。
- 增加 `resolvedTypeIdentifier(from:)`，从文件资源值或扩展名推导类型。
- `NSImage` 降级路径也会优先编码成 PNG data 后再走统一导入模型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: makeResolvedImportImage(from url:) / resolvedTypeIdentifier(from:)
// 功能说明: 修改后 macOS 文件导入优先保留原始文件数据和类型标识，避免 GIF 在导入入口就退化成一张静态图。
private static func makeResolvedImportImage(
    from url: URL
) -> CanvasResolvedImportImage? {
    guard let assetData = try? Data(contentsOf: url) else {
        return nil
    }

    return CanvasResolvedImportImage(
        data: assetData,
        typeIdentifier: resolvedTypeIdentifier(from: url),
        filenameHint: url.lastPathComponent
    )
}

private static func resolvedTypeIdentifier(
    from url: URL
) -> String? {
    if let resourceValues = try? url.resourceValues(
        forKeys: [.contentTypeKey]
    ),
       let contentType = resourceValues.contentType {
        return contentType.identifier
    }

    guard url.pathExtension.isEmpty == false else {
        return nil
    }

    return UTType(filenameExtension: url.pathExtension)?.identifier
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasImportAdapter.swift
// 函数名: makeResolvedImportImage(from image:) / makePNGData(from:)
// 功能说明: 修改后 macOS 的 NSImage 降级路径也会尽量先还原为 PNG Data，再统一进入新的导入模型。
private static func makeResolvedImportImage(
    from image: NSImage
) -> CanvasResolvedImportImage? {
    var proposedRect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil
    ) else {
        return nil
    }

    if let pngData = makePNGData(from: cgImage),
       let resolvedImage = CanvasResolvedImportImage(
           data: pngData,
           typeIdentifier: UTType.png.identifier
       ) {
        return resolvedImage
    }

    return CanvasResolvedImportImage(cgImage: cgImage)
}
```

## 修改五：`CanvasEditorSession` 增加 transient 导入资源挂账表，并处理历史回放保留策略

### 修改前

- `CanvasEditorSession` 没有专门的 transient 导入资源挂账表。
- `appendImportedImages(...)` 虽然会生成 `CanvasImageAsset`，但不会额外挂账原始资源和 GIF 元数据。
- `applyBoardRuntimeState(...)` 每次恢复运行时状态时，也没有“保留 transient 导入资产”的控制参数。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: 字段定义 / appendImportedImages(_:placement:layout:) / applyBoardRuntimeState(_:)
// 功能说明: 修改前 Session 只把导入图片转成 asset 后追加到 scene，没有额外的 transient 导入资源注册表。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let contextResolver = CanvasContextResolver()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()
private let boardStoreLogPrefix: String

func applyBoardRuntimeState(_ runtimeState: BoardRuntimeState) {
    // ...
    rotationInteractionState = nil
    lastRenderSnapshot = .empty
}

for (index, image) in images.enumerated() {
    let asset = image.makeTransientImageAsset()
    let item = CanvasImageItem(
        asset: asset,
        center: CGPoint(
            x: importCenter.x + offset.x,
            y: importCenter.y + offset.y
        ),
        size: normalizedDisplaySize(for: asset.logicalPixelSize),
        zIndex: startingZIndex + CGFloat(index)
    )
}
```

### 修改后

- 新增 `transientImageAssetPayloads` 字典，按 `CanvasImageAssetReference` 挂账本会话导入的原始资源与 GIF 元数据。
- 新增 `transientImageAssetPayload(for:)` 查询入口。
- `appendImportedImages(...)` 现在会使用 `makeTransientImageAssetRegistration()`，在创建 item 前先把 payload 注册到 session。
- `applyBoardRuntimeState(...)` 增加 `preserveTransientImageAssetPayloads` 参数；正常换板会清空挂账表，历史回放场景可以保留，避免 `undo/redo` 后 transient 导入资源丢失。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: transientImageAssetPayload(for:)
// 功能说明: 修改后 Session 增加会话级 transient 资源挂账表，用来承载尚未持久化的原始图片数据和 GIF 元数据入口。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let contextResolver = CanvasContextResolver()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()
private let boardStoreLogPrefix: String
private var transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]

func transientImageAssetPayload(
    for assetReference: CanvasImageAssetReference
) -> CanvasTransientImageAssetPayload? {
    transientImageAssetPayloads[assetReference]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: applyBoardRuntimeState(_:preserveTransientImageAssetPayloads:)
// 功能说明: 修改后 Session 在换板和历史回放之间区分 transient 资源表的清理策略，避免导入后的 GIF 原始数据在 undo/redo 时丢失。
func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    // ...
    rotationInteractionState = nil
    if preserveTransientImageAssetPayloads == false {
        transientImageAssetPayloads.removeAll()
    }
    lastRenderSnapshot = .empty
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendImportedImages(_:placement:layout:)
// 功能说明: 修改后导入图片会先生成 transient asset registration，并把原始资源 payload 注册到 Session，再创建 CanvasImageItem。
for (index, image) in images.enumerated() {
    let importRegistration = image.makeTransientImageAssetRegistration()
    let asset = importRegistration.asset
    if let payload = importRegistration.payload {
        transientImageAssetPayloads[payload.assetReference] = payload
    }
    let item = CanvasImageItem(
        asset: asset,
        center: CGPoint(
            x: importCenter.x + offset.x,
            y: importCenter.y + offset.y
        ),
        size: normalizedDisplaySize(for: asset.logicalPixelSize),
        zIndex: startingZIndex + CGFloat(index)
    )
}
```

## 阶段 2 完成状态

- 已完成：
  - 导入模型开始保留原始图片数据、类型标识和 GIF 动画元数据入口
  - 图片资产工厂支持按 `kind` 创建 transient / persisted asset
  - iOS / macOS 导入适配器优先保留原始图片数据
  - Session 增加 transient 导入资源挂账表
  - 历史回放场景下保留 transient 导入资源，避免 `undo/redo` 后丢失
- 未完成：
  - 将 transient 导入资源真正持久化到 `assets/`
  - `board.json` 写入 GIF 资源元数据
  - 读取持久化 GIF 资源并恢复播放能力
  - 主画布自动播放 GIF
