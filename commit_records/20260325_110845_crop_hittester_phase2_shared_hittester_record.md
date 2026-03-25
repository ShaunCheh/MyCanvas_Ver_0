# 20260325_110845_crop_hittester_phase2_shared_hittester_record

## 记录范围

- 记录内容：
  - 新增共享 `CanvasEditOverlayHitTester`，把 `selection/crop` 的 overlay hit test 从 `CanvasContextResolver` 中抽离出来。
  - 让 `CanvasContextResolver` 退化成“调用 hit tester，再映射回当前 context 语义”的编排层。
  - 在共享命中层内部引入 `cropTranslationArea` 术语，但对外仍保持 `.cropOutline` 行为不变。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- 本记录不包含：
  - `Phase 3` 的裁剪框内部命中扩展
  - iOS / macOS 控制器状态机改造
  - pointer / menu 彻底解耦

## 修改一：把 overlay hit test 从 `CanvasContextResolver` 中抽出来

### 修改前

- `CanvasContextResolver.swift` 同时承担了：
  - `editOverlay` handle 命中
  - crop 边线命中
  - inline edit blank 判断
  - scene item 命中
  - context 构造与日志输出
- `resolveEditHandleTarget(...)` 和 `resolveCropOutlineTarget(...)` 都写在 resolver 内部，导致“共享命中逻辑”和“上下文编排逻辑”耦合在一起。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveContext(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:interactionMetrics:)
// 功能说明: 修改前 resolver 直接串联自己的私有命中函数；它既负责 edit overlay hit test，也负责后续 context 构造和日志输出。
if let resolvedTarget = resolveEditHandleTarget(
    at: viewportPoint,
    renderSnapshot: renderSnapshot,
    interactionMetrics: interactionMetrics
) {
    return finalize(
        branch: "editHandle",
        resolvedTarget: resolvedTarget
    )
}

