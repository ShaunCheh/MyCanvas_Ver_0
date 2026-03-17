# 20260317_195356_minimap_phase5_controller_wiring_record

## 记录范围

- 记录内容：
  1. 为 iOS/macOS minimap 视图新增导航回调，让点击/拖动 minimap 可以向 controller 回传定位请求。
  2. 在 iOS/macOS controller 中正式引入 `CanvasMiniMapRenderer` 与 minimap 视图实例，并挂载到 `miniMapMountView`。
  3. 将 minimap 刷新接入主画板刷新链路，让 minimap 跟随主画板实时同步。
  4. 将 minimap 点击/拖动导航接到 `camera.center`，实现通过 minimap 快速定位主画板。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - Phase 6 的回归测试与细节修正

## 修改一：为 minimap 视图新增导航回调

### 修改前

- `Phase 4` 的 minimap 视图只负责渲染，不负责对外回传点击/拖动意图。
- 虽然已经有 `worldPoint(atMiniMapPoint:)`，但 controller 还收不到用户在 minimap 上的导航手势。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名: worldPoint(atMiniMapPoint:) / currentContentRect
// 功能说明: 修改前 iOS minimap 只有几何查询能力，没有手势回调，controller 无法接收 minimap 导航请求。
func worldPoint(atMiniMapPoint point: CGPoint) -> CGPoint? {
    guard let geometry else {
        return nil
    }

    return geometry.miniMapToWorld(
        geometry.clampedMiniMapPoint(point)
    )
}

