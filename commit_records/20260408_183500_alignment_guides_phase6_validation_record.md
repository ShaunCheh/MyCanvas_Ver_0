# 20260408_183500_alignment_guides_phase6_validation_record

## 记录范围

- 记录内容：
  1. 补齐 `CanvasEditorSessionAlignmentOverlayTests`，把 `Phase 6` 中最关键的架构回归点转成自动化测试。
  2. 验证 `alignment transient state` 不进入 history/runtime 快照，并且在恢复路径上会被清空。
  3. 验证裁剪模式下不会显示 `alignment overlay`，避免与编辑态 overlay 语义冲突。
- 涉及文件：
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
- 当前 changes 依据：
  - `git status --short` 当前显示：
    - `M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `git diff --stat -- MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 当前显示：
    - `1 file changed, 214 insertions(+), 2 deletions(-)`
  - `git diff -- MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 显示：本次修改集中在新增 `Phase 6` 验证用例、扩展测试 session 构造入口，以及补齐 image/runtime 测试辅助函数。
- 验证依据：
  - `ReadLints`：`CanvasEditorSessionAlignmentOverlayTests.swift` 无新增诊断问题。
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`：通过。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS"`：通过。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator"`：通过。
- 如实说明：
  - 本次 `Phase 6` 没有修改生产代码，只补了测试与验证覆盖。
  - 当前项目里没有现成的 `iOSViewController` / `macOSViewController` 指针交互测试基建，因此 `pointer up/cancel` 的 controller 收尾语义本次没有新增自动化用例。
  - “不同缩放下的吸附手感”“视口边缘/自动扩板时的真实交互体验”本次没有做人工拖拽验收，只能确认共享测试与双端构建通过。
- 本记录不包含：
  - git commit / push
  - 新的生产实现改动
  - 人工交互录屏或手验结论

## 修改一：从“只测 overlay 生成与屏蔽”扩展到“覆盖 `Phase 6` 的关键架构回归点”

### 修改前

- 修改前测试文件只覆盖：
  - 命中时能生成 `alignment overlay`
  - 阅读模式下隐藏
  - `rotation` 优先级高于 `alignment`
  - 文本 inline edit 下隐藏
- 还没有覆盖：
  - 裁剪模式
  - `history snapshot` 不携带 transient state
  - `applyBoardRuntimeState(...)`
  - `applyBoardHistorySnapshot(...)`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: CanvasEditorSessionAlignmentOverlayTests
// 功能说明: 修改前测试范围只覆盖 overlay 的基础生成和少量屏蔽条件，还没有进入 runtime/history 恢复链路的回归验证。
@MainActor
final class CanvasEditorSessionAlignmentOverlayTests: XCTestCase {
    func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws { ... }

    func testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() { ... }

    func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws { ... }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() { ... }
}
```

### 修改后

- 修改后新增 5 个高价值测试，把 `Phase 6` 计划里最容易回归的架构语义直接锁住：
  - `testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineCropEdit()`
  - `testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState()`
  - `testApplyBoardRuntimeStateClearsTransientAlignmentState()`
  - `testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithoutActiveBoard()`
  - `testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithActiveBoard()`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: CanvasEditorSessionAlignmentOverlayTests
// 功能说明: 修改后测试范围从 overlay 基础显示扩展到 crop/history/runtime 三类 Phase 6 回归点，保证 alignment transient state 只活在交互瞬时层。
@MainActor
final class CanvasEditorSessionAlignmentOverlayTests: XCTestCase {
    func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws { ... }

    func testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() { ... }

    func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws { ... }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() { ... }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineCropEdit() throws { ... }

    func testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState() { ... }

    func testApplyBoardRuntimeStateClearsTransientAlignmentState() { ... }

    func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithoutActiveBoard() { ... }

    func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithActiveBoard() { ... }
}
```

## 修改二：新增裁剪模式屏蔽测试，补齐编辑态 overlay 回归

### 修改前

- 修改前只有文本 inline edit 的屏蔽测试，没有验证图片裁剪模式下 `alignment overlay` 是否同样被屏蔽。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit()
// 功能说明: 修改前只校验文本 inline edit，会不会隐藏 alignment overlay；crop 模式还是空白区。
func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() {
    let item = makeAlignmentOverlayTestItem()
    let session = makeAlignmentOverlayTestSession(with: item)
    session.inlineEditState = CanvasInlineEditState(item: item)
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: item.id
    )

    let snapshot = session.makeCanvasSnapshot()

    XCTAssertNil(snapshot.interactionOverlay)
}
```

### 修改后

- 新增 image item 与 crop inline edit 测试，确保图片进入裁剪态时不会误显示拖拽辅助线。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineCropEdit()
// 功能说明: 修改后显式验证图片裁剪模式会屏蔽 alignment overlay，避免 crop chrome 与 drag guide 混在同一帧。
func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineCropEdit() throws {
    let item = try makeAlignmentOverlayTestImageItem()
    let session = makeAlignmentOverlayTestSession(with: item)
    session.inlineEditState = CanvasInlineEditState(item: item)
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: item.id
    )

    let snapshot = session.makeCanvasSnapshot()

    XCTAssertNil(snapshot.interactionOverlay)
}
```

## 修改三：把 “transient state 不进 history” 从约定补成测试

### 修改前

- 修改前测试没有直接约束 `currentBoardHistorySnapshot()` 的返回值，因此 `alignmentInteractionState` 是否意外渗入 history 只能靠代码阅读判断。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: currentBoardHistorySnapshot() 相关测试
// 功能说明: 修改前这里没有 history snapshot 级测试，alignment transient state “不进历史”的约束尚未被自动化锁定。
// 无对应测试用例
```

### 修改后

- 新增 `testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState()`，直接比较写入 transient state 前后的历史快照是否一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState()
// 功能说明: 修改后显式验证 rotation/alignment transient state 不会污染 BoardHistorySnapshot，保证 undo/redo 边界只记录文档态。
func testCurrentBoardHistorySnapshotIgnoresTransientAlignmentState() {
    let item = makeAlignmentOverlayTestItem()
    let session = makeAlignmentOverlayTestSession(with: item)
    let baselineSnapshot = session.currentBoardHistorySnapshot()

    session.rotationInteractionState = CanvasRotationInteractionState(
        itemID: item.id
    )
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: item.id
    )

    let historySnapshot = session.currentBoardHistorySnapshot()

    XCTAssertEqual(historySnapshot, baselineSnapshot)
}
```

## 修改四：把 runtime/history 恢复时的 transient state 清理语义补成自动化

### 修改前

- 修改前没有测试去覆盖以下两条路径：
  - `applyBoardRuntimeState(...)`
  - `applyBoardHistorySnapshot(...)`
- 所以虽然生产代码已经在恢复路径里清空 `alignmentInteractionState`，但一旦后续改动误删清理语句，测试不会报警。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: applyBoardRuntimeState(...) / applyBoardHistorySnapshot(...) 相关测试
// 功能说明: 修改前恢复路径没有配套测试，alignment transient state 的清理时机还没有被自动化覆盖。
// 无对应测试用例
```

### 修改后

- 新增 3 个测试分别覆盖：
  - runtime restore
  - history restore（无 active board）
  - history restore（有 active board）
- 这些测试不仅断言 transient state 被清空，还断言 `scene` 已切换到新的恢复对象，避免只测到“清空了状态”而没测到“恢复链路真的执行了”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testApplyBoardRuntimeStateClearsTransientAlignmentState()
// 功能说明: 修改后验证 runtime restore 会清掉 alignment/rotation transient state，并把 scene 切到恢复后的文档对象。
func testApplyBoardRuntimeStateClearsTransientAlignmentState() {
    let currentItem = makeAlignmentOverlayTestItem()
    let replacementItem = CanvasTextItem(
        text: "restored",
        center: CGPoint(x: 160, y: 80),
        size: CGSize(width: 110, height: 44)
    )
    let session = makeAlignmentOverlayTestSession(with: currentItem)
    session.rotationInteractionState = CanvasRotationInteractionState(
        itemID: currentItem.id
    )
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: currentItem.id
    )

    session.applyBoardRuntimeState(
        makeAlignmentOverlayTestRuntimeState(
            items: [.text(replacementItem)],
            selectedItemID: replacementItem.id
        )
    )

    XCTAssertNil(session.rotationInteractionState)
    XCTAssertNil(session.alignmentInteractionState)
    XCTAssertEqual(session.scene.boardItem(withID: replacementItem.id)?.id, replacementItem.id)
    XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithoutActiveBoard()
// 功能说明: 修改后验证在没有 active board 的 fallback 路径上，history restore 也会清掉 transient state，并正确替换 scene 数据。
func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithoutActiveBoard() {
    let currentItem = makeAlignmentOverlayTestItem()
    let replacementItem = CanvasTextItem(
        text: "undo target",
        center: CGPoint(x: 180, y: 120),
        size: CGSize(width: 120, height: 48)
    )
    let session = makeAlignmentOverlayTestSession(with: currentItem)
    session.rotationInteractionState = CanvasRotationInteractionState(
        itemID: currentItem.id
    )
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: currentItem.id
    )

    session.applyBoardHistorySnapshot(
        BoardHistorySnapshot(
            items: [.text(replacementItem)],
            boardState: nil,
            interactionState: CanvasInteractionState(selectedItemID: replacementItem.id)
        )
    )

    XCTAssertNil(session.rotationInteractionState)
    XCTAssertNil(session.alignmentInteractionState)
    XCTAssertEqual(session.scene.boardItem(withID: replacementItem.id)?.id, replacementItem.id)
    XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithActiveBoard()
