# 20260317_140441_unified_editoverlay_crop_corner_proportional_scaling_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 中，把 `crop` 模式四个角 handle 的拖拽求解从自由裁切改成按当前裁切框宽高比等比缩放。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 中同步完成同样的等比缩放改造。
  3. 保持 `crop` 模式四个边中点 handle 的单轴裁切行为不变，仅修改四角 handle 的几何求解。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - shared renderer / viewport 结构调整
  - 原始 gif diff
  - git commit / push
  - 逐项手动 UI 回归实测

## 修改一：iOS 中把 `crop` 四角拖拽从自由裁切改成等比缩放

### 修改前

- `constrainedCropLocalFrame(...)` 对四个角分别直接求新的 `x / y / width / height`。
- 旧逻辑只保证图片边界与最小尺寸，不保持当前 crop 框的宽高比。
- 四个边中点和四个角都走同一个“按 role 直接求 frame”的分支体系，其中角点本质上是自由变形。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改前 iOS crop 四角 handle 直接自由求解 frame，只限制边界与最小尺寸，不保持当前宽高比。
private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.maxY - minY
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .topTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottomTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: maxY - initialLocalFrame.minY
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .bottomLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

### 修改后

- `constrainedCropLocalFrame(...)` 只保留边中点的单轴裁切逻辑。
- 四个角统一转发到新的 `proportionalCropLocalFrame(...)`。
- 新 helper 组改用“固定对角点 + 宽高各自 scale + 取较大轴 scale + 最大可扩张 scale 上限”的方式求解，使角点拖拽始终保持当前 crop 框宽高比。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改后 iOS 只让四角 handle 走等比缩放求解，四个边中点继续保持单轴裁切。
private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
        return proportionalCropLocalFrame(
            draggedLocalPoint,
            for: handleRole,
            initialLocalFrame: initialLocalFrame,
            fullImageLocalFrame: fullImageLocalFrame,
            minimumLocalSize: minimumLocalSize
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: proportionalCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:) / fixedOppositeCropLocalCorner(for:in:) / constrainedDraggedCropLocalCorner(_:for:oppositeCorner:fullImageLocalFrame:) / maximumProportionalCropScale(for:oppositeCorner:initialLocalFrame:fullImageLocalFrame:) / cropLocalFrame(for:withFixedOppositeCorner:size:)
// 功能说明: 修改后 iOS 为 crop 四角新增等比缩放 helper 组，固定对角点并限制最大可缩放范围，避免越出 full image 边界。
private func proportionalCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    guard
        initialLocalFrame.width > 0,
        initialLocalFrame.height > 0
    else {
        return initialLocalFrame
    }

    let oppositeCorner = fixedOppositeCropLocalCorner(
        for: handleRole,
        in: initialLocalFrame
    )
    let constrainedLocalCorner = constrainedDraggedCropLocalCorner(
        draggedLocalPoint,
        for: handleRole,
        oppositeCorner: oppositeCorner,
        fullImageLocalFrame: fullImageLocalFrame
    )
    let widthScale = abs(constrainedLocalCorner.x - oppositeCorner.x) / initialLocalFrame.width
    let heightScale = abs(constrainedLocalCorner.y - oppositeCorner.y) / initialLocalFrame.height
    let minimumScale = max(
        minimumLocalSize.width / initialLocalFrame.width,
        minimumLocalSize.height / initialLocalFrame.height
    )
    let maximumScale = maximumProportionalCropScale(
        for: handleRole,
        oppositeCorner: oppositeCorner,
        initialLocalFrame: initialLocalFrame,
        fullImageLocalFrame: fullImageLocalFrame
    )
    let scale = min(
        max(widthScale, heightScale, minimumScale),
        maximumScale
    )
    guard scale.isFinite, scale > 0 else {
        return initialLocalFrame
    }

    return cropLocalFrame(
        for: handleRole,
        withFixedOppositeCorner: oppositeCorner,
        size: CGSize(
            width: initialLocalFrame.width * scale,
            height: initialLocalFrame.height * scale
        )
    )
}

private func fixedOppositeCropLocalCorner(
    for handleRole: CanvasCropHandleRole,
    in localFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
    case .topTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.maxY)
    case .bottomLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.minY)
    case .bottomTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.minY)
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles have an opposite corner.")
        return localFrame.origin
    }
}

private func constrainedDraggedCropLocalCorner(
    _ draggedLocalCorner: CGPoint,
    for handleRole: CanvasCropHandleRole,
    oppositeCorner: CGPoint,
    fullImageLocalFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(
            x: min(
                max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                oppositeCorner.x
            ),
            y: min(
                max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                oppositeCorner.y
            )
        )
    case .topTrailing:
        return CGPoint(
            x: max(
                min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                oppositeCorner.x
            ),
            y: min(
                max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                oppositeCorner.y
            )
        )
    case .bottomLeading:
        return CGPoint(
            x: min(
                max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                oppositeCorner.x
            ),
            y: max(
                min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                oppositeCorner.y
            )
        )
    case .bottomTrailing:
        return CGPoint(
            x: max(
                min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                oppositeCorner.x
            ),
            y: max(
                min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                oppositeCorner.y
            )
        )
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles support proportional dragging.")
        return draggedLocalCorner
    }
}