var currentContentRect: CGRect {
    geometry?.contentRect ?? .zero
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名: worldPoint(atMiniMapPoint:) / currentContentRect
// 功能说明: 修改前 macOS minimap 同样只有点位换算，没有把鼠标事件回传给 controller。
func worldPoint(atMiniMapPoint point: CGPoint) -> CGPoint? {
    guard let geometry else {
        return nil
    }

    return geometry.miniMapToWorld(
        geometry.clampedMiniMapPoint(point)
    )
}
```

### 修改后

- iOS minimap 新增：
  - `onNavigate`
  - `UITapGestureRecognizer`
  - `UIPanGestureRecognizer`
  - `handleTap(_:)`
  - `handlePan(_:)`
- macOS minimap 新增：
  - `onNavigate`
  - `mouseDown(with:)`
  - `mouseDragged(with:)`
- 这样 minimap 的“用户要跳转到哪”已经可以从视图层传到 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名: onNavigate / handleTap(_:) / handlePan(_:)
// 功能说明: iOS minimap 通过点击和拖动手势持续把 minimap 内部点位回传给 controller。
var onNavigate: ((CGPoint) -> Void)?

private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
    let gestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
    )
    return gestureRecognizer
}()

private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
    let gestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )
    return gestureRecognizer
}()

@objc
private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
    guard gestureRecognizer.state == .ended else {
        return
    }

    onNavigate?(gestureRecognizer.location(in: self))
}

@objc
private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
    switch gestureRecognizer.state {
    case .began, .changed:
        onNavigate?(gestureRecognizer.location(in: self))
    default:
        break
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名: onNavigate / mouseDown(with:) / mouseDragged(with:)
// 功能说明: macOS minimap 在鼠标按下和拖拽时都回传当前 minimap 点位，供 controller 做相机跳转。
var onNavigate: ((CGPoint) -> Void)?

override func mouseDown(with event: NSEvent) {
    onNavigate?(convert(event.locationInWindow, from: nil))
}

override func mouseDragged(with event: NSEvent) {
    onNavigate?(convert(event.locationInWindow, from: nil))
}
```

## 修改二：controller 正式持有 minimap renderer 与 minimap view

### 修改前

- `Phase 3` 只预留了 `miniMapMountView`，controller 里还没有 minimap renderer 和 minimap 视图实例。
- minimap 也没有被真正挂载到 `miniMapMountView`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性区
// 功能说明: 修改前 iOS controller 只有 minimap 布局配置和挂载位，没有真正的 minimap renderer / minimap view。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let miniMapMountView: iOSCanvasChromeOverlayView = {
    let view = iOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()
```

### 修改后

- iOS/macOS controller 都新增：
  - `miniMapRenderer`
  - `miniMapView`
- 并新增 `setupMiniMapView()`：
  - 设置初始 frame
  - 配置 autoresizingMask
  - 绑定 `onNavigate`
  - 挂到 `miniMapMountView`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性区 / setupMiniMapView()
// 功能说明: iOS controller 正式持有 minimap renderer 与 minimap view，并把 minimap view 安装到预留挂载位。
private let miniMapRenderer = CanvasMiniMapRenderer()
private let miniMapView = iOSCanvasMiniMapView()

private func setupMiniMapView() {
    miniMapView.frame = miniMapMountView.bounds
    miniMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    miniMapView.onNavigate = { [weak self] point in
        self?.handleMiniMapNavigate(to: point)
    }
    miniMapMountView.addSubview(miniMapView)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 属性区 / setupMiniMapView()
// 功能说明: macOS controller 做同构接线，保证后续刷新与交互逻辑在两个平台上保持一致。
private let miniMapRenderer = CanvasMiniMapRenderer()
private let miniMapView = macOSCanvasMiniMapView()

private func setupMiniMapView() {
    miniMapView.frame = miniMapMountView.bounds
    miniMapView.autoresizingMask = [.width, .height]
    miniMapView.onNavigate = { [weak self] point in
        self?.handleMiniMapNavigate(to: point)
    }
    miniMapMountView.addSubview(miniMapView)
}
```

## 修改三：把 minimap 刷新接入主画板刷新链路

### 修改前

- 主画板刷新时只会更新 `canvasViewportView`。
- minimap 虽然已有 `CanvasMiniMapRenderer` 和平台视图，但不会跟着主画板刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:)
// 功能说明: 修改前 iOS 的主刷新链只负责主画板 snapshot，不会顺带刷新 minimap。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    logCanvasState(reason: reason, snapshot: snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshCanvas()
// 功能说明: 修改前 macOS 的刷新链同样只更新主画板，不会生成 minimap snapshot。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}
```

### 修改后

- iOS/macOS 都新增 `refreshMiniMap()`：
  - 使用 `miniMapRenderer.makeSnapshot(...)`
  - 把 `scene / boardState / camera / inlineEditState / rotationPreviewState` 全量传入
  - 调用 `miniMapView.apply(snapshot)`
- 并在主刷新函数末尾追加 `refreshMiniMap()`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performCanvasRefresh(reason:) / refreshMiniMap()
// 功能说明: 主画板刷新完成后立即刷新 minimap，确保 minimap 和主画板使用同一批运行时状态。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
    logCanvasState(reason: reason, snapshot: snapshot)
}

private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    miniMapView.apply(snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshCanvas() / refreshMiniMap()
// 功能说明: macOS 主刷新链也同步补上 minimap snapshot 生成与应用。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
}

private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    miniMapView.apply(snapshot)
}
```

## 修改四：把 minimap 导航接到 `camera.center`

### 修改前

