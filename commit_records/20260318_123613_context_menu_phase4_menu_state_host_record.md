# 20260318_123613_context_menu_phase4_menu_state_host_record

## 记录范围

- 记录内容：
  1. 新增共享菜单展示态 `CanvasContextMenuState`，冻结展示时刻的 `resolvedContext + command descriptors`。
  2. 新增共享菜单宿主 `CanvasContextMenuHostView`，统一负责菜单容器、按钮列表、outside dismiss、基础定位和避让。
  3. 新增 `CanvasContextMenuLayoutSolver`，为菜单挂点定位、`safe area`/控件区/`minimap` 避让提供共享布局逻辑。
  4. 让 `iOS/macOS ViewController` 接入菜单宿主，并补齐 `present / dismiss / execute / relayout` 这些展示层职责。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `CanvasContextResolver`
  - `CanvasCommandCatalog` / `CanvasCommandExecutor`
  - `macOS` secondary click 触发桥接
  - `iOS` long press 触发桥接
  - 实际菜单内容策略的阶段 5/6 接线
  - `.cursor/plans/上下文菜单分阶段_e62bfffe.plan.md` 的状态同步
  - 原始 gif diff

## 修改一：新增共享菜单展示态与布局求解

### 修改前

- 项目里没有单独的菜单展示态。
- 也没有菜单宿主布局求解器，`safe area`、控件避让、`minimap` 避让都还不存在共享结构。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前没有共享菜单展示态和布局求解器，菜单 UI 状态还没有独立承载层。
// before: file did not exist
```

### 修改后

- 新增 `CanvasContextMenuCommandState`，把命令 id 和冻结后的 descriptor 绑定到一起。
- 新增 `CanvasContextMenuState`，冻结当前解析上下文和当时的命令状态。
- 新增 `CanvasContextMenuLayoutSolver`，负责菜单 frame 的候选放置、边界约束和 blocker overlap 最小化。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuCommandState / CanvasContextMenuState / CanvasContextMenuLayoutConfiguration / CanvasContextMenuLayoutSolver.resolveMenuFrame(...)
// 功能说明: 修改后新增共享菜单展示态与布局求解器，统一冻结菜单数据并处理挂点定位与避让。
import CoreGraphics
import Foundation

struct CanvasContextMenuCommandState {
    let commandID: CanvasCommandID
    let descriptor: CanvasCommandDescriptor
}

struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let commandStates: [CanvasContextMenuCommandState]

    var isEmpty: Bool {
        commandStates.isEmpty
    }
}

struct CanvasContextMenuLayoutConfiguration {
    var minimumWidth: CGFloat = 180
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var chromeClearance: CGFloat = 12
}

struct CanvasContextMenuLayoutSolver {
    func resolveMenuFrame(
        anchorPoint: CGPoint,
        preferredSize: CGSize,
        safeBounds: CGRect,
        occupiedRects: [CGRect],
        configuration: CanvasContextMenuLayoutConfiguration = CanvasContextMenuLayoutConfiguration()
    ) -> CGRect? {
        let layoutBounds = safeBounds
            .standardized
            .insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
            .standardized
        guard
            layoutBounds.width > 0,
            layoutBounds.height > 0
        else {
            return nil
        }

        let resolvedSize = resolvedMenuSize(
            from: preferredSize,
            within: layoutBounds.size,
            configuration: configuration
        )
        guard resolvedSize.width > 0, resolvedSize.height > 0 else {
            return nil
        }

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

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for placement in placements {
            let rawFrame = frame(
                around: anchorPoint,
                size: resolvedSize,
                placement: placement,
                anchorSpacing: configuration.anchorSpacing
            )
            let clampedFrame = clampedFrame(
                rawFrame,
                within: layoutBounds
            )
            let overlapScore = totalOverlapArea(
                of: clampedFrame,
                with: blockerRects
            )

            if overlapScore == 0 {
                return clampedFrame.standardized
            }

            if overlapScore < bestScore {
                bestScore = overlapScore
                bestFrame = clampedFrame.standardized
            }
        }

        return bestFrame
    }

    // ... 省略 resolvedMenuSize / candidatePlacements / frame / clampedFrame / totalOverlapArea 等辅助函数，实际代码已写入文件
}
```

## 修改二：新增跨平台菜单宿主 `CanvasContextMenuHostView`

### 修改前

