# 20260723_112240_group_list_navigation_record

## 记录范围

本记录如实对应刚刚完成的 group 列表点击导航修改：在 iOS/macOS 的 group 列表中，点击某个 group 的内容区域时，将画布镜头移动到该 group frame 的中心点；当前阶段不处理自动缩放。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 显示上述两个 Swift 文件有修改。本记录基于当前 `git diff` 与工作区 changes 整理，不直接粘贴原始 diff。

## 修改前

### iOS group list 只有 add/edit/submit 回调

修改前，iOS group list button setup 只接入添加 group、编辑 group title、提交 group title 三类回调。点击 group 行本身不会通知 controller，也不会移动镜头。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 group list 没有行选择回调，controller 无法响应“点击某个 group”。
// 函数名：iOSViewController.setupGroupListButton()
groupListView.onAddGroupRequested = { [weak self] in
    self?.handleAddGroupRequested()
}
groupListView.onEditGroupTitleRequested = { [weak self] groupID in
    self?.beginGroupTitleEditing(groupID: groupID)
}
groupListView.onGroupTitleSubmitted = { [weak self] groupID, title in
    self?.commitGroupTitleEditing(groupID: groupID, title: title)
}
```

### iOS row 内容区域没有点击手势

修改前，`makeGroupRow(...)` 只构建标题、item 数量、描述和 edit 按钮，没有给 row 内容区域添加 tap gesture。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：修改前 rowStack 只是展示 group 内容，不承载定位到 group 的点击行为。
// 函数名：iOSCanvasGroupListView.makeGroupRow(for:isEditingTitle:focusedTitleTextField:)
let rowStack = UIStackView()
rowStack.translatesAutoresizingMaskIntoConstraints = false
rowStack.axis = .vertical
rowStack.alignment = .fill
rowStack.spacing = 4
rowStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
```

### macOS group list 同样没有行选择回调

修改前，macOS 的 group list 也只处理添加、编辑、提交 title，没有将“点击 group 行”映射为导航动作。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前 macOS group list 没有 onGroupSelected 回调。
// 函数名：macOSViewController.setupGroupListButton()
groupListView.onAddGroupRequested = { [weak self] in
    self?.handleAddGroupRequested()
}
groupListView.onEditGroupTitleRequested = { [weak self] groupID in
    self?.beginGroupTitleEditing(groupID: groupID)
}
groupListView.onGroupTitleSubmitted = { [weak self] groupID, title in
    self?.commitGroupTitleEditing(groupID: groupID, title: title)
}
```

## 修改后

### iOS controller 接入 group 选择导航

修改后，iOS `setupGroupListButton()` 新增 `onGroupSelected` 回调，点击 group 内容区域时调用 `navigateToGroup(withID:)`。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：把 group list 的行选择事件接到 controller 的镜头导航逻辑。
// 函数名：iOSViewController.setupGroupListButton()
groupListView.onGroupSelected = { [weak self] groupID in
    self?.navigateToGroup(withID: groupID)
}
```

### iOS 新增保持 zoom 的 group 导航函数

`navigateToGroup(withID:)` 读取 group frame，计算 frame 中心点，只修改 `camera.center`，保持当前 `zoomScale` 不变。该操作是 view state 变化，不写 undo history，只触发 view state autosave。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：将 iOS 镜头平移到指定 group frame 的中心点，不改变 zoom，不写 undo history。
// 函数名：iOSViewController.navigateToGroup(withID:)
private func navigateToGroup(withID groupID: CanvasItemGroupID) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard let groupFrame = editorSession.groupFrame(withID: groupID) else {
        return
    }

    let targetCenter = CGPoint(x: groupFrame.midX, y: groupFrame.midY)
    guard
        targetCenter.x.isFinite,
        targetCenter.y.isFinite,
        camera.center != targetCenter
    else {
        return
    }

    camera.center = targetCenter
    requestCanvasRefresh(reason: "navigate group list to \(groupID.uuidString)")
    scheduleAutosave(
        reason: "navigate canvas via group list",
        updateKind: .viewStateOnly
    )
}
```

### iOS group row 内容区新增 tap gesture

修改后，`iOSCanvasGroupListView` 增加 `onGroupSelected`，并在非编辑态 row 的 `rowStack` 上添加带 group id 的 tap recognizer。tap 只绑定在内容区域，不绑定到外层 container，因此右侧 pencil edit 按钮不会触发行导航。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：非编辑态 group 内容区域点击后，把 group id 通过 onGroupSelected 回传给 controller。
// 函数名：iOSCanvasGroupListView.makeGroupRow(for:isEditingTitle:focusedTitleTextField:)
if isEditingTitle == false {
    let rowTapGesture = iOSCanvasGroupTapGestureRecognizer(
        groupID: group.id,
        target: self,
        action: #selector(handleGroupRowTap(_:))
    )
    rowTapGesture.cancelsTouchesInView = false
    rowStack.addGestureRecognizer(rowTapGesture)
}
```

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 功能注释：携带被点击 group id 的 iOS tap recognizer。
// 函数名：iOSCanvasGroupTapGestureRecognizer.init(groupID:target:action:)
private final class iOSCanvasGroupTapGestureRecognizer: UITapGestureRecognizer {
    let groupID: CanvasItemGroupID

