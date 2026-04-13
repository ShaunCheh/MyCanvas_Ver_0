# 20260413_182405_raw_input_lane_phase3_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase3` shared 展示层落地”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 `6` 个业务代码文件：

- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorQueue.swift`
- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorFormatter.swift`
- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift`
- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 包含 `2` 个已跟踪 controller 文件修改，以及 `1` 个新增 shared 目录
- `git diff --stat -- <2 个 controller 文件>` 统计为：`2 files changed, 34 insertions(+)`
- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/` 当前包含 `4` 个新建 Swift 文件
- 本记录文件是随后新增的说明材料，不属于上述 `6` 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase4` 的 macOS raw input 全量接通
- `phase5` 的 iOS / iPadOS raw input 接通

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_182405`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase3 写记录前的真实工作区状态。
## feat/cross-platform-input-indicator
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? MyCanvas_Ver_0/Platform/Shared/InputIndicator/
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计已跟踪的 controller 改动规模；新建 shared 文件另以当前 changes 列表补足。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

# 实际输出:
#  MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift     | 17 +++++++++++++++++
#  MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | 17 +++++++++++++++++
#  2 files changed, 34 insertions(+)
```

```bash
# 文件路径: 目录 MyCanvas_Ver_0/Platform/Shared/InputIndicator
# 函数名/命令名: 当前目录文件清单
# 功能说明: 补足 git status 中未展开的新建 shared 输入指示器文件。
CanvasInputIndicatorFormatter.swift
CanvasInputIndicatorHostView.swift
CanvasInputIndicatorLayoutSolver.swift
CanvasInputIndicatorQueue.swift
```

## 本次 phase3 的真实目标

这一步严格按计划实现 shared 指示器展示层，而不是继续扩 raw-input capture：

1. 新建纯展示层 shared 模块，提供胶囊文本格式化、队列、布局求解和 host view。
2. 让 host view 只负责展示，不负责输入采集。
3. 把 shared host view 挂到双端 `chromeOverlayView`。
4. 让 `handleCapturedInput(...)` 开始消费 `routingResult.indicatorEvent`，从而把 phase2 已经打通的 raw-input 路由真正喂给 phase3 UI。
5. 复用 `CanvasChromeLayoutContext`，让底部胶囊栈避开 toolbar、miniMap、backButton、workspaceModeButton 等 chrome blocker。

## 修改一：新增 `CanvasInputIndicatorQueue.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorQueue.swift
// 函数名/符号名: 文件不存在
// 功能说明: 修改前仓库里还没有输入指示器队列模型，phase3 所需的入栈、渐隐、超时移除能力不存在。
// 修改前：文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorQueue.swift
// 函数名/符号名: CanvasInputIndicatorQueueConfiguration / CanvasInputIndicatorQueueSnapshot / CanvasInputIndicatorQueue.enqueue(_:now:) / snapshot(asOf:)
// 功能说明: 修改后新增 shared 队列，负责新事件入栈、可见项裁剪、按时间渐隐，并输出 host view 可直接消费的 snapshot。
import CoreGraphics
import Foundation

struct CanvasInputIndicatorQueueConfiguration: Equatable, Sendable {
    var maximumVisibleItems: Int
    var itemLifetime: TimeInterval
    var fadeOutDuration: TimeInterval
    var refreshInterval: TimeInterval
    var newestOpacity: CGFloat
    var stackOpacityStep: CGFloat
    var minimumOpacity: CGFloat

    init(
        maximumVisibleItems: Int = 4,
        itemLifetime: TimeInterval = 2.4,
        fadeOutDuration: TimeInterval = 0.32,
        refreshInterval: TimeInterval = 1 / 12,
        newestOpacity: CGFloat = 1,
        stackOpacityStep: CGFloat = 0.18,
        minimumOpacity: CGFloat = 0.38
    ) {
        self.maximumVisibleItems = max(maximumVisibleItems, 1)
        self.itemLifetime = max(itemLifetime, 0.1)
        self.fadeOutDuration = max(
            min(fadeOutDuration, self.itemLifetime),
            0.05
        )
        self.refreshInterval = max(refreshInterval, 1 / 30)
        self.newestOpacity = min(max(newestOpacity, 0), 1)
        self.stackOpacityStep = max(stackOpacityStep, 0)
        self.minimumOpacity = min(max(minimumOpacity, 0), 1)
    }
}

