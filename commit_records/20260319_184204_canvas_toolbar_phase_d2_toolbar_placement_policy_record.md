# 20260319_184204_canvas_toolbar_phase_d2_toolbar_placement_policy_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段D-阶段2` 的实际代码变更。
- 本次实际产物：
- 扩展共享 `CanvasToolbarPlacement`，新增 `offsetAlongEdge`，让 placement contract 能表达“沿当前停靠边滑动”的输入。
- 新增共享 `CanvasToolbarPlacementConfiguration` 与 `CanvasToolbarPlacementSolver`，输入复用 `D1` 已统一的 `CanvasChromeLayoutContext`，输出明确的 `resolvedFrame`。
- `iOS/macOS` 控制器不再维护 `toolbarDockConstraints` / `makeToolbarDockConstraints(...)` 这套四边约束分支，而是在 `updateChromeOverlayLayout()` 中先求解并应用工具栏 frame。
- `toolbarHostView` 外层从“靠 Auto Layout 锚到四边”切换为“solver 出 frame”；host 内部按钮排布仍保持现有 Auto Layout。
- 首版 placement policy 保持“以当前边为主”：只在首选边上做 offset clamp 与沿边滑动，不自动跨边切换。
- 本次未执行：
- 未实现跨边自动切换策略。
- 未增加用户可调 `offsetAlongEdge` 的交互入口，当前仍是代码侧输入。
- 未修改 minimap solver 的核心放置算法。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 到 `D1` 结束时，工具栏虽然已经拥有共享 `CanvasChromeLayoutContext`，但“工具栏自身放哪儿”这件事仍主要依赖 controller 里的四边约束分支。
- 共享层的 `CanvasToolbarPlacement` 只能表达 `dockEdge + dockAlignment`，还不能显式表达“沿当前边偏移多少”。
- 项目里还没有独立的 toolbar placement solver 文件；工具栏 frame 不是共享层求解结果，而是控制器用 Auto Layout 间接拼出来的。

### Shared Placement Contract 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarPlacement
// 功能说明: 修改前共享 placement 只知道停靠边和对齐方式，还不能表达沿当前边滑动的 offset。
import Foundation

struct CanvasToolbarPlacement: Hashable, Sendable {
    var dockEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment

    init(
        dockEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered
    ) {
        self.dockEdge = dockEdge
        self.dockAlignment = dockAlignment
    }
}
```

### Shared Toolbar Solver 新增前状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift
// 函数名/类型名: 文件级共享 toolbar placement solver
// 功能说明: 修改前该文件不存在；项目里还没有独立的 CanvasToolbarPlacementSolver 来消费 safeBounds / occupiedRects / measuredSize 并直接输出 resolvedFrame。
// 该文件在阶段D-阶段2之前尚未创建。
```

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarDockConstraints / updatePreparedToolbarDockEdge() / makeToolbarDockConstraints(in:)
// 功能说明: 修改前 iOS 依赖约束组激活/失活决定工具栏位置，placement 逻辑仍散落在 controller 的 switch 分支里。
private var toolbarDockConstraints: [NSLayoutConstraint] = []

