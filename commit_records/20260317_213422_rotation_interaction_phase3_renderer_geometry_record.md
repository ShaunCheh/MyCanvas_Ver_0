# 20260317_213422_rotation_interaction_phase3_renderer_geometry_record

## 记录范围

- 记录内容：
  1. 在 shared core 层新增旋转 HUD 所需的角度换算与极坐标几何 helper。
  2. 扩展 `CanvasRotationInteractionOverlayPayload`，让其承载可直接绘制的 screen-space 几何。
  3. 重构 `CanvasRenderer` 的 interaction overlay 生成逻辑，把圆环、刻度段、0°基准段、当前角度段和文本锚点统一在 renderer 侧产出。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- 本记录不包含：
  - iOS / macOS viewport 的 interaction overlay layer 接入
  - 刻度环 / 指针 / 文字 layer 的实际绘制
  - 原始 gif diff / git diff / git commit / git push

## 阶段结论

- 这一阶段完成的是“renderer 几何与角度语义收口”。
- 修改完成后，后续 viewport 已经不需要再自行推导：
  - `0°` 的方向
  - `0~360°` 的角度显示值
  - 圆环矩形
  - 36 个刻度段
  - 0°基准段
  - 当前角度径向段
  - 文字锚点
- 当前仍未接入 viewport 绘制，因此画面上暂时不会出现新的角度指示器。

## 修改一：在 CanvasGeometry 中新增共享角度与极坐标 helper

### 修改前

- `CanvasGeometry.swift` 里只有：
  - `CanvasQuad`
  - `normalizedCanvasAngle(_:)`
- 也就是说，后续如果 viewport 直接绘制角度 HUD，就不得不自己重复做“弧度转 0~360 显示角度”、“正上方为 0° 的极坐标换算”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名: normalizedCanvasAngle(_:)
// 功能说明: 修改前 geometry 只提供弧度归一化，没有旋转 HUD 需要的显示角度和极坐标 helper。
func normalizedCanvasAngle(_ radians: CGFloat) -> CGFloat {
    atan2(sin(radians), cos(radians))
}
```

### 修改后

- 新增了 5 个共享 helper：
  - `normalizedCanvasDegrees0To360(_:)`
  - `canvasDisplayDegrees0To360(forRotationRadians:)`
  - `canvasCircleRect(centeredAt:radius:)`
  - `canvasPointOnInteractionCircle(centeredAt:radius:displayDegrees0To360:zeroReference:)`
  - `canvasRadialSegment(centeredAt:startRadius:endRadius:displayDegrees0To360:zeroReference:)`
- 这些 helper 统一把“正上方为 0°”和 `0~360°` 的显示语义固定在 core 层，避免后续 iOS / macOS 各自实现一套数学逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名: normalizedCanvasDegrees0To360(_) / canvasDisplayDegrees0To360(...) /
//        canvasCircleRect(...) / canvasPointOnInteractionCircle(...) / canvasRadialSegment(...)
// 功能说明: 修改后在 shared core 中补齐角度显示与极坐标几何 helper，供 renderer/viewport 共享使用。
func normalizedCanvasDegrees0To360(_ degrees: CGFloat) -> CGFloat {
    let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
    return normalizedDegrees >= 0
        ? normalizedDegrees
        : normalizedDegrees + 360
}

func canvasDisplayDegrees0To360(
    forRotationRadians radians: CGFloat
) -> CGFloat {
    normalizedCanvasDegrees0To360(radians * 180 / .pi)
}

func canvasCircleRect(
    centeredAt center: CGPoint,
    radius: CGFloat
) -> CGRect {
    let resolvedRadius = max(radius, 0)
    return CGRect(
        x: center.x - resolvedRadius,
        y: center.y - resolvedRadius,
        width: resolvedRadius * 2,
        height: resolvedRadius * 2
    ).standardized
}

func canvasPointOnInteractionCircle(
    centeredAt center: CGPoint,
    radius: CGFloat,
    displayDegrees0To360 degrees: CGFloat,
    zeroReference: CanvasInteractionAngleZeroReference = .up
) -> CGPoint {
    let resolvedRadius = max(radius, 0)
    let normalizedDegrees = normalizedCanvasDegrees0To360(degrees)
    let radians = normalizedDegrees * .pi / 180

    switch zeroReference {
    case .up:
        return CGPoint(
            x: center.x + (sin(radians) * resolvedRadius),
            y: center.y - (cos(radians) * resolvedRadius)
        )
    }
}

func canvasRadialSegment(
    centeredAt center: CGPoint,
    startRadius: CGFloat,
    endRadius: CGFloat,
    displayDegrees0To360 degrees: CGFloat,
    zeroReference: CanvasInteractionAngleZeroReference = .up
) -> CanvasInteractionLineSegment {
    CanvasInteractionLineSegment(
        start: canvasPointOnInteractionCircle(
            centeredAt: center,
            radius: startRadius,
            displayDegrees0To360: degrees,
            zeroReference: zeroReference
        ),
        end: canvasPointOnInteractionCircle(
            centeredAt: center,
            radius: endRadius,
            displayDegrees0To360: degrees,
            zeroReference: zeroReference
        )
    )
}
```