struct CanvasInputIndicatorQueueSnapshotItem: Sendable {
    let id: UUID
    let event: CanvasInputIndicatorEvent
    let opacity: CGFloat
}

struct CanvasInputIndicatorQueueSnapshot: Sendable {
    let items: [CanvasInputIndicatorQueueSnapshotItem]

    var isEmpty: Bool {
        items.isEmpty
    }
}

final class CanvasInputIndicatorQueue {
    private struct Entry {
        let id: UUID
        let event: CanvasInputIndicatorEvent
        let insertedAt: Date
    }

    @discardableResult
    func enqueue(
        _ event: CanvasInputIndicatorEvent,
        now: Date = Date()
    ) -> CanvasInputIndicatorQueueSnapshot {
        purgeExpiredEntries(asOf: now)
        entries.append(
            Entry(
                id: UUID(),
                event: event,
                insertedAt: now
            )
        )
        trimToVisibleCount()
        return snapshot(asOf: now)
    }

    @discardableResult
    func snapshot(
        asOf now: Date = Date()
    ) -> CanvasInputIndicatorQueueSnapshot {
        purgeExpiredEntries(asOf: now)
        let visibleEntries = Array(
            entries.suffix(configuration.maximumVisibleItems)
        )
        let items = visibleEntries.enumerated().map { index, entry in
            CanvasInputIndicatorQueueSnapshotItem(
                id: entry.id,
                event: entry.event,
                opacity: resolvedOpacity(
                    for: entry,
                    visibleIndex: index,
                    visibleCount: visibleEntries.count,
                    now: now
                )
            )
        }
        return CanvasInputIndicatorQueueSnapshot(items: items)
    }

    private func resolvedOpacity(
        for entry: Entry,
        visibleIndex: Int,
        visibleCount: Int,
        now: Date
    ) -> CGFloat {
        let rankOpacity = resolvedRankOpacity(
            visibleIndex: visibleIndex,
            visibleCount: visibleCount
        )
        let lifetimeOpacity = resolvedLifetimeOpacity(
            age: age(of: entry, at: now)
        )
        return min(max(rankOpacity * lifetimeOpacity, 0), 1)
    }
}
```

### 修改意图

这个文件把 phase3 里“新事件从底部冒出、旧事件被顶上去、过期后渐隐移除”的时序逻辑固定到了 shared 层，后续 platform adapter 只需要投喂事件，不需要各写一套动画生命周期管理。

## 修改二：新增 `CanvasInputIndicatorFormatter.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorFormatter.swift
// 函数名/符号名: 文件不存在
// 功能说明: 修改前仓库里还没有输入指示器文本格式化器，CanvasInputIndicatorEvent 不能直接被转成胶囊文案。
// 修改前：文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorFormatter.swift
// 函数名/符号名: CanvasInputIndicatorFormatter.text(for:) / formattedText(for:)
// 功能说明: 修改后统一把 keyChord 和 action 转成展示字符串，固定 modifier 顺序与动作命名。
import Foundation

struct CanvasInputIndicatorFormatter {
    func text(for event: CanvasInputIndicatorEvent) -> String {
        switch event {
        case .keyChord(let chord):
            return formattedText(for: chord)
        case .action(let action):
            return action.displayText
        }
    }

    private func formattedText(for chord: CanvasKeyChord) -> String {
        let modifierComponents = CanvasKeyModifier.displayOrder
            .filter { chord.modifiers.contains($0) }
            .map(\.displayText)
        let components = modifierComponents + [chord.key.displayText]
        return components.joined(separator: " + ")
    }
}

private extension CanvasKeyModifier {
    static let displayOrder: [CanvasKeyModifier] = [
        .command,
        .shift,
        .option,
        .control,
        .globe
    ]
}

