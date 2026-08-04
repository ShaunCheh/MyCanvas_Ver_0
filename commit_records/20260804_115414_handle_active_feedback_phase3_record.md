# 20260804_115414_handle_active_feedback_phase3_record

## 记录范围

本记录对应 `handle active feedback` 计划的阶段 3：把 handle 交互状态接入 `CanvasEditorSession`，并由 `CanvasRenderer` 将精确 identity 投影为 snapshot 中的 `normal/active` 视觉语义。

本记录参考了创建记录前的 `git status --short`、`git diff --stat` 和四个变更文件的当前 `git diff`。下文不粘贴原始 diff，而是根据实际源码整理修改前后情况。

阶段 3 完成的数据链路是：

- `CanvasEditorSession` 持有非持久化 `CanvasEditHandleInteractionState`。
- session 根据 reading、inline text 和 inline crop 模式生成 presentation state。
- `makeCanvasSnapshot()` 将 presentation state 传给 renderer。
- renderer 集中遍历普通 edit handles、独立 rotate handle 和 group frame handles。
- 只有完整 identity 与活动 identity 相同的 geometry 被标记为 `.active`。
- runtime restore、history restore 和由它们承载的 board 切换路径统一清空状态。

本阶段没有修改双端 pointer 生命周期，也没有修改 viewport 的颜色样式，因此当前 UI 仍不会实际显示变色；这些属于后续阶段。

## 时间戳来源

文件名前缀由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 命令：生成“年月日_时分秒”格式的记录时间戳
date '+%Y%m%d_%H%M%S'
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# date 命令输出
20260804_115414
```

## 创建记录前的当前 changes

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# git status --short 的实际结果
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
```

`git diff --stat` 的实际统计为四个文件、`315 insertions(+), 19 deletions(-)`。

## 修改一：Session 持有共享 handle 瞬态状态

### 修改前

`CanvasEditorSession` 已有 inline edit、rotation preview、rotation interaction 和 alignment interaction 等瞬态状态，但没有 handle pressed/dragging 状态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// CanvasEditorSession 瞬态字段：修改前没有 editHandleInteractionState
var inlineEditState: CanvasInlineEditState?
var rotationPreviewState: CanvasRotationPreviewState?
var rotationInteractionState: CanvasRotationInteractionState?
var alignmentInteractionState: CanvasAlignmentInteractionState?
```

### 修改后

handle 状态与 rotation/alignment interaction state 同级保存。它只存在于 session 内存中，不属于文档或历史快照。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// CanvasEditorSession.editHandleInteractionState：保存当前 pressed/dragging handle 的非持久化状态
var inlineEditState: CanvasInlineEditState?
var rotationPreviewState: CanvasRotationPreviewState?
var rotationInteractionState: CanvasRotationInteractionState?
var alignmentInteractionState: CanvasAlignmentInteractionState?
var editHandleInteractionState = CanvasEditHandleInteractionState()
```

## 修改二：增加 presentation 边界

### 修改前

session 已对 selection、inline edit、rotation 和 alignment 提供 reading-mode presentation 入口，但 handle 状态没有独立 presentation 规则。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// presentationAlignmentInteractionState：修改前最后一个 interaction presentation 入口
var presentationAlignmentInteractionState: CanvasAlignmentInteractionState? {
    isReadingModeActive ? nil : alignmentInteractionState
}
```

### 修改后

新增 `presentationEditHandleInteractionState`：

- reading mode 返回 inactive presentation state。
- inline text 返回 inactive presentation state；inline text 没有可交互 handle chrome。
- inline crop 保留原始状态，因为 crop handle 本身就是本功能需要覆盖的 handle。
- presentation 抑制不会直接修改原始状态，后续统一生命周期或恢复路径再负责真正清理。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// presentationEditHandleInteractionState：抑制 reading/inline text，保留 inline crop 的 active 能力
var presentationEditHandleInteractionState: CanvasEditHandleInteractionState {
    guard
        isReadingModeActive == false,
        inlineEditState?.mode != .text
    else {
        return CanvasEditHandleInteractionState()
    }

    // Inline crop owns visible crop handles, so it must retain active
    // feedback. Inline text has no interactive handle chrome.
    return editHandleInteractionState
}
```

