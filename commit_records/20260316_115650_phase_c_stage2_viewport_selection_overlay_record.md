# 20260316_115650_phase_c_stage2_viewport_selection_overlay_record

## 记录范围

- 记录内容：
  1. 将选中态的可视反馈从 `CanvasImageLayer` 迁移到 `viewport` 的 `overlayLayer`。
  2. 让 iOS / macOS 两端直接消费 `snapshot.selectionOverlay`，绘制选中框与四角小方块 handle。
  3. 清理 `CanvasRenderItem.isSelected` 与 `CanvasImageLayer` 中旧的图片层选中边框逻辑。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：原始 gif diff、handle 命中测试、拖拽缩放状态机。

## 修改一：移除图片层对选中边框的直接依赖

### 修改前

- `CanvasRenderItem` 还携带 `isSelected`，把“当前是否被选中”直接下发给图片层。
- `CanvasRenderer.makeSnapshot(...)` 在构建 `CanvasRenderItem` 时，会把 `interactionState.selectedItemID == item.id` 计算结果写进 item。
- `CanvasImageLayer.update(with:contentsScale:)` 则根据 `item.isSelected` 直接在图片 layer 上画蓝色边框。
- 这样选中态的表现与图片内容层耦合在一起，不利于后续在 `overlayLayer` 上统一绘制选中框与 handle。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderItem
// 功能说明: 修改前 CanvasRenderItem 仍携带 isSelected，图片层需要直接感知选中状态。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
    let isSelected: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:)
// 功能说明: 修改前 renderer 在组装 renderItems 时，会把当前选中状态直接写入 CanvasRenderItem。
let renderItems = visibleItems.map { item in
    CanvasRenderItem(
        id: item.id,
        screenFrame: camera.worldToViewport(item.worldFrame),
        cgImage: item.cgImage,
        zIndex: item.zIndex,
        isSelected: interactionState.selectedItemID == item.id
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改前图片 layer 自己根据 item.isSelected 决定是否绘制蓝色边框。
func update(with item: CanvasRenderItem, contentsScale: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // ... 省略 frame / image / zPosition / contentsScale 更新 ...

    if lastAppliedIsSelected != item.isSelected {
        borderWidth = item.isSelected ? Self.selectionBorderWidth : 0
        borderColor = item.isSelected ? Self.selectionBorderColor : nil
        lastAppliedIsSelected = item.isSelected
    }

    CATransaction.commit()
}

private func configureLayer() {
    contentsGravity = .resize
    masksToBounds = true
    borderWidth = 0
    borderColor = nil
}
```

### 修改后

- `CanvasRenderItem` 去掉了 `isSelected`，回到“图片内容 + 屏幕几何 + 层级”的纯渲染载荷。
- `CanvasRenderer.makeSnapshot(...)` 不再向图片层传递选中态，选中框与 handle 的几何统一由 `selectionOverlay` 提供。
- `CanvasImageLayer` 也同步删掉了选中边框相关常量、缓存字段和绘制逻辑，图片层只负责图片本身。
- 这样选中态的视觉表现就完全转移到了 `viewport overlayLayer`，为后续 handle 命中测试留出了干净入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderItem
// 功能说明: 修改后 CanvasRenderItem 不再承担选中态表达，图片 item 只描述内容、几何和层级。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:)
// 功能说明: 修改后 renderer 只构建纯渲染 item；选中框与 handle 改走 selectionOverlay 这条输出链路。
let renderItems = visibleItems.map { item in
    CanvasRenderItem(
        id: item.id,
        screenFrame: camera.worldToViewport(item.worldFrame),
        cgImage: item.cgImage,
        zIndex: item.zIndex
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改后图片 layer 只更新 frame、图片内容、zPosition 和 contentsScale，不再自己绘制选中边框。
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

    if lastAppliedZIndex != item.zIndex {
        zPosition = item.zIndex
        lastAppliedZIndex = item.zIndex
    }

    if lastAppliedContentsScale != contentsScale {
        self.contentsScale = contentsScale
        lastAppliedContentsScale = contentsScale
    }

    CATransaction.commit()
}

private func configureLayer() {
    contentsGravity = .resize
    masksToBounds = true
}
```

## 修改二：在 iOS viewport 的 overlayLayer 中绘制选中框与四角 handle

### 修改前

- `iOSCanvasViewportView` 的 `overlayLayer` 里只有 `boardHighlightLayer`，并没有专门的选中框或 handle layer。
- `apply(_:)` 和 `didMoveToWindow()` 只刷新图片层与画板高亮，不会刷新选中态 overlay。
- 这意味着即便第一阶段已经有了 `selectionOverlay` 几何，iOS 端也没有真正消费它来绘制选中框与四角小方块。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性定义 / apply(_:) / setupLayers() / refreshBoardHighlight()
// 功能说明: 修改前 iOS 的 overlayLayer 只负责 board highlight，不负责选中框与四角 handle。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
    }
}

