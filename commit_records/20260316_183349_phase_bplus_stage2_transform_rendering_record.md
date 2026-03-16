# 20260316_183349_phase_bplus_stage2_transform_rendering_record

## 记录范围

- 记录内容：
  1. 为 shared core 新增旋转感知的四边形几何基础。
  2. 让 `CanvasImageItem` 与 `CanvasScene` 从“纯轴对齐矩形”扩展到“quad + AABB + local/world 几何转换”。
  3. 让 `CanvasRenderSnapshot` / `CanvasRenderer` / `CanvasImageLayer` 开始承载裁切采样区域与旋转后的渲染数据。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
- 本记录不包含：
  - 裁切 overlay / rotate overlay
  - controller 的 crop / rotate 输入状态机
  - undo / redo 历史控制器
  - 原始 gif diff

## 修改一：新增共享四边形几何类型，作为旋转感知的基础

### 修改前

- 项目里没有专门表达“旋转后四个角点”的共享几何类型。
- `renderer`、`scene`、`viewport` 若想支持旋转，只能继续围绕 `CGRect` 做推导，这会把后续 selection、hit-test、culling 都锁死在轴对齐矩形上。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前项目中没有共享的 quad 几何类型，旋转后的四角点和 AABB 没有统一表达。
// before: file did not exist
```

### 修改后

- 新增 `CanvasQuad`，统一表达一个四边形的四个角点。
- `CanvasQuad` 提供 `boundingRect` 与 `map(...)`，后续 `scene`、`camera`、`renderer` 都可以复用这套基础。
- 阶段二只先落地几何载体，不引入额外平台语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名/类型名: CanvasQuad
// 功能说明: 修改后新增共享四边形几何类型，为旋转后的 item/world/screen 几何提供统一表达。
struct CanvasQuad: Equatable {
    let topLeading: CGPoint
    let topTrailing: CGPoint
    let bottomLeading: CGPoint
    let bottomTrailing: CGPoint

    init(rect: CGRect) {
        let standardizedRect = rect.standardized
        self.init(
            topLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.minY),
            topTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.minY),
            bottomLeading: CGPoint(x: standardizedRect.minX, y: standardizedRect.maxY),
            bottomTrailing: CGPoint(x: standardizedRect.maxX, y: standardizedRect.maxY)
        )
    }

    var boundingRect: CGRect {
        let xs = points.map(\\.x)
        let ys = points.map(\\.y)
        // ... 省略未改动代码 ...
    }

    func map(_ transform: (CGPoint) -> CGPoint) -> CanvasQuad {
        CanvasQuad(
            topLeading: transform(topLeading),
            topTrailing: transform(topTrailing),
            bottomLeading: transform(bottomLeading),
            bottomTrailing: transform(bottomTrailing)
        )
    }
}
```

## 修改二：让相机与图片实例具备旋转感知几何能力

### 修改前

