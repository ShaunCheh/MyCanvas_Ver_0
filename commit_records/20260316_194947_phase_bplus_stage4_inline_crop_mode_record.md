# 20260316_194947_phase_bplus_stage4_inline_crop_mode_record

## 记录范围

- 记录内容：
  1. 为图片实例补齐“完整原图”的 local/world 几何，作为 inline crop 预览、拖拽与提交的共享基础。
  2. 在 `CanvasRenderSnapshot` / `CanvasRenderer` 新增 crop overlay 语义，并让 crop 模式下的选中 item 以“完整原图预览 + 裁切框”方式渲染。
  3. 在 iOS / macOS viewport 上绘制 crop mask、crop outline 与 crop handles。
  4. 在 iOS / macOS controller 中接入 `Crop / Done` 入口、crop handle 命中、draft 拖拽与 `scene.cropItem(...)` 提交流程。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - inline rotate 模式
  - undo / redo 命令入口接线
  - 原始 gif diff
  - 构建产物目录 `.build_stage3_ios` / `.build_stage3_macos`

## 修改一：补齐 shared crop geometry 与 scene.cropItem(...) 提交入口

### 修改前

- `CanvasImageItem` 只有“当前可见区域”的 `localFrame / localQuad / worldQuad`，没有“完整原图”的 local/world 几何。
- 项目里也还没有“把 local crop frame 反推回 normalized crop rect”的共享 helper。
- `CanvasScene` 只有 `resizeItem(...)`，还没有统一的 `cropItem(...)` 写入入口。
- `CanvasInlineEditMode` 也还不是 `Equatable`，shared renderer / controller 不能直接用 `inlineEditState?.mode == .crop` 做 gate。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: localFrame / localQuad / worldQuad / imageContentsRect
// 功能说明: 修改前图片实例只能表达“当前可见区域”的局部/世界几何，还不能还原完整原图几何，也没有 local crop <-> normalized crop 的共享换算入口。
var localFrame: CGRect {
    CGRect(
        x: -size.width / 2,
        y: -size.height / 2,
        width: size.width,
        height: size.height
    )
}

var localQuad: CanvasQuad {
    CanvasQuad(rect: localFrame)
}

var worldQuad: CanvasQuad {
    localQuad.map(worldPoint(fromLocal:))
}

