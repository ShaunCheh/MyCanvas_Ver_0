# 20260324_100845_gif_phase0_contract_record

## 记录范围

- 记录内容：
  1. 为 GIF 方案 B 的阶段 0 增加统一契约类型，冻结播放、预览、复制、历史、目标文档版本语义。
  2. 将图片复制与图片历史比较逻辑从调用点收口到 `CanvasImageItem`。
  3. 将 `Scene`、`HistorySnapshot`、`EditorSession`、`BoardDocument`、`BoardPreviewContent` 接到阶段 0 契约入口。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift`
- 本记录不包含：
  - GIF 资源引用模型替换
  - GIF 导入链路改造
  - GIF 自动播放实现
  - `board.json` v4 存储迁移
  - git commit / push

## 修改一：新增阶段 0 统一契约文件

### 修改前

- 项目里还没有一个统一类型来固化 GIF 方案 B 的阶段 0 语义。
- “主画布可见自动播放 / 非画布预览只看首帧 / 复制共享底层资源 / 历史不记录播放进度 / 目标文档版本 4” 还停留在方案层，没有进入源码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift
// 函数名: 无（顶层契约类型定义尚不存在）
// 功能说明: 修改前项目内没有这个文件，阶段 0 的 GIF 语义尚未形成统一源码入口。
```

### 修改后

- 新增 `CanvasImageAssetContract` 作为阶段 0 的统一契约入口。
- 在同一文件内集中定义播放模式、预览表面、预览模式、编辑策略、复制策略、历史策略，以及目标文档版本。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageAssetContract.swift
// 函数名: previewMode(for:) / shouldAutoplayAnimatedImagesOnCanvas / duplicatesShareUnderlyingAssetReference
// 功能说明: 修改后集中定义 GIF 阶段 0 契约；主画布可见自动播放，Board List、持久化缩略图、minimap、占位预览统一使用首帧。
enum CanvasAnimatedImagePlaybackMode: Equatable {
    case autoplayWhenVisible
}

enum CanvasAnimatedImagePreviewSurface: Equatable {
    case boardList
    case persistedThumbnail
    case miniMap
    case placeholder
}

enum CanvasAnimatedImagePreviewMode: Equatable {
    case posterFrameOnly
}

enum CanvasImageEditPolicy: Equatable {
    case geometryOnlyNonDestructiveCrop
}

enum CanvasImageDuplicationMode: Equatable {
    case shareUnderlyingAssetReference
}

enum CanvasAnimatedImageHistoryMode: Equatable {
    case trackDocumentStateExcludingPlaybackProgress
}

struct CanvasImageAssetContract: Equatable {
    let playbackMode: CanvasAnimatedImagePlaybackMode
    let editPolicy: CanvasImageEditPolicy
    let duplicationMode: CanvasImageDuplicationMode
    let historyMode: CanvasAnimatedImageHistoryMode
    let targetDocumentFormatVersion: Int

    static let current = CanvasImageAssetContract(
        playbackMode: .autoplayWhenVisible,
        editPolicy: .geometryOnlyNonDestructiveCrop,
        duplicationMode: .shareUnderlyingAssetReference,
        historyMode: .trackDocumentStateExcludingPlaybackProgress,
        targetDocumentFormatVersion: 4
    )

    func previewMode(
        for surface: CanvasAnimatedImagePreviewSurface
    ) -> CanvasAnimatedImagePreviewMode {
        switch surface {
        case .boardList,
             .persistedThumbnail,
             .miniMap,
             .placeholder:
            return .posterFrameOnly
        }
    }
}
```

## 修改二：`CanvasImageItem` 收口图片级复制与历史语义

### 修改前

- `CanvasImageItem` 只承载单帧图片和几何数据，本身没有“阶段 0 契约入口”。
- 图片复制逻辑分散在 `CanvasScene`，图片历史比较逻辑分散在 `BoardHistorySnapshot`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: init(...) / localFrame
// 功能说明: 修改前图片项初始化完成后直接进入几何计算，没有对 GIF 阶段 0 契约做统一暴露。
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

var localFrame: CGRect {
    CGRect(
        x: -size.width / 2,
        y: -size.height / 2,
        width: size.width,
        height: size.height
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: imageContentsRect / localFrame(forNormalizedCropRect:)
// 功能说明: 修改前这里直接从可见内容矩形进入后续几何计算，没有 item 级 duplicated / matchesDocumentState 辅助方法。
var imageContentsRect: CGRect {
    cropRectNormalized.cgRect
}

func localFrame(forNormalizedCropRect normalizedCropRect: CanvasImageCropRect) -> CGRect {
    let cropRect = normalizedCropRect.cgRect
    let fullImageFrame = fullImageLocalFrame
    return CGRect(
        x: fullImageFrame.minX + (cropRect.minX * fullImageFrame.width),
        y: fullImageFrame.minY + (cropRect.minY * fullImageFrame.height),
        width: fullImageFrame.width * cropRect.width,
        height: fullImageFrame.height * cropRect.height
    )
}
```