- `CanvasCamera` 只有 `worldToViewport(_ point:)` 和 `worldToViewport(_ rect:)`。
- `CanvasImageItem` 只有轴对齐的 `worldFrame`，没有 local frame、world quad、world bounds 或 local/world 坐标变换工具。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift
// 函数名: worldToViewport(_ rect:)
// 功能说明: 修改前相机只支持 point/rect 转换，还没有 quad 级别的共享几何变换。
func worldToViewport(_ rect: CGRect) -> CGRect {
    let standardizedRect = rect.standardized
    let origin = worldToViewport(standardizedRect.origin)

    return CGRect(
        x: origin.x,
        y: origin.y,
        width: standardizedRect.width * zoomScale,
        height: standardizedRect.height * zoomScale
    )
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名/类型名: CanvasImageItem
// 功能说明: 修改前图片实例只有 worldFrame，无法表达旋转后的 quad、bounds 或 local/world 坐标互转。
struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var cropRectNormalized: CanvasImageCropRect
    var rotationRadians: CGFloat

    var worldFrame: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

### 修改后

- `CanvasCamera` 增加 `worldToViewport(_ quad:)`，相机可以直接把共享四边形几何转换到屏幕坐标。
- `CanvasImageItem` 新增：
  - `localFrame`
  - `localQuad`
  - `worldQuad`
  - `worldBounds`
  - `imageContentsRect`
  - `contains(worldPoint:)`
  - `worldPoint(fromLocal:)`
  - `localPoint(fromWorld:)`
- 同时保留 `worldFrame`，并用注释明确它当前仍是未旋转的显示框，方便分阶段过渡。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift
// 函数名: worldToViewport(_ quad:)
// 功能说明: 修改后相机可以直接把四边形几何映射到 viewport，为旋转后的 screen quad 提供共享转换入口。
func worldToViewport(_ quad: CanvasQuad) -> CanvasQuad {
    quad.map(worldToViewport)
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数名: localFrame / localQuad / worldQuad / worldBounds / contains(worldPoint:) / worldPoint(fromLocal:) / localPoint(fromWorld:)
// 功能说明: 修改后图片实例可以表达本地矩形、旋转后的 world quad、AABB，以及 local/world 坐标互转。
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

// `worldFrame` intentionally remains the unrotated visible frame so the
// existing axis-aligned move/resize flows can keep compiling during the
// staged rotation rollout. Use `worldBounds` for transformed culling/hit-test.
var worldFrame: CGRect { /* ... 省略未改动代码 ... */ }

var worldBounds: CGRect {
    worldQuad.boundingRect
}

var imageContentsRect: CGRect {
    cropRectNormalized.cgRect
}

func contains(worldPoint: CGPoint) -> Bool {
    localFrame.contains(localPoint(fromWorld: worldPoint))
}
```

## 修改三：让 scene 从轴对齐命中/裁剪升级到变换感知基础

### 修改前

- `CanvasScene.topmostItem(containing:)` 直接依赖 `item.worldFrame.contains(worldPoint)`。
- `visibleItems(in:)` 也只依赖 `item.worldFrame.intersects(worldRect)`。
- scene 无法向上游提供 item 的 `worldQuad` 或 `worldBounds`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: topmostItem(containing:) / visibleItems(in:)
// 功能说明: 修改前 scene 的命中和可见性判断都只依赖未旋转的 worldFrame。
func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
    orderedItems().reversed().first(where: { $0.worldFrame.contains(worldPoint) })
}

func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
    orderedItems(from: items.filter { $0.worldFrame.intersects(worldRect) })
}
```

### 修改后

- `topmostItem(containing:)` 改成调用 `item.contains(worldPoint:)`，切到 local/world 变换感知的命中入口。
- `visibleItems(in:)` 改成基于 `item.worldBounds` 做 culling。
- scene 新增 `itemWorldQuad(withID:)`、`itemWorldBounds(withID:)` 与 `topmostItemID(containing:)`，方便后续 renderer / controller 直接读共享几何。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: itemWorldQuad(withID:) / itemWorldBounds(withID:) / topmostItem(containing:) / topmostItemID(containing:) / visibleItems(in:)
// 功能说明: 修改后 scene 改为基于旋转后的 quad/AABB 做命中和可见性判断，并向上层暴露共享几何访问入口。
func itemWorldQuad(withID id: CanvasImageItemID) -> CanvasQuad? {
    item(withID: id)?.worldQuad
}

func itemWorldBounds(withID id: CanvasImageItemID) -> CGRect? {
    item(withID: id)?.worldBounds
}

func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
    orderedItems().reversed().first(where: { $0.contains(worldPoint: worldPoint) })
}

func topmostItemID(containing worldPoint: CGPoint) -> CanvasImageItemID? {
    topmostItem(containing: worldPoint)?.id
}

func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
    let standardizedWorldRect = worldRect.standardized
    return orderedItems(from: items.filter { item in
        item.worldBounds.intersects(standardizedWorldRect)
    })
}
```

## 修改四：扩展 render snapshot 与 renderer，开始产出 quad / contentsRect / rotation

### 修改前

- `CanvasRenderItem` 只有 `screenFrame + cgImage + zIndex`。
- `CanvasSelectionRenderOverlay` 只有 `worldFrame + screenFrame + handles`。
- `CanvasRenderer` 仍然直接从 `item.worldFrame` 生成 `screenFrame`，selection handles 也从矩形四角推导。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRenderItem / CanvasSelectionRenderOverlay
// 功能说明: 修改前 snapshot 仍以 screenFrame / worldFrame 作为主要几何载体，还没有 quad、contentsRect 和 rotation 数据。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let screenFrame: CGRect
    let handles: [CanvasSelectionHandleGeometry]
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeSelectionOverlay(...)
// 功能说明: 修改前 renderer 仍从 item.worldFrame 直接生成 screenFrame，selection handle 也按矩形四角生成。
let renderItems = visibleItems.map { item in
    CanvasRenderItem(
        id: item.id,
        screenFrame: camera.worldToViewport(item.worldFrame),
        cgImage: item.cgImage,
        zIndex: item.zIndex
    )
}

let worldFrame = selectedItem.worldFrame.standardized
let screenFrame = camera.worldToViewport(worldFrame).standardized
```

### 修改后

- `CanvasRenderItem` 新增：
  - `screenQuad`
  - `screenCenter`
  - `screenBoundsSize`
  - `contentsRect`
  - `rotationRadians`
