# 20260723_164349_group_nesting_phase4_subtree_drag_record

## 记录范围

本记录对应刚刚实施的 `group_nesting_78437533.plan.md` 阶段 4：拖动 parent group 时移动整棵子树，resize parent group 时仍只改变当前 group frame，不移动 child group 或内部 item。

当前 changes 涉及：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`

## 修改前

修改前，group drag 只保存当前 group 的 frame 和当前 group 的 direct member item geometry。它无法表达 descendant group frame，也无法表达整棵子树内的 item geometry。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS group drag state 只保存 direct member item 几何，不能移动 child group frame。
// 函数名：PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialMemberGeometries: [CanvasBoardItemGeometry]
    let dragStartWorldLocation: CGPoint
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS group drag state 只保存 direct member item 几何，不能移动 child group frame。
// 函数名：PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialMemberGeometries: [CanvasBoardItemGeometry]
    let dragStartWorldLocation: CGPoint
}
```

修改前，drag 开始时调用 `groupMemberGeometries(withID:)`，只读取当前 group 的 `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前只返回当前 group direct item 的 geometry。
// 函数名：CanvasEditorSession.groupMemberGeometries(withID:)
func groupMemberGeometries(withID groupID: CanvasItemGroupID) -> [CanvasBoardItemGeometry] {
    guard let group = group(withID: groupID) else {
        return []
    }

    return group.itemIDs.compactMap { itemID in
        scene.boardItem(withID: itemID).map(CanvasBoardItemGeometry.init(item:))
    }
}
```

修改前，移动 group frame 时只提交当前 group frame 和 direct member item geometries。因此拖动 parent C 时，child group A/B 的 frame 不会跟随移动。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 iOS group drag 只平移 direct member item geometries。
// 函数名：iOSViewController.moveGroupFrame(using:to:)
let proposedMemberGeometries = dragState.initialMemberGeometries.map { geometry in
    CanvasBoardItemGeometry(
        itemID: geometry.itemID,
        center: CGPoint(
            x: geometry.center.x + translation.x,
            y: geometry.center.y + translation.y
        ),
        size: geometry.size,
        rotationRadians: geometry.rotationRadians
    )
}
guard editorSession.updateGroupFrameAndMemberGeometries(
    withID: dragState.groupID,
    to: proposedFrame,
    memberGeometries: proposedMemberGeometries,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

修改前，resize 已经只调用 `updateGroupFrame(... reconcileMembership: false)`，这个语义在阶段 4 中保持不变。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：resize 路径修改前已经只更新当前 group frame，不移动内部 item。
// 函数名：iOSViewController.resizeGroupFrame(using:to:)
guard editorSession.updateGroupFrame(
    withID: resizeState.groupID,
    to: proposedFrame,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: resizeState.groupID)
        == proposedFrame.standardized
}
```

## 修改后

修改后，新增 subtree geometry 数据结构，用于在拖动开始时保存 descendant group frame 和 subtree item geometry。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：表达 descendant group frame 的可移动快照。
// 函数名：CanvasGroupFrameGeometry
struct CanvasGroupFrameGeometry: Equatable {
    let groupID: CanvasItemGroupID
    let frame: CGRect

    init(
        groupID: CanvasItemGroupID,
        frame: CGRect
    ) {
        self.groupID = groupID
        self.frame = frame.standardized
    }
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：表达 group subtree 的移动快照，包含 descendant group frames 和 subtree item geometries。
// 函数名：CanvasGroupSubtreeGeometries
struct CanvasGroupSubtreeGeometries: Equatable {
    let descendantGroupFrames: [CanvasGroupFrameGeometry]
    let itemGeometries: [CanvasBoardItemGeometry]

    init(
        descendantGroupFrames: [CanvasGroupFrameGeometry],
        itemGeometries: [CanvasBoardItemGeometry]
    ) {
        self.descendantGroupFrames = descendantGroupFrames
        self.itemGeometries = itemGeometries
    }
}
```