var imageContentsRect: CGRect {
    cropRectNormalized.cgRect
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditMode
// 功能说明: 修改前 inline 编辑模式只是普通 enum，shared 层不能直接做相等比较。
enum CanvasInlineEditMode {
    case crop
    case rotate
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:)
// 功能说明: 修改前 scene 只有 resize 入口，还没有 crop 提交 API。
@discardableResult
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        )
        item.size = standardizedFrame.size
        return item
    }
}
```

### 修改后

- `CanvasImageItem` 新增：
  - `fullImageLocalFrame`
  - `fullImageLocalQuad`
  - `fullImageWorldQuad`
  - `localFrame(forNormalizedCropRect:)`
  - `localQuad(forNormalizedCropRect:)`
  - `worldQuad(forNormalizedCropRect:)`
  - `normalizedCropRect(fromLocalFrame:)`
- `CanvasInlineEditMode` 声明为 `Equatable`，让 renderer / controller 可以直接按 mode 做 shared gate。
- `CanvasScene` 新增 `cropItem(withID:toNormalizedCropRect:)`，把“controller 编排、scene 落数据”这条 clean C 路径延伸到 crop。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: fullImageLocalFrame / fullImageLocalQuad / fullImageWorldQuad / localFrame(forNormalizedCropRect:) / worldQuad(forNormalizedCropRect:) / normalizedCropRect(fromLocalFrame:)
// 功能说明: 修改后图片实例既能表达当前可见区域，也能还原完整原图几何，并提供 crop draft / commit 所需的 local <-> normalized crop 共享换算。
var localFrame: CGRect {
    CGRect(
        x: -size.width / 2,
        y: -size.height / 2,
        width: size.width,
        height: size.height
    )
}

// Reconstruct the uncropped image extent in the item's local space so crop
// editing can preview and adjust against the original full image footprint.
var fullImageLocalFrame: CGRect {
    let normalizedCropRect = cropRectNormalized.cgRect
    let fullImageSize = CGSize(
        width: size.width / normalizedCropRect.width,
        height: size.height / normalizedCropRect.height
    )
    return CGRect(
        x: localFrame.minX - (normalizedCropRect.minX * fullImageSize.width),
        y: localFrame.minY - (normalizedCropRect.minY * fullImageSize.height),
        width: fullImageSize.width,
        height: fullImageSize.height
    )
}

var fullImageLocalQuad: CanvasQuad {
    CanvasQuad(rect: fullImageLocalFrame)
}

var fullImageWorldQuad: CanvasQuad {
    fullImageLocalQuad.map(worldPoint(fromLocal:))
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

func worldQuad(forNormalizedCropRect normalizedCropRect: CanvasImageCropRect) -> CanvasQuad {
    localQuad(forNormalizedCropRect: normalizedCropRect).map(worldPoint(fromLocal:))
}

func normalizedCropRect(fromLocalFrame localCropFrame: CGRect) -> CanvasImageCropRect {
    let fullImageFrame = fullImageLocalFrame
    guard
        fullImageFrame.width > 0,
        fullImageFrame.height > 0
    else {
        return .fullImage
    }

    return CanvasImageCropRect(
        CGRect(
            x: (localCropFrame.minX - fullImageFrame.minX) / fullImageFrame.width,
            y: (localCropFrame.minY - fullImageFrame.minY) / fullImageFrame.height,
            width: localCropFrame.width / fullImageFrame.width,
            height: localCropFrame.height / fullImageFrame.height
        )
    )
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名/类型名: CanvasInlineEditMode
// 功能说明: 修改后 inline edit mode 可直接做相等比较，让 shared renderer / controller 能按 mode gate crop 逻辑。
enum CanvasInlineEditMode: Equatable {
    case crop
    case rotate
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: cropItem(withID:toNormalizedCropRect:)
// 功能说明: 修改后 scene 统一负责把 normalized crop rect 提交成新的持久化 cropRectNormalized 与新的世界边界(center/size)。
@discardableResult
func cropItem(
    withID id: CanvasImageItemID,
    toNormalizedCropRect normalizedCropRect: CanvasImageCropRect
) -> CanvasImageItem? {
    updateItem(withID: id) { item in
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

## 修改二：为 snapshot / renderer 新增 crop overlay 语义，并在 crop 模式下切到完整原图预览

### 修改前

- `CanvasRenderSnapshot` 只有 `boardOverlay / items / selectionOverlay`。
- `CanvasRenderer.makeSnapshot(...)` 只接收 `interactionState`，不知道 `inlineEditState`。
- `makeSelectionOverlay(...)` 只要有选中项就会继续生成 selection overlay。
- `makeRenderItem(...)` 永远基于当前裁后可见区域做渲染，不会在 crop 模式下临时展示“完整原图”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasSelectionRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 里只有 selection overlay，还没有 crop overlay 语义。
struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let worldQuad: CanvasQuad
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let handles: [CanvasSelectionHandleGeometry]
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:) / makeSelectionOverlay(scene:camera:interactionState:) / makeRenderItem(for:camera:)
// 功能说明: 修改前 renderer 既不知道 inline edit state，也不会在 crop 模式下切换渲染语义或单独产出 crop overlay。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState()
) -> CanvasRenderSnapshot {
    // ... 省略未改动代码 ...
}

private func makeSelectionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState
) -> CanvasSelectionRenderOverlay? {
    // ... 省略未改动代码 ...
}

private func makeRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera
) -> CanvasRenderItem {
    let screenQuad = camera.worldToViewport(item.worldQuad)
    return CanvasRenderItem(
        id: item.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(item.center),
        screenBoundsSize: CGSize(
            width: item.size.width * camera.zoomScale,
            height: item.size.height * camera.zoomScale
        ),
        contentsRect: item.imageContentsRect,
        rotationRadians: item.rotationRadians,
        cgImage: item.cgImage,
        zIndex: item.zIndex
    )
}
```

### 修改后

- `CanvasRenderSnapshot` 新增：
  - `CanvasCropHandleRole`
  - `CanvasCropHandleGeometry`
  - `CanvasCropRenderOverlay`
  - `cropOverlay`
- `CanvasRenderer.makeSnapshot(...)` 新增 `inlineEditState` 参数。
- `makeSelectionOverlay(...)` 在 crop 模式下直接返回 `nil`，避免 selection chrome 和 crop chrome 同时出现。
- `makeRenderItem(...)` 在“当前 item 进入 crop 模式”时，临时切到：
  - `item.fullImageWorldQuad`
  - `item.fullImageLocalFrame.size`
  - `CanvasImageCropRect.fullImage.cgRect`
