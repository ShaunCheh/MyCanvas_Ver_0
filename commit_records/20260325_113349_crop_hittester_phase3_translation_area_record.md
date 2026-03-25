# 20260325_113349_crop_hittester_phase3_translation_area_record

## 记录范围

- 记录内容：
  - 将共享命中层里的 `cropTranslationArea` 从“仅边线容错命中”扩展为“裁剪框内部 + 边线容错区”的并集。
  - 给共享命中 target 补齐 `debugName`，并把 `editOverlayHitTargetKind` 透传进 `CanvasContextMenuContext.debugSummary`。
  - 调整 `CanvasContextResolver` 的日志 branch 和上下文映射，让日志可以区分内部真实命中语义，同时继续对外兼容 `.cropOutline`。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- 本记录不包含：
  - `Phase 4` 的 iOS / macOS 控制器状态机改造
  - `Phase 5` 的 pointer / menu 彻底解耦
  - 其它非 Crop 命中语义修改

## 修改一：把 `cropTranslationArea` 从“边线命中”扩展成“内部 + 边线容错区”

### 修改前

- `resolveCropHitTarget(...)` 在 handle 命中失败后，只会遍历 `payload.cropScreenQuad.edges`。
- 只要点不在边线容错宽度内，就不会产出 `cropTranslationArea`。
- 因此裁剪框内部点击仍然会继续落空，后续才会退回 resolver 的 blank / scene 路径。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveCropHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改前 cropTranslationArea 只由裁剪框边线附近的距离命中触发，不覆盖裁剪框内部区域。
private func resolveCropHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    guard case let .crop(payload) = editOverlay.payload else {
        return nil
    }

    for handle in editOverlay.handles {
        guard let role = handle.role.cropHandleRole else {
            continue
        }
        // ...
    }

    for edge in payload.cropScreenQuad.edges {
        if canvasDistance(
            from: viewportPoint,
            toSegmentStart: edge.start,
            segmentEnd: edge.end
        ) <= (metrics.cropOutlineHitTargetWidth / 2) {
            return CanvasEditOverlayHitTarget(
                kind: .cropTranslationArea,
                itemID: editOverlay.itemID,
                anchorRect: payload.cropScreenQuad.boundingRect.standardized
            )
        }
    }

    return nil
}
```

### 修改后

- 命中逻辑被改成 `isWithinCropTranslationArea(...)`。
- 先判断 `cropScreenQuad.contains(viewportPoint)`，覆盖真实四边形内部区域。
- 如果不在内部，再用原来的边线 `hit slop` 做距离兜底，保留既有边线抓取手感。
- 这样共享层已经把 `cropTranslationArea` 定义成了“内部 + 边线容错区”的并集。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveCropHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改后 cropTranslationArea 不再只依赖边线距离，而是统一走“内部命中 + 边线容错”的组合判定。
private func resolveCropHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    guard case let .crop(payload) = editOverlay.payload else {
        return nil
    }

    for handle in editOverlay.handles {
        guard let role = handle.role.cropHandleRole else {
            continue
        }
        // ...
    }

    if isWithinCropTranslationArea(
        viewportPoint,
        cropScreenQuad: payload.cropScreenQuad,
        hitSlopWidth: metrics.cropOutlineHitTargetWidth
    ) {
        return CanvasEditOverlayHitTarget(
            kind: .cropTranslationArea,
            itemID: editOverlay.itemID,
            anchorRect: payload.cropScreenQuad.boundingRect.standardized
        )
    }

    return nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: isWithinCropTranslationArea(_:cropScreenQuad:hitSlopWidth:)
// 功能说明: 修改后共享 hit tester 会先用真实四边形 contains 判定裁剪框内部，再用边线 hit slop 覆盖框边附近的拖拽容错区。
private func isWithinCropTranslationArea(
    _ viewportPoint: CGPoint,
    cropScreenQuad: CanvasQuad,
    hitSlopWidth: CGFloat
) -> Bool {
    if cropScreenQuad.contains(viewportPoint) {
        return true
    }

    let halfHitSlopWidth = max(hitSlopWidth, 0) / 2
    guard halfHitSlopWidth > 0 else {
        return false
    }

    return cropScreenQuad.edges.contains { edge in
        canvasDistance(
            from: viewportPoint,
            toSegmentStart: edge.start,
            segmentEnd: edge.end
        ) <= halfHitSlopWidth
    }
}
```

