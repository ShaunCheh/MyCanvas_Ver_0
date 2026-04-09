# 20260409_105137_boardlist_zoom_transition_phase6_followup_static_helper_capture_fix_record

## 记录范围

- 记录内容：补充记录 `boardlist缩放转场` `Phase 6` 实施后的一个编译修复。
- 记录内容：修复 `iOSBoardListCanvasTransitionCarrier.swift` 在动画闭包中调用 `animationOptions(...)` 时触发的显式捕获报错。
- 记录内容：同步修复 `macOSBoardListCanvasTransitionCarrier.swift` 中同类 helper 的调用方式，避免同一类问题在另一端继续出现。
- 记录依据：本记录基于当前工作树的 `git diff -- MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift` 以及修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 本记录不包含：`Phase 6` 主体功能实现。
- 本记录不包含：对既有 `commit_records/*.md` 的回写。
- 本记录不包含：git commit。

## 问题背景

- 本次补充修复对应的实际报错是：
  - `Call to method 'animationOptions' in closure requires explicit use of 'self' to make capture semantics explicit`
- 根因不是某一行单独漏写 `self`，而是：
  - `iOS` 侧的 `animationOptions(for:)`
  - `macOS` 侧的 `timingFunctionName(for:)`
- 这两个 helper 都不依赖实例状态，但在 `Phase 6` 中仍保留成了实例方法；当它们在动画闭包里被调用时，Swift 要求显式说明捕获语义。
- 因此这次不是只在单点加一个 `self.`，而是把 helper 提升成静态方法，并把全部调用统一改成 `Self.xxx(...)`，从根因上消除这类捕获问题。

## 修改一：iOS carrier 将 `animationOptions(for:)` 从实例 helper 改为静态 helper

### 修改前

- `iOSSnapshotShellCarrier` 在多个 `UIView.animate(...)` 调用里直接写 `animationOptions(for: ...)`。
- `animationOptions(for:)` 本身是实例方法，所以闭包里会隐式捕获 `self`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateOpeningTransition(completion:) / animateClosingTransition(completion:) / animationOptions(for:)
// 功能说明: 修改前 iOS carrier 在动画闭包上下文里直接调用实例 helper，导致 Swift 要求显式写出 self 的捕获语义。
private func animateOpeningTransition(completion: @escaping () -> Void) {
    guard let shellShadowView, let shellContentView else {
        destinationView.isHidden = false
        destinationView.alpha = 0
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
            delay: 0,
            options: [animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
        ) {
            destinationView.alpha = 1
        } completion: { _ in
            completion()
        }
        return
    }

    UIView.animate(
        withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
        delay: 0,
        usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
        initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
        options: [.beginFromCurrentState, animationOptions(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)]
    ) {
        shellShadowView.frame = targetFrame
        shellContentView.layer.cornerRadius = 0
    }
}

private func animateClosingTransition(completion: @escaping () -> Void) {
    if let targetFrame {
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
            delay: 0,
            options: [.beginFromCurrentState, animationOptions(for: BoardListCanvasTransitionConfiguration.closingAnimation.curve)]
        ) {
            shellShadowView.frame = targetFrame
        } completion: { _ in
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                delay: 0,
                options: [animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
            ) {
                shellShadowView.alpha = 0
            } completion: { _ in
                completion()
            }
        }
        return
    }
}