- `makeCropOverlay(...)` 把 full image quad、draft crop quad 和 handles 全部集中在 shared renderer 里生产。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasCropHandleRole / CanvasCropHandleGeometry / CanvasCropRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 增加 crop overlay 语义，shared 层统一输出完整原图、crop 框和 crop handles 的中性几何。
enum CanvasCropHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct CanvasCropHandleGeometry {
    let role: CanvasCropHandleRole
    let screenCenter: CGPoint
}

// Crop overlay stays semantic and neutral: renderer describes the full image
// extent plus the active crop rect, while each platform decides how to dim and
// decorate that geometry for inline editing.
struct CanvasCropRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
    let handles: [CanvasCropHandleGeometry]
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil,
        cropOverlay: nil
    )
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:inlineEditState:) / makeSelectionOverlay(scene:camera:interactionState:inlineEditState:) / makeRenderItem(for:camera:inlineEditState:) / makeCropOverlay(scene:camera:inlineEditState:)
// 功能说明: 修改后 renderer 既知道 inline crop mode，也负责在 crop 模式下切换到完整原图预览并生成 crop overlay 语义。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    // ... 省略前置可见性代码 ...
    let renderItems = visibleItems.map { item in
        makeRenderItem(
            for: item,
            camera: camera,
            inlineEditState: inlineEditState
        )
    }

    let selectionOverlay = makeSelectionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )
    let cropOverlay = makeCropOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    )

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay
    )
}

private func makeSelectionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasSelectionRenderOverlay? {
    guard inlineEditState?.mode != .crop else {
        return nil
    }
    // ... 省略未改动代码 ...
}

private func makeRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasRenderItem {
    let isEditingCropItem =
        inlineEditState?.mode == .crop &&
        inlineEditState?.itemID == item.id
    let worldQuad = isEditingCropItem ? item.fullImageWorldQuad : item.worldQuad
    let renderCenter = isEditingCropItem
        ? item.worldPoint(fromLocal: CGPoint(
            x: item.fullImageLocalFrame.midX,
            y: item.fullImageLocalFrame.midY
        ))
        : item.center
    let renderSize = isEditingCropItem
        ? item.fullImageLocalFrame.size
        : item.size
    let contentsRect = isEditingCropItem
        ? CanvasImageCropRect.fullImage.cgRect
        : item.imageContentsRect
    let screenQuad = camera.worldToViewport(worldQuad)
    return CanvasRenderItem(
        id: item.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        contentsRect: contentsRect,
        rotationRadians: item.rotationRadians,
        cgImage: item.cgImage,
        zIndex: item.zIndex
    )
}

private func makeCropOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasCropRenderOverlay? {
    guard
        let inlineEditState,
        inlineEditState.mode == .crop,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        return nil
    }

    let fullImageWorldQuad = item.fullImageWorldQuad
    let cropWorldQuad = item.worldQuad(forNormalizedCropRect: inlineEditState.draftCropRectNormalized)
    let fullImageScreenQuad = camera.worldToViewport(fullImageWorldQuad)
    let cropScreenQuad = camera.worldToViewport(cropWorldQuad)

    return CanvasCropRenderOverlay(
        itemID: item.id,
        mode: inlineEditState.mode,
        fullImageWorldQuad: fullImageWorldQuad,
        fullImageScreenQuad: fullImageScreenQuad,
        cropRectNormalized: inlineEditState.draftCropRectNormalized,
        cropWorldQuad: cropWorldQuad,
        cropScreenQuad: cropScreenQuad,
        handles: makeCropHandles(for: cropScreenQuad)
    )
}
```

## 修改三：在 iOS / macOS viewport 上绘制 crop mask、outline 与 handles

### 修改前

- 两个平台 viewport 都只有 selection overlay layers。
- `apply(_:)` 也只会刷新 image layers、board highlight 和 selection overlay。
- 没有 crop mask / crop outline / crop handles 的 layer，也没有 `refreshCropOverlay()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: selectionOutlineLayer / selectionHandleLayers / apply(_:) / setupLayers() / refreshSelectionOverlay()
// 功能说明: 修改前 iOS viewport 只画 selection overlay，没有 crop mask / outline / handles。
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
    }
}