- minimap 没有 controller 级导航入口。
- 即使视图层可以把 minimap 点位反推成世界坐标，也没有地方真正把该坐标写回相机。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: 无
// 功能说明: 修改前 iOS controller 中没有 minimap 导航入口，用户无法通过 minimap 改变 camera.center。
// 无对应实现
```

### 修改后

- iOS 新增 `handleMiniMapNavigate(to:)`：
  - 先同步 viewport size
  - 把 minimap 点位转成世界坐标
  - 若中心点发生变化，则写入 `camera.center`
  - 触发 `requestCanvasRefresh(...)`
  - 触发 autosave
- macOS 同步新增 `handleMiniMapNavigate(to:)`
  - 直接写 `camera.center`
  - 调用 `refreshCanvas()`
  - 触发 autosave

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleMiniMapNavigate(to:)
// 功能说明: iOS minimap 点击/拖动会把点位映射成世界坐标，并把 camera.center 跳到目标位置。
private func handleMiniMapNavigate(to miniMapPoint: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard let worldPoint = miniMapView.worldPoint(atMiniMapPoint: miniMapPoint) else {
        return
    }

    guard camera.center != worldPoint else {
        return
    }

    camera.center = worldPoint
    requestCanvasRefresh(reason: "navigate minimap to \(describe(point: worldPoint))")
    scheduleAutosave(reason: "navigate canvas via minimap")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleMiniMapNavigate(to:)
// 功能说明: macOS minimap 导航使用同样的世界坐标回写策略，刷新完成后主画板与 minimap 同步移动。
private func handleMiniMapNavigate(to miniMapPoint: CGPoint) {
    guard let worldPoint = miniMapView.worldPoint(atMiniMapPoint: miniMapPoint) else {
        return
    }

    guard camera.center != worldPoint else {
        return
    }

    camera.center = worldPoint
    refreshCanvas()
    scheduleAutosave(reason: "navigate canvas via minimap")
}
```

## 修改五：让 minimap 真正显示在 `miniMapMountView` 中

### 修改前

- `miniMapMountView` 在 `Phase 3` 里只是一个预留空容器。
- 即使 `updateChromeOverlayLayout()` 已经能算出 frame，界面上仍看不到 minimap。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: 修改前 mount view 只有 frame，没有真正挂载 minimap 内容视图。
let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
    safeBounds: safeBounds,
    occupiedRects: occupiedRects,
    configuration: miniMapConfiguration
)?.integral ?? .zero
if miniMapMountView.frame != miniMapFrame {
    miniMapMountView.frame = miniMapFrame
}
```

### 修改后

- `setupMiniMapView()` 已把 minimap view 真正加到 `miniMapMountView`
- `updateChromeOverlayLayout()` 现在除了更新 mount frame，还会：
  - 根据 `miniMapFrame.isEmpty` 控制 `miniMapMountView.isHidden`
  - 同步更新 `miniMapView.frame = miniMapMountView.bounds`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: updateChromeOverlayLayout()
// 功能说明: mount view 有了真实 minimap 内容后，layout 阶段同时更新容器可见性和 minimap 子视图尺寸。
private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
}
```

## 结果与影响

- 本次修改完成了 minimap `Phase 5`：
  - minimap 已真正挂载到界面
  - minimap 会随主画板刷新同步更新
  - minimap 点击/拖动已能驱动画板定位
- 当前 minimap 的功能闭环已经形成：
  - 数据有 `CanvasMiniMapRenderer`
  - 视图有 iOS/macOS minimap view
  - 布局有 `miniMapMountView + CanvasOverlayLayoutSolver`
  - 导航有 `handleMiniMapNavigate(to:)`
- 后续主要进入 `Phase 6` 的回归验证与细节修正阶段。

## 校验情况

- `ReadLints` 已检查：
  - `iOSCanvasMiniMapView.swift`
  - `macOSCanvasMiniMapView.swift`
  - `iOSViewController.swift`
  - `macOSViewController.swift`
- 未发现新增诊断。
- 已执行 macOS 侧全链路 typecheck：
  - `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift MyCanvas_Ver_0/Canvas/Editing/*.swift MyCanvas_Ver_0/Canvas/Storage/*.swift MyCanvas_Ver_0/App/*.swift MyCanvas_Ver_0/Platform/Shared/Rendering/*.swift MyCanvas_Ver_0/Platform/macOS/Canvas/*.swift MyCanvas_Ver_0/Platform/macOS/*.swift MyCanvas_Ver_0/Platform/macOS/AppRoot/*.swift MyCanvas_Ver_0/Platform/macOS/BoardList/*.swift`
- 通过。
