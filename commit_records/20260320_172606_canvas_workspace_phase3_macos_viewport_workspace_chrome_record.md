# 20260320_172606_canvas_workspace_phase3_macos_viewport_workspace_chrome_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中把主画布层级从“白色背景 + 橙色虚线 board highlight”迁移为“黑灰工作区 + 网格层 + 白色 board surface + items + overlay”。
  2. 让 `macOS` 视口开始消费 shared 的 `workspaceOverlay`，直接绘制 `minorGridSegments` / `majorGridSegments` 和白色 board surface。
  3. 从 `macOS` 视口中移除旧的橙色虚线 `boardHighlight` 渲染路径。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - `iOSCanvasViewportView` 同步迁移
  - minimap / board preview 的视觉统一
  - 原始 gif diff
  - git commit / push

## 修改一：重构 macOS viewport 层树，从 board highlight 改为 workspace chrome 分层

### 修改前

- `macOSCanvasViewportView` 的主层级只有：
  - `backgroundLayer`
  - `itemsLayer`
  - `overlayLayer`
- `boardHighlightLayer` 被挂在 `overlayLayer` 内部，因此它只能作为“画在内容上方的橙色虚线描边”，不适合作为白色 board surface。
- 这也是为什么之前只能看到白色整屏背景，而不能形成“白色画布放在黑灰网格工作区上”的视觉语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改前 viewport 只有 background/items/overlay 三层，boardHighlightLayer 挂在 overlay 内部，只能承担橙色虚线高亮描边职责。
private func setupLayers() {
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
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

    configureBoardHighlightLayer()
    configureSelectionOutlineLayer()
    configureInteractionOverlayLayer()
    // ... 省略未改动配置 ...
}
```

### 修改后

- `macOS` 视口新增：
  - `workspaceGridLayer`
  - `workspaceMinorGridLayer`
  - `workspaceMajorGridLayer`
  - `boardSurfaceLayer`
- 新层级顺序变为：
  - `backgroundLayer`
  - `workspaceGridLayer`
  - `boardSurfaceLayer`
  - `itemsLayer`
  - `overlayLayer`
- 这样 white board surface 被放到了 `itemsLayer` 下方，后续图片内容自然显示在白板上，而选择框/裁剪框/旋转交互仍维持在 overlay 里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers()
// 功能说明: 修改后 viewport 显式拆出工作区网格层和白色 board surface 层，让图片内容位于白板之上，编辑 chrome 仍位于 overlay 之上。
private func setupLayers() {
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(workspaceGridLayer)
    workspaceGridLayer.addSublayer(workspaceMinorGridLayer)
    workspaceGridLayer.addSublayer(workspaceMajorGridLayer)
    layer?.addSublayer(boardSurfaceLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
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

    configureWorkspaceGridLayers()
    configureBoardSurfaceLayer()
    configureSelectionOutlineLayer()
    configureInteractionOverlayLayer()
    // ... 省略未改动配置 ...
}
```

## 修改二：把背景和 board 高亮语义切换成 workspace 背景、网格和白色表面

### 修改前

- 背景仍然使用 `NSColor.windowBackgroundColor`。
- board 通过 `boardHighlightLayer` 渲染橙色虚线描边：
  - `fillColor = nil`
  - `strokeColor = boardStrokeColor`
  - `lineDashPattern = [10, 6]`
- 这条路径本质上表达的是“高亮框”，不是“画布表面”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: updateBackgroundAppearance() / configureBoardHighlightLayer()
// 功能说明: 修改前背景依旧是系统窗口底色，board 仍通过橙色虚线描边表达，无法形成黑灰工作区 + 白色画布的视觉层次。
private func updateBackgroundAppearance() {
    backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
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

- 新增 `workspaceBackgroundColor`、`workspaceMinorGridStrokeColor`、`workspaceMajorGridStrokeColor`、`boardSurfaceFillColor`。
- 背景改为固定黑灰色。
- 新增 `configureWorkspaceGridLayers()` 和 `configureBoardSurfaceLayer()`：
  - minor / major grid 都是独立 `CAShapeLayer`
  - board surface 只填白，不描边
- 旧的 `configureBoardHighlightLayer()` 已从 `macOS` 视口中移除。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: updateBackgroundAppearance() / configureWorkspaceGridLayers() / configureBoardSurfaceLayer()
// 功能说明: 修改后背景切换为黑灰工作区底色，board 改为白色 surface，网格拆为 minor/major 两层，完全替代旧的橙色虚线 highlight 语义。
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

## 修改三：macOS viewport 从读取 boardOverlay 改为消费 workspaceOverlay

### 修改前

- `viewDidMoveToWindow()` 和 `apply(_:)` 都会调用 `refreshBoardHighlight()`。
- `refreshBoardHighlight()` 只读取 `snapshot.boardOverlay`，把 board 画成一个橙色虚线矩形。
- 这意味着即使 shared 层已经开始产出 `workspaceOverlay`，macOS viewport 也完全没有接入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: viewDidMoveToWindow() / apply(_:) / refreshBoardHighlight()
// 功能说明: 修改前 macOS viewport 仍只消费旧 boardOverlay，把 board 画成橙色虚线矩形，尚未接入 shared 的 workspaceOverlay。
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
    boardHighlightLayer.contentsScale = currentContentsScale
}
```

### 修改后

- `viewDidMoveToWindow()` 和 `apply(_:)` 都切换为调用 `refreshWorkspaceChrome()`。
- `refreshWorkspaceChrome()` 直接读取 `snapshot.workspaceOverlay`：
  - 用 `boardSurfaceScreenRect` 绘制白色 board surface
  - 用 `minorGridSegments` / `majorGridSegments` 生成网格 path
- 新增 `hideWorkspaceChrome()` 和 `workspaceGridPath(...)` 作为专用 helper。
- `macOS` 侧已经不再直接读取 `snapshot.boardOverlay`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: viewDidMoveToWindow() / apply(_:) / refreshWorkspaceChrome() / hideWorkspaceChrome() / workspaceGridPath(...)
// 功能说明: 修改后 macOS viewport 开始直接消费 shared 的 workspaceOverlay，用 boardSurfaceScreenRect 绘制白色画布，用 major/minor grid segments 绘制工作区网格，并在无数据时统一隐藏 workspace chrome。
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
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

## 修改四：同步扩展 layer frame 刷新，保证 workspace chrome 跟随 viewport 布局

### 修改前

- `updateLayerFrames()` 只处理 `backgroundLayer`、`itemsLayer`、`overlayLayer` 和现有编辑 chrome 的 frame。
- 新增 workspace chrome 之前，根本没有 `workspaceGridLayer` / `boardSurfaceLayer` 需要同步 frame。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: updateLayerFrames()
// 功能说明: 修改前 frame 刷新只覆盖旧背景层、内容层和 overlay 层，没有 workspace grid 或 board surface 的布局同步逻辑。
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

    if selectionOutlineLayer.frame != bounds {
        selectionOutlineLayer.frame = bounds
    }
    // ... 省略未改动代码 ...
}
```

### 修改后

- `updateLayerFrames()` 现在会同时同步：
  - `workspaceGridLayer`
  - `workspaceMinorGridLayer`
  - `workspaceMajorGridLayer`
  - `boardSurfaceLayer`
- 这样视口布局变化后，工作区网格和白色画布表面都能稳定覆盖当前 bounds。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: updateLayerFrames()
// 功能说明: 修改后 frame 刷新新增 workspace grid 与 board surface 的同步逻辑，确保 viewport resize 时背景网格和白色画布都能正确覆盖新边界。
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

- `macOSCanvasViewportView` 已经从旧的橙色虚线 board highlight 模式切换到新的 workspace chrome 模式。
- 当前 `macOS` 主画布具备了这几个视觉层：
  - 黑灰工作区背景
  - major/minor 网格
  - 白色 board surface
  - 图片内容
  - 选择/裁剪/旋转 overlay
- `selection`、`crop`、`rotation` 的 overlay 渲染逻辑本次没有改语义，只是保留在新的层树上继续工作。

## 验证情况

- 已对 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 运行诊断检查，没有新增 lint 问题。
- 已确认该文件中不再存在以下旧路径：
  - `boardHighlight`
  - `refreshBoardHighlight`
  - `boardStrokeColor`
- 已确认 `macOS` 侧现在只消费 `snapshot.workspaceOverlay`，不再直接读取 `snapshot.boardOverlay`。

## 下一阶段输入

- 下一阶段将把同样的 workspace chrome 迁移到 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`，让 `iOS` 与 `macOS` 消费同一套 shared 几何并保持一致。 
