# 20260317_214058_rotation_interaction_phase4_viewport_layer_tree_record

## 记录范围

- 记录内容：
  1. 在 iOS / macOS viewport 中新增独立的 `interactionOverlayLayer`。
  2. 在两端 viewport 中为旋转 HUD 接入 `ring / tick / pointer / textBackground / text` 子 layer。
  3. 把 interaction overlay 的刷新、隐藏与生命周期接入 `apply`、`layout`、`didMoveToWindow` / `viewDidMoveToWindow` 等入口。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - 刻度环、当前角度指针、角度数值文本的正式绘制逻辑
  - 原始 gif diff / git diff / git commit / git push

## 阶段结论

- 这一阶段完成的是“viewport 独立 layer 树与生命周期接入”。
- 修改完成后，`snapshot.interactionOverlay` 已经可以被 iOS / macOS viewport 独立消费。
- 当前还没有把路径和文本真正画出来，所以界面上暂时不会出现新的角度指示器，但渲染通道已经打通。

## 修改一：为 iOS viewport 新增独立 interactionOverlayLayer 与子 layer

### 修改前

- `iOSCanvasViewportView` 的 overlay 层次只有：
  - `boardHighlightLayer`
  - `selectionOutlineLayer`
  - `cropMaskLayer`
  - `cropOutlineLayer`
  - `rotateGuideLayer`
  - `rotateHandleLayer`
- 没有任何独立的 interaction overlay 容器，也没有旋转 HUD 专属 layer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性区 / setupLayers()
// 功能说明: 修改前 iOS viewport 只有 selection/crop/rotate 相关 layer，没有独立 interaction overlay layer 树。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
private let cropMaskLayer = CAShapeLayer()
private let cropOutlineLayer = CAShapeLayer()
private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    overlayLayer.addSublayer(selectionOutlineLayer)
    overlayLayer.addSublayer(cropMaskLayer)
    overlayLayer.addSublayer(cropOutlineLayer)
    overlayLayer.addSublayer(rotateGuideLayer)
    overlayLayer.addSublayer(rotateHandleLayer)
}
```

### 修改后

- 新增：
  - `interactionOverlayLayer`
  - `rotationRingLayer`
  - `rotationTickLayer`
  - `rotationPointerLayer`
  - `rotationTextBackgroundLayer`
  - `rotationTextLayer`
- `setupLayers()` 中把 interaction overlay 作为独立容器挂到 `overlayLayer` 下，再把 5 个子 layer 挂到 `interactionOverlayLayer` 下。
- 这样后续阶段 5 只需要填充“画什么”，不用再改 layer 结构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性区 / setupLayers()
// 功能说明: 修改后 iOS viewport 拥有独立 interaction overlay layer 树，为旋转 HUD 提供专属渲染容器。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private let interactionOverlayLayer = CALayer()
private let rotationRingLayer = CAShapeLayer()
private let rotationTickLayer = CAShapeLayer()
private let rotationPointerLayer = CAShapeLayer()
private let rotationTextBackgroundLayer = CAShapeLayer()
private let rotationTextLayer = CATextLayer()
private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
private let cropMaskLayer = CAShapeLayer()
private let cropOutlineLayer = CAShapeLayer()
private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    overlayLayer.addSublayer(selectionOutlineLayer)
    overlayLayer.addSublayer(interactionOverlayLayer)
    overlayLayer.addSublayer(cropMaskLayer)
    overlayLayer.addSublayer(cropOutlineLayer)
    overlayLayer.addSublayer(rotateGuideLayer)
    overlayLayer.addSublayer(rotateHandleLayer)
    interactionOverlayLayer.addSublayer(rotationRingLayer)
    interactionOverlayLayer.addSublayer(rotationTickLayer)
    interactionOverlayLayer.addSublayer(rotationPointerLayer)
    interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
    interactionOverlayLayer.addSublayer(rotationTextLayer)
}
```

## 修改二：为 iOS viewport 新增 interaction overlay 的配置与生命周期入口

### 修改前