private extension CanvasInputIndicatorAction {
    var displayText: String {
        switch self {
        case .leftClick:
            return "Left Click"
        case .rightClick:
            return "Right Click"
        case .tap:
            return "Tap"
        case .longPress:
            return "Long Press"
        case .scroll:
            return "Scroll"
        case .pinch:
            return "Pinch"
        case .zoom:
            return "Zoom"
        }
    }
}
```

### 修改意图

这个文件把文案格式化从 host view 里拆出来，保证 `Command + V`、`Shift + Command + Z`、`Left Click` 等文本规则在 shared 层统一收敛，避免平台侧拼字符串。

## 修改三：新增 `CanvasInputIndicatorLayoutSolver.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift
// 函数名/符号名: 文件不存在
// 功能说明: 修改前仓库里还没有输入指示器布局求解器，新的胶囊栈无法基于 CanvasChromeLayoutContext 计算底部可用区。
// 修改前：文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift
// 函数名/符号名: CanvasInputIndicatorLayoutConfiguration / CanvasInputIndicatorLayoutSolver.resolveHostFrame(preferredSize:layoutContext:)
// 功能说明: 修改后新增 shared 布局求解器，基于 safeBounds 和 occupiedRects 把胶囊栈压到安全底部，并在碰到 chrome blocker 时向上让位。
import CoreGraphics
import Foundation

struct CanvasInputIndicatorLayoutConfiguration: Equatable, Sendable {
    var horizontalMargin: CGFloat
    var verticalMargin: CGFloat
    var blockerSpacing: CGFloat
}

struct CanvasInputIndicatorLayoutSolver {
    var configuration: CanvasInputIndicatorLayoutConfiguration

    func resolveHostFrame(
        preferredSize: CGSize,
        layoutContext: CanvasChromeLayoutContext
    ) -> CGRect? {
        guard
            let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
                layoutContext.safeBounds
            )
        else {
            return nil
        }

        let availableWidth = max(
            safeBounds.width - configuration.horizontalMargin * 2,
            0
        )
        let availableHeight = max(
            safeBounds.height - configuration.verticalMargin * 2,
            0
        )
        let sanitizedPreferredSize = CanvasChromeLayoutGeometry.sanitizedSize(
            preferredSize
        )
        let width = min(sanitizedPreferredSize.width, availableWidth)
        let height = min(sanitizedPreferredSize.height, availableHeight)
        guard width > 0, height > 0 else {
            return nil
        }

        let x = safeBounds.midX - width / 2
        let minimumY = safeBounds.minY + configuration.verticalMargin
        var candidateFrame = CGRect(
            x: x,
            y: safeBounds.maxY - configuration.verticalMargin - height,
            width: width,
            height: height
        )

        let blockers = layoutContext.occupiedRects.compactMap {
            CanvasChromeLayoutGeometry.sanitizedRect($0)
        }

        var didAdjust = true
        while didAdjust {
            didAdjust = false
            for blocker in blockers {
                let expandedBlocker = blocker.insetBy(
                    dx: -configuration.blockerSpacing,
                    dy: -configuration.blockerSpacing
                )
                guard candidateFrame.intersects(expandedBlocker) else {
                    continue
                }

                let shiftedY = blocker.minY - configuration.blockerSpacing - height
                guard shiftedY < candidateFrame.minY else {
                    continue
                }

                candidateFrame.origin.y = shiftedY
                didAdjust = true
            }
        }

        guard candidateFrame.minY >= minimumY else {
            return nil
        }

        return candidateFrame.integral
    }
}
```

### 修改意图

这个文件让输入指示器的布局规则和现有 chrome overlay 系统对齐，不是直接写死在屏幕底部，而是复用 shared layout context 去避让 toolbar / miniMap / backButton / workspaceModeButton。

## 修改四：新增 `CanvasInputIndicatorHostView.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: 文件不存在
// 功能说明: 修改前仓库里还没有输入指示器宿主视图，phase2 路由出来的 indicatorEvent 没有展示落点。
// 修改前：文件不存在
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: CanvasInputIndicatorHostView.record(event:) / updateLayout(layoutContext:) / applySnapshot(_:animated:)
// 功能说明: 修改后新增 cross-platform host view；iOS 与 macOS 各自渲染胶囊视图，但都复用同一套 queue、formatter、layout solver。
import CoreGraphics
import Foundation

#if os(iOS)
import UIKit

final class CanvasInputIndicatorHostView: UIView {
    private let layoutSolver = CanvasInputIndicatorLayoutSolver()
    private let formatter = CanvasInputIndicatorFormatter()
    private let queue = CanvasInputIndicatorQueue()
    private let containerView = UIView()
    private let stackView = UIStackView()
    private var itemViewsByID: [UUID: iOSCanvasInputIndicatorItemView] = [:]
    private var currentSnapshot = CanvasInputIndicatorQueueSnapshot()
    private var currentLayoutContext: CanvasChromeLayoutContext?
    private var refreshTimer: Timer?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func record(event: CanvasInputIndicatorEvent) {
        let snapshot = queue.enqueue(event)
        applySnapshot(snapshot, animated: window != nil)
        updateRefreshTimerIfNeeded()
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        currentLayoutContext = layoutContext
        applyLayout()
        layoutIfNeeded()
    }

