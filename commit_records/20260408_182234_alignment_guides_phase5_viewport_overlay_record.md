# 20260408_182234_alignment_guides_phase5_viewport_overlay_record

## 记录范围

- 记录内容：
  1. 在 iOS / macOS viewport 中新增 alignment 专用 `CAShapeLayer`，把 transient `guideSegments` 真正画出来。
  2. 将 `refreshInteractionOverlay()` 的 `.alignment` 分支从占位隐藏切换为真实绘制入口。
  3. 补齐 alignment / rotation overlay 的互斥刷新与统一清理逻辑，避免拖拽后残留旧路径。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 当前 changes 依据：
  - `git status --short` 当前显示：
    - `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
    - `M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `git diff --stat -- MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 当前显示：
    - `2 files changed, 120 insertions(+), 16 deletions(-)`
  - `git diff -- ...` 显示：本次修改集中在 alignment 图层注册、`.alignment` 分支接线、alignment/rotation 互斥刷新，以及 interaction overlay 的统一清理收口。
- 验证依据：
  - `ReadLints`：`iOSCanvasViewportView.swift`、`macOSCanvasViewportView.swift` 无新增诊断问题。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS"`：通过。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator"`：通过。
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`：单独重跑后通过。
  - 如实说明：第一次把上述 `test` 命令与双端 `build` 并发执行时，出现 `Early unexpected exit, operation never finished bootstrapping`；随后同一测试命令单独重跑通过，未见断言失败。
- 本记录不包含：
  - `Phase 6` 的交互回归与吸附手感验证
  - git commit / push
  - solver / controller / session / renderer 层的新改动

## 修改一：双端 viewport 新增 alignment 专用图层与样式入口

### 修改前

- iOS viewport 的 `interactionOverlayLayer` 只挂了 rotation 相关图层，没有 alignment 专用 `CAShapeLayer`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers() / configureInteractionOverlayLayer()
// 功能说明: 修改前 iOS viewport 只为 rotation overlay 注册子图层；alignment overlay 还没有独立的 shape layer 和样式入口。
private let interactionOverlayLayer = CALayer()
private let rotationRingLayer = CAShapeLayer()
private let rotationTickLayer = CAShapeLayer()
private let rotationPointerLayer = CAShapeLayer()

private func setupLayers() {
    ...
    overlayLayer.addSublayer(interactionOverlayLayer)
    ...
    interactionOverlayLayer.addSublayer(rotationRingLayer)
    interactionOverlayLayer.addSublayer(rotationTickLayer)
    interactionOverlayLayer.addSublayer(rotationPointerLayer)
    interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
    interactionOverlayLayer.addSublayer(rotationTextLayer)
    ...
    configureInteractionOverlayLayer()
    configureRotationRingLayer()
    configureRotationTickLayer()
    ...
}

private func configureInteractionOverlayLayer() {
    interactionOverlayLayer.isHidden = true
}
```

- macOS viewport 的 layer 注册结构与 iOS 同样只覆盖 rotation overlay。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / configureInteractionOverlayLayer()
// 功能说明: 修改前 macOS viewport 也没有 alignment 图层，interaction overlay 只能承载 rotation 相关形状。
private let interactionOverlayLayer = CALayer()
private let rotationRingLayer = CAShapeLayer()
private let rotationTickLayer = CAShapeLayer()
private let rotationPointerLayer = CAShapeLayer()

private func setupLayers() {
    ...
    overlayLayer.addSublayer(interactionOverlayLayer)
    ...
    interactionOverlayLayer.addSublayer(rotationRingLayer)
    interactionOverlayLayer.addSublayer(rotationTickLayer)
    interactionOverlayLayer.addSublayer(rotationPointerLayer)
    interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
    interactionOverlayLayer.addSublayer(rotationTextLayer)
    ...
    configureInteractionOverlayLayer()
    configureRotationRingLayer()
    configureRotationTickLayer()
    ...
}