private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    addGestureRecognizer(pinchGestureRecognizer)

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.isHidden = true
        return
    }

    boardHighlightLayer.path = CGPath(rect: boardOverlay.screenRect, transform: nil)
    boardHighlightLayer.isHidden = false
    boardHighlightLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
}
```

### 修改后

- iOS 端新增 `selectionOutlineLayer` 和四个 `selectionHandleLayers`，并通过 `selectionStrokeColor / selectionHandleFillColor / selectionHandleSize` 定义选中态视觉参数。
- `setupLayers()` 中把 `selectionOutlineLayer` 和 handle layers 挂到 `overlayLayer`，位置自然落在图片层之上。
- `apply(_:)` 与 `didMoveToWindow()` 新增 `refreshSelectionOverlay()`，在刷新图片层和画板高亮之后同步刷新选中框与四角方块。
- `refreshSelectionOverlay()` 直接消费 `snapshot.selectionOverlay` 的 `screenFrame` 与 `handles`，当没有选中项时通过 `hideSelectionOverlay()` 统一清空 outline 和 handles。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性定义 / apply(_:) / setupLayers()
// 功能说明: 修改后 iOS 在 overlayLayer 中新增选中框与四角 handle 的专用 layer，并在 apply 时统一刷新。
private static let selectionStrokeColor = CGColor(
    red: 0,
    green: 122.0 / 255.0,
    blue: 1,
    alpha: 1
)
private static let selectionHandleFillColor = CGColor(gray: 1, alpha: 1)
private static let selectionOutlineLineWidth: CGFloat = 2
private static let selectionHandleLineWidth: CGFloat = 2
private static let selectionHandleSize: CGFloat = 12

private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
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
    addGestureRecognizer(pinchGestureRecognizer)

    configureBoardHighlightLayer()
    configureSelectionOutlineLayer()
    configureSelectionHandleLayers()
    updateBackgroundAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: configureSelectionOutlineLayer() / configureSelectionHandleLayers() / refreshSelectionOverlay() / hideSelectionOverlay()
// 功能说明: 修改后 iOS 直接消费 snapshot.selectionOverlay，在 overlayLayer 中画选中框和四角 handle，并在无选中项时统一隐藏。
private func configureSelectionOutlineLayer() {
    selectionOutlineLayer.fillColor = nil
    selectionOutlineLayer.strokeColor = Self.selectionStrokeColor
    selectionOutlineLayer.lineWidth = Self.selectionOutlineLineWidth
    selectionOutlineLayer.isHidden = true
}

private func configureSelectionHandleLayers() {
    for role in CanvasSelectionHandleRole.allCases {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = Self.selectionHandleFillColor
        handleLayer.strokeColor = Self.selectionStrokeColor
        handleLayer.lineWidth = Self.selectionHandleLineWidth
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        selectionHandleLayers[role] = handleLayer
    }
}

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    selectionOutlineLayer.path = CGPath(
        rect: CGRect(origin: .zero, size: selectionFrame.size),
        transform: nil
    )
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = selectionOverlay.handles.first(where: { $0.role == role })
        else {
            selectionHandleLayers[role]?.path = nil
            selectionHandleLayers[role]?.frame = .zero
            selectionHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.selectionHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}

private func hideSelectionOverlay() {
    selectionOutlineLayer.path = nil
    selectionOutlineLayer.frame = .zero
    selectionOutlineLayer.isHidden = true

    for handleLayer in selectionHandleLayers.values {
        handleLayer.path = nil
        handleLayer.frame = .zero
        handleLayer.isHidden = true
    }
}
```

## 修改三：在 macOS viewport 的 overlayLayer 中同步接管选中态绘制

### 修改前

- `macOSCanvasViewportView` 的 `overlayLayer` 也只有 `boardHighlightLayer`，并没有选中框与四角 handle 的专用 layer。
- 选中态仍依赖图片层边框，因此 macOS 端同样无法直接消费第一阶段产出的 `selectionOverlay`。
- 这会让后续 handle 命中测试和选中态绘制来源分裂，不利于阶段三继续扩展。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 属性定义 / apply(_:) / setupLayers() / refreshBoardHighlight()
// 功能说明: 修改前 macOS 的 overlayLayer 只承载 board highlight，没有选中框与四角 handle。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
    }
}

