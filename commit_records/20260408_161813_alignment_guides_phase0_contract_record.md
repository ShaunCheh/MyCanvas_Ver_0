# 20260408_161813_alignment_guides_phase0_contract_record

## 记录范围

- 记录内容：
  1. 为“图片拖动对齐辅助线”实现 `Phase 0` 共享契约，新增统一的对齐锚点、参考源、guide、match、solver 配置、request/result 与 `CanvasCamera` 距离换算 helper。
  2. 为 transient 交互层新增 `CanvasAlignmentInteractionState`，明确对齐辅助线状态和旋转交互状态一样，只存在于运行期，不进入持久化和 history snapshot。
  3. 扩展 `CanvasInteractionOverlayKind` / `CanvasInteractionRenderOverlayPayload`，为后续 renderer -> snapshot -> viewport 的 alignment overlay 链路预留契约。
  4. 在 iOS/macOS 双端 viewport 的 `refreshInteractionOverlay()` 中补齐 `.alignment` 分支，占位保持可编译，但当前阶段仍不绘制任何辅助线。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 当前 changes 依据：
  - `git status --short` 显示 4 个已跟踪修改文件和 1 个新增未跟踪文件：
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift`
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
    - `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
    - `M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
    - `?? MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift`
  - `git diff -- <tracked files>` 证明四个既有文件只发生了本记录所描述的增量修改。
  - 新增文件 `CanvasAlignmentGuideSolver.swift` 因为当前仍是未跟踪状态，不会出现在普通 `git diff` 中；本记录对该文件的“修改后”描述，直接依据当前工作区文件内容。
  - 构建验证依据：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build` 已通过。
- 本记录不包含：
  - `Phase 1` 的共享 solver 实际候选搜索、阈值命中和吸附修正逻辑
  - `Phase 2` 的 `CanvasEditorSession` / `CanvasRenderer` 接线
  - `Phase 3` / `Phase 4` 的 iOS/macOS 控制器接入
  - `Phase 5` 的 viewport 辅助线实际绘制
  - git commit / push

## 修改一：新增共享对齐契约文件

### 修改前

- 项目中还没有“图片拖动对齐辅助线”的共享 solver 契约文件。
- 也还没有一处共享入口来统一定义：
  - 第一版只支持哪些对齐锚点
  - board / item 参考线的来源类型
  - solver 的输入输出结构
  - 屏幕距离到 world 距离的换算规则
- 如果直接在后续 `Phase 1` / `Phase 2` 中进入平台接线，iOS/macOS 很容易各自临时拼装一套对齐模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: 无（修改前该共享契约文件不存在）
// 功能说明: 修改前项目中没有这一层共享对齐 contract；锚点语义、reference source、guide/match、solver request/result 以及 viewport/world 距离换算 helper 都还未落到源码。
```

### 修改后

- 新增 `CanvasAlignmentGuideSolver.swift`，把 `Phase 0` 需要冻结的共享契约正式落到源码。
- 实际冻结下来的边界包括：
  - 对齐锚点：`left / centerX / right / top / centerY / bottom`
  - 轴向语义：`x` / `y`
  - guide 方向：`horizontal` / `vertical`
  - 参考源：`board` 或 `item(CanvasItemID)`
  - solver 配置：`snapThresholdInViewport = 8`、`searchPaddingInViewport = 160`
  - solver 输入：`movingItemID / proposedCenter / scene / boardState / camera`
  - solver 输出：`resolvedCenter / interactionState`
- 当前 `solve(_:)` 仍然是 `passthrough` 占位实现，这一点是刻意保持的：`Phase 0` 只收口契约，不提前进入实际吸附逻辑。
- 同时在 `CanvasCamera` 上补了两个 helper：
  - `worldDistance(forViewportDistance:)`
  - `expandedVisibleWorldRect(paddingInViewport:)`
- 这两个 helper 的作用是把后续“屏幕像素阈值”语义先固定下来，避免 `Phase 1` 再重复造轮子。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasAlignmentGuideSolver.swift
// 函数名: CanvasAlignmentAnchor.coordinate(in:) / CanvasAlignmentGuideSolver.solve(_:) / CanvasCamera.worldDistance(forViewportDistance:) / CanvasCamera.expandedVisibleWorldRect(paddingInViewport:)
// 功能说明: 修改后新增图片拖动对齐辅助线的共享 contract，先冻结 v1 的锚点、方向、reference source、solver request/result 和 viewport->world 距离换算规则；当前 solve(_:) 仍是 passthrough，占位给 Phase 1 的真实求解逻辑。
enum CanvasAlignmentAnchor: CaseIterable {
    case left
    case centerX
    case right
    case top
    case centerY
    case bottom

    var axis: CanvasAlignmentCoordinateAxis {
        switch self {
        case .left, .centerX, .right:
            return .x
        case .top, .centerY, .bottom:
            return .y
        }
    }

    func coordinate(in rect: CGRect) -> CGFloat {
        let standardizedRect = rect.standardized
        switch self {
        case .left:
            return standardizedRect.minX
        case .centerX:
            return standardizedRect.midX
        case .right:
            return standardizedRect.maxX
        case .top:
            return standardizedRect.minY
        case .centerY:
            return standardizedRect.midY
        case .bottom:
            return standardizedRect.maxY
        }
    }
}

struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
}

struct CanvasAlignmentSolveResult {
    let resolvedCenter: CGPoint
    let interactionState: CanvasAlignmentInteractionState?

    static func passthrough(
        proposedCenter: CGPoint
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult(
            resolvedCenter: proposedCenter,
            interactionState: nil
        )
    }
}

// Alignment solving stays axis-aligned in v1: all snap candidates come from
// board/item world frames plus centers, not rotated quads or transformed edges.
struct CanvasAlignmentGuideSolver {
    var configuration: CanvasAlignmentSolverConfiguration = .default

    func solve(
        _ request: CanvasAlignmentSolveRequest
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult.passthrough(
            proposedCenter: request.proposedCenter
        )
    }
}

extension CanvasCamera {
    func worldDistance(
        forViewportDistance viewportDistance: CGFloat
    ) -> CGFloat {
        guard zoomScale > 0 else {
            return viewportDistance
        }

        return viewportDistance / zoomScale
    }

    func expandedVisibleWorldRect(
        paddingInViewport viewportPadding: CGFloat
    ) -> CGRect {
        let paddingInWorld = worldDistance(
            forViewportDistance: max(viewportPadding, 0)
        )
        return visibleWorldRect.insetBy(
            dx: -paddingInWorld,
            dy: -paddingInWorld
        )
    }
}
```

