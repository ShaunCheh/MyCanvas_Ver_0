# 20260723_184737_group_nesting_phase8_cache_cleanup_record

## 背景

本次记录对应 group nesting 阶段8：清理临时调试日志，并为 group nesting 的 tree normalization / reconciliation 增加性能保护。

阶段8前，嵌套 group 的功能已完成，但 `CanvasEditorSession` 中多个路径会重复构建 parent map、child map、descendant cache：

- `directChildGroupIDs` / `parentGroupID` / `descendantGroupIDs` 分别重新构造 map。
- `automaticParentGroupID(...)` 在每个 child 判断时重新构建 descendant set 和 order map。
- `reconcileDirectItemMembershipsInTreeOrder(...)` 对每个 group 排序时重复沿 parent map 计算 depth。
- `groupSubtreeGeometries(...)` 会分别调用 descendant group 和 descendant item 逻辑，重复构建 tree。

## 修改 1：新增 normalized group hierarchy cache

修改前，child map、parent map、descendant set 各自分散构建。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - normalizedChildGroupIDsByParent()
private func normalizedChildGroupIDsByParent() -> [CanvasItemGroupID: [CanvasItemGroupID]] {
    let existingGroupIDs = Set(groups.map(\.id))
    var parentGroupIDsByChild: [CanvasItemGroupID: CanvasItemGroupID] = [:]
    var childGroupIDsByParent: [CanvasItemGroupID: [CanvasItemGroupID]] =
        Dictionary(uniqueKeysWithValues: groups.map { ($0.id, [CanvasItemGroupID]()) })

    for group in groups {
        var seenChildGroupIDs = Set<CanvasItemGroupID>()
        for childGroupID in group.childGroupIDs {
            guard
                existingGroupIDs.contains(childGroupID),
                childGroupID != group.id,
                seenChildGroupIDs.insert(childGroupID).inserted,
                parentGroupIDsByChild[childGroupID] == nil,
                wouldCreateGroupHierarchyCycle(
                    parentGroupID: group.id,
                    childGroupID: childGroupID,
                    parentGroupIDsByChild: parentGroupIDsByChild
                ) == false
            else {
                continue
            }

            parentGroupIDsByChild[childGroupID] = group.id
            childGroupIDsByParent[group.id, default: []].append(childGroupID)
        }
    }

    return childGroupIDsByParent
}
```

修改后，新增 `NormalizedGroupHierarchyCache`，一次性构建 `existingGroupIDs`、`childGroupIDsByParent`、`parentGroupIDsByChild`、ordered descendants、descendant sets、depth 和 original order。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - NormalizedGroupHierarchyCache / makeNormalizedGroupHierarchyCache()
private struct NormalizedGroupHierarchyCache {
    let existingGroupIDs: Set<CanvasItemGroupID>
    let childGroupIDsByParent: [CanvasItemGroupID: [CanvasItemGroupID]]
    let parentGroupIDsByChild: [CanvasItemGroupID: CanvasItemGroupID]
    let descendantGroupIDsByGroup: [CanvasItemGroupID: [CanvasItemGroupID]]
    let descendantGroupIDSetsByGroup: [CanvasItemGroupID: Set<CanvasItemGroupID>]
    let depthByGroupID: [CanvasItemGroupID: Int]
    let orderByGroupID: [CanvasItemGroupID: Int]
}

private func makeNormalizedGroupHierarchyCache() -> NormalizedGroupHierarchyCache {
    var existingGroupIDs = Set<CanvasItemGroupID>()
    var orderByGroupID: [CanvasItemGroupID: Int] = [:]
    var childGroupIDsByParent: [CanvasItemGroupID: [CanvasItemGroupID]] = [:]
    for (offset, group) in groups.enumerated() {
        existingGroupIDs.insert(group.id)
        if orderByGroupID[group.id] == nil {
            orderByGroupID[group.id] = offset
        }
        if childGroupIDsByParent[group.id] == nil {
            childGroupIDsByParent[group.id] = []
        }
    }

    // 后续在同一 cache 构建中继续生成 parent map、descendant cache 和 depth cache。
}
```

## 修改 2：查询 API 复用 cache

修改前，查询函数分别调用不同 normalized helper。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - group hierarchy query APIs
func directChildGroupIDs(withID groupID: CanvasItemGroupID) -> [CanvasItemGroupID] {
    normalizedChildGroupIDsByParent()[groupID] ?? []
}