if let resolvedTarget = resolveCropOutlineTarget(
    at: viewportPoint,
    renderSnapshot: renderSnapshot,
    interactionMetrics: interactionMetrics
) {
    return finalize(
        branch: "cropOutline",
        resolvedTarget: resolvedTarget
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveEditHandleTarget(at:renderSnapshot:interactionMetrics:)
// 功能说明: 修改前 selection / crop handle 命中细节都塞在 resolver 私有函数里，无法被共享命中层直接复用。
private func resolveEditHandleTarget(
    at viewportPoint: CGPoint,
    renderSnapshot: CanvasRenderSnapshot,
    interactionMetrics: CanvasContextResolverMetrics
) -> ResolvedTarget? {
    guard let editOverlay = renderSnapshot.editOverlay else {
        return nil
    }

    switch editOverlay.kind {
    case .crop:
        for handle in editOverlay.handles {
            guard let role = handle.role.cropHandleRole else {
                continue
            }
            // ...
        }
    case .selection:
        guard case let .selection(payload) = editOverlay.payload else {
            return nil
        }
        // ...
    }

    return nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveCropOutlineTarget(at:renderSnapshot:interactionMetrics:)
// 功能说明: 修改前 crop 边线命中也直接写在 resolver 私有函数里，使用 quadEdges + distance 做边线距离判断。
private func resolveCropOutlineTarget(
    at viewportPoint: CGPoint,
    renderSnapshot: CanvasRenderSnapshot,
    interactionMetrics: CanvasContextResolverMetrics
) -> ResolvedTarget? {
    guard
        let editOverlay = renderSnapshot.editOverlay,
        case let .crop(payload) = editOverlay.payload
    else {
        return nil
    }

    for (start, end) in quadEdges(for: payload.cropScreenQuad) {
        if distance(
            from: viewportPoint,
            toSegmentStart: start,
            segmentEnd: end
        ) <= (interactionMetrics.cropOutlineHitTargetWidth / 2) {
            return ResolvedTarget(
                targetKind: .cropOutline,
                targetItemID: editOverlay.itemID,
                anchorRect: payload.cropScreenQuad.boundingRect.standardized
            )
        }
    }

    return nil
}
```

### 修改后

- 新增了独立的 `CanvasEditOverlayHitTester.swift`。
- `selection` / `crop` 的 overlay hit test 被集中收口到共享层。
- `CanvasContextResolver` 不再直接实现这些几何命中细节，而是消费共享 hit tester 结果。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolve(at:renderSnapshot:metrics:)
// 功能说明: 修改后共享命中层成为 editOverlay hit test 的统一入口，按 overlay kind 分发到 crop / selection 的具体命中逻辑。
struct CanvasEditOverlayHitTester {
    func resolve(
        at viewportPoint: CGPoint,
        renderSnapshot: CanvasRenderSnapshot,
        metrics: CanvasContextResolverMetrics
    ) -> CanvasEditOverlayHitTarget? {
        guard let editOverlay = renderSnapshot.editOverlay else {
            return nil
        }

        switch editOverlay.kind {
        case .crop:
            return resolveCropHitTarget(
                at: viewportPoint,
                editOverlay: editOverlay,
                metrics: metrics
            )
        case .selection:
            return resolveSelectionHitTarget(
                at: viewportPoint,
                editOverlay: editOverlay,
                metrics: metrics
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveCropHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改后 crop overlay 的 handle 命中和边线命中都统一收敛到共享 hit tester 中，后续可在这里继续演进 cropTranslationArea 语义。
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

## 修改二：让 `CanvasContextResolver` 退化成编排层，并保持外部行为等价

### 修改前

- `CanvasContextResolver` 自己维护：
  - `rect(...)`
  - `quadEdges(...)`
  - `distance(...)`
  - `resolveEditHandleTarget(...)`
  - `resolveCropOutlineTarget(...)`
- 这让 resolver 既像“命中计算器”，又像“上下文装配器”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: rect(centeredAt:size:) / quadEdges(for:) / distance(from:toSegmentStart:segmentEnd:)
// 功能说明: 修改前 resolver 自带命中几何 helper，selection/crop overlay hit test 对这些私有函数形成直接依赖。
private func rect(
    centeredAt center: CGPoint,
    size: CGFloat
) -> CGRect {
    CGRect(
        x: center.x - size / 2,
        y: center.y - size / 2,
        width: size,
        height: size
    ).standardized
}

private func quadEdges(
    for quad: CanvasQuad
) -> [(start: CGPoint, end: CGPoint)] {
    [
        (quad.topLeading, quad.topTrailing),
        (quad.topTrailing, quad.bottomTrailing),
        (quad.bottomTrailing, quad.bottomLeading),
        (quad.bottomLeading, quad.topLeading)
    ]
}

private func distance(
    from point: CGPoint,
    toSegmentStart start: CGPoint,
    segmentEnd end: CGPoint
) -> CGFloat {
    // ...
}
```

### 修改后

- `CanvasContextResolver` 只保留：
  - `editOverlayHitTester.resolve(...)` 的调用
  - hit target 到当前 `CanvasContextMenuTargetKind` 的映射
  - 其余 context / item / blank 编排逻辑
- 原来 resolver 内部的命中辅助逻辑已经被移走。
- 同时为了保持行为完全等价，内部新的 `cropTranslationArea` 仍被映射回旧的 `.cropOutline`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveContext(at:scene:camera:renderSnapshot:selectedItemID:isInlineEditModeActive:isInlineCropModeActive:interactionMetrics:)
// 功能说明: 修改后 resolver 先询问共享 editOverlayHitTester，再把命中结果映射为当前外部 context 语义，继续复用既有菜单和控制器分支。
struct CanvasContextResolver {
    private let editOverlayHitTester = CanvasEditOverlayHitTester()

    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        // ...
        if let editOverlayHitTarget = editOverlayHitTester.resolve(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            metrics: interactionMetrics
        ) {
            return finalize(
                branch: contextResolverBranch(for: editOverlayHitTarget),
                resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
            )
        }
        // ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: contextResolverBranch(for:) / resolvedTarget(from:)
// 功能说明: 修改后 resolver 负责把共享命中层的未来术语映射回当前对外行为；Phase 2 中 cropTranslationArea 仍对外报告为 cropOutline，以保证 controller / menu 行为不变。
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

## 修改三：在共享命中层内部提前冻结未来输入语义，但不改变当前运行时行为

### 修改前

- 系统里没有 `CanvasEditOverlayHitTargetKind`。
- crop 边线命中直接产出 `.cropOutline`，这会把渲染命名和未来输入语义绑定在一起。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名: resolveCropOutlineTarget(at:renderSnapshot:interactionMetrics:)
// 功能说明: 修改前 crop 边线命中直接产出 CanvasContextMenuTargetKind.cropOutline，输入层和外部菜单语义是同一套命名。
return ResolvedTarget(
    targetKind: .cropOutline,
    targetItemID: editOverlay.itemID,
    anchorRect: payload.cropScreenQuad.boundingRect.standardized
)
```

### 修改后

- 新增 `CanvasEditOverlayHitTargetKind` 和 `CanvasEditOverlayHitTarget`。
- 在共享 hit tester 里，crop 边线命中已经内部统一归到 `cropTranslationArea`。
- 但 `Phase 2` 只冻结内部命名，不把这个新语义向外扩散。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: CanvasEditOverlayHitTargetKind / CanvasEditOverlayHitTarget
// 功能说明: 修改后共享命中层拥有独立 target 类型，为后续 Phase 3-5 的输入语义演进预留稳定契约。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case cropHandle(role: CanvasCropHandleRole)
    case cropTranslationArea
}

struct CanvasEditOverlayHitTarget {
    let kind: CanvasEditOverlayHitTargetKind
    let itemID: CanvasItemID
    let anchorRect: CGRect
}
```

## 本次修改结果

- 共享层已经具备独立的 `CanvasEditOverlayHitTester`，后续 `Phase 3` 可以直接在这里扩展“裁剪框内部可移动区域”。
- `CanvasContextResolver` 已经从“命中计算器 + 上下文装配器”收口成更纯粹的编排层。
- `cropTranslationArea` 这个未来输入术语已经在共享层内部冻结下来，但当前 controller、context menu、history、click logging 看到的仍然是原来的 `.cropOutline`。
- 因此这次修改属于纯重构，目标是代码结构更干净，不改变当前外部行为。

## 本次验证

- 已检查改动范围，仅涉及：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- 已通过 IDE lint 检查，当前无新增 linter 报错。
- 工程使用 `PBXFileSystemSynchronizedRootGroup`，新增的 `CanvasEditOverlayHitTester.swift` 不需要手动登记到 `project.pbxproj`。
- 未执行完整 Xcode build；当前命令行环境下 `xcodebuild` 不能直接使用完整 Xcode 构建链路。
