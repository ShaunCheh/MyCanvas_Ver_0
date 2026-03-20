# 20260320_173039_canvas_workspace_phase4_ios_viewport_workspace_chrome_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 中把主画布层级从“系统白底 + 橙色虚线 board highlight”迁移为“黑灰工作区 + 网格层 + 白色 board surface + items + overlay”。
  2. 让 `iOS` 视口开始直接消费 shared 的 `workspaceOverlay`，绘制 `minorGridSegments` / `majorGridSegments` 与白色 board surface。
  3. 保留 `pinch`、`long press`、触摸跟踪等交互链路不变，只替换背景与 board 表达语义。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本记录不包含：
  - `macOSCanvasViewportView` 的阶段 3 改动
  - minimap / board preview 的视觉统一
  - 原始 gif diff
  - git commit / push

## 修改一：重构 iOS viewport 层树，从 board highlight 改为 workspace chrome 分层

### 修改前

- `iOSCanvasViewportView` 的主层级只有：
  - `backgroundLayer`
  - `itemsLayer`
  - `overlayLayer`
- `boardHighlightLayer` 挂在 `overlayLayer` 内，因此 board 只能表现为浮在内容上方的一圈橙色虚线。
- 这种结构不适合承载“白色画布表面”，因为白板应该位于 `itemsLayer` 下方，而不是和选择框一样位于 overlay 内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改前 iOS viewport 只有 background/items/overlay 三层，boardHighlightLayer 挂在 overlay 内部，只适合橙色虚线高亮而不适合白色 board surface。
private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = true
    isMultipleTouchEnabled = true

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
    addGestureRecognizer(pinchGestureRecognizer)
    addGestureRecognizer(longPressGestureRecognizer)

    configureBoardHighlightLayer()
    configureSelectionOutlineLayer()
    configureInteractionOverlayLayer()
    // ... 省略未改动配置 ...
}
```

### 修改后

- `iOS` 视口新增：
  - `workspaceGridLayer`
  - `workspaceMinorGridLayer`
  - `workspaceMajorGridLayer`
  - `boardSurfaceLayer`
- 新层级顺序改为：
  - `backgroundLayer`
  - `workspaceGridLayer`
  - `boardSurfaceLayer`
  - `itemsLayer`
  - `overlayLayer`
- `pinchGestureRecognizer` 和 `longPressGestureRecognizer` 仍在原位置注册，不改变 iOS 的触摸交互入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改后 iOS viewport 显式拆出工作区网格层和白色 board surface 层，让图片内容位于白板之上，触摸交互仍沿用原有 gesture wiring。
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

    configureWorkspaceGridLayers()
    configureBoardSurfaceLayer()
    configureSelectionOutlineLayer()
    configureInteractionOverlayLayer()
    // ... 省略未改动配置 ...
}
```

## 修改二：把背景和 board 语义从系统白底 + 橙色虚线切换为黑灰工作区 + 白色表面

### 修改前

- `updateBackgroundAppearance()` 使用 `UIColor.systemBackground`，背景就是系统白底/浅底。
- `configureBoardHighlightLayer()` 仍然把 board 定义为：
  - `fillColor = nil`
  - `strokeColor = boardStrokeColor`
  - `lineDashPattern = [10, 6]`
- 这导致 iOS 端和旧 macOS 一样，只能表现一个橙色虚线矩形，而不是一个真正的白色画布面。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: updateBackgroundAppearance() / configureBoardHighlightLayer()
// 功能说明: 修改前背景沿用系统背景色，board 仍通过橙色虚线描边表示，无法形成黑灰工作区 + 白色画布的视觉层级。
private func updateBackgroundAppearance() {
    backgroundLayer.backgroundColor = UIColor.systemBackground.cgColor
}