func parentGroupID(for groupID: CanvasItemGroupID) -> CanvasItemGroupID? {
    normalizedParentGroupIDsByChild()[groupID]
}

func descendantGroupIDs(withID groupID: CanvasItemGroupID) -> [CanvasItemGroupID] {
    let childrenByParent = normalizedChildGroupIDsByParent()
    var descendants: [CanvasItemGroupID] = []
    // 递归 visit children...
    return descendants
}
```

修改后，查询入口统一从 `makeNormalizedGroupHierarchyCache()` 获取结果。`descendantItemIDs` 也增加了带 cache 的私有重载。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - group hierarchy query APIs
func directChildGroupIDs(withID groupID: CanvasItemGroupID) -> [CanvasItemGroupID] {
    makeNormalizedGroupHierarchyCache().childGroupIDsByParent[groupID] ?? []
}

func parentGroupID(for groupID: CanvasItemGroupID) -> CanvasItemGroupID? {
    makeNormalizedGroupHierarchyCache().parentGroupIDsByChild[groupID]
}

func descendantGroupIDs(withID groupID: CanvasItemGroupID) -> [CanvasItemGroupID] {
    let hierarchyCache = makeNormalizedGroupHierarchyCache()
    guard hierarchyCache.existingGroupIDs.contains(groupID) else {
        return []
    }

    return hierarchyCache.descendantGroupIDsByGroup[groupID] ?? []
}
```

## 修改 3：子树几何与 item membership 复用同一 cache

修改前，`groupSubtreeGeometries(...)` 会先调用 `descendantGroupIDs(...)`，再调用 `normalizedSubtreeItemIDs(...)`，两者都会重新派生 tree。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - groupSubtreeGeometries(withID:)
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
    // ...
}
```

修改后，`groupSubtreeGeometries(...)` 只构建一次 hierarchy cache，并传给 `normalizedSubtreeItemIDs(...)`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - groupSubtreeGeometries(withID:)
func groupSubtreeGeometries(withID groupID: CanvasItemGroupID) -> CanvasGroupSubtreeGeometries {
    let hierarchyCache = makeNormalizedGroupHierarchyCache()
    let descendantGroupIDs = hierarchyCache.descendantGroupIDsByGroup[groupID] ?? []
    let descendantGroupFrames = descendantGroupIDs.compactMap { descendantGroupID in
        groupFrame(withID: descendantGroupID).map { frame in
            CanvasGroupFrameGeometry(
                groupID: descendantGroupID,
                frame: frame
            )
        }
    }

    let subtreeItemIDs = normalizedSubtreeItemIDs(
        withID: groupID,
        hierarchyCache: hierarchyCache
    )
    // ...
}
```

## 修改 4：reconciliation 复用 parent map / descendant cache / depth cache

修改前，`automaticParentGroupID(...)` 每次调用都会重新构建 descendant set 和 order map。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - automaticParentGroupID(forChildGroupID:groupFrameByID:)
private func automaticParentGroupID(
    forChildGroupID childGroupID: CanvasItemGroupID,
    groupFrameByID: [CanvasItemGroupID: CGRect]
) -> CanvasItemGroupID? {
    let descendantGroupIDsByGroup = normalizedDescendantGroupIDSetByGroup()
    let groupOrderByID = Dictionary(
        uniqueKeysWithValues: groups.enumerated().map { offset, group in
            (group.id, offset)
        }
    )

    // 逐个候选 parent 判断...
}
```

修改后，`automaticParentGroupID(...)` 接收 `hierarchyCache`，复用 descendant set 和 group order。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - automaticParentGroupID(forChildGroupID:groupFrameByID:hierarchyCache:)
private func automaticParentGroupID(
    forChildGroupID childGroupID: CanvasItemGroupID,
    groupFrameByID: [CanvasItemGroupID: CGRect],
    hierarchyCache: NormalizedGroupHierarchyCache
) -> CanvasItemGroupID? {
    // ...
    guard
        group.id != childGroupID,
        let parentFrame = groupFrameByID[group.id],
        parentFrame.contains(childCenter),
        parentFrame.width * parentFrame.height > childFrameArea,
        hierarchyCache.descendantGroupIDSetsByGroup[childGroupID, default: []]
            .contains(group.id) == false
    else {
        return nil
    }

    return (
        groupID: group.id,
        area: parentFrame.width * parentFrame.height,
        order: hierarchyCache.orderByGroupID[group.id] ?? Int.max
    )
}
```

