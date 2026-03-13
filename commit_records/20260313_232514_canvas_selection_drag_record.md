# 20260313_232514_canvas_selection_drag_record

## 记录范围

- 记录内容：实现画布上的图片选中态、蓝色高亮边框，以及“拖动已选中图片移动图片位置，不影响空白区域拖动画布”的交互分流。
- 目标：保持当前 `Scene + Camera + Renderer + Viewport` 架构不变，把选中态和命中/移动能力下沉到共享层，把输入分流收口到平台控制器。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`、`MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`、`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`、`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`。
- 本次未包含：多选、空白点击取消选中、拖动未选中图片时自动选中并开始拖动、提交 Git Commit。

## 变更 1：新增共享交互态，选中图片不再散落在平台层临时变量里

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 类型名: CanvasInteractionState
// 功能说明: 修改前不存在该文件。
// 选中态没有独立的共享数据结构，renderer 和 controller 之间也没有统一的 selection 载体。
// 修改前: 文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInteractionState.swift
// 类型名: CanvasInteractionState / init(selectedItemID:)
// 功能说明: 修改后引入共享交互态，只保存运行时 selection，不污染 CanvasImageItem 文档数据。
import Foundation

struct CanvasInteractionState {
    var selectedItemID: CanvasImageItemID?

    init(selectedItemID: CanvasImageItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
```

## 变更 2：CanvasScene 增加命中测试和图片移动能力

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: removeItem(withID:) / visibleItems(in:) / orderedItems()
// 功能说明: 修改前 Scene 只管理增删和可见项过滤，没有 item 查询、顶层命中和图片移动能力。
func removeItem(withID id: CanvasImageItemID) {
    items.removeAll(where: { $0.id == id })
}

func visibleItems(in worldRect: CGRect) -> [CanvasImageItem] {
    orderedItems(from: items.filter { $0.worldFrame.intersects(worldRect) })
}

func orderedItems() -> [CanvasImageItem] {
    orderedItems(from: items)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: item(withID:) / topmostItem(containing:) / moveItem(withID:by:) / updateItem(withID:_:)
// 功能说明: 修改后 Scene 负责世界坐标命中测试和图片几何更新。
// topmostItem(containing:) 会按 z 序倒序返回顶层图片；moveItem(withID:by:) 只改 item.center，不碰 camera。
func item(withID id: CanvasImageItemID) -> CanvasImageItem? {
    items.first(where: { $0.id == id })
}

func topmostItem(containing worldPoint: CGPoint) -> CanvasImageItem? {
    orderedItems().reversed().first(where: { $0.worldFrame.contains(worldPoint) })
}

func moveItem(withID id: CanvasImageItemID, by deltaInWorld: CGPoint) {
    guard deltaInWorld != .zero else {
        return
    }

    updateItem(withID: id) { item in
        item.center.x += deltaInWorld.x
        item.center.y += deltaInWorld.y
    }
}

private func updateItem(
    withID id: CanvasImageItemID,
    _ mutate: (inout CanvasImageItem) -> Void
) {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
        return
    }

    mutate(&items[index])
}
```

## 变更 3：选中态进入渲染快照，渲染层可以直接知道哪张图需要高亮

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 类型名: CanvasRenderItem
// 功能说明: 修改前 render item 只有几何和图片内容，没有选中态。
struct CanvasRenderItem {
    let id: CanvasImageItemID
    let screenFrame: CGRect
    let cgImage: CGImage
    let zIndex: CGFloat
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:camera:)
// 功能说明: 修改前 renderer 只消费 scene 和 camera，无法把 selectedItemID 编进渲染结果。
func makeSnapshot(
    scene: CanvasScene,
    camera: CanvasCamera
) -> CanvasRenderSnapshot {
    let renderItems = visibleItems.map { item in
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
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 类型名: CanvasRenderItem
// 功能说明: 修改后 render item 显式携带 isSelected，渲染层不需要自己猜测当前选中对象。
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
// 函数名: makeSnapshot(scene:camera:interactionState:)
// 功能说明: 修改后 renderer 会把 interactionState.selectedItemID 编进快照，让高亮逻辑跟随统一渲染真相。
func makeSnapshot(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState()
) -> CanvasRenderSnapshot {
    let renderItems = visibleItems.map { item in
        CanvasRenderItem(
            id: item.id,
            screenFrame: camera.worldToViewport(item.worldFrame),
            cgImage: item.cgImage,
            zIndex: item.zIndex,
            isSelected: interactionState.selectedItemID == item.id
        )
    }

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        items: renderItems
    )
}
```