## 修改二：扩展 interaction payload，让其承载可直接绘制的几何

### 修改前

- `CanvasRotationInteractionOverlayPayload` 只包含较粗粒度的语义字段：
  - `screenCenter`
  - `currentRotationRadians`
  - `zeroReference`
  - `tickStepDegrees`
  - `ringRadius`
  - `isActive`
- 虽然已经够表达“这是什么 HUD”，但还不够让 viewport 直接画图。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRotationInteractionOverlayPayload
// 功能说明: 修改前 payload 只承载基础角度语义，还没有直接可绘制的 screen-space 几何。
struct CanvasRotationInteractionOverlayPayload {
    let screenCenter: CGPoint
    let currentRotationRadians: CGFloat
    let zeroReference: CanvasInteractionAngleZeroReference
    let tickStepDegrees: CGFloat
    let ringRadius: CGFloat
    let isActive: Bool
}
```

### 修改后

- 新增 `CanvasInteractionLineSegment`。
- `CanvasRotationInteractionOverlayPayload` 现在补齐了直接绘制所需字段：
  - `displayDegrees0To360`
  - `ringScreenRect`
  - `tickSegments`
  - `zeroReferenceSegment`
  - `currentAngleSegment`
  - `textScreenAnchor`
- 这样后续 viewport 基本只剩“把路径/文字画出来”的责任。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasInteractionLineSegment / CanvasRotationInteractionOverlayPayload
// 功能说明: 修改后 payload 同时携带角度语义与可直接绘制的几何，降低平台层重复计算。
struct CanvasInteractionLineSegment {
    let start: CGPoint
    let end: CGPoint
}

struct CanvasRotationInteractionOverlayPayload {
    let screenCenter: CGPoint
    let currentRotationRadians: CGFloat
    let displayDegrees0To360: CGFloat
    let zeroReference: CanvasInteractionAngleZeroReference
    let tickStepDegrees: CGFloat
    let ringRadius: CGFloat
    let ringScreenRect: CGRect
    let tickSegments: [CanvasInteractionLineSegment]
    let zeroReferenceSegment: CanvasInteractionLineSegment
    let currentAngleSegment: CanvasInteractionLineSegment
    let textScreenAnchor: CGPoint
    let isActive: Bool
}
```

## 修改三：在 CanvasRenderer 中集中产出旋转 HUD 几何

### 修改前

- `CanvasRenderer` 只会为 interaction overlay 提供基础语义：
  - `screenCenter`
  - `currentRotationRadians`
  - `ringRadius`
  - `tickStepDegrees`
