# 20260724_171512_group_list_outside_click_dismissal_record

## 背景

本次修改为 group 面板增加一个默认关闭的行为开关：当开关为 `true` 时，group 面板打开后点击非面板区域可以收起；当开关为 `false` 时，维持现有行为。

开关当前同时加入 iOS 和 macOS controller，默认值均为 `false`，因此默认运行行为不变。

## 当前 changes

本次记录参考了当前 `git diff` 和工作区 changes，源码层面只涉及以下两个文件：

```shell
# terminal
# 命令：查看本次未提交源码变更范围
git status --short
```

结果：

```shell
# terminal
# 当前 changes：只修改 iOS/macOS 两个 controller
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
```

## iOS 修改前

修改前，`iOSViewController` 只有 `isGroupListVisible` 控制 group 面板显隐，没有“点击外部收起”的可配置开关。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - iOSViewController state
private var isTransitionInteractionFrozen = false
private var transitionChromeHidden = false
private var isGroupListVisible = false
private var editingGroupTitleID: CanvasItemGroupID?
private var groupListNavigationDisplayLink: CADisplayLink?
private var groupListNavigationAnimationState: CameraCenterAnimationState?
```

修改前，primary pointer down 进入 canvas 点击流程时，不会主动检查 group 面板是否需要因为外部点击而关闭。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - handlePrimaryPointerDown(at:modifiers:)
if contextMenuState != nil {
    dismissContextMenu()
    return
}

let pressContext = resolvePointerPressContext(at: location)
pointerDragState = .pressed(
    pressedLocation: location,
    pressContext: pressContext,
    pointerModifiers: modifiers
)
```

## iOS 修改后

修改后，新增 `allowsGroupListOutsideClickDismissal`，默认值为 `false`。默认 false 是为了保持当前行为不变，只有显式改为 true 时才启用外部点击收起。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - iOSViewController state
private var isTransitionInteractionFrozen = false
private var transitionChromeHidden = false
private var isGroupListVisible = false
private var allowsGroupListOutsideClickDismissal = false
private var editingGroupTitleID: CanvasItemGroupID?
private var groupListNavigationDisplayLink: CADisplayLink?
private var groupListNavigationAnimationState: CameraCenterAnimationState?
```

primary pointer down 增加了外部点击检查。该调用不会阻断后续 canvas 原有点击流程，避免默认交互路径被额外改变。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - handlePrimaryPointerDown(at:modifiers:)
if contextMenuState != nil {
    dismissContextMenu()
    return
}

collapseGroupListForOutsidePointerIfNeeded(atViewportLocation: location)

let pressContext = resolvePointerPressContext(at: location)
pointerDragState = .pressed(
    pressedLocation: location,
    pressContext: pressContext,
    pointerModifiers: modifiers
)
```

新增 helper 会先检查开关和面板状态，再把 viewport 点转换到 root view、group 面板、group 按钮坐标系。只有点击同时落在面板和按钮之外时，才结束编辑、清空编辑态并关闭面板。

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift - collapseGroupListForOutsidePointerIfNeeded(atViewportLocation:)
@discardableResult
private func collapseGroupListForOutsidePointerIfNeeded(
    atViewportLocation location: CGPoint
) -> Bool {
    guard
        allowsGroupListOutsideClickDismissal,
        isGroupListVisible
    else {
        return false
    }

    let pointInRootView = canvasViewportView.convert(location, to: view)
    let pointInGroupList = groupListView.convert(pointInRootView, from: view)
    let pointInGroupListButton = groupListButton.convert(pointInRootView, from: view)
    guard
        groupListView.bounds.contains(pointInGroupList) == false,
        groupListButton.bounds.contains(pointInGroupListButton) == false
    else {
        return false
    }

    groupListView.endEditing(true)
    editingGroupTitleID = nil
    isGroupListVisible = false
    updateGroupListPresentation()
    updateChromeOverlayLayout()
    return true
}
```

## macOS 修改前

修改前，`macOSViewController` 同样只有 group 面板显隐状态，没有默认关闭的外部点击收起开关。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSViewController state
private var isTransitionInteractionFrozen = false
private var isGroupListVisible = false
private var editingGroupTitleID: CanvasItemGroupID?
private var keyboardShortcutObservationMonitor: Any?
private var observedKeyboardShortcuts: [ObservedKeyboardShortcut] = []
```

修改前，macOS primary pointer down 在 context menu 处理后直接进入 hit test 和 pointer state 建立流程。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - handlePrimaryPointerDown(at:modifiers:)
if contextMenuState != nil {
    dismissContextMenu()
    return
}

let pressContext = resolvePointerPressContext(at: location)
logPointerHitResolution(
    phase: "down",
    location: location,
    context: pressContext
)
```

## macOS 修改后

修改后，macOS 也新增同名开关，默认 `false`，与 iOS 行为保持一致。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - macOSViewController state
private var isTransitionInteractionFrozen = false
private var isGroupListVisible = false
private var allowsGroupListOutsideClickDismissal = false
private var editingGroupTitleID: CanvasItemGroupID?
private var keyboardShortcutObservationMonitor: Any?
private var observedKeyboardShortcuts: [ObservedKeyboardShortcut] = []
```

primary pointer down 增加外部点击收起检查，默认开关关闭时该调用直接返回 `false`，不改变当前行为。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - handlePrimaryPointerDown(at:modifiers:)
if contextMenuState != nil {
    dismissContextMenu()
    return
}

collapseGroupListForOutsidePointerIfNeeded(atViewportLocation: location)

let pressContext = resolvePointerPressContext(at: location)
logPointerHitResolution(
    phase: "down",
    location: location,
    context: pressContext
)
```

macOS helper 与 iOS 使用同样的坐标判断逻辑。关闭时会先释放 first responder，避免 group title inline editor 仍保持焦点。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift - collapseGroupListForOutsidePointerIfNeeded(atViewportLocation:)
@discardableResult
private func collapseGroupListForOutsidePointerIfNeeded(
    atViewportLocation location: CGPoint
) -> Bool {
    guard
        allowsGroupListOutsideClickDismissal,
        isGroupListVisible
    else {
        return false
    }

    let pointInRootView = canvasViewportView.convert(location, to: view)
    let pointInGroupList = groupListView.convert(pointInRootView, from: view)
    let pointInGroupListButton = groupListButton.convert(pointInRootView, from: view)
    guard
        groupListView.bounds.contains(pointInGroupList) == false,
        groupListButton.bounds.contains(pointInGroupListButton) == false
    else {
        return false
    }

    view.window?.makeFirstResponder(nil)
    editingGroupTitleID = nil
    isGroupListVisible = false
    updateGroupListPresentation()
    updateChromeOverlayLayout()
    return true
}
```

## 行为说明

- `allowsGroupListOutsideClickDismissal = false`：默认路径，点击非面板区域不会收起 group 面板，维持当前行为。
- `allowsGroupListOutsideClickDismissal = true`：group 面板打开时，点击 group 面板和 group 按钮之外的区域会收起面板。
- 点击 group 面板内部或 group 按钮本身不会触发外部收起逻辑。
- 收起逻辑不提前 `return`，因此不会额外吞掉原本 canvas pointer down 后续流程。

## 验证

已检查刚修改的两个文件，没有 linter 报错。

```shell
# terminal
# 验证：ReadLints 检查 iOS/macOS controller
ReadLints(
  paths: [
    "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift",
    "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
  ]
)
```

结果：无 linter errors。

已执行 macOS 和 iOS build。

```shell
# terminal
# 验证：先构建 macOS，再构建 iOS generic destination
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' && xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS'
```

结果：build 通过。

