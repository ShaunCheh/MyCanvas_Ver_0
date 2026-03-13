# 20260313_183232_fix_ios_drag_follow_record

## 记录范围

- 记录内容：修复 iOS 画布拖动“不跟手”的两轮修改。
- 第一轮目标：移除 `UIPanGestureRecognizer` 的系统滞后，改为 raw touch 驱动单指平移，并保证 pinch 结束后可以继续单指续拖。
- 第二轮目标：消除 `CALayer` 隐式动画和高频冗余属性写入造成的视觉追手问题。
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`、`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift`、`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`。
- 本次未包含：存储层改动、提交 Git Commit。

## 变更 1：iOS 单指拖动从 `UIPanGestureRecognizer` 改为 raw touch 状态机

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers() / handlePan(_:) / gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)
// 功能说明: 修改前单指平移完全依赖 UIPanGestureRecognizer。
// UIKit 会先完成系统手势识别和滞后判定，再把 translation 派发到画布层。
final class iOSCanvasViewportView: UIView, UIGestureRecognizerDelegate {
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
        switch gestureRecognizer.state {
        case .began, .changed:
            let translation = gestureRecognizer.translation(in: self)
            guard translation != .zero else {
                return
            }

            onPan?(translation)
            gestureRecognizer.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: touchesBegan(_:with:) / touchesMoved(_:with:) / touchesEnded(_:with:) / reconcileTouchInteractionState() / handlePinch(_:) / setupLayers()
// 功能说明: 修改后单指拖动改为 raw touch 状态机，直接根据连续触点位置差计算平移量。
// pinch 仍由 UIPinchGestureRecognizer 负责，但通过 cancelsTouchesInView = false 和状态机衔接，实现缩放结束后的单指续拖。
final class iOSCanvasViewportView: UIView {
    private enum TouchInteractionState {
        case idle
        case singleFingerPan(trackedTouch: UITouch, lastLocation: CGPoint)
        case awaitingPinch
        case pinching
    }

    private var interactionState: TouchInteractionState = .idle
    private var activeTouchesByID: [ObjectIdentifier: UITouch] = [:]

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()

    private func setupLayers() {
        backgroundColor = .clear
        clipsToBounds = true
        isMultipleTouchEnabled = true

        layer.addSublayer(backgroundLayer)
        layer.addSublayer(itemsLayer)
        layer.addSublayer(overlayLayer)
        addGestureRecognizer(pinchGestureRecognizer)

        updateBackgroundAppearance()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        registerActiveTouches(touches)

        guard !isPinchGestureActive else {
            interactionState = .pinching
            return
        }

        switch interactionState {
        case let .singleFingerPan(trackedTouch, lastLocation):
            guard activeTouchCount == 1,
                  let currentTouch = touchMatching(trackedTouch, in: touches) else {
                interactionState = .awaitingPinch
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

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began, .changed:
            interactionState = .pinching

            let scaleDelta = gestureRecognizer.scale
            guard scaleDelta.isFinite, scaleDelta > 0 else {
                return
            }

            onZoom?(scaleDelta, gestureRecognizer.location(in: self))
            gestureRecognizer.scale = 1
        case .ended, .cancelled, .failed:
            reconcileTouchInteractionState()
        default:
            break
        }
    }
}
```

## 变更 1 补充：关闭热路径诊断日志的默认输出

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: logImport(dataCount:cgImage:) / logCanvasState(reason:snapshot:) / logDeferredCanvasRefresh(reason:actualViewportSize:) / logIgnoredCanvasInput(_:)
// 功能说明: 修改前这些诊断函数默认直接 print。
// 当它们被放在导图、刷新和交互热路径中时，会持续向控制台输出日志。
private func logImport(dataCount: Int, cgImage: CGImage) {
    print(
        "[Canvas iOS] loaded image data bytes=\(dataCount) " +
        "pixelSize=\(cgImage.width)x\(cgImage.height)"
    )
}