private func configureInteractionOverlayLayer() {
    interactionOverlayLayer.isHidden = true
}
```

### 修改后

- 双端都新增 `alignmentGuideLayer` 与 `alignmentGuideLineWidth`，并复用现有 `selectionStrokeColor` 作为第一版辅助线颜色。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers() / configureAlignmentGuideLayer()
// 功能说明: 修改后 iOS viewport 为 alignment overlay 注册了独立 shape layer，并在初始化阶段完成线宽、颜色与圆角端点配置。
private static let alignmentGuideLineWidth: CGFloat = 2

private let interactionOverlayLayer = CALayer()
private let alignmentGuideLayer = CAShapeLayer()
private let rotationRingLayer = CAShapeLayer()

private func setupLayers() {
    ...
    overlayLayer.addSublayer(interactionOverlayLayer)
    ...
    interactionOverlayLayer.addSublayer(alignmentGuideLayer)
    interactionOverlayLayer.addSublayer(rotationRingLayer)
    interactionOverlayLayer.addSublayer(rotationTickLayer)
    interactionOverlayLayer.addSublayer(rotationPointerLayer)
    interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
    interactionOverlayLayer.addSublayer(rotationTextLayer)
    ...
    configureInteractionOverlayLayer()
    configureAlignmentGuideLayer()
    configureRotationRingLayer()
    ...
}

private func configureAlignmentGuideLayer() {
    alignmentGuideLayer.fillColor = nil
    alignmentGuideLayer.strokeColor = Self.selectionStrokeColor
    alignmentGuideLayer.lineWidth = Self.alignmentGuideLineWidth
    alignmentGuideLayer.lineCap = .round
    alignmentGuideLayer.lineJoin = .round
    alignmentGuideLayer.isHidden = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers() / configureAlignmentGuideLayer()
// 功能说明: 修改后 macOS viewport 与 iOS 对称，新增 alignmentGuideLayer 作为 transient 辅助线的实际承载层。
private static let alignmentGuideLineWidth: CGFloat = 2

private let interactionOverlayLayer = CALayer()
private let alignmentGuideLayer = CAShapeLayer()
private let rotationRingLayer = CAShapeLayer()

private func setupLayers() {
    ...
    overlayLayer.addSublayer(interactionOverlayLayer)
    ...
    interactionOverlayLayer.addSublayer(alignmentGuideLayer)
    interactionOverlayLayer.addSublayer(rotationRingLayer)
    interactionOverlayLayer.addSublayer(rotationTickLayer)
    interactionOverlayLayer.addSublayer(rotationPointerLayer)
    interactionOverlayLayer.addSublayer(rotationTextBackgroundLayer)
    interactionOverlayLayer.addSublayer(rotationTextLayer)
    ...
    configureInteractionOverlayLayer()
    configureAlignmentGuideLayer()
    configureRotationRingLayer()
    ...
}

private func configureAlignmentGuideLayer() {
    alignmentGuideLayer.fillColor = nil
    alignmentGuideLayer.strokeColor = Self.selectionStrokeColor
    alignmentGuideLayer.lineWidth = Self.alignmentGuideLineWidth
    alignmentGuideLayer.lineCap = .round
    alignmentGuideLayer.lineJoin = .round
    alignmentGuideLayer.isHidden = true
}
```

## 修改二：`.alignment` 分支从占位隐藏改为真实绘制入口

### 修改前

- 双端 `refreshInteractionOverlay()` 都把 `.alignment` 当作占位合同处理，直接 `hideInteractionOverlay()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改前 iOS viewport 在拿到 alignment interaction overlay 时不会绘制任何线段，而是直接隐藏 interaction overlay。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    case .alignment:
        hideInteractionOverlay()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改前 macOS viewport 对 alignment 分支也只有占位隐藏逻辑，因此 renderer 下发的 guideSegments 无法可视化。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    case .alignment:
        hideInteractionOverlay()
    }
}
```

### 修改后

