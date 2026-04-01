# 20260401_142420_video_runtime_poster_phase3_record

## 记录范围

- 记录内容：
  1. 将视频 item 的 `posterTimeSeconds` 从共享 `CanvasVideoSource` 拆回 `CanvasImageItem` 自身，避免 poster 状态挂在共享 source 上。
  2. 调整导入与文档映射链路，让导入视频时产生的 poster 时间直接落到运行时 item / 文档记录，而不是写进 `CanvasVideoSource`。
  3. 改造 render contract，显式区分“资源本身是否可动画播放”和“当前 item 是否允许在画板上播放”，确保视频 item 在画板上始终只显示静态 poster。
  4. 在 `CanvasScene` 与 `CanvasEditorSession` 增加视频 poster 更新入口，统一串起 scene 更新、history 记录与 autosave。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasVideoSource.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
  - `MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
- 本记录不包含：
  - 阶段 1 的双资产存储落盘
  - 阶段 2 的跨平台视频导入入口
  - 阶段 4 的 BoardList / thumbnail / persisted thumbnail
  - 阶段 5 的右键菜单“设置展示画面”
  - 阶段 7 / 8 的视频展示画面编辑页
  - git commit / push

## 修改一：把 `posterTimeSeconds` 从共享视频源拆回到 item 自身

### 修改前

- `CanvasVideoSource` 既表示“源视频文件引用”，又携带 `posterTimeSeconds`。
- `CanvasImageItem` 本身没有独立的 poster 时间状态。
- 这意味着 poster 选择状态仍然依附在共享 source 上，不符合阶段 3 “不要把 `posterTimeSeconds` 放在共享 source 引用上”的要求。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasVideoSource.swift
// 类型/函数: CanvasVideoSource.init(assetReference:posterTimeSeconds:)
// 功能说明: 修改前 source 同时承载“源视频文件身份”和“当前 poster 时间”，poster 状态仍然挂在共享 source 上。
struct CanvasVideoSource: Equatable, Hashable {
    let assetReference: CanvasVideoAssetReference
    var posterTimeSeconds: Double

    init(
        assetReference: CanvasVideoAssetReference,
        posterTimeSeconds: Double = 0
    ) {
        self.assetReference = assetReference
        self.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds
        )
    }

    var sourceVideoFilename: String {
        assetReference.stableAssetFilename
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.init(...) / CanvasImageItem.matchesDocumentState(_:)
// 功能说明: 修改前运行时 item 只有 asset 和 videoSource，没有独立的 poster 时间字段，历史比较也只能比 source 本身。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let asset: CanvasImageAsset
    var videoSource: CanvasVideoSource?
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        asset: CanvasImageAsset,
        videoSource: CanvasVideoSource? = nil,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.asset = asset
        self.videoSource = videoSource
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    func matchesDocumentState(_ other: CanvasImageItem) -> Bool {
        id == other.id &&
            assetReference == other.assetReference &&
            videoSource == other.videoSource &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            cropRectNormalized == other.cropRectNormalized &&
            rotationRadians == other.rotationRadians
    }
}
```

### 修改后

- `CanvasVideoSource` 只保留“源视频文件引用”的职责。
- `CanvasImageItem` 新增 `posterTimeSeconds`，并在 init 时统一做 sanitize。
- `matchesDocumentState(_:)` 把 `posterTimeSeconds` 纳入文档态比较。
- 视频 item 的 duplicated poster 资产明确改成新的静态图片资产，后续不同副本改封面不会互相串联。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasVideoSource.swift
// 类型/函数: CanvasVideoSource.init(assetReference:)
// 功能说明: 修改后 source 只表示源视频文件，不再承载 poster 时间，职责边界回到“共享视频资源引用”。
struct CanvasVideoSource: Equatable, Hashable {
    let assetReference: CanvasVideoAssetReference

    init(
        assetReference: CanvasVideoAssetReference
    ) {
        self.assetReference = assetReference
    }

