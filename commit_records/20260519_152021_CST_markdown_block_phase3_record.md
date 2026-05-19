# 20260519_152021_CST_markdown_block_phase3_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 3。
  - 从根因上修正 markdown block 的 resize 语义，使其与普通 text 分叉，满足“resize 改容器、内容字号不随之缩放”的交互约束。
  - 新增共享 `SelectionAccessory` 基础设施，为后续阶段 4 / 5 的 iOS / macOS 接线提供统一状态、布局与 host view 壳层。
  - 用测试锁定 markdown 单选保留 resize handles、markdown resize 不改字号、accessory 默认动作顺序与避让布局行为。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryLayoutSolver.swift`
  - `MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `MyCanvas_Ver_0Tests/SelectionAccessoryLayoutSolverTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示本次阶段 3 涉及 `4` 个已跟踪修改文件和 `4` 个新增文件。
  - 生成本记录前，`git diff --stat` 显示：`4 files changed, 121 insertions(+), 18 deletions(-)`。
  - 上述 `git diff --stat` 只统计已跟踪文件，不包含本次新增的 `SelectionAccessoryState.swift`、`SelectionAccessoryLayoutSolver.swift`、`SelectionAccessoryHostView.swift`、`SelectionAccessoryLayoutSolverTests.swift`。
- 本记录不包含：
  - 阶段 4 的 iOS 最简 markdown 编辑器入口。
  - 阶段 5 的 board list / minimap / macOS 编辑 parity 收口。
  - 任何 git 提交行为。

## 当前 changes 摘要

- `CanvasSelectionTransformState` 不再把所有 item 的 resize 都绑定到同一个等比 `scale`；markdown 现在使用宽高独立缩放，text 仍保持“缩放=改字号”，handDrawing 仍保持纸张尺寸归一。
- `CanvasChromeLayoutContext` 新增 `selectionAccessory` blocker kind，给 accessory 的后续布局避让留出共享类型入口。
- 新增 `SelectionAccessoryState`，把 markdown accessory 的默认动作顺序统一固化为 `Edit / - / +`。
- 新增 `SelectionAccessoryLayoutSolver`，以选区框 `anchorRect` 为锚点解析 accessory 位置，并避让现有 chrome blocker 与锚点扩展区。
- 新增双端共享 `SelectionAccessoryHostView`，当前只提供状态承载、布局与按钮壳层，不接阶段 4 / 5 的平台控制器。
- `CanvasRenderer.swift` 本阶段没有发生代码修改；因为现有 `effectiveItem.kind == .text ? [] : makeCornerEditHandles(...)` 逻辑已经让单选 markdown 保留 resize handles，这次通过测试把该行为锁定。

## 修改一：从根因上分叉 markdown resize 语义

### 1.1 `CanvasSelectionTransformState`

#### 修改前

- `CanvasSelectionResizeDraft` 只有单一 `scale`。
- `scaledGeometry(...)`、`resizedMemberGeometries(...)`、`resizedMemberItems(...)` 都默认所有元素等比缩放。
- `markdown` 虽然没有复用 `resizedTextItem(...)` 去改字号，但它仍会跟着共享 `scale` 做等比缩放，无法满足“自由拉伸任意宽高”的需求。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名: resizeDraft(handleRole:draggedWorldCorner:minimumScale:) / scaledGeometry(from:using:) / resizedItem(_:using:)
// 功能说明: 修改前所有选区 resize 都只生成单一 scale，markdown 也只能跟着做等比容器缩放。
private func resizeDraft(
    handleRole: CanvasSelectionHandleRole,
    draggedWorldCorner: CGPoint,
    minimumScale: CGFloat
) -> CanvasSelectionResizeDraft? {
    let widthScale = abs(constrainedCorner.x - fixedCorner.x) / selectionBounds.width
    let heightScale = abs(constrainedCorner.y - fixedCorner.y) / selectionBounds.height
    let scale = max(widthScale, heightScale, minimumScale)
    guard scale.isFinite else {
        return nil
    }

    return CanvasSelectionResizeDraft(
        fixedCorner: fixedCorner,
        scale: scale
    )
}

private func scaledGeometry(
    from geometry: CanvasBoardItemGeometry,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItemGeometry {
    CanvasBoardItemGeometry(
        itemID: geometry.itemID,
        center: canvasScalePoint(
            geometry.center,
            around: resizeDraft.fixedCorner,
            by: resizeDraft.scale
        ),
        size: CGSize(
            width: geometry.size.width * resizeDraft.scale,
            height: geometry.size.height * resizeDraft.scale
        ),
        rotationRadians: geometry.rotationRadians
    )
}

private func resizedItem(
    _ item: CanvasBoardItem,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItem {
    let scaledItemGeometry = scaledGeometry(
        from: CanvasBoardItemGeometry(item: item),
        using: resizeDraft
    )
    switch item {
    case let .text(textItem):
        return .text(
            resizedTextItem(
                textItem,
                scaledCenter: scaledItemGeometry.center,
                scale: resizeDraft.scale
            )
        )
    case .markdown:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    case let .handDrawing(handDrawingItem):
        return .handDrawing(
            resizedHandDrawingItem(
                handDrawingItem,
                scaledCenter: scaledItemGeometry.center,
                scale: resizeDraft.scale
            )
        )
    default:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    }
}
```

