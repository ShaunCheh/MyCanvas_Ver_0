# 20260324_111254_gif_phase4_render_contract_record

## 记录范围

- 记录内容：
  1. 将图片 render payload 从“直接携带当前 `CGImage`”改为“携带稳定展示契约”。
  2. 调整 `CanvasRenderer`，让 render snapshot 只表达几何、裁切与 poster 展示，不承担 GIF 时间推进。
  3. 重构 `CanvasImageLayer`，拆分静态 poster 路径与动画资源预备路径，并为后续播放器接管帧更新预留接口。
  4. 调整 iOS / macOS viewport，在 `refreshItemLayers()` 中建立静态图片路径与动画图片路径的分支结构。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - 阶段 0 语义契约
  - 阶段 1 资产模型拆分
  - 阶段 2 导入原始资源保留
  - 阶段 3 文档格式与存储迁移
  - 阶段 5 GIF 自动播放实现
  - git commit / push

## 修改一：`CanvasImageRenderPayload` 从“当前像素帧”改为“稳定展示契约”

### 修改前

- `CanvasImageRenderPayload` 直接保存 `cgImage`。
- 这意味着 render snapshot 语义上仍然在表达“当前显示的像素帧”，不利于后续把 GIF 播放交给 layer 生命周期。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: 无（CanvasImageRenderPayload 结构定义）
// 功能说明: 修改前图片 render payload 直接携带当前 CGImage，snapshot 仍与具体像素帧绑定。
struct CanvasImageRenderPayload {
    let contentsRect: CGRect
    let cgImage: CGImage
}
```

### 修改后

- 新增 `CanvasImageDisplayContract`，明确 snapshot 携带的是：
  - `assetReference`
  - `posterCGImage`
- `CanvasImageRenderPayload` 改为保存：
  - `displayContract`
  - `contentsRect`
- `isAnimatedAsset` 通过 `assetReference.kind` 判断，为 viewport 分流提供稳定入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: isAnimatedAsset
// 功能说明: 修改后图片 payload 不再直接表达“当前帧像素”，而是表达“资源引用 + poster 展示契约”，为后续 GIF 播放从 snapshot 解耦做准备。
struct CanvasImageDisplayContract {
    let assetReference: CanvasImageAssetReference
    let posterCGImage: CGImage

    var isAnimatedAsset: Bool {
        assetReference.kind.isAnimated
    }
}

struct CanvasImageRenderPayload {
    let displayContract: CanvasImageDisplayContract
    let contentsRect: CGRect
}
```

## 修改二：`CanvasRenderer` 只输出图片展示契约，不再直传 `cgImage`

### 修改前

- `makeImageRenderItem(...)` 直接把 `presentation.posterCGImage` 塞进 `CanvasImageRenderPayload.cgImage`。
- 这样 renderer 产出的 snapshot 依旧停留在“这次要画哪张像素图”的层级。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 直接把 posterCGImage 作为 render payload 的 cgImage 输出，snapshot 仍承担像素帧分发职责。
private func makeImageRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    // ...
    return CanvasRenderItem(
        id: presentation.itemID,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        rotationRadians: presentation.effectiveRotationRadians,
        zIndex: presentation.zIndex,
        payload: .image(
            CanvasImageRenderPayload(
                contentsRect: presentation.isCropPreviewActive
                    ? CanvasImageCropRect.fullImage.cgRect
                    : presentation.effectiveCropRectNormalized.cgRect,
                cgImage: presentation.posterCGImage
            )
        )
    )
}
```

### 修改后

- `CanvasRenderer` 现在只输出 `CanvasImageDisplayContract`。
- snapshot 层明确只承担：
  - 几何
  - 裁切 rect
  - zIndex
  - poster 展示契约
- GIF 的逐帧推进不再需要挤进 renderer 的数据结构。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeImageRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 renderer 只把 assetReference + posterCGImage 封装成展示契约输出，snapshot 不再承担 GIF 当前帧分发。
private func makeImageRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    // ...
    return CanvasRenderItem(
        id: presentation.itemID,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        rotationRadians: presentation.effectiveRotationRadians,
        zIndex: presentation.zIndex,
        payload: .image(
            CanvasImageRenderPayload(
                displayContract: CanvasImageDisplayContract(
                    assetReference: presentation.assetReference,
                    posterCGImage: presentation.posterCGImage
                ),
                contentsRect: presentation.isCropPreviewActive
                    ? CanvasImageCropRect.fullImage.cgRect
                    : presentation.effectiveCropRectNormalized.cgRect
            )
        )
    )
}
```

