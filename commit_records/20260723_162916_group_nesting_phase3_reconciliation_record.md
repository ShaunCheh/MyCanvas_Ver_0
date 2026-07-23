# 20260723_162916_group_nesting_phase3_reconciliation_record

## 记录范围

本记录对应刚刚实施的 `group_nesting_78437533.plan.md` 阶段 3：升级 group frame 的自动归属 reconciliation，使其同时处理直属 item 和直属 child group，并避免 parent group 重复收纳 child group 内的 item。

当前 changes 涉及：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`

## 修改前

修改前，group frame membership reconciliation 只有 item-only 逻辑。创建或更新 group frame 后，只会调用 `reconcileItemMembership(forGroupID:)`，不会自动把 frame 内的其它 group 变成 child group。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前创建带 frame 的 group 后，只刷新 itemIDs，不处理 childGroupIDs。
// 函数名：CanvasEditorSession.appendGroup(...)
groups.append(group)
if let frame {
    expandBoardIfNeeded(toInclude: frame)
    _ = reconcileItemMembership(forGroupID: group.id)
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前更新 group frame 后，只做 item-only membership reconciliation。
// 函数名：CanvasEditorSession.updateGroupFrame(...)
groups[groupIndex].frame = standardizedFrame
expandBoardIfNeeded(toInclude: standardizedFrame)
if reconcileMembership {
    _ = reconcileItemMembership(forGroupID: groupID)
}
```

修改前的 `reconcileItemMembership` 会把 frame 内所有 item 都写入当前 group 的 `itemIDs`。当 parent group C 框住 child group A/B 时，A/B 内 item 也会重复进入 C 的 direct `itemIDs`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前 item membership 只看 item center 是否在当前 group frame 内，不理解 child group subtree。
// 函数名：CanvasEditorSession.reconcileItemMembership(forGroupID:)
func reconcileItemMembership(forGroupID groupID: CanvasItemGroupID) -> Bool {
    guard
        let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
        let rawFrame = groups[groupIndex].frame
    else {
        return false
    }

    let frame = rawFrame.standardized
    guard frame.isNull == false,
          frame.isInfinite == false,
          frame.width > 0,
          frame.height > 0
    else {
        return false
    }

    let memberIDs = scene.orderedBoardItems().compactMap { item -> CanvasItemID? in
        let bounds = item.worldBounds.standardized
        guard bounds.isNull == false,
              bounds.isInfinite == false,
              bounds.width > 0,
              bounds.height > 0
        else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return frame.contains(center) ? item.id : nil
    }

    guard groups[groupIndex].itemIDs != memberIDs else {
        return false
    }

    groups[groupIndex].itemIDs = memberIDs
    return true
}
```

修改前，批量 reconciliation 只是遍历所有有 frame 的 group，并分别调用 item-only reconciliation。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：修改前批量 reconciliation 不会先 normalize group tree，也不会处理 childGroupIDs。
// 函数名：CanvasEditorSession.reconcileFrameGroupMemberships()
func reconcileFrameGroupMemberships() -> Bool {
    let groupIDs = groups.compactMap { group in
        group.frame == nil ? nil : group.id
    }
    var didChange = false
    for groupID in groupIDs {
        didChange = reconcileItemMembership(forGroupID: groupID) || didChange
    }
    return didChange
}
```

## 修改后

