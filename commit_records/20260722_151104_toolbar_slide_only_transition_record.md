# 20260722_151104_工具条切换改为完整滑入滑出记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚将编辑态 / 阅读态切换时的工具条动画，从“收缩 / 展开 + 滑入 / 滑出”临时改为“完整工具条直接滑入 / 滑出”的修改。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 1. Slide 阶段保持完整工具条内容可见

### 修改前

`exiting` / `entering` 阶段是围绕 collapsed 小形态设计的，内容透明度为 `0`，内容缩放为 `minimumScale`。因此如果直接跳过收缩/展开，滑入/滑出阶段会看起来像内容不可见或被缩小。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: presentation(for:context:)
// 功能说明: 修改前 exiting 阶段隐藏内容，并使用 minimumScale，适合 collapsed 小形态滑出。
case let .exiting(progress):
    let t = clamped(progress)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedRect(
            from: frames.collapsedFrame,
            to: frames.offscreenFrame,
            progress: t
        ),
        itemStates: visibleState.items,
        showsBackground: visibleState.showsBackground,
        contentAlpha: 0,
        contentScale: minimumScale,
        keepsHostVisible: true,
        isInteractive: false
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: presentation(for:context:)
// 功能说明: 修改前 entering 阶段同样隐藏内容，并使用 minimumScale，进入后再交给 expanding 展开。
case let .entering(progress):
    let t = clamped(progress)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedRect(
            from: frames.offscreenFrame,
            to: frames.collapsedFrame,
            progress: t
        ),
        itemStates: visibleState.items,
        showsBackground: visibleState.showsBackground,
        contentAlpha: 0,
        contentScale: minimumScale,
        keepsHostVisible: true,
        isInteractive: false
    )
```

### 修改后

`exiting` / `entering` 阶段保持 `contentAlpha = 1`、`contentScale = 1`，让完整工具条整体滑入 / 滑出。`collapsing` / `expanding` 的代码和 stage 没有删除，只是当前流程暂时不主动使用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: presentation(for:context:)
// 功能说明: 修改后 exiting 阶段以完整内容和原始 scale 滑出。
case let .exiting(progress):
    let t = clamped(progress)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedRect(
            from: frames.collapsedFrame,
            to: frames.offscreenFrame,
            progress: t
        ),
        itemStates: visibleState.items,
        showsBackground: visibleState.showsBackground,
        contentAlpha: 1,
        contentScale: 1,
        keepsHostVisible: true,
        isInteractive: false
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: presentation(for:context:)
// 功能说明: 修改后 entering 阶段以完整内容和原始 scale 滑入。
case let .entering(progress):
    let t = clamped(progress)
    return CanvasToolbarTransitionPresentation(
        frame: interpolatedRect(
            from: frames.offscreenFrame,
            to: frames.collapsedFrame,
            progress: t
        ),
        itemStates: visibleState.items,
        showsBackground: visibleState.showsBackground,
        contentAlpha: 1,
        contentScale: 1,
        keepsHostVisible: true,
        isInteractive: false
    )
```

## 2. iOS transition frame 改为完整工具条尺寸

### 修改前

iOS 在准备 transition context 时，会把 `visibleFrame` 先转成 `collapsedFrame`，再用 collapsed 小形态计算 offscreen frame。这样滑入/滑出的主体是 collapsed 小形态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改前 toReading 使用 collapsed 小形态作为滑出起点。
let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
    from: visibleFrame
)
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    placement: visibleState.placement
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改前 toEditing 也先计算 collapsed 小形态，再从屏幕外进入 collapsed 状态。
let visibleFrame = resolvedSteadyToolbarFrame(for: visibleState)
let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
    from: visibleFrame
)
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    placement: visibleState.placement
)
```

### 修改后

iOS 暂时让 `collapsedFrame = visibleFrame`。这样保留了 transition frames 的结构，但 slide 的起止 frame 都按完整工具条尺寸计算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后 toReading 使用完整工具条 frame 作为滑出起点。
let collapsedFrame = visibleFrame
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    placement: visibleState.placement
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后 toEditing 从屏幕外以完整工具条尺寸滑入。
let visibleFrame = resolvedSteadyToolbarFrame(for: visibleState)
let collapsedFrame = visibleFrame
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    placement: visibleState.placement
)
```

## 3. iOS 切换流程跳过 collapse / expand

### 修改前

从阅读态切回编辑态时，`entering` 完成后继续调用 `runToolbarCollapsePhase()`，在 `.toEditing` 分支里实际进入 `expanding`，完成展开后才 finish。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: runToolbarSlidePhase()
// 功能说明: 修改前 toEditing 是 entering 后接 expanding。
case .toEditing:
    targetStage = .entering(progress: 1)
    completion = { [weak self] in
        self?.runToolbarCollapsePhase()
    }
}
```

同时，初始阶段判断会让 `toReading` 从 `.collapsing(progress: 0)` 开始。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改前 toReading 默认先进入 collapsing。
guard let currentPresentation = toolbarTransitionRuntime?.currentPresentation else {
    switch direction {
    case .toReading:
        return .collapsing(progress: 0)
    case .toEditing:
        return .entering(progress: 0)
    }
}
```

### 修改后