private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    overlayLayer.addSublayer(selectionOutlineLayer)
    // ... 省略未改动代码 ...
}

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }
    // ... 省略未改动代码 ...
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: selectionOutlineLayer / selectionHandleLayers / apply(_:) / setupLayers() / refreshSelectionOverlay()
// 功能说明: 修改前 macOS viewport 也只有 selection overlay，没有 crop 专用绘制层。
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
    }
}
```

### 修改后

- iOS / macOS viewport 都新增：
  - `cropMaskLayer`
  - `cropOutlineLayer`
  - `cropHandleLayers`
  - `configureCropMaskLayer()`
  - `configureCropOutlineLayer()`
  - `configureCropHandleLayers()`
  - `refreshCropOverlay()`
  - `hideCropOverlay()`
- `apply(_:)` 和 `viewDidMoveToWindow()` 都会同步刷新 crop overlay。
- crop mask 采用“完整原图 quad - crop quad”的 even-odd 路径；平台层继续各自决定遮罩透明度、线宽和 handle 视觉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: cropMaskLayer / cropOutlineLayer / cropHandleLayers / refreshCropOverlay()
// 功能说明: 修改后 iOS viewport 消费 renderer 的 crop 语义几何，绘制完整原图遮罩、crop 框和四角 handles。
private static let cropMaskFillColor = UIColor.black.withAlphaComponent(0.4).cgColor
private static let cropOutlineStrokeColor = CGColor(
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 1
)
private static let cropHandleFillColor = CGColor(gray: 1, alpha: 1)
private static let cropOutlineLineWidth: CGFloat = 2
private static let cropHandleLineWidth: CGFloat = 2
private static let cropHandleSize: CGFloat = 12

private let cropMaskLayer = CAShapeLayer()
private let cropOutlineLayer = CAShapeLayer()
private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
        refreshCropOverlay()
    }
}

private func refreshCropOverlay() {
    guard let cropOverlay = snapshot.cropOverlay else {
        hideCropOverlay()
        return
    }

    // Crop chrome stays platform-owned; shared renderer only provides the
    // full-image and crop quads needed to dim, outline, and hit-test here.
    let maskPath = CGMutablePath()
    maskPath.addPath(Self.quadPath(for: cropOverlay.fullImageScreenQuad))
    maskPath.addPath(Self.quadPath(for: cropOverlay.cropScreenQuad))
    cropMaskLayer.path = maskPath
    cropMaskLayer.isHidden = false
    cropMaskLayer.contentsScale = currentContentsScale

    cropOutlineLayer.path = Self.quadPath(for: cropOverlay.cropScreenQuad)
    cropOutlineLayer.isHidden = false
    cropOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = cropOverlay.handles.first(where: { $0.role == role })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: cropMaskLayer / cropOutlineLayer / cropHandleLayers / refreshCropOverlay()
// 功能说明: 修改后 macOS viewport 同步消费 crop overlay 语义，在平台层决定遮罩透明度、线宽和 handles 视觉。
private static let cropMaskFillColor = CGColor(gray: 0, alpha: 0.4)
private static let cropOutlineStrokeColor = CGColor(
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 1
)
private static let cropHandleFillColor = CGColor(gray: 1, alpha: 1)
private static let cropOutlineLineWidth: CGFloat = 2
private static let cropHandleLineWidth: CGFloat = 2
private static let cropHandleSize: CGFloat = 10

private let cropMaskLayer = CAShapeLayer()
private let cropOutlineLayer = CAShapeLayer()
private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]

private func refreshCropOverlay() {
    guard let cropOverlay = snapshot.cropOverlay else {
        hideCropOverlay()
        return
    }

    let maskPath = CGMutablePath()
    maskPath.addPath(Self.quadPath(for: cropOverlay.fullImageScreenQuad))
    maskPath.addPath(Self.quadPath(for: cropOverlay.cropScreenQuad))
    cropMaskLayer.path = maskPath
    cropMaskLayer.isHidden = false
    cropMaskLayer.contentsScale = currentContentsScale

    cropOutlineLayer.path = Self.quadPath(for: cropOverlay.cropScreenQuad)
    cropOutlineLayer.isHidden = false
    cropOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = cropOverlay.handles.first(where: { $0.role == role })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

## 修改四：iOS controller 接入 Crop / Done 入口、crop 命中状态机与提交流程

### 修改前

- iOS controller 只有 selection / move / resize 这套 press target 和 drag state。
- 没有 `cropButton`，也没有 `inlineEditState`。
- `performCanvasRefresh(...)` 只把 `interactionState` 传给 renderer。
- `pointerPressTarget(...)` 只考虑 selection handle、body 和 blank，不知道 crop handle。
- 没有 `makePointerCropState(...)`、`updateCropDraft(...)`、`commitCropDraftIfNeeded()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerDragState / setupViewHierarchy() / setupConstraints() / setupSaveButton()
// 功能说明: 修改前 iOS controller 还没有 crop 按钮、inline edit state 和 crop 专用输入状态机。
private enum PointerPressTarget {
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private let saveButton: UIButton = { /* ... 省略未改动代码 ... */ }()
private let canvasViewportView = iOSCanvasViewportView()
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        // ... 省略未改动代码 ...
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12)
    ])
}