private func configureBoardHighlightLayer() {
    boardHighlightLayer.fillColor = nil
    boardHighlightLayer.strokeColor = Self.boardStrokeColor
    boardHighlightLayer.lineWidth = 2
    boardHighlightLayer.lineDashPattern = [10, 6]
    boardHighlightLayer.isHidden = true
}
```

### 修改后

- 新增：
  - `workspaceBackgroundColor`
  - `workspaceMinorGridStrokeColor`
  - `workspaceMajorGridStrokeColor`
  - `boardSurfaceFillColor`
- 背景改为黑灰色工作区。
- `configureWorkspaceGridLayers()` 负责配置 minor / major grid 两层。
- `configureBoardSurfaceLayer()` 负责配置白色 board surface。
- 旧的 `configureBoardHighlightLayer()` 已从 iOS 视口移除。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: updateBackgroundAppearance() / configureWorkspaceGridLayers() / configureBoardSurfaceLayer()
// 功能说明: 修改后 iOS 端把背景切换为黑灰工作区底色，用独立的 minor/major grid 层和白色 board surface 层替代旧的橙色虚线 highlight。
private static let workspaceBackgroundColor = CGColor(
    red: 28.0 / 255.0,
    green: 29.0 / 255.0,
    blue: 31.0 / 255.0,
    alpha: 1
)
private static let workspaceMinorGridStrokeColor = CGColor(
    red: 58.0 / 255.0,
    green: 60.0 / 255.0,
    blue: 64.0 / 255.0,
    alpha: 0.72
)
private static let workspaceMajorGridStrokeColor = CGColor(
    red: 84.0 / 255.0,
    green: 87.0 / 255.0,
    blue: 93.0 / 255.0,
    alpha: 0.9
)
private static let boardSurfaceFillColor = CGColor(gray: 1, alpha: 1)

private func updateBackgroundAppearance() {
    backgroundLayer.backgroundColor = Self.workspaceBackgroundColor
}

private func configureWorkspaceGridLayers() {
    workspaceGridLayer.masksToBounds = true

    workspaceMinorGridLayer.fillColor = nil
    workspaceMinorGridLayer.strokeColor = Self.workspaceMinorGridStrokeColor
    workspaceMinorGridLayer.lineWidth = Self.workspaceMinorGridLineWidth
    workspaceMinorGridLayer.isHidden = true

    workspaceMajorGridLayer.fillColor = nil
    workspaceMajorGridLayer.strokeColor = Self.workspaceMajorGridStrokeColor
    workspaceMajorGridLayer.lineWidth = Self.workspaceMajorGridLineWidth
    workspaceMajorGridLayer.isHidden = true
}

private func configureBoardSurfaceLayer() {
    boardSurfaceLayer.fillColor = Self.boardSurfaceFillColor
    boardSurfaceLayer.strokeColor = nil
    boardSurfaceLayer.isHidden = true
}
```

## 修改三：iOS viewport 从读取 boardOverlay 改为消费 workspaceOverlay

### 修改前

- `didMoveToWindow()` 和 `apply(_:)` 都调用 `refreshBoardHighlight()`。
- `refreshBoardHighlight()` 只读取 `snapshot.boardOverlay`，然后把 board 画成一圈橙色虚线。
- 这说明在修改前，iOS 端虽然已经拿到了 shared 的 `workspaceOverlay` 契约，但完全没有接入消费。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshBoardHighlight()
// 功能说明: 修改前 iOS viewport 仍只消费旧 boardOverlay，把 board 渲染成橙色虚线矩形，尚未接入 shared 的 workspaceOverlay。
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

- `didMoveToWindow()` 和 `apply(_:)` 都切换为调用 `refreshWorkspaceChrome()`。
- `refreshWorkspaceChrome()` 直接读取 `snapshot.workspaceOverlay`：
  - 用 `boardSurfaceScreenRect` 绘制白色 board surface
  - 用 `minorGridSegments` / `majorGridSegments` 绘制工作区网格
- 新增 `hideWorkspaceChrome()` 和 `workspaceGridPath(...)`，作为 iOS 端的专用辅助函数。
- iOS 视口已不再直接读取 `snapshot.boardOverlay`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshWorkspaceChrome() / hideWorkspaceChrome() / workspaceGridPath(...)
// 功能说明: 修改后 iOS viewport 开始直接消费 shared 的 workspaceOverlay，用白色 board surface 和 major/minor grid segments 组装新的工作区视觉。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshWorkspaceChrome()
        refreshEditOverlay()
        refreshInteractionOverlay()
    }
}

private func refreshWorkspaceChrome() {
    guard let workspaceOverlay = snapshot.workspaceOverlay else {
        hideWorkspaceChrome()
        return
    }

    let boardSurfaceRect = workspaceOverlay.boardSurfaceScreenRect.standardized
    if boardSurfaceRect.width > 0, boardSurfaceRect.height > 0 {
        boardSurfaceLayer.path = CGPath(
            rect: boardSurfaceRect,
            transform: nil
        )
        boardSurfaceLayer.isHidden = false
        boardSurfaceLayer.contentsScale = currentContentsScale
    } else {
        boardSurfaceLayer.path = nil
        boardSurfaceLayer.isHidden = true
    }

    if workspaceOverlay.minorGridSegments.isEmpty {
        workspaceMinorGridLayer.path = nil
        workspaceMinorGridLayer.isHidden = true
    } else {
        workspaceMinorGridLayer.path = Self.workspaceGridPath(
            workspaceOverlay.minorGridSegments
        )
        workspaceMinorGridLayer.isHidden = false
        workspaceMinorGridLayer.contentsScale = currentContentsScale
    }

    if workspaceOverlay.majorGridSegments.isEmpty {
        workspaceMajorGridLayer.path = nil
        workspaceMajorGridLayer.isHidden = true
    } else {
        workspaceMajorGridLayer.path = Self.workspaceGridPath(
            workspaceOverlay.majorGridSegments
        )
        workspaceMajorGridLayer.isHidden = false
        workspaceMajorGridLayer.contentsScale = currentContentsScale
    }

    workspaceGridLayer.isHidden = workspaceOverlay.minorGridSegments.isEmpty &&
        workspaceOverlay.majorGridSegments.isEmpty
}

