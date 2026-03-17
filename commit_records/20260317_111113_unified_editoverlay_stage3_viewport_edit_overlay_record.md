# 20260317_111113_unified_editoverlay_stage3_viewport_edit_overlay_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 中把 selection / rotate 的 viewport 刷新入口收口到统一的 `refreshEditOverlay()`。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中同步迁移到统一 `editOverlay` 消费链。
  3. 把两个平台的 selection corner handles 从轴对齐方块改为基于 `screenRotationRadians` 绘制旋转 path，让方块和高亮框在视觉上同角度。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - iOS / macOS controller 的统一 handle 命中迁移
  - crop payload / inline session 的 typed 收口
  - 删除旧 overlay 字段
  - 原始 gif diff
  - git commit / push

## 修改一：iOS viewport 从并行 `selection / rotate` 刷新切到统一 `refreshEditOverlay()`

### 修改前

- `didMoveToWindow()` 和 `apply(_:)` 会分别调用 `refreshSelectionOverlay()` 与 `refreshRotateOverlay()`。
- iOS viewport 同时消费 `snapshot.selectionOverlay` 和 `snapshot.rotateOverlay` 两条旧链路。
- selection 与 rotate 在平台层仍然是两套并行 chrome，rotate mode 下不能继续复用 selection 的四角方块。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshSelectionOverlay() / refreshRotateOverlay()
// 功能说明: 修改前 iOS viewport 仍分别刷新 selection overlay 和 rotate overlay，平台层存在两套并行入口。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
        refreshCropOverlay()
        refreshRotateOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
        refreshCropOverlay()
        refreshRotateOverlay()
    }
}

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    selectionOutlineLayer.path = Self.quadPath(for: selectionOverlay.screenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale
    // ... 继续用 selectionOverlay.handles 刷新四角方块 ...
}

private func refreshRotateOverlay() {
    guard let rotateOverlay = snapshot.rotateOverlay else {
        hideRotateOverlay()
        return
    }

    rotateGuideLayer.path = {
        let path = UIBezierPath()
        path.move(to: rotateOverlay.guideScreenStart)
        path.addLine(to: rotateOverlay.guideScreenEnd)
        return path.cgPath
    }()
    rotateGuideLayer.isHidden = false

    rotateOutlineLayer.path = Self.quadPath(for: rotateOverlay.screenQuad)
    rotateOutlineLayer.isHidden = false
    // ... 再单独绘制 rotate handle ...
}
```

### 修改后

- `didMoveToWindow()` 和 `apply(_:)` 统一改为调用 `refreshEditOverlay()`。
- `refreshEditOverlay()` 直接消费 `snapshot.editOverlay`，按 `kind` 分发为：
  - `.selection`：只画 shared selection chrome
  - `.rotate`：先画 shared selection chrome，再叠加 rotate guide / rotate handle
  - `.crop`：本阶段不并入，继续隐藏 selection / rotate chrome
- rotate mode 下不再单独画一套 rotate outline，而是直接复用 shared selection outline + corner handles，让整个 overlay 作为一个整体显示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: didMoveToWindow() / apply(_:) / refreshEditOverlay() / refreshSelectionChrome(from:) / refreshRotateChrome(from:)
// 功能说明: 修改后 iOS viewport 统一从 snapshot.editOverlay 消费 selection / rotate 几何，rotate mode 继续显示与高亮框同角度的四角方块。
override func didMoveToWindow() {
    super.didMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
}

private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideRotateOverlay()
    case .rotate:
        refreshSelectionChrome(from: editOverlay)
        refreshRotateChrome(from: editOverlay)
    case .crop:
        hideEditOverlay()
    }
}

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    // Selection and rotate now share one neutral edit overlay source; the
    // viewport only decides stroke, handle size, and per-platform drawing.
    selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale
    // ... 继续从 editOverlay.cornerHandles 刷新四角方块 ...
}

private func refreshRotateChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .rotate(payload) = editOverlay.payload else {
        hideRotateOverlay()
        return
    }

    let guidePath = CGMutablePath()
    guidePath.move(to: payload.guideScreenStart)
    guidePath.addLine(to: payload.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false

    rotateOutlineLayer.path = nil
    rotateOutlineLayer.isHidden = true
    // ... 继续绘制 rotate handle ...
}
```

## 修改二：iOS selection handles 从轴对齐方块改为按旋转角绘制

### 修改前

- selection handle 通过 `selectionHandleRect(centeredAt:)` 生成轴对齐 `CGRect`。
- 即使 handle 的位置跟着旋转后的角点移动，形状本身仍然是屏幕对齐的小方块。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay() / selectionHandleRect(centeredAt:)
// 功能说明: 修改前 iOS selection handles 只根据中心点生成轴对齐方块，还没有消费 shared handle 的旋转语义。
for role in CanvasSelectionHandleRole.allCases {
    guard
        let handleLayer = selectionHandleLayers[role],
        let handle = selectionOverlay.handles.first(where: { $0.role == role })
    else {
        selectionHandleLayers[role]?.path = nil
        selectionHandleLayers[role]?.frame = .zero
        selectionHandleLayers[role]?.isHidden = true
        continue
    }

    let handleRect = Self.selectionHandleRect(centeredAt: handle.screenCenter)
    handleLayer.frame = handleRect
    handleLayer.path = CGPath(
        rect: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    handleLayer.isHidden = false
}

private static func selectionHandleRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - selectionHandleSize / 2,
        y: center.y - selectionHandleSize / 2,
        width: selectionHandleSize,
        height: selectionHandleSize
    ).standardized
}
```

### 修改后

- iOS viewport 通过 `editHandleRole(for:)` 把旧 selection role 映射到统一 `CanvasEditHandleRole`。
- `refreshSelectionChrome(from:)` 从 `editOverlay.cornerHandles` 中读取 `screenCenter + screenRotationRadians`。
- `selectionHandlePath(centeredAt:rotationRadians:)` 使用 `cos / sin` 旋转四个局部角点，直接生成旋转后的方块 path。
- 因此 selection state 和 rotate state 的四角方块都会和 outline 同角度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshSelectionChrome(from:) / editHandleRole(for:) / selectionHandlePath(centeredAt:rotationRadians:)
// 功能说明: 修改后 iOS selection handles 直接消费 shared edit handle 的旋转角，生成与高亮框同角度的旋转方块 path。
for role in CanvasSelectionHandleRole.allCases {
    guard
        let handleLayer = selectionHandleLayers[role],
        let handle = editOverlay.cornerHandles.first(where: {
            $0.role == Self.editHandleRole(for: role)
        })
    else {
        selectionHandleLayers[role]?.path = nil
        selectionHandleLayers[role]?.frame = .zero
        selectionHandleLayers[role]?.isHidden = true
        continue
    }

    handleLayer.frame = bounds
    handleLayer.path = Self.selectionHandlePath(
        centeredAt: handle.screenCenter,
        rotationRadians: handle.screenRotationRadians
    )
    handleLayer.isHidden = false
}

private static func editHandleRole(
    for role: CanvasSelectionHandleRole
) -> CanvasEditHandleRole {
    switch role {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    }
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = selectionHandleSize / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

## 修改三：macOS viewport 同步迁移到统一 `refreshEditOverlay()`

### 修改前

- `macOSCanvasViewportView` 和 iOS 一样，也是在 `viewDidMoveToWindow()` / `apply(_:)` 中分别调用 `refreshSelectionOverlay()` 与 `refreshRotateOverlay()`。
- selection / rotate 各自读取旧 overlay，平台层仍有两条并行绘制链。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: viewDidMoveToWindow() / apply(_:) / refreshSelectionOverlay() / refreshRotateOverlay()
// 功能说明: 修改前 macOS viewport 和 iOS 一样，selection / rotate 仍分别消费旧 overlay，尚未切到统一 editOverlay。
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
        refreshCropOverlay()
        refreshRotateOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshSelectionOverlay()
        refreshCropOverlay()
        refreshRotateOverlay()
    }
}

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    selectionOutlineLayer.path = Self.quadPath(for: selectionOverlay.screenQuad)
    selectionOutlineLayer.isHidden = false
    // ... 继续单独刷新四角方块 ...
}

private func refreshRotateOverlay() {
    guard let rotateOverlay = snapshot.rotateOverlay else {
        hideRotateOverlay()
        return
    }

    let guidePath = CGMutablePath()
    guidePath.move(to: rotateOverlay.guideScreenStart)
    guidePath.addLine(to: rotateOverlay.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false

    rotateOutlineLayer.path = Self.quadPath(for: rotateOverlay.screenQuad)
    rotateOutlineLayer.isHidden = false
    // ... 再单独绘制 rotate handle ...
}
```

### 修改后

- macOS 端同样新增 `refreshEditOverlay()`，统一读取 `snapshot.editOverlay`。
- `.selection` 与 `.rotate` 共用 `refreshSelectionChrome(from:)`；旋转态再额外叠加 `refreshRotateChrome(from:)`。
- 这样 iOS / macOS viewport 的 selection / rotate 渲染结构被对齐，后续 controller 阶段可以开始面向统一 `editOverlay` 做 hit test 收口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: viewDidMoveToWindow() / apply(_:) / refreshEditOverlay() / refreshSelectionChrome(from:) / refreshRotateChrome(from:)
// 功能说明: 修改后 macOS viewport 与 iOS 对齐，统一通过 editOverlay 刷新 selection / rotate chrome。
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateBackgroundAppearance()
    performWithoutLayerActions {
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
}

func apply(_ snapshot: CanvasRenderSnapshot) {
    self.snapshot = snapshot
    performWithoutLayerActions {
        updateLayerFrames()
        refreshImageLayers()
        refreshBoardHighlight()
        refreshEditOverlay()
        refreshCropOverlay()
    }
}

private func refreshEditOverlay() {
    guard let editOverlay = snapshot.editOverlay else {
        hideEditOverlay()
        return
    }

    switch editOverlay.kind {
    case .selection:
        refreshSelectionChrome(from: editOverlay)
        hideRotateOverlay()
    case .rotate:
        refreshSelectionChrome(from: editOverlay)
        refreshRotateChrome(from: editOverlay)
    case .crop:
        hideEditOverlay()
    }
}

