# 20260722_152700_工具条滑动期间冻结内部按钮重排记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚修复 iOS 工具条在编辑态切换到阅读态时，虽然整体改为滑出，但内部按钮仍出现相对位移的问题。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

## 1. 记录当前已渲染的按钮顺序

### 修改前

`iOSCanvasToolbarHostView` 只保存已注册的按钮字典，没有记录当前已经排列到 `buttonsStackView` 中的按钮顺序。因此每次 `renderTransition(_:)` 调用 `syncButtons(with:)` 时，无法判断当前 arrangedSubviews 是否已经稳定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: iOSCanvasToolbarHostView
// 功能说明: 修改前只保存注册按钮，无法判断当前 stackView 中的按钮顺序是否已和输入状态一致。
private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
private var preferredAxisOverride: CanvasToolbarAxis?
private var isTransitionRendering = false
private var transitionInteractivity = true
```

### 修改后

新增 `renderedItemIDs`，用于记录当前已实际渲染到 `buttonsStackView` 的按钮 ID 顺序。这样 transition 期间可以判断“按钮集合和顺序没变”，从而跳过重建。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: iOSCanvasToolbarHostView
// 功能说明: 记录当前已渲染按钮顺序，用于避免 transition 期间重复重建 arrangedSubviews。
private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
private var renderedItemIDs: [CanvasToolbarItemID] = []
private var preferredAxisOverride: CanvasToolbarAxis?
private var isTransitionRendering = false
private var transitionInteractivity = true
```

## 2. 避免 transition 期间反复 remove/add arrangedSubviews

### 修改前

`syncButtons(with:)` 每次都会：

- 尝试记住当前 scroll offset
- 设置 `shouldRestoreRememberedContentOffset = true`
- 移除所有 arrangedSubviews
- 再重新添加按钮

在 toolbar 整体滑入 / 滑出期间，这会让 `UIStackView + UIScrollView` 反复重排内容，导致截图里看到的“工具条整体滑动，但内部按钮也在相对位移”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 修改前每次同步按钮都会重建 arrangedSubviews，transition 中容易触发布局重排和内部按钮位移。
private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
    rememberCurrentContentOffsetIfStable()
    shouldRestoreRememberedContentOffset = true

    let orderedButtons: [UIButton] = itemStates.compactMap { itemState in
        guard let button = registeredButtons[itemState.id] else {
            return nil
        }
        applyAppearance(itemState, to: button)
        return button
    }

    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
    setNeedsLayout()
}
```

### 修改后

`syncButtons(with:)` 先构造目标按钮顺序，然后和当前 `renderedItemIDs` 以及 `buttonsStackView.arrangedSubviews` 做一致性判断。若已经一致，只更新按钮外观并直接返回，不再触发 arrangedSubviews 重建，也不触发 scroll offset restore。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 如果按钮顺序和 arrangedSubviews 已稳定，则跳过重建，避免滑动动画中内部按钮相对位移。
let orderedButtonPairs: [(id: CanvasToolbarItemID, button: UIButton)] = itemStates.compactMap { itemState in
    guard let button = registeredButtons[itemState.id] else {
        return nil
    }
    applyAppearance(itemState, to: button)
    return (itemState.id, button)
}
let orderedItemIDs = orderedButtonPairs.map(\.id)
let orderedButtons = orderedButtonPairs.map(\.button)
let existingArrangedSubviews = buttonsStackView.arrangedSubviews
let hasSameArrangedButtons =
    renderedItemIDs == orderedItemIDs &&
    existingArrangedSubviews.count == orderedButtons.count &&
    zip(existingArrangedSubviews, orderedButtons).allSatisfy { existingView, orderedButton in
        existingView === orderedButton
    }

guard hasSameArrangedButtons == false else {
    logScrollOffsetDiagnostic(
        "syncButtons.skipStableArrangement",
        extra: "arranged=\(buttonsStackView.arrangedSubviews.count)"
    )
    return
}
```

## 3. 必要重建时取消内部布局动画

### 修改前

当 `buttonsStackView` 的 arrangedSubviews 被 remove/add 时，这些布局变化发生在 toolbar transition 的动画上下文中，可能被 UIKit 当成同一个动画事务的一部分处理，造成按钮在工具条内部滑动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 修改前重建 stackView 内容没有显式禁用动画。
buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
    buttonsStackView.removeArrangedSubview(arrangedSubview)
    arrangedSubview.removeFromSuperview()
}

orderedButtons.forEach { button in
    buttonsStackView.addArrangedSubview(button)
}
setNeedsLayout()
```

### 修改后

确实需要重建按钮时，用 `UIView.performWithoutAnimation` 包住 remove/add，并立即 `layoutIfNeeded()`，让内部布局稳定在当前帧，不跟随 toolbar host 的滑动动画做额外插值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 必须重建按钮时禁用内部布局动画，保证 transition 只移动 toolbar host 本身。
rememberCurrentContentOffsetIfStable()
shouldRestoreRememberedContentOffset = true

UIView.performWithoutAnimation {
    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
    buttonsStackView.layoutIfNeeded()
}

renderedItemIDs = orderedItemIDs
setNeedsLayout()
```

## 4. 实际效果

这次修改不是删除收缩 / 展开逻辑，也不是调整 transition stage；它修的是 iOS toolbar host 内部在 transition 期间的副作用：

- 按钮集合不变时，不再重建 `arrangedSubviews`
- 不再因为稳定同步而设置 `shouldRestoreRememberedContentOffset`
- 必要重建时关闭内部布局动画
- 目标是让工具条在滑入 / 滑出时表现为“整块 view 移动”，内部按钮不再相对位移

## 验证情况

已执行并通过：

- `ReadLints` 检查 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`，无 linter errors
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

创建本记录前，当前 `git status --short` 显示本次代码改动为：

- `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

本次仅创建记录文件，没有提交 commit。
