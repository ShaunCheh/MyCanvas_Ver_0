# 20260316_211848_phase_bplus_stage5_inline_rotate_mode_record

## 记录范围

- 记录内容：
  1. 为 shared geometry / snapshot / renderer 新增 rotate overlay 语义，并让 inline rotate 能预览 draft rotation。
  2. 在 `CanvasScene` 中补齐 `rotateItem(...)` 与共享 resize 写入口，继续保持“controller 算交互几何，scene 落持久状态”。
  3. 在 iOS / macOS viewport 上新增 rotate outline / guide / handle，并把 selection outline 从轴对齐矩形改成真实 quad。
  4. 在 iOS / macOS controller 中接入 `Rotate / Done` 入口、rotate handle 命中、draft 旋转、旋转后命中测试，以及基于 item local axes 的 resize。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 阶段六的 undo / redo 命令入口接线
  - 原始 gif diff
  - 手动交互录屏
  - git commit / push
  - 构建产物目录 `.build_stage5_ios` / `.build_stage5_macos`

## 修改一：为 shared geometry / snapshot / renderer 增加 rotate overlay 语义

### 修改前

- `CanvasQuad` 只有 corner points、`boundingRect` 和 `map(...)`，还没有“中心点 / 边中点 / 角度归一化”这类 rotate 共享 helper。
- `CanvasRenderSnapshot` 只有 `selectionOverlay` 和 `cropOverlay`，没有 rotate overlay。
- `CanvasRenderer` 只会产出 selection / crop overlay；inline edit 时也只对 `.crop` 做 gate，不会预览 draft rotation。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名/类型名: CanvasQuad
// 功能说明: 修改前 quad 只提供 corners、AABB 与 map，shared 层还不能直接拿到旋转手柄所需的中心点 / 边中点。
struct CanvasQuad: Equatable {
    let topLeading: CGPoint
    let topTrailing: CGPoint
    let bottomLeading: CGPoint
    let bottomTrailing: CGPoint

    var points: [CGPoint] {
        [
            topLeading,
            topTrailing,
            bottomTrailing,
            bottomLeading
        ]
    }

    var boundingRect: CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        // ... 省略未改动代码 ...
    }

    func map(_ transform: (CGPoint) -> CGPoint) -> CanvasQuad {
        CanvasQuad(
            topLeading: transform(topLeading),
            topTrailing: transform(topTrailing),
            bottomLeading: transform(bottomLeading),
            bottomTrailing: transform(bottomTrailing)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRenderSnapshot
// 功能说明: 修改前 snapshot 只承载 selection / crop overlay，没有 rotate overlay 的中性语义。
struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil,
        cropOverlay: nil
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot / makeSelectionOverlay / makeRenderItem
// 功能说明: 修改前 renderer 只会产出 selection / crop overlay；inline edit 只对 crop 做 gate，也不会预览 draft rotation。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    // ... 省略未改动代码 ...
    let selectionOverlay = makeSelectionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState
    )
    let cropOverlay = makeCropOverlay(
        scene: scene,
        camera: camera,
        inlineEditState: inlineEditState
    )

    return CanvasRenderSnapshot(
        viewportBounds: camera.viewportBounds,
        visibleWorldRect: visibleWorldRect,
        boardOverlay: boardOverlay,
        items: renderItems,
        selectionOverlay: selectionOverlay,
        cropOverlay: cropOverlay
    )
}

private func makeSelectionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?
) -> CanvasSelectionRenderOverlay? {
    guard inlineEditState?.mode != .crop else {
        return nil
    }
    // ... 省略未改动代码 ...
}

private func makeRenderItem(
    for item: CanvasImageItem,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState?
) -> CanvasRenderItem {
    let isEditingCropItem =
        inlineEditState?.mode == .crop &&
        inlineEditState?.itemID == item.id
    let worldQuad = isEditingCropItem ? item.fullImageWorldQuad : item.worldQuad
    // ... 省略未改动代码 ...
    return CanvasRenderItem(
        id: item.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(renderCenter),
        screenBoundsSize: CGSize(
            width: renderSize.width * camera.zoomScale,
            height: renderSize.height * camera.zoomScale
        ),
        contentsRect: contentsRect,
        rotationRadians: item.rotationRadians,
        cgImage: item.cgImage,
        zIndex: item.zIndex
    )
}
```

### 修改后

- `CanvasQuad` 新增 `center / topMidpoint / bottomMidpoint / leadingMidpoint / trailingMidpoint`，并补上 `normalizedCanvasAngle(...)`。
- `CanvasRenderSnapshot` 新增 `CanvasRotateRenderOverlay` 与 `rotateOverlay`，由 shared 层统一输出旋转中的中性几何。
- `CanvasRenderer` 新增：
  - `makeRotateOverlay(...)`
  - `previewedItem(...)`
  - `normalizedDirection(...)`
- inline edit 期间统一隐藏普通 selection overlay；rotate 模式下 render item 会直接预览 `draftRotationRadians`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasGeometry.swift
// 函数名/类型名: CanvasQuad.center / CanvasQuad.topMidpoint / normalizedCanvasAngle(_:)
// 功能说明: 修改后 shared geometry 直接提供旋转手柄定位与角度归一化 helper，renderer / controller 不再各自散落重复几何公式。
struct CanvasQuad: Equatable {
    let topLeading: CGPoint
    let topTrailing: CGPoint
    let bottomLeading: CGPoint
    let bottomTrailing: CGPoint

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

    var topMidpoint: CGPoint {
        midpoint(between: topLeading, and: topTrailing)
    }

    var bottomMidpoint: CGPoint {
        midpoint(between: bottomLeading, and: bottomTrailing)
    }

    var leadingMidpoint: CGPoint {
        midpoint(between: topLeading, and: bottomLeading)
    }

    var trailingMidpoint: CGPoint {
        midpoint(between: topTrailing, and: bottomTrailing)
    }

    // ... 省略 boundingRect / map 未改动代码 ...

    private func midpoint(
        between lhs: CGPoint,
        and rhs: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: (lhs.x + rhs.x) / 2,
            y: (lhs.y + rhs.y) / 2
        )
    }
}

func normalizedCanvasAngle(_ radians: CGFloat) -> CGFloat {
    atan2(sin(radians), cos(radians))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名/类型名: CanvasRotateHandleGeometry / CanvasRotateRenderOverlay / CanvasRenderSnapshot
// 功能说明: 修改后 snapshot 新增 rotate overlay 中性语义，由 shared renderer 统一给出 outline、guide 与 handle 几何。
struct CanvasRotateHandleGeometry {
    let screenCenter: CGPoint
}

// Rotate overlay keeps only semantic geometry for the current item outline,
// pivot guide, and rotate handle. Platforms still decide stroke, fill, and hit slop.
struct CanvasRotateRenderOverlay {
    let itemID: CanvasImageItemID
    let mode: CanvasInlineEditMode
    let worldQuad: CanvasQuad
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let guideScreenStart: CGPoint
    let guideScreenEnd: CGPoint
    let handle: CanvasRotateHandleGeometry
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let boardOverlay: CanvasBoardRenderOverlay?
    let items: [CanvasRenderItem]
    let selectionOverlay: CanvasSelectionRenderOverlay?
    let cropOverlay: CanvasCropRenderOverlay?
    let rotateOverlay: CanvasRotateRenderOverlay?

    static let empty = CanvasRenderSnapshot(
        viewportBounds: .zero,
        visibleWorldRect: .zero,
        boardOverlay: nil,
        items: [],
        selectionOverlay: nil,
        cropOverlay: nil,
        rotateOverlay: nil
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:interactionState:inlineEditState:) / makeRotateOverlay(scene:camera:inlineEditState:) / previewedItem(for:inlineEditState:)
// 功能说明: 修改后 renderer 会统一产出 rotate overlay，并在 rotate 模式下直接预览 draft rotation；selection overlay 也在任意 inline edit 时统一隐藏。
struct CanvasRenderer {
    private static let rotateHandleScreenOffset: CGFloat = 28

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState = CanvasInteractionState(),
        inlineEditState: CanvasInlineEditState? = nil
    ) -> CanvasRenderSnapshot {
        // ... 省略可见性与 renderItems 未改动代码 ...
        let selectionOverlay = makeSelectionOverlay(
            scene: scene,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState
        )
        let cropOverlay = makeCropOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        )
        let rotateOverlay = makeRotateOverlay(
            scene: scene,
            camera: camera,
            inlineEditState: inlineEditState
        )

        return CanvasRenderSnapshot(
            viewportBounds: camera.viewportBounds,
            visibleWorldRect: visibleWorldRect,
            boardOverlay: boardOverlay,
            items: renderItems,
            selectionOverlay: selectionOverlay,
            cropOverlay: cropOverlay,
            rotateOverlay: rotateOverlay
        )
    }

    private func makeSelectionOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        interactionState: CanvasInteractionState,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasSelectionRenderOverlay? {
        guard inlineEditState == nil else {
            return nil
        }
        // ... 省略未改动代码 ...
    }

    private func makeRotateOverlay(
        scene: CanvasScene,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasRotateRenderOverlay? {
        guard
            let inlineEditState,
            inlineEditState.mode == .rotate,
            let item = scene.item(withID: inlineEditState.itemID)
        else {
            return nil
        }

        let previewItem = previewedItem(
            for: item,
            inlineEditState: inlineEditState
        )
        let worldQuad = previewItem.worldQuad
        let screenQuad = camera.worldToViewport(worldQuad)
        let screenCenter = camera.worldToViewport(previewItem.center)
        let guideScreenStart = screenQuad.topMidpoint
        let outwardDirection = normalizedDirection(
            from: screenCenter,
            to: guideScreenStart
        )
        let guideScreenEnd = CGPoint(
            x: guideScreenStart.x + (outwardDirection.x * Self.rotateHandleScreenOffset),
            y: guideScreenStart.y + (outwardDirection.y * Self.rotateHandleScreenOffset)
        )

        return CanvasRotateRenderOverlay(
            itemID: previewItem.id,
            mode: inlineEditState.mode,
            worldQuad: worldQuad,
            screenQuad: screenQuad,
            screenCenter: screenCenter,
            guideScreenStart: guideScreenStart,
            guideScreenEnd: guideScreenEnd,
            handle: CanvasRotateHandleGeometry(screenCenter: guideScreenEnd)
        )
    }

    private func previewedItem(
        for item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?
    ) -> CanvasImageItem {
        guard
            let inlineEditState,
            inlineEditState.itemID == item.id
        else {
            return item
        }

        var previewItem = item
        switch inlineEditState.mode {
        case .crop:
            return previewItem
        case .rotate:
            previewItem.rotationRadians = inlineEditState.draftRotationRadians
            return previewItem
        }
    }
}
```

## 修改二：为 scene 补齐 rotateItem(...) 与共享 resize 写入入口

### 修改前

- `CanvasScene` 只有 `resizeItem(withID:to worldFrame:)` 的轴对齐 world frame 写法。
- shared 层还没有 `rotateItem(...)`；controller 如果要写旋转，只能自己直接改 item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:)
// 功能说明: 修改前 scene 只有 axis-aligned worldFrame resize，还没有 center/size 级共享写入口，也没有 rotate 提交 API。
@discardableResult
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        )
        item.size = standardizedFrame.size
        return item
    }
}
```

### 修改后

- `resizeItem(withID:to worldFrame:)` 继续保留，但转成调 `resizeItem(withID:toCenter:size:)`。
- 新增 `resizeItem(withID:toCenter:size:)`，把 rotate-aware resize 的最终落盘入口统一到 shared scene。
- 新增 `resizeItem(withID:toLocalFrame:)`，让 shared 层也能接受 local frame。
- 新增 `rotateItem(withID:to:)`，统一负责角度归一化和旋转持久化写入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: resizeItem(withID:to:) / resizeItem(withID:toCenter:size:) / resizeItem(withID:toLocalFrame:) / rotateItem(withID:to:)
// 功能说明: 修改后 scene 统一承接 worldFrame、center/size、localFrame 三种 resize 写法，并新增 rotateItem 作为旋转持久化入口。
@discardableResult
func resizeItem(withID id: CanvasImageItemID, to worldFrame: CGRect) -> CanvasImageItem? {
    let standardizedFrame = worldFrame.standardized
    guard standardizedFrame.width > 0, standardizedFrame.height > 0 else {
        return nil
    }

    return resizeItem(
        withID: id,
        toCenter: CGPoint(
            x: standardizedFrame.midX,
            y: standardizedFrame.midY
        ),
        size: standardizedFrame.size
    )
}

@discardableResult
func resizeItem(
    withID id: CanvasImageItemID,
    toCenter center: CGPoint,
    size: CGSize
) -> CanvasImageItem? {
    guard size.width > 0, size.height > 0 else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = center
        item.size = size
        return item
    }
}

@discardableResult
func resizeItem(
    withID id: CanvasImageItemID,
    toLocalFrame localFrame: CGRect
) -> CanvasImageItem? {
    let standardizedLocalFrame = localFrame.standardized
    guard
        standardizedLocalFrame.width > 0,
        standardizedLocalFrame.height > 0
    else {
        return nil
    }

    return updateItem(withID: id) { item in
        item.center = item.worldPoint(
            fromLocal: CGPoint(
                x: standardizedLocalFrame.midX,
                y: standardizedLocalFrame.midY
            )
        )
        item.size = standardizedLocalFrame.size
        return item
    }
}

@discardableResult
func rotateItem(
    withID id: CanvasImageItemID,
    to rotationRadians: CGFloat
) -> CanvasImageItem? {
    updateItem(withID: id) { item in
        item.rotationRadians = normalizedCanvasAngle(rotationRadians)
        return item
    }
}
```