#### 修改后

- `CanvasSelectionResizeDraft` 改为显式携带 `widthScale` / `heightScale`，并保留 `uniformScale` 作为 text / image / handDrawing 的兼容输入。
- 新增 `CanvasSelectionResizeScalingMode` 和 `resizeScalingMode(for:)`，按 item kind 决定 resize 语义：markdown 走 `.nonUniform`，其他仍走 `.uniform`。
- `scaledGeometry(...)` 和 `canvasScalePoint(...)` 改为接受 `CGSize` 形式的缩放因子。
- `text` 继续使用 `uniformScale` 走字号重算，`handDrawing` 改为接收 `scaledItemGeometry.size`，`markdown` 则只提交新的几何，不碰内容字号。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizeDraft(handleRole:draggedWorldCorner:minimumScale:) / scaledGeometry(from:using:scalingMode:) / resizedItem(_:using:)
// 功能说明: 修改后 markdown 走宽高独立缩放，text/handDrawing 继续沿用既有等比 resize 语义。
private func resizeDraft(
    handleRole: CanvasSelectionHandleRole,
    draggedWorldCorner: CGPoint,
    minimumScale: CGFloat
) -> CanvasSelectionResizeDraft? {
    let widthScale = abs(constrainedCorner.x - fixedCorner.x) / selectionBounds.width
    let heightScale = abs(constrainedCorner.y - fixedCorner.y) / selectionBounds.height
    guard widthScale.isFinite, heightScale.isFinite else {
        return nil
    }

    return CanvasSelectionResizeDraft(
        fixedCorner: fixedCorner,
        widthScale: max(widthScale, minimumScale),
        heightScale: max(heightScale, minimumScale)
    )
}

private func scaledGeometry(
    from geometry: CanvasBoardItemGeometry,
    using resizeDraft: CanvasSelectionResizeDraft,
    scalingMode: CanvasSelectionResizeScalingMode
) -> CanvasBoardItemGeometry {
    let resolvedScale = resolvedScale(
        from: resizeDraft,
        scalingMode: scalingMode
    )
    return CanvasBoardItemGeometry(
        itemID: geometry.itemID,
        center: canvasScalePoint(
            geometry.center,
            around: resizeDraft.fixedCorner,
            by: resolvedScale
        ),
        size: CGSize(
            width: geometry.size.width * resolvedScale.width,
            height: geometry.size.height * resolvedScale.height
        ),
        rotationRadians: geometry.rotationRadians
    )
}