- `iOSCanvasViewportView` 的生命周期只会刷新：
  - 图片层
  - board highlight
  - edit overlay
- 即使 snapshot 已经有了 `interactionOverlay`，iOS viewport 也完全不会消费。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / updateLayerFrames()
// 功能说明: 修改前 iOS viewport 的生命周期里没有 interaction overlay 的刷新和 frame 管理。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
}

private func updateLayerFrames() {
    if overlayLayer.frame != bounds {
        overlayLayer.frame = bounds
    }

    if selectionOutlineLayer.frame != bounds {
        selectionOutlineLayer.frame = bounds
    }
}
```

### 修改后

- 在生命周期里接入 `refreshInteractionOverlay()`。
- 在 `updateLayerFrames()` 中同步维护 `interactionOverlayLayer.frame`。
- 同时新增了 interaction overlay 各子 layer 的 `configure*` 方法，为后续阶段 5 画图做准备。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / updateLayerFrames() /
//        configureInteractionOverlayLayer() / configureRotation*Layer()
// 功能说明: 修改后 iOS viewport 生命周期已经能感知 interaction overlay，并为其维护 frame 与基础样式。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

private func updateLayerFrames() {
    if overlayLayer.frame != bounds {
        overlayLayer.frame = bounds
    }

    if selectionOutlineLayer.frame != bounds {
        selectionOutlineLayer.frame = bounds
    }

    // 关键补充: 独立 interaction overlay 也要跟随 viewport bounds 同步。
    if interactionOverlayLayer.frame != bounds {
        interactionOverlayLayer.frame = bounds
    }
}

private func configureInteractionOverlayLayer() {
    interactionOverlayLayer.isHidden = true
}

private func configureRotationRingLayer() {
    rotationRingLayer.fillColor = nil
    rotationRingLayer.strokeColor = Self.selectionStrokeColor
    rotationRingLayer.lineWidth = Self.selectionOutlineLineWidth
    rotationRingLayer.isHidden = true
}

private func configureRotationTickLayer() {
    rotationTickLayer.fillColor = nil
    rotationTickLayer.strokeColor = Self.selectionStrokeColor
    rotationTickLayer.lineWidth = Self.rotateGuideLineWidth
    rotationTickLayer.lineCap = .round
    rotationTickLayer.isHidden = true
}

private func configureRotationPointerLayer() {
    rotationPointerLayer.fillColor = nil
    rotationPointerLayer.strokeColor = Self.selectionStrokeColor
    rotationPointerLayer.lineWidth = Self.rotateGuideLineWidth
    rotationPointerLayer.lineCap = .round
    rotationPointerLayer.isHidden = true
}

private func configureRotationTextBackgroundLayer() {
    rotationTextBackgroundLayer.fillColor = Self.selectionHandleFillColor
    rotationTextBackgroundLayer.strokeColor = Self.selectionStrokeColor
    rotationTextBackgroundLayer.lineWidth = Self.selectionHandleLineWidth
    rotationTextBackgroundLayer.isHidden = true
}

private func configureRotationTextLayer() {
    rotationTextLayer.alignmentMode = .center
    rotationTextLayer.contentsScale = currentContentsScale
    rotationTextLayer.isWrapped = false
    rotationTextLayer.isHidden = true
    rotationTextLayer.truncationMode = .none
}
```

## 修改三：为 iOS viewport 新增 interaction overlay 的刷新与隐藏通道

### 修改前

- iOS viewport 只有 `refreshEditOverlay()` / `hideEditOverlay()`。
- 没有独立的 `refreshInteractionOverlay()` / `hideInteractionOverlay()`。
- 这会让 interaction overlay 的显示/隐藏继续耦合到 selection / crop 逻辑里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshEditOverlay() / hideEditOverlay()
// 功能说明: 修改前 viewport 只有 edit overlay 刷新/隐藏通道，没有独立 interaction overlay 生命周期。
private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideCropOverlay()
    case .crop:
        hideSelectionOverlay()
        refreshCropChrome(from: editOverlay)
    }
}

private func hideEditOverlay() {
    hideSelectionOverlay()
    hideCropOverlay()
}
```

### 修改后

- 新增：
  - `refreshInteractionOverlay()`
  - `refreshRotationInteractionOverlay(from:)`
  - `hideInteractionOverlay()`
- 当前阶段先把 layer 显隐、frame、contentsScale、基础占位状态接上，不提前完成实际绘制。
- 这让 interaction overlay 生命周期已经与 selection/crop overlay 解耦。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay() / refreshRotationInteractionOverlay(from:) / hideInteractionOverlay()
// 功能说明: 修改后 iOS viewport 拥有独立 interaction overlay 刷新/隐藏通道，后续阶段5只需填充真实绘制逻辑。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    }
}

private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    // 当前阶段只接生命周期，不正式绘制路径。
    rotationRingLayer.frame = bounds
    rotationRingLayer.path = nil
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = nil
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = nil
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = CGRect(origin: payload.textScreenAnchor, size: .zero)
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}

private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true

    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true

    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.isHidden = true

    rotationTextLayer.frame = .zero
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = true
}
```

## 修改四：macOS viewport 与 iOS 保持镜像的独立 interaction layer 树

### 修改前

- `macOSCanvasViewportView` 的结构与 iOS 同构，但同样没有独立 interaction overlay layer 树。
- 生命周期也只会刷新 `image / board / edit overlay`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 属性区 / setupLayers() / viewDidMoveToWindow() / apply(_:)
// 功能说明: 修改前 macOS viewport 和 iOS 一样，没有 interaction overlay 独立容器，也没有对应刷新入口。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private var selectionHandleLayers: [CanvasSelectionHandleRole: CAShapeLayer] = [:]
private let cropMaskLayer = CAShapeLayer()
private let cropOutlineLayer = CAShapeLayer()
private var cropHandleLayers: [CanvasCropHandleRole: CAShapeLayer] = [:]
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
    }
}
```

### 修改后

- macOS 也新增了与 iOS 同构的：
  - `interactionOverlayLayer`
  - `rotationRingLayer`
  - `rotationTickLayer`
  - `rotationPointerLayer`
  - `rotationTextBackgroundLayer`
  - `rotationTextLayer`
- 同时接入：
  - `refreshInteractionOverlay()`
  - `refreshRotationInteractionOverlay(from:)`
  - `hideInteractionOverlay()`
- 两端结构保持镜像，后续阶段 5 / 6 的维护成本会更低。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 属性区 / setupLayers() / viewDidMoveToWindow() / apply(_:) /
//        refreshInteractionOverlay() / refreshRotationInteractionOverlay(from:) / hideInteractionOverlay()
// 功能说明: 修改后 macOS viewport 与 iOS 保持镜像结构，独立接入 interaction overlay 的 layer 树与生命周期。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()
private let selectionOutlineLayer = CAShapeLayer()
private let interactionOverlayLayer = CALayer()
private let rotationRingLayer = CAShapeLayer()
private let rotationTickLayer = CAShapeLayer()
private let rotationPointerLayer = CAShapeLayer()
private let rotationTextBackgroundLayer = CAShapeLayer()
private let rotationTextLayer = CATextLayer()

override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    }
}

private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = nil
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = nil
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = nil
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = CGRect(origin: payload.textScreenAnchor, size: .zero)
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}

private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true

    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true

    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.isHidden = true

    rotationTextLayer.frame = .zero
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = true
}
```

## 本阶段完成后的代码行为

1. `snapshot.interactionOverlay` 已经可以被 iOS / macOS viewport 独立消费。
2. interaction overlay 已经拥有独立 layer 树，不再需要继续混入 selection/crop chrome。
3. 生命周期已经接通：窗口挂载、`apply(snapshot)`、frame 更新、刷新、隐藏都具备了 interaction overlay 的独立路径。
4. 当前还没有正式绘制圆环、刻度、指针和文字，所以界面上仍不会出现新的角度指示器。

## 校验结果

- 对以下文件执行过 lint 检查，未发现新增错误：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