## 修改三：在 iOS / macOS viewport 画 rotate overlay，并把 selection outline 改成真实 quad

### 修改前

- iOS / macOS viewport 都只有 selection / crop overlay 图层，没有 rotate overlay 图层。
- selection outline 还是基于 `selectionOverlay.screenFrame` 的 AABB 画矩形；一旦 item 旋转，选中框会和实际 quad 脱离。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers / refreshSelectionOverlay
// 功能说明: 修改前 iOS viewport 只管理 selection / crop layers，选中框按 screenFrame 画轴对齐矩形。
overlayLayer.addSublayer(boardHighlightLayer)
overlayLayer.addSublayer(selectionOutlineLayer)
overlayLayer.addSublayer(cropMaskLayer)
overlayLayer.addSublayer(cropOutlineLayer)

let selectionFrame = selectionOverlay.screenFrame.standardized
selectionOutlineLayer.frame = selectionFrame
selectionOutlineLayer.path = CGPath(
    rect: CGRect(origin: .zero, size: selectionFrame.size),
    transform: nil
)

// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers / refreshSelectionOverlay
// 功能说明: 修改前 macOS viewport 与 iOS 同样只有 selection / crop layers，选中框也是按 screenFrame 画 AABB。
overlayLayer.addSublayer(boardHighlightLayer)
overlayLayer.addSublayer(selectionOutlineLayer)
overlayLayer.addSublayer(cropMaskLayer)
overlayLayer.addSublayer(cropOutlineLayer)

