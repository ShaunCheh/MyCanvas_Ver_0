# 20260515_180534_selection_translation_area_phase2_record

## 记录范围

- 记录内容：
  - 在共享命中层 `CanvasEditOverlayHitTester` 中，正式实现 `selectionTranslationArea` 的几何命中。
  - 将 `selectionTranslationArea` 拆成两部分：
    - 选区外框 ring 命中
    - 群组选区内部空白命中
  - 为避免重复几何逻辑，抽出通用的 quad translation / outline hit helper，并让既有 `cropTranslationArea` 复用。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 中只有 `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift` 处于修改状态。
  - `phase 1` 的契约层修改已在 `commit_records/20260515_174251_selection_translation_area_phase1_record.md` 中单独记录，本次只记录 `phase 2` 新增的几何命中实现。
- 本记录不包含：
  - `phase 3` 的控制器 move 分发接线
  - 任何额外测试代码改动
  - 其它非 `CanvasEditOverlayHitTester.swift` 的源码调整

## 当前 changes 摘要

- 当前这轮源码修改只影响共享 hit test 层，不涉及 renderer、resolver、controller、scene。
- 这意味着：
  - 现在 `selectionTranslationArea` 已经可以在命中层被产出；
  - 但因为 `phase 3` 尚未实施，平台控制器还不会把这个 target 解释成真正的移动行为。

## 修改一：给 selection 命中链路补入 `renderSnapshot`

### 修改前

- `resolveSelectionHitTarget(...)` 只接收 `editOverlay` 和 `metrics`。
- 因此它只能基于 `activeScreenQuad` 和 handles 做判断，拿不到当前 render items 的 `screenQuad`。
- 这样就无法实现“点在群组选区内部，但不在任何成员正文内”的空白区判定。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolve(at:renderSnapshot:metrics:) / resolveSelectionHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改前 selection hit test 拿不到 renderSnapshot，因此无法读取成员 item 的 screenQuad 做内部空白判断。
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

private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    // ...
}
```

### 修改后

- `resolveSelectionHitTarget(...)` 现在显式接收 `renderSnapshot`。
- 这样 selection hit test 可以直接读取 `renderSnapshot.items`，按 `memberItemIDs` 提取成员 `screenQuad`。
- 后续“群组内部空白命中”不需要改 renderer，也不需要给 payload 再额外加字段。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolve(at:renderSnapshot:metrics:) / resolveSelectionHitTarget(at:editOverlay:renderSnapshot:metrics:)
// 功能说明: 修改后 selection hit test 可以访问 renderSnapshot.items，从共享层直接构造成员 screenQuad 集合。
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
            renderSnapshot: renderSnapshot,
            metrics: metrics
        )
    }
}

private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    renderSnapshot: CanvasRenderSnapshot,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    // ...
}
```

## 修改二：在 selection 命中优先级里正式接入 `selectionTranslationArea`

### 修改前

- `resolveSelectionHitTarget(...)` 的顺序只有：
  - rotate handle
  - selection handles
  - 直接返回 `nil`
- 因此命中层不可能产出 `selectionTranslationArea`。
- 选区内部空白、选区边框 ring 都会继续回落到 body / blank 的后续链路。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改前 selection hit test 在 handles 之后直接结束，没有 selectionTranslationArea 的几何命中阶段。
private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    guard case let .selection(payload) = editOverlay.payload else {
        return nil
    }

    let rotateHitRect = rect(
        centeredAt: payload.rotateAffordance.handle.screenCenter,
        size: metrics.rotateHandleHitTargetSize
    )
    if rotateHitRect.contains(viewportPoint) {
        return CanvasEditOverlayHitTarget(
            kind: payload.subject.isGroupSelection ? .groupRotateHandle : .rotateHandle,
            itemID: editOverlay.itemID,
            anchorRect: rotateHitRect
        )
    }

    for handle in editOverlay.handles {
        guard let role = handle.role.selectionHandleRole else {
            continue
        }
        let hitRect = rect(
            centeredAt: handle.screenCenter,
            size: metrics.selectionHandleHitTargetSize
        )
        if hitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: payload.subject.isGroupSelection
                    ? .groupSelectionHandle(role: role)
                    : .selectionHandle(role: role),
                itemID: editOverlay.itemID,
                anchorRect: hitRect
            )
        }
    }

    return nil
}
```

### 修改后

- 在 handles 之后新增一段 `selectionTranslationArea` 判定。
- 返回顺序变成：
  - rotate handle
  - selection handles
  - selection translation area
  - `nil`
- 这保证了 `selectionTranslationArea` 的优先级低于缩放/旋转，但高于后续正文或 blank 回退。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:renderSnapshot:metrics:)
// 功能说明: 修改后 selection 命中链路在 handles 之后、正文回退之前，新增了 selectionTranslationArea 的几何判定阶段。
private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    renderSnapshot: CanvasRenderSnapshot,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    guard case let .selection(payload) = editOverlay.payload else {
        return nil
    }

    let rotateHitRect = rect(
        centeredAt: payload.rotateAffordance.handle.screenCenter,
        size: metrics.rotateHandleHitTargetSize
    )
    if rotateHitRect.contains(viewportPoint) {
        return CanvasEditOverlayHitTarget(
            kind: payload.subject.isGroupSelection ? .groupRotateHandle : .rotateHandle,
            itemID: editOverlay.itemID,
            anchorRect: rotateHitRect
        )
    }

    for handle in editOverlay.handles {
        guard let role = handle.role.selectionHandleRole else {
            continue
        }
        let hitRect = rect(
            centeredAt: handle.screenCenter,
            size: metrics.selectionHandleHitTargetSize
        )
        if hitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: payload.subject.isGroupSelection
                    ? .groupSelectionHandle(role: role)
                    : .selectionHandle(role: role),
                itemID: editOverlay.itemID,
                anchorRect: hitRect
            )
        }
    }

    let selectedMemberScreenQuads = selectionMemberScreenQuads(
        for: payload.subject.memberItemIDs,
        renderSnapshot: renderSnapshot
    )
    if isWithinSelectionTranslationArea(
        viewportPoint,
        selectionScreenQuad: editOverlay.activeScreenQuad,
        selectedMemberScreenQuads: selectedMemberScreenQuads,
        expectedMemberCount: payload.subject.memberItemIDs.count,
        outlineHitSlopWidth: metrics.selectionOutlineHitTargetWidth
    ) {
        return CanvasEditOverlayHitTarget(
            kind: .selectionTranslationArea,
            itemID: editOverlay.itemID,
            anchorRect: editOverlay.activeScreenQuad.boundingRect.standardized
        )
    }

    return nil
}
```