private func hideWorkspaceChrome() {
    workspaceGridLayer.isHidden = true

    workspaceMinorGridLayer.path = nil
    workspaceMinorGridLayer.isHidden = true

    workspaceMajorGridLayer.path = nil
    workspaceMajorGridLayer.isHidden = true

    boardSurfaceLayer.path = nil
    boardSurfaceLayer.isHidden = true
}

private static func workspaceGridPath(
    _ segments: [CanvasWorkspaceGridLineSegment]
) -> CGPath {
    let path = CGMutablePath()

    for segment in segments {
        path.move(to: segment.start)
        path.addLine(to: segment.end)
    }

    return path
}
```

## 修改四：同步扩展 frame 刷新逻辑，保证 iOS resize / layout 后 workspace chrome 正确覆盖

### 修改前

- `updateLayerFrames()` 只同步旧的背景、内容、overlay 和 `boardHighlightLayer`。
- 在没有 workspace grid 和 board surface 的前提下，这套逻辑不足以支撑新的工作区层树。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: updateLayerFrames()
// 功能说明: 修改前 frame 刷新只覆盖旧背景层、内容层、overlay 层和 boardHighlightLayer，没有 workspace grid 与 board surface 的布局同步逻辑。
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

    if boardHighlightLayer.frame != bounds {
        boardHighlightLayer.frame = bounds
    }

    if selectionOutlineLayer.frame != bounds {
        selectionOutlineLayer.frame = bounds
    }
    // ... 省略未改动代码 ...
}
```

### 修改后

- `updateLayerFrames()` 新增了以下层的同步：
  - `workspaceGridLayer`
  - `workspaceMinorGridLayer`
  - `workspaceMajorGridLayer`
  - `boardSurfaceLayer`
- 这样在 `layoutSubviews()` 之后，新的工作区网格和白色画布都能稳定覆盖当前 `bounds`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: updateLayerFrames()
// 功能说明: 修改后 frame 刷新新增 workspace grid 与 board surface 的同步逻辑，确保 iOS 端在 layout 和旋转后仍能正确覆盖新的工作区层树。
private func updateLayerFrames() {
    if backgroundLayer.frame != bounds {
        backgroundLayer.frame = bounds
    }

    if workspaceGridLayer.frame != bounds {
        workspaceGridLayer.frame = bounds
    }

    if workspaceMinorGridLayer.frame != bounds {
        workspaceMinorGridLayer.frame = bounds
    }

    if workspaceMajorGridLayer.frame != bounds {
        workspaceMajorGridLayer.frame = bounds
    }

    if boardSurfaceLayer.frame != bounds {
        boardSurfaceLayer.frame = bounds
    }

    if itemsLayer.frame != bounds {
        itemsLayer.frame = bounds
    }

    if overlayLayer.frame != bounds {
        overlayLayer.frame = bounds
    }

    if selectionOutlineLayer.frame != bounds {
        selectionOutlineLayer.frame = bounds
    }
    // ... 省略未改动代码 ...
}
```

## 阶段结果

- `iOSCanvasViewportView` 已经和 `macOSCanvasViewportView` 对齐到同一套 workspace chrome 结构。
- 当前 iOS 主画布具备以下视觉层：
  - 黑灰工作区背景
  - major/minor 网格
  - 白色 board surface
  - 图片内容
  - 选择/裁剪/旋转 overlay
- `pinch`、`long press`、触摸拖拽这些交互通路本次没有改变语义，只是继续运行在新的层树之上。

## 验证情况

- 已对 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 运行诊断检查，没有新增 lint 问题。
- 已确认该文件中不再存在以下旧路径：
  - `boardHighlight`
  - `refreshBoardHighlight`
  - `boardStrokeColor`
  - `boardOverlay`
- 已确认 `iOS` 侧现在只消费 `snapshot.workspaceOverlay`，不再直接读取旧 `snapshot.boardOverlay`。

## 下一阶段输入

- 下一阶段将进入阶段 5，开始清理 shared 与双端里遗留的 `boardOverlay` / `boardHighlight` 旧语义，并做一轮收口与回归检查。