let selectionFrame = selectionOverlay.screenFrame.standardized
selectionOutlineLayer.frame = selectionFrame
selectionOutlineLayer.path = CGPath(
    rect: CGRect(origin: .zero, size: selectionFrame.size),
    transform: nil
)
```

### 修改后

- iOS / macOS viewport 都新增：
  - `rotateOutlineLayer`
  - `rotateGuideLayer`
  - `rotateHandleLayer`
- `apply(_:)` / `didMoveToWindow()` / `viewDidMoveToWindow()` 都会刷新 `refreshRotateOverlay()`。
- selection outline 改为直接画 `selectionOverlay.screenQuad`，不再依赖 AABB。
- rotate overlay 由平台层各自决定 stroke、fill、handle 尺寸和 hit slop。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: setupLayers / refreshSelectionOverlay / refreshRotateOverlay
// 功能说明: 修改后 iOS viewport 新增 rotate overlay 图层，并将 selection outline 改为真实 quad 路径。
private let rotateOutlineLayer = CAShapeLayer()
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

overlayLayer.addSublayer(boardHighlightLayer)
overlayLayer.addSublayer(selectionOutlineLayer)
overlayLayer.addSublayer(cropMaskLayer)
overlayLayer.addSublayer(cropOutlineLayer)
overlayLayer.addSublayer(rotateGuideLayer)
overlayLayer.addSublayer(rotateOutlineLayer)
overlayLayer.addSublayer(rotateHandleLayer)

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    selectionOutlineLayer.path = Self.quadPath(for: selectionOverlay.screenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale
    // ... 省略 selection handles 未改动代码 ...
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
    rotateGuideLayer.contentsScale = currentContentsScale

    rotateOutlineLayer.path = Self.quadPath(for: rotateOverlay.screenQuad)
    rotateOutlineLayer.isHidden = false
    rotateOutlineLayer.contentsScale = currentContentsScale

    let handleRect = Self.rotateHandleRect(centeredAt: rotateOverlay.handle.screenCenter)
    rotateHandleLayer.frame = handleRect
    rotateHandleLayer.path = CGPath(
        ellipseIn: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    rotateHandleLayer.isHidden = false
    rotateHandleLayer.contentsScale = currentContentsScale
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: setupLayers / refreshSelectionOverlay / refreshRotateOverlay
// 功能说明: 修改后 macOS viewport 与 iOS 对齐，按 shared rotate overlay 语义画 outline / guide / handle，并让 selection outline 直接跟随 quad。
private let rotateOutlineLayer = CAShapeLayer()
private let rotateGuideLayer = CAShapeLayer()
private let rotateHandleLayer = CAShapeLayer()

overlayLayer.addSublayer(boardHighlightLayer)
overlayLayer.addSublayer(selectionOutlineLayer)
overlayLayer.addSublayer(cropMaskLayer)
overlayLayer.addSublayer(cropOutlineLayer)
overlayLayer.addSublayer(rotateGuideLayer)
overlayLayer.addSublayer(rotateOutlineLayer)
overlayLayer.addSublayer(rotateHandleLayer)

private func refreshSelectionOverlay() {
    guard let selectionOverlay = snapshot.selectionOverlay else {
        hideSelectionOverlay()
        return
    }

    selectionOutlineLayer.path = Self.quadPath(for: selectionOverlay.screenQuad)
    selectionOutlineLayer.isHidden = false
    selectionOutlineLayer.contentsScale = currentContentsScale
    // ... 省略 selection handles 未改动代码 ...
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
    rotateGuideLayer.contentsScale = currentContentsScale

    rotateOutlineLayer.path = Self.quadPath(for: rotateOverlay.screenQuad)
    rotateOutlineLayer.isHidden = false
    rotateOutlineLayer.contentsScale = currentContentsScale

    let handleRect = Self.rotateHandleRect(centeredAt: rotateOverlay.handle.screenCenter)
    rotateHandleLayer.frame = handleRect
    rotateHandleLayer.path = CGPath(
        ellipseIn: CGRect(origin: .zero, size: handleRect.size),
        transform: nil
    )
    rotateHandleLayer.isHidden = false
    rotateHandleLayer.contentsScale = currentContentsScale
}
```

## 修改四：在 iOS / macOS controller 接入 inline rotate，并把命中 / resize 切到 world point + local axes

### 修改前

- iOS / macOS controller 都只有 crop mode，没有 rotate mode 的 button、press target、drag state 和 commit 流程。
- item body 命中仍依赖 `screenFrame.contains(...)`，旋转后很容易命中失真。
- resize 仍然以 `initialWorldFrame` 和 `fixedOppositeWorldCorner` 做比例缩放，一旦 item 旋转，几何就会偏离 item local axes。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: PointerPressTarget / hitTestItemID / makePointerResizeState / makeResizedWorldFrame
// 功能说明: 修改前 iOS controller 只有 crop 子模式；item 命中依赖 screenFrame.contains(...)；resize 也仍按 worldFrame 四角做比例缩放。
private enum PointerPressTarget {
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    lastRenderSnapshot.items
        .reversed()
        .first(where: { $0.screenFrame.contains(viewportLocation) })?
        .id
}

private func makePointerResizeState(
    itemID: CanvasImageItemID,
    handleRole: CanvasSelectionHandleRole
) -> PointerResizeState? {
    guard let item = scene.item(withID: itemID) else {
        return nil
    }

    let initialWorldFrame = item.worldFrame.standardized
    guard initialWorldFrame.width > 0, initialWorldFrame.height > 0 else {
        return nil
    }

    let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
    let minimumScale = max(
        minimumWorldDimension / initialWorldFrame.width,
        minimumWorldDimension / initialWorldFrame.height
    )

    return PointerResizeState(
        itemID: itemID,
        handleRole: handleRole,
        initialWorldFrame: initialWorldFrame,
        fixedOppositeWorldCorner: fixedOppositeWorldCorner(for: handleRole, in: initialWorldFrame),
        minimumScale: minimumScale
    )
}