private func resizedItem(
    _ item: CanvasBoardItem,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItem {
    let scalingMode = resizeScalingMode(for: item.id)
    let scaledItemGeometry = scaledGeometry(
        from: CanvasBoardItemGeometry(item: item),
        using: resizeDraft,
        scalingMode: scalingMode
    )
    switch item {
    case let .text(textItem):
        return .text(
            resizedTextItem(
                textItem,
                scaledCenter: scaledItemGeometry.center,
                scale: resizeDraft.uniformScale
            )
        )
    case .markdown:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    case let .handDrawing(handDrawingItem):
        return .handDrawing(
            resizedHandDrawingItem(
                handDrawingItem,
                scaledCenter: scaledItemGeometry.center,
                proposedSize: scaledItemGeometry.size
            )
        )
    default:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    }
}

private func resizeScalingMode(
    for itemID: CanvasItemID
) -> CanvasSelectionResizeScalingMode {
    switch sourceItemsByID[itemID]?.kind {
    case .some(.markdown):
        return .nonUniform
    case .some(.image), .some(.text), .some(.handDrawing), .none:
        return .uniform
    }
}

private struct CanvasSelectionResizeDraft {
    let fixedCorner: CGPoint
    let widthScale: CGFloat
    let heightScale: CGFloat

    var uniformScale: CGFloat {
        max(widthScale, heightScale)
    }
}
```

## 修改二：为块旁悬浮条补共享 accessory 基础设施

### 2.1 `CanvasChromeLayoutContext`

#### 修改前

- chrome blocker kind 里还没有 accessory 对应的占位类型。
- 这意味着后续如果要让 accessory 自己参与布局避让，没有统一 kind 可以拿来排除或回填。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift（修改前）
// 类型名: CanvasChromeBlockerKind
// 功能说明: 修改前 chrome blocker 尚未为 selection accessory 预留共享 kind。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case toolbar
    case miniMap
    case contextMenu
}
```

#### 修改后

- 新增 `selectionAccessory` kind，为 accessory 的布局避让和后续控制器接线提供共享 blocker 类型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 类型名: CanvasChromeBlockerKind
// 功能说明: 修改后 chrome layout context 为 selection accessory 预留共享 blocker kind。
enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case modeToggle
    case toolbar
    case miniMap
    case contextMenu
    case selectionAccessory
}
```

### 2.2 `SelectionAccessoryState`

#### 修改前

- 工程内不存在 accessory 的共享状态模型。
- `Edit / - / +` 的默认动作顺序与命令描述还没有统一封装入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryState.swift（修改前）
// 类型名: SelectionAccessoryState
// 功能说明: 修改前工程内不存在 selection accessory 的共享状态与动作描述文件。
// 此文件不存在。
```

#### 修改后

- 新增 `SelectionAccessoryActionDescriptor`、`SelectionAccessoryActionState`、`SelectionAccessoryState`。
- 提供 `SelectionAccessoryState.markdown(...)` 工厂方法，把 markdown accessory 默认动作顺序固定为 `beginMarkdownEdit`、`decreaseMarkdownContentSize`、`increaseMarkdownContentSize`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryState.swift
// 类型名: SelectionAccessoryState
// 功能说明: 修改后新增 accessory 共享状态模型，并为 markdown accessory 统一产出 Edit / - / + 的默认动作顺序。
struct SelectionAccessoryActionDescriptor: Equatable {
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let isActive: Bool

    init(commandDescriptor: CanvasCommandDescriptor) {
        self.init(
            title: commandDescriptor.title,
            systemImageName: commandDescriptor.systemImageName,
            isEnabled: commandDescriptor.isEnabled,
            isActive: commandDescriptor.isActive
        )
    }
}

struct SelectionAccessoryActionState: Equatable {
    let commandID: CanvasCommandID
    let descriptor: SelectionAccessoryActionDescriptor
}

struct SelectionAccessoryState: Equatable {
    let itemID: CanvasItemID
    let anchorRect: CGRect
    let actionStates: [SelectionAccessoryActionState]

    static func markdown(
        itemID: CanvasItemID,
        anchorRect: CGRect,
        editDescriptor: CanvasCommandDescriptor,
        decreaseDescriptor: CanvasCommandDescriptor,
        increaseDescriptor: CanvasCommandDescriptor
    ) -> SelectionAccessoryState {
        SelectionAccessoryState(
            itemID: itemID,
            anchorRect: anchorRect,
            actionStates: [
                SelectionAccessoryActionState(
                    commandID: editDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: editDescriptor
                    )
                ),
                SelectionAccessoryActionState(
                    commandID: decreaseDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: decreaseDescriptor
                    )
                ),
                SelectionAccessoryActionState(
                    commandID: increaseDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: increaseDescriptor
                    )
                )
            ]
        )
    }
}
```

### 2.3 `SelectionAccessoryLayoutSolver`

#### 修改前

- 工程内没有 selection accessory 的共享布局求解器。
- 也没有把选中框自身的扩展区域当成避让区，因此即便未来 accessory 能显示，也容易在顶部空间不足时被 clamp 回选中块上方附近。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryLayoutSolver.swift（修改前）
// 类型名: SelectionAccessoryLayoutSolver
// 功能说明: 修改前工程内不存在 selection accessory 的共享布局求解器。
// 此文件不存在。
```

