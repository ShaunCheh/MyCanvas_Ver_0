# 20260318_165001_ios_context_menu_top_left_fix_record

## 记录范围

- 记录目标：
  1. 记录这次 `iOS` 上下文菜单“视觉上固定在左上角”的完整排查链路。
  2. 记录早期几次必要但未命中最终根因的修复。
  3. 记录为定位问题逐层补充的日志，以及如何根据日志排除错误方向。
  4. 记录最终真正修掉问题的改动。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 不包含：
  - 原始 gif diff
  - git commit

## 问题现象

- 用户在 `iOS` 上长按后，菜单视觉上总是出现在左上角。
- 早期直觉容易把问题归因到：
  - 触点坐标不对
  - 菜单锚点算错
  - `safeBounds / occupiedRects` 转换错误
  - 共享 layout solver 把菜单 clamp 到了左上角
- 最终日志证明：这些方向只解释了一部分现象，但**最终根因并不在 solver，而在 iOS 宿主视图的外层菜单容器布局责任混用**。

## 一、早期失败但必要的修复

### 1. 共享锚点语义：让 body 菜单跟随真实触点

这一步修的是“菜单跟着 item 中心，而不是跟着手指”的问题。它是必要修复，但还不是“左上角”问题的最终根因。

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: CanvasContextMenuContext.anchorPoint
// 功能说明: 修改前只要存在 anchorRect，就统一取几何中心，body/outline 菜单也会偏向对象中心。
var anchorPoint: CGPoint {
    guard let anchorRect else {
        return invocationViewportPoint
    }

    return CGPoint(
        x: anchorRect.midX,
        y: anchorRect.midY
    )
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
// 函数名/类型名: CanvasContextMenuContext.anchorPoint
// 功能说明: 修改后按 targetKind 区分菜单锚点语义，body/outline/blank 跟随真实触点，handle 继续跟随几何中心。
var anchorPoint: CGPoint {
    switch targetKind {
    case .rotateHandle, .cropHandle, .selectionHandle:
        guard let anchorRect else {
            return invocationViewportPoint
        }

        return CGPoint(
            x: anchorRect.midX,
            y: anchorRect.midY
        )
    case .cropOutline, .selectedItemBody, .unselectedItemBody, .blank:
        // Body/outline menus should follow the actual invocation point instead
        // of the item's geometric center so the menu feels attached to the click.
        return invocationViewportPoint
    }
}
```

#### 结论

- 这一步解决的是“锚点语义错误”，让菜单的目标点不再漂向 item 中心。
- 但后续日志显示，即使 `anchorPoint` 已经正确，菜单最终仍可能视觉上跑到左上角，所以这不是最终根因。

### 2. iOS controller：展示前统一桥接到 host 坐标系

这一步修的是“viewport / overlay / host 使用不同坐标系”的问题。它保证共享宿主只吃一种坐标语义。

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / updateContextMenuPresentation()
// 功能说明: 修改前 controller 直接把上下文和 chrome 几何交给宿主，没有先统一转换到 contextMenuHostView 坐标系。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs,
        context: resolvedContext
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}

private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: chromeSafeBounds(),
        occupiedRects: chromeOccupiedRects()
    )
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: presentContextMenu(for:) / contextMenuLayoutAnchorPoint(for:) / contextMenuSafeBounds() / contextMenuOccupiedRects()
// 功能说明: 修改后 controller 负责把 anchorPoint、safeBounds、occupiedRects 都桥接到 contextMenuHostView 坐标系。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs,
        context: resolvedContext
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
        commandStates: commandStates
    )
}

private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: contextMenuSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}

private func contextMenuLayoutAnchorPoint(
    for resolvedContext: CanvasContextMenuContext
) -> CGPoint {
    convertToContextMenuHost(
        resolvedContext.anchorPoint,
        from: canvasViewportView
    )
}

private func contextMenuSafeBounds() -> CGRect {
    convertToContextMenuHost(
        chromeSafeBounds(),
        from: chromeOverlayView
    )
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }

    return rects.map { rect in
        convertToContextMenuHost(rect, from: chromeOverlayView)
    }
}
```

#### 结论

- 这一步解决的是“菜单输入几何语义不统一”的问题。
- 之后的 `ContextMenuPosition` 日志已经能看到 `layoutAnchorPoint`、`safeBounds`、`occupiedRects` 都是正确的 host 坐标。
- 但菜单仍然会视觉上跑到左上角，所以根因还在更后面的宿主布局链路。

### 3. 共享 solver：支持固定右侧、允许覆盖 chrome、iOS 特定场景不 clamp

这一步修的是“菜单被过早翻面、避让 chrome、或被边界回推”的问题。它也不是最终根因，但它确保了 solver 本身输出的是对的。

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutSolver.resolveMenuFrame(...)
// 功能说明: 修改前 occupiedRects 恒定作为 blocker，候选方向也更多依赖中线偏好与默认 clamp 行为。
let blockerRects = occupiedRects
    .map(\.standardized)
    .filter { $0.isEmpty == false }
    .map {
        $0.insetBy(
            dx: -configuration.chromeClearance,
            dy: -configuration.chromeClearance
        )
    }

let prefersTrailing = anchorPoint.x < layoutBounds.midX
let prefersBottom = anchorPoint.y < layoutBounds.midY
let placements = candidatePlacements(
    prefersTrailing: prefersTrailing,
    prefersBottom: prefersBottom
)
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutSolver.resolveMenuFrame(...) / preferredPlacements(...) / shouldClamp(...)
// 功能说明: 修改后支持 allowChromeOverlap、fixedRightOfAnchor，以及 iOS 固定右侧候选不做 clamp。
switch configuration.occlusionPolicy {
case .avoidOverlayChrome:
    blockerRects = occupiedRects
        .map(\.standardized)
        .filter { $0.isEmpty == false }
        .map {
            $0.insetBy(
                dx: -configuration.chromeClearance,
                dy: -configuration.chromeClearance
            )
        }
    placements = candidatePlacements(
        for: configuration.placementStyle,
        around: anchorPoint,
        size: resolvedSize,
        within: layoutBounds,
        anchorSpacing: configuration.anchorSpacing,
        configuration: configuration
    )
case .allowChromeOverlap:
    blockerRects = []
    placements = preferredPlacements(for: configuration.placementStyle)
}

private func preferredPlacements(
    for placementStyle: CanvasContextMenuPlacementStyle
) -> [Placement] {
    switch placementStyle {
    case .fixedRightOfAnchor:
        return [
            Placement(
                horizontalAlignment: .trailing,
                verticalAlignment: .anchored,
                defaultPreferenceRank: 0
            )
        ]
    default:
        return []
    }
}

private func shouldClamp(
    placement: Placement,
    configuration: CanvasContextMenuLayoutConfiguration
) -> Bool {
    switch configuration.placementStyle {
    case .cursorPreferred, .fingerPreferred:
        return true
    case .fixedRightOfAnchor:
        break
    }

    switch (placement.horizontalAlignment, placement.verticalAlignment) {
    case (.trailing, .anchored):
        return false
    default:
        return true
    }
}
```

#### 宿主默认策略

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.layoutConfiguration
// 功能说明: iOS 宿主默认使用 fixedRightOfAnchor + allowChromeOverlap，让菜单优先固定在触点右侧并覆盖 chrome。
private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
    var configuration = CanvasContextMenuLayoutConfiguration()
    configuration.occlusionPolicy = .allowChromeOverlap
    configuration.placementStyle = .fixedRightOfAnchor
    return configuration
}()
```

#### 结论

- 这一步把 solver 的行为收敛到了用户想要的方向：固定右侧、允许覆盖悬浮按钮和 minimap、指定候选不 clamp。
- 后续日志已经证明 `resolvedMenuFrame` 本身是正确的，所以 solver 不是最终根因。

## 二、为了定位问题逐层添加的日志

### 1. 输入层日志：先确认长按触点有没有错

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: handleLongPress(at:)
// 功能说明: 修改前长按链路没有输出输入位置日志，无法确认手势输入和各层 view 几何是否正常。
private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    prepareForLongPressContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: handleLongPress(at:)
// 功能说明: 修改后先输出触点、viewport、overlay 的几何信息，确认原始输入不是左上角。
private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    print(
        "[Canvas iOS][ContextMenuInput] " +
        "longPressLocation=\(describe(point: location)) " +
        "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
        "overlayFrame=\(describe(rect: chromeOverlayView.frame))"
    )
    prepareForLongPressContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

### 2. 展示层日志：确认上下文解析和 host 坐标桥接是否正确

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: presentContextMenu(for:)
// 功能说明: 修改前只负责生成命令，不输出 target、anchorPoint、layoutAnchorPoint、safeBounds 等关键展示数据。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs,
        context: resolvedContext
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
        commandStates: commandStates
    )
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: logContextMenuPresentation(resolvedContext:commandIDs:)
// 功能说明: 修改后输出 target、anchorPoint、layoutAnchorPoint、safeBounds、occupiedRects，确认 solver 输入链路无误。
private func logContextMenuPresentation(
    resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let occupiedRectsDescription = contextMenuOccupiedRects()
        .map(describe(rect:))
        .joined(separator: ", ")
    let commandIDsDescription = commandIDs.map(\.rawValue).joined(separator: ",")
    let layoutAnchorPoint = contextMenuLayoutAnchorPoint(
        for: resolvedContext
    )

    print(
        "[Canvas iOS][ContextMenuPosition] " +
        resolvedContext.debugSummary + " " +
        "viewportBounds=\(describe(rect: canvasViewportView.bounds)) " +
        "viewportFrame=\(describe(rect: canvasViewportView.frame)) " +
        "overlayBounds=\(describe(rect: chromeOverlayView.bounds)) " +
        "overlayFrame=\(describe(rect: chromeOverlayView.frame)) " +
        "hostBounds=\(describe(rect: contextMenuHostView.bounds)) " +
        "hostFrame=\(describe(rect: contextMenuHostView.frame)) " +
        "layoutAnchorPoint=\(describe(point: layoutAnchorPoint)) " +
        "safeBounds=\(describe(rect: contextMenuSafeBounds())) " +
        "occupiedRects=[\(occupiedRectsDescription)] " +
        "commandIDs=[\(commandIDsDescription)]"
    )
}
```

### 3. 宿主运行时深日志：最终把“左上角”根因钉死

#### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.updateLayout(safeBounds:occupiedRects:)
// 功能说明: 修改前宿主只输出 solver 结果，没有继续观察 menuContainerView、contentView、commandStackView 在下一轮布局后的真实 frame。
func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: layoutConfiguration
    ) else {
        menuContainerView.frame = .zero
        return
    }

    menuContainerView.frame = menuFrame.integral
}
```

#### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.updateLayout(safeBounds:occupiedRects:) / logRuntimeState(reason:)
// 功能说明: 修改后宿主持续输出 menuContainerView、contentView、commandStackView、按钮尺寸与 window 坐标，观察后续布局有没有把菜单挪走。
func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    guard let currentState else {
        return
    }

    let preferredSize = preferredMenuSize()
    guard let menuFrame = layoutSolver.resolveMenuFrame(
        anchorPoint: currentState.layoutAnchorPoint,
        preferredSize: preferredSize,
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: layoutConfiguration
    ) else {
        updateMenuContainerConstraints(.zero)
        return
    }

    updateMenuContainerConstraints(menuFrame.integral)
    layoutIfNeeded()
    logRuntimeState(reason: "updateLayout")
    DispatchQueue.main.async { [weak self] in
        self?.logRuntimeState(reason: "asyncAfterUpdateLayout")
    }
}

private func logRuntimeState(reason: String) {
    let contentView = menuContainerView.contentView
    let menuFrame = menuContainerView.frame.standardized
    let contentViewFrame = contentView.frame.standardized
    let commandStackFrameInMenu = commandStackView.frame.standardized
    let commandStackFittingSize = commandStackView.systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize
    )
    let arrangedSubviewStates = commandStackView.arrangedSubviews
        .enumerated()
        .map { index, view -> String in
            [
                "index=\(index)",
                "frame=\(contextMenuHostDescribe(view.frame.standardized))",
                "intrinsic=\(contextMenuHostDescribe(view.intrinsicContentSize))",
                "ambiguous=\(view.hasAmbiguousLayout)"
            ].joined(separator: " ")
        }
        .joined(separator: " || ")

    print(
        "[Canvas iOS][ContextMenuRuntime] " +
        "reason=\(reason) " +
        "menuFrame=\(contextMenuHostDescribe(menuFrame)) " +
        "contentViewFrame=\(contextMenuHostDescribe(contentViewFrame)) " +
        "commandStackFrameInMenu=\(contextMenuHostDescribe(commandStackFrameInMenu)) " +
        "commandStackFittingSize=\(contextMenuHostDescribe(commandStackFittingSize)) " +
        "arrangedSubviews=[\(arrangedSubviewStates)]"
    )
}
```

## 三、关键日志分析：为什么前几轮修复都没真正命中根因

### 1. solver 输出其实已经不是左上角

```text
# 日志来源: iOS 运行时日志
# 日志标签: [Canvas iOS][ContextMenuLayout]
# 功能说明: 这条日志证明共享 solver 输出的 resolvedMenuFrame 已经在触点右侧，不是左上角。
[Canvas iOS][ContextMenuLayout] target=selectedItemBody invocationViewportPoint={281.56, 509.20} layoutAnchorPoint={281.56, 509.20} safeBounds={{0.00, 62.00}, {440.00, 860.00}} preferredSize={168.00, 392.00} resolvedMenuFrame={{291.56, 509.20}, {180.00, 392.00}} occupiedRects=[{{332.00, 638.00}, {88.00, 264.00}}, {{16.00, 774.00}, {180.00, 132.00}}] commandIDs=[crop,duplicateItem,deleteItem,bringItemForward,sendItemBackward,bringItemToFront,sendItemToBack,clearSelection,undo]
```

结论：

- `layoutAnchorPoint` 是对的。
- `resolvedMenuFrame` 也是对的。
- 所以“菜单出现在左上角”不是因为 solver 把结果算成了 `(0, 0)`。

### 2. 第一拍看到 `commandStackView = 0x0`，这不是最终根因

```text
# 日志来源: iOS 运行时日志
# 日志标签: [Canvas iOS][ContextMenuRuntime] reason=updateLayout
# 功能说明: 这条日志说明 updateLayout 当帧里 menuContainerView 已经在正确位置，但内部 stack 还没有完成最终布局。
[Canvas iOS][ContextMenuRuntime] reason=updateLayout hostFrame={{0.00, 0.00}, {440.00, 956.00}} menuFrame={{291.00, 509.00}, {181.00, 393.00}} contentViewFrame={{0.00, 0.00}, {181.00, 393.00}} commandStackFrameInMenu={{10.00, 10.00}, {0.00, 0.00}} commandStackFittingSize={148.00, 372.00} arrangedSubviewCount=9
```

结论：

- 早期看到 `commandStackFrameInMenu = {0,0}`，容易误判为“内容布局坏了，所以看起来像左上角”。
- 但 `commandStackFittingSize` 已经不是零，说明按钮尺寸其实已经能算出来。
- 这条日志只能说明“首拍日志太早”，还不能解释为什么视觉上固定在左上角。

### 3. 真正把问题钉死的是下一拍日志

```text
# 日志来源: iOS 运行时日志
# 日志标签: [Canvas iOS][ContextMenuRuntime] reason=asyncAfterUpdateLayout
# 功能说明: 这条日志说明下一轮布局后，按钮已经正常排出来了，但外层 menuContainerView 被放回了左上角。
[Canvas iOS][ContextMenuRuntime] reason=asyncAfterUpdateLayout hostFrame={{0.00, 0.00}, {440.00, 956.00}} menuFrame={{0.00, 0.00}, {168.00, 392.00}} contentViewFrame={{0.00, 0.00}, {168.00, 392.00}} commandStackFrameInMenu={{10.00, 10.00}, {148.00, 372.00}} commandStackFittingSize={148.00, 372.00} arrangedSubviewCount=9
```

这条日志把根因完全钉死了：

- 第一拍：`menuFrame` 正确，`commandStackView` 还没完全布局。
- 第二拍：`commandStackView` 和按钮都正常了，但 `menuFrame` 变成了 `{{0,0}, ...}`。
- 所以真正的问题不是按钮没生成，也不是 solver 算错，而是**外层菜单容器在后续布局时被重新放回了 `(0, 0)`**。

## 四、最终根因修复：iOS 宿主外层菜单容器不再混用 frame 和 Auto Layout

最终根因在 `CanvasContextMenuHostView` 的 `iOS` 分支：

- `menuContainerView.translatesAutoresizingMaskIntoConstraints = false`
- 但外层位置和尺寸又通过 `menuContainerView.frame = ...` 手动写入
- 下一轮 UIKit 布局时，外层容器位置被重新接管，最终掉回 `(0, 0)`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.init(frame:) / updateLayout(safeBounds:occupiedRects:) / dismiss()
// 功能说明: 修改前 menuContainerView 自身没有一套明确的外层定位约束，却又在运行时直接写 frame，形成布局责任混用。
override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear
    isHidden = true
    isUserInteractionEnabled = true

    menuContainerView.translatesAutoresizingMaskIntoConstraints = false
    menuContainerView.layer.cornerRadius = 16
    menuContainerView.clipsToBounds = true
    menuContainerView.isHidden = true

    commandStackView.translatesAutoresizingMaskIntoConstraints = false
    commandStackView.axis = .vertical
    commandStackView.alignment = .fill
    commandStackView.distribution = .fill
    commandStackView.spacing = 6

    addSubview(menuContainerView)
    menuContainerView.contentView.addSubview(commandStackView)
    NSLayoutConstraint.activate([
        commandStackView.topAnchor.constraint(equalTo: menuContainerView.contentView.topAnchor, constant: 10),
        commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.contentView.leadingAnchor, constant: 10),
        commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.contentView.trailingAnchor, constant: -10),
        commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.contentView.bottomAnchor, constant: -10)
    ])
}

func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    // ...
    menuContainerView.frame = menuFrame.integral
}

func dismiss() {
    // ...
    menuContainerView.frame = .zero
    menuContainerView.isHidden = true
    isHidden = true
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.init(frame:) / updateLayout(safeBounds:occupiedRects:) / updateMenuContainerConstraints(_:) / dismiss()
// 功能说明: 修改后外层 menuContainerView 的位置和尺寸都由宿主持有的四个约束驱动，内部 commandStackView 继续使用 Auto Layout。
private var menuLeadingConstraint: NSLayoutConstraint!
private var menuTopConstraint: NSLayoutConstraint!
private var menuWidthConstraint: NSLayoutConstraint!
private var menuHeightConstraint: NSLayoutConstraint!

override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear
    isHidden = true
    isUserInteractionEnabled = true

    menuContainerView.translatesAutoresizingMaskIntoConstraints = false
    menuContainerView.layer.cornerRadius = 16
    menuContainerView.clipsToBounds = true
    menuContainerView.isHidden = true

    commandStackView.translatesAutoresizingMaskIntoConstraints = false
    commandStackView.axis = .vertical
    commandStackView.alignment = .fill
    commandStackView.distribution = .fill
    commandStackView.spacing = 6

    addSubview(menuContainerView)
    menuContainerView.contentView.addSubview(commandStackView)
    menuLeadingConstraint = menuContainerView.leadingAnchor.constraint(equalTo: leadingAnchor)
    menuTopConstraint = menuContainerView.topAnchor.constraint(equalTo: topAnchor)
    menuWidthConstraint = menuContainerView.widthAnchor.constraint(equalToConstant: 0)
    menuHeightConstraint = menuContainerView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
        menuLeadingConstraint,
        menuTopConstraint,
        menuWidthConstraint,
        menuHeightConstraint,
        commandStackView.topAnchor.constraint(equalTo: menuContainerView.contentView.topAnchor, constant: 10),
        commandStackView.leadingAnchor.constraint(equalTo: menuContainerView.contentView.leadingAnchor, constant: 10),
        commandStackView.trailingAnchor.constraint(equalTo: menuContainerView.contentView.trailingAnchor, constant: -10),
        commandStackView.bottomAnchor.constraint(equalTo: menuContainerView.contentView.bottomAnchor, constant: -10)
    ])
}

func updateLayout(
    safeBounds: CGRect,
    occupiedRects: [CGRect]
) {
    // ...
    updateMenuContainerConstraints(menuFrame.integral)
    layoutIfNeeded()
    logRuntimeState(reason: "updateLayout")
}

func dismiss() {
    // ...
    updateMenuContainerConstraints(.zero)
    menuContainerView.isHidden = true
    isHidden = true
}

private func updateMenuContainerConstraints(_ frame: CGRect) {
    let standardizedFrame = frame.standardized
    menuLeadingConstraint.constant = standardizedFrame.minX
    menuTopConstraint.constant = standardizedFrame.minY
    menuWidthConstraint.constant = max(0, standardizedFrame.width)
    menuHeightConstraint.constant = max(0, standardizedFrame.height)
}
```