private func makeResizedWorldFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialWorldFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialWorldFrame.height * resizeState.minimumScale
    let draggedWorldCorner = constrainedDraggedWorldCorner(
        camera.viewportToWorld(draggedViewportLocation),
        for: resizeState.handleRole,
        oppositeCorner: resizeState.fixedOppositeWorldCorner,
        minimumWidth: minimumWidth,
        minimumHeight: minimumHeight
    )
    // ... 省略未改动代码 ...
}
```

### 修改后

- iOS / macOS controller 都新增：
  - `rotateButton`
  - `PointerPressTarget.rotateHandle`
  - `PointerRotateState`
  - `PointerDragState.rotatingSelectedItem`
  - `handleRotateButtonTap` / `handleRotateButtonClick`
  - `beginRotateModeIfPossible()`
  - `updateRotationDraft(...)`
  - `commitRotationDraftIfNeeded()`
- body hit test 改为 `scene.topmostItemID(containing: camera.viewportToWorld(...))`，不再依赖 `screenFrame.contains(...)`。
- rotate handle 命中与优先级被纳入 `pointerPressTarget(...)`。
- resize 改为先把 pointer world point 转回 item reference local space，再在 local frame 上算比例缩放；最后通过 `referenceWorldPoint(...)` 把新的 local frame 中心映回世界坐标并写入 scene。
- history / autosave 也对 rotate 对齐：一次旋转手势只生成一条历史记录。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupRotateButton / handleRotateButtonTap / hitTestItemID / hitTestRotateHandle / pointerPressTarget / makePointerRotateState / updateRotationDraft / commitRotationDraftIfNeeded
// 功能说明: 修改后 iOS controller 接入 inline rotate 入口、rotate handle 命中和 draft 旋转提交流程，并把 body 命中切到 shared scene 的世界点命中测试。
private enum PointerPressTarget {
    case rotateHandle(itemID: CanvasImageItemID)
    case cropHandle(role: CanvasCropHandleRole, itemID: CanvasImageItemID)
    case handle(role: CanvasSelectionHandleRole, itemID: CanvasImageItemID)
    case selectedBody(itemID: CanvasImageItemID)
    case unselectedItem(itemID: CanvasImageItemID)
    case blank
}

private struct PointerRotateState {
    let itemID: CanvasImageItemID
    let referenceCenter: CGPoint
    let rotationOffsetToPointerAngle: CGFloat
}

private enum PointerDragState {
    case idle
    case pressed(pressedLocation: CGPoint, pressTarget: PointerPressTarget)
    case croppingSelectedItem(PointerCropState)
    case rotatingSelectedItem(PointerRotateState)
    case draggingSelectedItem(itemID: CanvasImageItemID)
    case resizingSelectedItem(PointerResizeState)
    case draggingCanvas
}

private let rotateButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private func setupRotateButton() {
    rotateButton.addTarget(self, action: #selector(handleRotateButtonTap), for: .touchUpInside)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleRotateButtonTap() {
    if isInlineRotateModeActive {
        endInlineEditMode(reason: "exit rotate mode")
    } else {
        beginRotateModeIfPossible()
    }
}

private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    scene.topmostItemID(
        containing: camera.viewportToWorld(viewportLocation)
    )
}

private func hitTestRotateHandle(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    guard let rotateOverlay = lastRenderSnapshot.rotateOverlay else {
        return nil
    }

    guard Self.rotateHandleHitRect(
        centeredAt: rotateOverlay.handle.screenCenter
    ).contains(viewportLocation) else {
        return nil
    }

    return rotateOverlay.itemID
}

private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if isInlineCropModeActive {
        if let cropHandleHit = hitTestCropHandle(at: viewportLocation) {
            return .cropHandle(role: cropHandleHit.role, itemID: cropHandleHit.itemID)
        }

        return .blank
    }

    if isInlineRotateModeActive {
        if let rotateHandleItemID = hitTestRotateHandle(at: viewportLocation) {
            return .rotateHandle(itemID: rotateHandleItemID)
        }

        return .blank
    }

    if let handleHit = hitTestSelectionHandle(at: viewportLocation) {
        return .handle(role: handleHit.role, itemID: handleHit.itemID)
    }

    guard let itemID = hitTestItemID(at: viewportLocation) else {
        return .blank
    }

    return itemID == interactionState.selectedItemID
        ? .selectedBody(itemID: itemID)
        : .unselectedItem(itemID: itemID)
}

private func makePointerRotateState(
    itemID: CanvasImageItemID,
    initialViewportLocation: CGPoint
) -> PointerRotateState? {
    guard
        let item = scene.item(withID: itemID),
        let inlineEditState,
        inlineEditState.mode == .rotate,
        inlineEditState.itemID == itemID
    else {
        return nil
    }

    let initialPointerAngle = angle(
        from: item.center,
        to: camera.viewportToWorld(initialViewportLocation)
    )

    return PointerRotateState(
        itemID: itemID,
        referenceCenter: item.center,
        rotationOffsetToPointerAngle: normalizedCanvasAngle(
            inlineEditState.draftRotationRadians - initialPointerAngle
        )
    )
}

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    guard
        var inlineEditState,
        inlineEditState.mode == .rotate,
        inlineEditState.itemID == rotateState.itemID
    else {
        return
    }

    let pointerAngle = angle(
        from: rotateState.referenceCenter,
        to: camera.viewportToWorld(viewportLocation)
    )
    let draftRotationRadians = normalizedCanvasAngle(
        pointerAngle + rotateState.rotationOffsetToPointerAngle
    )
    guard !anglesMatch(
        inlineEditState.draftRotationRadians,
        draftRotationRadians
    ) else {
        return
    }

    inlineEditState.draftRotationRadians = draftRotationRadians
    self.inlineEditState = inlineEditState
    requestCanvasRefresh(reason: "update rotate draft")
}

private func commitRotationDraftIfNeeded() {
    guard
        let inlineEditState,
        inlineEditState.mode == .rotate,
        let item = scene.item(withID: inlineEditState.itemID)
    else {
        historyController.cancelPendingTransaction()
        return
    }

    guard !anglesMatch(item.rotationRadians, inlineEditState.draftRotationRadians) else {
        historyController.cancelPendingTransaction()
        return
    }

    guard let rotatedItem = scene.rotateItem(
        withID: inlineEditState.itemID,
        to: inlineEditState.draftRotationRadians
    ) else {
        historyController.cancelPendingTransaction()
        return
    }

    expandBoardIfNeeded(toInclude: rotatedItem.worldBounds)
    self.inlineEditState = CanvasInlineEditState(item: rotatedItem, mode: .rotate)
    requestCanvasRefresh(reason: "commit rotate item")
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makePointerResizeState / resizeSelectedItem / makeResizedLocalFrame / referenceLocalPoint / referenceWorldPoint
// 功能说明: 修改后 iOS controller 的 resize 全部切到 item local axes；pointer 在 local 空间里做比例缩放，最终再映回世界坐标提交到 scene。
private struct PointerResizeState {
    let itemID: CanvasImageItemID
    let handleRole: CanvasSelectionHandleRole
    let referenceCenter: CGPoint
    let referenceRotationRadians: CGFloat
    let initialLocalFrame: CGRect
    let fixedOppositeLocalCorner: CGPoint
    let minimumScale: CGFloat
}

private func makePointerResizeState(
    itemID: CanvasImageItemID,
    handleRole: CanvasSelectionHandleRole
) -> PointerResizeState? {
    guard let item = scene.item(withID: itemID) else {
        return nil
    }

    let initialLocalFrame = item.localFrame.standardized
    guard initialLocalFrame.width > 0, initialLocalFrame.height > 0 else {
        return nil
    }

    let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
    let minimumScale = max(
        minimumWorldDimension / initialLocalFrame.width,
        minimumWorldDimension / initialLocalFrame.height
    )

    return PointerResizeState(
        itemID: itemID,
        handleRole: handleRole,
        referenceCenter: item.center,
        referenceRotationRadians: item.rotationRadians,
        initialLocalFrame: initialLocalFrame,
        fixedOppositeLocalCorner: fixedOppositeResizeLocalCorner(
            for: handleRole,
            in: initialLocalFrame
        ),
        minimumScale: minimumScale
    )
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    guard
        let resizedLocalFrame = makeResizedLocalFrame(
            using: resizeState,
            draggedViewportLocation: viewportLocation
        ),
        let currentItem = scene.item(withID: resizeState.itemID)
    else {
        return
    }

    let resizedCenter = referenceWorldPoint(
        fromLocal: CGPoint(
            x: resizedLocalFrame.midX,
            y: resizedLocalFrame.midY
        ),
        center: resizeState.referenceCenter,
        rotationRadians: resizeState.referenceRotationRadians
    )
    guard
        currentItem.center != resizedCenter ||
        currentItem.size != resizedLocalFrame.size
    else {
        return
    }

    guard let resizedItem = scene.resizeItem(
        withID: resizeState.itemID,
        toCenter: resizedCenter,
        size: resizedLocalFrame.size
    ) else {
        return
    }

    expandBoardIfNeeded(toInclude: resizedItem.worldBounds)
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedItem.worldBounds))")
}

private func makeResizedLocalFrame(
    using resizeState: PointerResizeState,
    draggedViewportLocation: CGPoint
) -> CGRect? {
    let minimumWidth = resizeState.initialLocalFrame.width * resizeState.minimumScale
    let minimumHeight = resizeState.initialLocalFrame.height * resizeState.minimumScale
    let draggedLocalCorner = constrainedDraggedResizeLocalCorner(
        referenceLocalPoint(
            fromWorld: camera.viewportToWorld(draggedViewportLocation),
            center: resizeState.referenceCenter,
            rotationRadians: resizeState.referenceRotationRadians
        ),
        for: resizeState.handleRole,
        oppositeCorner: resizeState.fixedOppositeLocalCorner,
        minimumWidth: minimumWidth,
        minimumHeight: minimumHeight
    )
    // ... 省略比例计算与 localFrame(...) 未改动代码 ...
}

private func referenceLocalPoint(
    fromWorld worldPoint: CGPoint,
    center: CGPoint,
    rotationRadians: CGFloat
) -> CGPoint {
    let translatedPoint = CGPoint(
        x: worldPoint.x - center.x,
        y: worldPoint.y - center.y
    )
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    return CGPoint(
        x: (translatedPoint.x * cosine) + (translatedPoint.y * sine),
        y: (-translatedPoint.x * sine) + (translatedPoint.y * cosine)
    )
}

private func referenceWorldPoint(
    fromLocal localPoint: CGPoint,
    center: CGPoint,
    rotationRadians: CGFloat
) -> CGPoint {
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    return CGPoint(
        x: center.x + (localPoint.x * cosine) - (localPoint.y * sine),
        y: center.y + (localPoint.x * sine) + (localPoint.y * cosine)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupRotateButton / handleRotateButtonClick / hitTestItemID / updateRotationDraft / commitRotationDraftIfNeeded / updateRotateButtonAppearance
// 功能说明: 修改后 macOS controller 与 iOS 共用同一套 rotate / rotated-resize 思路，只在按钮类型与刷新入口上保留平台差异。
private let rotateButton: NSButton = {
    let button = NSButton(title: "Rotate", target: nil, action: nil)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.bezelStyle = .rounded
    button.imagePosition = .imageLeading
    return button
}()

private func setupRotateButton() {
    rotateButton.target = self
    rotateButton.action = #selector(handleRotateButtonClick)
    updateInlineEditButtonsAppearance()
}

@objc
private func handleRotateButtonClick() {
    if isInlineRotateModeActive {
        endInlineEditMode(reason: "exit rotate mode")
    } else {
        beginRotateModeIfPossible()
    }
}

private func hitTestItemID(at viewportLocation: CGPoint) -> CanvasImageItemID? {
    scene.topmostItemID(
        containing: camera.viewportToWorld(viewportLocation)
    )
}

private func updateRotationDraft(
    using rotateState: PointerRotateState,
    to viewportLocation: CGPoint
) {
    // ... 省略与 iOS 对齐的角度计算逻辑 ...
    self.inlineEditState = inlineEditState
    refreshCanvas()
}

private func commitRotationDraftIfNeeded() {
    // ... 省略与 iOS 对齐的 scene.rotateItem(...) / history 提交逻辑 ...
    self.inlineEditState = CanvasInlineEditState(item: rotatedItem, mode: .rotate)
    refreshCanvas()
    commitPendingPointerHistoryTransaction(autosaveReason: "rotate item")
}

private func updateRotateButtonAppearance() {
    let isActive = isInlineRotateModeActive
    let isEnabled = isActive || (interactionState.selectedItemID != nil && !isInlineCropModeActive)
    applyRotateButtonAppearance(
        title: isActive ? "Done" : "Rotate",
        systemImageName: isActive ? "checkmark" : "rotate.right",
        tintColor: isActive ? .systemPurple : .systemTeal,
        isEnabled: isEnabled
    )
}
```

## 验证结果

- `ReadLints`：阶段五涉及文件无 lint 报错。
- `macOS Debug build`：成功。
- `iOS Simulator Debug build`：
  - 默认 `xcodebuild ... build` 首次失败在最终 `CodeSign`，报错为 `resource fork, Finder information, or similar detritus not allowed`。
  - 改为 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 后，同一套阶段五源码构建成功。
- 手动交互回归：本次未执行。
