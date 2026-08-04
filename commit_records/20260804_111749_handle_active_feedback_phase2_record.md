# 20260804_111749_handle_active_feedback_phase2_record

## 记录范围

本记录对应 `handle active feedback` 计划的阶段 2：把阶段 1 建立的稳定 handle identity 贯穿 renderer geometry、edit overlay hit testing、context resolver 和 pointer press context。

本记录参考了创建记录前的 `git status --short`、受版本控制文件的 `git diff --stat` 与 `git diff`，并直接检查了新增测试文件的当前内容。下文不粘贴原始 diff，而是按实际代码整理修改前后的业务变化。

阶段 2 只建立 identity 数据管线：

- renderer 为每个可交互 handle 生成完整 identity。
- render geometry 同时携带 identity 和默认 `.normal` visual state。
- hit tester 命中 handle 后直接返回 geometry 自带 identity。
- context resolver 把 identity 透传到 `CanvasPointerPressContext`。
- translation area、item/group body 和 blank 不属于 handle，identity 保持 `nil`。

本阶段尚未把阶段 1 的交互状态机接入 `CanvasEditorSession`，也没有修改 iOS/macOS viewport 的颜色渲染，因此当前 UI 中的 handle 仍不会实际变色。

## 时间戳来源

文件名前缀通过系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 命令：生成“年月日_时分秒”格式的记录时间戳
date '+%Y%m%d_%H%M%S'
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# date 命令输出
20260804_111749
```

## 创建记录前的当前 changes

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# git status --short 的实际结果
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
?? MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
```

受版本控制的五个源码文件统计为 `184 insertions(+), 37 deletions(-)`。新增测试文件尚未被 Git 跟踪，因此不在 `git diff --stat` 的数字中，但已纳入本记录。

## 修改一：render geometry 携带 identity 与 visual state

### 修改前

`CanvasEditHandleGeometry` 只有通用 role 和屏幕几何。相同 `.topLeading` role 无法区分 selection resize、crop resize 或 group frame resize，也无法表达 normal/active 渲染语义。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// CanvasEditHandleGeometry：修改前只包含方位和屏幕几何
struct CanvasEditHandleGeometry {
    let role: CanvasEditHandleRole
    let screenCenter: CGPoint
    let screenRotationRadians: CGFloat
}
```

### 修改后

geometry 增加阶段 1 定义的 `CanvasEditHandleIdentity` 和 `CanvasEditHandleVisualState`。初始化器把 visual state 默认设为 `.normal`，保证阶段 2 尚未接入交互状态机时，所有 handle 的现有视觉行为保持不变。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// CanvasEditHandleGeometry.init：稳定身份与易变屏幕几何分离，visualState 默认 normal
struct CanvasEditHandleGeometry {
    let identity: CanvasEditHandleIdentity
    let role: CanvasEditHandleRole
    let screenCenter: CGPoint
    let screenRotationRadians: CGFloat
    let visualState: CanvasEditHandleVisualState

    init(
        identity: CanvasEditHandleIdentity,
        role: CanvasEditHandleRole,
        screenCenter: CGPoint,
        screenRotationRadians: CGFloat,
        visualState: CanvasEditHandleVisualState = .normal
    ) {
        self.identity = identity
        self.role = role
        self.screenCenter = screenCenter
        self.screenRotationRadians = screenRotationRadians
        self.visualState = visualState
    }
}
```

## 修改二：renderer 按语义生成完整 identity

### 修改前