    init(
        groupID: CanvasItemGroupID,
        target: Any?,
        action: Selector?
    ) {
        self.groupID = groupID
        super.init(target: target, action: action)
    }
}
```

### macOS controller 接入 group 选择导航

macOS 与 iOS 对齐，新增 `onGroupSelected` 回调，并在 controller 中调用同名导航函数。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：把 macOS group list 的行选择事件接到 controller 的镜头导航逻辑。
// 函数名：macOSViewController.setupGroupListButton()
groupListView.onGroupSelected = { [weak self] groupID in
    self?.navigateToGroup(withID: groupID)
}
```

### macOS 新增保持 zoom 的 group 导航函数

macOS 的 `navigateToGroup(withID:)` 同样只设置 `camera.center` 为 group frame 中心点，不修改 zoom，不写 undo history，并按 view state autosave。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：将 macOS 镜头平移到指定 group frame 的中心点，不改变 zoom，不写 undo history。
// 函数名：macOSViewController.navigateToGroup(withID:)
private func navigateToGroup(withID groupID: CanvasItemGroupID) {
    guard let groupFrame = editorSession.groupFrame(withID: groupID) else {
        return
    }

    let targetCenter = CGPoint(x: groupFrame.midX, y: groupFrame.midY)
    guard
        targetCenter.x.isFinite,
        targetCenter.y.isFinite,
        camera.center != targetCenter
    else {
        return
    }

    camera.center = targetCenter
    refreshCanvas(reason: "navigate group list to \(groupID.uuidString)")
    scheduleAutosave(
        reason: "navigate canvas via group list",
        updateKind: .viewStateOnly
    )
}
```

### macOS group row 内容区新增 click recognizer

修改后，`macOSCanvasGroupListView` 增加 `onGroupSelected`，并在非编辑态 row 的 `rowStack` 上添加带 group id 的 `NSClickGestureRecognizer`。由于 click recognizer 绑定在 `rowStack`，右侧 edit 按钮不触发行导航；编辑态输入框所在 row 也不会添加该 recognizer。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：非编辑态 group 内容区域点击后，把 group id 通过 onGroupSelected 回传给 controller。
// 函数名：macOSCanvasGroupListView.makeGroupRow(for:isEditingTitle:focusedTitleTextField:)
if isEditingTitle == false {
    rowStack.addGestureRecognizer(
        macOSCanvasGroupClickGestureRecognizer(
            groupID: group.id,
            target: self,
            action: #selector(handleGroupRowClick(_:))
        )
    )
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：携带被点击 group id 的 macOS click recognizer。
// 函数名：macOSCanvasGroupClickGestureRecognizer.init(groupID:target:action:)
private final class macOSCanvasGroupClickGestureRecognizer: NSClickGestureRecognizer {
    let groupID: CanvasItemGroupID

    init(
        groupID: CanvasItemGroupID,
        target: Any?,
        action: Selector?
    ) {
        self.groupID = groupID
        super.init(target: target, action: action)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
```

## 行为变化

- 在 group 列表中点击某个 group 的内容区域，会将镜头中心移动到该 group frame 中心。
- 当前阶段不自动缩放，不做 fit-to-view。
- 导航只改变 camera view state，不进入 undo/redo 历史。
- 右侧 pencil edit 按钮仍只负责进入标题编辑，不触发镜头导航。
- 正在编辑标题的 row 不挂载 row 点击导航手势，避免输入框点击与导航冲突。
- group 不存在、frame center 非有限值、或 camera 已经在目标中心时，导航 no-op。

## 验证

已执行 lints 检查：

- `ReadLints`：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 无 linter errors。
- `ReadLints`：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 无 linter errors。

已执行 macOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS group list 行点击导航改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

结果：build 成功。

已执行 iOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 iOS group list 行点击导航改动后的编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'generic/platform=iOS' build
```

结果：build 成功。
