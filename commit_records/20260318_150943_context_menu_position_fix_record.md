# 20260318_150943_context_menu_position_fix_record

## 记录范围

- 记录内容：
  1. 修正共享菜单锚点语义，让 `selectedItemBody / unselectedItemBody / cropOutline / blank` 跟随实际触点或光标，而不是统一退化为几何中心。
  2. 为 `CanvasContextMenuState` 增加 `layoutAnchorPoint`，把“命中上下文”和“最终展示坐标”拆开。
  3. 重写 `CanvasContextMenuLayoutSolver` 的候选方向排序逻辑，从“按中线翻面”改为“按真实可用空间排序”。
  4. 让 `CanvasContextMenuHostView` 统一消费 host 坐标系里的锚点；macOS 菜单宿主额外改为 flipped 坐标系，消除与 viewport 的 y 语义偏差。
  5. 让 `iOS/macOS` controller 在展示菜单前，把 `anchorPoint / safeBounds / occupiedRects` 都显式转换到 `contextMenuHostView` 坐标系，并补充 `layoutAnchorPoint` 位置日志。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `.cursor/plans/菜单定位修复_691eddda.plan.md`
  - 原始 gif diff
  - git commit

## 修改一：共享锚点语义不再把 body 菜单绑定到 item 中心

### 修改前

- `CanvasContextMenuContext.anchorPoint` 只要存在 `anchorRect`，就统一取中心点。
- 这会让 `selectedItemBody / unselectedItemBody / cropOutline` 的菜单位置跟随对象包围盒中心，而不是跟随用户实际按下的位置。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: CanvasContextMenuContext.anchorPoint
// 功能说明: 修改前只要有 anchorRect 就取几何中心，body/outline 菜单也会偏向对象中心。
var anchorPoint: CGPoint {
    guard let anchorRect else {
        return invocationViewportPoint
    }

    return CGPoint(
        x: anchorRect.midX,
        y: anchorRect.midY
    )
}
```

### 修改后

- `rotateHandle / cropHandle / selectionHandle` 继续使用几何中心，保持小命中目标的稳定性。
- `cropOutline / selectedItemBody / unselectedItemBody / blank` 改为直接使用 `invocationViewportPoint`，让菜单视觉上贴近实际触点/光标。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: CanvasContextMenuContext.anchorPoint
// 功能说明: 修改后按 targetKind 区分菜单锚点语义，body/outline/blank 跟随实际触点，handle 继续跟随几何中心。
var anchorPoint: CGPoint {
    switch targetKind {
    case .rotateHandle, .cropHandle, .selectionHandle:
        guard let anchorRect else {
            return invocationViewportPoint
        }

        return CGPoint(
            x: anchorRect.midX,
            y: anchorRect.midY
        )
    case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
        // Body/outline menus should follow the actual invocation point instead
        // of the item's geometric center so the menu feels attached to the click.
        return invocationViewportPoint
    }
}
```

## 修改二：共享菜单状态与布局求解从“中线翻面”改为“按真实空间排序”

### 修改前

- `CanvasContextMenuState` 只保存 `resolvedContext` 和 `commandStates`。
- `CanvasContextMenuLayoutSolver` 根据锚点是否落在中线左/右、上/下，直接决定优先放左边还是右边、上边还是下边。
- 这会导致即使触点旁边明明有空间，菜单也可能被提前翻到对侧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuState / CanvasContextMenuLayoutSolver.resolveMenuFrame(...) / candidatePlacements(prefersTrailing:prefersBottom:)
// 功能说明: 修改前 state 不区分展示锚点，布局优先级完全由 anchorPoint 是否跨过中线决定。
struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let commandStates: [CanvasContextMenuCommandState]
}

let prefersTrailing = anchorPoint.x < layoutBounds.midX
let prefersBottom = anchorPoint.y < layoutBounds.midY
let placements = candidatePlacements(
    prefersTrailing: prefersTrailing,
    prefersBottom: prefersBottom
)

