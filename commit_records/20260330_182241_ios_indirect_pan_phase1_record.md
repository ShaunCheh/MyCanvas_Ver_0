# 20260330_182241_ios_indirect_pan_phase1_record

## 记录范围

- 记录内容：
  1. 在 iOS 画布视图层新增独立的 `onPan` 输入回调。
  2. 新增一个只识别 `scroll / indirect pan` 的 `UIPanGestureRecognizer`。
  3. 在 `setupLayers()` 中注册该 recognizer，并新增 `handleIndirectPan(_:)` 负责把滚动事件转换为增量 `delta`。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本记录不包含：
  - `iOSViewController` 的 `onPan` 接线
  - `camera.pan(by:)` 的控制器消费逻辑
  - 方向校正与运行时真机回归验证

## 修改一：视图层新增独立的 indirect pan 事件入口

### 修改前

- `iOSCanvasViewportView` 只暴露 `pointer`、`longPress`、`zoom` 相关回调。
- 视图层只有 `pinchGestureRecognizer` 与 `longPressGestureRecognizer`，没有独立承接 trackpad 双指滚动的 recognizer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性声明区 / pinchGestureRecognizer / longPressGestureRecognizer
// 功能说明: 修改前视图层只暴露直接触摸与缩放相关回调，没有独立的 indirect pan 输入通道。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?

private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
    let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    gestureRecognizer.cancelsTouchesInView = false
    return gestureRecognizer
}()

private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
    let gestureRecognizer = UILongPressGestureRecognizer(
        target: self,
        action: #selector(handleLongPress(_:))
    )
    gestureRecognizer.cancelsTouchesInView = false
    gestureRecognizer.minimumPressDuration = Self.longPressMinimumDuration
    gestureRecognizer.allowableMovement = Self.longPressAllowableMovement
    gestureRecognizer.numberOfTouchesRequired = 1
    return gestureRecognizer
}()
```

### 修改后

- 新增 `onPan`，让控制器层未来可以像 macOS 一样独立接收平移输入。
- 新增 `indirectPanGestureRecognizer`，只识别连续滚动类型，不参与 direct touch 拖拽识别。
- 通过 `allowedTouchTypes = []` 将这个 recognizer 和现有 `touchesMoved` 状态机隔离开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 属性声明区 / indirectPanGestureRecognizer
// 功能说明: 修改后视图层新增独立的 onPan 回调，并新增一个只承接 scroll / indirect pan 的手势识别器。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?

private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
    let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    gestureRecognizer.cancelsTouchesInView = false
    return gestureRecognizer
}()

private lazy var indirectPanGestureRecognizer: UIPanGestureRecognizer = {
    let gestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleIndirectPan(_:))
    )
    // 只接 trackpad 等设备产生的连续 scroll，不让它参与 direct touch 拖拽。
    gestureRecognizer.allowedScrollTypesMask = .continuous
    gestureRecognizer.allowedTouchTypes = []
    gestureRecognizer.cancelsTouchesInView = false
    return gestureRecognizer
}()

private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
    let gestureRecognizer = UILongPressGestureRecognizer(
        target: self,
        action: #selector(handleLongPress(_:))
    )
    gestureRecognizer.cancelsTouchesInView = false
    gestureRecognizer.minimumPressDuration = Self.longPressMinimumDuration
    gestureRecognizer.allowableMovement = Self.longPressAllowableMovement
    gestureRecognizer.numberOfTouchesRequired = 1
    return gestureRecognizer
}()
```

## 修改二：在视图层注册 indirect pan recognizer

### 修改前

- `setupLayers()` 只注册 `pinch` 和 `longPress`。
- 即便系统发来了 `scroll / indirect pan`，视图层也没有 recognizer 可以接住它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改前 setupLayers 只挂载 pinch 与 long press 手势，视图层没有 scroll 输入的接入点。
private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = true
    isMultipleTouchEnabled = true

    layer.addSublayer(backgroundLayer)
    layer.addSublayer(workspaceGridLayer)
    workspaceGridLayer.addSublayer(workspaceMinorGridLayer)
    workspaceGridLayer.addSublayer(workspaceMajorGridLayer)
    layer.addSublayer(boardSurfaceLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
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
    addGestureRecognizer(pinchGestureRecognizer)
    addGestureRecognizer(longPressGestureRecognizer)
}
```

### 修改后

- `setupLayers()` 新增 `addGestureRecognizer(indirectPanGestureRecognizer)`。
- recognizer 注册顺序保持清晰：先加独立的 scroll 输入，再保留现有 `pinch` / `longPress`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改后 setupLayers 会显式注册 indirectPanGestureRecognizer，让 scroll / indirect pan 进入视图层。
private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = true
    isMultipleTouchEnabled = true

    layer.addSublayer(backgroundLayer)
    layer.addSublayer(workspaceGridLayer)
    workspaceGridLayer.addSublayer(workspaceMinorGridLayer)
    workspaceGridLayer.addSublayer(workspaceMajorGridLayer)
    layer.addSublayer(boardSurfaceLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
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
    addGestureRecognizer(indirectPanGestureRecognizer)
    addGestureRecognizer(pinchGestureRecognizer)
    addGestureRecognizer(longPressGestureRecognizer)
}
```

## 修改三：新增 handleIndirectPan(_:) 将 scroll 事件转换为增量 delta

### 修改前

- `isPinchGestureActive` 后面直接进入 `handlePinch(_:)`。
- 类中没有 `handleIndirectPan(_:)`，scroll 输入无法被转换为控制器可消费的平移增量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: isPinchGestureActive / handlePinch(_:)
// 功能说明: 修改前 pinch 状态判断之后直接进入缩放处理，视图层没有独立的 indirect pan handler。
private var isPinchGestureActive: Bool {
    switch pinchGestureRecognizer.state {
    case .began, .changed:
        true
    default:
        false
    }
}

@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began, .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        // ...
    default:
        break
    }
}
```

### 修改后

- 新增 `handleIndirectPan(_:)`，只在 `.began / .changed` 时处理连续滚动输入。
- 每次读取 `translation(in:)` 后立刻 `setTranslation(.zero, in: self)`，把 recognizer 输出归一成连续增量 `delta`。
- 当前阶段只负责把 `delta` 上报到 `onPan`，还没有在 controller 中消费它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handleIndirectPan(_:) / handlePinch(_:)
// 功能说明: 修改后新增独立的 indirect pan handler，把 scroll 输入转换为连续增量并上报给 onPan。
private var isPinchGestureActive: Bool {
    switch pinchGestureRecognizer.state {
    case .began, .changed:
        true
    default:
        false
    }
}

@objc
private func handleIndirectPan(_ gestureRecognizer: UIPanGestureRecognizer) {
    switch gestureRecognizer.state {
    case .began, .changed:
        let delta = gestureRecognizer.translation(in: self)
        guard delta != .zero else {
            return
        }

        // 视图层只负责把 scroll 手势归一成增量，控制器层将在后续阶段接入 camera 平移。
        onPan?(delta)
        gestureRecognizer.setTranslation(.zero, in: self)
    default:
        break
    }
}

@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began, .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        // ...
    default:
        break
    }
}
```

## 本阶段结果

- iOS 视图层已经具备承接 `scroll / indirect pan` 的输入能力。
- 现有 `touchesBegan / touchesMoved / touchesEnded` 状态机未被改动。
- 现有 `pinch` 与 `longPress` 逻辑未被移除或替换。
- 当前改动仍停留在视图层；要让画布真正移动，还需要后续阶段把 `onPan` 接到 `iOSViewController` 的相机平移逻辑。