## 变更 4：CanvasImageLayer 根据选中态绘制蓝色边框

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改前图片层只同步 frame、contents、zPosition、contentsScale，没有边框高亮概念。
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

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: update(with:contentsScale:) / configureLayer()
// 功能说明: 修改后图片层把 isSelected 渲染为蓝色边框，并缓存上次选中态，避免重复提交 border 属性。
private static let selectionBorderColor = CGColor(
    red: 0,
    green: 122.0 / 255.0,
    blue: 1,
    alpha: 1
)
private static let selectionBorderWidth: CGFloat = 2
private var lastAppliedIsSelected: Bool?

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

## 变更 5：iOS viewport 从 `onPan` 升级为 pointer 生命周期事件源

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: TouchInteractionState / touchesMoved(_:with:)
// 功能说明: 修改前 viewport 把单指拖动直接翻译成 onPan，控制器拿到的已经是“移动画布”的高层语义。
private enum TouchInteractionState {
    case idle
    case singleFingerPan(trackedTouch: UITouch, lastLocation: CGPoint)
    case awaitingPinch
    case pinching
}

var onPan: ((CGPoint) -> Void)?

override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    registerActiveTouches(touches)

    guard !isPinchGestureActive else {
        interactionState = .pinching
        return
    }

    switch interactionState {
    case let .singleFingerPan(trackedTouch, lastLocation):
        guard activeTouchCount == 1 else {
            interactionState = .awaitingPinch
            return
        }

        guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
            return
        }

        let currentLocation = currentTouch.location(in: self)
        interactionState = .singleFingerPan(
            trackedTouch: trackedTouch,
            lastLocation: currentLocation
        )

        let translation = CGPoint(
            x: currentLocation.x - lastLocation.x,
            y: currentLocation.y - lastLocation.y
        )
        guard translation != .zero else {
            return
        }

        onPan?(translation)
    case .idle, .awaitingPinch, .pinching:
        reconcileTouchInteractionState()
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: TouchInteractionState / touchesMoved(_:with:) / beginPrimaryPointerTracking(with:) / cancelPrimaryPointerIfNeeded()
// 功能说明: 修改后 viewport 只负责上报 pointer 生命周期和位置变化，不直接决定是拖图片还是拖画布。
private enum TouchInteractionState {
    case idle
    case trackingPrimaryPointer(trackedTouch: UITouch, lastLocation: CGPoint)
    case awaitingPinch
    case pinching
}

var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?

override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    registerActiveTouches(touches)

    guard !isPinchGestureActive else {
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        return
    }

    switch interactionState {
    case let .trackingPrimaryPointer(trackedTouch, lastLocation):
        guard activeTouchCount == 1 else {
            cancelPrimaryPointerIfNeeded()
            interactionState = .awaitingPinch
            return
        }

        guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
            return
        }

        let currentLocation = currentTouch.location(in: self)
        interactionState = .trackingPrimaryPointer(
            trackedTouch: trackedTouch,
            lastLocation: currentLocation
        )

        guard currentLocation != lastLocation else {
            return
        }

        onPointerMove?(currentLocation, lastLocation)
    case .idle, .awaitingPinch, .pinching:
        reconcileTouchInteractionState()
    }
}

private func beginPrimaryPointerTracking(with touch: UITouch) {
    let location = touch.location(in: self)
    interactionState = .trackingPrimaryPointer(
        trackedTouch: touch,
        lastLocation: location
    )
    onPointerDown?(location)
}

