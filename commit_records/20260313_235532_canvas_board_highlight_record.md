# 20260313_235532_canvas_board_highlight_record

## 记录范围

- 记录内容：为逻辑画布范围新增独立的 `CanvasBoardState`，并在 iOS/macOS 画布视口中高亮显示当前画布边界。
- 目标：保持当前 `Scene + Camera + Renderer + Viewport` 架构不变，不把 board 状态塞进 `CanvasScene` 或平台 view，而是通过 `renderer -> snapshot -> viewport` 统一渲染。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`、`MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`、`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`、`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`。
- 本次未包含：画布范围收缩、多选板块、空白点击取消选中、提交 Git Commit。

## 变更 1：新增独立的 `CanvasBoardState`，承载逻辑画布范围

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift
// 函数名: CanvasBoardState / init(baseSize:centeredAt:) / expandIfNeeded(toInclude:)
// 功能说明: 修改前该文件不存在，逻辑画布范围没有独立的共享状态模型。
// 修改前: 文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardState.swift
// 函数名: CanvasBoardState / init(baseSize:centeredAt:) / expandIfNeeded(toInclude:)
// 功能说明: 修改后引入独立的 board 状态，记录基础尺寸和当前 worldRect，并按左右上下四个方向整块扩张。
import CoreGraphics
import Foundation

struct CanvasBoardState {
    let baseSize: CGSize
    private(set) var worldRect: CGRect

    init(
        baseSize: CGSize,
        centeredAt center: CGPoint = .zero
    ) {
        let sanitizedBaseSize = CGSize(
            width: max(baseSize.width, 1),
            height: max(baseSize.height, 1)
        )
        self.baseSize = sanitizedBaseSize
        worldRect = CGRect(
            x: center.x - sanitizedBaseSize.width / 2,
            y: center.y - sanitizedBaseSize.height / 2,
            width: sanitizedBaseSize.width,
            height: sanitizedBaseSize.height
        )
    }

    @discardableResult
    mutating func expandIfNeeded(toInclude worldFrame: CGRect) -> Bool {
        let standardizedFrame = worldFrame.standardized
        var didExpand = false

        while standardizedFrame.minX < worldRect.minX {
            worldRect.origin.x -= baseSize.width
            worldRect.size.width += baseSize.width
            didExpand = true
        }

        while standardizedFrame.maxX > worldRect.maxX {
            worldRect.size.width += baseSize.width
            didExpand = true
        }

        while standardizedFrame.minY < worldRect.minY {
            worldRect.origin.y -= baseSize.height
            worldRect.size.height += baseSize.height
            didExpand = true
        }

        while standardizedFrame.maxY > worldRect.maxY {
            worldRect.size.height += baseSize.height
            didExpand = true
        }

        return didExpand
    }
}
```