- 当前 `chrome overlay` 是刻意事件穿透的，只适合承载按钮和 `minimap`，不适合直接承担可交互菜单。
- 项目里没有独立的菜单宿主来处理 outside dismiss、菜单按钮点击和布局刷新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名/类型名: iOSCanvasChromeOverlayView.hitTest(_:with:)
// 功能说明: 修改前 iOS overlay 对自身点击直接透传，不具备独立菜单宿主的拦截能力。
final class iOSCanvasChromeOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数名/类型名: macOSCanvasChromeOverlayView.hitTest(_:)
// 功能说明: 修改前 macOS overlay 同样对自身点击透传，没有菜单容器和外部点击关闭逻辑。
final class macOSCanvasChromeOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}
```

### 修改后

- 新增跨平台 `CanvasContextMenuHostView`。
- `iOS` 版本使用 `UIVisualEffectView + UIStackView + UIButton`，负责外部点按 dismiss、命令按钮点击和 frame 更新。
- `macOS` 版本使用 `NSVisualEffectView + NSStackView + NSButton`，负责外部点击 dismiss、命令按钮点击和 frame 更新。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.apply(state:safeBounds:occupiedRects:) / updateLayout(safeBounds:occupiedRects:) / dismiss()
// 功能说明: 修改后新增跨平台菜单宿主，统一承载菜单容器、按钮列表、外部点击关闭和布局刷新。
import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class CanvasContextMenuHostView: UIView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = CanvasContextMenuLayoutSolver()
    private let layoutConfiguration = CanvasContextMenuLayoutConfiguration()
    private let menuContainerView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let commandStackView = UIStackView()
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: CanvasContextMenuState?

    func apply(
        state: CanvasContextMenuState?,
        safeBounds: CGRect,
        occupiedRects: [CGRect]
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildCommandButtons(for: state)
        isHidden = false
        menuContainerView.isHidden = false
        updateLayout(
            safeBounds: safeBounds,
            occupiedRects: occupiedRects
        )
    }

    func updateLayout(
        safeBounds: CGRect,
        occupiedRects: [CGRect]
    ) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredMenuSize()
        guard let menuFrame = layoutSolver.resolveMenuFrame(
            anchorPoint: currentState.resolvedContext.anchorPoint,
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

    func dismiss() {
        currentState = nil
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        menuContainerView.frame = .zero
        menuContainerView.isHidden = true
        isHidden = true
    }

    // ... 省略 rebuildCommandButtons / makeCommandButton / touchesEnded / hitTest 等辅助实现，实际代码已写入文件
}
#elseif os(macOS)
import AppKit

final class CanvasContextMenuHostView: NSView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = CanvasContextMenuLayoutSolver()
    private let layoutConfiguration = CanvasContextMenuLayoutConfiguration()
    private let menuContainerView = NSVisualEffectView()
    private let commandStackView = NSStackView()
    private var commandIDs: [CanvasCommandID] = []
    private(set) var currentState: CanvasContextMenuState?

    override func mouseDown(with event: NSEvent) {
        guard currentState != nil else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if menuContainerView.frame.contains(location) == false {
            onDismissRequested?()
        }
    }

    // ... 省略 apply / updateLayout / dismiss / rebuildCommandButtons / makeCommandButton 等实现，实际代码已写入文件
}
#endif
```

## 修改三：`iOSViewController` 接入菜单展示态和宿主

### 修改前

- `iOSViewController` 只有 `canvasHostView`、`chromeOverlayView`、`controlsStackView`、`miniMapMountView` 这些已有 overlay 元素。
- 没有 `contextMenuState`、没有菜单宿主、也没有菜单的 `present / dismiss / execute / relayout` 流程。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: 成员区 / setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout()
// 功能说明: 修改前 iOS controller 还没有菜单宿主，overlay 上只有按钮区和 minimap。
private let miniMapMountView: iOSCanvasChromeOverlayView = {
    let view = iOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()
private let miniMapView = iOSCanvasMiniMapView()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
}
```

### 修改后

- 新增 `contextMenuHostView` 和 `contextMenuState`。
- 新增 `frozenContextMenuCommandStates(...)`、`presentContextMenu(...)`、`dismissContextMenu()`、`performContextMenuCommand(...)`。
- 在 overlay 上挂入菜单宿主，并把菜单布局纳入 `updateChromeOverlayLayout()` 和 `contextMenuOccupiedRects()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: contextMenuHostView / contextMenuState / frozenContextMenuCommandStates(...) / presentContextMenu(...) / dismissContextMenu() / performContextMenuCommand(...)
// 功能说明: 修改后 iOS controller 开始持有菜单展示态，并负责冻结命令状态、驱动宿主显示和执行菜单命令。
private let contextMenuHostView = CanvasContextMenuHostView()