### 修改后

- 新增 `static var assetContract`，让图片项可以直接访问阶段 0 契约。
- 新增 `duplicated(offsetInWorld:)`，把“复制后共享底层资源”的阶段 0 语义收回到 item 自身。
- 新增 `matchesDocumentState(_:)`，把“历史比较不跟踪播放进度，但仍比较资源身份和几何状态”的规则收回到 item 自身。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: assetContract
// 功能说明: 修改后图片项可直接暴露阶段 0 的统一 GIF 契约，为后续资产引用改造提供统一入口。
static var assetContract: CanvasImageAssetContract {
    .current
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: duplicated(offsetInWorld:) / matchesDocumentState(_:)
// 功能说明: 修改后图片项统一承担“复制共享底层资源”和“历史比较忽略播放进度”的语义。
var imageContentsRect: CGRect {
    cropRectNormalized.cgRect
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
```

## 修改三：`CanvasScene` 与 `BoardHistorySnapshot` 改为走图片项语义入口

### 修改前

- `CanvasScene` 自己拼装图片复制结果，复制规则散落在调用点。
- `BoardHistorySnapshot` 自己按字段比较图片项，历史规则散落在调用点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改前 Scene 直接内联构造复制后的图片项，复制语义没有通过图片项统一收口。
case let .image(item):
    return .image(
        CanvasImageItem(
            cgImage: item.cgImage,
            center: CGPoint(
                x: item.center.x + offsetInWorld.x,
                y: item.center.y + offsetInWorld.y
            ),
            size: item.size,
            zIndex: item.zIndex,
            cropRectNormalized: item.cropRectNormalized,
            rotationRadians: item.rotationRadians
        )
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_)
// 功能说明: 修改前 HistorySnapshot 直接按字段比较图片项，历史规则没有通过图片项统一收口。
case let (.image(lhsImage), .image(rhsImage)):
    return lhsImage.id == rhsImage.id &&
        lhsImage.center == rhsImage.center &&
        lhsImage.size == rhsImage.size &&
        lhsImage.zIndex == rhsImage.zIndex &&
        lhsImage.cropRectNormalized == rhsImage.cropRectNormalized &&
        lhsImage.rotationRadians == rhsImage.rotationRadians
```

### 修改后

- `CanvasScene` 改为委托 `CanvasImageItem.duplicated(offsetInWorld:)`。
- `BoardHistorySnapshot` 改为委托 `CanvasImageItem.matchesDocumentState(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: duplicatedItem(from:offsetInWorld:)
// 功能说明: 修改后 Scene 不再内联复制图片项，而是统一走图片项自己的复制语义入口。
case let .image(item):
    return .image(item.duplicated(offsetInWorld: offsetInWorld))
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名: itemsMatch(_:_)
// 功能说明: 修改后 HistorySnapshot 统一走图片项的文档状态比较入口，为后续资产引用替换预留稳定边界。
case let (.image(lhsImage), .image(rhsImage)):
    return lhsImage.matchesDocumentState(rhsImage)
```

## 修改四：`CanvasEditorSession` 暴露主画布阶段 0 播放语义

### 修改前

- `CanvasEditorSession` 内没有显式属性表达“主画布应该自动播放可见 GIF”。
- 后续播放层如果直接接入，只能在 controller 或 viewport 侧临时硬编码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: init(saveQueueLabel:logPrefix:)
// 功能说明: 修改前 Session 在字段区只持有 renderer、minimap、history、save 等对象，没有 GIF 阶段 0 契约入口。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let contextResolver = CanvasContextResolver()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()
private let boardStoreLogPrefix: String

init(
    saveQueueLabel: String,
    logPrefix: String
) {
    boardStoreLogPrefix = logPrefix
    saveCoordinator = BoardSaveCoordinator(
        queueLabel: saveQueueLabel,
        logPrefix: logPrefix
    )
}
```

### 修改后

- `CanvasEditorSession` 新增 `imageAssetContract` 与 `shouldAutoplayAnimatedImagesOnCanvas`。
- 这样后续播放层可以直接从 Session 读取阶段 0 约束，不必在视图层重复硬编码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: imageAssetContract / shouldAutoplayAnimatedImagesOnCanvas
// 功能说明: 修改后 Session 明确暴露主画布阶段 0 的动画播放语义，后续播放层可直接复用这里的统一约束。
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let contextResolver = CanvasContextResolver()
private let saveCoordinator: BoardSaveCoordinator
private let historyController = BoardHistoryController()
private let boardStoreLogPrefix: String

var imageAssetContract: CanvasImageAssetContract {
    .current
}

var shouldAutoplayAnimatedImagesOnCanvas: Bool {
    imageAssetContract.shouldAutoplayAnimatedImagesOnCanvas
}
```

## 修改五：`BoardDocument` 显式暴露图片资产目标文档版本

### 修改前

- `BoardDocument` 只有当前已落地的 `currentFormatVersion = 3`。
- GIF 方案 B 的目标版本 `4` 还没有显式入口，阶段 0 无法在代码里对齐计划中的迁移目标。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: 无（BoardDocument 顶层静态常量）
// 功能说明: 修改前 BoardDocument 只暴露当前格式版本，尚未给 GIF 资产方案预留目标版本入口。
struct BoardDocument: Codable {
    static let currentFormatVersion = 3
    static let defaultTitle = "Untitled Board"
```

### 修改后

- 新增 `targetFormatVersionForImageAssets`，从统一契约读取阶段 0 约定的目标文档版本 `4`。
- 当前运行格式不变，阶段 0 只是先把未来迁移目标固化到代码里。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: 无（BoardDocument 顶层静态常量）
// 功能说明: 修改后 BoardDocument 显式暴露 GIF 资产方案的目标文档版本，但当前格式版本仍保持 3。
struct BoardDocument: Codable {
    static let currentFormatVersion = 3
    static let targetFormatVersionForImageAssets =
        CanvasImageAssetContract.current.targetDocumentFormatVersion
    static let defaultTitle = "Untitled Board"
```

## 修改六：`BoardPreviewContent` 固化 Board List 首帧预览策略

### 修改前

- `BoardPreviewContent` 只有 `empty / geometry / thumbnail` 三种内容表达。
- `Board List` 对动画图是“播放”还是“只看首帧”没有统一代码入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名: isThumbnail
// 功能说明: 修改前 Board List 预览内容只区分是否为缩略图，没有显式的 GIF 首帧策略。
enum BoardPreviewContent {
    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage, BoardPreviewSeed)

    var isThumbnail: Bool {
        if case .thumbnail = self {
            return true
        }

        return false
    }
}
```

### 修改后

- `BoardPreviewContent` 新增 `animatedImagePreviewSurface`、`animatedImagePreviewMode`、`usesPosterFrameForAnimatedImages`。
- `Board List` 的阶段 0 行为被明确固定为 `posterFrameOnly`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名: animatedImagePreviewMode / usesPosterFrameForAnimatedImages
// 功能说明: 修改后 Board List 对动画图的预览策略被统一固定为“只显示首帧”，避免列表滚动时引入动画播放。
enum BoardPreviewContent {
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .boardList

    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage, BoardPreviewSeed)

    static var animatedImagePreviewMode: CanvasAnimatedImagePreviewMode {
        CanvasImageAssetContract.current.previewMode(
            for: animatedImagePreviewSurface
        )
    }

    var isThumbnail: Bool {
        if case .thumbnail = self {
            return true
        }

        return false
    }

    var usesPosterFrameForAnimatedImages: Bool {
        Self.animatedImagePreviewMode == .posterFrameOnly
    }
}
```

## 阶段 0 完成状态

- 已完成：
  - 统一 GIF 阶段 0 契约入口
  - 图片项级复制语义入口
  - 图片项级历史比较语义入口
  - `Scene` / `HistorySnapshot` / `Session` / `BoardDocument` / `BoardPreviewContent` 的契约接入
- 未完成：
  - 资源引用模型替换
  - GIF 导入原始资源保留
  - `board.json` v4 实际迁移
  - 主画布自动播放实现
  - 缩略图与 minimap 的 GIF 首帧提取实现
