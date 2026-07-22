# 20260722_174935_cross_platform_group_frame_record

## 记录范围

本记录基于当前 `git status --short`、`git diff --stat` 与代表性 `git diff` 整理，不包含原始 diff。

当前 changes：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 当前工作区变更
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
```

变更规模：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 git diff --stat 摘要
17 files changed, 286 insertions(+), 10 deletions(-)
```

本次目标：

- 在跨平台画布工具条中新增 group 按钮。
- 点击 group 按钮后，在当前视口中心创建一个浅灰色半透明 group 框。
- group 框持久化到 board document。
- 渲染层级保持为：画布背景 / board surface < group 框 < item。
- 暂不实现拖拽、缩放、自动把框内 item 加入 group。

## 数据模型与持久化

修改前，`CanvasItemGroup` 只保存语义信息：标题、描述和关联 item IDs，没有画布上的 frame，因此不能渲染或恢复 group 框。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - CanvasItemGroup 修改前
// 功能说明：旧 group 只有语义关联数据，没有 canvas-space frame。
struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]
}
```

修改后，`CanvasItemGroup` 增加可选 `frame`。旧 group 没有 frame 时仍然可读，只是不渲染 group 框。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - CanvasItemGroup 修改后
// 功能说明：frame 是 canvas-space rect，用于持久化并渲染 group 背景框。
struct CanvasItemGroup: Equatable, Hashable, Sendable {
    let id: CanvasItemGroupID
    var title: String
    var description: String
    var itemIDs: [CanvasItemID]
    var frame: CGRect?

    init(
        id: CanvasItemGroupID = UUID(),
        title: String,
        description: String = "",
        itemIDs: [CanvasItemID],
        frame: CGRect? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.itemIDs = Self.normalizedItemIDs(itemIDs)
        self.frame = frame?.standardized
    }
}
```

文档版本从 `12` 升到 `13`，并在 `BoardGroupRecord` 中新增 `frame`。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift - BoardDocument / BoardGroupRecord
// 功能说明：版本 13 表示 group 可以携带可选的持久化 frame。
static let currentFormatVersion = 13

struct BoardGroupRecord: Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var itemIDs: [UUID]
    var frame: BoardRectRecord?
}
```

mapper 也同步处理 frame 的 runtime/document 双向转换。

```swift
// MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift - makeGroup / makeGroupRecord
// 功能说明：BoardGroupRecord.frame 与 CanvasItemGroup.frame 双向转换。
private static func makeGroup(
    from groupRecord: BoardGroupRecord
) -> CanvasItemGroup {
    CanvasItemGroup(
        id: groupRecord.id,
        title: groupRecord.title,
        description: groupRecord.description,
        itemIDs: groupRecord.itemIDs,
        frame: groupRecord.frame?.cgRect
    )
}

private static func makeGroupRecord(
    from group: CanvasItemGroup
) -> BoardGroupRecord {
    BoardGroupRecord(
        id: group.id,
        title: group.title,
        description: group.description,
        itemIDs: group.itemIDs,
        frame: group.frame.map(BoardRectRecord.init)
    )
}
```

## 创建 Group 框

修改前，`appendGroup` 只创建无 frame 的语义 group，主要供 group list 使用。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - appendGroup 修改前
// 功能说明：旧逻辑只能追加语义 group，无法创建画布上的 group 框。
func appendGroup(
    title: String? = nil,
    description: String = "",
    itemIDs: [CanvasItemID] = [],
    recordHistory: Bool = false
) -> CanvasItemGroup {
    let group = CanvasItemGroup(
        title: title ?? "group \(groups.count + 1)",
        description: description,
        itemIDs: itemIDs
    )
    groups.append(group)
    return group
}
```

修改后，`appendGroup` 支持可选 frame；新增 `addGroup()` 专门给工具条按钮使用，会在 camera center 创建默认 `360 x 240` 的 group 框并记录 history / autosave。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift - addGroup()
// 功能说明：工具条创建 group 框，默认放在当前视口中心。
private static let defaultGroupFrameSize = CGSize(width: 360, height: 240)

var canAddGroup: Bool {
    inlineEditState == nil
}