private func cancelPrimaryPointerIfNeeded() {
    guard case .trackingPrimaryPointer = interactionState else {
        return
    }

    onPointerCancel?()
}
```

## 变更 6：iOS 控制器接管命中测试和交互分流

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport() / handlePan(_:) / performCanvasRefresh(reason:)
// 功能说明: 修改前 controller 只接收 onPan，并把所有单指拖动都解释为移动可见区域。
private func setupCanvasViewport() {
    canvasViewportView.onPan = { [weak self] translation in
        self?.handlePan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}

private func handlePan(_ translation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pan \(describe(point: translation))")
        return
    }

    let cameraCenterBeforePan = camera.center
    camera.pan(by: translation)
    logPanDispatch(
        translation: translation,
        cameraCenterBeforePan: cameraCenterBeforePan,
        cameraCenterAfterPan: camera.center
    )
    requestCanvasRefresh(reason: "pan \(describe(point: translation))")
}

private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
    canvasViewportView.apply(snapshot)
    logCanvasState(reason: reason, snapshot: snapshot)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport() / handlePrimaryPointerDown(at:) / handlePrimaryPointerMove(to:from:) / handlePrimaryPointerUp(at:) / moveSelectedItem(withID:from:to:) / panCanvas(from:to:) / performCanvasRefresh(reason:)
// 功能说明: 修改后 controller 持有 selection 和 pointerDragState。
// 它会先基于上一次 render snapshot 的 screenFrame 做命中测试，再分流为选中图片、拖动已选中图片或拖动画布。
private enum PointerDragState {
    case idle
    case pressed(pressedItemID: CanvasImageItemID?, pressedItemWasSelected: Bool)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case draggingCanvas
}

private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
private var pointerDragState: PointerDragState = .idle

private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer move \(describe(point: location))")
        return
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, pressedItemWasSelected):
        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: previousLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: previousLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(pressedItemID, _):
        guard let pressedItemID, hitTestItemID(at: location) == pressedItemID else {
            return
        }

        selectItem(withID: pressedItemID)
    case .draggingSelectedItem, .draggingCanvas, .idle:
        break
    }
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let deltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard deltaInWorld != .zero else {
        return
    }

    scene.moveItem(withID: itemID, by: deltaInWorld)
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
}

private func panCanvas(from previousLocation: CGPoint, to location: CGPoint) {
    let translation = CGPoint(
        x: location.x - previousLocation.x,
        y: location.y - previousLocation.y
    )
    guard translation != .zero else {
        return
    }

    let cameraCenterBeforePan = camera.center
    camera.pan(by: translation)
    logPanDispatch(
        translation: translation,
        cameraCenterBeforePan: cameraCenterBeforePan,
        cameraCenterAfterPan: camera.center
    )
    requestCanvasRefresh(reason: "pan \(describe(point: translation))")
}

private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    logCanvasState(reason: reason, snapshot: snapshot)
}
```

## 变更 7：macOS 同步成相同的 pointer 语义，滚轮仍只负责拖动画布

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: mouseDown(with:) / mouseDragged(with:) / mouseUp(with:)
// 功能说明: 修改前 mouseDragged 直接输出 onPan，鼠标主指针没有独立的 pointer 生命周期回调。
private var lastDragLocation: CGPoint?
var onPan: ((CGPoint) -> Void)?

override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    lastDragLocation = convert(event.locationInWindow, from: nil)
}

override func mouseDragged(with event: NSEvent) {
    let currentLocation = convert(event.locationInWindow, from: nil)
    let previousLocation = lastDragLocation ?? currentLocation
    let delta = CGPoint(
        x: currentLocation.x - previousLocation.x,
        y: currentLocation.y - previousLocation.y
    )

    lastDragLocation = currentLocation
    guard delta != .zero else {
        return
    }

    onPan?(delta)
}