这里对 inline text 与 inline crop 做了明确区分。如果对所有 `inlineEditState` 一律返回 inactive，阶段 4 接入 pointer 后 crop handle 将永远无法显示 active，和计划要求覆盖 crop handle 的目标冲突。

## 修改三：Session 将 presentation state 送入 renderer

### 修改前

`makeCanvasSnapshot()` 只传递 selection、group selection、inline edit、rotation 和 alignment 等状态。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// makeCanvasSnapshot：修改前 renderer 收不到 handle 生命周期状态
let snapshot = renderer.makeSnapshot(
    scene: scene,
    groups: groups,
    boardState: boardState,
    camera: camera,
    interactionState: presentationInteractionState,
    groupInteractionState: groupInteractionState,
    inlineEditState: presentationInlineEditState,
    rotationPreviewState: presentationRotationPreviewState,
    rotationInteractionState: presentationRotationInteractionState,
    alignmentInteractionState: presentationAlignmentInteractionState
)
```

### 修改后

`makeCanvasSnapshot()` 传入 presentation handle state。原始 state 不直接越过 presentation 边界。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// makeCanvasSnapshot：将经过模式约束的 handle state 输入 renderer
let snapshot = renderer.makeSnapshot(
    scene: scene,
    groups: groups,
    boardState: boardState,
    camera: camera,
    interactionState: presentationInteractionState,
    groupInteractionState: groupInteractionState,
    editHandleInteractionState: presentationEditHandleInteractionState,
    inlineEditState: presentationInlineEditState,
    rotationPreviewState: presentationRotationPreviewState,
    rotationInteractionState: presentationRotationInteractionState,
    alignmentInteractionState: presentationAlignmentInteractionState
)
```

## 修改四：Renderer 集中投影 visual state

### 修改前

阶段 2 已让每个 geometry 携带 identity 和默认 `.normal` visual state，但 `CanvasRenderer.makeSnapshot()` 没有交互状态参数，也不会把任何 geometry 标记为 active。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeSnapshot：修改前 edit/group overlay 生成后直接写入 snapshot
let editOverlay = makeEditOverlay(
    scene: scene,
    camera: camera,
    interactionState: interactionState,
    inlineEditState: inlineEditState,
    rotationPreviewState: rotationPreviewState
)
let groupEditOverlay = makeGroupEditOverlay(
    groups: groups,
    camera: camera,
    groupInteractionState: groupInteractionState,
    inlineEditState: inlineEditState
)
```

### 修改后：Renderer 输入

`makeSnapshot()` 新增带默认 inactive 值的 `editHandleInteractionState` 参数。直接调用 renderer 的既有代码不传该参数时，所有 handles 继续保持 normal。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeSnapshot：接收共享 handle state，同时保留默认 inactive 兼容路径
func makeSnapshot(
    scene: CanvasScene,
    groups: [CanvasItemGroup] = [],
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    groupInteractionState: CanvasGroupInteractionState = CanvasGroupInteractionState(),
    editHandleInteractionState: CanvasEditHandleInteractionState = CanvasEditHandleInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil,
    alignmentInteractionState: CanvasAlignmentInteractionState? = nil
) -> CanvasRenderSnapshot {
    // 原有 snapshot 生成逻辑继续执行
}
```

### 修改后：统一投影出口

普通 edit overlay 和 canvas group edit overlay 都在完成几何与 identity 生成后，进入统一 visual-state 投影函数。这样不会把生命周期逻辑混进 resize/crop/arrow 等几何 helper。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// makeSnapshot：在 overlay 出口集中应用 handle visual state
let editOverlay = applyingEditHandleVisualStates(
    to: makeEditOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    ),
    editHandleInteractionState: editHandleInteractionState
)

