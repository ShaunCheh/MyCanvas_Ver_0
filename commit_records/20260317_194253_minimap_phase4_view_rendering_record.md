# 20260317_194253_minimap_phase4_view_rendering_record

## 记录范围

- 记录内容：
  1. 新增 `CanvasMiniMapViewGeometry.swift`，负责 minimap 的世界坐标与视图内容区域映射。
  2. 新增 `iOSCanvasMiniMapView.swift`，实现 iOS 平台 minimap 视图与图层绘制。
  3. 新增 `macOSCanvasMiniMapView.swift`，实现 macOS 平台 minimap 视图与图层绘制。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift`
- 本记录不包含：
  - controller 层的 minimap 挂载与 snapshot 接线
  - minimap 点击/拖动联动画板
  - 原始 gif diff
  - git commit / push

## 修改一：新增共享几何映射层 `CanvasMiniMapViewGeometry`

### 修改前

- 工程里还没有 minimap 专用的视图坐标换算 helper。
- 也没有把 `displayWorldRect` 按 `aspectFit` 映射到 minimap `contentRect` 的共享逻辑。
- 如果直接在平台视图内各写一套换算，iOS/macOS 很容易出现边界和比例不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift
// 函数名/类型名: 无
// 功能说明: 修改前工程中不存在 minimap 世界坐标与视图内容区域之间的共享映射层。
// 无对应实现
```

### 修改后

- 新增 `CanvasMiniMapViewGeometry`，统一负责：
  - 用 `displayWorldRect` 和 `viewBounds` 算 `contentRect`
  - 保持整体 `aspectFit`
  - 提供 `worldToMiniMap(...)` / `miniMapToWorld(...)`
  - 提供 `clampedMiniMapPoint(...)`
- 同时补了 `CanvasQuad.cgPath`，后续 iOS/macOS 绘制灰色四边形都可以复用。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift
// 函数名: init(displayWorldRect:viewBounds:contentInset:) / worldToMiniMap(_:) / miniMapToWorld(_:)
// 功能说明: 新增 minimap 共享几何映射层，把世界坐标系统缩放并居中到 minimap 内容区域。
struct CanvasMiniMapViewGeometry {
    let displayWorldRect: CGRect
    let contentRect: CGRect
    let scale: CGFloat

    init?(
        displayWorldRect: CGRect,
        viewBounds: CGRect,
        contentInset: CGFloat
    ) {
        // 先清洗输入 rect，再按 aspectFit 计算 minimap 内部真正的内容区域。
    }

    func worldToMiniMap(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: contentRect.minX + ((point.x - displayWorldRect.minX) * scale),
            y: contentRect.minY + ((point.y - displayWorldRect.minY) * scale)
        )
    }

    func miniMapToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: ((point.x - contentRect.minX) / scale) + displayWorldRect.minX,
            y: ((point.y - contentRect.minY) / scale) + displayWorldRect.minY
        )
    }
}

extension CanvasQuad {
    var cgPath: CGPath {
        let path = CGMutablePath()
        path.move(to: topLeading)
        path.addLine(to: topTrailing)
        path.addLine(to: bottomTrailing)
        path.addLine(to: bottomLeading)
        path.closeSubpath()
        return path
    }
}
```

## 修改二：新增 iOS minimap 视图

### 修改前

- iOS 侧只有主画板 `iOSCanvasViewportView`，还没有 minimap 视图。
- 更没有专门用于 minimap 的 `background / board / occupancy / viewport` 图层结构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名/类型名: 无
// 功能说明: 修改前工程中没有 iOS 平台 minimap 视图。
// 无对应实现
```

### 修改后

- 新增 `iOSCanvasMiniMapView`。
- 实现形式延续主画板风格：`UIView` 外壳 + `CALayer / CAShapeLayer`。
- 图层职责拆分为：
  - `backgroundLayer`
  - `boardLayer`
  - `occupancyLayer`
  - `viewportLayer`
- `apply(_ snapshot)` 可以直接消费 `CanvasMiniMapSnapshot`。
- 视图内部按 `CanvasMiniMapViewGeometry` 计算内容区域，并分别刷新：
  - 画板范围
  - 灰色占位四边形
  - 当前视口框

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名: apply(_:) / refreshMiniMap() / refreshOccupancyLayer(using:contentsScale:)
// 功能说明: 新增 iOS minimap 视图，统一在 layer 树里绘制背景、画板边界、灰色占位块和当前视口框。
final class iOSCanvasMiniMapView: UIView {
    private let backgroundLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private let viewportLayer = CAShapeLayer()
    private var snapshot: CanvasMiniMapSnapshot = .empty
    private var geometry: CanvasMiniMapViewGeometry?

    func apply(_ snapshot: CanvasMiniMapSnapshot) {
        self.snapshot = snapshot
        performWithoutLayerActions {
            refreshMiniMap()
        }
    }

    private func refreshMiniMap() {
        geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: bounds,
            contentInset: Self.contentInset
        )
        // 再分别刷新 board / occupancy / viewport
    }

    private func refreshOccupancyLayer(
        using geometry: CanvasMiniMapViewGeometry,
        contentsScale: CGFloat
    ) {
        let path = CGMutablePath()
        for node in snapshot.nodes {
            path.addPath(
                geometry.worldToMiniMap(node.worldQuad).cgPath
            )
        }
        occupancyLayer.path = path
    }
}
```

## 修改三：新增 macOS minimap 视图

### 修改前

- macOS 侧同样只有主画板 `macOSCanvasViewportView`，还没有 minimap 视图。
- 没有可用于后续 controller 挂载的 minimap 组件。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名/类型名: 无
// 功能说明: 修改前工程中没有 macOS 平台 minimap 视图。
// 无对应实现
```