private func animationOptions(
    for curve: BoardListCanvasTransitionTimingCurve
) -> UIView.AnimationOptions {
    switch curve {
    case .easeInOut:
        return .curveEaseInOut
    case .easeOut:
        return .curveEaseOut
    }
}
```

### 修改后

- `animationOptions(for:)` 改成 `private static func`。
- 所有调用统一改成 `Self.animationOptions(for: ...)`。
- 改完后闭包不再需要隐式捕获实例来访问这个 helper。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateOpeningTransition(completion:) / animateClosingTransition(completion:) / animationOptions(for:)
// 功能说明: 修改后 iOS carrier 把曲线映射 helper 静态化，并统一通过 Self 调用，消除动画闭包中的隐式实例捕获。
private func animateOpeningTransition(completion: @escaping () -> Void) {
    guard let shellShadowView, let shellContentView else {
        destinationView.isHidden = false
        destinationView.alpha = 0
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
            delay: 0,
            options: [Self.animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
        ) {
            destinationView.alpha = 1
        } completion: { _ in
            completion()
        }
        return
    }

    UIView.animate(
        withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
        delay: 0,
        usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
        initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
        options: [.beginFromCurrentState, Self.animationOptions(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)]
    ) {
        shellShadowView.frame = targetFrame
        shellContentView.layer.cornerRadius = 0
    }
}

private func animateClosingTransition(completion: @escaping () -> Void) {
    if let targetFrame {
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
            delay: 0,
            options: [.beginFromCurrentState, Self.animationOptions(for: BoardListCanvasTransitionConfiguration.closingAnimation.curve)]
        ) {
            shellShadowView.frame = targetFrame
        } completion: { _ in
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                delay: 0,
                options: [Self.animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
            ) {
                shellShadowView.alpha = 0
            } completion: { _ in
                completion()
            }
        }
        return
    }
}

private static func animationOptions(
    for curve: BoardListCanvasTransitionTimingCurve
) -> UIView.AnimationOptions {
    switch curve {
    case .easeInOut:
        return .curveEaseInOut
    case .easeOut:
        return .curveEaseOut
    }
}
```

## 修改二：macOS carrier 将 `timingFunctionName(for:)` 同步改为静态 helper

### 修改前

- `macOSSnapshotShellCarrier` 中的 `timingFunctionName(for:)` 也还是实例方法。
- 当前虽然先暴露的是 iOS 报错，但 macOS 侧保持同样写法，后续仍可能在同类闭包调用下继续出现显式捕获问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateOpeningTransition(completion:) / animateClosingTransition(completion:) / timingFunctionName(for:)
// 功能说明: 修改前 macOS carrier 与 iOS 一样，闭包里直接调用实例 helper 来解析 CAMediaTimingFunctionName。
private func animateOpeningTransition(completion: @escaping () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = BoardListCanvasTransitionConfiguration.openingAnimation.duration
        context.timingFunction = CAMediaTimingFunction(
            name: timingFunctionName(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)
        )
        shellShadowView.animator().frame = targetFrame
    } completionHandler: {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BoardListCanvasTransitionConfiguration.handoffAnimation.duration
            context.timingFunction = CAMediaTimingFunction(
                name: timingFunctionName(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve)
            )
            shellShadowView.animator().alphaValue = 0
        }
    }
}

private func timingFunctionName(
    for curve: BoardListCanvasTransitionTimingCurve
) -> CAMediaTimingFunctionName {
    switch curve {
    case .easeInOut:
        return .easeInEaseOut
    case .easeOut:
        return .easeOut
    }
}
```

### 修改后

- `timingFunctionName(for:)` 改成 `private static func`。
- 所有 `CAMediaTimingFunction(name: ...)` 调用统一改为 `Self.timingFunctionName(for: ...)`。
- 这样双端 helper 的语义保持一致，也把同类 capture 问题一次性清掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: animateOpeningTransition(completion:) / animateClosingTransition(completion:) / timingFunctionName(for:)
// 功能说明: 修改后 macOS carrier 同步把 timing helper 静态化，与 iOS 的修复策略保持同构，避免另一端残留同类隐式捕获。
private func animateOpeningTransition(completion: @escaping () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = BoardListCanvasTransitionConfiguration.openingAnimation.duration
        context.timingFunction = CAMediaTimingFunction(
            name: Self.timingFunctionName(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)
        )
        shellShadowView.animator().frame = targetFrame
    } completionHandler: {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BoardListCanvasTransitionConfiguration.handoffAnimation.duration
            context.timingFunction = CAMediaTimingFunction(
                name: Self.timingFunctionName(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve)
            )
            shellShadowView.animator().alphaValue = 0
        }
    }
}

private static func timingFunctionName(
    for curve: BoardListCanvasTransitionTimingCurve
) -> CAMediaTimingFunctionName {
    switch curve {
    case .easeInOut:
        return .easeInEaseOut
    case .easeOut:
        return .easeOut
    }
}
```

## 影响范围说明

- 本次修复不改变 opening / closing 动画的时长、曲线、圆角、阴影或 fallback 行为。
- 本次修复不改变 `Phase 6` 的输入冻结机制。
- 本次修复只调整 helper 的调用语义和声明方式，使其不再依赖实例捕获。

## 验证

- 已对以下文件执行 `ReadLints`，无报错：
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
- 已执行：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift"`
- 上述语法检查通过。
- 未执行 git commit。