- 双端 `.alignment` 分支都切到 `refreshAlignmentInteractionOverlay(from:)`，viewport 仍然只负责画，不负责算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改后 iOS viewport 会把 renderer 生成的 alignment overlay 转发给专用绘制函数，真正写入 alignmentGuideLayer。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    case .alignment:
        refreshAlignmentInteractionOverlay(from: interactionOverlay)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改后 macOS viewport 与 iOS 一致，把 alignment overlay 切到专用绘制逻辑，而不是直接隐藏。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    case .alignment:
        refreshAlignmentInteractionOverlay(from: interactionOverlay)
    }
}
```

## 修改三：新增 alignment 绘制函数，并把 rotation/alignment 切换改成互斥显示

### 修改前

- `refreshRotationInteractionOverlay(...)` 只根据 `payload.isActive` 直接切 `isHidden`，但不会主动清掉 alignment 图层。
- alignment 侧没有自己的绘制函数，也不会把 `guideSegments` 转为 path。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改前 rotation overlay 只控制自身图层显隐；alignment 图层还不存在，也没有 guideSegments 的 path 构建入口。
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

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = !payload.isActive

    rotationPointerLayer.frame = bounds
    rotationPointerLayer.path = Self.lineSegmentsPath([
        payload.zeroReferenceSegment,
        payload.currentAngleSegment
    ])
    rotationPointerLayer.isHidden = !payload.isActive
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:)
// 功能说明: 修改前 macOS rotation overlay 同样只处理 rotation 自身显隐，alignment 没有专用渲染路径。
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

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = !payload.isActive
}
```

### 修改后

- rotation 分支先 `guard payload.isActive`，再显式隐藏 alignment 图层。
- alignment 分支新增 `refreshAlignmentInteractionOverlay(from:)`，直接把 `payload.guideSegments` 转成 `CGPath`。
- 这样即使 `interactionOverlay` 仍然是单值，viewport 侧也能保证当前帧只显示一种 transient overlay。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:) / refreshAlignmentInteractionOverlay(from:)
// 功能说明: 修改后 iOS viewport 会在 rotation/alignment 之间显式互斥；alignment 分支负责把 guideSegments 转为 path 并写到 alignmentGuideLayer。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    guard payload.isActive else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = false
    hideAlignmentInteractionOverlayLayer()

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = CGPath(
        ellipseIn: payload.ringScreenRect,
        transform: nil
    )
    rotationRingLayer.isHidden = false

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = false
}