## 修改二：新增 transient 对齐交互状态

### 修改前

- `CanvasInlineEditState.swift` 里只有：
  - `CanvasRotationPreviewState`
  - `CanvasRotationInteractionState`
  - `CanvasInlineEditState`
- 也就是说，项目里还没有一个与“旋转交互态”平级的“对齐交互态”数据结构。
- 如果不先补这一层，后续 `Phase 2` 到 `Phase 4` 很容易把对齐线状态散落到控制器或 viewport 层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: CanvasRotationInteractionState / CanvasInlineEditState
// 功能说明: 修改前这里只有旋转相关的 transient state；alignment guides 还没有运行期状态承载体。
struct CanvasRotationInteractionState {
    let itemID: CanvasItemID
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop/text drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasItemID
    private var session: CanvasInlineEditSession
}
```

### 修改后

- 在 `CanvasRotationInteractionState` 和 `CanvasInlineEditState` 之间新增了 `CanvasAlignmentInteractionState`。
- 这次新增的字段非常克制，只保留了 `Phase 0` 必须冻结的最小 contract：
  - `itemID`
  - `guides`
  - `xMatch`
  - `yMatch`
  - `isActive`
- 这使得后续可以像对待旋转交互态一样，把 alignment state 严格限定在 transient 层，不污染 `BoardRuntimeState` 和 `BoardHistorySnapshot`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasInlineEditState.swift
// 函数名: CanvasAlignmentInteractionState
// 功能说明: 修改后新增对齐辅助线运行期状态；它只服务拖拽期的 solver / renderer / viewport，不参与持久化和 history snapshot 比较。
struct CanvasRotationInteractionState {
    let itemID: CanvasItemID
}

// Like rotation interaction state, alignment guides stay transient and never
// enter BoardRuntimeState / history snapshots.
struct CanvasAlignmentInteractionState: Equatable {
    let itemID: CanvasItemID
    let guides: [CanvasAlignmentGuide]
    let xMatch: CanvasAlignmentMatch?
    let yMatch: CanvasAlignmentMatch?

    var isActive: Bool {
        guides.isEmpty == false || xMatch != nil || yMatch != nil
    }
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop/text drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasItemID
    private var session: CanvasInlineEditSession
}
```

## 修改三：扩展 interaction overlay 契约

### 修改前

- `CanvasRenderSnapshot.swift` 中的 transient interaction overlay 只有旋转一种类型。
- 具体来说：
  - `CanvasInteractionOverlayKind` 只有 `.rotation`
  - `CanvasInteractionRenderOverlayPayload` 只有 `.rotation(CanvasRotationInteractionOverlayPayload)`