修改后，创建和更新 group frame 的入口改为调用 `reconcileGroupMembership(forGroupID:)`，让单个 group 的 reconciliation 同时覆盖 child group 和 direct item。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：创建带 frame 的 group 后，改为执行 group-level membership reconciliation。
// 函数名：CanvasEditorSession.appendGroup(...)
groups.append(group)
if let frame {
    expandBoardIfNeeded(toInclude: frame)
    _ = reconcileGroupMembership(forGroupID: group.id)
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：更新 group frame 后，改为刷新当前 group 的 child group 和 direct item 归属。
// 函数名：CanvasEditorSession.updateGroupFrame(...)
groups[groupIndex].frame = standardizedFrame
expandBoardIfNeeded(toInclude: standardizedFrame)
if reconcileMembership {
    _ = reconcileGroupMembership(forGroupID: groupID)
}
```

修改后，item reconciliation 被拆为 `reconcileDirectItemMembership`。它会先读取当前 group 的 descendant item 集合，并从 direct item 候选中排除这些 item，避免 parent group 重复持有 child group 内 item。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：刷新当前 group 的直属 itemIDs，并排除 descendant group 已持有的 item。
// 函数名：CanvasEditorSession.reconcileDirectItemMembership(forGroupID:)
func reconcileDirectItemMembership(forGroupID groupID: CanvasItemGroupID) -> Bool {
    guard
        let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
        let frame = validGroupFrame(withID: groupID)
    else {
        return false
    }

    let descendantMemberIDs = Set(descendantItemIDs(withID: groupID))
    let memberIDs = scene.orderedBoardItems().compactMap { item -> CanvasItemID? in
        guard descendantMemberIDs.contains(item.id) == false else {
            return nil
        }

        let bounds = item.worldBounds.standardized
        guard bounds.isNull == false,
              bounds.isInfinite == false,
              bounds.width > 0,
              bounds.height > 0
        else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return frame.contains(center) ? item.id : nil
    }

    guard groups[groupIndex].itemIDs != memberIDs else {
        return false
    }

    groups[groupIndex].itemIDs = memberIDs
    return true
}
```

修改后，新增 `reconcileDirectChildGroupMembership` 和 `reconcileGroupMembership`。child group 自动归属基于 group frame center，并通过 `setChildGroups` 复用阶段 2 的单父、无环、normalize 规则。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：刷新当前 group 的直属 childGroupIDs，候选 child 的自动 parent 必须是当前 group。
// 函数名：CanvasEditorSession.reconcileDirectChildGroupMembership(forGroupID:)
func reconcileDirectChildGroupMembership(forGroupID groupID: CanvasItemGroupID) -> Bool {
    guard validGroupFrame(withID: groupID) != nil else {
        return false
    }

    let groupFrameByID = validGroupFramesByID()
    let childGroupIDs = groups.compactMap { group -> CanvasItemGroupID? in
        guard
            group.id != groupID,
            groupFrameByID[group.id] != nil,
            automaticParentGroupID(
                forChildGroupID: group.id,
                groupFrameByID: groupFrameByID
            ) == groupID
        else {
            return nil
        }

        return group.id
    }

    return setChildGroups(forGroupID: groupID, to: childGroupIDs)
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：单个 group 的完整 membership reconciliation：先 child group，再按树顺序刷新 direct item。
// 函数名：CanvasEditorSession.reconcileGroupMembership(forGroupID:)
func reconcileGroupMembership(forGroupID groupID: CanvasItemGroupID) -> Bool {
    guard validGroupFrame(withID: groupID) != nil else {
        return false
    }

    var didChange = false
    didChange = reconcileDirectChildGroupMembership(forGroupID: groupID) || didChange
    didChange = normalizeGroupHierarchy() || didChange
    didChange = reconcileDirectItemMembershipsInTreeOrder(
        groupIDs: [groupID] + descendantGroupIDs(withID: groupID)
    ) || didChange
    didChange = normalizeGroupHierarchy() || didChange
    return didChange
}
```

修改后，批量 reconciliation 改为“先 normalize，再刷新 child group，再按树深度由深到浅刷新 direct item，最后 normalize”。这样 child group 先拿到自己的 direct item，parent 再排除 descendant item。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：批量刷新所有 frame group 的 childGroupIDs 和 itemIDs，并保证 parent 不重复持有 descendant item。
// 函数名：CanvasEditorSession.reconcileFrameGroupMemberships()
func reconcileFrameGroupMemberships() -> Bool {
    var didChange = false
    didChange = normalizeGroupHierarchy() || didChange

    let groupIDs = groups.compactMap { group in
        validGroupFrame(withID: group.id) == nil ? nil : group.id
    }
    for groupID in groupIDs {
        didChange = reconcileDirectChildGroupMembership(forGroupID: groupID) || didChange
    }
    didChange = normalizeGroupHierarchy() || didChange
    didChange = reconcileDirectItemMembershipsInTreeOrder(groupIDs: groupIDs) || didChange
    didChange = normalizeGroupHierarchy() || didChange
    return didChange
}
```

修改后，新增自动 parent 判断。除了 “child frame center 在 parent frame 内”，还要求 parent frame 面积大于 child frame，避免大 group 的中心刚好落在小 group 内时，小 group 被误判为大 group 的 parent。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 功能注释：根据 frame 几何选择自动 parent，优先选择包含 child center 的最小有效 parent frame。
// 函数名：CanvasEditorSession.automaticParentGroupID(forChildGroupID:groupFrameByID:)
private func automaticParentGroupID(
    forChildGroupID childGroupID: CanvasItemGroupID,
    groupFrameByID: [CanvasItemGroupID: CGRect]
) -> CanvasItemGroupID? {
    guard let childFrame = groupFrameByID[childGroupID] else {
        return nil
    }

    let childCenter = CGPoint(x: childFrame.midX, y: childFrame.midY)
    let childFrameArea = childFrame.width * childFrame.height
    let descendantGroupIDsByGroup = normalizedDescendantGroupIDSetByGroup()
    let groupOrderByID = Dictionary(
        uniqueKeysWithValues: groups.enumerated().map { offset, group in
            (group.id, offset)
        }
    )

    return groups.compactMap { group -> (groupID: CanvasItemGroupID, area: CGFloat, order: Int)? in
        guard
            group.id != childGroupID,
            let parentFrame = groupFrameByID[group.id],
            parentFrame.contains(childCenter),
            parentFrame.width * parentFrame.height > childFrameArea,
            descendantGroupIDsByGroup[childGroupID, default: []].contains(group.id) == false
        else {
            return nil
        }

        return (
            groupID: group.id,
            area: parentFrame.width * parentFrame.height,
            order: groupOrderByID[group.id] ?? Int.max
        )
    }
    .sorted { lhs, rhs in
        if lhs.area == rhs.area {
            return lhs.order < rhs.order
        }
        return lhs.area < rhs.area
    }
    .first?
    .groupID
}
```

修改后，测试新增阶段 3 重点场景：C 框住 A/B、A/B 内 item 不重复出现在 C、A 移出 C 后解除 child 关系。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证 parent frame C 框住 child frame A/B 后，C.childGroupIDs 会包含 A/B。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testReconcileFrameGroupMembershipsAddsContainedGroupsAsDirectChildren()
func testReconcileFrameGroupMembershipsAddsContainedGroupsAsDirectChildren() {
    let childAID = CanvasItemGroupID()
    let childBID = CanvasItemGroupID()
    let parentID = CanvasItemGroupID()
    let session = makeGroupHierarchyTestSession()
    session.groups = [
        CanvasItemGroup(
            id: childAID,
            title: "A",
            itemIDs: [],
            frame: CGRect(x: 20, y: 20, width: 80, height: 60)
        ),
        CanvasItemGroup(
            id: childBID,
            title: "B",
            itemIDs: [],
            frame: CGRect(x: 140, y: 40, width: 80, height: 60)
        ),
        CanvasItemGroup(
            id: parentID,
            title: "C",
            itemIDs: [],
            frame: CGRect(x: 0, y: 0, width: 260, height: 140)
        )
    ]

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [childAID, childBID])
    XCTAssertEqual(session.parentGroupID(for: childAID), parentID)
    XCTAssertEqual(session.parentGroupID(for: childBID), parentID)
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证 parent group 的 direct itemIDs 不会重复包含 child group 内 item。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testReconcileFrameGroupMembershipsDoesNotDuplicateChildItemsInParent()
func testReconcileFrameGroupMembershipsDoesNotDuplicateChildItemsInParent() {
    let childAID = CanvasItemGroupID()
    let childBID = CanvasItemGroupID()
    let parentID = CanvasItemGroupID()
    let childAItem = makeGroupHierarchyTextItem(
        text: "inside A",
        center: CGPoint(x: 60, y: 50)
    )
    let childBItem = makeGroupHierarchyTextItem(
        text: "inside B",
        center: CGPoint(x: 180, y: 70)
    )
    let parentDirectItem = makeGroupHierarchyTextItem(
        text: "direct C",
        center: CGPoint(x: 240, y: 80)
    )
    let session = makeGroupHierarchyTestSession()
    session.scene.append(childAItem)
    session.scene.append(childBItem)
    session.scene.append(parentDirectItem)
    session.groups = [
        CanvasItemGroup(
            id: childAID,
            title: "A",
            itemIDs: [],
            frame: CGRect(x: 20, y: 20, width: 80, height: 60)
        ),
        CanvasItemGroup(
            id: childBID,
            title: "B",
            itemIDs: [],
            frame: CGRect(x: 140, y: 40, width: 80, height: 60)
        ),
        CanvasItemGroup(
            id: parentID,
            title: "C",
            itemIDs: [],
            frame: CGRect(x: 0, y: 0, width: 280, height: 140)
        )
    ]

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    XCTAssertEqual(session.directItemIDs(withID: childAID), [childAItem.id])
    XCTAssertEqual(session.directItemIDs(withID: childBID), [childBItem.id])
    XCTAssertEqual(session.directItemIDs(withID: parentID), [parentDirectItem.id])
    XCTAssertEqual(session.descendantItemIDs(withID: parentID), [childAItem.id, childBItem.id])
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift
// 功能注释：验证 child group frame 移出 parent frame 后，会从 parent.childGroupIDs 中移除。
// 函数名：CanvasEditorSessionGroupHierarchyTests.testReconcileFrameGroupMembershipsRemovesChildGroupMovedOutsideParent()
func testReconcileFrameGroupMembershipsRemovesChildGroupMovedOutsideParent() {
    let childID = CanvasItemGroupID()
    let parentID = CanvasItemGroupID()
    let session = makeGroupHierarchyTestSession()
    session.groups = [
        CanvasItemGroup(
            id: childID,
            title: "A",
            itemIDs: [],
            frame: CGRect(x: 360, y: 20, width: 80, height: 60)
        ),
        CanvasItemGroup(
            id: parentID,
            title: "C",
            itemIDs: [],
            childGroupIDs: [childID],
            frame: CGRect(x: 0, y: 0, width: 260, height: 140)
        )
    ]

    XCTAssertTrue(session.reconcileFrameGroupMemberships())

    XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [])
    XCTAssertNil(session.parentGroupID(for: childID))
}
```

## 验证记录

已执行并通过：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：运行 group hierarchy 测试，覆盖阶段 2 与阶段 3 的 tree/reconciliation 行为。
# 函数名：xcodebuild test -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证阶段 3 修改不破坏 iOS Debug 构建。
# 函数名：xcodebuild build iOS
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证阶段 3 修改不破坏 macOS Debug 构建。
# 函数名：xcodebuild build macOS
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

`ReadLints` 对以下文件检查无报错：

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`

## 当前状态

本记录创建时，当前 git changes 为：

- modified: `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- modified: `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
- untracked: `commit_records/20260723_162916_group_nesting_phase3_reconciliation_record.md`

尚未提交。
