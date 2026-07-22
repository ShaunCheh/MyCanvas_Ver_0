# 20260722_083149_iOS 工具条横向滚动位置记忆修复记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚针对 iOS 底部横向工具条滚动位置无法在阅读态/编辑态切换后保留的问题修复。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

## 1. 问题背景

前一次修改中，iOS 工具条内容已经通过 `UIScrollView` 支持横向滚动。但从阅读态切换回编辑态时，工具条会经历 `renderTransition` / `render` / `syncButtons`，按钮栈会被清空再重建；同时原实现还在工具条轴变化时主动把 `contentOffset` 设为 `.zero`。因此用户上一次横向滚动到的位置没有被记住。

## 2. Scroll View 委托与滚动状态字段

### 修改前

`iOSCanvasToolbarHostView` 只是普通 `UIView`，没有监听 `UIScrollView` 的滚动事件，也没有保存用户最后滚动位置的状态字段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: iOSCanvasToolbarHostView 类型定义与属性区
// 功能说明: 修改前没有 UIScrollViewDelegate，也没有记录 contentOffset 的状态。
final class iOSCanvasToolbarHostView: UIView {
    private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var isTransitionRendering = false
    private var transitionInteractivity = true
    private var horizontalStackHeightConstraint: NSLayoutConstraint?
    private var verticalStackWidthConstraint: NSLayoutConstraint?
}
```

### 修改后

`iOSCanvasToolbarHostView` 实现 `UIScrollViewDelegate`，新增横向/竖向 offset 记忆值，以及程序化恢复和待恢复状态标记。`delaysContentTouches = false` 保持工具条按钮点击响应更直接。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: iOSCanvasToolbarHostView 类型定义与属性区
// 功能说明: 修改后 host 自己监听 scroll，并保存滚动位置用于跨 render/transition 恢复。
final class iOSCanvasToolbarHostView: UIView, UIScrollViewDelegate {
    private let contentScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        return scrollView
    }()

    private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
    private var preferredAxisOverride: CanvasToolbarAxis?
    private var isTransitionRendering = false
    private var transitionInteractivity = true
    private var horizontalStackHeightConstraint: NSLayoutConstraint?
    private var verticalStackWidthConstraint: NSLayoutConstraint?
    private var rememberedHorizontalContentOffset: CGFloat = 0
    private var rememberedVerticalContentOffset: CGFloat = 0
    private var isProgrammaticallyRestoringContentOffset = false
    private var shouldRestoreRememberedContentOffset = false
}
```

## 3. 初始化时接入 UIScrollViewDelegate

### 修改前

`contentScrollView` 只是作为滚动容器承载按钮栈，没有把 delegate 交给 host，因此用户滚动行为不会回写到 host 状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改前只搭建 scrollView 层级，没有监听滚动事件。
addSubview(backgroundView)
addSubview(contentClipView)
contentClipView.addSubview(contentScrollView)
contentScrollView.addSubview(buttonsStackView)
```

### 修改后

初始化时将 `contentScrollView.delegate` 设置为当前 host，后续通过 `scrollViewDidScroll(_:)` 记录用户滚动位置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改后由 host 接管 scroll 回调，用于记忆用户最后滚动位置。
addSubview(backgroundView)
addSubview(contentClipView)
contentClipView.addSubview(contentScrollView)
contentScrollView.addSubview(buttonsStackView)
contentScrollView.delegate = self
```

## 4. 布局稳定后恢复滚动位置

### 修改前

布局变化后没有恢复逻辑；按钮重建、阅读态/编辑态切换或 scroll view 内容尺寸变化后，系统可能把 `contentOffset` clamp 回 0。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: hitTest(_:with:)
// 功能说明: 修改前该区域之后没有 layoutSubviews 恢复逻辑。
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard transitionInteractivity else {
        return nil
    }
    let hitView = super.hitTest(point, with: event)
    return hitView === self ? nil : hitView
}
```

### 修改后

在 `layoutSubviews()` 中调用 `restoreRememberedContentOffsetIfNeeded()`。这样等 Auto Layout 更新完 `contentSize` 与可见尺寸后，再把记忆的 offset 按当前可滚动范围钳制恢复。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: layoutSubviews()
// 功能说明: 布局稳定后恢复之前记住的工具条滚动位置。
override func layoutSubviews() {
    super.layoutSubviews()
    restoreRememberedContentOffsetIfNeeded()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: restoreRememberedContentOffsetIfNeeded()
// 功能说明: 根据当前 contentSize 与可见 bounds 钳制 offset，避免恢复到越界位置。
private func restoreRememberedContentOffsetIfNeeded() {
    guard shouldRestoreRememberedContentOffset else {
        return
    }

    let contentSize = contentScrollView.contentSize
    let visibleSize = contentScrollView.bounds.size
    guard
        contentSize.width.isFinite,
        contentSize.height.isFinite,
        visibleSize.width.isFinite,
        visibleSize.height.isFinite,
        visibleSize.width > 0,
        visibleSize.height > 0
    else {
        return
    }

    let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
    let maxOffsetX = max(contentSize.width - visibleSize.width, 0)
    let maxOffsetY = max(contentSize.height - visibleSize.height, 0)
    let restoredOffset: CGPoint

    switch preferredAxis {
    case .horizontal:
        restoredOffset = CGPoint(
            x: min(rememberedHorizontalContentOffset, maxOffsetX),
            y: 0
        )
    case .vertical:
        restoredOffset = CGPoint(
            x: 0,
            y: min(rememberedVerticalContentOffset, maxOffsetY)
        )
    }

    shouldRestoreRememberedContentOffset = false
    guard contentScrollView.contentOffset != restoredOffset else {
        return
    }

    isProgrammaticallyRestoringContentOffset = true
    contentScrollView.setContentOffset(restoredOffset, animated: false)
    isProgrammaticallyRestoringContentOffset = false
}
```