- 这意味着 renderer -> snapshot -> viewport 这条共享通道还不能承载 alignment overlay。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasInteractionOverlayKind / CanvasInteractionRenderOverlayPayload
// 功能说明: 修改前 transient interaction overlay 只支持 rotation，alignment overlay 还没有合法的 kind 和 payload。
enum CanvasInteractionOverlayKind {
    case rotation
}

enum CanvasInteractionRenderOverlayPayload {
    case rotation(CanvasRotationInteractionOverlayPayload)
}
```

### 修改后

- 为 interaction overlay 正式扩了 alignment 契约：
  - `CanvasInteractionOverlayKind.alignment`
  - `CanvasAlignmentInteractionOverlayPayload`
  - `CanvasInteractionRenderOverlayPayload.alignment(...)`
- 这一步非常关键，因为后续 `Phase 2` 的 renderer 接线就可以沿用现有 rotation HUD 的共享通道，而不是重新造一套平台私有 overlay 管线。
- `CanvasAlignmentInteractionOverlayPayload` 当前只定义了：
  - `guideSegments`
  - `xMatch`
  - `yMatch`
  - `isActive`
- 这说明当前阶段只冻结“renderer 最终需要交给 viewport 画什么”，但还没有实现“renderer 何时生成这些内容”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasInteractionOverlayKind / CanvasAlignmentInteractionOverlayPayload / CanvasInteractionRenderOverlayPayload
// 功能说明: 修改后把 alignment overlay 纳入现有 transient interaction overlay 管道，为后续 renderer -> snapshot -> viewport 链路提供合法的共享载体。
enum CanvasInteractionOverlayKind {
    case rotation
    case alignment
}

// Alignment overlay also stays in transient interaction space; the renderer
// will later map world-space guides into these screen-space segments.
struct CanvasAlignmentInteractionOverlayPayload {
    let guideSegments: [CanvasInteractionLineSegment]
    let xMatch: CanvasAlignmentMatch?
    let yMatch: CanvasAlignmentMatch?
    let isActive: Bool
}

enum CanvasInteractionRenderOverlayPayload {
    case rotation(CanvasRotationInteractionOverlayPayload)
    case alignment(CanvasAlignmentInteractionOverlayPayload)
}
```

## 修改四：在双端 viewport 补齐 alignment case 的编译占位

### 修改前

- iOS / macOS 的 `refreshInteractionOverlay()` 只认识 `.rotation`。
- 一旦在 `CanvasInteractionOverlayKind` 中新增 `.alignment`，双端 viewport 的 `switch` 就会立刻变成不完备分支。
- 所以只扩契约还不够，必须同步补齐双端分支，哪怕当前阶段仍然不画任何对齐线。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift、MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改前双端 viewport 的 interaction overlay 刷新逻辑只处理 rotation case。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    }
}
```

### 修改后

- iOS / macOS 两端都新增了 `.alignment` 分支。
- 但这个分支当前并不做绘制，而是显式 `hideInteractionOverlay()`，原因是：
  - `Phase 0` 只保证新契约能通过编译
  - `Phase 5` 才会正式实现 alignment line 的实际绘制
- 这样做的好处是：不会因为先扩枚举就被迫提前进入视觉实现，同时也不会留下“新增 case 但平台侧漏处理”的编译/运行时风险。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift、MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshInteractionOverlay()
// 功能说明: 修改后双端 viewport 都补齐了 alignment case；当前阶段仅做编译占位和显式隐藏，不提前绘制辅助线。
private func refreshInteractionOverlay() {
    guard let interactionOverlay = snapshot.interactionOverlay else {
        hideInteractionOverlay()
        return
    }

    switch interactionOverlay.kind {
    case .rotation:
        refreshRotationInteractionOverlay(from: interactionOverlay)
    case .alignment:
        // Phase 0 only lands the contract; viewport drawing comes later.
        hideInteractionOverlay()
    }
}
```

## 本次修改后的实际状态

- 已经落下来的能力：
  - 共享 solver contract
  - alignment transient state
  - alignment overlay payload
  - 双端 viewport 的 `.alignment` 编译占位
- 还没有落下来的能力：
  - 真实候选搜索
  - 真实吸附修正
  - `EditorSession` / `Renderer` 接线
  - iOS/macOS 控制器拖拽接入
  - 辅助线实际显示
- 因此当前行为仍然是：
  - 工程可以编译
  - 项目中还看不到对齐辅助线
  - 拖动图片时还不会发生吸附

## 验证结果

- `git status --short` 与当前工作区内容一致，说明本记录覆盖了本次 `Phase 0` 的全部实际改动面。
- `ReadLints` 未发现本次修改相关文件新增 lint 错误。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" build` 已通过，说明本次“只扩契约、不接行为”的改动至少在 macOS 目标上可编译。