`reconcileDirectItemMembershipsInTreeOrder(...)` 也不再每次排序时沿 parent chain 计算 depth，而是使用 cache 中的 `depthByGroupID`。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - reconcileDirectItemMembershipsInTreeOrder(groupIDs:hierarchyCache:)
private func reconcileDirectItemMembershipsInTreeOrder(
    groupIDs: [CanvasItemGroupID],
    hierarchyCache: NormalizedGroupHierarchyCache
) -> Bool {
    let sortedGroupIDs = uniqueGroupIDs.sorted { lhs, rhs in
        let lhsDepth = hierarchyCache.depthByGroupID[lhs] ?? 0
        let rhsDepth = hierarchyCache.depthByGroupID[rhs] ?? 0
        if lhsDepth == rhsDepth {
            return (originalOrderByID[lhs] ?? Int.max) < (originalOrderByID[rhs] ?? Int.max)
        }
        return lhsDepth > rhsDepth
    }

    var didChange = false
    for groupID in sortedGroupIDs {
        didChange = reconcileDirectItemMembership(
            forGroupID: groupID,
            hierarchyCache: hierarchyCache
        ) || didChange
    }
    return didChange
}
```

## 修改 5：清理 macOS group title edit 临时日志

修改前，`macOSGroupTitleEditTrace(...)` 会输出大量 focus / commit / render 调试日志。这是之前定位 macOS inline edit focus 问题时添加的临时日志。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSGroupTitleEditTrace(...)
private func macOSGroupTitleEditTrace(
    _ phase: String,
    groupID: CanvasItemGroupID? = nil,
    editingGroupTitleID: CanvasItemGroupID? = nil,
    title: String? = nil,
    firstResponder: NSResponder? = nil,
    detail: String? = nil
) {
    print(
        "[Canvas macOS][GroupTitleEdit] " +
        "phase=\(phase) " +
        "groupID=\(groupIDDescription) " +
        "editingGroupTitleID=\(editingGroupIDDescription) " +
        "title=\(titleDescription) " +
        "firstResponder=\(responderDescription) " +
        "detail=\(detailDescription)"
    )
}
```

修改后，保留 no-op hook，避免修改大量调用点引入交互风险，同时确保正常使用不再输出这些临时日志。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSGroupTitleEditTrace(...)
private func macOSGroupTitleEditTrace(
    _ phase: String,
    groupID: CanvasItemGroupID? = nil,
    editingGroupTitleID: CanvasItemGroupID? = nil,
    title: String? = nil,
    firstResponder: NSResponder? = nil,
    detail: String? = nil
) {
    // Intentionally kept as a no-op hook: the verbose focus trace was useful
    // for diagnosing inline title editing, but should not log during normal use.
}
```

## 修改 6：补充深层 group tree 回归测试

新增 64 层链式嵌套测试，验证 cache 化后：

- direct child 查询稳定。
- descendants 顺序稳定。
- parent 查询稳定。
- cycle guard 仍然拒绝把 leaf 指回 root。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testDeepGroupHierarchyQueriesStayStableAfterCacheNormalization()
let session = makeGroupHierarchyTestSession()
let groupIDs = (0..<64).map { _ in CanvasItemGroupID() }
session.groups = groupIDs.enumerated().map { offset, groupID in
    CanvasItemGroup(
        id: groupID,
        title: "group \(offset)",
        itemIDs: [],
        childGroupIDs: offset + 1 < groupIDs.count
            ? [groupIDs[offset + 1]]
            : []
    )
}

XCTAssertEqual(
    session.directChildGroupIDs(withID: groupIDs[0]),
    [groupIDs[1]]
)
XCTAssertEqual(
    session.descendantGroupIDs(withID: groupIDs[0]),
    Array(groupIDs.dropFirst())
)
XCTAssertFalse(
    session.setChildGroups(
        forGroupID: groupIDs[groupIDs.count - 1],
        to: [groupIDs[0]]
    )
)
```

## 验证

已执行并通过：

- `ReadLints`：无 linter errors。
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS'`

## 当前变更文件

- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
