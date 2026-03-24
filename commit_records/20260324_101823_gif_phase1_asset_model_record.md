# 20260324_101823_gif_phase1_asset_model_record

## 记录范围

- 记录内容：
  1. 将运行时图片模型从“直接持有单个 `CGImage`”切换为“持有图片资产 `CanvasImageAsset` + poster 元数据”。
  2. 为图片展示层增加资产引用、poster 图、逻辑像素尺寸等桥接字段。
  3. 将导入、渲染、存储、缩略图路径桥接到新的资产模型，保证阶段 1 结束后静态图仍能继续工作。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 本记录不包含：
  - 阶段 0 契约记录
  - GIF 原始资源保留
  - GIF 导入元数据扩展
  - GIF 自动播放实现
  - `board.json` v4 升级
  - git commit / push

## 修改一：新增图片资产模型文件

### 修改前

- 项目里还没有独立的图片资产模型文件。
- `CanvasImageItem` 直接持有 `CGImage`，还没有把“资源引用、poster 图、逻辑像素尺寸”抽离成单独抽象。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: 无（文件尚不存在）
// 功能说明: 修改前项目内没有独立的图片资产模型文件，运行时图片资源没有专门的引用层与 poster 层。
```

### 修改后

- 新增 `CanvasImageAssetKind`、`CanvasImageAssetStorage`、`CanvasImageAssetReference`、`CanvasImagePoster`、`CanvasImageAsset`。
- 当前阶段 1 先铺好静态图桥接能力，同时预留 `.animatedGIF` 资产种类给后续阶段。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAsset.swift
// 函数名: transientStaticImage(...) / persistedStaticImage(...) / posterCGImage
// 功能说明: 修改后引入统一图片资产模型；运行时 item 不再直接只认 CGImage，而是通过 asset 持有资源引用、poster 图与逻辑像素尺寸。
enum CanvasImageAssetKind: String, Codable, Equatable, Hashable {
    case staticImage
    case animatedGIF
}

enum CanvasImageAssetStorage: Equatable, Hashable {
    case transient(UUID)
    case persisted(filename: String)
}

struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage
}

struct CanvasImagePoster {
    let cgImage: CGImage
}

struct CanvasImageAsset {
    let reference: CanvasImageAssetReference
    let poster: CanvasImagePoster
    let logicalPixelSize: CGSize

    static func transientStaticImage(
        cgImage: CGImage,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .transientStaticImage(assetID: assetID),
            poster: CanvasImagePoster(cgImage: cgImage)
        )
    }

    static func persistedStaticImage(
        filename: String,
        cgImage: CGImage
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .persistedStaticImage(filename: filename),
            poster: CanvasImagePoster(cgImage: cgImage)
        )
    }
}
```

## 修改二：`CanvasImageItem` 从直接持有 `CGImage` 改为持有 `CanvasImageAsset`

### 修改前

- `CanvasImageItem` 的资源字段是 `let cgImage: CGImage`。
- 初始化、复制、历史比较都围绕单个 `CGImage` 展开。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: init(...) / duplicated(offsetInWorld:) / matchesDocumentState(_:)
// 功能说明: 修改前图片项直接持有 CGImage；复制与历史比较也直接围绕 cgImage 工作。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.cgImage = cgImage
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
        CanvasImageItem(
            cgImage: cgImage,
            center: CGPoint(
                x: center.x + offsetInWorld.x,
                y: center.y + offsetInWorld.y
            ),
            size: size,
            zIndex: zIndex,
            cropRectNormalized: cropRectNormalized,
            rotationRadians: rotationRadians
        )
    }

    func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
        id == other.id &&
            cgImage === other.cgImage &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            cropRectNormalized == other.cropRectNormalized &&
            rotationRadians == other.rotationRadians
    }
}
```

### 修改后

- `CanvasImageItem` 的资源字段改为 `let asset: CanvasImageAsset`。
- 新增 `assetReference`、`assetKind`、`posterCGImage`、`logicalPixelSize` 四个桥接访问器。
- 复制与历史比较不再直接认裸 `CGImage`，而是通过 `asset` / `assetReference` 运转。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: init(...) / assetReference / posterCGImage / duplicated(offsetInWorld:) / matchesDocumentState(_:)
// 功能说明: 修改后图片项切换到资产模型；几何仍留在 item 上，资源本身从单个 cgImage 提升为 asset + poster 结构。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let asset: CanvasImageAsset
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        asset: CanvasImageAsset,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.asset = asset
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    var assetReference: CanvasImageAssetReference {
        asset.reference
    }

    var posterCGImage: CGImage {
        asset.posterCGImage
    }

    var logicalPixelSize: CGSize {
        asset.logicalPixelSize
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
        CanvasImageItem(
            asset: asset,
            center: CGPoint(
                x: center.x + offsetInWorld.x,
                y: center.y + offsetInWorld.y
            ),
            size: size,
            zIndex: zIndex,
            cropRectNormalized: cropRectNormalized,
            rotationRadians: rotationRadians
        )
    }

    func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
        id == other.id &&
            assetReference == other.assetReference &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            cropRectNormalized == other.cropRectNormalized &&
            rotationRadians == other.rotationRadians
    }
}
```