## 修改二：给共享命中 target 补齐 `debugName`，并把 `overlayTarget` 带进菜单上下文日志

### 修改前

- `CanvasEditOverlayHitTargetKind` 只有 case，没有自己的调试文本。
- `CanvasContextMenuContext` 也没有保存共享命中层的内部 target kind。
- 因此即使共享层内部已经出现了未来语义，日志里仍然只能看到外部 `targetKind`，无法区分“实际是 `cropTranslationArea`，但对外兼容成 `.cropOutline`”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: CanvasEditOverlayHitTargetKind
// 功能说明: 修改前共享命中 target 只有 case 定义，没有 debugName，日志层无法直接输出内部命中语义。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名: CanvasContextMenuContext.debugSummary
// 功能说明: 修改前菜单上下文日志只输出外部 targetKind，没有保存共享命中层内部 target，因此看不到 overlay 侧真实命中结果。
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    var debugSummary: String {
        [
            "target=\(targetKind.debugName)",
            "invocationViewportPoint=\(contextMenuDescribe(invocationViewportPoint))",
            "invocationWorldPoint=\(contextMenuDescribe(invocationWorldPoint))",
            "anchorRect=\(anchorRect.map(contextMenuDescribe) ?? \"nil\")"
        ].joined(separator: " ")
    }
}
```

### 修改后

- `CanvasEditOverlayHitTargetKind` 新增了 `debugName`。
- `CanvasContextMenuContext` 新增 `editOverlayHitTargetKind` 字段。
- `debugSummary` 里新增 `overlayTarget=...`，之后 resolver / context menu / host view 的日志都能看到共享命中层的真实 target。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: CanvasEditOverlayHitTargetKind.debugName
// 功能说明: 修改后共享命中层拥有稳定的调试文本，便于 resolver 和菜单日志输出内部真实命中语义。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea

    var debugName: String {
        switch self {
        case .rotateHandle:
            return "rotateHandle"
        case let .selectionHandle(role):
            return "selectionHandle(\(String(describing: role)))"
        case let .cropHandle(role):
            return "cropHandle(\(String(describing: role)))"
        case .cropTranslationArea:
            return "cropTranslationArea"
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名: CanvasContextMenuContext.debugSummary
// 功能说明: 修改后菜单上下文会同时记录外部 target 和共享命中层 overlayTarget，让“对外兼容 target”和“内部真实命中语义”可以并排出现在日志里。
struct CanvasContextMenuContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasContextMenuTargetKind
    let editOverlayHitTargetKind: CanvasEditOverlayHitTargetKind?
    let targetItemID: CanvasItemID?
    let anchorRect: CGRect?
    let selectedItemID: CanvasItemID?
    let isInlineEditModeActive: Bool
    let isInlineCropModeActive: Bool

    var debugSummary: String {
        [
            "target=\(targetKind.debugName)",
            "overlayTarget=\(editOverlayHitTargetKind?.debugName ?? \"nil\")",
            "invocationViewportPoint=\(contextMenuDescribe(invocationViewportPoint))",
            "invocationWorldPoint=\(contextMenuDescribe(invocationWorldPoint))",
            "anchorRect=\(anchorRect.map(contextMenuDescribe) ?? \"nil\")"
        ].joined(separator: " ")
    }
}
```

## 修改三：让 resolver 日志能反映共享层真实命中，但继续对外兼容 `.cropOutline`

### 修改前

- `CanvasContextResolver.contextResolverBranch(for:)` 在 `cropTranslationArea` 场景下仍返回 `"cropOutline"`。
- `resolvedTarget(from:)` 只把共享命中结果映射成旧的 `CanvasContextMenuTargetKind`，不会保留内部 hit target 信息。
- 所以日志和上下文里都看不到“共享层已经进入 `cropTranslationArea`”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: contextResolverBranch(for:) / resolvedTarget(from:)
// 功能说明: 修改前 resolver 在 cropTranslationArea 场景下仍把 branch 和 target 都收束成 cropOutline，内部语义不会透传到上下文日志。
private func contextResolverBranch(
    for hitTarget: CanvasEditOverlayHitTarget
) -> String {
    switch hitTarget.kind {
    case .rotateHandle, .selectionHandle, .cropHandle:
        return "editHandle"
    case .cropTranslationArea:
        return "cropOutline"
    }
}

