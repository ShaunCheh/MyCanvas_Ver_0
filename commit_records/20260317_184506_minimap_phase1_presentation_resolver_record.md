# 20260317_184506_minimap_phase1_presentation_resolver_record

## 记录范围

- 记录内容：
  1. 新增 `CanvasImagePresentation`，把图片当前展示所需的共享几何抽成独立结构。
  2. 新增 `CanvasImagePresentationResolver`，统一合并正式状态、裁切草稿、旋转草稿。
  3. 修改 `CanvasRenderer`，让 `selection overlay`、`crop overlay`、`render item` 全部改为消费共享 presentation，而不是继续在 renderer 内部零散拼装 preview 几何。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - minimap 视图/UI
  - minimap snapshot / renderer
  - 原始 gif diff
  - git commit / push

## 修改一：新增 `CanvasImagePresentation`，收敛共享展示几何

### 修改前

- 还没有独立的 presentation 层。
- `CanvasRenderer` 直接在 `makeRenderItem(...)` 内部拼接 `crop preview`、`rotation preview`、`full image` 与 `visible image` 的几何关系。
- 这种结构只够主画板自己使用，后续 minimap 无法复用一份统一的“当前展示结果”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 自己决定 crop 编辑时画完整图片还是可见区域，并在本地临时推导 renderCenter / renderSize / contentsRect。
let previewItem = previewedItem(
    for: item,
    inlineEditState: inlineEditState,
    rotationPreviewState: rotationPreviewState
)
let isEditingCropItem =
    inlineEditState?.mode == .crop &&
    inlineEditState?.itemID == item.id
let worldQuad = isEditingCropItem
    ? previewItem.fullImageWorldQuad
    : previewItem.worldQuad
let renderCenter = isEditingCropItem
    ? previewItem.worldPoint(fromLocal: CGPoint(
        x: previewItem.fullImageLocalFrame.midX,
        y: previewItem.fullImageLocalFrame.midY
    ))
    : previewItem.center
let renderSize = isEditingCropItem
    ? previewItem.fullImageLocalFrame.size
    : previewItem.size
let contentsRect = isEditingCropItem
    ? CanvasImageCropRect.fullImage.cgRect
    : previewItem.imageContentsRect
```

### 修改后

- 新增 `CanvasImagePresentation`，集中表达“当前图片应该如何被展示”。
- 这个结构同时保留：
  - 当前可见区域的局部/世界几何
  - 完整图片的局部/世界几何
  - 当前有效的旋转角与裁切值
  - 当前是否处于 crop/rotation preview
- 这样后续主画板 renderer 和 minimap renderer 可以共享同一份展示解释结果，而不是重复推导。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentation.swift
// 函数名: CanvasImagePresentation
// 功能说明: 新增共享展示结构，统一承载可见区域、完整图片区域、有效裁切/旋转值以及 preview 标记。
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

## 修改二：新增 `CanvasImagePresentationResolver`，统一合并正式态与预览态

### 修改前

- 旋转预览只在 `previewedItem(...)` 里覆盖 `rotationRadians`。
- 裁切预览则散落在 `makeCropEditOverlay(...)` 和 `makeRenderItem(...)` 两个函数里各算一次。
- 结果是：
  - rotate preview 有单独入口
  - crop preview 没有统一“当前可见几何”
  - 后续 minimap 无法直接复用一套统一解释逻辑

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: previewedItem(for:inlineEditState:rotationPreviewState:) / makeCropEditOverlay(scene:camera:inlineEditState:)
// 功能说明: 修改前 rotate 与 crop 预览态分别散落在多个函数内处理，没有共享的 presentation resolver。
private func previewedItem(
    for item: CanvasImageItem,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasImageItem {
    if
        let inlineEditState,
        inlineEditState.itemID == item.id
    {
        return item
    }

    guard
        let rotationPreviewState,
        rotationPreviewState.itemID == item.id
    else {
        return item
    }

    var previewItem = item
    previewItem.rotationRadians = rotationPreviewState.draftRotationRadians
    return previewItem
}

let cropWorldQuad = previewItem.worldQuad(
    forNormalizedCropRect: cropSession.draftCropRectNormalized
)
```

### 修改后

- 新增 `CanvasImagePresentationResolver.resolve(...)` 作为统一入口。
- 处理顺序是：
  1. 先判断当前 item 是否命中 crop preview / rotation preview。
  2. 如果命中 rotation preview，先把 `effectiveItem.rotationRadians` 替换为草稿角度。
  3. 如果命中 crop preview，再基于草稿裁切值重新计算 `visibleLocalFrame` 与 `visibleWorldQuad`。
  4. 最后再统一返回 `fullImageWorldQuad`、`visibleWorldQuad`、中心点、尺寸等结果。
- 这样后续 minimap 只要消费 resolver，就能拿到裁切后且带旋转角的当前可见几何。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImagePresentationResolver.swift
// 函数名: resolve(item:inlineEditState:rotationPreviewState:)
// 功能说明: 新增统一几何解释器，先合并旋转草稿，再合并裁切草稿，最终产出当前图片的共享 presentation。
struct CanvasImagePresentationResolver {
    func resolve(
        item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasImagePresentation {
        let isCropPreviewActive = inlineEditState?.itemID == item.id
        let isRotationPreviewActive = rotationPreviewState?.itemID == item.id

        var effectiveItem = item
        if let rotationPreviewState, rotationPreviewState.itemID == item.id {
            effectiveItem.rotationRadians = rotationPreviewState.draftRotationRadians
        }

        let effectiveCropRectNormalized = isCropPreviewActive
            ? inlineEditState?.draftCropRectNormalized ?? effectiveItem.cropRectNormalized
            : effectiveItem.cropRectNormalized

        let visibleLocalFrame = isCropPreviewActive
            ? effectiveItem.localFrame(
                forNormalizedCropRect: effectiveCropRectNormalized
            ).standardized
            : effectiveItem.localFrame.standardized
        let visibleWorldQuad = isCropPreviewActive
            ? effectiveItem.worldQuad(
                forNormalizedCropRect: effectiveCropRectNormalized
            )
            : effectiveItem.worldQuad

        return CanvasImagePresentation(
            itemID: effectiveItem.id,
            cgImage: effectiveItem.cgImage,
            zIndex: effectiveItem.zIndex,
            effectiveRotationRadians: effectiveItem.rotationRadians,
            effectiveCropRectNormalized: effectiveCropRectNormalized,
            visibleLocalFrame: visibleLocalFrame,
            visibleWorldQuad: visibleWorldQuad,
            visibleCenter: effectiveItem.worldPoint(
                fromLocal: CGPoint(x: visibleLocalFrame.midX, y: visibleLocalFrame.midY)
            ),
            visibleSize: visibleLocalFrame.size,
            fullImageLocalFrame: effectiveItem.fullImageLocalFrame.standardized,
            fullImageWorldQuad: effectiveItem.fullImageWorldQuad,
            fullImageCenter: effectiveItem.worldPoint(
                fromLocal: CGPoint(
                    x: effectiveItem.fullImageLocalFrame.midX,
                    y: effectiveItem.fullImageLocalFrame.midY
                )
            ),
            fullImageSize: effectiveItem.fullImageLocalFrame.standardized.size,
            isCropPreviewActive: isCropPreviewActive,
            isRotationPreviewActive: isRotationPreviewActive
        )
    }
}
```

## 修改三：`CanvasRenderer` 改为依赖共享 presentation

### 修改前

- `selection overlay` 直接使用 `previewItem.worldQuad`。
- `crop overlay` 手动从 `cropSession.draftCropRectNormalized` 计算 `cropWorldQuad`。
- `render item` 手动判断 `isEditingCropItem`，再选择 `fullImageWorldQuad` 或 `worldQuad`。
- `makeRotateAffordance(...)` 直接依赖 `CanvasImageItem.center`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeCropEditOverlay(...) / makeRotateAffordance(...)
// 功能说明: 修改前 selection、crop、rotate 的展示几何分别取自 previewItem 或 cropSession，几何来源不统一。
let previewItem = previewedItem(
    for: selectedItem,
    inlineEditState: inlineEditState,
    rotationPreviewState: rotationPreviewState
)
let worldQuad = previewItem.worldQuad

let cropWorldQuad = previewItem.worldQuad(
    forNormalizedCropRect: cropSession.draftCropRectNormalized
)

private func makeRotateAffordance(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    screenQuad: CanvasQuad
) -> CanvasEditRotateOverlayPayload {
    let screenCenter = camera.worldToViewport(item.center)
    // ...
}
```

### 修改后

- `CanvasRenderer` 新增 `presentationResolver` 字段。
- `selection overlay` 改为读取 `presentation.visibleWorldQuad`。
- `crop overlay` 改为读取 `presentation.fullImageWorldQuad` 与 `presentation.visibleWorldQuad`。
- `render item` 改为读取 `presentation.fullImageCenter / visibleCenter / fullImageSize / visibleSize / effectiveCropRectNormalized`。
- `makeRotateAffordance(...)` 改为依赖 `CanvasImagePresentation.visibleCenter`。
- 原有 `previewedItem(...)` 已删除，避免 renderer 内继续保留一条零散的 preview 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeCropEditOverlay(...) / makeRenderItem(...)
// 功能说明: 修改后 renderer 统一消费 resolver 产出的 presentation，selection/crop/render item 使用同一份共享几何解释结果。
private let presentationResolver = CanvasImagePresentationResolver()

let presentation = presentationResolver.resolve(
    item: item,
    inlineEditState: inlineEditState,
    rotationPreviewState: rotationPreviewState
)

let worldQuad = presentation.isCropPreviewActive
    ? presentation.fullImageWorldQuad
    : presentation.visibleWorldQuad
let renderCenter = presentation.isCropPreviewActive
    ? presentation.fullImageCenter
    : presentation.visibleCenter
let renderSize = presentation.isCropPreviewActive
    ? presentation.fullImageSize
    : presentation.visibleSize
let contentsRect = presentation.isCropPreviewActive
    ? CanvasImageCropRect.fullImage.cgRect
    : presentation.effectiveCropRectNormalized.cgRect
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRotateAffordance(for:camera:screenQuad:)
// 功能说明: 修改后旋转引导线起点仍基于 screenQuad，但中心点改为读取共享 presentation 的 visibleCenter。
private func makeRotateAffordance(
    for presentation: CanvasImagePresentation,
    camera: CanvasCamera,
    screenQuad: CanvasQuad
) -> CanvasEditRotateOverlayPayload {
    let screenCenter = camera.worldToViewport(presentation.visibleCenter)
    let guideScreenStart = screenQuad.topMidpoint
    // ...
}
```

## 结果与影响

- 本次修改完成了 minimap `Phase 1` 的核心前置工作：把“当前图片应该如何展示”的几何解释从主 renderer 内部抽离出来。
- 当前主画板行为保持原有语义：
  - crop 编辑时仍然是“完整图片 + crop overlay”
  - 非 crop 编辑时仍然显示可见区域
  - rotate preview 仍然会实时覆盖到渲染结果
- 后续 minimap 可以直接复用 `CanvasImagePresentationResolver`，从 `presentation.visibleWorldQuad` 读取“裁切后且已带旋转”的灰色占位几何，而不需要再重复发明一套 preview 解释逻辑。

## 校验情况

- `ReadLints` 已检查本次新增/修改文件，无新增诊断。
- 已执行 `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift`，通过。
- 未执行完整 `xcodebuild` 工程构建；当前环境的 `xcode-select` 指向 `CommandLineTools`，不是完整 Xcode 开发目录。