override func mouseUp(with event: NSEvent) {
    lastDragLocation = nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupCanvasViewport() / handlePan(_:) / refreshCanvas()
// 功能说明: 修改前 macOS controller 和 iOS 一样，把拖动统一解释为 camera.pan(by:)。
private func setupCanvasViewport() {
    canvasViewportView.onPan = { [weak self] translation in
        self?.handlePan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas()
}

private func handlePan(_ translation: CGPoint) {
    camera.pan(by: translation)
    refreshCanvas()
}

private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
    canvasViewportView.apply(snapshot)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: mouseDown(with:) / mouseDragged(with:) / mouseUp(with:) / scrollWheel(with:)
// 功能说明: 修改后 macOS viewport 也会上报 onPointerDown / onPointerMove / onPointerUp。
// scrollWheel 仍然保留为独立的 onPan，继续只服务于间接平移可见区域。
private var lastPrimaryPointerLocation: CGPoint?
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onPan: ((CGPoint) -> Void)?

override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let location = convert(event.locationInWindow, from: nil)
    lastPrimaryPointerLocation = location
    onPointerDown?(location)
}

override func mouseDragged(with event: NSEvent) {
    let currentLocation = convert(event.locationInWindow, from: nil)
    let previousLocation = lastPrimaryPointerLocation ?? currentLocation
    lastPrimaryPointerLocation = currentLocation
    guard currentLocation != previousLocation else {
        return
    }

    onPointerMove?(currentLocation, previousLocation)
}

override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    lastPrimaryPointerLocation = nil
    onPointerUp?(location)
}

override func scrollWheel(with event: NSEvent) {
    let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
    guard delta != .zero else {
        super.scrollWheel(with: event)
        return
    }

    onPan?(delta)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupCanvasViewport() / handlePrimaryPointerMove(to:from:) / handleIndirectPan(_:) / moveSelectedItem(withID:from:to:) / refreshCanvas()
// 功能说明: 修改后 macOS controller 与 iOS 保持相同的选中与拖拽分流逻辑。
private enum PointerDragState {
    case idle
    case pressed(pressedItemID: CanvasImageItemID?, pressedItemWasSelected: Bool)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case draggingCanvas
}

private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
private var pointerDragState: PointerDragState = .idle

private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas()
}

private func handlePrimaryPointerMove(to location: CGPoint, from previousLocation: CGPoint) {
    switch pointerDragState {
    case let .pressed(pressedItemID, pressedItemWasSelected):
        if pressedItemWasSelected, let pressedItemID {
            pointerDragState = .draggingSelectedItem(itemID: pressedItemID)
            moveSelectedItem(withID: pressedItemID, from: previousLocation, to: location)
        } else {
            pointerDragState = .draggingCanvas
            panCanvas(from: previousLocation, to: location)
        }
    case let .draggingSelectedItem(itemID):
        moveSelectedItem(withID: itemID, from: previousLocation, to: location)
    case .draggingCanvas:
        panCanvas(from: previousLocation, to: location)
    case .idle:
        break
    }
}

private func handleIndirectPan(_ translation: CGPoint) {
    camera.pan(by: translation)
    refreshCanvas()
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let deltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard deltaInWorld != .zero else {
        return
    }

    scene.moveItem(withID: itemID, by: deltaInWorld)
    refreshCanvas()
}

private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

## 结果说明

- 选中态现在有了共享数据模型，且不再污染 `CanvasImageItem`。
- 图片是否选中由 renderer 明确写进 `CanvasRenderItem.isSelected`，渲染层只负责如实显示。
- iOS 和 macOS 的命中、选中、拖动已选中图片、拖动画布语义已经对齐。
- 当前交互策略是保守版：
  - 点击图片进入选中态并显示蓝色边框。
  - 只有“已选中图片”会被直接拖动。
  - 拖动未选中图片或空白区域时，仍然移动可见区域。
  - 本次没有加入“点击空白取消选中”。

## 验证结果

- 使用完整 Xcode 工具链执行 iOS Simulator 构建验证，构建通过。
- 使用完整 Xcode 工具链执行 macOS 构建验证，构建通过。
- 本次只新增记录文件，未提交 Git Commit。