@discardableResult
func addGroup() -> CanvasItemGroup? {
    guard canAddGroup else {
        return nil
    }

    let frame = CGRect(
        x: camera.center.x - Self.defaultGroupFrameSize.width / 2,
        y: camera.center.y - Self.defaultGroupFrameSize.height / 2,
        width: Self.defaultGroupFrameSize.width,
        height: Self.defaultGroupFrameSize.height
    )
    return appendGroup(
        frame: frame,
        recordHistory: true
    )
}
```

## Command 与工具条

修改前，command 和工具条只有 text / markdown / hand drawing / arrow / import 等 item 入口，没有 add group 命令。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift - CanvasCommandID 修改前
// 功能说明：旧命令集合没有 addGroup。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case addMarkdownItem
    case addHandDrawingItem
    case addArrowItem
}
```

修改后，新增 `.addGroup`，并在 catalog / executor / context menu resolver 中接入。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift - CanvasCommandID / CanvasCommand 修改后
// 功能说明：新增跨平台 addGroup 命令，供工具条按钮执行。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case addMarkdownItem
    case addHandDrawingItem
    case addArrowItem
    case addGroup
}

enum CanvasCommand {
    case addArrowItem
    case addGroup
}
```

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift - execute(_:)
// 功能说明：addGroup 命令调用 session.addGroup()，创建持久化 group 框。
case .addGroup:
    guard let addedGroup = session.addGroup() else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "add group \(addedGroup.id.uuidString)"
    )
```

工具条 state 新增 `.group` item，并插入在 arrow 后、import 前。

```swift
// MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift - CanvasToolbarItemID
// 功能说明：新增 group 工具条按钮 id。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case arrow
    case group
    case importMedia
}
```

```swift
// MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift - mainToolbarState()
// 功能说明：跨平台主工具条追加 group 按钮状态。
itemStates.append(arrowItemState(session: session))
itemStates.append(groupItemState(session: session))
itemStates.append(importItemState(isEnabled: isImportEnabled))
```

```swift
// MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift - groupItemState(session:)
// 功能说明：group 按钮使用 addGroup command descriptor。
func groupItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .addGroup,
        session: session
    )
    return CanvasToolbarItemState(
        id: .group,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        isActive: descriptor.isActive,
        accessibilityLabel: "Add group",
        visualRole: .accent
    )
}
```

## iOS / macOS 工具条接入

iOS 和 macOS controller 都新增了实际按钮对象，并注册到 `toolbarButtonsByID`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - toolbarButtonsByID / handleGroupButtonTap()
// 功能说明：iOS 工具条按钮点击后执行 .addGroup。
private let groupButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .arrow: arrowButton,
        .group: groupButton,
        .importMedia: importButton
    ]
}

@objc
private func handleGroupButtonTap() {
    performCommand(.addGroup)
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - toolbarButtonsByID / handleGroupButtonClick()
// 功能说明：macOS 工具条按钮点击后执行 .addGroup。
private let groupButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .arrow: arrowButton,
        .group: groupButton,
        .importMedia: importButton
    ]
}

@objc
private func handleGroupButtonClick() {
    performCommand(.addGroup)
}
```

## 渲染层级

修改前，`CanvasRenderSnapshot` 只有普通 item render 列表；group 没有独立渲染合同。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift - CanvasRenderSnapshot 修改前
// 功能说明：旧 snapshot 只有 items，viewport 无法单独控制 group 框层级。
struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let items: [CanvasRenderItem]
}
```

修改后，新增 `CanvasGroupRenderItem`，并在 snapshot 中增加 `groups`，让 viewport 在 item 层下方独立绘制 group 框。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift - CanvasGroupRenderItem / CanvasRenderSnapshot 修改后
// 功能说明：groups 是单独的 render layer 输入，层级独立于普通 items。
struct CanvasGroupRenderItem {
    let id: CanvasItemGroupID
    let screenFrame: CGRect
    let worldFrame: CGRect
}

struct CanvasRenderSnapshot {
    let viewportBounds: CGRect
    let visibleWorldRect: CGRect
    let workspaceOverlay: CanvasWorkspaceRenderOverlay?
    let groups: [CanvasGroupRenderItem]
    let items: [CanvasRenderItem]
}
```

renderer 会过滤无 frame 或不可见 group，并把 canvas-space frame 转换为 screen-space frame。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift - makeGroupRenderItem(for:visibleWorldRect:camera:)
// 功能说明：只渲染有合法 frame 且与当前可见区域相交的 group 框。
private func makeGroupRenderItem(
    for group: CanvasItemGroup,
    visibleWorldRect: CGRect,
    camera: CanvasCamera
) -> CanvasGroupRenderItem? {
    guard let rawFrame = group.frame else {
        return nil
    }

    let worldFrame = rawFrame.standardized
    guard worldFrame.width > 0,
          worldFrame.height > 0,
          worldFrame.intersects(visibleWorldRect)
    else {
        return nil
    }

    return CanvasGroupRenderItem(
        id: group.id,
        screenFrame: camera.worldToViewport(worldFrame).standardized,
        worldFrame: worldFrame
    )
}
```