## 修改三：把 `selectionTranslationArea` 明确拆成“外框 ring + 内部空白”

### 修改前

- 代码里还没有任何 selection translation 专用 helper。
- selection overlay 的命中语义只覆盖 rotate / resize handles。
- 群组内部空白区没有独立定义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:metrics:)
// 功能说明: 修改前 selection 命中阶段没有 selectionMemberScreenQuads、内部空白判定或选区 outline 命中 helper。
private func resolveSelectionHitTarget(
    at viewportPoint: CGPoint,
    editOverlay: CanvasEditRenderOverlay,
    metrics: CanvasContextResolverMetrics
) -> CanvasEditOverlayHitTarget? {
    // rotate handle
    // selection handles
    return nil
}
```

### 修改后

- 新增 `selectionMemberScreenQuads(...)`，直接从 `renderSnapshot.items` 建出成员 quad 列表。
- 新增 `isWithinSelectionTranslationArea(...)`，总控 selection translation 的两段判定：
  - `isWithinQuadOutlineHitArea(...)`
  - `isWithinSelectionInteriorBlankArea(...)`
- 新增 `isWithinSelectionInteriorBlankArea(...)`，只在以下条件全部满足时返回 `true`：
  - 点在群组选区 `selectionScreenQuad` 内
  - 成员 quad 数量完整
  - 点不在任何成员 `screenQuad` 内
- 这保证了“单选正文仍然落回 body”，“多选成员之间的空白才算 translation area”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: selectionMemberScreenQuads(for:renderSnapshot:) / isWithinSelectionTranslationArea(_:selectionScreenQuad:selectedMemberScreenQuads:expectedMemberCount:outlineHitSlopWidth:) / isWithinSelectionInteriorBlankArea(_:selectionScreenQuad:selectedMemberScreenQuads:expectedMemberCount:)
// 功能说明: 修改后 selectionTranslationArea 被明确拆成成员 quad 收集、外框 ring 命中、群组内部空白命中三层逻辑。
private func selectionMemberScreenQuads(
    for memberItemIDs: [CanvasItemID],
    renderSnapshot: CanvasRenderSnapshot
) -> [CanvasQuad] {
    let screenQuadByItemID = Dictionary(
        uniqueKeysWithValues: renderSnapshot.items.map { item in
            (item.id, item.screenQuad)
        }
    )
    return memberItemIDs.compactMap { memberItemID in
        screenQuadByItemID[memberItemID]
    }
}

private func isWithinSelectionTranslationArea(
    _ viewportPoint: CGPoint,
    selectionScreenQuad: CanvasQuad,
    selectedMemberScreenQuads: [CanvasQuad],
    expectedMemberCount: Int,
    outlineHitSlopWidth: CGFloat
) -> Bool {
    if isWithinQuadOutlineHitArea(
        viewportPoint,
        screenQuad: selectionScreenQuad,
        hitSlopWidth: outlineHitSlopWidth
    ) {
        return true
    }

    return isWithinSelectionInteriorBlankArea(
        viewportPoint,
        selectionScreenQuad: selectionScreenQuad,
        selectedMemberScreenQuads: selectedMemberScreenQuads,
        expectedMemberCount: expectedMemberCount
    )
}

private func isWithinSelectionInteriorBlankArea(
    _ viewportPoint: CGPoint,
    selectionScreenQuad: CanvasQuad,
    selectedMemberScreenQuads: [CanvasQuad],
    expectedMemberCount: Int
) -> Bool {
    guard
        selectionScreenQuad.contains(viewportPoint),
        expectedMemberCount > 0,
        selectedMemberScreenQuads.count == expectedMemberCount
    else {
        return false
    }

    return selectedMemberScreenQuads.contains(where: { screenQuad in
        screenQuad.contains(viewportPoint)
    }) == false
}
```