修改后，`groupSubtreeGeometries(withID:)` 会返回 descendant group frame，并把当前 group direct item 与 descendant item 合并成 subtree item geometry。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：读取 group subtree 快照，供拖动 parent/child group 时平移整棵子树。
// 函数名：CanvasEditorSession.groupSubtreeGeometries(withID:)
func groupSubtreeGeometries(withID groupID: CanvasItemGroupID) -> CanvasGroupSubtreeGeometries {
    let descendantGroupIDs = descendantGroupIDs(withID: groupID)
    let descendantGroupFrames = descendantGroupIDs.compactMap { descendantGroupID in
        groupFrame(withID: descendantGroupID).map { frame in
            CanvasGroupFrameGeometry(
                groupID: descendantGroupID,
                frame: frame
            )
        }
    }

    let subtreeItemIDs = normalizedSubtreeItemIDs(withID: groupID)
    let itemGeometries = subtreeItemIDs.compactMap { itemID in
        scene.boardItem(withID: itemID).map(CanvasBoardItemGeometry.init(item:))
    }

    return CanvasGroupSubtreeGeometries(
        descendantGroupFrames: descendantGroupFrames,
        itemGeometries: itemGeometries
    )
}
```

修改后，新增 `updateGroupFrameAndSubtreeGeometries(...)`，一次性提交当前 group frame、descendant group frames、subtree item geometries。它仍然支持 history/autosave 和 membership reconciliation 参数。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：一次性更新当前 group frame、descendant group frames 和 subtree item geometries。
// 函数名：CanvasEditorSession.updateGroupFrameAndSubtreeGeometries(withID:to:subtreeGeometries:recordHistory:reconcileMembership:)
func updateGroupFrameAndSubtreeGeometries(
    withID groupID: CanvasItemGroupID,
    to frame: CGRect,
    subtreeGeometries: CanvasGroupSubtreeGeometries,
    recordHistory: Bool = false,
    reconcileMembership: Bool = true
) -> Bool {
    guard
        canUpdateGroupFrame(withID: groupID),
        let groupIndex = groups.firstIndex(where: { $0.id == groupID })
    else {
        return false
    }

    let standardizedFrame = frame.standardized
    guard isValidGroupFrame(standardizedFrame) else {
        return false
    }

    let existingItemGeometries = subtreeGeometries.itemGeometries.filter { geometry in
        scene.boardItem(withID: geometry.itemID) != nil
    }
    let didFrameChange = groups[groupIndex].frame != standardizedFrame
    let didItemGeometryChange = existingItemGeometries.contains { geometry in
        guard let item = scene.boardItem(withID: geometry.itemID) else {
            return false
        }

        return CanvasBoardItemGeometry(item: item) != geometry
    }

    // 中间省略 descendant group frame 过滤和更新逻辑；实际实现会校验并更新 descendant group frame。
    // ... existing code ...

    if didFrameChange {
        groups[groupIndex].frame = standardizedFrame
        expandBoardIfNeeded(toInclude: standardizedFrame)
    }
    if reconcileMembership {
        _ = reconcileGroupMembership(forGroupID: groupID)
    }

    return true
}
```

修改后，iOS/macOS 的 drag state 保存 subtree snapshot，而不是 direct member item snapshot。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group drag state 改为保存 subtree geometry 快照。
// 函数名：PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialSubtreeGeometries: CanvasGroupSubtreeGeometries
    let dragStartWorldLocation: CGPoint
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group drag state 改为保存 subtree geometry 快照。
// 函数名：PointerGroupDragState
private struct PointerGroupDragState {
    let groupID: CanvasItemGroupID
    let initialFrame: CGRect
    let initialSubtreeGeometries: CanvasGroupSubtreeGeometries
    let dragStartWorldLocation: CGPoint
}
```

修改后，drag 开始时调用 `groupSubtreeGeometries(withID:)`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group drag 开始时读取整棵子树的 geometry 快照。
// 函数名：iOSViewController.makePointerGroupDragState(groupID:initialViewportLocation:)
return PointerGroupDragState(
    groupID: groupID,
    initialFrame: initialFrame,
    initialSubtreeGeometries: editorSession.groupSubtreeGeometries(withID: groupID),
    dragStartWorldLocation: camera.viewportToWorld(initialViewportLocation)
)
```