## Viewport 绘制

iOS viewport 新增 `groupFramesLayer`，插入在 `boardSurfaceLayer` 与 `itemsLayer` 之间，保证层级为：画布 / board surface < group 框 < item。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift - setupLayers()
// 功能说明：groupFramesLayer 放在 item layer 下方。
layer.addSublayer(boardSurfaceLayer)
layer.addSublayer(groupFramesLayer)
layer.addSublayer(itemsLayer)
layer.addSublayer(overlayLayer)
```

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift - refreshGroupFrameLayers()
// 功能说明：使用浅灰半透明 CAShapeLayer 绘制 group 框。
private static let groupFrameFillColor = CGColor(gray: 0.55, alpha: 0.18)
private static let groupFrameStrokeColor = CGColor(gray: 0.45, alpha: 0.32)
private static let groupFrameCornerRadius: CGFloat = 14

private func refreshGroupFrameLayers() {
    let incomingGroupIDs = Set(snapshot.groups.map(\.id))
    let existingGroupIDs = Set(groupFrameLayers.keys)

    for removedID in existingGroupIDs.subtracting(incomingGroupIDs) {
        groupFrameLayers[removedID]?.removeFromSuperlayer()
        groupFrameLayers[removedID] = nil
    }

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
}
```

macOS viewport 采用同样结构和颜色，保持跨平台一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift - setupLayers()
// 功能说明：macOS 同样把 group 框层放在 itemsLayer 下方。
layer?.addSublayer(boardSurfaceLayer)
layer?.addSublayer(groupFramesLayer)
layer?.addSublayer(itemsLayer)
layer?.addSublayer(overlayLayer)
```

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift - refreshGroupFrameLayers()
// 功能说明：macOS 使用同样的浅灰半透明圆角矩形绘制 group 框。
private static let groupFrameFillColor = CGColor(gray: 0.55, alpha: 0.18)
private static let groupFrameStrokeColor = CGColor(gray: 0.45, alpha: 0.32)
private static let groupFrameCornerRadius: CGFloat = 14

private func refreshGroupFrameLayers() {
    let incomingGroupIDs = Set(snapshot.groups.map(\.id))
    let existingGroupIDs = Set(groupFrameLayers.keys)

    for removedID in existingGroupIDs.subtracting(incomingGroupIDs) {
        groupFrameLayers[removedID]?.removeFromSuperlayer()
        groupFrameLayers[removedID] = nil
    }

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
}
```

## 测试

原有 group round-trip 测试只验证 id / title / description / itemIDs。现在补充验证 frame 的 document record 与 runtime 恢复。

```swift
// MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift - testBoardDocumentMapperRoundTripsCanvasItemGroups()
// 功能说明：验证 group frame 可以被编码到文档，并在 mapper round-trip 后恢复。
let groupFrame = CGRect(x: -120, y: 80, width: 360, height: 240)
runtimeState.groups = [
    CanvasItemGroup(
        id: groupID,
        title: "Question Evidence",
        description: "Image answers the markdown question.",
        itemIDs: [itemID],
        frame: groupFrame
    )
]

XCTAssertEqual(groupRecord.frame?.cgRect, groupFrame)
XCTAssertEqual(roundTrippedGroup.frame, groupFrame)
```

## 验证命令

本次已运行以下验证，结果均通过。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 macOS build
xcodebuild -scheme MyCanvas_Ver_0 -destination 'platform=macOS' build > /tmp/mycanvas_group_frame_macos_build.log 2>&1
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 iOS Simulator build
xcodebuild -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator' build > /tmp/mycanvas_group_frame_ios_build.log 2>&1
```

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0 group frame round-trip 测试
xcodebuild -scheme MyCanvas_Ver_0 -destination 'platform=macOS' test -only-testing:MyCanvas_Ver_0Tests/BoardVideoStorageTests/testBoardDocumentMapperRoundTripsCanvasItemGroups > /tmp/mycanvas_group_frame_test.log 2>&1
```

同时已读取 IDE lint 诊断，相关修改文件无 linter errors。

## 备注

本次没有提交代码。该记录只描述刚刚实现的跨平台工具条 group 按钮与持久化 group 框。