private func candidatePlacements(
    prefersTrailing: Bool,
    prefersBottom: Bool
) -> [Placement] {
    [
        Placement(
            attachesTrailing: prefersTrailing,
            attachesBottom: prefersBottom
        ),
        Placement(
            attachesTrailing: !prefersTrailing,
            attachesBottom: prefersBottom
        ),
        Placement(
            attachesTrailing: prefersTrailing,
            attachesBottom: !prefersBottom
        ),
        Placement(
            attachesTrailing: !prefersTrailing,
            attachesBottom: !prefersBottom
        )
    ]
}
```

### 修改后

- `CanvasContextMenuState` 新增 `layoutAnchorPoint`，把“共享命中语义”和“最终菜单落位语义”拆开。
- `CanvasContextMenuLayoutSolver` 改成先计算四个方向各自的可用宽高，再按 `totalOverflow -> availableArea -> defaultPreferenceRank` 排序。
- 默认偏好仍然是右下、右上、左下、左上，但只有在空间同样足够时才按默认偏好取值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuState / CanvasContextMenuLayoutSolver.candidatePlacements(...) / candidateScore(...)
// 功能说明: 修改后 state 显式保存 layoutAnchorPoint，布局候选顺序改为按真实剩余空间排序，而不是按中线直接翻面。
struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let layoutAnchorPoint: CGPoint
    let commandStates: [CanvasContextMenuCommandState]

    var isEmpty: Bool {
        commandStates.isEmpty
    }
}

private func candidatePlacements(
    around anchorPoint: CGPoint,
    menuSize: CGSize,
    within layoutBounds: CGRect,
    anchorSpacing: CGFloat
) -> [Placement] {
    let placements = [
        Placement(attachesTrailing: true, attachesBottom: true, defaultPreferenceRank: 0),
        Placement(attachesTrailing: true, attachesBottom: false, defaultPreferenceRank: 1),
        Placement(attachesTrailing: false, attachesBottom: true, defaultPreferenceRank: 2),
        Placement(attachesTrailing: false, attachesBottom: false, defaultPreferenceRank: 3)
    ]

    return placements.sorted { lhs, rhs in
        let lhsScore = candidateScore(
            for: lhs,
            anchorPoint: anchorPoint,
            menuSize: menuSize,
            layoutBounds: layoutBounds,
            anchorSpacing: anchorSpacing
        )
        let rhsScore = candidateScore(
            for: rhs,
            anchorPoint: anchorPoint,
            menuSize: menuSize,
            layoutBounds: layoutBounds,
            anchorSpacing: anchorSpacing
        )

        if lhsScore.totalOverflow != rhsScore.totalOverflow {
            return lhsScore.totalOverflow < rhsScore.totalOverflow
        }

        if lhsScore.totalOverflow == 0, rhsScore.totalOverflow == 0 {
            return lhs.defaultPreferenceRank < rhs.defaultPreferenceRank
        }

        if lhsScore.availableArea != rhsScore.availableArea {
            return lhsScore.availableArea > rhsScore.availableArea
        }

        return lhs.defaultPreferenceRank < rhs.defaultPreferenceRank
    }
}

private func candidateScore(
    for placement: Placement,
    anchorPoint: CGPoint,
    menuSize: CGSize,
    layoutBounds: CGRect,
    anchorSpacing: CGFloat
) -> CandidateScore {
    let horizontalSpace = directionalSpace(
        attachesPositiveDirection: placement.attachesTrailing,
        coordinate: anchorPoint.x,
        minBound: layoutBounds.minX,
        maxBound: layoutBounds.maxX,
        anchorSpacing: anchorSpacing
    )
    let verticalSpace = directionalSpace(
        attachesPositiveDirection: placement.attachesBottom,
        coordinate: anchorPoint.y,
        minBound: layoutBounds.minY,
        maxBound: layoutBounds.maxY,
        anchorSpacing: anchorSpacing
    )

    let horizontalOverflow = max(menuSize.width - horizontalSpace, 0)
    let verticalOverflow = max(menuSize.height - verticalSpace, 0)
    return CandidateScore(
        totalOverflow: horizontalOverflow + verticalOverflow,
        availableArea: horizontalSpace * verticalSpace
    )
}
```