### 修复后的职责分层

- 外层 `menuContainerView`
  - 只由宿主内部四个约束控制位置和尺寸
  - 不再同时接受“手动写 frame + UIKit 后续重排”的混用状态
- 内层 `commandStackView`
  - 继续使用 Auto Layout
  - 负责内容尺寸和按钮纵向分布
- `CanvasContextMenuLayoutSolver`
  - 继续只负责产出目标 `CGRect`
  - 不承担宿主内部视图树的后续布局副作用

## 五、最终结论

- 早期几轮修复并不是无效修改，而是分别修正了：
  - 触点与锚点语义
  - host 坐标桥接
  - iOS 菜单的固定右侧策略
  - chrome 覆盖与 clamp 策略
- 这些修复让 solver 输出越来越接近正确，也让日志链路足够完整。
- 真正把“菜单固定在左上角”钉死并修掉的，是最后这次 `iOS CanvasContextMenuHostView` 外层容器布局责任收敛：
  - **不是 solver 算成左上角**
  - **不是命令按钮没生成**
  - **而是外层 menuContainerView 在下一轮布局被 UIKit 放回了 `(0, 0)`**

## 当前结果

- `iOS` 菜单已经恢复正常，不再固定显示在左上角。
- 此阶段保留了较深的运行时日志，便于后续继续观察；如果后续确认稳定，可以再收敛日志噪音。
- 本次改动后，`iOS Simulator` 与 `macOS` 目标均已通过编译验证。