private func refreshAlignmentInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .alignment(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    guard payload.isActive else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = false
    hideRotationInteractionOverlayLayers()

    alignmentGuideLayer.frame = bounds
    alignmentGuideLayer.path = payload.guideSegments.isEmpty
        ? nil
        : Self.lineSegmentsPath(payload.guideSegments)
    alignmentGuideLayer.isHidden = payload.guideSegments.isEmpty
    alignmentGuideLayer.contentsScale = currentContentsScale
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshRotationInteractionOverlay(from:) / refreshAlignmentInteractionOverlay(from:)
// 功能说明: 修改后 macOS viewport 也采用同一套互斥策略；alignment guide 会直接复用 lineSegmentsPath(...) 生成蓝色辅助线路径。
private func refreshRotationInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .rotation(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    guard payload.isActive else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = false
    hideAlignmentInteractionOverlayLayer()

    rotationRingLayer.frame = bounds
    rotationRingLayer.path = CGPath(
        ellipseIn: payload.ringScreenRect,
        transform: nil
    )
    rotationRingLayer.isHidden = false

    rotationTickLayer.frame = bounds
    rotationTickLayer.path = Self.lineSegmentsPath(payload.tickSegments)
    rotationTickLayer.isHidden = false
}

private func refreshAlignmentInteractionOverlay(
    from interactionOverlay: CanvasInteractionRenderOverlay
) {
    guard case let .alignment(payload) = interactionOverlay.payload else {
        hideInteractionOverlay()
        return
    }

    guard payload.isActive else {
        hideInteractionOverlay()
        return
    }

    interactionOverlayLayer.isHidden = false
    hideRotationInteractionOverlayLayers()

    alignmentGuideLayer.frame = bounds
    alignmentGuideLayer.path = payload.guideSegments.isEmpty
        ? nil
        : Self.lineSegmentsPath(payload.guideSegments)
    alignmentGuideLayer.isHidden = payload.guideSegments.isEmpty
    alignmentGuideLayer.contentsScale = currentContentsScale
}
```

## 修改四：统一 hide 逻辑，避免 overlay 切换或拖拽结束后的残留

### 修改前

- `hideInteractionOverlay()` 只清 rotation 相关图层；由于没有 alignment 专用图层，一旦开始画辅助线，这里就缺少统一收尾点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: hideInteractionOverlay()
// 功能说明: 修改前 iOS viewport 的 hide 逻辑只负责 rotation 图层复位，还没有 alignment overlay 的清理入口。
private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true

    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true

    rotationTextBackgroundLayer.path = nil
    rotationTextBackgroundLayer.frame = .zero
    rotationTextBackgroundLayer.isHidden = true

    rotationTextLayer.frame = .zero
    rotationTextLayer.string = nil
    rotationTextLayer.isHidden = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: hideInteractionOverlay()
// 功能说明: 修改前 macOS viewport 也只有 rotation 清理逻辑，没有 alignment 图层的统一收尾函数。
private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true

    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true
}
```

### 修改后

- 新增 `hideAlignmentInteractionOverlayLayer()` 和 `hideRotationInteractionOverlayLayers()`。
- `hideInteractionOverlay()` 变成统一收口点，既负责整体隐藏，也负责两类 transient overlay 各自复位。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: hideInteractionOverlay() / hideAlignmentInteractionOverlayLayer() / hideRotationInteractionOverlayLayers()
// 功能说明: 修改后 iOS viewport 的 hide 逻辑被拆成“总入口 + alignment 清理 + rotation 清理”，保证 overlay 切换与拖拽结束时不会残留路径。
private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true
    hideAlignmentInteractionOverlayLayer()
    hideRotationInteractionOverlayLayers()
}

private func hideAlignmentInteractionOverlayLayer() {
    alignmentGuideLayer.path = nil
    alignmentGuideLayer.frame = bounds
    alignmentGuideLayer.isHidden = true
}

private func hideRotationInteractionOverlayLayers() {
    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: hideInteractionOverlay() / hideAlignmentInteractionOverlayLayer() / hideRotationInteractionOverlayLayers()
// 功能说明: 修改后 macOS viewport 与 iOS 对称，把 alignment 与 rotation 的清理职责拆开，再由 hideInteractionOverlay() 统一收口。
private func hideInteractionOverlay() {
    interactionOverlayLayer.isHidden = true
    hideAlignmentInteractionOverlayLayer()
    hideRotationInteractionOverlayLayers()
}

private func hideAlignmentInteractionOverlayLayer() {
    alignmentGuideLayer.path = nil
    alignmentGuideLayer.frame = bounds
    alignmentGuideLayer.isHidden = true
}

private func hideRotationInteractionOverlayLayers() {
    rotationRingLayer.path = nil
    rotationRingLayer.frame = bounds
    rotationRingLayer.isHidden = true

    rotationTickLayer.path = nil
    rotationTickLayer.frame = bounds
    rotationTickLayer.isHidden = true

    rotationPointerLayer.path = nil
    rotationPointerLayer.frame = bounds
    rotationPointerLayer.isHidden = true
}
```

## 修改结果

- `Phase 5` 已把 `CanvasRenderer` 传下来的 `alignment` transient overlay 在 iOS / macOS viewport 中真正画出来。
- viewport 仍然只负责把 `guideSegments` 渲染成线段，不承担任何 alignment 求解逻辑。
- `rotation` 与 `alignment` 仍保持单值 overlay 模型，但 viewport 侧已经具备稳定的互斥显示与清理行为。
- 当前工作区只包含这两个 viewport 文件的未提交修改。