private func setupSaveButton() {
    saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:) / pointerPressTarget(at:)
// 功能说明: 修改前 renderer 不接 inlineEditState，pointer hit test 也还不认识 crop handle。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    if itemID == interactionState.selectedItemID {
        return .selectedBody(itemID: itemID)
    }

    return .unselectedItem(itemID: itemID)
}
```

### 修改后

- iOS controller 新增：
  - `cropButton`
  - `inlineEditState`
  - `PointerPressTarget.cropHandle`
  - `PointerCropState`
  - `PointerDragState.croppingSelectedItem`
  - crop hit-test / drag / commit helper
- `Crop / Done` 入口与当前浮层按钮体系保持同一层级。
- `pointerPressTarget(...)` 在 crop 模式下只消费 crop handle hit-test，并屏蔽常规 selection handle / body 逻辑。
- `handlePrimaryPointerMove(...)` / `handlePrimaryPointerUp(...)` / `handlePrimaryPointerCancel()` 增加 crop draft 预览与提交逻辑。
- `performCanvasRefresh(...)` 把 `inlineEditState` 一并传给 renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerCropState / PointerDragState / cropButton / inlineEditState / setupCropButton()
// 功能说明: 修改后 iOS controller 新增 crop 专用按钮、inline edit state，以及 crop handle / crop drag 的输入状态机。
private enum PointerPressTarget {
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private struct PointerCropState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasCropHandleRole
    let fullImageLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumLocalSize: CGSize
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case croppingSelectedItem(PointerCropState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let cropHandleHitTargetSize: CGFloat = 28
private static let minimumCropViewportDimension: CGFloat = 28
private let cropButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
private var inlineEditState: CanvasInlineEditState?

private func setupCropButton() {
    cropButton.addTarget(self, action: #selector(handleCropButtonTap), for: .touchUpInside)
    updateCropButtonAppearance()
}

@objc
private func handleCropButtonTap() {
    if isInlineCropModeActive {
        endInlineEditMode(reason: "exit crop mode")
    } else {
        beginCropModeIfPossible()
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:) / hitTestCropHandle(at:) / pointerPressTarget(at:) / makePointerCropState(itemID:handleRole:) / updateCropDraft(using:to:) / commitCropDraftIfNeeded()
// 功能说明: 修改后 iOS controller 在 crop 模式下把命中、拖拽预览与 scene.cropItem 提交统一接到 shared crop geometry 上。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    logCanvasState(reason: reason, snapshot: snapshot)
}

private func hitTestCropHandle(at viewportLocation: CGPoint) -> (role: CanvasCropHandleRole, itemID: CanvasImageItemID)? {
    guard let cropOverlay = lastRenderSnapshot.cropOverlay else {
        return nil
    }

    return cropOverlay.handles.first(where: { handle in
        Self.cropHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: cropOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }
    // ... 省略未改动代码 ...
}

private func makePointerCropState(
    itemID: CanvasImageItemID,
    handleRole: CanvasCropHandleRole
) -> PointerCropState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    let fullImageLocalFrame = item.fullImageLocalFrame.standardized
    let draftLocalFrame = item.localFrame(
        forNormalizedCropRect: inlineEditState.draftCropRectNormalized
    ).standardized
    let minimumLocalDimension = Self.minimumCropViewportDimension / camera.zoomScale

    return PointerCropState(
        itemID: itemID,
        handleRole: handleRole,
        fullImageLocalFrame: fullImageLocalFrame,
        fixedOppositeLocalCorner: fixedOppositeLocalCorner(
            for: handleRole,
            in: draftLocalFrame
        ),
        minimumLocalSize: CGSize(
            width: min(minimumLocalDimension, fullImageLocalFrame.width),
            height: min(minimumLocalDimension, fullImageLocalFrame.height)
        )
    )
}

private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == cropState.itemID,
        let item = scene.item(withID: cropState.itemID)
    else {
        return
    }

    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let constrainedLocalPoint = constrainedDraggedCropLocalCorner(
        draggedLocalPoint,
        for: cropState.handleRole,
        oppositeCorner: cropState.fixedOppositeLocalCorner,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let cropLocalFrame = CGRect(
        x: min(constrainedLocalPoint.x, cropState.fixedOppositeLocalCorner.x),
        y: min(constrainedLocalPoint.y, cropState.fixedOppositeLocalCorner.y),
        width: abs(constrainedLocalPoint.x - cropState.fixedOppositeLocalCorner.x),
        height: abs(constrainedLocalPoint.y - cropState.fixedOppositeLocalCorner.y)
    ).standardized
    let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update crop draft")
}

private func commitCropDraftIfNeeded() {
    guard
        let inlineEditState,
        inlineEditState.mode == .crop,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard item.cropRectNormalized != inlineEditState.draftCropRectNormalized else {
        historyController.cancelPendingTransaction()
        return
    }

    guard let croppedItem = scene.cropItem(
        withID: inlineEditState.itemID,
        toNormalizedCropRect: inlineEditState.draftCropRectNormalized
    ) else {
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: croppedItem.worldBounds)
    self.inlineEditState = CanvasInlineEditState(item: croppedItem, mode: .crop)
    requestCanvasRefresh(reason: "commit crop item")
    commitPendingPointerHistoryTransaction(autosaveReason: "crop item")
}
```