## 变更 2：把画布范围高亮并入统一渲染快照

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderSnapshot / empty
// 功能说明: 修改前快照只包含 viewport、visibleWorldRect 和图片 items，没有 board overlay。
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

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:camera:interactionState:)
// 功能说明: 修改前 renderer 只渲染图片 item，无法把逻辑画布范围转成屏幕空间高亮信息。
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

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasBoardRenderOverlay / CanvasRenderSnapshot / empty
// 功能说明: 修改后快照新增 boardOverlay，统一承接逻辑画布范围的 world-space 与 screen-space 渲染结果。
struct CanvasBoardRenderOverlay {
    let worldRect: CGRect
    let screenRect: CGRect
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: []
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:)
// 功能说明: 修改后 renderer 会把 CanvasBoardState.worldRect 转成 screenRect，并作为 boardOverlay 放进统一快照。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
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

    let boardOverlay = boardState.map { boardState in
        CanvasBoardRenderOverlay(
            worldRect: boardState.worldRect,
            screenRect: camera.worldToViewport(boardState.worldRect)
        )
    }

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems
    )
}
```

## 变更 3：iOS viewport 在 overlayLayer 上绘制画布范围高亮

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers() / apply(_:) / updateLayerFrames() / performWithoutLayerActions(_:)
// 功能说明: 修改前 iOS 视口只有 background/items/overlay 三层，但 overlay 没有专门的 board 高亮子层。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
    }
}

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
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers() / apply(_:) / updateLayerFrames() / configureBoardHighlightLayer() / refreshBoardHighlight()
// 功能说明: 修改后 iOS 视口在 overlayLayer 下新增 CAShapeLayer，用来绘制逻辑画布边界高亮框。
private static let boardStrokeColor = CGColor(
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 0.9
)

private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
    }
}

private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = true
    isMultipleTouchEnabled = true

    layer.addSublayer(backgroundLayer)
    layer.addSublayer(itemsLayer)
    layer.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)
    addGestureRecognizer(pinchGestureRecognizer)

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func configureBoardHighlightLayer() {
    boardHighlightLayer.fillColor = nil
    boardHighlightLayer.strokeColor = Self.boardStrokeColor
    boardHighlightLayer.lineWidth = 2
    boardHighlightLayer.lineDashPattern = [10, 6]
    boardHighlightLayer.isHidden = true
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

## 变更 4：iOS 控制器持有 `CanvasBoardState`，并在导图/拖图后触发扩张

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性区 / syncCameraViewportSizeIfNeeded(_:source:) / performCanvasRefresh(reason:) / appendImportedImage(_:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 controller 没有 boardState；刷新只消费 scene 和 camera；导图和拖图都不会推动逻辑画布范围扩张。
private var pendingRefreshReason: String?
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

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
    // ... more code ...
}

private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}

private func appendImportedImage(_ cgImage: CGImage) {
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    requestCanvasRefresh(
        reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
    )
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... deltaInWorld 计算 ...
    scene.moveItem(withID: itemID, by: deltaInWorld)
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性区 / syncCameraViewportSizeIfNeeded(_:source:) / syncCameraViewportSizeFromCurrentBoundsIfPossible() / performCanvasRefresh(reason:) / appendImportedImage(_:) / moveSelectedItem(withID:from:to:) / expandBoardIfNeeded(toInclude:) / configureBoardStateIfNeeded(for:)
// 功能说明: 修改后 controller 持有 boardState，在首次拿到有效 viewport 时初始化基础画布尺寸；导图和拖图都会按 worldFrame 推动画布范围扩张。
private var pendingRefreshReason: String?
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

private func syncCameraViewportSizeIfNeeded(
    _ viewportSize: CGSize,
    source: String
) {
    guard isRenderable(viewportSize: viewportSize) else {
        return
    }

    let sizeChanged = viewportSize != camera.viewportSize
    let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
    let deferredReason = pendingRefreshReason
    guard sizeChanged || deferredReason != nil || didConfigureBoardState else {
        return
    }

    if sizeChanged {
        camera.setViewportSize(viewportSize)
    }
    // ... more code ...
}

private func syncCameraViewportSizeFromCurrentBoundsIfPossible() {
    let viewportSize = canvasViewportView.bounds.size
    guard
        isRenderable(viewportSize: viewportSize),
        viewportSize != camera.viewportSize
    else {
        return
    }

    camera.setViewportSize(viewportSize)
    _ = configureBoardStateIfNeeded(for: viewportSize)
}

private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}

private func appendImportedImage(_ cgImage: CGImage) {
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    requestCanvasRefresh(
        reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
    )
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... deltaInWorld 计算 ...
    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.item(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldFrame)
    }
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
}

private func expandBoardIfNeeded(toInclude worldFrame: CGRect) {
    guard var boardState else {
        return
    }

    if boardState.expandIfNeeded(toInclude: worldFrame) {
        self.boardState = boardState
    }
}

private func configureBoardStateIfNeeded(for viewportSize: CGSize) -> Bool {
    guard boardState == nil else {
        return false
    }

    boardState = CanvasBoardState(
        baseSize: viewportSize,
        centeredAt: camera.center
    )
    return true
}
```

## 变更 5：macOS 侧同步接入 board 高亮和扩张链路

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / apply(_:)
// 功能说明: 修改前 macOS 视口没有 board 高亮子层，只会刷新图片 layer。
private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 属性区 / updateCameraViewportSizeIfNeeded() / refreshCanvas() / appendImportedImage(_:) / moveSelectedItem(withID:from:to:)
// 功能说明: 修改前 macOS controller 没有 boardState，也不会在导图和拖图后扩张逻辑画布范围。
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