selection、crop 和 group frame 的普通 handle 最终只向共用 helper 传入 `[CanvasEditHandleRole]`。helper 只能生成方位与屏幕几何，无法知道 owner 或 handle family。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeEditHandles(for:roles:)：修改前只根据通用 role 生成 geometry
private func makeEditHandles(
    for screenQuad: CanvasQuad,
    roles: [CanvasEditHandleRole]
) -> [CanvasEditHandleGeometry] {
    let rotationRadians = editHandleRotation(for: screenQuad)
    return roles.map { role in
        CanvasEditHandleGeometry(
            role: role,
            screenCenter: editHandleCenter(for: role, in: screenQuad),
            screenRotationRadians: rotationRadians
        )
    }
}
```

### 修改后：语义 descriptor

renderer 新增 `EditHandleDescriptor`，要求调用方在进入通用几何 helper 前就明确 role 和 identity。通用 helper 不再根据 role 反推业务身份。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// EditHandleDescriptor / makeEditHandles(for:descriptors:)：几何生成只消费已经确定的语义 identity
private struct EditHandleDescriptor {
    let role: CanvasEditHandleRole
    let identity: CanvasEditHandleIdentity
}

private func makeEditHandles(
    for screenQuad: CanvasQuad,
    descriptors: [EditHandleDescriptor]
) -> [CanvasEditHandleGeometry] {
    let rotationRadians = editHandleRotation(for: screenQuad)
    return descriptors.map { descriptor in
        CanvasEditHandleGeometry(
            identity: descriptor.identity,
            role: descriptor.role,
            screenCenter: editHandleCenter(
                for: descriptor.role,
                in: screenQuad
            ),
            screenRotationRadians: rotationRadians
        )
    }
}
```

### 修改后：selection resize

单选 owner 使用 `.item(itemID)`；多选 owner 使用 `.selection(...)`，其中 primary 与无序成员集合共同确定身份。corner handle 和 all-markdown edge handle 都通过同一 selection 语义入口生成 `.selectionResize(role)`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeSelectionResizeHandles(for:roles:owner:)：为单选或多选 resize 生成 selectionResize identity
private func makeSelectionResizeHandles(
    for screenQuad: CanvasQuad,
    roles: [CanvasSelectionHandleRole],
    owner: CanvasEditHandleOwner
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        descriptors: roles.map { role in
            EditHandleDescriptor(
                role: role.editHandleRole,
                identity: CanvasEditHandleIdentity(
                    owner: owner,
                    kind: .selectionResize(role)
                )
            )
        }
    )
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeSelectionEditOverlay：多选 handle owner 使用规范化 selection identity
let handleOwner = CanvasEditHandleOwner.selection(
    CanvasEditHandleSelectionIdentity(
        primaryItemID: resolvedPrimarySelectedItemID,
        memberItemIDs: selectedItems.map(\.id)
    )
)

selectionHandles = selectionEditHandles(
    forGroupSelectedItems: selectedItems,
    screenQuad: screenQuad,
    owner: handleOwner
)
```

### 修改后：crop 与 canvas group frame

crop 和 group frame 不再复用没有 family 信息的 role 数组。即使二者和 selection 使用相同方位，也会得到不同 identity。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeCropEditHandles(for:itemID:)：同方位 crop handle 使用 cropResize kind
private func makeCropEditHandles(
    for screenQuad: CanvasQuad,
    itemID: CanvasItemID
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        descriptors: CanvasCropHandleRole.allCases.map { role in
            EditHandleDescriptor(
                role: role.editHandleRole,
                identity: CanvasEditHandleIdentity(
                    owner: .item(itemID),
                    kind: .cropResize(role)
                )
            )
        }
    )
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeGroupFrameResizeHandles(for:groupID:)：group frame handle 使用 group owner 和 groupFrameResize kind
private func makeGroupFrameResizeHandles(
    for screenQuad: CanvasQuad,
    groupID: CanvasItemGroupID
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        descriptors: CanvasSelectionHandleRole.allCases.map { role in
            EditHandleDescriptor(
                role: role.editHandleRole,
                identity: CanvasEditHandleIdentity(
                    owner: .group(groupID),
                    kind: .groupFrameResize(role)
                )
            )
        }
    )
}
```

### 修改后：arrow endpoint