    private func applySnapshot(
        _ snapshot: CanvasInputIndicatorQueueSnapshot,
        animated: Bool
    ) {
        if snapshot.isEmpty {
            containerView.isHidden = true
            isHidden = true
            applyLayout()
            return
        }

        for item in snapshot.items {
            let view = itemViewsByID[item.id] ?? iOSCanvasInputIndicatorItemView()
            itemViewsByID[item.id] = view
            view.apply(text: formatter.text(for: item.event))
        }

        containerView.isHidden = false
        isHidden = false
        applyLayout()
    }
}

#elseif os(macOS)
import AppKit

final class CanvasInputIndicatorHostView: NSView {
    private let layoutSolver = CanvasInputIndicatorLayoutSolver()
    private let formatter = CanvasInputIndicatorFormatter()
    private let queue = CanvasInputIndicatorQueue()
    private let containerView = NSView()
    private let stackView = NSStackView()
    private var itemViewsByID: [UUID: macOSCanvasInputIndicatorItemView] = [:]
    private var currentSnapshot = CanvasInputIndicatorQueueSnapshot()
    private var currentLayoutContext: CanvasChromeLayoutContext?
    private var refreshTimer: Timer?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func record(event: CanvasInputIndicatorEvent) {
        let snapshot = queue.enqueue(event)
        applySnapshot(snapshot, animated: window != nil)
        updateRefreshTimerIfNeeded()
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        currentLayoutContext = layoutContext
        applyLayout()
        layoutSubtreeIfNeeded()
    }

