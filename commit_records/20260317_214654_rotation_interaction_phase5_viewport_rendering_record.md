# 20260317_214654_rotation_interaction_phase5_viewport_rendering_record

## 记录范围

- 记录内容：
  1. 在 iOS / macOS viewport 中正式绘制旋转角度指示器的圆环、刻度、指针和角度文本。
  2. 为两端 viewport 新增路径拼接、角度文本排版和文本背景框计算 helper。
  3. 让阶段 3 / 4 已经准备好的 interaction overlay 数据真正转化为可见 UI。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - 原始 gif diff / git diff / git commit / git push
  - 阶段 6 的生命周期回归收口

## 阶段结论

- 这一阶段完成的是“viewport 实际绘制逻辑”。
- 修改完成后，旋转中的 interaction overlay 不再只是占位 layer，而是会真正画出：
  - 圆形刻度环
  - 36 个刻度段
  - 0° 基准线
  - 当前角度线
  - 当前角度数值
  - 数值背景框
- 当前角度文本已经使用整数度数显示，符合“0~360、0 在正上方”的显示语义。

## 修改一：iOS viewport 从“只接生命周期”升级为“真正绘制圆环/刻度/指针/文字”

### 修改前

- `refreshRotationInteractionOverlay(from:)` 只会：
  - 根据 `payload.isActive` 控制显隐
  - 为各 layer 赋 frame
  - 清空 `path`
  - 清空文本内容
- 也就是说，阶段 4 只是把 interaction overlay 通道接通了，但还没有真正画任何东西。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改前 iOS 只把 interaction overlay layer 树接上，但路径与文本都还是空占位。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = nil
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = nil
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = nil
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = CGRect(origin: payload.textScreenAnchor, size: .zero)
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}
```

### 修改后

- `rotationRingLayer` 现在直接用 `payload.ringScreenRect` 画圆环。
- `rotationTickLayer` 用 `payload.tickSegments` 画全部刻度段。
- `rotationPointerLayer` 同时画：
  - `payload.zeroReferenceSegment`
  - `payload.currentAngleSegment`
- `rotationTextLayer` 现在会显示角度数值，`rotationTextBackgroundLayer` 负责画文字底框。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改后 iOS 会真正把 interaction overlay payload 转成圆环、刻度、指针和角度文字。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = CGPath(
        ellipseIn: payload.ringScreenRect,
        transform: nil
    )
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = Self.lineSegmentsPath([
        payload.zeroReferenceSegment,
        payload.currentAngleSegment
    ])
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    let attributedText = Self.rotationAttributedText(for: payload)
    let textFrame = Self.rotationTextFrame(
        for: attributedText,
        anchoredAt: payload.textScreenAnchor
    )
    let textBackgroundFrame = Self.rotationTextBackgroundFrame(
        for: textFrame
    )

    rotationTextBackgroundLayer.frame = bounds
    rotationTextBackgroundLayer.path = CGPath(
        roundedRect: textBackgroundFrame,
        cornerWidth: Self.rotationTextCornerRadius,
        cornerHeight: Self.rotationTextCornerRadius,
        transform: nil
    )
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = textFrame
    rotationTextLayer.string = attributedText
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}
```

## 修改二：iOS 新增绘制辅助常量与 helper，用于刻度路径和角度文字排版

### 修改前