- 同时，iOS controller 还补了 crop 模式的 enter / exit / sync 和按钮外观更新逻辑，让选中切换、恢复运行态与按钮状态保持一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginCropModeIfPossible() / endInlineEditMode(reason:) / syncInlineEditStateWithSelection() / updateCropButtonAppearance() / applyCropButtonAppearance(title:systemImageName:backgroundColor:isEnabled:)
// 功能说明: 修改后 iOS controller 负责把 crop 子模式与选中状态、按钮视觉和 renderer 刷新保持同步。
private var isInlineCropModeActive: Bool {
    inlineEditState?.mode == .crop
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateCropButtonAppearance()
    requestCanvasRefresh(reason: "enter crop mode")
}

private func endInlineEditMode(reason: String) {
    guard inlineEditState != nil else {
        return
    }

    inlineEditState = nil
    updateCropButtonAppearance()
    requestCanvasRefresh(reason: reason)
}

private func syncInlineEditStateWithSelection() {
    guard let inlineEditState else {
        updateCropButtonAppearance()
        return
    }

    guard interactionState.selectedItemID == inlineEditState.itemID else {
        self.inlineEditState = nil
        updateCropButtonAppearance()
        return
    }

    if let item = scene.item(withID: inlineEditState.itemID) {
        self.inlineEditState = CanvasInlineEditState(item: item, mode: inlineEditState.mode)
    }
    updateCropButtonAppearance()
}