修改后，moveGroupFrame 会平移 subtree snapshot，再调用 `updateGroupFrameAndSubtreeGeometries(...)`。resize 路径未改变，仍只更新当前 frame。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：iOS group drag 改为提交平移后的 subtree geometry。
// 函数名：iOSViewController.moveGroupFrame(using:to:)
let proposedSubtreeGeometries = translatedGroupSubtreeGeometries(
    dragState.initialSubtreeGeometries,
    by: translation
)
guard editorSession.updateGroupFrameAndSubtreeGeometries(
    withID: dragState.groupID,
    to: proposedFrame,
    subtreeGeometries: proposedSubtreeGeometries,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：macOS group drag 改为提交平移后的 subtree geometry。
// 函数名：macOSViewController.moveGroupFrame(using:to:)
let proposedSubtreeGeometries = translatedGroupSubtreeGeometries(
    dragState.initialSubtreeGeometries,
    by: translation
)
guard editorSession.updateGroupFrameAndSubtreeGeometries(
    withID: dragState.groupID,
    to: proposedFrame,
    subtreeGeometries: proposedSubtreeGeometries,
    reconcileMembership: false
) else {
    return editorSession.groupFrame(withID: dragState.groupID)
        == proposedFrame.standardized
}
```

测试新增三类阶段4行为：拖动 parent 移动子树、resize parent 不移动 children、拖动 child 不影响 parent/sibling。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证拖动 parent C 时，child group A/B frame 和 subtree item 都跟随移动，sibling 不动。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testUpdateGroupFrameAndSubtreeGeometriesMovesParentChildFramesAndSubtreeItems()
func testUpdateGroupFrameAndSubtreeGeometriesMovesParentChildFramesAndSubtreeItems() throws {
    let fixture = makeGroupHierarchySubtreeMoveFixture()
    let session = fixture.session

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    let translation = CGPoint(x: 18, y: 26)
    let parentSnapshot = session.groupSubtreeGeometries(withID: fixture.parentID)

    XCTAssertTrue(
        session.updateGroupFrameAndSubtreeGeometries(
            withID: fixture.parentID,
            to: fixture.parentFrame.offsetBy(dx: translation.x, dy: translation.y),
            subtreeGeometries: translatedGroupHierarchySubtreeGeometries(
                parentSnapshot,
                by: translation
            ),
            reconcileMembership: false
        )
    )

    XCTAssertEqual(
        session.groupFrame(withID: fixture.childAID),
        fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y)
    )
    XCTAssertEqual(
        try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
        fixture.childAItem.center.translated(by: translation)
    )
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证 resize parent C 只改变 C frame，不移动 A/B frame 或 item。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testUpdateGroupFrameResizeKeepsChildFramesAndItemsInPlace()
func testUpdateGroupFrameResizeKeepsChildFramesAndItemsInPlace() throws {
    let fixture = makeGroupHierarchySubtreeMoveFixture()
    let session = fixture.session

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    XCTAssertTrue(
        session.updateGroupFrame(
            withID: fixture.parentID,
            to: CGRect(x: -20, y: -10, width: 340, height: 190),
            reconcileMembership: false
        )
    )

    XCTAssertEqual(session.groupFrame(withID: fixture.childAID), fixture.childAFrame)
    XCTAssertEqual(
        try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
        fixture.childAItem.center
    )
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证拖动 child A 时，只移动 A 子树，不影响 parent C 或 sibling B。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testUpdateGroupFrameAndSubtreeGeometriesMovesOnlySelectedChildSubtree()
func testUpdateGroupFrameAndSubtreeGeometriesMovesOnlySelectedChildSubtree() throws {
    let fixture = makeGroupHierarchySubtreeMoveFixture()
    let session = fixture.session

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    let translation = CGPoint(x: -12, y: 22)
    let childSnapshot = session.groupSubtreeGeometries(withID: fixture.childAID)

    XCTAssertTrue(
        session.updateGroupFrameAndSubtreeGeometries(
            withID: fixture.childAID,
            to: fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y),
            subtreeGeometries: translatedGroupHierarchySubtreeGeometries(
                childSnapshot,
                by: translation
            ),
            reconcileMembership: false
        )
    )

    XCTAssertEqual(session.groupFrame(withID: fixture.parentID), fixture.parentFrame)
    XCTAssertEqual(session.groupFrame(withID: fixture.childBID), fixture.childBFrame)
}
```

## 验证记录

已执行并通过：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行 group hierarchy 测试，覆盖阶段4 subtree drag/resize 语义。
# 函数名：xcodebuild test -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证阶段4修改不破坏 iOS Debug 构建。
# 函数名：xcodebuild build iOS
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证阶段4修改不破坏 macOS Debug 构建。
# 函数名：xcodebuild build macOS
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

`ReadLints` 对以下文件检查无报错：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`

## 当前状态

本记录创建时，当前 git changes 为：

- modified: `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- modified: `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- modified: `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- modified: `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
- untracked: `commit_records/20260723_164349_group_nesting_phase4_subtree_drag_record.md`

尚未提交。