- iOS viewport 没有角度文本相关常量。
- 也没有：
  - 线段数组转 `CGPath` 的 helper
  - 角度文本生成 helper
  - 文本 frame / 背景框 frame 计算 helper

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 常量区 / 静态 helper 区
// 功能说明: 修改前 iOS 只有 selection/crop/rotate 的基础绘制常量，没有角度文本和 interaction overlay 绘制 helper。
private static let rotateGuideLineWidth: CGFloat = 2
private static let rotateHandleLineWidth: CGFloat = 2
private static let rotateHandleSize: CGFloat = 14
```

### 修改后

- 新增文本绘制常量：
  - `rotationTextFontSize`
  - `rotationTextHorizontalPadding`
  - `rotationTextVerticalPadding`
  - `rotationTextCornerRadius`
- 新增 helper：
  - `lineSegmentsPath(_:)`
  - `rotationAttributedText(for:)`
  - `rotationTextFrame(for:anchoredAt:)`
  - `rotationTextBackgroundFrame(for:)`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: 常量区 / lineSegmentsPath(_) / rotationAttributedText(for:) /
//        rotationTextFrame(for:anchoredAt:) / rotationTextBackgroundFrame(for:)
// 功能说明: 修改后 iOS 拥有 interaction overlay 的路径拼接与角度文字排版 helper。
private static let rotateGuideLineWidth: CGFloat = 2
private static let rotateHandleLineWidth: CGFloat = 2
private static let rotateHandleSize: CGFloat = 14
private static let rotationTextFontSize: CGFloat = 12
private static let rotationTextHorizontalPadding: CGFloat = 8
private static let rotationTextVerticalPadding: CGFloat = 4
private static let rotationTextCornerRadius: CGFloat = 8

private static func lineSegmentsPath(
    _ segments: [CanvasInteractionLineSegment]
) -> CGPath {
    let path = CGMutablePath()

    for segment in segments {
        path.move(to: segment.start)
        path.addLine(to: segment.end)
    }

    return path
}

private static func rotationAttributedText(
    for payload: CanvasRotationInteractionOverlayPayload
) -> NSAttributedString {
    let degrees = Int(payload.displayDegrees0To360.rounded())
    let displayDegrees = degrees == 360 ? 360 : max(0, degrees)
    let font = UIFont.monospacedDigitSystemFont(
        ofSize: rotationTextFontSize,
        weight: .semibold
    )
    let textColor = UIColor(cgColor: selectionStrokeColor)

    return NSAttributedString(
        string: "\(displayDegrees)\u{00B0}",
        attributes: [
            .font: font,
            .foregroundColor: textColor
        ]
    )
}

private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}

private static func rotationTextBackgroundFrame(
    for textFrame: CGRect
) -> CGRect {
    textFrame.insetBy(
        dx: -rotationTextHorizontalPadding,
        dy: -rotationTextVerticalPadding
    ).integral
}
```

## 修改三：macOS viewport 与 iOS 同步落地正式绘制逻辑

### 修改前

- `macOSCanvasViewportView` 在阶段 4 中也只是把 interaction overlay layer 树接上。
- `refreshRotationInteractionOverlay(from:)` 和 iOS 一样只做占位，不真正画内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改前 macOS 侧和 iOS 一样，只有 interaction overlay 生命周期，没有真实绘制。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = nil
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = nil
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = nil
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = CGRect(origin: payload.textScreenAnchor, size: .zero)
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}
```

### 修改后

- macOS 现在与 iOS 同步正式绘制：
  - `payload.ringScreenRect`
  - `payload.tickSegments`
  - `payload.zeroReferenceSegment`
  - `payload.currentAngleSegment`
  - `payload.textScreenAnchor`
- 这样两端在 interaction overlay 数据消费方式上保持镜像。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改后 macOS 也会真正画出圆环、刻度、指针和角度文本，保持与 iOS 的消费方式一致。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = !payload.isActive

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = CGPath(
        ellipseIn: payload.ringScreenRect,
        transform: nil
    )
    rotationRingLayer.isHidden = !payload.isActive
    rotationRingLayer.contentsScale = currentContentsScale

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = !payload.isActive
    rotationTickLayer.contentsScale = currentContentsScale

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = Self.lineSegmentsPath([
        payload.zeroReferenceSegment,
        payload.currentAngleSegment
    ])
    rotationPointerLayer.isHidden = !payload.isActive
    rotationPointerLayer.contentsScale = currentContentsScale

    let attributedText = Self.rotationAttributedText(for: payload)
    let textFrame = Self.rotationTextFrame(
        for: attributedText,
        anchoredAt: payload.textScreenAnchor
    )
    let textBackgroundFrame = Self.rotationTextBackgroundFrame(
        for: textFrame
    )

    rotationTextBackgroundLayer.frame = bounds
    rotationTextBackgroundLayer.path = CGPath(
        roundedRect: textBackgroundFrame,
        cornerWidth: Self.rotationTextCornerRadius,
        cornerHeight: Self.rotationTextCornerRadius,
        transform: nil
    )
    rotationTextBackgroundLayer.isHidden = !payload.isActive
    rotationTextBackgroundLayer.contentsScale = currentContentsScale

    rotationTextLayer.frame = textFrame
    rotationTextLayer.string = attributedText
    rotationTextLayer.isHidden = !payload.isActive
    rotationTextLayer.contentsScale = currentContentsScale
}
```