let groupEditOverlay = applyingEditHandleVisualStates(
    to: makeGroupEditOverlay(
        groups: groups,
        camera: camera,
        groupInteractionState: groupInteractionState,
        inlineEditState: inlineEditState
    ),
    editHandleInteractionState: editHandleInteractionState
)
```

单个 geometry 的坐标、role 和 identity 原样保留，只重新计算 visual state。完整 identity 不相等的 handle 始终返回 `.normal`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// applyingEditHandleVisualState(to:editHandleInteractionState:)：按完整 identity 投影 normal/active
private func applyingEditHandleVisualState(
    to handle: CanvasEditHandleGeometry,
    editHandleInteractionState: CanvasEditHandleInteractionState
) -> CanvasEditHandleGeometry {
    CanvasEditHandleGeometry(
        identity: handle.identity,
        role: handle.role,
        screenCenter: handle.screenCenter,
        screenRotationRadians: handle.screenRotationRadians,
        visualState: editHandleInteractionState.visualState(
            for: handle.identity
        )
    )
}
```

### 独立 rotate handle 路径

rotate handle 位于 `CanvasEditSelectionOverlayPayload.rotateAffordance.handle`，不属于普通 `editOverlay.handles` 数组。renderer 在重建 selection payload 时单独投影这条路径。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// applyingEditHandleVisualStates(to:editHandleInteractionState:)：单独覆盖 rotateAffordance.handle
let rotateAffordance = selectionPayload.rotateAffordance.map { affordance in
    CanvasEditRotateOverlayPayload(
        guideScreenStart: affordance.guideScreenStart,
        guideScreenEnd: affordance.guideScreenEnd,
        handle: applyingEditHandleVisualState(
            to: affordance.handle,
            editHandleInteractionState: editHandleInteractionState
        )
    )
}
```

### Canvas group frame 路径

`groupEditOverlay.handles` 不属于普通 edit overlay，使用单独重载统一投影。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// applyingEditHandleVisualStates(to:editHandleInteractionState:)：覆盖 canvas group frame handles
private func applyingEditHandleVisualStates(
    to groupEditOverlay: CanvasGroupEditOverlay?,
    editHandleInteractionState: CanvasEditHandleInteractionState
) -> CanvasGroupEditOverlay? {
    guard let groupEditOverlay else {
        return nil
    }

    return CanvasGroupEditOverlay(
        groupID: groupEditOverlay.groupID,
        worldFrame: groupEditOverlay.worldFrame,
        screenFrame: groupEditOverlay.screenFrame,
        handles: groupEditOverlay.handles.map { handle in
            applyingEditHandleVisualState(
                to: handle,
                editHandleInteractionState: editHandleInteractionState
            )
        }
    )
}
```

该出口同时覆盖 selection resize、multi-selection resize、all-markdown edge resize、crop resize、arrow endpoint、single/multi rotate 和 group frame resize。

## 修改五：统一 runtime/history 恢复清理

### 修改前

`applyBoardRuntimeState` 与没有 active board 的 `applyBoardHistorySnapshot` 分别手工清空四类瞬态状态。新增 handle 状态后，如果继续在每个恢复入口手工追加，会增加遗漏 board 切换或恢复边界的风险。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// applyBoardRuntimeState / applyBoardHistorySnapshot：修改前重复清理各个瞬态字段
inlineEditState = nil
rotationPreviewState = nil
rotationInteractionState = nil
alignmentInteractionState = nil
```

### 修改后

新增 `resetTransientEditingState()` 作为统一恢复清理入口，并让 runtime 与 history 两条路径复用。active board 的 history restore 本来就调用 `applyBoardRuntimeState`，因此也会经过相同清理。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// resetTransientEditingState：集中清理所有非持久化编辑状态，包括 handle pressed/dragging
private func resetTransientEditingState() {
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
    alignmentInteractionState = nil
    editHandleInteractionState = CanvasEditHandleInteractionState()
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// applyBoardRuntimeState / applyBoardHistorySnapshot：board/runtime/history 恢复统一调用清理入口
workspaceMode = runtimeState.workspaceMode
resetTransientEditingState()

// applyBoardHistorySnapshot 的无 active board 分支
groupInteractionState = normalizedGroupInteractionState(
    snapshot.groupInteractionState
)
resetTransientEditingState()
lastRenderSnapshot = .empty
```

