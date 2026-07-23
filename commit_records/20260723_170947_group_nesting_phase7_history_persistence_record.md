# 20260723_170947_group_nesting_phase7_history_persistence_record

## 背景

本次记录对应 group nesting 阶段7：验证嵌套 group 的 history、autosave 触发路径和文档保存/恢复一致性。

本阶段没有修改业务实现代码。检查现有实现后确认：

- `BoardHistorySnapshot` 已包含 `groups`。
- `CanvasItemGroup` 已包含 `childGroupIDs`。
- `BoardDocumentMapper` 已双向映射 `childGroupIDs`。
- group frame drag/resize 通过 history transaction 或 immediate history snapshot 保存完整 document state。

因此本次主要补充回归测试，锁住阶段7计划中的四类行为。

## 修改 1：补充自动嵌套归属 undo/redo 测试

修改前，已有测试覆盖自动把框内 group 归为 child，但没有覆盖该变化进入 history 后的 undo/redo。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - existing reconciliation tests before phase 7
XCTAssertTrue(session.reconcileFrameGroupMemberships())
XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [childID])
XCTAssertEqual(session.parentGroupID(for: childID), parentID)
```

修改后，新增 `testUndoRedoRestoresAutomaticChildGroupMembershipTransaction()`。测试用 pending history transaction 包住 `updateGroupFrame(...)`，让 parent frame 移动到能框住 A/B 的位置，确认自动 child membership 可 undo/redo。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testUndoRedoRestoresAutomaticChildGroupMembershipTransaction()
session.beginHistoryTransaction(reason: "test automatic group membership")
XCTAssertTrue(
    session.updateGroupFrame(
        withID: parentID,
        to: CGRect(x: 0, y: 0, width: 260, height: 140)
    )
)
XCTAssertTrue(session.commitPendingHistoryTransaction())
XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [childAID, childBID])

XCTAssertTrue(applyGroupHierarchyUndo(in: session))
XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [])
XCTAssertNil(session.parentGroupID(for: childAID))
XCTAssertNil(session.parentGroupID(for: childBID))

XCTAssertTrue(applyGroupHierarchyRedo(in: session))
XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [childAID, childBID])
XCTAssertEqual(session.parentGroupID(for: childAID), parentID)
XCTAssertEqual(session.parentGroupID(for: childBID), parentID)
```

## 修改 2：补充 parent group 子树拖动 undo/redo 测试

修改前，已有测试验证直接调用 `updateGroupFrameAndSubtreeGeometries(...)` 会移动 parent、child frames 和 descendant items，但没有验证该操作进入 history transaction 后可恢复。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testUpdateGroupFrameAndSubtreeGeometriesMovesParentChildFramesAndSubtreeItems()
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
```

修改后，新增 `testUndoRedoRestoresParentSubtreeDragTransaction()`，用 `beginHistoryTransaction(...)` / `commitPendingHistoryTransaction()` 模拟真实拖动提交，确认 undo/redo 能恢复 parent frame、child frames、descendant items。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testUndoRedoRestoresParentSubtreeDragTransaction()
session.beginHistoryTransaction(reason: "test move group subtree")
XCTAssertTrue(
    session.updateGroupFrameAndSubtreeGeometries(
        withID: fixture.parentID,
        to: movedParentFrame,
        subtreeGeometries: movedSubtreeGeometries,
        reconcileMembership: false
    )
)
XCTAssertTrue(session.commitPendingHistoryTransaction())
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), movedParentFrame)
try assertGroupHierarchySubtreeMoveFixture(
    fixture,
    translation: translation
)

XCTAssertTrue(applyGroupHierarchyUndo(in: session))
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), fixture.parentFrame)
try assertGroupHierarchySubtreeMoveFixture(fixture, translation: .zero)

XCTAssertTrue(applyGroupHierarchyRedo(in: session))
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), movedParentFrame)
try assertGroupHierarchySubtreeMoveFixture(
    fixture,
    translation: translation
)
```

## 修改 3：补充 parent resize undo/redo 测试

修改前，已有测试验证 resize parent frame 不移动 child frames/items，但没有覆盖 undo/redo。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testUpdateGroupFrameResizeKeepsChildFramesAndItemsInPlace()
XCTAssertTrue(
    session.updateGroupFrame(
        withID: fixture.parentID,
        to: CGRect(x: -20, y: -10, width: 340, height: 190),
        reconcileMembership: false
    )
)
XCTAssertEqual(session.groupFrame(withID: fixture.childAID), fixture.childAFrame)
XCTAssertEqual(session.groupFrame(withID: fixture.childBID), fixture.childBFrame)
```

修改后，新增 `testUndoRedoRestoresParentResizeWithoutMovingChildSubtree()`，确认 undo/redo 只影响 parent frame，child frames 与 items 均保持世界坐标不变。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testUndoRedoRestoresParentResizeWithoutMovingChildSubtree()
let resizedParentFrame = CGRect(x: -20, y: -10, width: 340, height: 190)
session.beginHistoryTransaction(reason: "test resize group frame")
XCTAssertTrue(
    session.updateGroupFrame(
        withID: fixture.parentID,
        to: resizedParentFrame,
        reconcileMembership: false
    )
)
XCTAssertTrue(session.commitPendingHistoryTransaction())
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), resizedParentFrame)
try assertGroupHierarchySubtreeMoveFixture(fixture, translation: .zero)

XCTAssertTrue(applyGroupHierarchyUndo(in: session))
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), fixture.parentFrame)
try assertGroupHierarchySubtreeMoveFixture(fixture, translation: .zero)

XCTAssertTrue(applyGroupHierarchyRedo(in: session))
XCTAssertEqual(session.groupFrame(withID: fixture.parentID), resizedParentFrame)
try assertGroupHierarchySubtreeMoveFixture(fixture, translation: .zero)
```