### 修改后

- 新增 `macOSCanvasMiniMapView`。
- 整体结构与 iOS 保持同构，便于后续 controller 共用 `CanvasMiniMapSnapshot` 和绘制语义。
- 关键点包括：
  - `isFlipped = true`
  - `apply(_ snapshot)`
  - `refreshBoardLayer(...)`
  - `refreshOccupancyLayer(...)`
  - `refreshViewportLayer(...)`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名: apply(_:) / refreshBoardLayer(using:contentsScale:) / refreshViewportLayer(using:contentsScale:)
// 功能说明: 新增 macOS minimap 视图，使用与 iOS 同构的 layer 绘制逻辑，保证跨平台视觉与几何语义一致。
final class macOSCanvasMiniMapView: NSView {
    override var isFlipped: Bool {
        true
    }

    private let backgroundLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private let viewportLayer = CAShapeLayer()
    private var snapshot: CanvasMiniMapSnapshot = .empty
    private var geometry: CanvasMiniMapViewGeometry?

    func apply(_ snapshot: CanvasMiniMapSnapshot) {
        self.snapshot = snapshot
        performWithoutLayerActions {
            refreshMiniMap()
        }
    }

    private func refreshViewportLayer(
        using geometry: CanvasMiniMapViewGeometry,
        contentsScale: CGFloat
    ) {
        let viewportRect = geometry.worldToMiniMap(snapshot.visibleWorldRect)
        viewportLayer.path = CGPath(rect: viewportRect, transform: nil)
    }
}
```

## 修改四：minimap 绘制内容从结构上对齐产品需求

### 修改前

- 虽然 `Phase 2` 已有 `CanvasMiniMapSnapshot` 和 `CanvasMiniMapRenderer`，但没有任何实际的视图把这些数据画出来。
- “灰色矩形表示图片位置、显示裁切后的图片、旋转也要画出来、显示当前视口框”还停留在 Core 数据层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名/类型名: 无
// 功能说明: 修改前产品需求只在讨论与 Core 设计阶段存在，还没有实际绘制落点。
// 无对应实现
```

### 修改后

- `boardLayer` 使用 `snapshot.boardWorldRect` 绘制板面范围。
- `occupancyLayer` 使用 `snapshot.nodes[*].worldQuad` 绘制灰色占位块。
  - 因为这里用的是四边形而不是包围盒，所以旋转角度会保住。
  - 因为 `Phase 2` 已经让 node 几何来自 `presentation.visibleWorldQuad`，所以显示的是裁切后的当前可见区域。
- `viewportLayer` 使用 `snapshot.visibleWorldRect` 绘制当前视口框。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名: refreshBoardLayer(using:contentsScale:) / refreshOccupancyLayer(using:contentsScale:) / refreshViewportLayer(using:contentsScale:)
// 功能说明: minimap 现在已经具备板面边界、灰色占位块、当前视口框三层绘制能力。
private func refreshBoardLayer(
    using geometry: CanvasMiniMapViewGeometry,
    contentsScale: CGFloat
) {
    let boardRect = geometry.worldToMiniMap(snapshot.boardWorldRect)
    boardLayer.path = CGPath(rect: boardRect, transform: nil)
}

private func refreshOccupancyLayer(
    using geometry: CanvasMiniMapViewGeometry,
    contentsScale: CGFloat
) {
    let path = CGMutablePath()
    for node in snapshot.nodes {
        path.addPath(
            geometry.worldToMiniMap(node.worldQuad).cgPath
        )
    }
    occupancyLayer.path = path
}

private func refreshViewportLayer(
    using geometry: CanvasMiniMapViewGeometry,
    contentsScale: CGFloat
) {
    let viewportRect = geometry.worldToMiniMap(snapshot.visibleWorldRect)
    viewportLayer.path = CGPath(rect: viewportRect, transform: nil)
}
```

## 修改五：为 `Phase 5` 预留 minimap 点位反查能力

### 修改前

- 修改前即使后续把 minimap 画出来，也还缺一层“从 minimap 点击位置反推世界坐标”的封装能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift
// 函数名/类型名: 无
// 功能说明: 修改前 minimap 视图不存在，因此也没有对外暴露 minimap 点位到世界坐标的转换接口。
// 无对应实现
```

### 修改后

- iOS/macOS minimap 视图都新增：
  - `worldPoint(atMiniMapPoint:)`
  - `currentContentRect`
- 这两个接口会在 `Phase 5` 的 controller 联动里直接使用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift
// 函数名: worldPoint(atMiniMapPoint:) / currentContentRect
// 功能说明: 提前为 minimap 点击/拖动导航预留世界坐标反查接口，避免后续把几何逻辑再塞回 controller。
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

## 结果与影响

- 本次修改完成了 minimap `Phase 4`：视图本体和图层绘制已经就位。
- 当前工程已经具备：
  - 共享几何映射层
  - iOS minimap 视图
  - macOS minimap 视图
  - 灰色占位块、板面边界、视口框的绘制能力
- 但这一步仍然不会在界面上真正显示 minimap，因为 controller 还没把 minimap view 挂载进 `miniMapMountView`，也还没把 `CanvasMiniMapSnapshot` 喂进去。

## 校验情况

- 已执行 `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift`，通过。
- 已执行 `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift`，通过。
- `ReadLints` 已检查：
  - `CanvasMiniMapViewGeometry.swift`
  - `iOSCanvasMiniMapView.swift`
  - `macOSCanvasMiniMapView.swift`
- 未发现新增诊断。