private func setupLayers() {
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.frame = .zero
        boardHighlightLayer.isHidden = true
        return
    }

    let boardFrame = boardOverlay.screenRect.standardized
    boardHighlightLayer.frame = boardFrame
    boardHighlightLayer.path = CGPath(
        rect: CGRect(origin: .zero, size: boardFrame.size),
        transform: nil
    )
    boardHighlightLayer.isHidden = false
    boardHighlightLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
}
```

### 修改后

- macOS 端同样新增 `selectionOutlineLayer` 与四个 handle layers，并把它们放到 `overlayLayer` 中。
- `apply(_:)` 与 `viewDidMoveToWindow()` 现在都会调用 `refreshSelectionOverlay()`，确保窗口挂载和每次 snapshot 刷新时选中态 overlay 都同步更新。
- `refreshSelectionOverlay()` 直接消费 `snapshot.selectionOverlay`，用 `screenFrame` 画 outline，用 `handles` 画四角小方块，并通过 `currentContentsScale` 统一设置清晰度。
- iOS / macOS 在数据源上保持一致，但 handle 视觉尺寸仍留在各自 viewport 中，macOS 这里使用 `10pt`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 属性定义 / apply(_:) / setupLayers()
// 功能说明: 修改后 macOS 在 overlayLayer 中新增选中框与四角 handle，并在 apply 时统一刷新。
private static let selectionStrokeColor = CGColor(
    red: 0,
    green: 122.0 / 255.0,
    blue: 1,
    alpha: 1
)
private static let selectionHandleFillColor = CGColor(gray: 1, alpha: 1)
private static let selectionOutlineLineWidth: CGFloat = 2
private static let selectionHandleLineWidth: CGFloat = 2
private static let selectionHandleSize: CGFloat = 10

private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
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
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    overlayLayer.addSublayer(selectionOutlineLayer)

    configureBoardHighlightLayer()
    configureSelectionOutlineLayer()
    configureSelectionHandleLayers()
    updateBackgroundAppearance()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: configureSelectionOutlineLayer() / configureSelectionHandleLayers() / refreshSelectionOverlay() / hideSelectionOverlay()
// 功能说明: 修改后 macOS 直接消费 snapshot.selectionOverlay，在 overlayLayer 中绘制选中框和四角小方块，并在无选中项时统一隐藏。
private func configureSelectionOutlineLayer() {
    selectionOutlineLayer.fillColor = nil
    selectionOutlineLayer.strokeColor = Self.selectionStrokeColor
    selectionOutlineLayer.lineWidth = Self.selectionOutlineLineWidth
    selectionOutlineLayer.isHidden = true
}

private func configureSelectionHandleLayers() {
    for role in CanvasSelectionHandleRole.allCases {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = Self.selectionHandleFillColor
        handleLayer.strokeColor = Self.selectionStrokeColor
        handleLayer.lineWidth = Self.selectionHandleLineWidth
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        selectionHandleLayers[role] = handleLayer
    }
}

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    let selectionFrame = selectionOverlay.screenFrame.standardized
    selectionOutlineLayer.frame = selectionFrame
    selectionOutlineLayer.path = CGPath(
        rect: CGRect(origin: .zero, size: selectionFrame.size),
        transform: nil
    )
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale

    for role in CanvasSelectionHandleRole.allCases {
        guard
            let handleLayer = selectionHandleLayers[role],
            let handle = selectionOverlay.handles.first(where: { $0.role == role })
        else {
            selectionHandleLayers[role]?.path = nil
            selectionHandleLayers[role]?.frame = .zero
            selectionHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.selectionHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}

private func hideSelectionOverlay() {
    selectionOutlineLayer.path = nil
    selectionOutlineLayer.frame = .zero
    selectionOutlineLayer.isHidden = true

    for handleLayer in selectionHandleLayers.values {
        handleLayer.path = nil
        handleLayer.frame = .zero
        handleLayer.isHidden = true
    }
}
```

## 结果

- 选中态的视觉表现已经从图片层迁移到 `viewport overlayLayer`，为后续阶段三的 handle 命中测试和缩放状态机打好了基础。
- iOS / macOS 两端现在都直接消费 `snapshot.selectionOverlay` 来绘制 outline 与四角 handle，但平台视觉参数仍保留在各自 viewport 中。
- 这一步只完成了绘制层迁移，尚未实现 handle 的点击命中、拖拽缩放与相关交互日志。