private func maximumProportionalCropScale(
    for handleRole: CanvasCropHandleRole,
    oppositeCorner: CGPoint,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect
) -> CGFloat {
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    switch handleRole {
    case .topLeading:
        maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
        maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
    case .topTrailing:
        maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
        maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
    case .bottomLeading:
        maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
        maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
    case .bottomTrailing:
        maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
        maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles have a proportional max scale.")
        return 1
    }

    return min(
        maxWidth / initialLocalFrame.width,
        maxHeight / initialLocalFrame.height
    )
}

private func cropLocalFrame(
    for handleRole: CanvasCropHandleRole,
    withFixedOppositeCorner oppositeCorner: CGPoint,
    size: CGSize
) -> CGRect {
    switch handleRole {
    case .topLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .topTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .bottomLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .bottomTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles build proportional corner frames.")
        return CGRect(origin: oppositeCorner, size: size)
    }
}
```

## 修改二：macOS 中同步将 `crop` 四角拖拽改成等比缩放

### 修改前

- macOS 侧 `constrainedCropLocalFrame(...)` 与 iOS 一样，四角走自由裁切求解。
- 拖拽角点时仅限制最小尺寸和图片边界，不保持宽高比。
- 这会导致 macOS 与 iOS 一样，在 `crop` 四角拖拽时出现自由变形。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改前 macOS crop 四角 handle 同样直接自由求解 frame，不保持当前裁切框宽高比。
private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.maxY - minY
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .topTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottomTrailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: maxY - initialLocalFrame.minY
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .bottomLeading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

### 修改后

- macOS 侧也把四角统一转发到 `proportionalCropLocalFrame(...)`。
- 新增的 helper 组与 iOS 对称，保持双平台相同的拖拽几何语义。
- 角点现在会按比例缩放，边中点仍然只裁切单轴。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: constrainedCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:)
// 功能说明: 修改后 macOS 与 iOS 对称，只让 crop 四角 handle 走等比缩放求解，边中点逻辑保持不变。
private func constrainedCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    let initialLocalFrame = initialLocalFrame.standardized
    let fullImageLocalFrame = fullImageLocalFrame.standardized

    switch handleRole {
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
        return proportionalCropLocalFrame(
            draggedLocalPoint,
            for: handleRole,
            initialLocalFrame: initialLocalFrame,
            fullImageLocalFrame: fullImageLocalFrame,
            minimumLocalSize: minimumLocalSize
        )
    case .top:
        let minY = min(
            max(draggedLocalPoint.y, fullImageLocalFrame.minY),
            initialLocalFrame.maxY - minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: minY,
            width: initialLocalFrame.width,
            height: initialLocalFrame.maxY - minY
        )
    case .trailing:
        let maxX = max(
            min(draggedLocalPoint.x, fullImageLocalFrame.maxX),
            initialLocalFrame.minX + minimumLocalSize.width
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: maxX - initialLocalFrame.minX,
            height: initialLocalFrame.height
        )
    case .bottom:
        let maxY = max(
            min(draggedLocalPoint.y, fullImageLocalFrame.maxY),
            initialLocalFrame.minY + minimumLocalSize.height
        )
        return CGRect(
            x: initialLocalFrame.minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.width,
            height: maxY - initialLocalFrame.minY
        )
    case .leading:
        let minX = min(
            max(draggedLocalPoint.x, fullImageLocalFrame.minX),
            initialLocalFrame.maxX - minimumLocalSize.width
        )
        return CGRect(
            x: minX,
            y: initialLocalFrame.minY,
            width: initialLocalFrame.maxX - minX,
            height: initialLocalFrame.height
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: proportionalCropLocalFrame(_:for:initialLocalFrame:fullImageLocalFrame:minimumLocalSize:) / fixedOppositeCropLocalCorner(for:in:) / constrainedDraggedCropLocalCorner(_:for:oppositeCorner:fullImageLocalFrame:) / maximumProportionalCropScale(for:oppositeCorner:initialLocalFrame:fullImageLocalFrame:) / cropLocalFrame(for:withFixedOppositeCorner:size:)
// 功能说明: 修改后 macOS 同步使用与 iOS 对称的 crop 四角等比缩放 helper 组，保证双平台 corner drag 行为一致。
private func proportionalCropLocalFrame(
    _ draggedLocalPoint: CGPoint,
    for handleRole: CanvasCropHandleRole,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect,
    minimumLocalSize: CGSize
) -> CGRect {
    guard
        initialLocalFrame.width > 0,
        initialLocalFrame.height > 0
    else {
        return initialLocalFrame
    }

    let oppositeCorner = fixedOppositeCropLocalCorner(
        for: handleRole,
        in: initialLocalFrame
    )
    let constrainedLocalCorner = constrainedDraggedCropLocalCorner(
        draggedLocalPoint,
        for: handleRole,
        oppositeCorner: oppositeCorner,
        fullImageLocalFrame: fullImageLocalFrame
    )
    let widthScale = abs(constrainedLocalCorner.x - oppositeCorner.x) / initialLocalFrame.width
    let heightScale = abs(constrainedLocalCorner.y - oppositeCorner.y) / initialLocalFrame.height
    let minimumScale = max(
        minimumLocalSize.width / initialLocalFrame.width,
        minimumLocalSize.height / initialLocalFrame.height
    )
    let maximumScale = maximumProportionalCropScale(
        for: handleRole,
        oppositeCorner: oppositeCorner,
        initialLocalFrame: initialLocalFrame,
        fullImageLocalFrame: fullImageLocalFrame
    )
    let scale = min(
        max(widthScale, heightScale, minimumScale),
        maximumScale
    )
    guard scale.isFinite, scale > 0 else {
        return initialLocalFrame
    }

    return cropLocalFrame(
        for: handleRole,
        withFixedOppositeCorner: oppositeCorner,
        size: CGSize(
            width: initialLocalFrame.width * scale,
            height: initialLocalFrame.height * scale
        )
    )
}

private func fixedOppositeCropLocalCorner(
    for handleRole: CanvasCropHandleRole,
    in localFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
    case .topTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.maxY)
    case .bottomLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.minY)
    case .bottomTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.minY)
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles have an opposite corner.")
        return localFrame.origin
    }
}

private func constrainedDraggedCropLocalCorner(
    _ draggedLocalCorner: CGPoint,
    for handleRole: CanvasCropHandleRole,
    oppositeCorner: CGPoint,
    fullImageLocalFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(
            x: min(
                max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                oppositeCorner.x
            ),
            y: min(
                max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                oppositeCorner.y
            )
        )
    case .topTrailing:
        return CGPoint(
            x: max(
                min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                oppositeCorner.x
            ),
            y: min(
                max(draggedLocalCorner.y, fullImageLocalFrame.minY),
                oppositeCorner.y
            )
        )
    case .bottomLeading:
        return CGPoint(
            x: min(
                max(draggedLocalCorner.x, fullImageLocalFrame.minX),
                oppositeCorner.x
            ),
            y: max(
                min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                oppositeCorner.y
            )
        )
    case .bottomTrailing:
        return CGPoint(
            x: max(
                min(draggedLocalCorner.x, fullImageLocalFrame.maxX),
                oppositeCorner.x
            ),
            y: max(
                min(draggedLocalCorner.y, fullImageLocalFrame.maxY),
                oppositeCorner.y
            )
        )
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles support proportional dragging.")
        return draggedLocalCorner
    }
}

private func maximumProportionalCropScale(
    for handleRole: CanvasCropHandleRole,
    oppositeCorner: CGPoint,
    initialLocalFrame: CGRect,
    fullImageLocalFrame: CGRect
) -> CGFloat {
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    switch handleRole {
    case .topLeading:
        maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
        maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
    case .topTrailing:
        maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
        maxHeight = oppositeCorner.y - fullImageLocalFrame.minY
    case .bottomLeading:
        maxWidth = oppositeCorner.x - fullImageLocalFrame.minX
        maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
    case .bottomTrailing:
        maxWidth = fullImageLocalFrame.maxX - oppositeCorner.x
        maxHeight = fullImageLocalFrame.maxY - oppositeCorner.y
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles have a proportional max scale.")
        return 1
    }

    return min(
        maxWidth / initialLocalFrame.width,
        maxHeight / initialLocalFrame.height
    )
}

private func cropLocalFrame(
    for handleRole: CanvasCropHandleRole,
    withFixedOppositeCorner oppositeCorner: CGPoint,
    size: CGSize
) -> CGRect {
    switch handleRole {
    case .topLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .topTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .bottomLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .bottomTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .top, .trailing, .bottom, .leading:
        assertionFailure("Only crop corner handles build proportional corner frames.")
        return CGRect(origin: oppositeCorner, size: size)
    }
}
```

## 验证结果

### lints

- 对以下文件执行 `ReadLints`，结果均为 `No linter errors found.`：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

### 构建验证

```bash
# 功能说明: iOS Simulator Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ".build/ios-sim" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO
```

- 结果：`Exit code 0`，构建通过。

```bash
# 功能说明: macOS Debug 构建验证；沿用工作区内 derivedDataPath 与禁签名参数。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath ".build/macos" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

- 结果：`Exit code 0`，构建通过。

## 本次未执行的回归项

- 未逐项手动验证 `crop` 四角 handle 在不同初始宽高比下的拖拽手感是否都符合预期。
- 未逐项手动验证 rotated item 进入 `crop` 模式后，四角等比缩放与四边单轴裁切的组合行为。
- 未逐项手动验证 undo / redo、autosave、手动保存、重开恢复，以及“单次手势只生成一条历史记录”。