## 修改三：图片展示层开始携带资产引用、poster 图与逻辑尺寸

### 修改前

- `CanvasImagePresentation` 只携带一个 `cgImage`。
- `CanvasImagePresentationResolver` 也只是把 `effectiveItem.cgImage` 透传到 presentation。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift
// 函数名: 无（结构体字段定义）
// 功能说明: 修改前图片 presentation 只有单帧 cgImage，展示层还不知道 asset 引用和逻辑像素尺寸。
struct CanvasImagePresentation {
    let itemID: CanvasImageItemID
    let cgImage: CGImage
    let zIndex: CGFloat
    let effectiveRotationRadians: CGFloat
    let effectiveCropRectNormalized: CanvasImageCropRect
    let visibleLocalFrame: CGRect
    let visibleWorldQuad: CanvasQuad
    let visibleCenter: CGPoint
    let visibleSize: CGSize
    let fullImageLocalFrame: CGRect
    let fullImageWorldQuad: CanvasQuad
    let fullImageCenter: CGPoint
    let fullImageSize: CGSize
    let isCropPreviewActive: Bool
    let isRotationPreviewActive: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数名: resolve(item:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 resolver 只把 effectiveItem.cgImage 填进 presentation，展示层没有 asset 语义。
return CanvasImagePresentation(
    itemID: effectiveItem.id,
    cgImage: effectiveItem.cgImage,
    zIndex: effectiveItem.zIndex,
    effectiveRotationRadians: effectiveItem.rotationRadians,
    effectiveCropRectNormalized: effectiveCropRectNormalized,
    visibleLocalFrame: visibleLocalFrame,
    visibleWorldQuad: visibleWorldQuad,
    visibleCenter: visibleCenter,
    visibleSize: visibleLocalFrame.size,
    fullImageLocalFrame: fullImageLocalFrame,
    fullImageWorldQuad: fullImageWorldQuad,
    fullImageCenter: fullImageCenter,
    fullImageSize: fullImageLocalFrame.size,
    isCropPreviewActive: isCropPreviewActive,
    isRotationPreviewActive: isRotationPreviewActive
)
```

### 修改后

- `CanvasImagePresentation` 增加 `assetReference`、`assetKind`、`posterCGImage`、`logicalPixelSize`。
- `CanvasImagePresentationResolver` 改为从 `CanvasImageItem` 读取这些桥接数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift
// 函数名: 无（结构体字段定义）
// 功能说明: 修改后图片 presentation 开始显式携带 asset 引用、poster 图和逻辑像素尺寸，为后续动画播放与资源持久化做准备。
struct CanvasImagePresentation {
    let itemID: CanvasImageItemID
    let assetReference: CanvasImageAssetReference
    let assetKind: CanvasImageAssetKind
    let posterCGImage: CGImage
    let logicalPixelSize: CGSize
    let zIndex: CGFloat
    let effectiveRotationRadians: CGFloat
    let effectiveCropRectNormalized: CanvasImageCropRect
    let visibleLocalFrame: CGRect
    let visibleWorldQuad: CanvasQuad
    let visibleCenter: CGPoint
    let visibleSize: CGSize
    let fullImageLocalFrame: CGRect
    let fullImageWorldQuad: CanvasQuad
    let fullImageCenter: CGPoint
    let fullImageSize: CGSize
    let isCropPreviewActive: Bool
    let isRotationPreviewActive: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数名: resolve(item:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 resolver 不再透传裸 cgImage，而是把图片项的 asset 引用、poster 图、逻辑尺寸一起传给 presentation。
return CanvasImagePresentation(
    itemID: effectiveItem.id,
    assetReference: effectiveItem.assetReference,
    assetKind: effectiveItem.assetKind,
    posterCGImage: effectiveItem.posterCGImage,
    logicalPixelSize: effectiveItem.logicalPixelSize,
    zIndex: effectiveItem.zIndex,
    effectiveRotationRadians: effectiveItem.rotationRadians,
    effectiveCropRectNormalized: effectiveCropRectNormalized,
    visibleLocalFrame: visibleLocalFrame,
    visibleWorldQuad: visibleWorldQuad,
    visibleCenter: visibleCenter,
    visibleSize: visibleLocalFrame.size,
    fullImageLocalFrame: fullImageLocalFrame,
    fullImageWorldQuad: fullImageWorldQuad,
    fullImageCenter: fullImageCenter,
    fullImageSize: fullImageLocalFrame.size,
    isCropPreviewActive: isCropPreviewActive,
    isRotationPreviewActive: isRotationPreviewActive
)
```

## 修改四：导入链路从“直接喂 `cgImage`”桥接为“先生成 transient asset”

### 修改前

- `CanvasResolvedImportImage` 只有 `cgImage` 本身，没有资产构造辅助。
- `CanvasEditorSession.appendImportedImages(...)` 直接拿 `image.cgImage` 创建 `CanvasImageItem`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: init(cgImage:)
// 功能说明: 修改前导入结果只包装单个 cgImage，还没有把导入结果桥接成运行时资产对象。
struct CanvasResolvedImportImage {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: normalizedDisplaySize(for:) / appendImportedImages(_:placement:layout:)
// 功能说明: 修改前 Session 直接从 cgImage 读像素尺寸，并直接构造 CanvasImageItem(cgImage:...)。
func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
    let pixelSize = CGSize(
        width: cgImage.width,
        height: cgImage.height
    )
    let longestSide = max(pixelSize.width, pixelSize.height)
    guard longestSide > 0 else {
        return CGSize(width: 240, height: 240)
    }
    // ...
}

for (index, image) in images.enumerated() {
    let item = CanvasImageItem(
        cgImage: image.cgImage,
        center: CGPoint(
            x: importCenter.x + offset.x,
            y: importCenter.y + offset.y
        ),
        size: normalizedDisplaySize(for: image.cgImage),
        zIndex: startingZIndex + CGFloat(index)
    )
}
```

### 修改后

- `CanvasResolvedImportImage` 增加 `logicalPixelSize` 和 `makeTransientImageAsset()`。
- `CanvasEditorSession` 增加 `normalizedDisplaySize(for pixelSize:)`，并在导入时先构造 transient asset，再用 asset 的逻辑像素尺寸创建 item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名: logicalPixelSize / makeTransientImageAsset()
// 功能说明: 修改后导入结果可以先转换成 transient asset，为后续保留 GIF 原始资源和扩展导入元数据做桥接。
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

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: normalizedDisplaySize(for pixelSize:) / appendImportedImages(_:placement:layout:)
// 功能说明: 修改后导入流程先生成 transient asset，再用 asset.logicalPixelSize 计算显示尺寸并构造 CanvasImageItem(asset:...)。
func normalizedDisplaySize(for cgImage: CGImage) -> CGSize {
    normalizedDisplaySize(
        for: CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
    )
}

func normalizedDisplaySize(for pixelSize: CGSize) -> CGSize {
    let longestSide = max(pixelSize.width, pixelSize.height)
    guard longestSide > 0 else {
        return CGSize(width: 240, height: 240)
    }
    // ...
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

## 修改五：渲染路径从 `presentation.cgImage` 改为 `presentation.posterCGImage`

### 修改前

- `CanvasRenderer.makeImageRenderItem(...)` 仍然把 `presentation.cgImage` 塞进 `CanvasImageRenderPayload`。
- 这意味着渲染契约还直接依赖单帧位图字段。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 直接把 presentation.cgImage 放入 render payload，渲染路径仍绑定单帧图片字段。
payload: .image(
    CanvasImageRenderPayload(
        contentsRect: presentation.isCropPreviewActive
            ? CanvasImageCropRect.fullImage.cgRect
            : presentation.effectiveCropRectNormalized.cgRect,
        cgImage: presentation.cgImage
    )
)
```

### 修改后

- `CanvasRenderer` 仍沿用当前 render payload 结构，但像素来源切为 `presentation.posterCGImage`。
- 这样阶段 1 不引入播放逻辑，也先把“渲染看到的是 poster，而不是裸 `CanvasImageItem.cgImage`”固化下来。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 renderer 先桥接到 presentation.posterCGImage，保留现有渲染结构，同时解除对 CanvasImageItem.cgImage 字段的直接依赖。
payload: .image(
    CanvasImageRenderPayload(
        contentsRect: presentation.isCropPreviewActive
            ? CanvasImageCropRect.fullImage.cgRect
            : presentation.effectiveCropRectNormalized.cgRect,
        cgImage: presentation.posterCGImage
    )
)
```

## 修改六：存储与缩略图路径改为从 asset 的 poster 取像素

### 修改前

- `BoardDocumentMapper.makeRuntimeState(...)` 读取文档后，直接构造 `CanvasImageItem(cgImage: ...)`。
- `BoardStore.saveBoard(...)` 保存时直接对 `item.cgImage` 编码 PNG。
- `BoardThumbnailRenderer.renderPersistedThumbnail(...)` 直接返回 `runtimeItem.cgImage`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:)
// 功能说明: 修改前文档恢复后直接构造 CanvasImageItem(cgImage:...)，运行时仍是单帧图片模型。
case let .image(imageRecord):
    return CanvasBoardItem.image(
        CanvasImageItem(
            id: imageRecord.id,
            cgImage: try imageLoader(imageRecord),
            center: imageRecord.center.cgPoint,
            size: imageRecord.size.cgSize,
            zIndex: CGFloat(imageRecord.zIndex),
            cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
            rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
        )
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改前保存时直接把 item.cgImage 编码成 PNG，存储路径仍直接依赖单帧字段。
for item in persistedState.imageItems {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        \"\\(item.id.uuidString).png\"
    )
    let pngData = try makePNGData(for: item.cgImage, itemID: item.id)
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改前运行时缩略图生成直接从 runtimeItem.cgImage 取像素。
guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
    throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
        itemID: itemRecord.id
    )
}

return runtimeItem.cgImage
```

### 修改后

- `BoardDocumentMapper` 读取文档后先构造 `CanvasImageAsset.persistedStaticImage(...)`，再生成 `CanvasImageItem(asset: ...)`。
- `BoardStore.saveBoard(...)` 保存时改为取 `item.posterCGImage`。
- `BoardThumbnailRenderer` 生成运行时缩略图时改为取 `runtimeItem.posterCGImage`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:)
// 功能说明: 修改后文档恢复会先构造 persisted static asset，再让运行时图片项持有 asset，而不是裸 cgImage。
case let .image(imageRecord):
    return CanvasBoardItem.image(
        CanvasImageItem(
            id: imageRecord.id,
            asset: CanvasImageAsset.persistedStaticImage(
                filename: imageRecord.assetFilename,
                cgImage: try imageLoader(imageRecord)
            ),
            center: imageRecord.center.cgPoint,
            size: imageRecord.size.cgSize,
            zIndex: CGFloat(imageRecord.zIndex),
            cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
            rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
        )
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: saveBoard(_:)
// 功能说明: 修改后保存时改为从图片资产的 poster 取像素，先让存储层适配新模型。
for item in persistedState.imageItems {
    let assetURL = assetsDirectoryURL.appendingPathComponent(
        \"\\(item.id.uuidString).png\"
    )
    let pngData = try makePNGData(
        for: item.posterCGImage,
        itemID: item.id
    )
    try CoordinatedFileIO.writeData(pngData, to: assetURL)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改后运行时缩略图生成统一从 poster 图取像素，缩略图链路不再直接依赖 CanvasImageItem.cgImage。
guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
    throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
        itemID: itemRecord.id
    )
}

return runtimeItem.posterCGImage
```

## 阶段 1 完成状态

- 已完成：
  - 新增图片资产模型 `CanvasImageAsset`
  - `CanvasImageItem` 切换为持有 `asset`
  - `CanvasImagePresentation` / `Resolver` 开始携带 asset 引用与 poster 图
  - 导入链路桥接为 transient asset
  - 存储与运行时缩略图桥接为 poster 图
  - `CanvasRenderer` 改为使用 `presentation.posterCGImage`
- 未完成：
  - GIF 原始资源保留
  - GIF 资源类型元数据透传到导入层
  - 主画布动画播放接入
  - 文档格式升级到 `v4`
  - 资源去重与共享文件名策略