## 修改三：`CanvasImageLayer` 从“单一路径更新图片”改为“静态 poster / 动画预备 / 播放接管”三层职责

### 修改前

- `CanvasImageLayer` 只有一个 `update(...)` 入口。
- 它直接把 `imagePayload.cgImage` 赋给 `contents`，同时缓存 `lastAppliedImage`。
- 这会让几何刷新和未来 GIF 帧更新耦合在同一个调用面里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:imagePayload:contentsScale:) / isDisplayingImage(_:)
// 功能说明: 修改前图片 layer 只能接收一个静态 cgImage 更新入口，几何刷新和未来 GIF 播放没有结构性分界。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedContentsRect: CGRect
    private var lastAppliedRotationRadians: CGFloat

    func update(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if !isDisplayingImage(imagePayload.cgImage) {
            contents = imagePayload.cgImage
            lastAppliedImage = imagePayload.cgImage
        }

        if lastAppliedContentsRect != imagePayload.contentsRect {
            contentsRect = imagePayload.contentsRect
            lastAppliedContentsRect = imagePayload.contentsRect
        }

        // ... position / bounds / rotation / zIndex / scale 更新 ...

        CATransaction.commit()
    }

    private func isDisplayingImage(_ cgImage: CGImage) -> Bool {
        guard let lastAppliedImage else {
            return false
        }

        return lastAppliedImage === cgImage
    }
}
```

### 修改后

- 新增内部状态：
  - `CanvasImageLayerDisplayMode`
  - `CanvasImageLayerFrameSource`
  - `lastAppliedPosterImage`
  - `lastAppliedAssetReference`
  - `lastDisplayedImage`
- 新增外部接口：
  - `updateStaticPresentation(...)`
  - `updateAnimatedPresentation(...)`
  - `displayPlaybackFrame(...)`
  - `restorePosterFrameIfNeeded(...)`
- 新增内部职责拆分：
  - `applyGeometry(...)`
  - `applyDisplayContract(...)`
  - `applyDisplayedImageIfNeeded(...)`
  - `restorePosterFrameWithoutActionsIfNeeded(...)`
- 结果是：
  - 静态图仍然稳定显示 poster
  - 动画图当前阶段仍可先显示 poster
  - 后续阶段 5 的播放器可以直接接管 `displayPlaybackFrame(...)`，而不会影响几何刷新逻辑

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: updateStaticPresentation(...) / updateAnimatedPresentation(...) / displayPlaybackFrame(_:for:) / restorePosterFrameIfNeeded(for:)
// 功能说明: 修改后图片 layer 明确区分静态 poster 显示、动画资源预备状态和未来播放帧接管入口，几何刷新不再等价于当前帧刷新。
private enum CanvasImageLayerDisplayMode: Equatable {
    case staticPoster
    case animatedPlaybackReady
}

private enum CanvasImageLayerFrameSource: Equatable {
    case poster
    case playback
}

final class CanvasImageLayer: CALayer {
    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastDisplayedImage: CGImage?
    private var lastAppliedPosterImage: CGImage?
    private var lastAppliedAssetReference: CanvasImageAssetReference?
    private var lastAppliedDisplayMode: CanvasImageLayerDisplayMode?
    private var currentFrameSource: CanvasImageLayerFrameSource
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedContentsRect: CGRect
    private var lastAppliedRotationRadians: CGFloat

    func updateStaticPresentation(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        performWithoutActions {
            applyGeometry(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            applyDisplayContract(
                imagePayload.displayContract,
                displayMode: .staticPoster
            )
        }
    }

    func updateAnimatedPresentation(
        with item: CanvasRenderItem,
        imagePayload: CanvasImageRenderPayload,
        contentsScale: CGFloat
    ) {
        performWithoutActions {
            applyGeometry(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            applyDisplayContract(
                imagePayload.displayContract,
                displayMode: .animatedPlaybackReady
            )
        }
    }

    func displayPlaybackFrame(
        _ cgImage: CGImage,
        for assetReference: CanvasImageAssetReference
    ) {
        guard
            lastAppliedAssetReference == assetReference,
            lastAppliedDisplayMode == .animatedPlaybackReady
        else {
            return
        }

        performWithoutActions {
            applyDisplayedImageIfNeeded(cgImage)
            currentFrameSource = .playback
        }
    }

    func restorePosterFrameIfNeeded(
        for assetReference: CanvasImageAssetReference? = nil
    ) {
        performWithoutActions {
            restorePosterFrameWithoutActionsIfNeeded(
                for: assetReference
            )
        }
    }
}
```