#### 修改后

- 新增 `SelectionAccessoryLayoutConfiguration` 与 `SelectionAccessoryLayoutSolver`。
- solver 会基于 `anchorRect` 计算 `aboveCentered / belowCentered / aboveTrailing / belowTrailing` 候选位置。
- 除了避让 chrome blocker，还会把 `anchorRect` 扩展成 `anchorExclusionRect`，避免 accessory 被 clamp 后重新压回选区本体附近。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryLayoutSolver.swift
// 类型名: SelectionAccessoryLayoutSolver
// 功能说明: 修改后新增 accessory 共享布局求解器，负责锚点布局、chrome 避让和锚点扩展区避让。
struct SelectionAccessoryLayoutConfiguration: Equatable, Sendable {
    var minimumWidth: CGFloat
    var edgeInset: CGFloat
    var anchorSpacing: CGFloat
    var chromeClearance: CGFloat
}

struct SelectionAccessoryLayoutSolver {
    private enum Placement: CaseIterable {
        case aboveCentered
        case belowCentered
        case aboveTrailing
        case belowTrailing
    }

    func resolveAccessoryFrame(
        anchorRect: CGRect,
        preferredSize: CGSize,
        layoutContext: CanvasChromeLayoutContext,
        configuration: SelectionAccessoryLayoutConfiguration = .init()
    ) -> CGRect? {
        let chromeBlockerRects = layoutContext
            .occupiedRects(excluding: [.selectionAccessory])
            .compactMap(CanvasChromeLayoutGeometry.sanitizedRect)
            .map {
                $0.insetBy(
                    dx: -configuration.chromeClearance,
                    dy: -configuration.chromeClearance
                )
            }
        let anchorExclusionRect = sanitizedAnchorRect.insetBy(
            dx: -configuration.anchorSpacing,
            dy: -configuration.anchorSpacing
        )
        let blockerRects = chromeBlockerRects + [anchorExclusionRect]

        for placement in Placement.allCases {
            let candidateFrame = clampedFrame(
                frame(
                    for: placement,
                    anchorRect: sanitizedAnchorRect,
                    size: resolvedSize,
                    anchorSpacing: configuration.anchorSpacing
                ),
                within: layoutBounds
            )
            let overlapScore = totalOverlapArea(
                of: candidateFrame,
                with: blockerRects
            )
            if overlapScore == 0 {
                return candidateFrame.integral
            }
        }

        return bestFrame?.integral
    }
}
```

### 2.4 `SelectionAccessoryHostView`

#### 修改前

- 工程内没有 selection accessory 的 host view。
- 阶段 4 / 5 若直接在平台控制器里临时拼按钮和布局，后续 iOS / macOS 会再次分叉出两套 UI 壳层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift（修改前）
// 类型名: SelectionAccessoryHostView
// 功能说明: 修改前工程内不存在 selection accessory 的双端 host view 壳层。
// 此文件不存在。
```

#### 修改后