arrow start/end 使用 arrow item 作为 owner，并保留各自 endpoint role。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeArrowEndpointHandles(for:camera:)：start/end geometry 分别携带 arrowEndpoint identity
private func makeArrowEndpointHandles(
    for item: CanvasArrowItem,
    camera: CanvasCamera
) -> [CanvasEditHandleGeometry] {
    CanvasArrowEndpointRole.allCases.map { role in
        CanvasEditHandleGeometry(
            identity: CanvasEditHandleIdentity(
                owner: .item(item.id),
                kind: .arrowEndpoint(role)
            ),
            role: role == .start ? .arrowStart : .arrowEnd,
            screenCenter: camera.worldToViewport(
                item.endpointWorldPoint(for: role)
            ),
            screenRotationRadians: item.rotationRadians
        )
    }
}
```

### 修改后：rotate 的独立路径

rotate handle 不位于普通 `editOverlay.handles` 数组中，而是位于 `rotateAffordance.handle`。现在单选 rotate 使用 item owner，多选 rotate 使用 selection owner，两者都使用 `.rotate` kind。

rotation interaction HUD 原来复用 `makeRotateAffordance` 只是为了取得 guide endpoint。加入必填 identity 后，没有为 HUD 构造虚假 identity；本次把纯几何计算拆到 `makeRotateAffordanceGeometry`，真实 edit handle 才创建 `CanvasEditHandleGeometry`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeRotateAffordance(screenCenter:screenQuad:identity:)：只有真实 rotate handle 接收稳定 identity
private func makeRotateAffordance(
    screenCenter: CGPoint,
    screenQuad: CanvasQuad,
    identity: CanvasEditHandleIdentity
) -> CanvasEditRotateOverlayPayload {
    let geometry = makeRotateAffordanceGeometry(
        screenCenter: screenCenter,
        screenQuad: screenQuad
    )
    return CanvasEditRotateOverlayPayload(
        guideScreenStart: geometry.guideScreenStart,
        guideScreenEnd: geometry.guideScreenEnd,
        handle: CanvasEditHandleGeometry(
            identity: identity,
            role: .rotate,
            screenCenter: geometry.guideScreenEnd,
            screenRotationRadians: geometry.screenRotationRadians
        )
    )
}
```

renderer 最终覆盖以下 handle 路径：

- 单选 image、hand drawing 的 corner resize。
- 单选 markdown 的 edge resize。
- 多选普通 corner resize。
- 全 markdown 多选 edge resize。
- 单选和多选 rotate。
- crop 的八个 resize handle。
- arrow start/end endpoint。
- canvas group frame 的八个 resize handle。

## 修改三：hit tester 返回 geometry 自带 identity

### 修改前

`CanvasEditOverlayHitTarget` 只有 target kind、item ID 和 anchor rect。hit tester 根据 geometry role 判断目标类型，但命中结果没有保留具体 handle identity。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// CanvasEditOverlayHitTarget：修改前没有 targetHandleIdentity
struct CanvasEditOverlayHitTarget {
    let kind: CanvasEditOverlayHitTargetKind
    let itemID: CanvasItemID
    let anchorRect: CGRect
}
```

### 修改后

命中 selection、crop、rotate 或 arrow handle 时，结果直接使用命中 geometry 的 identity，不在 hit tester 内重新拼装 owner/kind/role。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// CanvasEditOverlayHitTarget：保存命中 geometry 的稳定 identity
struct CanvasEditOverlayHitTarget {
    let kind: CanvasEditOverlayHitTargetKind
    let itemID: CanvasItemID
    let targetHandleIdentity: CanvasEditHandleIdentity?
    let anchorRect: CGRect
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// resolveSelectionHitTarget：普通 selection handle 直接透传 handle.identity
return CanvasEditOverlayHitTarget(
    kind: handleHitTargetKind,
    itemID: editOverlay.itemID,
    targetHandleIdentity: handle.identity,
    anchorRect: hitRect
)
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// resolveSelectionHitTarget：rotateAffordance.handle 是独立路径，单独透传其 identity
return CanvasEditOverlayHitTarget(
    kind: rotateHitTargetKind,
    itemID: editOverlay.itemID,
    targetHandleIdentity: rotateAffordance.handle.identity,
    anchorRect: rotateHitRect
)
```

