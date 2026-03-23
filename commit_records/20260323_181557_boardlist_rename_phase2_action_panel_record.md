# 20260323_181557_boardlist_rename_phase2_action_panel_record

## 记录范围

- 记录内容：
  1. 为 BoardList rename Phase 2 新增共享层的 action panel state / layout solver。
  2. 为 `iOS` / `macOS` 新增对等的 `BoardListActionPanelHostView`。
  3. 同步更新 BoardList rename 实施计划中的 `shared-action-panel` 状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift`
  - `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md`
- 本记录不包含：
  - `BoardListViewController` 对 panel 的接线
  - Grid/List cell 的三点按钮
  - 标题内联编辑
  - git commit / push

## 修改一：新增 BoardList action panel 的状态与布局求解文件

### 修改前

- `Platform/Shared/BoardList/` 下还没有独立的 action panel state / layout solver。
- BoardList 共享层只有 catalog、preview、entry、display mode 等已有结构，后续如果想做自定义三点菜单，还缺少一个和 canvas 解耦的最小状态模型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: N/A（新增文件）
// 功能说明: 修改前该文件不存在；BoardList 共享层没有专用的 action panel state、layout context 和 layout solver。
// 文件不存在
```

### 修改后

- 新增 `BoardListActionID`、`BoardListActionRole`、`BoardListActionState`。
- 新增 `BoardListActionPanelState`，用 `boardID + layoutAnchorPoint + actionStates` 描述一次菜单展示。
- 新增 `renameMenu(...)` 工厂方法，先支持“只有 Rename 一个动作”的最小菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: BoardListActionState.rename(...) / BoardListActionPanelState.renameMenu(...)
// 功能说明: 修改后 BoardList 共享层拥有独立的 action 状态定义；控制器后续只需传入 boardID 和锚点，即可生成 rename 面板的基础 state。
enum BoardListActionID: String, Hashable, Sendable {
    case rename
}

enum BoardListActionRole: Hashable, Sendable {
    case standard
    case destructive
}

struct BoardListActionState: Hashable, Sendable {
    let id: BoardListActionID
    let title: String
    let systemImageName: String?
    let role: BoardListActionRole
    let isEnabled: Bool

    static func rename(
        isEnabled: Bool = true
    ) -> BoardListActionState {
        BoardListActionState(
            id: .rename,
            title: "Rename",
            systemImageName: "pencil",
            role: .standard,
            isEnabled: isEnabled
        )
    }
}

struct BoardListActionPanelState: Hashable, Sendable {
    let boardID: UUID
    let layoutAnchorPoint: CGPoint
    let actionStates: [BoardListActionState]

    var isEmpty: Bool {
        actionStates.isEmpty
    }

