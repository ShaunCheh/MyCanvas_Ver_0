# 20260313_160249_phase5_canvas_input_camera_record

## 记录范围

- 记录内容：阶段 5 的自定义平移缩放输入与 `CanvasCamera` 接线。
- 目标：让 `iOS` 和 `macOS` 两端的 viewport 能采集输入事件，并统一交给控制器更新 `CanvasCamera`，再通过 `CanvasRenderer` 刷新快照。
- 本次未包含：测试图片接入、真实图片显示验证、导入与存储。

## 变更 1：iOS viewport 新增手势输入出口

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数/类型: apply(_:) / setupLayers()
// 功能说明: 修改前的 iOS viewport 只负责维护 layer 树和消费 CanvasRenderSnapshot，还没有把平移和缩放输入向外抛出。
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

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)

        updateBackgroundAppearance()
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数/类型: handlePan(_:) / handlePinch(_:) / gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)
// 功能说明: 修改后的 iOS viewport 增加平移和缩放手势，并通过 onPan / onZoom 回调把输入交给上层控制器。
final class iOSCanvasViewportView: UIView, UIGestureRecognizerDelegate {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var snapshot: CanvasRenderSnapshot = .empty
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)

        updateBackgroundAppearance()
    }

    @objc
    private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation = gestureRecognizer.translation(in: self)
        onPan?(translation)
        gestureRecognizer.setTranslation(.zero, in: self)
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        let scaleDelta = gestureRecognizer.scale
        onZoom?(scaleDelta, gestureRecognizer.location(in: self))
        gestureRecognizer.scale = 1
    }
}
```

## 变更 2：macOS viewport 新增鼠标、滚轮和放大输入出口

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数/类型: apply(_:) / setupLayers()
// 功能说明: 修改前的 macOS viewport 只负责维护 layer 树和消费 CanvasRenderSnapshot，还没有把拖拽、滚轮和放大输入向外抛出。
final class macOSCanvasViewportView: NSView {
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
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数/类型: mouseDown(with:) / mouseDragged(with:) / scrollWheel(with:) / magnify(with:)
// 功能说明: 修改后的 macOS viewport 增加拖拽、滚轮和平滑放大输入，并通过 onPan / onZoom 回调把输入交给上层控制器。
final class macOSCanvasViewportView: NSView {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var snapshot: CanvasRenderSnapshot = .empty
    private var lastDragLocation: CGPoint?
    var onPan: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

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
        onPan?(delta)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        onPan?(delta)
    }

    override func magnify(with event: NSEvent) {
        let scaleDelta = max(0.01, 1 + event.magnification)
        let anchor = convert(event.locationInWindow, from: nil)
        onZoom?(scaleDelta, anchor)
    }
}
```

## 变更 3：iOS 画板宿主接入 `CanvasScene + CanvasCamera + CanvasRenderer`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型: viewDidLoad() / setupCanvasViewport()
// 功能说明: 修改前的 iOS 宿主控制器只负责把空 viewport 挂进去，还没有维护场景、相机和渲染器，也没有把输入事件接到刷新链路。
final class iOSViewController: UIViewController {
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?

    private func setupCanvasViewport() {
        installCanvasContentView(canvasViewportView)
        canvasViewportView.apply(.empty)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/类型: updateCameraViewportSizeIfNeeded() / handlePan(_:) / handleZoom(_:around:) / refreshCanvas()
// 功能说明: 修改后的 iOS 宿主控制器接管场景、相机和渲染器，并将 viewport 的输入统一转换成相机更新与快照刷新。
final class iOSViewController: UIViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()
    private let canvasViewportView = iOSCanvasViewportView()
    private var canvasContentView: UIView?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCameraViewportSizeIfNeeded()
    }

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

    private func updateCameraViewportSizeIfNeeded() {
        let viewportSize = canvasViewportView.bounds.size
        guard viewportSize != camera.viewportSize else {
            return
        }

        camera.setViewportSize(viewportSize)
        refreshCanvas()
    }

    private func handlePan(_ translation: CGPoint) {
        camera.pan(by: translation)
        refreshCanvas()
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
    }

    private func refreshCanvas() {
        let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
        canvasViewportView.apply(snapshot)
    }
}
```

## 变更 4：macOS 画板宿主接入 `CanvasScene + CanvasCamera + CanvasRenderer`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型: viewDidLoad() / setupCanvasViewport()
// 功能说明: 修改前的 macOS 宿主控制器只负责把空 viewport 挂进去，还没有维护场景、相机和渲染器，也没有把输入事件接到刷新链路。
final class macOSViewController: NSViewController {
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?

    private func setupCanvasViewport() {
        installCanvasContentView(canvasViewportView)
        canvasViewportView.apply(.empty)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数/类型: updateCameraViewportSizeIfNeeded() / handlePan(_:) / handleZoom(_:around:) / refreshCanvas()
// 功能说明: 修改后的 macOS 宿主控制器接管场景、相机和渲染器，并将 viewport 的输入统一转换成相机更新与快照刷新。
final class macOSViewController: NSViewController {
    private let scene = CanvasScene()
    private var camera = CanvasCamera()
    private let renderer = CanvasRenderer()
    private let canvasHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.masksToBounds = true
        return view
    }()
    private let canvasViewportView = macOSCanvasViewportView()
    private var canvasContentView: NSView?

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCameraViewportSizeIfNeeded()
    }

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

    private func updateCameraViewportSizeIfNeeded() {
        let viewportSize = canvasViewportView.bounds.size
        guard viewportSize != camera.viewportSize else {
            return
        }

        camera.setViewportSize(viewportSize)
        refreshCanvas()
    }

    private func handlePan(_ translation: CGPoint) {
        camera.pan(by: translation)
        refreshCanvas()
    }

    private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
        camera.zoom(by: scaleDelta, around: anchor)
        refreshCanvas()
    }

    private func refreshCanvas() {
        let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
        canvasViewportView.apply(snapshot)
    }
}
```

## 当前阶段结果

- 两端 viewport 都已经能采集平移和缩放输入。
- 两端宿主控制器都已经维护 `CanvasScene`、`CanvasCamera`、`CanvasRenderer`。
- 当前交互链路已经变成：
  - viewport 输入
  - 更新 `CanvasCamera`
  - `CanvasRenderer` 生成快照
  - viewport 应用 `CanvasRenderSnapshot`
- 由于还没有接入测试图片，所以现在交互已经生效，但屏幕上仍然是空白 viewport。