## 修改 4：补充历史测试 helper

新增 fixture 和断言 helper，减少重复断言，并明确 undo/redo 测试只应用 history snapshot，不通过 UI command executor。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - applyGroupHierarchyUndo(in:) / applyGroupHierarchyRedo(in:)
private func applyGroupHierarchyUndo(
    in session: CanvasEditorSession
) -> Bool {
    guard let snapshot = session.undoHistorySnapshot() else {
        return false
    }

    session.applyBoardHistorySnapshot(snapshot)
    return true
}

private func applyGroupHierarchyRedo(
    in session: CanvasEditorSession
) -> Bool {
    guard let snapshot = session.redoHistorySnapshot() else {
        return false
    }

    session.applyBoardHistorySnapshot(snapshot)
    return true
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - assertGroupHierarchySubtreeMoveFixture(_:translation:file:line:)
private func assertGroupHierarchySubtreeMoveFixture(
    _ fixture: GroupHierarchySubtreeMoveFixture,
    translation: CGPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let session = fixture.session
    XCTAssertEqual(
        session.groupFrame(withID: fixture.childAID),
        fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y),
        file: file,
        line: line
    )
    XCTAssertEqual(
        try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
        fixture.childAItem.center.translated(by: translation),
        file: file,
        line: line
    )
}
```

## 修改 5：补充 BoardDocumentMapper 多级 group tree 持久化测试

修改前，已有 mapper 测试覆盖单层 child group round trip。

```swift
// MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift - testBoardDocumentMapperRoundTripsCanvasItemGroups()
runtimeState.groups = [
    CanvasItemGroup(
        id: groupID,
        title: "Question Evidence",
        description: "Image answers the markdown question.",
        itemIDs: [itemID],
        childGroupIDs: [childGroupID, childGroupID],
        frame: groupFrame
    ),
    CanvasItemGroup(
        id: childGroupID,
        title: "Detail Evidence",
        description: "Nested supporting group.",
        itemIDs: [],
        frame: childGroupFrame
    )
]
```

修改后，新增 `testBoardDocumentMapperRoundTripsNestedGroupTreeStructure()`，覆盖 root -> child -> grandchild 的多级 tree structure 保存和恢复。

```swift
// MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift - testBoardDocumentMapperRoundTripsNestedGroupTreeStructure()
runtimeState.groups = [
    CanvasItemGroup(
        id: rootID,
        title: "Root",
        itemIDs: [],
        childGroupIDs: [childID],
        frame: CGRect(x: 0, y: 0, width: 360, height: 240)
    ),
    CanvasItemGroup(
        id: childID,
        title: "Child",
        itemIDs: [],
        childGroupIDs: [grandchildID],
        frame: CGRect(x: 40, y: 40, width: 180, height: 120)
    ),
    CanvasItemGroup(
        id: grandchildID,
        title: "Grandchild",
        itemIDs: [],
        frame: CGRect(x: 70, y: 70, width: 80, height: 60)
    )
]

let document = BoardDocumentMapper.makeDocument(from: runtimeState)
let restoredRuntimeState = try BoardDocumentMapper.makeRuntimeState(
    from: document,
    imageLoader: { _ in
        throw NSError(
            domain: "BoardDocumentMapperGroupTreeTest",
            code: 1
        )
    }
)

XCTAssertEqual(
    restoredRuntimeState.groups.first(where: { $0.id == rootID })?.childGroupIDs,
    [childID]
)
XCTAssertEqual(
    restoredRuntimeState.groups.first(where: { $0.id == childID })?.childGroupIDs,
    [grandchildID]
)
```

## 验证过程

首次运行新增测试时，三个 history 测试因为测试中直接使用 `CanvasCommandExecutor(session:).execute(.undo/.redo)` 触发了测试环境下的 crash。修正为直接使用 `undoHistorySnapshot()` / `redoHistorySnapshot()` 并调用 `applyBoardHistorySnapshot(_:)` 后，测试通过。业务实现未因此修改。

已执行并通过：

- `ReadLints`：无 linter errors。
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests/testBoardDocumentMapperRoundTripsNestedGroupTreeStructure`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS'`

## 当前变更文件

- `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