translation area 不是 handle，因此显式写入 `nil`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// resolveCropHitTarget：crop translation area 保持非 handle 语义
return CanvasEditOverlayHitTarget(
    kind: .cropTranslationArea,
    itemID: editOverlay.itemID,
    targetHandleIdentity: nil,
    anchorRect: payload.cropScreenQuad.boundingRect.standardized
)
```

## 修改四：identity 贯穿 context resolver 和 pointer press context

### 修改前

`CanvasPointerPressContext` 只能表达 target kind、item/group ID 和 anchor rect。controller 即使知道按中了 handle，也无法取得与 render geometry 一致的稳定 identity。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// CanvasPointerPressContext：修改前没有 targetHandleIdentity
struct CanvasPointerPressContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasPointerTargetKind
    let targetItemID: CanvasItemID?
    let targetGroupID: CanvasItemGroupID?
    let anchorRect: CGRect?
}
```

### 修改后

pointer press context 增加可选 identity。`CanvasPointerTargetKind` 保持不变，现有 controller 仍可继续使用原分支执行几何行为。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
// CanvasPointerPressContext：为后续 pointer 生命周期提供命中的稳定 handle identity
struct CanvasPointerPressContext {
    let invocationViewportPoint: CGPoint
    let invocationWorldPoint: CGPoint
    let targetKind: CanvasPointerTargetKind
    let targetItemID: CanvasItemID?
    let targetGroupID: CanvasItemGroupID?
    let targetHandleIdentity: CanvasEditHandleIdentity?
    let anchorRect: CGRect?
}
```

普通 edit overlay 命中结果通过 `ResolvedTarget` 传入最终 context。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// resolvedTarget(from:)：把 hit target 中的 geometry identity 写入内部解析结果
return ResolvedTarget(
    pointerTargetKind: pointerTargetKind,
    editOverlayHitTargetKind: hitTarget.kind,
    targetItemID: hitTarget.itemID,
    targetHandleIdentity: hitTarget.targetHandleIdentity,
    anchorRect: hitTarget.anchorRect
)
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// makePointerPressContext：把内部解析结果中的 identity 原样写入 pointer press context
CanvasPointerPressContext(
    invocationViewportPoint: viewportPoint,
    invocationWorldPoint: worldPoint,
    targetKind: resolvedTarget.pointerTargetKind,
    targetItemID: resolvedTarget.targetItemID,
    targetGroupID: resolvedTarget.targetGroupID,
    targetHandleIdentity: resolvedTarget.targetHandleIdentity,
    anchorRect: resolvedTarget.anchorRect
)
```

canvas group frame resize 不经过 `CanvasEditOverlayHitTester`，因此在 `resolveGroupEditOverlayTarget` 中单独透传 `groupEditOverlay.handles` 中命中 handle 的 identity。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// resolveGroupEditOverlayTarget：覆盖 groupEditOverlay.handles 的独立命中路径
return ResolvedTarget(
    pointerTargetKind: .groupFrameResizeHandle(role: role),
    targetGroupID: overlay.groupID,
    targetHandleIdentity: handle.identity,
    anchorRect: hitRect
)
```

item body、group frame body、blank、reading mode suppressed target 和 inline edit blank 等路径没有赋值，使用 `ResolvedTarget.targetHandleIdentity` 的默认 `nil`。

## 修改五：新增 identity 管线契约测试

### 修改前

不存在 `CanvasEditHandleIdentityPipelineTests.swift`。阶段 1 只测试了 identity 和状态机自身，没有验证 renderer、hit tester 与 pointer context 是否使用同一个 identity。

### 修改后

新增五个测试：

- `testSelectionAndCropSameRoleKeepDistinctIdentitiesThroughHitPipeline`
- `testMultiSelectionResizeAndRotateUseCanonicalSelectionOwner`
- `testMarkdownEdgesAndArrowEndpointsReceiveSemanticIdentities`
- `testCanvasGroupFrameIdentityStaysDistinctFromMultiSelection`
- `testTranslationBodyAndBlankTargetsNeverCarryHandleIdentity`

selection 与 crop 即使都是 `.topLeading`，也分别得到 `.selectionResize(.topLeading)` 与 `.cropResize(.topLeading)`，并验证 geometry、hit target、pointer press context 三者 identity 完全一致。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testSelectionAndCropSameRoleKeepDistinctIdentitiesThroughHitPipeline：验证同方位不同 family 不冲突
XCTAssertEqual(
    selectionHandle.identity,
    CanvasEditHandleIdentity(
        owner: .item(item.id),
        kind: .selectionResize(.topLeading)
    )
)

XCTAssertEqual(
    cropHandle.identity,
    CanvasEditHandleIdentity(
        owner: .item(item.id),
        kind: .cropResize(.topLeading)
    )
)
XCTAssertNotEqual(selectionHandle.identity, cropHandle.identity)
XCTAssertEqual(
    cropPressContext.targetHandleIdentity,
    cropHandle.identity
)
```

