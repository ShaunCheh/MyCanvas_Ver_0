# 20260723_165523_group_nesting_phase5_render_hit_list_record

## 背景

本次记录对应 group nesting 阶段5：让嵌套 group 在画布渲染、hit test、group list 中按树结构工作。

阶段5前，group 已经具备 `childGroupIDs`、自动嵌套归属、子树拖拽等能力，但展示层仍主要按扁平 `groups` 数组处理：

- group frame 渲染顺序直接取 `groups` 原始顺序。
- group frame 图层刷新不会主动重排已有 layer。
- group list 按扁平列表展示，不体现 parent / child 层级。
- hit test 依赖 `renderSnapshot.groups.reversed()`，但如果 snapshot 本身不是 parent-before-child 顺序，child 不一定优先。

## 修改 1：新增共享 group 树形派生

修改前，`CanvasItemGroup` 后面直接进入 `BoardDocument`，没有一个展示层可复用的 tree rows / depth / render order 派生工具。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - CanvasItemGroup / BoardDocument 边界
struct CanvasItemGroup: Equatable, Hashable, Sendable {
    // ... group model，包含 itemIDs、childGroupIDs、frame
}

struct BoardDocument: Codable {
    // ... storage document model
}
```

修改后，在 model 附近新增 `CanvasGroupHierarchyRow` 和 `CanvasGroupHierarchy`。这个 helper 会基于 `childGroupIDs` 生成 normalized tree rows，并做基础防护：忽略不存在 child、self child、重复 child、多 parent、会形成 cycle 的 child 引用。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - CanvasGroupHierarchy.rows(from:)
struct CanvasGroupHierarchyRow: Equatable {
    let group: CanvasItemGroup
    let depth: Int
}

enum CanvasGroupHierarchy {
    static func rows(from groups: [CanvasItemGroup]) -> [CanvasGroupHierarchyRow] {
        let tree = normalizedTree(from: groups)
        var rows: [CanvasGroupHierarchyRow] = []
        var visitedGroupIDs = Set<CanvasItemGroupID>()

        func appendRows(
            from groupID: CanvasItemGroupID,
            depth: Int
        ) {
            guard
                visitedGroupIDs.insert(groupID).inserted,
                let group = tree.groupByID[groupID]
            else {
                return
            }

            rows.append(
                CanvasGroupHierarchyRow(
                    group: group,
                    depth: depth
                )
            )

            for childGroupID in tree.childGroupIDsByParent[groupID] ?? [] {
                appendRows(from: childGroupID, depth: depth + 1)
            }
        }

        for group in groups where tree.parentGroupIDByChild[group.id] == nil {
            appendRows(from: group.id, depth: 0)
        }

        for group in groups where visitedGroupIDs.contains(group.id) == false {
            appendRows(from: group.id, depth: 0)
        }

        return rows
    }
}
```

`renderOrderedGroups(from:)` 直接复用 rows，保证渲染层拿到 parent-before-child 顺序。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - CanvasGroupHierarchy.renderOrderedGroups(from:)
static func renderOrderedGroups(
    from groups: [CanvasItemGroup]
) -> [CanvasItemGroup] {
    rows(from: groups).map(\.group)
}
```

## 修改 2：renderer 输出 parent-before-child group frame

修改前，renderer 按 `groups` 原始数组顺序生成 `CanvasGroupRenderItem`。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift - CanvasRenderer.makeSnapshot(...)
let renderGroups = groups.compactMap { group in
    makeGroupRenderItem(
        for: group,
        visibleWorldRect: visibleWorldRect,
        camera: camera
    )
}
```

修改后，renderer 使用 `CanvasGroupHierarchy.renderOrderedGroups(from:)`。这样 parent frame 会先进入 snapshot，child frame 后进入 snapshot；已有 `CanvasContextResolver` 对 group frame 使用 reversed hit test，因此 child 会优先命中。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift - CanvasRenderer.makeSnapshot(...)
let renderGroups = CanvasGroupHierarchy.renderOrderedGroups(from: groups).compactMap { group in
    makeGroupRenderItem(
        for: group,
        visibleWorldRect: visibleWorldRect,
        camera: camera
    )
}
```

## 修改 3：iOS/macOS group frame layer 按 snapshot 顺序重排

修改前，viewport 刷新 group frame 时只更新 layer 几何；如果 layer 已存在，`groupFrameLayer(for:)` 会直接返回旧 layer，不保证 sublayer 顺序与最新 snapshot 顺序一致。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift - refreshGroupFrameLayers()
for group in snapshot.groups {
    let layer = groupFrameLayer(for: group.id)
    layer.frame = group.screenFrame
    layer.path = CGPath(
        roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
        cornerWidth: Self.groupFrameCornerRadius,
        cornerHeight: Self.groupFrameCornerRadius,
        transform: nil
    )
}
```

