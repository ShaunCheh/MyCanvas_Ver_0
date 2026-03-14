# 20260314_113315_fix_macos_vertical_direction_record

## 记录范围

- 记录内容：修复 macOS 画布拖动时，橙色虚线边框与图片在垂直方向解释不一致的问题，并记录中间一次错误修复为什么仍然不符合预期。
- 目标：不改共享的 `CanvasCamera` / `CanvasRenderer` 数学，只在 macOS 视口层收敛坐标语义。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`。
- 本次未包含：iOS 改动、共享 `Scene + Camera + Renderer` 架构重构、Git 提交。

## 背景与根因

- 共享层 `CanvasRenderer` 对图片和 board 输出的是同一套 `screenFrame` / `screenRect`，因此问题不在 `CanvasCamera.pan(by:)` 或 `worldToViewport(...)`。
- 原始 macOS 视口同时使用了 `NSView.isFlipped = true` 和多层 `isGeometryFlipped = true`。
- 图片通过 `CALayer.frame` 做几何放置，board 通过 `CAShapeLayer.path` 做内容绘制；`isGeometryFlipped` 会影响 layer geometry，但不会影响 layer content rendering，于是两条渲染分支对同一个 `screenY` 产生了不同解释。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / refreshBoardHighlight()
// 功能说明: 原始实现同时混用了 flipped view 和 geometryFlipped layer；图片和 board 分别走 frame 与 path 两条链路。
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

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.isHidden = true
        return
    }

    boardHighlightLayer.path = CGPath(rect: boardOverlay.screenRect, transform: nil)
    boardHighlightLayer.isHidden = false
}
```

## 第一次修改：去掉 `isGeometryFlipped`，并手动做一次 `Y` 转换

### 第一次修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / refreshImageLayers() / refreshBoardHighlight()
// 功能说明: 修改前图片直接消费共享 screenFrame；board 直接把共享 screenRect 塞进 path；同时保留多层 geometryFlipped。
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
}

private func refreshImageLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        let imageLayer = imageLayer(for: item.id)
        imageLayer.update(with: item, contentsScale: contentsScale)
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
}
```

### 第一次修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / refreshImageLayers() / refreshBoardHighlight() / layerRect(fromViewportRect:)
// 功能说明: 第一次尝试先去掉 geometryFlipped，再手工把共享 viewport rect 转成 layer rect，想统一图片与 board 的方向。
private func setupLayers() {
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func refreshImageLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        let imageLayer = imageLayer(for: item.id)
        let layerItem = CanvasRenderItem(
            id: item.id,
            screenFrame: layerRect(fromViewportRect: item.screenFrame),
            cgImage: item.cgImage,
            zIndex: item.zIndex,
            isSelected: item.isSelected
        )
        imageLayer.update(with: layerItem, contentsScale: contentsScale)
    }
}

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.isHidden = true
        return
    }

    boardHighlightLayer.path = CGPath(
        rect: layerRect(fromViewportRect: boardOverlay.screenRect),
        transform: nil
    )
    boardHighlightLayer.isHidden = false
}

private func layerRect(fromViewportRect viewportRect: CGRect) -> CGRect {
    let standardizedRect = viewportRect.standardized
    return CGRect(
        x: standardizedRect.minX,
        y: bounds.height - standardizedRect.maxY,
        width: standardizedRect.width,
        height: standardizedRect.height
    )
}
```

### 为什么第一次仍然不符合预期

- 第一次修改做对了一半：删掉 `isGeometryFlipped`，确实瞄准了原始分叉的根因之一。
- 但同时又新增了 `layerRect(fromViewportRect:)`，手工做了 `y = bounds.height - maxY` 的二次翻转。
- 当前 `macOSCanvasViewportView` 本身已经是 `isFlipped = true`，共享 `screenFrame` / `screenRect` 也是按 top-left viewport 语义产出的；此时再手工翻一次 `Y`，就把图片和 board 一起变成了错误方向。
- 所以第一次修改后的现象是：原来的“一个向上、一个向下”被改成了“两个同向”，但这个同向是同向错误。鼠标向上移动时，图片和橙色虚线框都会往下移动。

## 第二次修改：保留去掉 `isGeometryFlipped`，但去掉手工翻转，并把 board 改成和图片一致的 `frame` 放置

### 第二次修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshImageLayers() / refreshBoardHighlight() / layerRect(fromViewportRect:)
// 功能说明: 第二次修改前，代码仍然通过 layerRect(fromViewportRect:) 对图片和 board 做手工 Y 翻转。
private func refreshImageLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        let imageLayer = imageLayer(for: item.id)
        let layerItem = CanvasRenderItem(
            id: item.id,
            screenFrame: layerRect(fromViewportRect: item.screenFrame),
            cgImage: item.cgImage,
            zIndex: item.zIndex,
            isSelected: item.isSelected
        )
        imageLayer.update(with: layerItem, contentsScale: contentsScale)
    }
}

private func refreshBoardHighlight() {
    guard let boardOverlay = snapshot.boardOverlay else {
        boardHighlightLayer.path = nil
        boardHighlightLayer.isHidden = true
        return
    }

    boardHighlightLayer.path = CGPath(
        rect: layerRect(fromViewportRect: boardOverlay.screenRect),
        transform: nil
    )
    boardHighlightLayer.isHidden = false
}
```

### 第二次修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / refreshImageLayers() / refreshBoardHighlight()
// 功能说明: 第二次修改彻底去掉 geometryFlipped 与手工 Y 翻转，让图片和 board 共用同一类 frame-based placement 语义。
private func setupLayers() {
    wantsLayer = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(itemsLayer)
    layer?.addSublayer(overlayLayer)
    overlayLayer.addSublayer(boardHighlightLayer)

    configureBoardHighlightLayer()
    updateBackgroundAppearance()
}

private func refreshImageLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        let imageLayer = imageLayer(for: item.id)
        imageLayer.update(with: item, contentsScale: contentsScale)
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
}
```

### 为什么第二次能解决

- 第二次修改保留了“移除 `isGeometryFlipped`”这件正确的事情，消除了原始实现里只影响 geometry 的额外垂直翻转。
- 第二次修改同时删掉了 `layerRect(fromViewportRect:)`，不再对共享 `screenFrame` / `screenRect` 进行第二次手工 `Y` 反转。
- 更关键的是，board 不再直接把全局 `screenRect` 塞进 `CAShapeLayer.path`，而是先像图片一样通过 `frame` 放到父 layer 坐标系里，再在自己的局部坐标 `(0, 0) -> size` 内画 path。
- 这样一来，图片和 board 终于走的是同一种 geometry placement 语义：都先用 `frame` 定位，再在各自的局部坐标里渲染内容，垂直方向的解释被统一了。
- 最终结果是：macOS 上拖动画布时，图片与橙色虚线边框在上下方向恢复为同向运动；用户实测确认已经恢复正常。

## 验证记录

- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 无新增 lint 问题。
- macOS 目标使用无签名构建方式验证通过。
- 用户在 macOS 上手动验证通过，确认“ok了”。