## 修改三：共享菜单宿主改为消费 layoutAnchorPoint，并统一 macOS 的 flipped 坐标语义

### 修改前

- `CanvasContextMenuHostView` 直接读取 `currentState.resolvedContext.anchorPoint`。
- macOS 宿主没有显式 `isFlipped`，会和 `canvasViewportView` 的 top-left 语义形成偏差。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.updateLayout(...)
// 功能说明: 修改前宿主直接消费 resolvedContext.anchorPoint，没有区分命中语义和展示坐标语义。
guard let menuFrame = layoutSolver.resolveMenuFrame(
    anchorPoint: currentState.resolvedContext.anchorPoint,
    preferredSize: preferredSize,
    safeBounds: safeBounds,
    occupiedRects: occupiedRects,
    configuration: layoutConfiguration
) else {
    menuContainerView.frame = .zero
    return
}
```

### 修改后

- `iOS/macOS` 宿主都改为消费 `currentState.layoutAnchorPoint`。
- macOS 宿主显式 `override var isFlipped: Bool { true }`，统一与 viewport 的 y 方向解释。
- 布局日志增加 `layoutAnchorPoint` 字段，方便继续追踪“共享上下文 anchor”和“最终 host anchor”是否一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.updateLayout(...) / CanvasContextMenuHostView.isFlipped / logContextMenuLayout(...)
// 功能说明: 修改后宿主只消费已经转换到 host 坐标系的 layoutAnchorPoint，macOS 宿主也与 viewport 对齐为 flipped 坐标系。
guard let menuFrame = layoutSolver.resolveMenuFrame(
    anchorPoint: currentState.layoutAnchorPoint,
    preferredSize: preferredSize,
    safeBounds: safeBounds,
    occupiedRects: occupiedRects,
    configuration: layoutConfiguration
) else {
    logContextMenuLayout(
        platform: "macOS",
        state: currentState,
        hostBounds: bounds,
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        preferredSize: preferredSize,
        resolvedMenuFrame: nil
    )
    menuContainerView.frame = .zero
    return
}

override var isFlipped: Bool {
    true
}

print(
    "[Canvas \(platform)][ContextMenuLayout] " +
    state.resolvedContext.debugSummary + " " +
    "layoutAnchorPoint=\(contextMenuHostDescribe(state.layoutAnchorPoint)) " +
    "hostBounds=\(contextMenuHostDescribe(hostBounds)) " +
    "safeBounds=\(contextMenuHostDescribe(safeBounds)) "
)
```

## 修改四：iOS controller 在冻结菜单 state 前先统一到 host 坐标系

### 修改前

- `iOSViewController` 冻结菜单 state 时只保存 `resolvedContext`。
- `safeBounds` 直接使用 `chromeSafeBounds()`，`contextMenuOccupiedRects()` 直接返回 overlay 内的 rect。
- 这意味着菜单展示层没有显式拿到 host 坐标系里的 anchor / bounds / blocker。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / updateContextMenuPresentation() / contextMenuOccupiedRects()
// 功能说明: 修改前 iOS controller 直接把 viewport/overlay 语义的数据下发给菜单宿主，没有显式转成 host 坐标。
contextMenuState = CanvasContextMenuState(
    resolvedContext: resolvedContext,
    commandStates: commandStates
)