private func updateCameraViewportSizeIfNeeded() {
    let viewportSize = canvasViewportView.bounds.size
    guard viewportSize != camera.viewportSize else {
        return
    }

    camera.setViewportSize(viewportSize)
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

private func appendImportedImage(_ cgImage: CGImage) {
    // ... build item ...
    scene.append(item)
    refreshCanvas()
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... deltaInWorld 计算 ...
    scene.moveItem(withID: itemID, by: deltaInWorld)
    refreshCanvas()
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / apply(_:) / configureBoardHighlightLayer() / refreshBoardHighlight()
// 功能说明: 修改后 macOS 视口也通过 overlayLayer 下的 CAShapeLayer 画出逻辑画布边界高亮。
private static let boardStrokeColor = CGColor(
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 0.9
)

private let backgroundLayer = CALayer()
private let itemsLayer = CALayer()
private let overlayLayer = CALayer()
private let boardHighlightLayer = CAShapeLayer()

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

    backgroundLayer.isGeometryFlipped = true
    itemsLayer.isGeometryFlipped = true
    overlayLayer.isGeometryFlipped = true
    boardHighlightLayer.isGeometryFlipped = true

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func configureBoardHighlightLayer() {
    boardHighlightLayer.fillColor = nil
    boardHighlightLayer.strokeColor = Self.boardStrokeColor
    boardHighlightLayer.lineWidth = 2
    boardHighlightLayer.lineDashPattern = [10, 6]
    boardHighlightLayer.isHidden = true
}

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.isHidden = true
        return
    }

    boardHighlightLayer.path = CGPath(rect: boardOverlay.screenRect, transform: nil)
    boardHighlightLayer.isHidden = false
    boardHighlightLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 属性区 / updateCameraViewportSizeIfNeeded() / refreshCanvas() / appendImportedImage(_:) / moveSelectedItem(withID:from:to:) / expandBoardIfNeeded(toInclude:) / configureBoardStateIfNeeded(for:)
// 功能说明: 修改后 macOS controller 与 iOS 一样持有 boardState，并在有效 viewport、导图、拖图后同步扩张逻辑画布范围。
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty

private func updateCameraViewportSizeIfNeeded() {
    let viewportSize = canvasViewportView.bounds.size
    guard viewportSize.width > 0, viewportSize.height > 0 else {
        return
    }

    let sizeChanged = viewportSize != camera.viewportSize
    if sizeChanged {
        camera.setViewportSize(viewportSize)
    }

    let didConfigureBoardState = configureBoardStateIfNeeded(for: viewportSize)
    guard sizeChanged || didConfigureBoardState else {
        return
    }

    refreshCanvas()
}

private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
}

private func appendImportedImage(_ cgImage: CGImage) {
    // ... build item ...
    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    refreshCanvas()
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... deltaInWorld 计算 ...
    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.item(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldFrame)
    }
    refreshCanvas()
}

private func expandBoardIfNeeded(toInclude worldFrame: CGRect) {
    guard var boardState else {
        return
    }

    if boardState.expandIfNeeded(toInclude: worldFrame) {
        self.boardState = boardState
    }
}

private func configureBoardStateIfNeeded(for viewportSize: CGSize) -> Bool {
    guard boardState == nil else {
        return false
    }

    boardState = CanvasBoardState(
        baseSize: viewportSize,
        centeredAt: camera.center
    )
    return true
}
```

## 结果说明

- 逻辑画布范围现在有了独立的数据模型 `CanvasBoardState`，不再依赖 `CanvasScene` 或平台 view 私自持有。
- 画布范围高亮被纳入 `CanvasRenderSnapshot.boardOverlay`，和图片渲染共享同一条刷新链路。
- iOS 与 macOS 都在 `overlayLayer` 上显示画布边界高亮，且高亮会跟随相机平移与缩放。
- 当前扩张时机为：
  - 第一次拿到有效 viewport 时初始化基础画布范围
  - 图片导入后按图片 `worldFrame` 扩张
  - 拖动已选中图片后按图片最新 `worldFrame` 扩张
- 当前规则是“只扩不缩”，且支持左右上下多个方向同时扩张。

## 验证结果

- 使用完整 Xcode 工具链执行 iOS Simulator 构建验证，构建通过。
- 使用完整 Xcode 工具链执行 macOS 构建验证，构建通过。
- 本次只新增记录文件，未提交 Git Commit。
