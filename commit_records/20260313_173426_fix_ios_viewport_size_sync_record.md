# 20260313_173426_fix_ios_viewport_size_sync_record

## 记录范围

- 记录内容：修复 iOS 端 `camera.viewportSize` 长期停留为 `.zero`，导致图片初始偏到左上角、继续拖动后被错误裁剪消失的问题。
- 目标：让 `iOSCanvasViewportView` 成为真实视口尺寸的上报来源，阻断零视口进入首帧渲染和交互渲染链路。
- 本次未包含：`UIScene` 生命周期升级、macOS 侧调整、提交 Git Commit。

## 变更 1：iOS viewport 在布局阶段主动上报真实尺寸

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数: layoutSubviews()
// 功能说明: 修改前 viewport 只在布局时更新自己的 layer frame，不记录也不上报真实 bounds.size。
// 这会让外层控制器继续依赖生命周期轮询，存在错过 zero -> 有效尺寸切换时机的风险。
override func layoutSubviews() {
    super.layoutSubviews()
    updateLayerFrames()
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数: layoutSubviews() / reportViewportSizeIfNeeded()
// 功能说明: 修改后 viewport 成为尺寸事实来源，在布局时比较并上报新的 bounds.size。
// 这样 iOSViewController 可以在真实尺寸出现的第一时间同步 camera.viewportSize。
private var lastReportedViewportSize: CGSize?
var onViewportSizeChange: ((CGSize) -> Void)?

override func layoutSubviews() {
    super.layoutSubviews()
    updateLayerFrames()
    reportViewportSizeIfNeeded()
}

private func reportViewportSizeIfNeeded() {
    let viewportSize = bounds.size
    guard viewportSize != lastReportedViewportSize else {
        return
    }

    lastReportedViewportSize = viewportSize
    onViewportSizeChange?(viewportSize)
}
```

## 变更 2：iOS 宿主控制器改为等待有效视口后再刷新

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: viewDidLayoutSubviews() / setupCanvasViewport() / updateCameraViewportSizeIfNeeded()
// 功能说明: 修改前 controller 在外层布局回调里轮询 canvasViewportView.bounds.size，并在安装 viewport 后立即刷新。
// 如果这一轮拿到的还是 zero 视口，那么初始渲染、图片导入和后续手势都会沿用错误的 viewportSize。
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
    refreshCanvas(reason: "initial setup")
}

private func updateCameraViewportSizeIfNeeded() {
    let viewportSize = canvasViewportView.bounds.size
    guard viewportSize != camera.viewportSize else {
        return
    }

    camera.setViewportSize(viewportSize)
    refreshCanvas(reason: "viewport size changed to \(describe(size: viewportSize))")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handlePan(_:) / handleZoom(_:around:) / refreshCanvas(reason:)
// 功能说明: 修改前 pan / zoom / 导图后的刷新都会直接进入 renderer，没有先校验 viewport 是否有效。
private func handlePan(_ translation: CGPoint) {
    camera.pan(by: translation)
    refreshCanvas(reason: "pan \(describe(point: translation))")
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    camera.zoom(by: scaleDelta, around: anchor)
    refreshCanvas(
        reason: "zoom scaleDelta=\(String(format: \"%.4f\", scaleDelta)) anchor=\(describe(point: anchor))"
    )
}

private func refreshCanvas(reason: String) {
    let snapshot = renderer.makeSnapshot(scene: scene, camera: camera)
    canvasViewportView.apply(snapshot)
    logCanvasState(reason: reason, snapshot: snapshot)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: viewDidLayoutSubviews() / setupCanvasViewport() / syncCameraViewportSizeIfNeeded(_:source:)
// 功能说明: 修改后 controller 以 viewport 回调为主同步 camera 尺寸，并保留 viewDidLayoutSubviews 作为兜底。
// 只要拿到有效尺寸，就会把之前挂起的刷新请求统一 flush，避免首帧继续带着 zero 视口渲染。
private var pendingRefreshReason: String?

override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: "controller layout fallback"
    )
}

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

private func syncCameraViewportSizeIfNeeded(
    _ viewportSize: CGSize,
    source: String
) {
    guard isRenderable(viewportSize: viewportSize) else {
        return
    }

    let sizeChanged = viewportSize != camera.viewportSize
    let deferredReason = pendingRefreshReason
    guard sizeChanged || deferredReason != nil else {
        return
    }

    if sizeChanged {
        camera.setViewportSize(viewportSize)
    }

    pendingRefreshReason = nil

    if let deferredReason {
        performCanvasRefresh(
            reason: "flush deferred refresh (\(deferredReason)) after \(source) size=\(describe(size: viewportSize))"
        )
    } else {
        performCanvasRefresh(
            reason: "viewport size changed to \(describe(size: viewportSize)) via \(source)"
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handlePan(_:) / handleZoom(_:around:) / requestCanvasRefresh(reason:)
// 功能说明: 修改后所有交互和导图后的刷新都先检查 viewport 是否有效。
// 当真实尺寸尚未到位时，刷新会被挂起；当手势发生在 zero 视口阶段时，会直接忽略，避免继续污染 camera 和 snapshot。
private func handlePan(_ translation: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pan \(describe(point: translation))")
        return
    }

    camera.pan(by: translation)
    requestCanvasRefresh(reason: "pan \(describe(point: translation))")
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "zoom scaleDelta=\(String(format: \"%.4f\", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: \"%.4f\", scaleDelta)) anchor=\(describe(point: anchor))"
    )
}

private func requestCanvasRefresh(reason: String) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        pendingRefreshReason = reason
        logDeferredCanvasRefresh(
            reason: reason,
            actualViewportSize: canvasViewportView.bounds.size
        )
        return
    }

    pendingRefreshReason = nil
    performCanvasRefresh(reason: reason)
}
```

## 变更 3：共享渲染器为零视口增加护栏

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeSnapshot(scene:camera:)
// 功能说明: 修改前 renderer 无条件使用 visibleWorldRect 做可见项裁剪。
// 当 viewportSize 为 zero 时，visibleWorldRect 会退化成零尺寸矩形，visibleItems(in:) 会把问题放大成点裁剪。
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
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数: makeSnapshot(scene:camera:)
// 功能说明: 修改后 renderer 会先判断 viewport 是否有效。
// 对于无效 zero 视口，不再走 visibleWorldRect 裁剪，而是退回 orderedItems，避免再次退化成以 camera.center 为中心的点裁剪。
func makeSnapshot(
    scene: CanvasScene,
    camera: CanvasCamera
) -> CanvasRenderSnapshot {
    let visibleWorldRect = camera.visibleWorldRect

    let visibleItems: [CanvasImageItem]
    if camera.viewportSize.width > 0, camera.viewportSize.height > 0 {
        visibleItems = scene.visibleItems(in: visibleWorldRect)
    } else {
        visibleItems = scene.orderedItems()
    }

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

## 当前结果

- `camera.viewportSize` 不再只依赖 `iOSViewController.viewDidLayoutSubviews()` 去轮询内层 view 的尺寸变化。
- `initial setup`、图片导入、`pan`、`zoom` 在拿到有效视口前不会再直接进入渲染链路。
- `CanvasRenderer` 即使再次收到 zero 视口，也不会把可见裁剪退化成“跟随 `camera.center` 的点裁剪”。

## 验证结果

- 本次改动后，`ReadLints` 未发现这 3 个修改文件的新诊断问题。
- 使用以下命令完成了一次 iOS 目标编译验证，结果为 `BUILD SUCCEEDED`。
- 验证命令：`DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS" -derivedDataPath ".build/DerivedData" CODE_SIGNING_ALLOWED=NO build`