private func resolvedTarget(
    from hitTarget: CanvasEditOverlayHitTarget
) -> ResolvedTarget {
    let targetKind: CanvasContextMenuTargetKind
    switch hitTarget.kind {
    case .rotateHandle:
        targetKind = .rotateHandle
    case let .selectionHandle(role):
        targetKind = .selectionHandle(role: role)
    case let .cropHandle(role):
        targetKind = .cropHandle(role: role)
    case .cropTranslationArea:
        targetKind = .cropOutline
    }

    return ResolvedTarget(
        targetKind: targetKind,
        targetItemID: hitTarget.itemID,
        anchorRect: hitTarget.anchorRect
    )
}
```

### 修改后

- `contextResolverBranch(for:)` 在 `cropTranslationArea` 场景下直接使用 `hitTarget.kind.debugName`，所以 resolver 日志的 `branch=` 能看到真实共享命中语义。
- `ResolvedTarget` 增加了 `editOverlayHitTargetKind`，再由 `makeContext(...)` 填进 `CanvasContextMenuContext`。
- 但是外部 `targetKind` 仍保持 `.cropOutline`，所以 controller / menu / history 现阶段行为仍然兼容。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: contextResolverBranch(for:)
// 功能说明: 修改后 resolver 日志分支会直接输出 cropTranslationArea，方便定位共享命中层已经进入新的内部语义。
private func contextResolverBranch(
    for hitTarget: CanvasEditOverlayHitTarget
) -> String {
    switch hitTarget.kind {
    case .rotateHandle, .selectionHandle, .cropHandle:
        return "editHandle"
    case .cropTranslationArea:
        return hitTarget.kind.debugName
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolvedTarget(from:) / makeContext(viewportPoint:worldPoint:resolvedTarget:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:)
// 功能说明: 修改后 resolver 会把共享命中层的内部 target 透传进上下文，但 outward targetKind 仍继续兼容成 cropOutline，保证后续 controller / menu 逻辑暂时不变。
private func resolvedTarget(
    from hitTarget: CanvasEditOverlayHitTarget
) -> ResolvedTarget {
    let targetKind: CanvasContextMenuTargetKind
    switch hitTarget.kind {
    case .rotateHandle:
        targetKind = .rotateHandle
    case let .selectionHandle(role):
        targetKind = .selectionHandle(role: role)
    case let .cropHandle(role):
        targetKind = .cropHandle(role: role)
    case .cropTranslationArea:
        targetKind = .cropOutline
    }

    return ResolvedTarget(
        targetKind: targetKind,
        editOverlayHitTargetKind: hitTarget.kind,
        targetItemID: hitTarget.itemID,
        anchorRect: hitTarget.anchorRect
    )
}

private func makeContext(
    viewportPoint: CGPoint,
    worldPoint: CGPoint,
    resolvedTarget: ResolvedTarget,
    selectedItemID: CanvasItemID?,
    isInlineEditModeActive: Bool,
    isInlineCropModeActive: Bool
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: viewportPoint,
        invocationWorldPoint: worldPoint,
        targetKind: resolvedTarget.targetKind,
        editOverlayHitTargetKind: resolvedTarget.editOverlayHitTargetKind,
        targetItemID: resolvedTarget.targetItemID,
        anchorRect: resolvedTarget.anchorRect,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive
    )
}
```

## 本次修改结果

- 共享命中层现在已经真正支持“裁剪框内部 + 边线容错区”的 `cropTranslationArea`。
- `Crop` 框内部点击不会再在共享层退化成空白命中。
- 日志层已经能同时看到：
  - 外部 `target=cropOutline`
  - 内部 `overlayTarget=cropTranslationArea`
- 这样在不提前改动 controller 的前提下，已经为后续 `Phase 4` 的平台状态机切换铺平了数据和日志基础。

## 本次验证

- 已检查改动范围，仅涉及：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- 已通过 IDE lint 检查，当前无新增 linter 报错。
- 未执行完整 Xcode build；当前命令行环境下 `xcodebuild` 不能直接使用完整 Xcode 构建链路。