## 修改六：确认 history 与存储零变化

`currentBoardHistorySnapshot()` 的字段保持不变，没有加入 `editHandleInteractionState`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// currentBoardHistorySnapshot：只记录文档、selection 和 group selection，不记录 handle 瞬态状态
func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedBoardItems(),
        groups: groups,
        boardState: boardState,
        interactionState: interactionState,
        groupInteractionState: normalizedGroupInteractionState(
            groupInteractionState
        )
    )
}
```

本阶段没有修改 `BoardHistorySnapshot`、`BoardRuntimeState`、`BoardDocumentMapper`、autosave 或文档格式。

## 修改七：测试覆盖

### Renderer 与 presentation 测试

`CanvasEditHandleIdentityPipelineTests` 新增四个测试：

- `testSessionProjectsOnlyExactSelectionOrRotateIdentityAsActive`
- `testInlineCropActivatesOnlyMatchingCropIdentity`
- `testReadingModeSuppressesActiveGroupHandleWithoutMutatingRawState`
- `testInlineTextSuppressesActiveFeedbackWithoutMutatingRawState`

普通 selection resize 只激活完整 identity 相同的一个 handle，rotate 的独立 geometry 路径也单独验证。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testSessionProjectsOnlyExactSelectionOrRotateIdentityAsActive：精确匹配普通 resize 与独立 rotate handle
let resizeIdentity = CanvasEditHandleIdentity(
    owner: .item(item.id),
    kind: .selectionResize(.topLeading)
)
_ = session.editHandleInteractionState.apply(.press(resizeIdentity))

let resizeSnapshot = session.makeCanvasSnapshot()
let resizeOverlay = try XCTUnwrap(resizeSnapshot.editOverlay)
XCTAssertEqual(
    resizeOverlay.handles
        .filter { $0.visualState == .active }
        .map(\.identity),
    [resizeIdentity]
)
```

inline crop 会保留状态入口，但 selection identity 不会误激活同方位 crop handle；切换为精确 crop identity 后才 active。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testInlineCropActivatesOnlyMatchingCropIdentity：同方位不同 family 不串用 active
let selectionIdentity = CanvasEditHandleIdentity(
    owner: .item(item.id),
    kind: .selectionResize(.topLeading)
)
_ = session.editHandleInteractionState.apply(.press(selectionIdentity))
session.inlineEditState = CanvasInlineEditState(item: item)

let unmatchedSnapshot = session.makeCanvasSnapshot()
let unmatchedOverlay = try XCTUnwrap(unmatchedSnapshot.editOverlay)
XCTAssertTrue(
    unmatchedOverlay.handles.allSatisfy { $0.visualState == .normal }
)

let cropIdentity = CanvasEditHandleIdentity(
    owner: .item(item.id),
    kind: .cropResize(.topLeading)
)
_ = session.editHandleInteractionState.apply(.press(cropIdentity))
```

reading mode 使用 inactive presentation state，原始 pressed state 不被 presentation getter 修改。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testReadingModeSuppressesActiveGroupHandleWithoutMutatingRawState：显示态 normal，原始状态仍为 pressed
session.workspaceMode = .reading
let readingSnapshot = session.makeCanvasSnapshot()
let readingOverlay = try XCTUnwrap(readingSnapshot.groupEditOverlay)
XCTAssertTrue(
    readingOverlay.handles.allSatisfy { $0.visualState == .normal }
)
XCTAssertEqual(
    session.editHandleInteractionState.phase,
    .pressed(activeIdentity)
)
```

