# 20260722_090203_iOS 工具条滚动位置保存条件修复记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚针对 iOS 底部横向工具条滚动位置被阅读态清空按钮流程覆盖为 0 的修复。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

## 1. 定位结论

定位日志显示，用户滑动工具条时 `rememberedX` 能正确记录到右侧位置，例如 `116`。问题发生在切换阅读态后：工具条按钮被清空，`UIScrollView` 的内容尺寸变成空内容，系统把 `contentOffset` clamp 到 `0`，随后 `scrollViewDidScroll(_:)` 又把这个系统性 clamp 当成用户滚动保存，导致 `rememberedX` 被覆盖为 `0`。

因此这次修改没有继续调整 restore 逻辑，而是收紧“什么时候允许写入 remembered offset”的条件。

## 2. scrollViewDidScroll 写入条件收紧

### 修改前

`scrollViewDidScroll(_:)` 只判断是否正在程序化恢复、是否有待恢复任务。只要这两个条件都为 false，就会保存当前 offset。阅读态清空按钮后，系统触发的 `contentOffset = 0` 也会进入保存路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: scrollViewDidScroll(_:)
// 功能说明: 修改前会把系统 clamp 产生的 0 也当作用户滚动写入记忆值。
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard
        isProgrammaticallyRestoringContentOffset == false,
        shouldRestoreRememberedContentOffset == false
    else {
        logScrollOffsetDiagnostic(
            "scrollViewDidScroll.ignored",
            extra:
                "programmatic=\(isProgrammaticallyRestoringContentOffset) " +
                "restorePending=\(shouldRestoreRememberedContentOffset)"
        )
        return
    }

    logScrollOffsetDiagnostic("scrollViewDidScroll.record")
    rememberCurrentContentOffset()
}
```

### 修改后

新增 `canRememberCurrentContentOffset()` 校验。只有工具条处在稳定、可交互、有按钮、并且当前轴向确实可滚动时，`scrollViewDidScroll(_:)` 才允许写入记忆值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: scrollViewDidScroll(_:)
// 功能说明: 修改后只有稳定且真实可滚动的用户滚动才会写入 remembered offset。
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard
        isProgrammaticallyRestoringContentOffset == false,
        shouldRestoreRememberedContentOffset == false,
        canRememberCurrentContentOffset()
    else {
        logScrollOffsetDiagnostic(
            "scrollViewDidScroll.ignored",
            extra:
                "programmatic=\(isProgrammaticallyRestoringContentOffset) " +
                "restorePending=\(shouldRestoreRememberedContentOffset) " +
                "canRemember=\(canRememberCurrentContentOffset())"
        )
        return
    }

    logScrollOffsetDiagnostic("scrollViewDidScroll.record")
    rememberCurrentContentOffset()
}
```

## 3. 非 scroll 回调保存路径同步收紧

### 修改前