    static func renameMenu(
        boardID: UUID,
        anchorPoint: CGPoint,
        isRenameEnabled: Bool = true
    ) -> BoardListActionPanelState {
        BoardListActionPanelState(
            boardID: boardID,
            layoutAnchorPoint: anchorPoint,
            actionStates: [
                .rename(isEnabled: isRenameEnabled)
            ]
        )
    }
}
```

- 同文件里还新增了 `BoardListActionPanelLayoutContext`、`BoardListActionPanelLayoutConfiguration` 和 `BoardListActionPanelLayoutSolver`。
- 这套 solver 会根据 `safeBounds`、`occupiedRects`、锚点和候选摆放方向，选择一个尽量少遮挡、尽量少 clamp 的 frame。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift
// 函数名: resolvePanelFrame(anchorPoint:preferredSize:layoutContext:configuration:)
// 功能说明: 修改后新增 BoardList 专用布局求解器；它不依赖 CanvasCommandID 或 CanvasContextMenuState，而是按 safeBounds / occupiedRects 为 action panel 计算位置。
struct BoardListActionPanelLayoutSolver {
    func resolvePanelFrame(
        anchorPoint: CGPoint,
        preferredSize: CGSize,
        layoutContext: BoardListActionPanelLayoutContext,
        configuration: BoardListActionPanelLayoutConfiguration = BoardListActionPanelLayoutConfiguration()
    ) -> CGRect? {
        let layoutBounds = layoutContext.safeBounds
            .standardized
            .insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
            .standardized
        guard
            layoutBounds.width > 0,
            layoutBounds.height > 0
        else {
            return nil
        }

        let panelSize = resolvedPanelSize(
            from: preferredSize,
            within: layoutBounds.size,
            configuration: configuration
        )
        guard panelSize.width > 0, panelSize.height > 0 else {
            return nil
        }

        let blockerRects = layoutContext.occupiedRects
            .map(\.standardized)
            .filter { $0.isEmpty == false }
            .map {
                $0.insetBy(
                    dx: -configuration.blockerClearance,
                    dy: -configuration.blockerClearance
                )
            }

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for placement in Placement.allCases {
            let rawFrame = frame(
                around: anchorPoint,
                size: panelSize,
                placement: placement,
                anchorSpacing: configuration.anchorSpacing
            )
            let clampedFrame = clampedFrame(rawFrame, within: layoutBounds)
            let overlapScore = totalOverlapArea(of: clampedFrame, with: blockerRects)
            let clampScore = clampDistance(between: rawFrame, and: clampedFrame)
            let candidateScore = overlapScore * 10_000 + clampScore + placement.preferenceScore

            if overlapScore == 0, clampScore == 0 {
                return clampedFrame.standardized
            }

            if candidateScore < bestScore {
                bestScore = candidateScore
                bestFrame = clampedFrame.standardized
            }
        }

        return bestFrame
    }
}
```

## 修改二：新增 iOS / macOS 对等的 `BoardListActionPanelHostView`

### 修改前

- BoardList 共享层没有自己的 panel host view。
- 如果后续 controller 想展示自定义三点菜单，只能临时拼 UIKit/AppKit 视图，或错误复用 canvas 专属的 context menu host。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: N/A（新增文件）
// 功能说明: 修改前该文件不存在；BoardList 没有专门承载 action panel 的全屏 host view。
// 文件不存在
```

### 修改后

- 新增 `BoardListActionPanelHostView`，并在同一文件中提供 `iOS` / `macOS` 两套实现。
- 两端统一暴露：
  - `onActionSelected`
  - `onDismissRequested`
  - `apply(state:layoutContext:)`
  - `updateLayout(layoutContext:)`
  - `dismiss()`
- 这使得 Phase 3 可以像 canvas controller 接 `contextMenuHostView` 一样，把 BoardList panel 直接挂到控制器根视图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: apply(state:layoutContext:) / updateLayout(layoutContext:) / dismiss()
// 功能说明: 修改后 iOS 侧新增 BoardListActionPanelHostView；它负责根据共享 state 重建按钮、计算 panel frame，并在 state 为空时统一收起面板。
final class BoardListActionPanelHostView: UIView {
    var onActionSelected: ((BoardListActionID) -> Void)?
    var onDismissRequested: (() -> Void)?

    private let layoutSolver = BoardListActionPanelLayoutSolver()
    private let layoutConfiguration = BoardListActionPanelLayoutConfiguration()
    private let panelContainerView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let actionStackView = UIStackView()
    private var actionIDs: [BoardListActionID] = []
    private(set) var currentState: BoardListActionPanelState?

    func apply(
        state: BoardListActionPanelState?,
        layoutContext: BoardListActionPanelLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildActionButtons(for: state)
        isHidden = false
        panelContainerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: BoardListActionPanelLayoutContext) {
        guard let currentState else {
            return
        }

        let preferredSize = preferredPanelSize()
        guard let panelFrame = layoutSolver.resolvePanelFrame(
            anchorPoint: currentState.layoutAnchorPoint,
            preferredSize: preferredSize,
            layoutContext: layoutContext,
            configuration: layoutConfiguration
        ) else {
            updatePanelContainerConstraints(.zero)
            return
        }

        updatePanelContainerConstraints(panelFrame.integral)
        layoutIfNeeded()
    }

    func dismiss() {
        currentState = nil
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        updatePanelContainerConstraints(.zero)
        panelContainerView.isHidden = true
        isHidden = true
    }
}
```