修改后，iOS 每次按 `snapshot.groups` 顺序移除并重新添加 layer，让 parent layer 在下、child layer 在上。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift - refreshGroupFrameLayers()
for group in snapshot.groups {
    let layer = groupFrameLayer(for: group.id)
    layer.removeFromSuperlayer()
    groupFramesLayer.addSublayer(layer)
    layer.frame = group.screenFrame
    layer.path = CGPath(
        roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
        cornerWidth: Self.groupFrameCornerRadius,
        cornerHeight: Self.groupFrameCornerRadius,
        transform: nil
    )
}
```

macOS 同步使用相同策略。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift - refreshGroupFrameLayers()
for group in snapshot.groups {
    let layer = groupFrameLayer(for: group.id)
    layer.removeFromSuperlayer()
    groupFramesLayer.addSublayer(layer)
    layer.frame = group.screenFrame
    layer.path = CGPath(
        roundedRect: CGRect(origin: .zero, size: group.screenFrame.size),
        cornerWidth: Self.groupFrameCornerRadius,
        cornerHeight: Self.groupFrameCornerRadius,
        transform: nil
    )
}
```

## 修改 4：group list 改为树形 rows 并缩进 child

修改前，iOS group list 直接遍历扁平 `groups`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - iOSCanvasGroupListView.render(groups:editingGroupTitleID:)
for group in groups {
    let isEditingTitle = group.id == editingGroupTitleID
    stackView.addArrangedSubview(
        makeGroupRow(
            for: group,
            isEditingTitle: isEditingTitle,
            focusedTitleTextField: &focusedTitleTextField
        )
    )
}
```

修改后，iOS 使用 `CanvasGroupHierarchy.rows(from:)`，并把 `row.depth` 传入 row 构造函数。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - iOSCanvasGroupListView.render(groups:editingGroupTitleID:)
for row in CanvasGroupHierarchy.rows(from: groups) {
    let group = row.group
    let isEditingTitle = group.id == editingGroupTitleID
    stackView.addArrangedSubview(
        makeGroupRow(
            for: group,
            depth: row.depth,
            isEditingTitle: isEditingTitle,
            focusedTitleTextField: &focusedTitleTextField
        )
    )
}
```

iOS row 使用 depth 计算左缩进，保留原有 edit button、row tap navigation、inline title edit 逻辑。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - iOSCanvasGroupListView.makeGroupRow(...)
let leadingIndent = 10 + CGFloat(max(depth, 0)) * 18
NSLayoutConstraint.activate([
    outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
    outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingIndent),
    outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
    outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    editButton.widthAnchor.constraint(equalToConstant: 32),
    editButton.heightAnchor.constraint(equalToConstant: 32)
])
```

macOS group list 做同样调整。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
for row in CanvasGroupHierarchy.rows(from: groups) {
    let group = row.group
    stackView.addArrangedSubview(
        makeGroupRow(
            for: group,
            depth: row.depth,
            isEditingTitle: group.id == editingGroupTitleID,
            focusedTitleTextField: &focusedTitleTextField
        )
    )
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSCanvasGroupListView.makeGroupRow(...)
let leadingIndent = 10 + CGFloat(max(depth, 0)) * 18
NSLayoutConstraint.activate([
    outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
    outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leadingIndent),
    outerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
    outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
    editButton.widthAnchor.constraint(equalToConstant: 32),
    editButton.heightAnchor.constraint(equalToConstant: 32)
])
```

## 修改 5：补充阶段5测试

新增测试覆盖三件事：

- tree rows 会把 parent 放在 child 前，并产生 depth。
- renderer snapshot 中 parent group frame 在 child group frame 前。
- 重叠 group frame hit test 时，child frame 优先于 parent frame。

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testGroupHierarchyRowsPlaceParentBeforeChildrenWithDepth()
let rows = CanvasGroupHierarchy.rows(from: [child, parent, sibling])

XCTAssertEqual(rows.map(\.group.id), [parentID, childID, siblingID])
XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testCanvasRendererOrdersParentGroupFramesBeforeChildFrames()
let session = makeGroupHierarchyRenderOrderSession(
    parentID: parentID,
    childID: childID
)
let snapshot = session.makeCanvasSnapshot()

XCTAssertEqual(snapshot.groups.map(\.id), [parentID, childID])
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift - testCanvasContextResolverHitsChildGroupFrameBeforeParentFrame()
_ = session.makeCanvasSnapshot()

let pressContext = session.resolvePointerTarget(
    at: session.camera.worldToViewport(CGPoint(x: 75, y: 75)),
    interactionMetrics: makeGroupHierarchyContextResolverMetrics()
)

guard case .groupFrameBody = pressContext.targetKind else {
    XCTFail("Expected child group frame body hit.")
    return
}
XCTAssertEqual(pressContext.targetGroupID, childID)
```

测试过程中曾发现一个测试前置条件问题：`CanvasEditorSession.resolvePointerTarget(...)` 使用 `lastRenderSnapshot`，因此 context resolver 测试需要先调用 `session.makeCanvasSnapshot()`。修正后新增测试通过。

## 验证

已执行并通过：

- `ReadLints`：无 linter errors。
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS'`

## 当前变更文件

- `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasEditorSessionGroupHierarchyTests.swift`
