# 20260320_174327_canvas_workspace_phase6_preview_alignment_record

## 记录范围

- 记录内容：
  1. 新增 `CanvasWorkspacePalette`，把 workspace 背景色、主/次网格色、白色 board surface 统一收敛到 shared palette。
  2. 将 `macOSCanvasViewportView` 与 `iOSCanvasViewportView` 改为消费 shared palette，去掉各自内联的 workspace 色值。
  3. 将 `macOSCanvasMiniMapView` / `iOSCanvasMiniMapView` / `macOSBoardPreviewView` / `iOSBoardPreviewView` 从“系统背景 + 橙色 board 描边”切换为“深色 workspace 背景 + 白色 board surface”。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasWorkspacePalette.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - `BoardPreviewRenderer` / `BoardThumbnailRenderer` 的栅格绘制逻辑改动
  - 主画布网格几何算法改动

## 修改一：新增 shared palette，消除 workspace 色值的多点散落

### 修改前

- `macOSCanvasViewportView` 与 `iOSCanvasViewportView` 都在各自类型内部重复定义一套相同的 workspace 背景色、主/次网格色、白色 board surface。
- 如果阶段 6 继续扩散到 minimap / preview，这种结构只会继续复制 RGB 字面量，无法从根因上保证各入口视觉一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: macOSCanvasViewportView
// 功能说明: 修改前 macOS 主画布把 workspace 相关颜色常量直接写在视图类型内部，其他入口无法复用这一份视觉基准。
final class macOSCanvasViewportView: NSView {
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
    // ... 省略未改动常量 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: iOSCanvasViewportView
// 功能说明: 修改前 iOS 主画布同样在视图类型内部重复声明同一套 workspace 颜色常量，和 macOS 形成平行复制。
final class iOSCanvasViewportView: UIView {
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
    // ... 省略未改动常量 ...
}
```

### 修改后

- 新增 `CanvasWorkspacePalette` 作为 shared 颜色真源。
- 双端主画布只保留引用，不再各自内联色值。
- minimap / board preview 也可以直接复用同一套颜色语义，而不是再复制一遍字面量。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasWorkspacePalette.swift
// 函数名/类型名: CanvasWorkspacePalette
// 功能说明: 修改后 shared palette 统一承载 workspace 背景、主次网格与白色 board surface 的颜色定义，作为主画布、minimap、preview 的共同视觉基准。
import CoreGraphics

enum CanvasWorkspacePalette {
    static let backgroundColor = CGColor(
        red: 28.0 / 255.0,
        green: 29.0 / 255.0,
        blue: 31.0 / 255.0,
        alpha: 1
    )

    static let minorGridStrokeColor = CGColor(
        red: 58.0 / 255.0,
        green: 60.0 / 255.0,
        blue: 64.0 / 255.0,
        alpha: 0.72
    )

    static let majorGridStrokeColor = CGColor(
        red: 84.0 / 255.0,
        green: 87.0 / 255.0,
        blue: 93.0 / 255.0,
        alpha: 0.9
    )

    static let boardSurfaceFillColor = CGColor(gray: 1, alpha: 1)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: macOSCanvasViewportView
// 功能说明: 修改后 macOS 主画布不再持有重复色值，而是改为消费 shared palette，避免 workspace 主题在不同入口发生漂移。
final class macOSCanvasViewportView: NSView {
    private static let workspaceBackgroundColor = CanvasWorkspacePalette.backgroundColor
    private static let workspaceMinorGridStrokeColor = CanvasWorkspacePalette.minorGridStrokeColor
    private static let workspaceMajorGridStrokeColor = CanvasWorkspacePalette.majorGridStrokeColor
    private static let workspaceMinorGridLineWidth: CGFloat = 1
    private static let workspaceMajorGridLineWidth: CGFloat = 1
    private static let boardSurfaceFillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    // ... 省略未改动常量 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: iOSCanvasViewportView
// 功能说明: 修改后 iOS 主画布与 macOS 一样改为依赖 shared palette，双端 workspace 颜色语义收敛为同一份定义。
final class iOSCanvasViewportView: UIView {
    private static let workspaceBackgroundColor = CanvasWorkspacePalette.backgroundColor
    private static let workspaceMinorGridStrokeColor = CanvasWorkspacePalette.minorGridStrokeColor
    private static let workspaceMajorGridStrokeColor = CanvasWorkspacePalette.majorGridStrokeColor
    private static let workspaceMinorGridLineWidth: CGFloat = 1
    private static let workspaceMajorGridLineWidth: CGFloat = 1
    private static let boardSurfaceFillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    // ... 省略未改动常量 ...
}
```

## 修改二：统一 minimap 的 board 视觉，去掉旧橙色描边

### 修改前

- 双端 minimap 的 `boardLayer` 都还是“浅色半透明填充 + 橙色描边”。
- minimap 容器背景依然跟随系统背景，而不是主画布已经建立好的深色 workspace 背景。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改前 macOS minimap 的 board 仍是旧的橙色高亮语义，背景也仍然使用系统窗口背景。
private func setupLayers() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.masksToBounds = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(occupancyLayer)
    layer?.addSublayer(viewportLayer)

    boardLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
    boardLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75).cgColor
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = NSColor.systemGray.cgColor
    occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
    occupancyLayer.lineWidth = 1

    viewportLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
    viewportLayer.strokeColor = NSColor.systemBlue.cgColor
    viewportLayer.lineWidth = Self.viewportLineWidth

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
    layer?.borderWidth = Self.borderWidth
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改前 iOS minimap 和 macOS 一样仍沿用旧的橙色 board 描边，容器底色也没有和主画布对齐。
private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = false
    isUserInteractionEnabled = true
    layer.cornerRadius = Self.cornerRadius
    layer.masksToBounds = true
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(occupancyLayer)
    layer.addSublayer(viewportLayer)
    tapGestureRecognizer.require(toFail: panGestureRecognizer)
    addGestureRecognizer(tapGestureRecognizer)
    addGestureRecognizer(panGestureRecognizer)

    boardLayer.fillColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55).cgColor
    boardLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.75).cgColor
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = UIColor.systemGray.cgColor
    occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
    occupancyLayer.lineWidth = 1

    viewportLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
    viewportLayer.strokeColor = UIColor.systemBlue.cgColor
    viewportLayer.lineWidth = Self.viewportLineWidth

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92).cgColor
    layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
    layer.borderWidth = Self.borderWidth
}
```

### 修改后

- 双端 minimap 的 `boardLayer` 都改成白色 `board surface`，不再绘制橙色 stroke。
- minimap 容器背景统一切到 `CanvasWorkspacePalette.backgroundColor`。
- 这样 minimap 终于和主画布共享同一套“深色 workspace + 白色 board”视觉语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改后 macOS minimap 直接复用 shared palette，把 board 视觉切换为白色画布，并让容器背景与主画布 workspace 对齐。
private func setupLayers() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.masksToBounds = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(occupancyLayer)
    layer?.addSublayer(viewportLayer)

    boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    boardLayer.strokeColor = nil
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = NSColor.systemGray.cgColor
    occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
    occupancyLayer.lineWidth = 1

    viewportLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
    viewportLayer.strokeColor = NSColor.systemBlue.cgColor
    viewportLayer.lineWidth = Self.viewportLineWidth

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
    layer?.borderWidth = Self.borderWidth
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改后 iOS minimap 和 macOS 一样使用 shared palette，board 改成白色 surface，背景改成深色 workspace 底。
private func setupLayers() {
    backgroundColor = .clear
    clipsToBounds = false
    isUserInteractionEnabled = true
    layer.cornerRadius = Self.cornerRadius
    layer.masksToBounds = true
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(occupancyLayer)
    layer.addSublayer(viewportLayer)
    tapGestureRecognizer.require(toFail: panGestureRecognizer)
    addGestureRecognizer(tapGestureRecognizer)
    addGestureRecognizer(panGestureRecognizer)

    boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    boardLayer.strokeColor = nil
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = UIColor.systemGray.cgColor
    occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
    occupancyLayer.lineWidth = 1

    viewportLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
    viewportLayer.strokeColor = UIColor.systemBlue.cgColor
    viewportLayer.lineWidth = Self.viewportLineWidth

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
    layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
    layer.borderWidth = Self.borderWidth
}
```