    var sourceVideoFilename: String {
        assetReference.stableAssetFilename
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.init(...) / CanvasImageItem.duplicated(offsetInWorld:) / CanvasImageItem.matchesDocumentState(_:)
// 功能说明: 修改后视频 item 自身持有 poster 时间，并在复制与历史比较时把 poster 状态作为 item 级文档状态处理。
struct CanvasImageItem {
    let id: CanvasImageItemID
    var asset: CanvasImageAsset
    var videoSource: CanvasVideoSource?
    var posterTimeSeconds: Double?
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        asset: CanvasImageAsset,
        videoSource: CanvasVideoSource? = nil,
        posterTimeSeconds: Double? = nil,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationRadians: CGFloat = 0
    ) {
        self.id = id
        self.asset = asset
        self.videoSource = videoSource
        self.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
            posterTimeSeconds,
            isVideo: videoSource != nil
        )
        self.center = center
        self.size = size
        self.zIndex = zIndex
        self.cropRectNormalized = cropRectNormalized
        self.rotationRadians = rotationRadians
    }

    func duplicated(offsetInWorld: CGPoint) -> CanvasImageItem {
        let duplicatedAsset: CanvasImageAsset
        if isVideo {
            duplicatedAsset = CanvasImageAsset.transientStaticImage(
                cgImage: asset.posterCGImage,
                logicalPixelSize: asset.logicalPixelSize
            )
        } else {
            duplicatedAsset = asset
        }

        return CanvasImageItem(
            asset: duplicatedAsset,
            videoSource: videoSource,
            posterTimeSeconds: posterTimeSeconds,
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
            videoSource == other.videoSource &&
            posterTimeSeconds == other.posterTimeSeconds &&
            center == other.center &&
            size == other.size &&
            zIndex == other.zIndex &&
            cropRectNormalized == other.cropRectNormalized &&
            rotationRadians == other.rotationRadians
    }
}
```

## 修改二：导入与文档映射改为把 poster 时间直接落在 item 上

### 修改前

- `CanvasImportedVideoAsset` 只返回 `asset + videoSource`。
- `CanvasMediaImportService.importVideo(...)` 在构造 `CanvasVideoSource` 时直接塞入 `posterTimeSeconds`。
- `BoardDocumentMapper` 读写时通过 `item.videoSource?.posterTimeSeconds` 取回 poster 时间。
- `BoardDocument.videoSource` 也继续把文档里的 `posterTimeSeconds` 还原进 `CanvasVideoSource`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasImportedVideoAsset
// 功能说明: 修改前导入视频结果没有单独暴露 poster 时间，poster 时间只能继续依赖 videoSource 传递。
struct CanvasImportedVideoAsset {
    let asset: CanvasImageAsset
    let videoSource: CanvasVideoSource
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 函数名: importVideo(_:into:)
// 功能说明: 修改前导入阶段把 poster 时间写进 CanvasVideoSource，source 同时带了资源身份和 item poster 状态。
let videoSource = CanvasVideoSource(
    assetReference: .persisted(filename: sourceVideoFilename),
    posterTimeSeconds: video.posterTimeSeconds
)
return ImportedVideoResult(
    item: CanvasImportedVideoAsset(
        asset: posterAsset,
        videoSource: videoSource
    ),
    createdAssetURLs: [
        sourceVideoAssetURL,
        posterImageAssetURL
    ]
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 类型/函数: BoardImageItemRecord.videoSource
// 功能说明: 修改前文档记录恢复运行时 source 时，也会把 poster 时间重新塞回 source。
var videoSource: CanvasVideoSource? {
    guard let sourceVideoFilename else {
        return nil
    }

    return CanvasVideoSource(
        assetReference: .persisted(filename: sourceVideoFilename),
        posterTimeSeconds: posterTimeSeconds ?? 0
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改前 mapper 读取与写回 poster 时间时，仍然从 videoSource 上取值。
CanvasImageItem(
    id: imageRecord.id,
    asset: CanvasImageAsset.persistedImage(
        kind: imageRecord.assetReference.kind,
        filename: imageRecord.assetReference.stableAssetFilename,
        cgImage: try imageLoader(imageRecord)
    ),
    videoSource: imageRecord.videoSource,
    center: imageRecord.center.cgPoint,
    size: imageRecord.size.cgSize,
    zIndex: CGFloat(imageRecord.zIndex),
    cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
    rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
)

BoardImageItemRecord(
    id: item.id,
    center: BoardPointRecord(item.center),
    size: BoardSizeRecord(item.size),
    zIndex: Double(item.zIndex),
    assetFilename: item.assetReference.stableAssetFilename,
    assetKind: item.assetKind,
    posterImageFilename: item.assetReference.stableAssetFilename,
    sourceVideoFilename: item.videoSource?.sourceVideoFilename,
    posterTimeSeconds: item.videoSource?.posterTimeSeconds,
    cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
    rotationRadians: Double(item.rotationRadians)
)
```

### 修改后

- `CanvasImportedVideoAsset` 显式带出 `posterTimeSeconds`。
- `CanvasMediaImportService.importVideo(...)` 只把源视频身份写进 `CanvasVideoSource`，同时把 `posterTimeSeconds` 单独挂在导入结果上。
- `BoardDocumentMapper` 在 runtime <-> document 之间，直接通过 `item.posterTimeSeconds` 读写 poster 时间。
- `BoardDocument.videoSource` 只恢复源视频引用，不再恢复 poster 时间。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasImportedVideoAsset
// 功能说明: 修改后导入结果会单独携带 poster 时间，后续运行时 item 初始化不再依赖 videoSource 承载这部分状态。
struct CanvasImportedVideoAsset {
    let asset: CanvasImageAsset
    let videoSource: CanvasVideoSource
    let posterTimeSeconds: Double
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 函数名: importVideo(_:into:)
// 功能说明: 修改后导入阶段只保留 source 视频身份，poster 时间改为显式写入导入结果，避免继续污染共享 source 语义。
let videoSource = CanvasVideoSource(
    assetReference: .persisted(filename: sourceVideoFilename)
)
return ImportedVideoResult(
    item: CanvasImportedVideoAsset(
        asset: posterAsset,
        videoSource: videoSource,
        posterTimeSeconds: video.posterTimeSeconds
    ),
    createdAssetURLs: [
        sourceVideoAssetURL,
        posterImageAssetURL
    ]
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 类型/函数: BoardImageItemRecord.videoSource
// 功能说明: 修改后文档恢复 source 时只恢复“源视频文件引用”，poster 时间继续留在 record / item 自身。
var videoSource: CanvasVideoSource? {
    guard let sourceVideoFilename else {
        return nil
    }

    return CanvasVideoSource(
        assetReference: .persisted(filename: sourceVideoFilename)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeRuntimeState(from:imageLoader:) / makeImageRecord(from:)
// 功能说明: 修改后 mapper 在 runtime 和 document 之间直接读写 item.posterTimeSeconds，使 poster 状态真正属于 item。
CanvasImageItem(
    id: imageRecord.id,
    asset: CanvasImageAsset.persistedImage(
        kind: imageRecord.assetReference.kind,
        filename: imageRecord.assetReference.stableAssetFilename,
        cgImage: try imageLoader(imageRecord)
    ),
    videoSource: imageRecord.videoSource,
    posterTimeSeconds: imageRecord.posterTimeSeconds,
    center: imageRecord.center.cgPoint,
    size: imageRecord.size.cgSize,
    zIndex: CGFloat(imageRecord.zIndex),
    cropRectNormalized: imageRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage,
    rotationRadians: CGFloat(imageRecord.rotationRadians ?? 0)
)

BoardImageItemRecord(
    id: item.id,
    center: BoardPointRecord(item.center),
    size: BoardSizeRecord(item.size),
    zIndex: Double(item.zIndex),
    assetFilename: item.assetReference.stableAssetFilename,
    assetKind: item.assetKind,
    posterImageFilename: item.assetReference.stableAssetFilename,
    sourceVideoFilename: item.videoSource?.sourceVideoFilename,
    posterTimeSeconds: item.posterTimeSeconds,
    cropRectNormalized: BoardImageCropRecord(item.cropRectNormalized),
    rotationRadians: Double(item.rotationRadians)
)
```

## 修改三：render contract 显式禁止视频 item 进入动画播放链

### 修改前

- `CanvasImageDisplayContract.isAnimatedAsset` 只看 `assetReference.kind.isAnimated`。
- 渲染链没有“这个 item 是否允许在画板上播放动画”的开关。
- 阶段 3 要求视频 item 在画板上始终是 poster-only，因此这里需要补一层 item 级别的播放许可。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 类型/函数: CanvasImageDisplayContract.isAnimatedAsset
// 功能说明: 修改前渲染合同只看资源类型本身是否可动画播放，缺少 item 级别的播放开关。
struct CanvasImageDisplayContract {
    let assetReference: CanvasImageAssetReference
    let posterCGImage: CGImage

    var isAnimatedAsset: Bool {
        assetReference.kind.isAnimated
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 只把 assetReference 和 posterCGImage 传给 display contract，后续 viewport 无法区分“GIF 可以播”和“视频只能静态展示”。
CanvasImageRenderPayload(
    displayContract: CanvasImageDisplayContract(
        assetReference: presentation.assetReference,
        posterCGImage: presentation.posterCGImage
    ),
    contentsRect: presentation.isCropPreviewActive
        ? CanvasImageCropRect.fullImage.cgRect
        : presentation.effectiveCropRectNormalized.cgRect
)
```

### 修改后

- `CanvasImageItem` 增加 `allowsAnimatedPlayback`，视频 item 固定返回 `false`。
- `CanvasImagePresentation` / `CanvasImagePresentationResolver` 把这个状态透传到 render 层。
- `CanvasImageDisplayContract.isAnimatedAsset` 改为 `allowsAnimatedPlayback && assetReference.kind.isAnimated`。
- 这样 viewport 仍然可以给 GIF 开启动画播放，但视频 item 永远只走静态 poster 渲染链。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 类型/函数: CanvasImageItem.allowsAnimatedPlayback
// 功能说明: 修改后 item 级别可以决定自己是否允许进入动画播放链；视频 item 固定返回 false。
var allowsAnimatedPlayback: Bool {
    isVideo == false
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 类型/函数: CanvasImageDisplayContract.isAnimatedAsset
// 功能说明: 修改后 render contract 显式携带 item 级播放许可，只有“资源可动画 + item 允许播放”时才走动画链路。
struct CanvasImageDisplayContract {
    let assetReference: CanvasImageAssetReference
    let posterCGImage: CGImage
    let allowsAnimatedPlayback: Bool

    var isAnimatedAsset: Bool {
        allowsAnimatedPlayback && assetReference.kind.isAnimated
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 renderer 把 item 的 poster-only / animation-allowed 语义一起塞进 display contract，保持几何层不变，仅调整素材展示来源。
CanvasImageRenderPayload(
    displayContract: CanvasImageDisplayContract(
        assetReference: presentation.assetReference,
        posterCGImage: presentation.posterCGImage,
        allowsAnimatedPlayback: presentation.allowsAnimatedPlayback
    ),
    contentsRect: presentation.isCropPreviewActive
        ? CanvasImageCropRect.fullImage.cgRect
        : presentation.effectiveCropRectNormalized.cgRect
)
```

## 修改四：补齐 `Scene` / `EditorSession` 的视频 poster 更新入口

### 修改前

- `CanvasScene` 只有 `cropItem(...)`、`rotateItem(...)`、`resizeItem(...)` 这类几何更新入口，没有“替换某个视频 item poster”的共享 mutation API。
- `CanvasEditorSession` 也没有统一的 `updateVideoPoster(...)` 入口，因此后续视频编辑页即使拿到了新 poster，也没有统一地方去触发 history / autosave / refresh。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: cropItem(withID:toNormalizedCropRect:)
// 功能说明: 修改前 Scene 只有几何相关的共享 mutation 入口，没有视频 poster 回写入口。
@discardableResult
func cropItem(
    withID id: CanvasImageItemID,
    toNormalizedCropRect normalizedCropRect: CanvasImageCropRect
) -> CanvasImageItem? {
    updateImageItem(withID: id) { item in
        let updatedLocalFrame = item.localFrame(forNormalizedCropRect: normalizedCropRect).standardized
        guard
            updatedLocalFrame.width > 0,
            updatedLocalFrame.height > 0
        else {
            return item
        }

        let updatedCenter = item.worldPoint(
            fromLocal: CGPoint(
                x: updatedLocalFrame.midX,
                y: updatedLocalFrame.midY
            )
        )
        item.cropRectNormalized = normalizedCropRect
        item.center = updatedCenter
        item.size = updatedLocalFrame.size
        return item
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: commitTextEdit()
// 功能说明: 修改前 EditorSession 只有文本编辑等现有入口，没有可供视频编辑页复用的 poster 更新入口。
@discardableResult
func commitTextEdit() -> CanvasTextEditCommitResult? {
    guard
        let inlineEditState,
        inlineEditState.mode == .text
    else {
        return nil
    }

    // ... 省略其他逻辑 ...
}
```

### 修改后

- `CanvasScene.updateVideoPoster(...)` 负责把新的 poster 图和 poster 时间写回对应的视频 item。
- `CanvasImageItem.updatingVideoPoster(...)` 会生成新的静态 poster 资产，并保留原 `logicalPixelSize` / 运行时几何状态。
- `CanvasEditorSession.updateVideoPoster(...)` 统一触发：
  - scene 更新
  - inline selection 同步
  - history 记录
  - autosave 调度
  - 向上返回 `refreshReason`
- 同时，导入视频生成的 `posterTimeSeconds` 也在 `appendImportedMedia(...)` 阶段直接写入新建的 video item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: updatingVideoPoster(posterCGImage:logicalPixelSize:posterTimeSeconds:assetID:)
// 功能说明: 修改后 item 可以在不触碰几何状态的前提下替换 poster 资产，并把新的 poster 时间写回 item 自身。
func updatingVideoPoster(
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double,
    assetID: UUID = UUID()
) -> CanvasImageItem? {
    guard isVideo else {
        return nil
    }

    var updatedItem = self
    updatedItem.asset = CanvasImageAsset.transientStaticImage(
        cgImage: posterCGImage,
        logicalPixelSize: logicalPixelSize ?? asset.logicalPixelSize,
        assetID: assetID
    )
    updatedItem.posterTimeSeconds = Self.sanitizedPosterTimeSeconds(
        posterTimeSeconds,
        isVideo: true
    )
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: updateVideoPoster(withID:posterCGImage:logicalPixelSize:posterTimeSeconds:)
// 功能说明: 修改后 Scene 提供共享 poster 回写入口，控制器层后续只需提交新 poster，不必自己碰运行时 item 细节。
@discardableResult
func updateVideoPoster(
    withID id: CanvasImageItemID,
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double
) -> CanvasImageItem? {
    var updatedItem: CanvasImageItem?
    updateImageItem(withID: id) { item in
        guard let nextItem = item.updatingVideoPoster(
            posterCGImage: posterCGImage,
            logicalPixelSize: logicalPixelSize,
            posterTimeSeconds: posterTimeSeconds
        ) else {
            return
        }

        item = nextItem
        updatedItem = nextItem
    }
    return updatedItem
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canUpdateVideoPoster(withID:) / updateVideoPoster(withID:posterCGImage:logicalPixelSize:posterTimeSeconds:)
// 功能说明: 修改后 EditorSession 统一接住视频 poster 更新，顺手完成 history、autosave 与 refreshReason 产出，供后续视频编辑页直接复用。
func canUpdateVideoPoster(withID itemID: CanvasItemID) -> Bool {
    scene.item(withID: itemID)?.isVideo == true
}

@discardableResult
func updateVideoPoster(
    withID itemID: CanvasItemID,
    posterCGImage: CGImage,
    logicalPixelSize: CGSize? = nil,
    posterTimeSeconds: Double
) -> CanvasVideoPosterUpdateResult? {
    guard canUpdateVideoPoster(withID: itemID) else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard let updatedItem = scene.updateVideoPoster(
        withID: itemID,
        posterCGImage: posterCGImage,
        logicalPixelSize: logicalPixelSize,
        posterTimeSeconds: posterTimeSeconds
    ) else {
        return nil
    }

    syncInlineEditStateWithSelection()
    let changeReason = "update video poster"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return CanvasVideoPosterUpdateResult(
        item: updatedItem,
        refreshReason: changeReason
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: appendImportedMedia(_:placement:layout:)
// 功能说明: 修改后导入阶段生成的视频 item 会把初始 poster 时间直接写进运行时 item，后续保存与更新都不再依赖 source 承载这部分状态。
case let .video(video):
    importedItem = CanvasImageItem(
        asset: video.asset,
        videoSource: video.videoSource,
        posterTimeSeconds: video.posterTimeSeconds,
        center: CGPoint(
            x: importCenter.x + offset.x,
            y: importCenter.y + offset.y
        ),
        size: normalizedDisplaySize(
            for: video.asset.logicalPixelSize
        ),
        zIndex: startingZIndex + CGFloat(index)
    )
```

## 结果说明

- 视频 item 的 poster 时间现在真正属于 item，而不是共享 source。
- 画板渲染链继续复用现有 `posterCGImage + contentsRect + rotation` 数学，视频 item 与图片在缩放、旋转、裁切上的表现保持一致。
- 视频 item 在画板上不会误走动画播放链，始终显示静态 poster。
- 后续阶段 5 / 7 / 8 只需要调用 `CanvasEditorSession.updateVideoPoster(...)`，即可把视频编辑页选中的展示帧回写到现有运行时与保存链路中。