## 修改四：macOS 同步新增角度文本与路径 helper

### 修改前

- macOS viewport 也没有 interaction overlay 的文本与路径 helper。
- 即使后续要显示角度值，也缺少：
  - 文本样式
  - 文本 frame
  - 背景框 frame
  - 线段转 path 的帮助函数

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 常量区 / 静态 helper 区
// 功能说明: 修改前 macOS 没有 interaction overlay 的文本与路径 helper。
private static let rotateGuideLineWidth: CGFloat = 2
private static let rotateHandleLineWidth: CGFloat = 2
private static let rotateHandleSize: CGFloat = 12
```

### 修改后

- 新增与 iOS 对齐的文本常量和 helper。
- 差异只在字体与颜色取值：
  - iOS 用 `UIFont` / `UIColor`
  - macOS 用 `NSFont` / `NSColor`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: 常量区 / lineSegmentsPath(_) / rotationAttributedText(for:) /
//        rotationTextFrame(for:anchoredAt:) / rotationTextBackgroundFrame(for:)
// 功能说明: 修改后 macOS 也补齐 interaction overlay 的路径拼接与角度文字排版 helper。
private static let rotateGuideLineWidth: CGFloat = 2
private static let rotateHandleLineWidth: CGFloat = 2
private static let rotateHandleSize: CGFloat = 12
private static let rotationTextFontSize: CGFloat = 12
private static let rotationTextHorizontalPadding: CGFloat = 8
private static let rotationTextVerticalPadding: CGFloat = 4
private static let rotationTextCornerRadius: CGFloat = 8

private static func lineSegmentsPath(
    _ segments: [CanvasInteractionLineSegment]
) -> CGPath {
    let path = CGMutablePath()

    for segment in segments {
        path.move(to: segment.start)
        path.addLine(to: segment.end)
    }

    return path
}

private static func rotationAttributedText(
    for payload: CanvasRotationInteractionOverlayPayload
) -> NSAttributedString {
    let degrees = Int(payload.displayDegrees0To360.rounded())
    let displayDegrees = degrees == 360 ? 360 : max(0, degrees)
    let font = NSFont.monospacedDigitSystemFont(
        ofSize: rotationTextFontSize,
        weight: .semibold
    )
    let textColor = NSColor(cgColor: selectionStrokeColor) ?? .controlAccentColor

    return NSAttributedString(
        string: "\(displayDegrees)\u{00B0}",
        attributes: [
            .font: font,
            .foregroundColor: textColor
        ]
    )
}

private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}

private static func rotationTextBackgroundFrame(
    for textFrame: CGRect
) -> CGRect {
    textFrame.insetBy(
        dx: -rotationTextHorizontalPadding,
        dy: -rotationTextVerticalPadding
    ).integral
}
```

## 本阶段完成后的代码行为

1. 旋转中的 interaction overlay 已经不再是空占位 layer。
2. 两端现在都会真正绘制：
  - 圆环
  - 36 个刻度段
  - 0° 基准线
  - 当前角度线
  - 当前角度文本与背景框
3. 当前角度文本使用整数度数显示，符合阶段 3 已确定的 `0~360` 角度语义。

## 校验结果

- 对以下文件执行过 lint 检查，未发现新增错误：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