- iOS 侧还补了点空白关闭和按钮构建逻辑：面板打开时全屏 host 接管 hit test，点到 panel 外部会触发 `onDismissRequested`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: hitTest(_:with:) / touchesEnded(_:with:) / makeActionButton(for:)
// 功能说明: 修改后 iOS host 能拦截面板展示时的点击，并为共享 action state 动态生成按钮。
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard currentState != nil, isHidden == false else {
        return nil
    }

    let hitView = super.hitTest(point, with: event)
    return hitView === self ? self : hitView
}

override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard
        currentState != nil,
        let touch = touches.first
    else {
        super.touchesEnded(touches, with: event)
        return
    }

    let location = touch.location(in: self)
    if panelContainerView.frame.contains(location) == false {
        onDismissRequested?()
    }
}

private func makeActionButton(
    for actionState: BoardListActionState
) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
    button.contentHorizontalAlignment = .leading
    button.isEnabled = actionState.isEnabled
    // ... 省略其余按钮外观配置 ...
    return button
}
```

- macOS 侧也提供了对等实现：同样是全屏 host + 模糊 panel + 动态 action buttons，只是事件入口改成 `mouseDown` / `rightMouseDown`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift
// 函数名: mouseDown(with:) / rightMouseDown(with:) / makeActionButton(for:)
// 功能说明: 修改后 macOS host 与 iOS 对齐：面板打开后可点击空白关闭，并根据 action state 动态生成 AppKit 按钮。
override func mouseDown(with event: NSEvent) {
    guard currentState != nil else {
        super.mouseDown(with: event)
        return
    }

    let location = convert(event.locationInWindow, from: nil)
    if panelContainerView.frame.contains(location) == false {
        onDismissRequested?()
    }
}

override func rightMouseDown(with event: NSEvent) {
    guard currentState != nil else {
        super.rightMouseDown(with: event)
        return
    }

    let location = convert(event.locationInWindow, from: nil)
    if panelContainerView.frame.contains(location) == false {
        onDismissRequested?()
    }
}

private func makeActionButton(
    for actionState: BoardListActionState
) -> NSButton {
    let button = NSButton(
        title: actionState.title,
        target: self,
        action: #selector(handleActionButtonClick(_:))
    )
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    button.isBordered = false
    // ... 省略其余按钮外观配置 ...
    return button
}
```

## 修改三：同步计划文件中的 Phase 2 完成状态

### 修改前

- BoardList rename 计划里，`shared-action-panel` 仍是 `pending`。
- 这会让“共享基础设施已经落地”和“计划里还未完成”之间出现状态偏差。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改前，Phase 2 的共享 action panel 任务仍标记为 pending。
todos:
  - id: shared-action-panel
    content: 新增 BoardListActionPanelState 与 BoardListActionPanelHostView，完成 BoardList 专用自定义面板基础设施
    status: pending
```

### 修改后

- 将 `shared-action-panel` 标记为 `completed`。
- 这属于实施进度同步，不改变产品运行逻辑，但能保证计划文档与当前代码一致。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改后，Phase 2 的共享 action panel 基础设施任务已同步标记为 completed。
todos:
  - id: shared-action-panel
    content: 新增 BoardListActionPanelState 与 BoardListActionPanelHostView，完成 BoardList 专用自定义面板基础设施
    status: completed
```

## 当前边界说明

- 本次 Phase 2 只补共享层基础设施，尚未把 panel 挂进 `iOSBoardListViewController` / `macOSBoardListViewController`。
- 因此当前项目里虽然已经有 panel state 和 host view，但还没有任何用户可触发的三点菜单行为。
- 这部分会留给后续 Phase 3 接入控制器生命周期时完成。

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift` 无新增 linter 问题。
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelHostView.swift` 无新增 linter 问题。
- 类型检查：
  - 已执行 `xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift`
  - 结果通过。

## 当前阶段结论

- Phase 2 已完成：BoardList 已具备独立于 canvas command 体系的 action panel 共享模型和 host view。
- 下一阶段可以直接进入 Phase 3，把这套基础设施接到 `BoardListViewController` 的 state 和展示生命周期里。