private func updateCropButtonAppearance() {
    let isActive = isInlineCropModeActive
    let isEnabled = isActive || interactionState.selectedItemID != nil
    applyCropButtonAppearance(
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        backgroundColor: isActive ? .systemOrange : .systemIndigo,
        isEnabled: isEnabled
    )
}
```

## 修改五：macOS controller 同步接入相同的 crop 模式与提交流程

### 修改前

- macOS controller 与 iOS 一样，只有 selection / move / resize 这套输入状态机。
- 没有 `cropButton`、没有 `inlineEditState`、没有 crop handle hit-test。
- `refreshCanvas()` 也只把 `interactionState` 传给 renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerDragState / setupViewHierarchy() / setupConstraints() / setupSaveButton()
// 功能说明: 修改前 macOS controller 也还没有 crop 子模式入口和 crop 专用输入状态机。
private enum PointerPressTarget {
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private let saveButton: NSButton = { /* ... 省略未改动代码 ... */ }()
private let canvasViewportView = macOSCanvasViewportView()
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupSaveButton() {
    saveButton.target = self
    saveButton.action = #selector(handleSaveButtonClick)
}

private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

### 修改后

- macOS controller 同步新增：
  - `cropButton`
  - `inlineEditState`
  - `PointerPressTarget.cropHandle`
  - `PointerCropState`
  - `PointerDragState.croppingSelectedItem`
- `handleCropButtonClick()` 负责切换 `Crop / Done`。
- `pointerPressTarget(...)`、`makePointerCropState(...)`、`updateCropDraft(...)`、`commitCropDraftIfNeeded()` 与 iOS 保持同一套 shared geometry 驱动方式。
- `refreshCanvas()` 改为把 `inlineEditState` 一并传给 renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: PointerPressTarget / PointerCropState / PointerDragState / cropButton / inlineEditState / setupCropButton()
// 功能说明: 修改后 macOS controller 与 iOS 同步拥有 crop 子模式入口、crop hit-test 和 crop drag 状态机。
private enum PointerPressTarget {
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private struct PointerCropState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasCropHandleRole
    let fullImageLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumLocalSize: CGSize
}

private enum PointerDragState {
    case idle
    case pressed(
        pressedLocation: CGPoint,
        pressTarget: PointerPressTarget
    )
    case croppingSelectedItem(PointerCropState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private static let cropHandleHitTargetSize: CGFloat = 18
private static let minimumCropViewportDimension: CGFloat = 20
private let cropButton: NSButton = {
    let button = NSButton(title: "Crop", target: nil, action: nil)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.bezelStyle = .rounded
    button.imagePosition = .imageLeading
    return button
}()
private var inlineEditState: CanvasInlineEditState?

private func setupCropButton() {
    cropButton.target = self
    cropButton.action = #selector(handleCropButtonClick)
    updateCropButtonAppearance()
}

@objc
private func handleCropButtonClick() {
    if isInlineCropModeActive {
        endInlineEditMode(reason: "exit crop mode")
    } else {
        beginCropModeIfPossible()
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshCanvas() / hitTestCropHandle(at:) / pointerPressTarget(at:) / makePointerCropState(itemID:handleRole:) / updateCropDraft(using:to:) / commitCropDraftIfNeeded()
// 功能说明: 修改后 macOS controller 也基于 shared crop geometry 完成 crop handle 命中、draft 预览与 scene.cropItem 提交。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}

private func hitTestCropHandle(at viewportLocation: CGPoint) -> (role: CanvasCropHandleRole, itemID: CanvasImageItemID)? {
    guard let cropOverlay = lastRenderSnapshot.cropOverlay else {
        return nil
    }

    return cropOverlay.handles.first(where: { handle in
        Self.cropHandleHitRect(centeredAt: handle.screenCenter).contains(viewportLocation)
    }).map { handle in
        (role: handle.role, itemID: cropOverlay.itemID)
    }
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }
    // ... 省略未改动代码 ...
}

private func makePointerCropState(
    itemID: CanvasImageItemID,
    handleRole: CanvasCropHandleRole
) -> PointerCropState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    let fullImageLocalFrame = item.fullImageLocalFrame.standardized
    let draftLocalFrame = item.localFrame(
        forNormalizedCropRect: inlineEditState.draftCropRectNormalized
    ).standardized
    let minimumLocalDimension = Self.minimumCropViewportDimension / camera.zoomScale

    return PointerCropState(
        itemID: itemID,
        handleRole: handleRole,
        fullImageLocalFrame: fullImageLocalFrame,
        fixedOppositeLocalCorner: fixedOppositeLocalCorner(
            for: handleRole,
            in: draftLocalFrame
        ),
        minimumLocalSize: CGSize(
            width: min(minimumLocalDimension, fullImageLocalFrame.width),
            height: min(minimumLocalDimension, fullImageLocalFrame.height)
        )
    )
}

private func updateCropDraft(
    using cropState: PointerCropState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .crop,
        inlineEditState.itemID == cropState.itemID,
        let item = scene.item(withID: cropState.itemID)
    else {
        return
    }

    let draggedWorldPoint = camera.viewportToWorld(viewportLocation)
    let draggedLocalPoint = item.localPoint(fromWorld: draggedWorldPoint)
    let constrainedLocalPoint = constrainedDraggedCropLocalCorner(
        draggedLocalPoint,
        for: cropState.handleRole,
        oppositeCorner: cropState.fixedOppositeLocalCorner,
        fullImageLocalFrame: cropState.fullImageLocalFrame,
        minimumLocalSize: cropState.minimumLocalSize
    )
    let cropLocalFrame = CGRect(
        x: min(constrainedLocalPoint.x, cropState.fixedOppositeLocalCorner.x),
        y: min(constrainedLocalPoint.y, cropState.fixedOppositeLocalCorner.y),
        width: abs(constrainedLocalPoint.x - cropState.fixedOppositeLocalCorner.x),
        height: abs(constrainedLocalPoint.y - cropState.fixedOppositeLocalCorner.y)
    ).standardized
    let draftCropRectNormalized = item.normalizedCropRect(fromLocalFrame: cropLocalFrame)
    guard inlineEditState.draftCropRectNormalized != draftCropRectNormalized else {
        return
    }

    inlineEditState.draftCropRectNormalized = draftCropRectNormalized
    self.inlineEditState = inlineEditState
    refreshCanvas()
}

private func commitCropDraftIfNeeded() {
    guard
        let inlineEditState,
        inlineEditState.mode == .crop,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard item.cropRectNormalized != inlineEditState.draftCropRectNormalized else {
        historyController.cancelPendingTransaction()
        return
    }

    guard let croppedItem = scene.cropItem(
        withID: inlineEditState.itemID,
        toNormalizedCropRect: inlineEditState.draftCropRectNormalized
    ) else {
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: croppedItem.worldBounds)
    self.inlineEditState = CanvasInlineEditState(item: croppedItem, mode: .crop)
    refreshCanvas()
    commitPendingPointerHistoryTransaction(autosaveReason: "crop item")
}
```