多选与 canvas group 使用不同 owner shape，防止两种“组”语义混淆。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testCanvasGroupFrameIdentityStaysDistinctFromMultiSelection：验证 canvas group 与 multi-selection identity 分离
XCTAssertEqual(
    groupHandle.identity,
    CanvasEditHandleIdentity(
        owner: .group(groupID),
        kind: .groupFrameResize(.topLeading)
    )
)
XCTAssertEqual(groupHandle.visualState, .normal)
XCTAssertNotEqual(selectionHandle.identity, groupHandle.identity)
XCTAssertEqual(
    pressContext.targetHandleIdentity,
    groupHandle.identity
)
```

非 handle 目标保持 `nil`，覆盖 selection translation、selected item body、blank、crop translation 和 group frame body。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testTranslationBodyAndBlankTargetsNeverCarryHandleIdentity：非 handle 命中不得携带陈旧或伪造 identity
XCTAssertNil(translationContext.targetHandleIdentity)
XCTAssertNil(bodyContext.targetHandleIdentity)
XCTAssertNil(blankContext.targetHandleIdentity)
XCTAssertNil(cropTranslationContext.targetHandleIdentity)
XCTAssertNil(groupBodyContext.targetHandleIdentity)
```

## 自动验证

### macOS 相关回归测试

最终顺序执行了阶段 2 新测试、阶段 1 状态机测试，以及受 renderer/context 影响的 alignment overlay 与 group hierarchy 测试。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：运行 handle identity、状态机、overlay 和 group hierarchy 相关测试
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests"
```

结果：`TEST SUCCEEDED`，四个测试类共 60 个测试全部通过。

### iOS Simulator 构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：确认阶段 2 共享管线可在 iOS Simulator 目标编译
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

结果：`BUILD SUCCEEDED`。

### 静态检查

- 六个新增或修改文件的 IDE lint 检查没有错误。
- `git diff --check` 通过。

## 明确未修改的范围

- 未向 `CanvasEditorSession` 添加 active handle 瞬态状态。
- 未把 `CanvasEditHandleInteractionState` 传给 renderer。
- 未修改 iOS/macOS controller 的 pointer down、move、up 或 cancel 生命周期。
- 未修改 iOS/macOS viewport 的 handle fill/stroke 颜色。
- 未修改 resize、crop、rotate、arrow endpoint 或 group frame 的几何计算结果。
- 未修改 history、autosave、storage、document mapper 或文档格式。
- 未修改 `.cursor/plans/handle_active_feedback_fc72a0c4.plan.md`。

## 当前状态

创建本记录后，工作区包含阶段 2 的五个源码修改、一个新增测试文件，以及本记录文件。

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 创建记录文件后的预期 git status --short
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
?? MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
?? commit_records/20260804_111749_handle_active_feedback_phase2_record.md
```

本次没有提交代码。