// 功能说明: 修改后验证在 active board 已存在的真实 restore 路径上，history restore 同样会清理 transient state，避免 undo/redo 后残留辅助线。
func testApplyBoardHistorySnapshotClearsTransientAlignmentStateWithActiveBoard() {
    let currentItem = makeAlignmentOverlayTestItem()
    let replacementItem = CanvasTextItem(
        text: "redo target",
        center: CGPoint(x: 220, y: 140),
        size: CGSize(width: 140, height: 52)
    )
    let session = makeAlignmentOverlayTestSession(with: currentItem)
    session.applyBoardRuntimeState(
        makeAlignmentOverlayTestRuntimeState(
            items: [.text(currentItem)],
            selectedItemID: currentItem.id
        )
    )
    session.rotationInteractionState = CanvasRotationInteractionState(
        itemID: currentItem.id
    )
    session.alignmentInteractionState = makeAlignmentOverlayTestState(
        itemID: currentItem.id
    )

    session.applyBoardHistorySnapshot(
        BoardHistorySnapshot(
            items: [.text(replacementItem)],
            boardState: nil,
            interactionState: CanvasInteractionState(selectedItemID: replacementItem.id)
        )
    )

    XCTAssertNil(session.rotationInteractionState)
    XCTAssertNil(session.alignmentInteractionState)
    XCTAssertEqual(session.scene.boardItem(withID: replacementItem.id)?.id, replacementItem.id)
    XCTAssertNil(session.scene.boardItem(withID: currentItem.id))
}
```

## 修改五：扩展测试基建，支持 image item 与 runtime restore 场景

### 修改前

- 修改前测试辅助函数只有文本 item 入口：
  - `makeAlignmentOverlayTestSession(with item: CanvasTextItem)`
  - `makeAlignmentOverlayTestItem()`
  - `makeAlignmentOverlayTestState(...)`
- 这意味着：
  - 不能直接构造 crop 场景
  - 不能便捷构造 image item
  - 不能快速拼装 runtime restore 所需的 `BoardRuntimeState`

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: makeAlignmentOverlayTestSession(with:) / makeAlignmentOverlayTestItem() / makeAlignmentOverlayTestState(...)
// 功能说明: 修改前测试辅助函数只面向 text item，无法支撑 crop/image/runtime 三类新增验证场景。
private func makeAlignmentOverlayTestSession(
    with item: CanvasTextItem
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems([.text(item)])
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 600, height: 400)
    )
    session.interactionState.selectedItemID = item.id
    CanvasEditorSessionAlignmentOverlayTestRetainer.sessions.append(session)
    return session
}
```

### 修改后

- 修改后新增通用辅助层：
  - `makeAlignmentOverlayTestSession(items:selectedItemID:)`
  - `makeAlignmentOverlayTestSession(with item: CanvasImageItem)`
  - `makeAlignmentOverlayTestRuntimeState(...)`
  - `makeAlignmentOverlayTestImageItem()`
  - `makeAlignmentOverlayTestCGImage()`
  - `AlignmentOverlayTestImageError`
- 这样测试文件就能直接覆盖 text/image/runtime 三种不同维度的验证需求。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: makeAlignmentOverlayTestSession(items:selectedItemID:) / makeAlignmentOverlayTestRuntimeState(...) / makeAlignmentOverlayTestImageItem()
// 功能说明: 修改后测试辅助层被扩展为通用工厂，既能创建 text/image 两类 session，也能快速拼装 runtime restore 输入和最小可用 CGImage。
private func makeAlignmentOverlayTestSession(
    with item: CanvasImageItem
) -> CanvasEditorSession {
    makeAlignmentOverlayTestSession(
        items: [.image(item)],
        selectedItemID: item.id
    )
}

private func makeAlignmentOverlayTestSession(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems(items)
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 600, height: 400)
    )
    session.interactionState.selectedItemID = selectedItemID
    CanvasEditorSessionAlignmentOverlayTestRetainer.sessions.append(session)
    return session
}

private func makeAlignmentOverlayTestRuntimeState(
    items: [CanvasBoardItem],
    selectedItemID: CanvasItemID? = nil
) -> BoardRuntimeState {
    BoardRuntimeState(
        boardID: UUID(),
        title: "Alignment Test Board",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        items: items,
        boardState: nil,
        camera: CanvasCamera(
            center: .zero,
            zoomScale: 1,
            viewportSize: CGSize(width: 600, height: 400)
        ),
        interactionState: CanvasInteractionState(selectedItemID: selectedItemID),
        workspaceMode: .editing
    )
}

private func makeAlignmentOverlayTestImageItem() throws -> CanvasImageItem {
    CanvasImageItem(
        asset: .transientStaticImage(
            cgImage: try makeAlignmentOverlayTestCGImage()
        ),
        center: CGPoint(x: 20, y: 20),
        size: CGSize(width: 96, height: 64)
    )
}
```

## 修改结果

- `Phase 6` 这次实际新增的是测试与验证，不是新的生产实现。
- 自动化现在已经覆盖：
  - `reading mode`
  - `rotation > alignment` 优先级
  - 文本 inline edit
  - 图片 crop inline edit
  - `history snapshot` 不包含 transient state
  - `runtime/history restore` 会清理 transient state
- 当前仍未自动化覆盖：
  - controller 级 `pointer up/cancel` 收尾手势链路
  - 人工交互手感验证
- 当前工作区只包含这一个测试文件的未提交修改。