private func refreshSelectionChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    selectionOutlineLayer.path = Self.quadPath(for: editOverlay.activeScreenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale
    // ... 继续从 editOverlay.cornerHandles 刷新四角方块 ...
}

private func refreshRotateChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .rotate(payload) = editOverlay.payload else {
        hideRotateOverlay()
        return
    }

    let guidePath = CGMutablePath()
    guidePath.move(to: payload.guideScreenStart)
    guidePath.addLine(to: payload.guideScreenEnd)
    rotateGuideLayer.path = guidePath
    rotateGuideLayer.isHidden = false

    rotateOutlineLayer.path = nil
    rotateOutlineLayer.isHidden = true
    // ... 继续绘制 rotate handle ...
}
```

## 修改四：macOS selection handles 同步改为按旋转角绘制

### 修改前

- macOS selection handles 也通过 `selectionHandleRect(centeredAt:)` 画轴对齐方块。
- 因此在旋转后的 item 上，方块虽然移动到四个角点，但本身不会和 outline 一起转。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshSelectionOverlay() / selectionHandleRect(centeredAt:)
// 功能说明: 修改前 macOS selection handles 只按中心点画轴对齐方块，还未接入 shared handle 的 screenRotationRadians。
for role in CanvasSelectionHandleRole.allCases {
    guard
        let handleLayer = selectionHandleLayers[role],
        let handle = selectionOverlay.handles.first(where: { $0.role == role })
    else {
        selectionHandleLayers[role]?.path = nil
        selectionHandleLayers[role]?.frame = .zero
        selectionHandleLayers[role]?.isHidden = true
        continue
    }

    let handleRect = Self.selectionHandleRect(centeredAt: handle.screenCenter)
    handleLayer.frame = handleRect
    handleLayer.path = CGPath(
        rect: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    handleLayer.isHidden = false
}

private static func selectionHandleRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - selectionHandleSize / 2,
        y: center.y - selectionHandleSize / 2,
        width: selectionHandleSize,
        height: selectionHandleSize
    ).standardized
}
```

### 修改后

- macOS 端和 iOS 一样，从 `editOverlay.cornerHandles` 读取统一 handle 语义。
- `selectionHandlePath(centeredAt:rotationRadians:)` 也改成用旋转后的四个局部角点直接生成 path。
- 这一步让两个平台都达到阶段三目标：selection 方块与高亮框作为一个整体显示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshSelectionChrome(from:) / editHandleRole(for:) / selectionHandlePath(centeredAt:rotationRadians:)
// 功能说明: 修改后 macOS selection handles 与 iOS 对齐，统一按 shared edit handle 的旋转角绘制路径。
for role in CanvasSelectionHandleRole.allCases {
    guard
        let handleLayer = selectionHandleLayers[role],
        let handle = editOverlay.cornerHandles.first(where: {
            $0.role == Self.editHandleRole(for: role)
        })
    else {
        selectionHandleLayers[role]?.path = nil
        selectionHandleLayers[role]?.frame = .zero
        selectionHandleLayers[role]?.isHidden = true
        continue
    }

    handleLayer.frame = bounds
    handleLayer.path = Self.selectionHandlePath(
        centeredAt: handle.screenCenter,
        rotationRadians: handle.screenRotationRadians
    )
    handleLayer.isHidden = false
}

private static func editHandleRole(
    for role: CanvasSelectionHandleRole
) -> CanvasEditHandleRole {
    switch role {
    case .topLeading:
        return .topLeading
    case .topTrailing:
        return .topTrailing
    case .bottomLeading:
        return .bottomLeading
    case .bottomTrailing:
        return .bottomTrailing
    }
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = selectionHandleSize / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

## 影响与边界

- 阶段三后，iOS / macOS viewport 已经优先消费 `snapshot.editOverlay` 来绘制 selection / rotate chrome。
- `refreshCropOverlay()` 本阶段仍然保留，crop 还没有并入统一 `refreshEditOverlay()`。
- controller 端目前还没有迁移到统一 `hitTestEditHandle()`，所以命中分发逻辑仍使用旧入口；这属于阶段四任务。
- shared 层的旧 `selectionOverlay / rotateOverlay` 仍保留，当前只是 viewport 不再依赖它们进行 selection / rotate 绘制。

## 验证

```bash
# 功能说明: 阶段三构建验证命令，用于确认双平台 viewport 切到 editOverlay 后，selection / rotate / crop 的现有编译链路仍保持通过。
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ".build_editoverlay_stage3_ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ".build_editoverlay_stage3_macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

- 验证结果：
  - `ReadLints` 对 `iOSCanvasViewportView.swift`、`macOSCanvasViewportView.swift` 无报错。
  - iOS Simulator Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - macOS Debug build 通过，日志末尾为 `** BUILD SUCCEEDED **`。
  - 写记录前执行 `git status --short`，只显示两个 viewport 文件被修改，符合阶段三只动平台视图层的预期。