- `CanvasSelectionRenderOverlay` 新增 `worldQuad` 与 `screenQuad`，同时保留 AABB 形式的 `worldFrame/screenFrame` 作为过渡兼容字段。
- `CanvasRenderer` 新增 `makeRenderItem(...)`，统一从 item 的 `worldQuad` 和 `imageContentsRect` 产出屏幕级渲染数据。
- selection handles 改为直接取 `screenQuad` 的四个角点，而不是矩形四角。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRenderItem / CanvasSelectionRenderOverlay
// 功能说明: 修改后 snapshot 同时承载 AABB、quad、采样区域和旋转角度，为后续裁切/旋转渲染和命中提供共享语义。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let contentsRect: CGRect
    let rotationRadians: CGFloat
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasSelectionRenderOverlay {
    let itemID: CanvasImageItemID
    let worldFrame: CGRect
    let worldQuad: CanvasQuad
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let handles: [CanvasSelectionHandleGeometry]
}

// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRenderItem(for:camera:) / makeSelectionOverlay(scene:camera:interactionState:) / makeSelectionHandles(for:)
// 功能说明: 修改后 renderer 统一从 item.worldQuad / imageContentsRect 生成渲染数据，并用 screenQuad 四角生成 selection handles。
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

private func makeSelectionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState
) -> CanvasSelectionRenderOverlay? {
    // ... 省略未改动代码 ...
    let worldQuad = selectedItem.worldQuad
    let worldFrame = worldQuad.boundingRect.standardized
    let screenQuad = camera.worldToViewport(worldQuad)
    let screenFrame = screenQuad.boundingRect.standardized

    return CanvasSelectionRenderOverlay(
        itemID: selectedItemID,
        worldFrame: worldFrame,
        worldQuad: worldQuad,
        screenFrame: screenFrame,
        screenQuad: screenQuad,
        handles: makeSelectionHandles(for: screenQuad)
    )
}
```

## 修改五：让图片 layer 使用 contentsRect 与 layer transform

### 修改前

- `CanvasImageLayer` 只缓存并比较 `frame`、`cgImage`、`zIndex`、`contentsScale`。
- 图片 layer 通过 `frame = item.screenFrame` 直接铺满一个轴对齐矩形，无法表达非破坏性裁切采样区域和旋转。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改前图片 layer 只按 screenFrame 放置整张图，没有 contentsRect 和 rotation transform。
final class CanvasImageLayer: CALayer {
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedFrame != item.screenFrame {
            frame = item.screenFrame
            lastAppliedFrame = item.screenFrame
        }

        if !isDisplayingImage(item.cgImage) {
            contents = item.cgImage
            lastAppliedImage = item.cgImage
        }
        // ... 省略未改动代码 ...
    }

    private func configureLayer() {
        contentsGravity = .resize
        masksToBounds = true
    }
}
```

### 修改后

- `CanvasImageLayer` 改为缓存并比较：
  - `position`
  - `boundsSize`
  - `contentsRect`
  - `rotationRadians`
- `update(with:contentsScale:)` 改成：
  - 用 `bounds` + `position` 摆放图片
  - 用 `contentsRect` 表达非破坏性裁切
  - 用 `CATransform3DMakeRotation(...)` 表达旋转
- `configureLayer()` 新增 `anchorPoint = (0.5, 0.5)`，以中心为旋转枢轴。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改后图片 layer 使用 bounds/position + contentsRect + transform 来表达裁切与旋转，原图内容本身不变。
final class CanvasImageLayer: CALayer {
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedContentsRect: CGRect
    private var lastAppliedRotationRadians: CGFloat

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if lastAppliedContentsRect != item.contentsRect {
            contentsRect = item.contentsRect
            lastAppliedContentsRect = item.contentsRect
        }

        if lastAppliedRotationRadians != item.rotationRadians {
            transform = CATransform3DMakeRotation(item.rotationRadians, 0, 0, 1)
            lastAppliedRotationRadians = item.rotationRadians
        }
        // ... 省略未改动代码 ...
    }

    private func configureLayer() {
        contentsGravity = .resize
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
    }
}
```

## 校验情况

- 已对以下文件执行 `ReadLints`：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
- lint 结果：`No linter errors found.`
- 已执行 iOS Simulator 构建校验：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath ".build/DerivedData-stage2-iOSSim" CODE_SIGNING_ALLOWED=NO build`
- 已执行 macOS 构建校验：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -derivedDataPath ".build/DerivedData-stage2-macOS" CODE_SIGNING_ALLOWED=NO build`
- 构建结果：
  - iOS Simulator：`BUILD SUCCEEDED`
  - macOS：`BUILD SUCCEEDED`
- 本次记录对应阶段二“变换感知的 scene / renderer / image layer 基础”，不包含阶段四/五的 inline crop / rotate 交互实现。
