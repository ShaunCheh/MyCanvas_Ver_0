# 20260325_104420_crop_hittester_phase1_geometry_foundation_record

## 记录范围

- 记录内容：
  - 将 `CanvasQuad.cgPath` 从 minimap 专用文件迁回共享几何层。
  - 为 `CanvasQuad` 补齐 `edges`、`contains(_:)` 和点到线段距离函数，作为后续共享 hit tester 的几何基础。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift`
- 本记录不包含：
  - `Phase 2` 的 `CanvasEditOverlayHitTester` 抽取
  - `Crop` 模式交互行为变更
  - 其它非几何层改造

## 修改一：把 `CanvasQuad.cgPath` 从 minimap 文件迁回共享几何层

### 修改前

- `CanvasQuad.cgPath` 定义在 `CanvasMiniMapViewGeometry.swift` 末尾的扩展里。
- 这会让一个通用四边形能力挂在 minimap 专用文件中，语义归属不正确。
- 其它模块如果要复用 `CanvasQuad` 的路径表达，会被迫依赖一个与 minimap 命名绑定的文件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift
// 函数名: CanvasQuad.cgPath
// 功能说明: 修改前 cgPath 挂在 minimap 专用文件末尾；它本质是通用四边形路径能力，但文件语义却是 MiniMap 几何。
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

### 修改后

- `CanvasQuad.cgPath` 被迁回 `CanvasGeometry.swift`，归入共享几何层。
- `CanvasMiniMapViewGeometry.swift` 不再承载 `CanvasQuad` 的通用能力，只保留 minimap 自己的坐标映射职责。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名: CanvasQuad.cgPath
// 功能说明: 修改后 cgPath 回到共享几何层，供 viewport、minimap、后续 hit tester 统一复用四边形路径表达。
var cgPath: CGPath {
    let path = CGMutablePath()
    path.move(to: topLeading)
    path.addLine(to: topTrailing)
    path.addLine(to: bottomTrailing)
    path.addLine(to: bottomLeading)
    path.closeSubpath()
    return path
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapViewGeometry.swift
// 函数名: 无（文件尾）
// 功能说明: 修改后移除了 CanvasQuad 的通用 cgPath 扩展；这个文件重新只负责 MiniMap 的几何映射，不再混入共享四边形能力。
private static func sanitizedRect(_ rect: CGRect) -> CGRect? {
    guard rect.isNull == false, rect.isInfinite == false else {
        return nil
    }

    let standardizedRect = rect.standardized
    guard
        standardizedRect.width > 0,
        standardizedRect.height > 0
    else {
        return nil
    }

    return standardizedRect
}
```

## 修改二：给 `CanvasQuad` 补齐共享 hit test 几何能力

### 修改前

- `CanvasQuad` 只有顶点、中心点、中点、包围盒和 `map(_:)`。
- 共享几何层里没有：
  - `edges`
  - `contains(_:)`
  - 点到线段距离函数
- 这意味着后续如果要做旋转 crop quad 的精确命中，不能直接复用共享几何层能力。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名: CanvasQuad.points / CanvasQuad.center / CanvasQuad.boundingRect / CanvasQuad.map(_:)
// 功能说明: 修改前 CanvasQuad 只提供基础几何描述，没有真正面向 hit test 的共享能力。
var points: [CGPoint] {
    [
        topLeading,
        topTrailing,
        bottomTrailing,
        bottomLeading
    ]
}

var center: CGPoint {
    CGPoint(
        x: (topLeading.x + topTrailing.x + bottomLeading.x + bottomTrailing.x) / 4,
        y: (topLeading.y + topTrailing.y + bottomLeading.y + bottomTrailing.y) / 4
    )
}

var boundingRect: CGRect {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    // ...
}

func map(_ transform: (CGPoint) -> CGPoint) -> CanvasQuad {
    CanvasQuad(
        topLeading: transform(topLeading),
        topTrailing: transform(topTrailing),
        bottomLeading: transform(bottomLeading),
        bottomTrailing: transform(bottomTrailing)
    )
}
```

### 修改后

- 新增 `edges`，把四条边变成共享可复用结构。
- 新增 `contains(_:)`，先用 `cgPath.contains` 做真实四边形内部判断，再用边距离容差覆盖落在边上的点。
- 新增 `canvasDistance(...)`，把点到线段距离提炼成共享函数，为后续 crop/selection hit tester 复用做准备。
- 这一步只补基础设施，没有接入 `CanvasContextResolver`，所以当前交互行为不变。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名: CanvasQuad.edges / CanvasQuad.contains(_:) / canvasDistance(from:toSegmentStart:segmentEnd:)
// 功能说明: 修改后共享几何层已经具备四边形边集合、真实点内判定和点到线段距离计算，后续 HitTester 可以直接复用。
var edges: [(start: CGPoint, end: CGPoint)] {
    [
        (topLeading, topTrailing),
        (topTrailing, bottomTrailing),
        (bottomTrailing, bottomLeading),
        (bottomLeading, topLeading)
    ]
}

func contains(_ point: CGPoint) -> Bool {
    if cgPath.contains(
        point,
        using: .winding,
        transform: .identity
    ) {
        return true
    }

    return edges.contains { edge in
        canvasDistance(
            from: point,
            toSegmentStart: edge.start,
            segmentEnd: edge.end
        ) <= canvasQuadContainmentEpsilon
    }
}

func canvasDistance(
    from point: CGPoint,
    toSegmentStart start: CGPoint,
    segmentEnd end: CGPoint
) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = (dx * dx) + (dy * dy)
    guard lengthSquared > 0 else {
        return hypot(point.x - start.x, point.y - start.y)
    }

    let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    let clampedProjection = min(max(projection, 0), 1)
    let closestPoint = CGPoint(
        x: start.x + (clampedProjection * dx),
        y: start.y + (clampedProjection * dy)
    )
    return hypot(point.x - closestPoint.x, point.y - closestPoint.y)
}
```

## 本次修改结果

- `CanvasQuad` 的通用路径与 hit test 基础能力已经回收到共享几何层。
- `CanvasMiniMapViewGeometry.swift` 重新只负责 minimap 自身的几何映射。
- 后续 `Phase 2` 可以直接在共享层抽 `CanvasEditOverlayHitTester`，而不需要继续依赖 minimap 文件或在 resolver 里重复实现几何 helper。
- 这次修改不改变 `Crop`、`Selection`、`Rotate` 的现有交互行为，只完成几何基础收口。

## 本次验证

- 已检查修改范围，仅涉及上述 2 个 Swift 文件。
- 已通过 IDE lint 检查，当前无新增 linter 报错。
- 未执行完整 Xcode build；当前命令行环境下 `xcodebuild` 不能直接使用完整 Xcode 构建链路。