## 5. 用户滚动时记录 offset，恢复期间不覆盖记忆值

### 修改前

没有 `scrollViewDidScroll(_:)`，所以用户把横向工具条滚动到中间或末尾后，host 内部没有任何状态保存这个位置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: 无
// 功能说明: 修改前没有 UIScrollViewDelegate 回调实现，滚动位置不会被记录。
// 修改前此处无 scrollViewDidScroll(_:) 实现。
```

### 修改后

`scrollViewDidScroll(_:)` 记录用户滚动，但在程序化恢复或按钮重建等待恢复期间不记录，避免临时 `contentOffset = 0` 覆盖真实记忆值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: scrollViewDidScroll(_:)
// 功能说明: 用户滚动时记录 offset；恢复期间忽略系统临时滚动回调。
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard
        isProgrammaticallyRestoringContentOffset == false,
        shouldRestoreRememberedContentOffset == false
    else {
        return
    }

    rememberCurrentContentOffset()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffset()
// 功能说明: 保存当前 scrollView offset，并过滤非有限值与负值。
private func rememberCurrentContentOffset() {
    guard contentScrollView.bounds.isEmpty == false else {
        return
    }

    let currentOffset = contentScrollView.contentOffset
    if currentOffset.x.isFinite {
        rememberedHorizontalContentOffset = max(currentOffset.x, 0)
    }
    if currentOffset.y.isFinite {
        rememberedVerticalContentOffset = max(currentOffset.y, 0)
    }
}
```

## 6. 按钮重建与方向布局时保留 offset

### 修改前

`syncButtons(with:)` 会清空并重建 arranged subviews，但不保存/恢复滚动位置。`updateDockEdgeLayout()` 在轴变化时显式将 `contentOffset` 设为 `.zero`，这是阅读态切回编辑态回到起点的直接原因之一。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 修改前按钮重建没有标记恢复 offset，scroll view 可能被系统 clamp 到起点。
private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
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
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: updateDockEdgeLayout()
// 功能说明: 修改前轴变化时主动清零 contentOffset，导致无法记住横向滚动位置。
private func updateDockEdgeLayout() {
    let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
    let isHorizontal = preferredAxis == .horizontal
    let previousAxis = buttonsStackView.axis
    buttonsStackView.axis = preferredAxis == .horizontal
        ? .horizontal
        : .vertical

    if previousAxis != buttonsStackView.axis {
        contentScrollView.setContentOffset(.zero, animated: false)
    }
}
```

### 修改后

按钮重建和方向布局变化前先在稳定状态下保存 offset，然后设置 `shouldRestoreRememberedContentOffset = true`，等待下一次布局完成后恢复。原来的清零逻辑被移除。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: syncButtons(with:)
// 功能说明: 按钮重建前保存稳定 offset，重建后标记下一次 layout 恢复。
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: updateDockEdgeLayout()
// 功能说明: 方向布局变化不再清零 offset，而是标记布局完成后恢复记忆位置。
private func updateDockEdgeLayout() {
    rememberCurrentContentOffsetIfStable()

    let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
    let isHorizontal = preferredAxis == .horizontal
    buttonsStackView.axis = preferredAxis == .horizontal
        ? .horizontal
        : .vertical
    buttonsStackView.alignment = preferredAxis == .horizontal
        ? .center
        : .trailing
    horizontalStackHeightConstraint?.isActive = isHorizontal
    verticalStackWidthConstraint?.isActive = isHorizontal == false
    contentScrollView.alwaysBounceHorizontal = isHorizontal
    contentScrollView.alwaysBounceVertical = isHorizontal == false
    contentScrollView.showsHorizontalScrollIndicator = isHorizontal
    contentScrollView.showsVerticalScrollIndicator = isHorizontal == false

    shouldRestoreRememberedContentOffset = true
    setNeedsLayout()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffsetIfStable()
// 功能说明: 等待恢复期间不再保存 offset，避免按钮清空/重建过程中的临时 0 覆盖记忆值。
private func rememberCurrentContentOffsetIfStable() {
    guard shouldRestoreRememberedContentOffset == false else {
        return
    }

    rememberCurrentContentOffset()
}
```

## 验证情况

已执行并通过：

- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

当前 `git status --short` 显示本次代码改动只有：

- `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

本次仅创建记录文件，没有提交 commit。