private var contextMenuState: CanvasContextMenuState? {
    didSet {
        updateContextMenuPresentation()
    }
}

private func frozenContextMenuCommandStates(
    for commandIDs: [CanvasCommandID]
) -> [CanvasContextMenuCommandState] {
    commandIDs.map { commandID in
        CanvasContextMenuCommandState(
            commandID: commandID,
            descriptor: commandDescriptor(for: commandID)
        )
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
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

private func dismissContextMenu() {
    contextMenuState = nil
}

private func performContextMenuCommand(_ commandID: CanvasCommandID) {
    guard
        let contextMenuState,
        let command = contextMenuCommand(
            for: commandID,
            in: contextMenuState
        )
    else {
        dismissContextMenu()
        return
    }

    dismissContextMenu()
    performCommand(command)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / contextMenuOccupiedRects() / setupContextMenuHostView()
// 功能说明: 修改后 iOS overlay 顶层挂入菜单宿主，并把菜单布局、避让和 outside dismiss 接进 controller。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    ])
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }
    return rects
}

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onCommandSelected = { [weak self] commandID in
        self?.performContextMenuCommand(commandID)
    }
}
```

## 修改四：`macOSViewController` 同步接入菜单展示态和宿主

### 修改前

- `macOSViewController` 同样只有按钮区和 `minimap` 的 overlay 宿主。
- 没有独立的菜单展示态、菜单宿主，也没有程序化的 `present / dismiss / execute` 流程。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: 成员区 / setupViewHierarchy() / updateChromeOverlayLayout()
// 功能说明: 修改前 macOS controller 和 iOS 一样，还没有菜单宿主和菜单展示态。
private let miniMapMountView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()
private let miniMapView = macOSCanvasMiniMapView()

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
}
```

### 修改后

- `macOS` 同样新增 `contextMenuHostView` 和 `contextMenuState`。
- 新增冻结菜单状态、展示、关闭、执行命令的完整基础设施。
- 菜单宿主同样挂在 `chromeOverlayView` 顶层，并纳入 `minimap` 与按钮区避让。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: contextMenuHostView / contextMenuState / frozenContextMenuCommandStates(...) / presentContextMenu(...) / dismissContextMenu() / performContextMenuCommand(...)
// 功能说明: 修改后 macOS controller 具备冻结菜单状态、显示菜单宿主和执行菜单命令的完整展示层职责。
private let contextMenuHostView = CanvasContextMenuHostView()

private var contextMenuState: CanvasContextMenuState? {
    didSet {
        updateContextMenuPresentation()
    }
}

private func frozenContextMenuCommandStates(
    for commandIDs: [CanvasCommandID]
) -> [CanvasContextMenuCommandState] {
    commandIDs.map { commandID in
        CanvasContextMenuCommandState(
            commandID: commandID,
            descriptor: commandDescriptor(for: commandID)
        )
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
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

private func dismissContextMenu() {
    contextMenuState = nil
}

private func performContextMenuCommand(_ commandID: CanvasCommandID) {
    guard
        let contextMenuState,
        let command = contextMenuCommand(
            for: commandID,
            in: contextMenuState
        )
    else {
        dismissContextMenu()
        return
    }

    dismissContextMenu()
    performCommand(command)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / contextMenuOccupiedRects() / setupContextMenuHostView()
// 功能说明: 修改后 macOS overlay 也挂入菜单宿主，并把布局刷新、避让和 outside click dismiss 接到 controller。
private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    chromeOverlayView.addSubview(contextMenuHostView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        canvasHostView.topAnchor.constraint(equalTo: view.topAnchor),
        canvasHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        canvasHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        canvasHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        chromeOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
        chromeOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        chromeOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        chromeOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        contextMenuHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        contextMenuHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        contextMenuHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        contextMenuHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor),
        controlsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        controlsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    ])
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }
    return rects
}

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onCommandSelected = { [weak self] commandID in
        self?.performContextMenuCommand(commandID)
    }
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_123613`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `macOS`: `generic/platform=macOS`
  - `iOS`: `generic/platform=iOS`

## 当前阶段结论

- 阶段 4 已把菜单展示态和菜单宿主从 `editorSession` 外独立出来。
- 目前 `iOS/macOS` 都已经具备“冻结菜单数据 -> 宿主定位展示 -> 外部点击关闭 -> 回调执行命令”的展示层基础设施。
- 阶段 5 可以直接在 `macOS` 的 secondary click 输入桥上调用 `presentContextMenu(...)`，不需要再补菜单容器和布局层。