## 修改四：抽出通用 quad 命中 helper，并让 crop 侧复用

### 修改前

- `isWithinCropTranslationArea(...)` 自己同时负责：
  - quad 内部命中
  - edge distance 命中
- 这套逻辑是 crop 专用的，selection 侧如果直接复制，会变成重复代码。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: isWithinCropTranslationArea(_:cropScreenQuad:hitSlopWidth:)
// 功能说明: 修改前 cropTranslationArea 的内部命中和边线容错逻辑都写在一个函数里，selection 无法直接复用。
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

### 修改后

- 新增 `isWithinQuadTranslationArea(...)` 统一处理“内部 + 外框容错”。
- 新增 `isWithinQuadOutlineHitArea(...)` 专门处理 outline ring。
- `cropTranslationArea` 现在只做轻量转发。
- selection 侧复用了同一套 quad geometry 基础能力，但没有影响 crop 的既有语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: isWithinCropTranslationArea(_:cropScreenQuad:hitSlopWidth:) / isWithinQuadTranslationArea(_:screenQuad:hitSlopWidth:) / isWithinQuadOutlineHitArea(_:screenQuad:hitSlopWidth:)
// 功能说明: 修改后 crop 与 selection 共用 quad 级命中 helper；crop 继续保留“内部 + 外框容错”的原始语义，selection 则单独复用 outline ring 判定。
private func isWithinCropTranslationArea(
    _ viewportPoint: CGPoint,
    cropScreenQuad: CanvasQuad,
    hitSlopWidth: CGFloat
) -> Bool {
    isWithinQuadTranslationArea(
        viewportPoint,
        screenQuad: cropScreenQuad,
        hitSlopWidth: hitSlopWidth
    )
}

private func isWithinQuadTranslationArea(
    _ viewportPoint: CGPoint,
    screenQuad: CanvasQuad,
    hitSlopWidth: CGFloat
) -> Bool {
    if screenQuad.contains(viewportPoint) {
        return true
    }

    return isWithinQuadOutlineHitArea(
        viewportPoint,
        screenQuad: screenQuad,
        hitSlopWidth: hitSlopWidth
    )
}

private func isWithinQuadOutlineHitArea(
    _ viewportPoint: CGPoint,
    screenQuad: CanvasQuad,
    hitSlopWidth: CGFloat
) -> Bool {
    let halfHitSlopWidth = max(hitSlopWidth, 0) / 2
    guard halfHitSlopWidth > 0 else {
        return false
    }

    return screenQuad.edges.contains { edge in
        canvasDistance(
            from: viewportPoint,
            toSegmentStart: edge.start,
            segmentEnd: edge.end
        ) <= halfHitSlopWidth
    }
}
```

## 结果边界

- 到本次 `phase 2` 结束时，命中层已经能在以下区域产出 `selectionTranslationArea`：
  - 选区外框 ring
  - 群组选区内部、但不在成员正文内的空白区域
- 当前仍然没有进入 `phase 3`，所以控制器不会把它解释成 move。
- 因此当前行为边界是：
  - 命中语义已建成
  - 真实移动尚未接通

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:renderSnapshot:metrics:)
// 功能说明: 这段逻辑现在已经能产出 selectionTranslationArea，但后续控制器是否把它解释成 move，要等 phase 3 接线。
if isWithinSelectionTranslationArea(
    viewportPoint,
    selectionScreenQuad: editOverlay.activeScreenQuad,
    selectedMemberScreenQuads: selectedMemberScreenQuads,
    expectedMemberCount: payload.subject.memberItemIDs.count,
    outlineHitSlopWidth: metrics.selectionOutlineHitTargetWidth
) {
    return CanvasEditOverlayHitTarget(
        kind: .selectionTranslationArea,
        itemID: editOverlay.itemID,
        anchorRect: editOverlay.activeScreenQuad.boundingRect.standardized
    )
}
```

## 验证情况

- 参考依据：
  - `git diff -- MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
  - 生成记录前的 `git status --short`
  - 当前文件最新内容
- 本次实现阶段已执行并通过：
  - `ReadLints` 检查
  - `xcodebuild -destination "generic/platform=iOS" build`
  - `xcodebuild -destination "platform=macOS" test -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests"`