- 新增共享 `SelectionAccessoryHostView`，iOS / macOS 双端都提供 `apply(state:layoutContext:)`、`updateLayout(layoutContext:)`、`dismiss()` 壳层。
- 当前 host view 只做状态承载、按钮生成、命令回调与布局，不接具体控制器生命周期和命令分发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift
// 函数名: apply(state:layoutContext:) / updateLayout(layoutContext:) / dismiss()
// 功能说明: 修改后新增双端共享 accessory host view，承载状态、布局与按钮壳层，为阶段 4 / 5 的平台接线做准备。
#if os(iOS)
final class SelectionAccessoryHostView: UIView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    func apply(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state

        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }

        rebuildButtons(for: state)
        isHidden = false
        containerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }

    func updateLayout(layoutContext: CanvasChromeLayoutContext) {
        guard let currentState else {
            return
        }
        let preferredSize = preferredAccessorySize()
        guard let accessoryFrame = layoutSolver.resolveAccessoryFrame(
            anchorRect: currentState.anchorRect,
            preferredSize: preferredSize,
            layoutContext: layoutContext
        ) else {
            updateContainerConstraints(.zero)
            return
        }
        updateContainerConstraints(accessoryFrame.integral)
    }
}
#elseif os(macOS)
final class SelectionAccessoryHostView: NSView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    var onDismissRequested: (() -> Void)?

    func apply(
        state: SelectionAccessoryState?,
        layoutContext: CanvasChromeLayoutContext
    ) {
        currentState = state
        guard let state, state.isEmpty == false else {
            dismiss()
            return
        }
        rebuildButtons(for: state)
        isHidden = false
        containerView.isHidden = false
        updateLayout(layoutContext: layoutContext)
    }
}
#endif
```

## 修改三：补测试锁定 markdown 交互语义与 accessory 布局契约

### 3.1 `CanvasSelectionTransformStateTests`

#### 修改前

- 现有测试覆盖了 text resize 改字号、handDrawing resize 保持纸张比例。
- 但还没有覆盖 markdown resize 的关键契约：容器可自由拉伸，样式和 markdown source 不应被 resize 改写。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift（修改前）
// 函数名: testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()
// 功能说明: 修改前不存在 markdown resize 语义测试，无法自动锁定“resize 改容器、不改字号”。
// 此函数不存在。
```

#### 修改后

- 新增 `testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()`。
- 该测试验证 markdown resize 后：
  - `center` 和 `size` 按非等比几何结果更新；
  - `style` 不变；
  - `markdownSource` 不变。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数名: testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()
// 功能说明: 修改后新增 markdown resize 语义测试，锁定容器自由拉伸但内容样式不变的契约。
func testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry() throws {
    let markdownStyle = CanvasTextStyle(fontSize: 20)
    let markdownItem = CanvasMarkdownItem(
        markdownSource: "## Title\n\nBody",
        style: markdownStyle,
        center: CGPoint(x: 40, y: 30),
        size: CGSize(width: 80, height: 60)
    )
    let snapshot = CanvasSelectionTransformSnapshot(
        primaryItemID: markdownItem.id,
        memberItems: [.markdown(markdownItem)],
        selectionBounds: CGRect(x: 0, y: 0, width: 80, height: 60)
    )

    let resizedItems = try XCTUnwrap(
        snapshot.resizedMemberItems(
            handleRole: .bottomTrailing,
            draggedWorldCorner: CGPoint(x: 160, y: 90),
            minimumScale: 0.1
        )
    )
    let resizedMarkdownItem = try XCTUnwrap(
        resizedItems.first?.markdownItem
    )

    XCTAssertEqual(resizedMarkdownItem.center, CGPoint(x: 80, y: 45))
    XCTAssertEqual(resizedMarkdownItem.size, CGSize(width: 160, height: 90))
    XCTAssertEqual(resizedMarkdownItem.style, markdownItem.style)
    XCTAssertEqual(
        resizedMarkdownItem.markdownSource,
        markdownItem.markdownSource
    )
}
```

### 3.2 `CanvasEditorSessionAlignmentOverlayTests`

#### 修改前

- 已有测试覆盖“单选 text 无 handles”“单选 image 有 handles”。
- 但还没有自动化约束“单选 markdown 也应保留 handles”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift（修改前）
// 函数名: testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection()
// 功能说明: 修改前不存在 markdown 单选 handles 测试，renderer 当前行为未被测试锁定。
// 此函数不存在。
```

#### 修改后

- 新增 `testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection()`。
- 该测试用例没有修改 `CanvasRenderer.swift` 本体，而是把“markdown 单选保留 handles”这条现有行为锁定下来。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection()
// 功能说明: 修改后新增 markdown 单选 handles 测试，锁定现有 renderer 的正确行为。
func testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection() throws {
    let item = CanvasMarkdownItem(
        markdownSource: "## Markdown",
        center: CGPoint(x: 40, y: 20),
        size: CGSize(width: 140, height: 84)
    )
    let session = makeAlignmentOverlayTestSession(
        items: [.markdown(item)],
        selectedItemID: item.id
    )

    let snapshot = session.makeCanvasSnapshot()
    let editOverlay = try XCTUnwrap(snapshot.editOverlay)

    XCTAssertEqual(editOverlay.itemID, item.id)
    XCTAssertEqual(
        editOverlay.handles.count,
        CanvasSelectionHandleRole.allCases.count
    )
}
```

### 3.3 `SelectionAccessoryLayoutSolverTests`

#### 修改前

- accessory 相关共享类型是本阶段新增的，因此还没有任何定向测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/SelectionAccessoryLayoutSolverTests.swift（修改前）
// 类型名: SelectionAccessoryLayoutSolverTests
// 功能说明: 修改前工程内不存在 selection accessory 布局与状态定向测试。
// 此文件不存在。
```