private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: chromeSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }
    return rects
}
```

### 修改后

- `presentContextMenu(for:)` 会把 `resolvedContext.anchorPoint` 先转成 `layoutAnchorPoint` 再冻结。
- `contextMenuSafeBounds()` 和 `contextMenuOccupiedRects()` 都显式通过 `contextMenuHostView.convert(...)` 转为 host 坐标。
- `layoutAnchorPoint` 也被加入定位日志，方便直接核对“触点 -> host anchor -> menuFrame”整条链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / contextMenuSafeBounds() / contextMenuLayoutAnchorPoint(for:) / convertToContextMenuHost(...)
// 功能说明: 修改后 iOS controller 在展示前统一完成 viewport/overlay 到 host 的坐标转换，让共享宿主只消费一种坐标语义。
contextMenuState = CanvasContextMenuState(
    resolvedContext: resolvedContext,
    layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
    commandStates: commandStates
)

private func contextMenuSafeBounds() -> CGRect {
    convertToContextMenuHost(
        chromeSafeBounds(),
        from: chromeOverlayView
    )
}

private func contextMenuLayoutAnchorPoint(
    for resolvedContext: CanvasContextMenuContext
) -> CGPoint {
    convertToContextMenuHost(
        resolvedContext.anchorPoint,
        from: canvasViewportView
    )
}

private func convertToContextMenuHost(
    _ point: CGPoint,
    from sourceView: UIView
) -> CGPoint {
    contextMenuHostView.convert(
        point,
        from: sourceView
    )
}

private func convertToContextMenuHost(
    _ rect: CGRect,
    from sourceView: UIView
) -> CGRect {
    contextMenuHostView.convert(
        rect,
        from: sourceView
    ).standardized
}
```

## 修改五：macOS controller 对称接入 host 坐标桥接，消除 viewport 与 overlay 的坐标偏差

### 修改前

- `macOSViewController` 和 `iOS` 一样，直接把 `chromeSafeBounds()` 与 raw `occupiedRects` 交给菜单宿主。
- 在 macOS 下，viewport 自身是 flipped，但 overlay / host 在修复前没有对齐这层语义，容易把 y 方向偏差带到菜单布局链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / updateContextMenuPresentation() / contextMenuOccupiedRects()
// 功能说明: 修改前 macOS controller 没有在 controller 层完成 viewport/overlay 到 host 的显式坐标归一。
contextMenuState = CanvasContextMenuState(
    resolvedContext: resolvedContext,
    commandStates: commandStates
)

private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: chromeSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }
    return rects
}
```

### 修改后

- `macOSViewController` 采用和 `iOS` 对称的 host 坐标桥接。
- `layoutAnchorPoint`、`contextMenuSafeBounds()` 和 `contextMenuOccupiedRects()` 都统一转成 `contextMenuHostView` 坐标系后再下发。
- 这样 `CanvasContextMenuHostView` 和 `CanvasContextMenuLayoutSolver` 不再需要猜测“当前拿到的是 viewport 坐标还是 overlay 坐标”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / contextMenuSafeBounds() / contextMenuLayoutAnchorPoint(for:) / convertToContextMenuHost(...)
// 功能说明: 修改后 macOS controller 与 iOS 对称完成坐标桥接，把 flipped viewport 语义显式收敛到 host 坐标系。
contextMenuState = CanvasContextMenuState(
    resolvedContext: resolvedContext,
    layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
    commandStates: commandStates
)

private func contextMenuSafeBounds() -> CGRect {
    convertToContextMenuHost(
        chromeSafeBounds(),
        from: chromeOverlayView
    )
}

private func contextMenuLayoutAnchorPoint(
    for resolvedContext: CanvasContextMenuContext
) -> CGPoint {
    convertToContextMenuHost(
        resolvedContext.anchorPoint,
        from: canvasViewportView
    )
}

private func convertToContextMenuHost(
    _ point: CGPoint,
    from sourceView: NSView
) -> CGPoint {
    contextMenuHostView.convert(
        point,
        from: sourceView
    )
}

private func convertToContextMenuHost(
    _ rect: CGRect,
    from sourceView: NSView
) -> CGRect {
    contextMenuHostView.convert(
        rect,
        from: sourceView
    ).standardized
}
```

## 验证结果

- `ReadLints`：本次修改文件无新增问题。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_ALLOWED=NO`：通过。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=macOS" build CODE_SIGNING_ALLOWED=NO`：通过。

## 结果总结

- 这次修复把菜单定位问题收敛到了共享层，不再依赖 `iOS/macOS` 各自做平台补丁。
- `body / outline / blank` 现在会优先贴近用户实际触点或光标。
- `handle` 菜单仍保持稳定的几何中心锚点，不会因为 hit slop 内的细微触点抖动而跳动。
- 菜单布局优先级改为按真实可用空间排序，减少“明明旁边有空间，却被翻到反方向”的情况。