- 圆环、刻度、文字锚点等几何还没有被 renderer 产出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeInteractionOverlay(...)
// 功能说明: 修改前 renderer 只提供基础 HUD 语义，没有把实际绘制几何整理出来。
private func makeInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?
) -> CanvasInteractionRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let rotationInteractionState,
        interactionState.selectedItemID == rotationInteractionState.itemID,
        let item = scene.item(withID: rotationInteractionState.itemID)
    else {
        return nil
    }

    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let screenQuad = camera.worldToViewport(presentation.visibleWorldQuad)
    let rotateAffordance = makeRotateAffordance(
        for: presentation,
        camera: camera,
        screenQuad: screenQuad
    )
    let screenCenter = camera.worldToViewport(item.center)

    return CanvasInteractionRenderOverlay(
        itemID: presentation.itemID,
        kind: .rotation,
        payload: .rotation(
            CanvasRotationInteractionOverlayPayload(
                screenCenter: screenCenter,
                currentRotationRadians: presentation.effectiveRotationRadians,
                zeroReference: .up,
                tickStepDegrees: Self.rotationInteractionTickStepDegrees,
                ringRadius: distance(
                    from: screenCenter,
                    to: rotateAffordance.handle.screenCenter
                ),
                isActive: true
            )
        )
    )
}
```

### 修改后

- 新增 renderer 常量：
  - `minimumRotationInteractionRingRadius`
  - `rotationInteractionTickLength`
  - `rotationInteractionTextOffset`
- `makeInteractionOverlay(...)` 变成一个薄包装，把生成逻辑下沉到 `makeRotationInteractionOverlay(...)`。
- 在 `makeRotationInteractionOverlay(...)` 中统一生成：
  - 归一化后的当前弧度
  - `0~360°` 显示值
  - 正上方 `0°` 基准
  - 经过最小值夹紧的环半径
  - 圆环矩形
  - 36 个刻度段
  - 0° 基准径向段
  - 当前角度径向段
  - 文字锚点

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: CanvasRenderer 常量区 / makeInteractionOverlay(...) / makeRotationInteractionOverlay(...)
// 功能说明: 修改后 renderer 集中产出旋转 HUD 的完整 screen-space 几何，平台层只需负责绘制。
struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28
    private static let rotationInteractionTickStepDegrees: CGFloat = 10
    private static let minimumRotationInteractionRingRadius: CGFloat = 48
    private static let rotationInteractionTickLength: CGFloat = 8
    private static let rotationInteractionTextOffset: CGFloat = 18
    // ...
}

private func makeInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?
) -> CanvasInteractionRenderOverlay? {
    makeRotationInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
}

private func makeRotationInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?
) -> CanvasInteractionRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let rotationInteractionState,
        interactionState.selectedItemID == rotationInteractionState.itemID,
        let item = scene.item(withID: rotationInteractionState.itemID)
    else {
        return nil
    }

    let presentation = presentationResolver.resolve(
        item: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    let screenQuad = camera.worldToViewport(presentation.visibleWorldQuad)
    let rotateAffordance = makeRotateAffordance(
        for: presentation,
        camera: camera,
        screenQuad: screenQuad
    )
    let screenCenter = camera.worldToViewport(item.center)
    let currentRotationRadians = normalizedCanvasAngle(
        presentation.effectiveRotationRadians
    )
    let displayDegrees0To360 = canvasDisplayDegrees0To360(
        forRotationRadians: currentRotationRadians
    )
    let zeroReference: CanvasInteractionAngleZeroReference = .up
    let ringRadius = max(
        Self.minimumRotationInteractionRingRadius,
        distance(
            from: screenCenter,
            to: rotateAffordance.handle.screenCenter
        )
    )
    let tickSegments = makeRotationInteractionTickSegments(
        centeredAt: screenCenter,
        ringRadius: ringRadius,
        zeroReference: zeroReference
    )
    let zeroReferenceSegment = canvasRadialSegment(
        centeredAt: screenCenter,
        startRadius: 0,
        endRadius: ringRadius,
        displayDegrees0To360: 0,
        zeroReference: zeroReference
    )
    let currentAngleSegment = canvasRadialSegment(
        centeredAt: screenCenter,
        startRadius: 0,
        endRadius: ringRadius,
        displayDegrees0To360: displayDegrees0To360,
        zeroReference: zeroReference
    )
    let textScreenAnchor = CGPoint(
        x: screenCenter.x,
        y: screenCenter.y - ringRadius - Self.rotationInteractionTextOffset
    )

    return CanvasInteractionRenderOverlay(
        itemID: presentation.itemID,
        kind: .rotation,
        payload: .rotation(
            CanvasRotationInteractionOverlayPayload(
                screenCenter: screenCenter,
                currentRotationRadians: currentRotationRadians,
                displayDegrees0To360: displayDegrees0To360,
                zeroReference: zeroReference,
                tickStepDegrees: Self.rotationInteractionTickStepDegrees,
                ringRadius: ringRadius,
                ringScreenRect: canvasCircleRect(
                    centeredAt: screenCenter,
                    radius: ringRadius
                ),
                tickSegments: tickSegments,
                zeroReferenceSegment: zeroReferenceSegment,
                currentAngleSegment: currentAngleSegment,
                textScreenAnchor: textScreenAnchor,
                isActive: true
            )
        )
    )
}
```

## 修改四：在 renderer 内部生成 36 个刻度段

### 修改前

- 虽然已经有 `tickStepDegrees = 10`，但 renderer 还没有真正把 36 个刻度段展开出来。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeInteractionOverlay(...)
// 功能说明: 修改前 tick step 只是一个数字常量，renderer 还没有把刻度段几何真正生成出来。
tickStepDegrees: Self.rotationInteractionTickStepDegrees,
ringRadius: distance(
    from: screenCenter,
    to: rotateAffordance.handle.screenCenter
),
isActive: true
```

### 修改后

- 新增 `makeRotationInteractionTickSegments(...)`。
- 用 `stride(from: 0, to: 360, by: 10)` 生成整圈 36 个刻度段。
- 起点半径会减去 `rotationInteractionTickLength`，这样输出的是“短刻度段”，而不是整根半径线。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeRotationInteractionTickSegments(...)
// 功能说明: 修改后 renderer 会按 10 度步进展开整圈 36 个刻度段，并输出为统一的 screen-space 线段数组。
private func makeRotationInteractionTickSegments(
    centeredAt center: CGPoint,
    ringRadius: CGFloat,
    zeroReference: CanvasInteractionAngleZeroReference
) -> [CanvasInteractionLineSegment] {
    let tickStartRadius = max(
        ringRadius - Self.rotationInteractionTickLength,
        0
    )
    return stride(
        from: CGFloat(0),
        to: 360,
        by: Self.rotationInteractionTickStepDegrees
    ).map { degrees in
        canvasRadialSegment(
            centeredAt: center,
            startRadius: tickStartRadius,
            endRadius: ringRadius,
            displayDegrees0To360: degrees,
            zeroReference: zeroReference
        )
    }
}
```

## 本阶段完成后的代码行为

1. renderer 已经能稳定产出“正上方为 0°、0~360°”的显示角度语义。
2. interaction payload 已经具备 viewport 直接绘制所需的核心几何。
3. 旋转 HUD 的 36 个刻度段、0°基准段、当前角度段与文本锚点都由 renderer 统一生成。
4. iOS / macOS 视图层后续只需要消费 `snapshot.interactionOverlay` 并绘制，不再需要自己推数学。

## 校验结果

- 对以下文件执行过 lint 检查，未发现新增错误：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