private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func makeToolbarDockConstraints(
    in safeAreaLayoutGuide: UILayoutGuide
) -> [NSLayoutConstraint] {
    switch toolbarDockEdge {
    case .top:
        [
            toolbarHostView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .bottom:
        [
            toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .leading:
        [
            toolbarHostView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    case .trailing:
        [
            toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    }
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarDockConstraints / updatePreparedToolbarDockEdge() / makeToolbarDockConstraints(in:)
// 功能说明: 修改前 macOS 也通过四边约束分支来表达工具栏位置，placement policy 还没有沉到共享层。
private var toolbarDockConstraints: [NSLayoutConstraint] = []

private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func makeToolbarDockConstraints(
    in safeAreaLayoutGuide: NSLayoutGuide
) -> [NSLayoutConstraint] {
    switch toolbarDockEdge {
    case .top:
        [
            toolbarHostView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .bottom:
        [
            toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .leading:
        [
            toolbarHostView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    case .trailing:
        [
            toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    }
}
```

## 修改后

- 共享 placement contract 现在可以表达：
- `preferredEdge`
- `dockAlignment`
- `offsetAlongEdge`
- 新增 `CanvasToolbarPlacementSolver` 后，工具栏 placement 输入链已经变为：
- `safeBounds`
- `toolbarPreferredPlacement`
- `toolbarMeasuredSize`
- `occupiedRects(excluding: [.toolbar])`
- solver 首版策略会先在首选边内做 inset/clamp，再根据 blocker 推导候选沿边坐标，最后选择“重叠面积更小，且尽量靠近首选位置”的 frame。
- `iOS/macOS` 控制器都新增了：
- `toolbarOffsetAlongEdge`
- `toolbarPlacementSolver`
- `applyToolbarPlacement()`
- `toolbarHostView.translatesAutoresizingMaskIntoConstraints = true`
- 这样工具栏外层定位已经从 `switch toolbarDockEdge` 的约束模式切到 `resolvedFrame` 模式。

### Shared Placement Contract 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarPlacement
// 功能说明: D2 之后，共享 placement 除了 dockEdge/dockAlignment 之外，还能表达沿当前边滑动的 offsetAlongEdge。
import CoreGraphics
import Foundation

struct CanvasToolbarPlacement: Hashable, Sendable {
    var dockEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment
    var offsetAlongEdge: CGFloat

    init(
        dockEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered,
        offsetAlongEdge: CGFloat = 0
    ) {
        self.dockEdge = dockEdge
        self.dockAlignment = dockAlignment
        self.offsetAlongEdge = offsetAlongEdge
    }
}
```

### Shared Toolbar Solver 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift
// 函数名/类型名: CanvasToolbarPlacementConfiguration / CanvasToolbarPlacementSolver / resolveFrame(in:configuration:)
// 功能说明: D2 新增共享 toolbar placement solver，复用 D1 的 layout context，在首选边上做 inset、offset clamp、blocker 避让与 resolvedFrame 求解。
import CoreGraphics
import Foundation

struct CanvasToolbarPlacementConfiguration: Hashable, Sendable {
    var edgeInset: CGFloat = 20
    var blockerClearance: CGFloat = 12
}

struct CanvasToolbarPlacementSolver {
    func resolveFrame(
        in layoutContext: CanvasChromeLayoutContext,
        configuration: CanvasToolbarPlacementConfiguration = CanvasToolbarPlacementConfiguration()
    ) -> CGRect? {
        guard
            let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                layoutContext.safeBounds
            )
        else {
            return nil
        }

        let inset = max(configuration.edgeInset, 0)
        guard
            let layoutBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                safeBounds.insetBy(dx: inset, dy: inset)
            )
        else {
            return nil
        }

        let measuredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            layoutContext.toolbarMeasuredSize
        )
        let placement = layoutContext.toolbarPreferredPlacement
        let preferredLeadingCoordinate = clampedLeadingCoordinate(
            for: placement,
            size: measuredSize,
            in: layoutBounds
        )
        let blockerRects = expandedBlockerRects(
            from: layoutContext,
            configuration: configuration
        )
        let candidateLeadingCoordinates = candidateLeadingCoordinates(
            around: preferredLeadingCoordinate,
            placement: placement,
            size: measuredSize,
            in: layoutBounds,
            blockerRects: blockerRects
        )

        // ... 省略 blockingInterval / frame / overlap 细节实现 ...
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift
// 函数名/类型名: expandedBlockerRects(from:configuration:) / clampedLeadingCoordinate(for:size:in:)
// 功能说明: solver 会排除 toolbar 自身 blocker，并把 offsetAlongEdge 限制在当前边允许的滑动范围内。
private func expandedBlockerRects(
    from layoutContext: CanvasChromeLayoutContext,
    configuration: CanvasToolbarPlacementConfiguration
) -> [CGRect] {
    let clearance = max(configuration.blockerClearance, 0)
    return layoutContext
        .occupiedRects(excluding: [.toolbar])
        .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
        .map { rect in
            rect.insetBy(dx: -clearance, dy: -clearance)
        }
        .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
}

private func clampedLeadingCoordinate(
    for placement: CanvasToolbarPlacement,
    size: CGSize,
    in bounds: CGRect
) -> CGFloat {
    let range = leadingCoordinateRange(
        for: placement.dockEdge,
        size: size,
        in: bounds
    )
    let centeredLeadingCoordinate: CGFloat

    switch placement.dockEdge {
    case .top, .bottom:
        centeredLeadingCoordinate = bounds.midX - (size.width / 2)
    case .leading, .trailing:
        centeredLeadingCoordinate = bounds.midY - (size.height / 2)
    }

    return clamp(
        centeredLeadingCoordinate + placement.offsetAlongEdge,
        minValue: range.min,
        maxValue: range.max
    )
}
```

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarOffsetAlongEdge / toolbarPlacementSolver / setupViewHierarchy()
// 功能说明: D2 之后，iOS controller 持有共享 placement solver，并把 toolbar host 外层切到 frame 驱动模式。
private var toolbarOffsetAlongEdge: CGFloat = 0 {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarDockEdge()
    }
}
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(historyButtonsStackView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    installHistoryButtons()
    registerToolbarButtons()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updatePreparedToolbarDockEdge() / updateChromeOverlayLayout() / toolbarPreferredPlacement() / applyToolbarPlacement()
// 功能说明: 修改后 iOS 不再切换四边约束，而是先把 dockEdge/offset 组装成 placement，再通过 solver 求 resolvedFrame。
private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func updateChromeOverlayLayout() {
    applyToolbarPlacement()
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    // ... 其余 minimap / context menu 布局逻辑保持不变 ...
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(
        dockEdge: toolbarDockEdge,
        offsetAlongEdge: toolbarOffsetAlongEdge
    )
}

private func applyToolbarPlacement() {
    let layoutContext = makeChromeLayoutContext()
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }
}
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarOffsetAlongEdge / toolbarPlacementSolver / setupViewHierarchy()
// 功能说明: D2 之后，macOS controller 同样持有共享 placement solver，并让 toolbar host 改为 frame 驱动外层定位。
private var toolbarOffsetAlongEdge: CGFloat = 0 {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarDockEdge()
    }
}
private let toolbarPlacementSolver = CanvasToolbarPlacementSolver()

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    registerToolbarButtons()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updatePreparedToolbarDockEdge() / updateChromeOverlayLayout() / toolbarPreferredPlacement() / applyToolbarPlacement()
// 功能说明: 修改后 macOS 也不再依赖 makeToolbarDockConstraints(...)，而是统一通过 shared solver 直接写入 toolbarHostView.frame。
private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func updateChromeOverlayLayout() {
    applyToolbarPlacement()
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    // ... 其余 minimap / context menu 布局逻辑保持不变 ...
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(
        dockEdge: toolbarDockEdge,
        offsetAlongEdge: toolbarOffsetAlongEdge
    )
}

private func applyToolbarPlacement() {
    let layoutContext = makeChromeLayoutContext()
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }
}
```

## 验证结果

- 已执行 `ReadLints`，检查以下文件，结果无新增 lint 问题：
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已执行 iOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath ".build/ios-sim" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" AD_HOC_CODE_SIGNING_ALLOWED=NO`
- 已执行 macOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=macOS" -derivedDataPath ".build/macos" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## 结果说明

- `D2` 的核心落点已经从“controller 手写四边约束分支”切换为“共享 placement policy 求 resolved frame”。
- 工具栏外层的定位职责已经从平台控制器中抽离出一层稳定 contract，为后续 `D3` 把 toolbar 纳入完整 overlay 布局链继续铺路。