#### 修改后

- 新增 `SelectionAccessoryLayoutSolverTests`，锁定三类行为：
  - markdown accessory 默认动作顺序为 `Edit / - / +`；
  - 顶部有空间时优先放在 anchorRect 上方；
  - 上方空间不足或有 blocker 时回落到下方。

```swift
// 文件路径: MyCanvas_Ver_0Tests/SelectionAccessoryLayoutSolverTests.swift
// 类型名: SelectionAccessoryLayoutSolverTests
// 功能说明: 修改后新增 accessory 状态与布局测试，锁定默认动作顺序与锚点避让行为。
final class SelectionAccessoryLayoutSolverTests: XCTestCase {
    func testMarkdownAccessoryStateOrdersEditDecreaseIncrease() {
        let state = SelectionAccessoryState.markdown(
            itemID: UUID(),
            anchorRect: CGRect(x: 120, y: 140, width: 80, height: 60),
            editDescriptor: CanvasCommandDescriptor(
                id: .beginMarkdownEdit,
                title: "Edit Markdown",
                systemImageName: "pencil",
                isEnabled: true,
                isActive: false
            ),
            decreaseDescriptor: CanvasCommandDescriptor(
                id: .decreaseMarkdownContentSize,
                title: "Smaller Markdown",
                systemImageName: "minus",
                isEnabled: true,
                isActive: false
            ),
            increaseDescriptor: CanvasCommandDescriptor(
                id: .increaseMarkdownContentSize,
                title: "Larger Markdown",
                systemImageName: "plus",
                isEnabled: true,
                isActive: false
            )
        )

        XCTAssertEqual(
            state.actionStates.map(\.commandID),
            [
                .beginMarkdownEdit,
                .decreaseMarkdownContentSize,
                .increaseMarkdownContentSize
            ]
        )
    }

    func testResolveAccessoryFrameFallsBelowWhenAbovePlacementWouldOverlapAnchor() throws {
        let solver = SelectionAccessoryLayoutSolver()
        let anchorRect = CGRect(x: 150, y: 20, width: 100, height: 60)
        let frame = try XCTUnwrap(
            solver.resolveAccessoryFrame(
                anchorRect: anchorRect,
                preferredSize: CGSize(width: 180, height: 44),
                layoutContext: makeSelectionAccessoryLayoutContext()
            )
        )

        XCTAssertGreaterThan(frame.minY, anchorRect.maxY)
        XCTAssertEqual(frame.minY, anchorRect.maxY + 10, accuracy: 0.0001)
    }
}
```

## 补充说明

- 计划中的 `CanvasRenderer.swift`“确保 markdown 单选像 image/handDrawing 一样显示 resize handles”在进入本阶段实现前已经被现有逻辑满足：
  - `selectionHandles = effectiveItem.kind == .text ? [] : makeCornerEditHandles(...)`
  - 因为 markdown 的 `kind` 是 `.markdown`，所以它不会走 text 的空 handles 分支。
- 因此本阶段没有为了“对齐计划文字”去额外改动 `CanvasRenderer.swift`，而是新增了 `CanvasEditorSessionAlignmentOverlayTests` 来锁定这一既有正确行为。

## 验证结果

- `ReadLints` 检查本次修改文件，无新增 linter 问题。
- 已执行并通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests -only-testing:MyCanvas_Ver_0Tests/SelectionAccessoryLayoutSolverTests`
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'`
- 实施过程中出现过一次 `CanvasSelectionTransformState.swift` 的编译错误：把 `scaledGeometry(...)` 从单表达式函数改成多行后漏写了 `return`，已在当前 changes 内修复，现状中不再保留该错误。