    private func applySnapshot(
        _ snapshot: CanvasInputIndicatorQueueSnapshot,
        animated: Bool
    ) {
        if snapshot.isEmpty {
            containerView.isHidden = true
            isHidden = true
            applyLayout()
            return
        }

        for item in snapshot.items {
            let view = itemViewsByID[item.id] ?? macOSCanvasInputIndicatorItemView()
            itemViewsByID[item.id] = view
            view.apply(text: formatter.text(for: item.event))
        }

        containerView.isHidden = false
        isHidden = false
        applyLayout()
    }
}
#endif
```

### 修改意图

这个文件把 phase3 的 UI 真实落到了双端 overlay 上，同时保持边界清晰：host view 只展示，不采集输入；输入事实仍然来自 raw-input lane，展示文案和布局也都继续走 shared 组件。

## 修改五：`iOSViewController.swift` 挂载输入指示器 host，并在 routing 后投喂展示层

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: 属性区 / setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / handleCapturedInput(...)
// 功能说明: 修改前 iOS controller 只有 contextMenuHostView，没有 inputIndicatorHostView，也不会消费 routingResult.indicatorEvent。
private let contextMenuHostView = CanvasContextMenuHostView()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
}

private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: 属性区 / updateInputIndicatorLayout(using:) / setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / handleCapturedInput(...)
// 功能说明: 修改后 iOS controller 把 shared input indicator host 挂到 chromeOverlayView，并在 raw-input routing 后优先记录 indicatorEvent。
private let contextMenuHostView = CanvasContextMenuHostView()
private let inputIndicatorHostView = CanvasInputIndicatorHostView()

private func updateInputIndicatorLayout(
    using layoutContext: CanvasChromeLayoutContext
) {
    inputIndicatorHostView.updateLayout(layoutContext: layoutContext)
}

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(inputIndicatorHostView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        inputIndicatorHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        inputIndicatorHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        inputIndicatorHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        inputIndicatorHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor)
    ])
}

private func updateChromeOverlayLayout() {
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateInputIndicatorLayout(using: contextMenuLayoutContext)
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    if let indicatorEvent = routingResult.indicatorEvent {
        inputIndicatorHostView.record(event: indicatorEvent)
    }

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改意图

这一步让 iOS 侧第一次有了真实的 phase3 展示落点：`Command + V` 等通过 phase2 进来的 raw-input routing 结果，不再只是日志和 interaction gate，而是会真正冒出底部胶囊。

## 修改六：`macOSViewController.swift` 挂载输入指示器 host，并在 routing 后投喂展示层

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: 属性区 / setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / handleCapturedInput(...)
// 功能说明: 修改前 macOS controller 也还没有 inputIndicatorHostView，shared routing 结果里即使存在 indicatorEvent 也没有 UI 消费方。
private let contextMenuHostView = CanvasContextMenuHostView()

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
}

private func updateChromeOverlayLayout() {
    if chromeOverlayView.bounds.isEmpty == false {
        chromeOverlayView.layoutSubtreeIfNeeded()
    }
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: 属性区 / updateInputIndicatorLayout(using:) / setupViewHierarchy() / setupConstraints() / updateChromeOverlayLayout() / handleCapturedInput(...)
// 功能说明: 修改后 macOS controller 与 iOS 对齐，把 shared indicator host 接进 overlay，并在 routing 之后先记录 indicatorEvent。
private let contextMenuHostView = CanvasContextMenuHostView()
private let inputIndicatorHostView = CanvasInputIndicatorHostView()

private func updateInputIndicatorLayout(
    using layoutContext: CanvasChromeLayoutContext
) {
    inputIndicatorHostView.updateLayout(layoutContext: layoutContext)
}

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    view.addSubview(transitionInteractionShieldView)
    chromeOverlayView.addSubview(miniMapMountView)
    toolbarHostView.translatesAutoresizingMaskIntoConstraints = true
    chromeOverlayView.addSubview(toolbarHostView)
    chromeOverlayView.addSubview(textEditorOverlayView)
    chromeOverlayView.addSubview(inputIndicatorHostView)
    chromeOverlayView.addSubview(contextMenuHostView)
    chromeOverlayView.addSubview(backButton)
    chromeOverlayView.addSubview(workspaceModeButton)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        inputIndicatorHostView.topAnchor.constraint(equalTo: chromeOverlayView.topAnchor),
        inputIndicatorHostView.leadingAnchor.constraint(equalTo: chromeOverlayView.leadingAnchor),
        inputIndicatorHostView.trailingAnchor.constraint(equalTo: chromeOverlayView.trailingAnchor),
        inputIndicatorHostView.bottomAnchor.constraint(equalTo: chromeOverlayView.bottomAnchor)
    ])
}

private func updateChromeOverlayLayout() {
    if chromeOverlayView.bounds.isEmpty == false {
        chromeOverlayView.layoutSubtreeIfNeeded()
    }
    let contextMenuLayoutContext = performOverlayLayoutPass()
    updateInputIndicatorLayout(using: contextMenuLayoutContext)
    updateContextMenuLayout(using: contextMenuLayoutContext)
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    if let indicatorEvent = routingResult.indicatorEvent {
        inputIndicatorHostView.record(event: indicatorEvent)
    }

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改意图

这一步把 macOS 侧也接到了 phase3 的展示层上，使 `pasteKeyboardShortcut` 等经过 phase2 ingress 的 raw-input 结果在桌面端也有了统一的 shared UI 出口。

## 验证结果

`ReadLints` 针对以下范围检查后没有新增诊断：

- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase3 当前代码在 macOS 与 iOS 目标下都能通过编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS" build
```

实际结果：

- `macOS build` 通过
- `iOS build` 通过

补充说明：

- 在 phase3 实施过程中，`CanvasInputIndicatorQueue.swift` 里的 snapshot 类型一度带了多余的 `Hashable` 约束，导致 `CanvasInputIndicatorEvent` 无法自动合成 `Hashable` 而编译失败
- 当前代码已经如实修正为 `Sendable` 即可，不再要求 snapshot item / snapshot 自身 `Hashable`
- 修正后再次执行双端构建，均返回成功

## 本次 phase3 的实际完成面

已经完成：

- shared input indicator `queue`
- shared input indicator `formatter`
- shared input indicator `layout solver`
- cross-platform `host view`
- iOS / macOS controller 挂载与 `indicatorEvent` 投喂
- 复用 `CanvasChromeLayoutContext` 做底部避障布局

明确还没做：

- `phase4` 的 macOS copy / undo / scroll / zoom / click 全量接通
- `phase5` 的 iOS / iPadOS touch / hardware keyboard / pointer 全量接通
- 更完整的自动化测试补齐
