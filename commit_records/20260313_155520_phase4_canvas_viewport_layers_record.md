# 20260313_155520_phase4_canvas_viewport_layers_record

## 记录范围

- 记录内容：阶段 4 的平台视口层与共享图片 layer 搭建。
- 目标：新增 `CanvasImageLayer`、`iOSCanvasViewportView`、`macOSCanvasViewportView`，并把空的 viewport 真正挂入画板宿主控制器。
- 本次未包含：测试图片数据、自定义平移缩放输入、真实图片显示链路联调。

## 变更 1：新增共享图片 layer `CanvasImageLayer`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数/类型: CanvasImageLayer.init(itemID:) / update(with:contentsScale:)
// 功能说明: 修改前文件不存在，平台层还没有统一的单图片 layer 封装来承接 CanvasRenderItem。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数/类型: CanvasImageLayer.init(itemID:) / update(with:contentsScale:)
// 功能说明: 为单张图片建立统一的 CALayer 封装，负责持有 itemID，并根据 CanvasRenderItem 刷新 frame、contents 和层级。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        super.init()
        contentsGravity = .resize
        masksToBounds = true
    }

    func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
        frame = item.screenFrame
        contents = item.cgImage
        zPosition = item.zIndex
        self.contentsScale = contentsScale
    }
}
```

## 变更 2：新增 iOS 固定视口层 `iOSCanvasViewportView`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数/类型: apply(_:) / refreshImageLayers() / imageLayer(for:)
// 功能说明: 修改前文件不存在，iOS 端还没有真正承接 CanvasRenderSnapshot 的固定视口视图。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数/类型: apply(_:) / refreshImageLayers() / imageLayer(for:)
// 功能说明: 新增 iOS 固定视口容器，维护 background/items/overlay 三层，并按 itemID 对 CanvasImageLayer 做增删改。
final class iOSCanvasViewportView: UIView {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var snapshot: CanvasRenderSnapshot = .empty

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        updateLayerFrames()
        refreshImageLayers()
    }

    private func refreshImageLayers() {
        let incomingIDs = Set(snapshot.items.map(\\.id))
        let existingIDs = Set(imageLayers.keys)

        for removedID in existingIDs.subtracting(incomingIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        let contentsScale = window?.screen.scale ?? UIScreen.main.scale
        for item in snapshot.items {
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(with: item, contentsScale: contentsScale)
        }
    }
}
```

## 变更 3：新增 macOS 固定视口层 `macOSCanvasViewportView`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数/类型: isFlipped / apply(_:) / refreshImageLayers() / imageLayer(for:)
// 功能说明: 修改前文件不存在，macOS 端还没有真正承接 CanvasRenderSnapshot 的固定视口视图。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数/类型: isFlipped / apply(_:) / refreshImageLayers() / imageLayer(for:)
// 功能说明: 新增 macOS 固定视口容器，显式翻转坐标系，并维护 background/items/overlay 三层和图片 layer diff。
final class macOSCanvasViewportView: NSView {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var snapshot: CanvasRenderSnapshot = .empty

    override var isFlipped: Bool {
        true
    }

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        updateLayerFrames()
        refreshImageLayers()
    }

    private func refreshImageLayers() {
        let incomingIDs = Set(snapshot.items.map(\\.id))
        let existingIDs = Set(imageLayers.keys)

        for removedID in existingIDs.subtracting(incomingIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in snapshot.items {
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(with: item, contentsScale: contentsScale)
        }
    }
}
```

## 变更 4：iOS 画板宿主接入空的 viewport

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型: viewDidLoad() / installCanvasContentView(_:)
// 功能说明: 修改前的 iOSViewController 虽然已经是宿主容器，但还没有真正挂入固定视口视图。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型: viewDidLoad() / setupCanvasViewport()
// 功能说明: 在宿主控制器里创建并挂入 iOSCanvasViewportView，让画板页正式拥有固定视口层。
private let canvasViewportView = iOSCanvasViewportView()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupCanvasViewport()
}

private func setupCanvasViewport() {
    installCanvasContentView(canvasViewportView)
    canvasViewportView.apply(.empty)
}
```

## 变更 5：macOS 画板宿主接入空的 viewport

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型: viewDidLoad() / installCanvasContentView(_:)
// 功能说明: 修改前的 macOSViewController 虽然已经是宿主容器，但还没有真正挂入固定视口视图。
override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型: viewDidLoad() / setupCanvasViewport()
// 功能说明: 在宿主控制器里创建并挂入 macOSCanvasViewportView，让画板页正式拥有固定视口层。
private let canvasViewportView = macOSCanvasViewportView()

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    setupCanvasViewport()
}

private func setupCanvasViewport() {
    installCanvasContentView(canvasViewportView)
    canvasViewportView.apply(.empty)
}
```

## 当前阶段结果

- 画板页现在已经不只是“宿主控制器 + 空容器”，而是已经挂上了真正的固定视口层。
- `iOS` 和 `macOS` 两端都具备三层 layer 结构：
  - `backgroundLayer`
  - `itemsLayer`
  - `overlayLayer`
- `CanvasRenderSnapshot` 已经可以被平台视口消费，只是当前还没有喂入真实图片数据。
- 当前 UI 上看到的是一个真实的空白 viewport，而不是简单的空白控制器背景。