## 修改三：统一 board preview 的 board 视觉，列表缩略图也切到白色画布语义

### 修改前

- 双端 board preview 的 `boardLayer` 仍然使用旧的橙色描边。
- 即使主画布已经变成“深色 workspace + 白色画布”，列表里的 preview 卡片仍旧会暴露旧视觉语言。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改前 macOS board preview 仍然用橙色描边强调 board 边界，容器背景也还是系统窗口背景。
private func setupLayers() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.masksToBounds = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(imageLayer)
    layer?.addSublayer(occupancyLayer)

    imageLayer.contentsGravity = .resizeAspectFill

    boardLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
    boardLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75).cgColor
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = NSColor.systemGray.cgColor
    occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
    occupancyLayer.lineWidth = 1

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
    layer?.borderWidth = Self.borderWidth
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改前 iOS board preview 同样沿用旧的橙色 board 描边，和主画布新视觉存在明显割裂。
private func setupLayers() {
    backgroundColor = .clear
    layer.cornerRadius = Self.cornerRadius
    layer.masksToBounds = true
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(imageLayer)
    layer.addSublayer(occupancyLayer)

    imageLayer.contentsGravity = .resizeAspectFill

    boardLayer.fillColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55).cgColor
    boardLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.75).cgColor
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = UIColor.systemGray.cgColor
    occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
    occupancyLayer.lineWidth = 1

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92).cgColor
    layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
    layer.borderWidth = Self.borderWidth
}
```

### 修改后

- 双端 board preview 都改成白色 `board surface`，彻底去掉橙色描边。
- preview 容器背景也改为 shared 深色 workspace 背景。
- 这样 board list 的缩略图入口和主画布、minimap 处于同一套视觉语言下。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改后 macOS board preview 复用 shared palette，列表缩略图容器也切到深色 workspace + 白色画布语义。
private func setupLayers() {
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.masksToBounds = true
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(imageLayer)
    layer?.addSublayer(occupancyLayer)

    imageLayer.contentsGravity = .resizeAspectFill

    boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    boardLayer.strokeColor = nil
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = NSColor.systemGray.cgColor
    occupancyLayer.strokeColor = NSColor.systemGray.withAlphaComponent(0.85).cgColor
    occupancyLayer.lineWidth = 1

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
    layer?.borderWidth = Self.borderWidth
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: setupLayers() / updateAppearance()
// 功能说明: 修改后 iOS board preview 和 macOS 一样统一切到 shared palette，去掉橙色 board 视觉遗留。
private func setupLayers() {
    backgroundColor = .clear
    layer.cornerRadius = Self.cornerRadius
    layer.masksToBounds = true
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(imageLayer)
    layer.addSublayer(occupancyLayer)

    imageLayer.contentsGravity = .resizeAspectFill

    boardLayer.fillColor = CanvasWorkspacePalette.boardSurfaceFillColor
    boardLayer.strokeColor = nil
    boardLayer.lineWidth = Self.boardLineWidth

    occupancyLayer.fillColor = UIColor.systemGray.cgColor
    occupancyLayer.strokeColor = UIColor.systemGray2.cgColor
    occupancyLayer.lineWidth = 1

    updateAppearance()
}

private func updateAppearance() {
    backgroundLayer.backgroundColor = CanvasWorkspacePalette.backgroundColor
    layer.borderColor = UIColor.separator.withAlphaComponent(0.75).cgColor
    layer.borderWidth = Self.borderWidth
}
```

## 校验说明

- 已对本阶段修改的 7 个源码文件执行 lint 检查，未发现新增 lint 错误。
- 已在 `Platform/macOS/Canvas`、`Platform/iOS/Canvas`、`Platform/macOS/BoardList`、`Platform/iOS/BoardList` 范围内搜索旧的橙色 board 视觉 token，未发现 `systemOrange` 残留。
- 本阶段未运行完整 Xcode build，因此这里记录的是代码级和静态检查级确认结果。