inline text 沿用现有行为隐藏整个 edit overlay，同时 presentation handle state 为 inactive。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
// testInlineTextSuppressesActiveFeedbackWithoutMutatingRawState：inline text 不输出 active handle chrome
session.inlineEditState = CanvasInlineEditState(item: item)

XCTAssertEqual(
    session.presentationEditHandleInteractionState.phase,
    .inactive
)
let snapshot = session.makeCanvasSnapshot()
XCTAssertNil(snapshot.editOverlay)
```

### History/runtime 边界测试

`CanvasEditorSessionAlignmentOverlayTests` 扩展了现有 transient 测试：

- history snapshot 在加入 active handle 状态前后仍相等。
- `applyBoardRuntimeState` 清空 handle state。
- 有 active board 和无 active board 的 `applyBoardHistorySnapshot` 都清空 handle state。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState：handle state 不进入 history snapshot
let baselineSnapshot = session.currentBoardHistorySnapshot()
activateAlignmentOverlayTestHandle(
    in: session,
    itemID: item.id
)
let historySnapshot = session.currentBoardHistorySnapshot()

XCTAssertEqual(historySnapshot, baselineSnapshot)
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// runtime/history restore tests：恢复完成后 handle state 回到 inactive
XCTAssertNil(session.rotationInteractionState)
XCTAssertNil(session.alignmentInteractionState)
XCTAssertEqual(session.editHandleInteractionState.phase, .inactive)
```

## 自动验证

### 首次聚焦测试与修正

首次执行两个阶段 3 相关测试类时，唯一失败为：

`testInlineTextSuppressesActiveFeedbackWithoutMutatingRawState`

失败原因不是业务实现错误，而是测试错误地假设 inline text 会保留一个 normal edit overlay。实际现有行为是 inline text 直接不生成 `editOverlay`，失败信息为 `XCTUnwrap failed: expected non-nil value of type "CanvasEditRenderOverlay"`。

测试随后改为如实断言 `snapshot.editOverlay == nil`，没有为通过测试而改变业务代码。

### 修正后的聚焦测试

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：运行阶段 3 visual-state 与 session transient 测试
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests"
```

结果：`TEST SUCCEEDED`，两个测试类共 33 个测试通过。

### 最终相关回归

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：运行 identity、state machine、overlay 和 group hierarchy 回归
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests"
```

结果：命令退出码为 `0`，四个测试类共 64 个测试全部通过。

### iOS Simulator 构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：确认阶段 3 session/renderer 链路可在 iOS Simulator 目标编译
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

结果：`BUILD SUCCEEDED`。

构建仍输出 `CanvasEditorSession.swift` 原有的 main-actor isolation warnings，位置为当前文件第 292、313 行；这些调用不属于本阶段修改。新增和修改文件的 IDE lint 检查没有错误，`git diff --check` 通过。

## 明确未修改的范围

- 未修改 iOS/macOS controller 的 pointer down、move、up、cancel 状态同步。
- 未修改 iOS/macOS viewport 的 handle fill/stroke 颜色。
- 未修改 handle 尺寸、形状、命中范围或 resize/crop/rotate 几何算法。
- 未修改 history snapshot 数据结构。
- 未修改 autosave、storage、document mapper 或文档格式。
- 未修改 `.cursor/plans/handle_active_feedback_fc72a0c4.plan.md`。

## 当前状态

创建本记录后，工作区包含阶段 3 的四个代码/测试修改，以及本记录文件。

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 创建记录后的预期 git status --short
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
?? commit_records/20260804_115414_handle_active_feedback_phase3_record.md
```

本次没有提交代码。
