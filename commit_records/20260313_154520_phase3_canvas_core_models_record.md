# 20260313_154520_phase3_canvas_core_models_record

## 记录范围

- 记录内容：阶段 3 的共享 Canvas 核心模型搭建。
- 目标：建立平台无关的图片节点、场景、相机、渲染快照和渲染器，为后续 `CanvasViewportView` 和 `CanvasImageLayer` 提供统一接口。
- 本次未包含：平台视口视图、图片 layer、测试图片接线、自定义平移缩放手势。

## 变更 1：新增图片节点模型 `CanvasImageItem`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数/类型: CanvasImageItem.init(...) / worldFrame
// 功能说明: 修改前文件不存在，共享层里没有统一的图片节点模型来描述图片内容、世界坐标和层级。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasImageItem.swift
// 函数/类型: CanvasImageItem.init(...) / worldFrame
// 功能说明: 定义平台无关的图片节点，统一管理图片内容、世界坐标中心点、尺寸、层级以及世界坐标包围盒。
typealias CanvasImageItemID = UUID

struct CanvasImageItem {
    let id: CanvasImageItemID
    let cgImage: CGImage
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat

    init(
        id: CanvasImageItemID = UUID(),
        cgImage: CGImage,
        center: CGPoint,
        size: CGSize,
        zIndex: CGFloat = 0
    ) {
        self.id = id
        self.cgImage = cgImage
        self.center = center
        self.size = size
        self.zIndex = zIndex
    }

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

## 变更 2：新增运行时画板场景 `CanvasScene`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数/类型: setItems(_:) / append(_:) / upsert(_:) / visibleItems(in:)
// 功能说明: 修改前文件不存在，共享层里没有统一的内存态画板容器来管理图片集合和可见性筛选。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数/类型: setItems(_:) / append(_:) / upsert(_:) / visibleItems(in:)
// 功能说明: 统一管理当前画板中的图片节点，并按 zIndex 返回有序结果，为后续渲染器提供稳定输入。
final class CanvasScene {
    private(set) var items: [CanvasImageItem]

    init(items: [CanvasImageItem] = []) {
        self.items = items
    }

    func setItems(_ items: [CanvasImageItem]) {
        self.items = items
    }

    func append(_ item: CanvasImageItem) {
        items.append(item)
    }

    func upsert(_ item: CanvasImageItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
        orderedItems(from: items.filter { $0.worldFrame.intersects(worldRect) })
    }
}
```

## 变更 3：新增相机模型 `CanvasCamera`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift
// 函数/类型: visibleWorldRect / worldToViewport(_:) / viewportToWorld(_:) / pan(by:) / zoom(to:around:)
// 功能说明: 修改前文件不存在，工程里没有固定视口 + 自定义相机的统一坐标变换模型。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasCamera.swift
// 函数/类型: visibleWorldRect / worldToViewport(_:) / viewportToWorld(_:) / pan(by:) / zoom(to:around:)
// 功能说明: 统一管理画板中心点、缩放比例、视口尺寸，并提供世界坐标和屏幕坐标之间的转换与相机变换。
struct CanvasCamera {
    private static let minimumZoomScale: CGFloat = 0.1
    private static let maximumZoomScale: CGFloat = 8

    var center: CGPoint
    var zoomScale: CGFloat
    var viewportSize: CGSize

    var visibleWorldRect: CGRect {
        let visibleSize = CGSize(
            width: viewportSize.width / zoomScale,
            height: viewportSize.height / zoomScale
        )

        return CGRect(
            x: center.x - visibleSize.width / 2,
            y: center.y - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
    }

    func worldToViewport(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - center.x) * zoomScale + viewportSize.width / 2,
            y: (point.y - center.y) * zoomScale + viewportSize.height / 2
        )
    }

    mutating func pan(by deltaInViewport: CGPoint) {
        center.x -= deltaInViewport.x / zoomScale
        center.y -= deltaInViewport.y / zoomScale
    }

    mutating func zoom(to newZoomScale: CGFloat, around anchorInViewport: CGPoint) {
        let worldAnchorBeforeZoom = viewportToWorld(anchorInViewport)
        zoomScale = Self.clampedZoomScale(for: newZoomScale)
        let worldAnchorAfterZoom = viewportToWorld(anchorInViewport)
        center.x += worldAnchorBeforeZoom.x - worldAnchorAfterZoom.x
        center.y += worldAnchorBeforeZoom.y - worldAnchorAfterZoom.y
    }
}
```

## 变更 4：新增渲染输出 `CanvasRenderSnapshot`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数/类型: CanvasRenderItem / CanvasRenderSnapshot.empty
// 功能说明: 修改前文件不存在，平台层没有统一的渲染结果结构可以直接消费。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数/类型: CanvasRenderItem / CanvasRenderSnapshot.empty
// 功能说明: 定义平台无关的渲染结果，让后续平台视口层只消费 screenFrame、图片内容和层级，而不自己散算 frame。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let items: [CanvasRenderItem]

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        items: []
    )
}
```

## 变更 5：新增渲染器 `CanvasRenderer`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数/类型: makeSnapshot(scene:camera:)
// 功能说明: 修改前文件不存在，CanvasScene 和 CanvasCamera 之间没有统一的快照生成入口。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数/类型: makeSnapshot(scene:camera:)
// 功能说明: 根据当前可见世界区域筛选图片节点，并将世界坐标 frame 转成平台层可直接消费的 screenFrame。
struct CanvasRenderer {
    func makeSnapshot(
        scene: CanvasScene,
        camera: CanvasCamera
    ) -> CanvasRenderSnapshot {
        let visibleWorldRect = camera.visibleWorldRect
        let renderItems = scene.visibleItems(in: visibleWorldRect).map { item in
            CanvasRenderItem(
                id: item.id,
                screenFrame: camera.worldToViewport(item.worldFrame),
                cgImage: item.cgImage,
                zIndex: item.zIndex
            )
        }

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            items: renderItems
        )
    }
}
```

## 当前阶段结果

- 共享核心层已经具备 5 个关键类型：
  - `CanvasImageItem`
  - `CanvasScene`
  - `CanvasCamera`
  - `CanvasRenderSnapshot`
  - `CanvasRenderer`
- `iOS` 和 `macOS` 后续的视口层不需要再自己维护图片几何计算，统一围绕 `CanvasRenderer` 输出工作。
- 当前还没有新增可见 UI，因为这一阶段只是在搭建共享数据结构和坐标变换模型。