- macOS 侧同样补了 mode 同步与按钮外观更新，让 `Crop / Done`、选中状态和 inline edit state 保持一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: beginCropModeIfPossible() / endInlineEditMode(reason:) / syncInlineEditStateWithSelection() / updateCropButtonAppearance() / applyCropButtonAppearance(title:systemImageName:tintColor:isEnabled:)
// 功能说明: 修改后 macOS controller 负责维护 crop 子模式与按钮状态，并与选中状态、renderer 刷新同步。
private var isInlineCropModeActive: Bool {
    inlineEditState?.mode == .crop
}

private func beginCropModeIfPossible() {
    guard
        let selectedItemID = interactionState.selectedItemID,
        let item = scene.item(withID: selectedItemID)
    else {
        return
    }

    inlineEditState = CanvasInlineEditState(item: item, mode: .crop)
    updateCropButtonAppearance()
    refreshCanvas()
}

private func endInlineEditMode(reason _: String) {
    guard inlineEditState != nil else {
        return
    }

    inlineEditState = nil
    updateCropButtonAppearance()
    refreshCanvas()
}

private func syncInlineEditStateWithSelection() {
    guard let inlineEditState else {
        updateCropButtonAppearance()
        return
    }

    guard interactionState.selectedItemID == inlineEditState.itemID else {
        self.inlineEditState = nil
        updateCropButtonAppearance()
        return
    }

    if let item = scene.item(withID: inlineEditState.itemID) {
        self.inlineEditState = CanvasInlineEditState(item: item, mode: inlineEditState.mode)
    }
    updateCropButtonAppearance()
}

private func updateCropButtonAppearance() {
    let isActive = isInlineCropModeActive
    let isEnabled = isActive || interactionState.selectedItemID != nil
    applyCropButtonAppearance(
        title: isActive ? "Done" : "Crop",
        systemImageName: isActive ? "checkmark" : "crop",
        tintColor: isActive ? .systemOrange : .controlAccentColor,
        isEnabled: isEnabled
    )
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增 lint 问题：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 构建验证通过：
  - iOS Simulator `xcodebuild` 构建成功
  - macOS `xcodebuild` 构建成功

## 本阶段结果总结

- shared 层现在已经能表达“完整原图 + 当前 draft crop 框”的统一几何，并有 `scene.cropItem(...)` 负责提交。
- renderer / snapshot / viewport 已经形成了完整的 crop overlay 管线，保持 clean C：共享层只产出语义几何，平台层只决定视觉表现。
- iOS / macOS 两端 controller 也已经统一到“Crop / Done 入口 + crop handle hit-test + drag preview + pointerUp 提交”的阶段四规则。
- 后续阶段五可以在这套框架上继续接入 rotate overlay、rotate 状态机，并修正旋转后的 selection / resize。