private func logCanvasState(reason: String, snapshot: CanvasRenderSnapshot) {
    let orderedItems = scene.orderedItems()
    let firstWorldFrame = orderedItems.first.map { describe(rect: $0.worldFrame) } ?? "nil"
    let firstScreenFrame = snapshot.items.first.map { describe(rect: $0.screenFrame) } ?? "nil"

    print(
        "[Canvas iOS] \(reason) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", camera.zoomScale)) " +
        "viewportSize=\(describe(size: camera.viewportSize)) " +
        "visibleWorldRect=\(describe(rect: camera.visibleWorldRect)) " +
        "sceneItems=\(orderedItems.count) " +
        "visibleItems=\(snapshot.items.count) " +
        "firstWorldFrame=\(firstWorldFrame) " +
        "firstScreenFrame=\(firstScreenFrame)"
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: isDiagnosticLoggingEnabled / logImport(dataCount:cgImage:) / logCanvasState(reason:snapshot:) / logPanDispatch(translation:cameraCenterBeforePan:cameraCenterAfterPan:)
// 功能说明: 修改后保留诊断能力，但默认关闭日志输出，避免热路径 print 进一步影响拖动手感。
private static let isDiagnosticLoggingEnabled = false

private func logImport(dataCount: Int, cgImage: CGImage) {
    guard Self.isDiagnosticLoggingEnabled else {
        return
    }

    print(
        "[Canvas iOS] loaded image data bytes=\(dataCount) " +
        "pixelSize=\(cgImage.width)x\(cgImage.height)"
    )
}

private func logCanvasState(reason: String, snapshot: CanvasRenderSnapshot) {
    guard Self.isDiagnosticLoggingEnabled else {
        return
    }

    let orderedItems = scene.orderedItems()
    let firstWorldFrame = orderedItems.first.map { describe(rect: $0.worldFrame) } ?? "nil"
    let firstScreenFrame = snapshot.items.first.map { describe(rect: $0.screenFrame) } ?? "nil"

    print(
        "[Canvas iOS] \(reason) " +
        "cameraCenter=\(describe(point: camera.center)) " +
        "zoom=\(String(format: "%.4f", camera.zoomScale)) " +
        "viewportSize=\(describe(size: camera.viewportSize)) " +
        "visibleWorldRect=\(describe(rect: camera.visibleWorldRect)) " +
        "sceneItems=\(orderedItems.count) " +
        "visibleItems=\(snapshot.items.count) " +
        "firstWorldFrame=\(firstWorldFrame) " +
        "firstScreenFrame=\(firstScreenFrame)"
    )
}

private func logPanDispatch(
    translation: CGPoint,
    cameraCenterBeforePan: CGPoint,
    cameraCenterAfterPan: CGPoint
) {
    guard Self.isDiagnosticLoggingEnabled else {
        return
    }

    print(
        "[Canvas iOS][ControllerPan] " +
        "translation=\(describe(point: translation)) " +
        "cameraCenterBefore=\(describe(point: cameraCenterBeforePan)) " +
        "cameraCenterAfter=\(describe(point: cameraCenterAfterPan)) " +
        "zoom=\(String(format: "%.4f", camera.zoomScale)) " +
        "cameraViewportSize=\(describe(size: camera.viewportSize)) " +
        "viewBoundsSize=\(describe(size: canvasViewportView.bounds.size))"
    )
}
```

## 变更 2：关闭高频 `CALayer` 同步的隐式动画

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: layoutSubviews() / didMoveToWindow() / apply(_:) / updateLayerFrames()
// 功能说明: 修改前每次布局和刷新都会直接改容器 layer 的 frame，并立即刷新图片层。
// 这里没有显式关闭 Core Animation actions，拖动时会把高频位置更新暴露给隐式动画系统。
override func layoutSubviews() {
    super.layoutSubviews()
    updateLayerFrames()
    reportViewportSizeIfNeeded()
}

override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    refreshImageLayers()
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    updateLayerFrames()
    refreshImageLayers()
}

private func updateLayerFrames() {
    backgroundLayer.frame = bounds
    itemsLayer.frame = bounds
    overlayLayer.frame = bounds
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: layoutSubviews() / didMoveToWindow() / apply(_:) / performWithoutLayerActions(_:) / updateLayerFrames()
// 功能说明: 修改后把整批 layer 同步包进无隐式动画事务，并避免在 bounds 未变化时重复改容器层 frame。
override func layoutSubviews() {
    super.layoutSubviews()
    performWithoutLayerActions {
        updateLayerFrames()
    }
    reportViewportSizeIfNeeded()
}

override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
    }
}

private func updateLayerFrames() {
    if backgroundLayer.frame != bounds {
        backgroundLayer.frame = bounds
    }

    if itemsLayer.frame != bounds {
        itemsLayer.frame = bounds
    }

    if overlayLayer.frame != bounds {
        overlayLayer.frame = bounds
    }
}

private func performWithoutLayerActions(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}
```