`rememberCurrentContentOffsetIfStable()` 只避开了 `shouldRestoreRememberedContentOffset == true` 的情况。只要没有待恢复标记，就会继续调用 `rememberCurrentContentOffset()`，而 `rememberCurrentContentOffset()` 只检查 bounds 是否为空。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffsetIfStable()
// 功能说明: 修改前只根据 restorePending 判断是否保存，无法排除空按钮或不可滚动状态。
private func rememberCurrentContentOffsetIfStable() {
    guard shouldRestoreRememberedContentOffset == false else {
        logScrollOffsetDiagnostic("remember.skipRestorePending")
        return
    }

    rememberCurrentContentOffset()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffset()
// 功能说明: 修改前只过滤空 bounds，仍可能在内容不可滚动或按钮为空时保存 0。
private func rememberCurrentContentOffset() {
    guard contentScrollView.bounds.isEmpty == false else {
        logScrollOffsetDiagnostic("remember.skipEmptyBounds")
        return
    }

    let currentOffset = contentScrollView.contentOffset
    if currentOffset.x.isFinite {
        rememberedHorizontalContentOffset = max(currentOffset.x, 0)
    }
    if currentOffset.y.isFinite {
        rememberedVerticalContentOffset = max(currentOffset.y, 0)
    }
    logScrollOffsetDiagnostic("remember.saved")
}
```

### 修改后

`rememberCurrentContentOffsetIfStable()` 也复用 `canRememberCurrentContentOffset()`，确保按钮重建、模式切换、空内容 clamp 期间都不会覆盖原来的 `rememberedX`。`rememberCurrentContentOffset()` 只负责执行写入，不再承担稳定性判断。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffsetIfStable()
// 功能说明: 修改后所有非 scroll 回调保存路径也必须通过稳定性与可滚动性校验。
private func rememberCurrentContentOffsetIfStable() {
    guard shouldRestoreRememberedContentOffset == false else {
        logScrollOffsetDiagnostic("remember.skipRestorePending")
        return
    }

    guard canRememberCurrentContentOffset() else {
        logScrollOffsetDiagnostic("remember.skipUnstableGeometry")
        return
    }

    rememberCurrentContentOffset()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: rememberCurrentContentOffset()
// 功能说明: 修改后该函数只执行有限值过滤与写入，调用前由 canRememberCurrentContentOffset 保证状态稳定。
private func rememberCurrentContentOffset() {
    let currentOffset = contentScrollView.contentOffset
    if currentOffset.x.isFinite {
        rememberedHorizontalContentOffset = max(currentOffset.x, 0)
    }
    if currentOffset.y.isFinite {
        rememberedVerticalContentOffset = max(currentOffset.y, 0)
    }
    logScrollOffsetDiagnostic("remember.saved")
}
```

## 4. 新增 canRememberCurrentContentOffset

### 修改前

没有统一的“是否允许保存 offset”判断。滚动回调和布局/按钮重建路径各自只做局部判断，无法识别以下不应保存的场景：

- transition 渲染中；
- toolbar 当前不可交互；
- 按钮栈为空；
- scrollView bounds 或 contentSize 不稳定；
- 当前轴向没有真实可滚动空间。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: 无
// 功能说明: 修改前没有统一的 offset 保存资格判断函数。
// 修改前此处无 canRememberCurrentContentOffset()。
```

### 修改后

新增 `canRememberCurrentContentOffset()`，把保存资格集中到一个函数中。横向工具条只有 `contentSize.width > visibleSize.width + 0.5` 时才允许保存横向 offset；阅读态按钮清空后 `arrangedSubviews.isEmpty == true`，会直接返回 false。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: canRememberCurrentContentOffset()
// 功能说明: 统一判断当前 scroll offset 是否来自稳定、可交互、真实可滚动的工具条状态。
private func canRememberCurrentContentOffset() -> Bool {
    guard
        isTransitionRendering == false,
        transitionInteractivity,
        buttonsStackView.arrangedSubviews.isEmpty == false,
        contentScrollView.bounds.isEmpty == false
    else {
        return false
    }

    let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
    let contentSize = contentScrollView.contentSize
    let visibleSize = contentScrollView.bounds.size
    guard
        contentSize.width.isFinite,
        contentSize.height.isFinite,
        visibleSize.width.isFinite,
        visibleSize.height.isFinite,
        contentScrollView.contentOffset.x.isFinite,
        contentScrollView.contentOffset.y.isFinite,
        visibleSize.width > 0,
        visibleSize.height > 0
    else {
        return false
    }

    switch preferredAxis {
    case .horizontal:
        return contentSize.width > visibleSize.width + 0.5
    case .vertical:
        return contentSize.height > visibleSize.height + 0.5
    }
}
```

## 预期效果

阅读态切换时，按钮清空导致的系统 clamp 会进入 `scrollViewDidScroll.ignored` 或 `remember.skipUnstableGeometry`，不会再把用户之前滚到右侧的 `rememberedHorizontalContentOffset` 覆盖为 `0`。切回编辑态后，restore 仍会使用旧的 `rememberedX`，并按当前 `contentSize - bounds.width` 做 clamp。

## 验证情况

已执行并通过：

- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

当前 `git status --short` 在创建本记录前显示本次代码改动只有：

- `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`

本次仅创建记录文件，没有提交 commit。