`toEditing` 的 `entering` 完成后直接 finish，不再接 `expanding`；`toReading` 默认直接从 `exiting` 开始。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: runToolbarSlidePhase()
// 功能说明: 修改后 toEditing 只做 entering，完成后直接应用 settledState。
case .toEditing:
    targetStage = .entering(progress: 1)
    completion = { [weak self] in
        guard let self else {
            return
        }
        self.finishToolbarModeTransition(
            applying: runtime.context.settledState
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改后 toReading 默认直接进入 exiting。
guard let currentPresentation = toolbarTransitionRuntime?.currentPresentation else {
    switch direction {
    case .toReading:
        return .exiting(progress: 0)
    case .toEditing:
        return .entering(progress: 0)
    }
}
```

## 4. iOS 中断/反向切换的阶段推断改为 slide-only

### 修改前

`initialToolbarTransitionStage(for:context:)` 会根据当前 frame 判断是否还处于 collapsing / expanding，并可能返回 `.collapsing` 或 `.expanding`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改前中断切换时可能回到 collapsing 或 expanding。
case .toReading:
    let isCollapsed = toolbarExpansionExtent(
        currentFrame,
        for: placement
    ) <= (toolbarExpansionExtent(collapsedFrame, for: placement) + 0.5)
    if isCollapsed {
        return .exiting(...)
    }

    return .collapsing(progress: 0)

case .toEditing:
    if toolbarExpansionExtent(
        currentFrame,
        for: placement
    ) > (toolbarExpansionExtent(collapsedFrame, for: placement) + 0.5) {
        return .expanding(progress: expandingProgress)
    }
    return .entering(progress: enteringProgress)
```

### 修改后

阶段推断只在 slide 上计算 progress。`toReading` 永远返回 `.exiting(...)`；`toEditing` 接近完成时返回 `.steadyVisible`，否则返回 `.entering(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改后中断/反向切换也只在 entering/exiting 之间恢复进度。
case .toReading:
    return .exiting(
        progress: toolbarLinearProgress(
            from: toolbarSlideCoordinate(collapsedFrame, for: placement),
            to: toolbarSlideCoordinate(
                context.frames.offscreenFrame,
                for: placement
            ),
            current: toolbarSlideCoordinate(currentFrame, for: placement)
        )
    )

case .toEditing:
    let enteringProgress = toolbarLinearProgress(
        from: toolbarSlideCoordinate(context.frames.offscreenFrame, for: placement),
        to: toolbarSlideCoordinate(collapsedFrame, for: placement),
        current: toolbarSlideCoordinate(currentFrame, for: placement)
    )
    if enteringProgress >= 0.999 {
        return .steadyVisible
    }

    return .entering(progress: enteringProgress)
```

## 5. macOS 同步改为完整工具条滑入 / 滑出

### 修改前

macOS 也会先计算 collapsed 小形态，并通过 `hiddenFrame(...)` 计算隐藏位置；`toEditing` 的 entering 结束后继续进入 expanding。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改前 macOS 使用 collapsed 小形态和 hiddenFrame 进行隐藏/进入。
let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
    from: visibleFrame
)
let offscreenFrame = CanvasToolbarTransitionGeometry.hiddenFrame(
    for: visibleState.placement,
    visibleFrame: visibleFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    scale: toolbarPlacementScale(),
    baseChromeBlockers: baseChromeBlockersForToolbarLayout(),
    solver: toolbarPlacementSolver
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: runToolbarSlidePhase()
// 功能说明: 修改前 macOS toEditing 是 entering 后接 expanding。
case .toEditing:
    targetStage = .entering(progress: 1)
    completion = { [weak self] in
        self?.runToolbarCollapsePhase()
    }
}
```

### 修改后

macOS 与 iOS 保持同构：`collapsedFrame = visibleFrame`，offscreen frame 按完整工具条尺寸计算，entering 完成后直接 finish。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: prepareToolbarTransitionContext(direction:)
// 功能说明: 修改后 macOS 使用完整工具条 frame 计算滑入/滑出。
let collapsedFrame = visibleFrame
let offscreenFrame = CanvasToolbarTransitionGeometry.offscreenFrame(
    from: collapsedFrame,
    safeBounds: toolbarLayoutSafeBounds(),
    placement: visibleState.placement
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: runToolbarSlidePhase()
// 功能说明: 修改后 macOS toEditing 只做 entering，完成后直接应用 settledState。
case .toEditing:
    targetStage = .entering(progress: 1)
    completion = { [weak self] in
        guard let self else {
            return
        }
        self.finishToolbarModeTransition(
            applying: runtime.context.settledState
        )
    }
}
```

## 6. macOS 阶段推断改为 slide-only

### 修改前

macOS 的 `initialToolbarTransitionStage(for:context:)` 也会判断 collapsed / expanded，并可能返回 `.collapsing` 或 `.expanding`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改前 macOS 中断恢复可能继续收缩或展开。
case .toReading:
    let isCollapsed = currentFrame.height <= (collapsedFrame.height + 0.5)
    if isCollapsed {
        return .exiting(...)
    }

    return .collapsing(progress: 0)

case .toEditing:
    if currentFrame.height > (collapsedFrame.height + 0.5) {
        return .expanding(progress: expandingProgress)
    }
    return .entering(progress: enteringProgress)
```

### 修改后

macOS 也只根据 slide 坐标恢复 `.exiting` 或 `.entering`；entering 接近完成时返回 `.steadyVisible`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改后 macOS 中断/反向切换只恢复滑动进度。
case .toReading:
    return .exiting(
        progress: toolbarLinearProgress(
            from: collapsedFrame.minX,
            to: context.frames.offscreenFrame.minX,
            current: currentFrame.minX
        )
    )

case .toEditing:
    let enteringProgress = toolbarLinearProgress(
        from: context.frames.offscreenFrame.minX,
        to: collapsedFrame.minX,
        current: currentFrame.minX
    )
    if enteringProgress >= 0.999 {
        return .steadyVisible
    }

    return .entering(progress: enteringProgress)
```

## 验证情况

已执行并通过：

- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'`

创建本记录前，当前 `git status --short` 显示本次代码改动为：

- `M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
- `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

本次仅创建记录文件，没有提交 commit。