## 修改四：iOS viewport 建立“静态图路径 / 动画图路径”分流

### 修改前

- `iOSCanvasViewportView.refreshItemLayers()` 在图片分支里统一调用 `imageLayer.update(...)`。
- 不区分静态图还是 GIF 资源，后续要接播放器时只能再拆一次刷新循环。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers()
// 功能说明: 修改前 iOS viewport 对所有图片 item 统一走 imageLayer.update(...)，没有静态图和动画图的渲染分支。
private func refreshItemLayers() {
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

### 修改后

- `refreshItemLayers()` 里图片分支改为调用 `refreshImageLayer(...)`。
- 新增三层分发：
  - `refreshImageLayer(...)`
  - `refreshStaticImageLayer(...)`
  - `refreshAnimatedImageLayer(...)`
- 当前阶段 4 中，动画资源仍然先走 `updateAnimatedPresentation(...)` 显示 poster，但分支结构已经就位。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / refreshImageLayer(_:with:imagePayload:contentsScale:) / refreshStaticImageLayer(_:with:imagePayload:contentsScale:) / refreshAnimatedImageLayer(_:with:imagePayload:contentsScale:)
// 功能说明: 修改后 iOS viewport 在图片刷新时明确区分静态图与动画图路径，为后续 GIF 播放器接管保留稳定入口。
private func refreshItemLayers() {
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}

private func refreshImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    if imagePayload.displayContract.isAnimatedAsset {
        refreshAnimatedImageLayer(
            imageLayer,
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    } else {
        refreshStaticImageLayer(
            imageLayer,
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    }
}

private func refreshStaticImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    imageLayer.updateStaticPresentation(
        with: item,
        imagePayload: imagePayload,
        contentsScale: contentsScale
    )
}

private func refreshAnimatedImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    imageLayer.updateAnimatedPresentation(
        with: item,
        imagePayload: imagePayload,
        contentsScale: contentsScale
    )
}
```

## 修改五：macOS viewport 同步建立“静态图路径 / 动画图路径”分流

### 修改前

- `macOSCanvasViewportView.refreshItemLayers()` 与 iOS 一样，对所有图片 item 统一调用 `imageLayer.update(...)`。
- 平台层没有专门的动画图片刷新入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshItemLayers()
// 功能说明: 修改前 macOS viewport 对所有图片 item 统一走 imageLayer.update(...)，还没有为动画资源预留单独刷新路径。
private func refreshItemLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

### 修改后

- macOS 端和 iOS 端保持同构：
  - `refreshImageLayer(...)`
  - `refreshStaticImageLayer(...)`
  - `refreshAnimatedImageLayer(...)`
- 阶段 4 到这里为止，平台两侧都已经具备“poster 静态显示”和“后续动画接管”的结构边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / refreshImageLayer(_:with:imagePayload:contentsScale:) / refreshStaticImageLayer(_:with:imagePayload:contentsScale:) / refreshAnimatedImageLayer(_:with:imagePayload:contentsScale:)
// 功能说明: 修改后 macOS viewport 也建立了静态图与动画图的分流入口，保证两端后续 GIF 播放接入方式一致。
private func refreshItemLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}

private func refreshImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    if imagePayload.displayContract.isAnimatedAsset {
        refreshAnimatedImageLayer(
            imageLayer,
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    } else {
        refreshStaticImageLayer(
            imageLayer,
            with: item,
            imagePayload: imagePayload,
            contentsScale: contentsScale
        )
    }
}

private func refreshStaticImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    imageLayer.updateStaticPresentation(
        with: item,
        imagePayload: imagePayload,
        contentsScale: contentsScale
    )
}

private func refreshAnimatedImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    imageLayer.updateAnimatedPresentation(
        with: item,
        imagePayload: imagePayload,
        contentsScale: contentsScale
    )
}
```

## 阶段 4 完成状态

- 已完成：
  - render snapshot 中的图片 payload 改为表达稳定展示契约
  - `CanvasRenderer` 不再把图片“当前像素帧”作为 snapshot 语义输出
  - `CanvasImageLayer` 具备静态 poster、动画预备和未来播放帧接管的结构边界
  - iOS / macOS viewport 都建立了静态图路径和动画图路径的分流
  - 当前即使还没接 GIF 播放器，动画资源也能稳定走 poster 路径显示
- 未完成：
  - GIF 本地播放注册表
  - 基于时间推进的帧切换
  - viewport 可见性驱动的播放生命周期管理
  - 离屏 / 移除 / 切后台时的暂停与释放