## 变更 2 补充：图片层只在属性真正变化时才提交更新

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: init(itemID:) / update(with:contentsScale:)
// 功能说明: 修改前每次刷新都会无条件重写 frame、contents、zPosition 和 contentsScale。
// 这意味着纯平移时即使图片内容未变化，也会重复把同一批属性提交给 Core Animation。
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

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasImageLayer.swift
// 函数名: init(itemID:) / update(with:contentsScale:) / configureLayer() / isDisplayingImage(_:)
// 功能说明: 修改后图片层自身也包了一层无隐式动画事务，并缓存上次应用的属性值。
// 这样纯平移时只更新 screenFrame，对未变化的 contents、zPosition、contentsScale 不再重复提交。
final class CanvasImageLayer: CALayer {
    let itemID: CanvasImageItemID
    private var lastAppliedFrame: CGRect
    private var lastAppliedImage: CGImage?
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat

    init(itemID: CanvasImageItemID) {
        self.itemID = itemID
        lastAppliedFrame = .null
        lastAppliedImage = nil
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        super.init()
        configureLayer()
    }

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

    private func isDisplayingImage(_ cgImage: CGImage) -> Bool {
        guard let lastAppliedImage else {
            return false
        }

        return lastAppliedImage === cgImage
    }
}
```

## 变更 2 补充：macOS 视口层同步补上无动画事务，保持跨平台一致

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: layout() / viewDidMoveToWindow() / apply(_:) / updateLayerFrames()
// 功能说明: 修改前 macOS 侧和 iOS 侧一样，直接在布局和刷新中同步 layer，没有显式关闭隐式动画。
override func layout() {
    super.layout()
    updateLayerFrames()
}

override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    refreshImageLayers()
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    updateLayerFrames()
    refreshImageLayers()
}

private func updateLayerFrames() {
    backgroundLayer.frame = bounds
    itemsLayer.frame = bounds
    overlayLayer.frame = bounds
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: layout() / viewDidMoveToWindow() / apply(_:) / performWithoutLayerActions(_:) / updateLayerFrames()
// 功能说明: 修改后 macOS 也统一走无隐式动画事务，并避免在 bounds 未变化时重复更新容器层 frame。
override func layout() {
    super.layout()
    performWithoutLayerActions {
        updateLayerFrames()
    }
}

override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
    }
}

private func updateLayerFrames() {
    if backgroundLayer.frame != bounds {
        backgroundLayer.frame = bounds
    }

    if itemsLayer.frame != bounds {
        itemsLayer.frame = bounds
    }

    if overlayLayer.frame != bounds {
        overlayLayer.frame = bounds
    }
}

private func performWithoutLayerActions(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}
```

## 结果说明

- 第一轮修改解决的是输入层问题：绕过 `UIPanGestureRecognizer` 的系统滞后，让单指拖动从 raw touch 直接驱动画布平移。
- 第二轮修改解决的是渲染层问题：避免 `CALayer` 在高频位置同步时出现隐式动画，同时减少纯平移时的无效属性提交。
- 两轮结合后，拖动的“起步迟滞”和“画面追手”分别从输入层和图层层面被拆开处理，最终恢复到当前可接受的跟手状态。

## 验证结果

- 使用完整 Xcode 工具链执行 iOS Simulator 构建验证，构建通过。
- 使用完整 Xcode 工具链执行 macOS 构建验证，构建通过。
- 本次只新增记录文件，未提交 Git Commit。
