# 20260520_152913_markdown_width_only_resize_record

## 记录范围

- 记录内容：
  - 将 markdown block 的 resize 语义从“四角二维缩放”收口为“只调整宽度”。
  - 单选 markdown 时，selection handle 从四个角改成左右两条边。
  - 多选且成员全部为 markdown 时，也改成左右两条边。
  - 混选场景保持现状，不引入新的 width-only 语义。
  - 拖拽预览阶段和最终提交阶段统一改成“按新宽度实时/最终重测 markdown 高度”。
  - 补充 selection overlay、selection transform、markdown finalize commit 的回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
- 参考现状：
  - `git status --short` 显示当前工作区共有 `11` 个已跟踪代码文件处于修改状态。
  - `git diff --stat -- <本次修复文件>` 显示当前这次修复为：`11 files changed, 620 insertions(+), 53 deletions(-)`。
  - 本记录创建前，本次代码修复没有新增未跟踪代码文件；新增文件只有本记录自身。
- 本记录不包含：
  - 任何 git 提交行为。
  - 混选场景交互语义变更。
  - 任何 `.cursor/plans/*.md` 内容改动。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_markdown_width_only_resize_record"
# 功能说明: 使用系统 date 命令生成本记录文件的时间戳前缀。
20260520_152913_markdown_width_only_resize_record
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录创建本记录前的工作区状态；本次 width-only resize 相关代码变更共 11 个文件。
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
 M MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- "MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift" "MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift" "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift" "MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift" "MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift"
# 功能说明: 统计本次 markdown width-only resize 修复的真实改动量。
.../Canvas/Core/CanvasRenderSnapshot.swift         | 21 ++++-
MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    | 51 ++++++++++-
.../Canvas/Editing/CanvasEditorSession.swift       | 18 ++++
.../Editing/CanvasSelectionTransformState.swift    | 90 ++++++++++++++++++--
.../iOS/Canvas/iOSCanvasViewportView.swift         | 38 ++++++++-
.../Platform/iOS/iOSViewController.swift           | 98 ++++++++++++++++++----
.../macOS/Canvas/macOSCanvasViewportView.swift     | 40 ++++++++-
.../Platform/macOS/macOSViewController.swift       | 98 ++++++++++++++++++----
.../CanvasCommandPolicyParityTests.swift           | 59 +++++++++++++
.../CanvasEditorSessionAlignmentOverlayTests.swift | 69 +++++++++++++--
.../CanvasSelectionTransformStateTests.swift       | 91 ++++++++++++++++++++
11 files changed, 620 insertions(+), 53 deletions(-)
```

## 当前 changes 摘要

- markdown 的 selection handle 角色从“只支持四角”扩展到“支持左右边”，但新语义只在 `单选 markdown` 和 `全 markdown 多选` 下启用。
- renderer 现在会根据选中内容类型决定 handle 形态：`text` 仍无 resize handle，`markdown` 进入 width-only handles，其他类型和混选保持四角 handle。
- iOS/macOS viewport 不再把所有 selection handle 都画成小方块；`leading / trailing` 会绘制成长条边 handle，四角 handle 保持原样。
- 交互层不再把 markdown width-only drag 当作普通二维缩放：拖拽中只改变宽度，实时重测 markdown 内容高度并更新中心点。
- finalize commit 也同步支持 `leading / trailing`，保证“拖拽预览”和“最终提交”使用同一套 fixed-edge 语义。

## 修改一：Selection handle 角色与 renderer 输出收口到 width-only contract

### 1.1 修改前

- `CanvasSelectionHandleRole` 只有四个角：`topLeading / topTrailing / bottomLeading / bottomTrailing`。
- `CanvasRenderer.makeSelectionEditOverlay(...)` 对单选 markdown 和普通多选一视同仁，除了 text 以外都直接走 `makeCornerEditHandles(...)`。
- 这意味着 markdown 即使语义上只需要调宽度，选中后仍会暴露四角二维缩放 affordance。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前）
// 函数名: CanvasSelectionHandleRole / CanvasEditHandleRole.selectionHandleRole
// 功能说明: 修改前 selection 只有四个角 handle，没有 leading / trailing 这样的 width-only 角色。
enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

extension CanvasEditHandleRole {
    var selectionHandleRole: CanvasSelectionHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .top, .trailing, .bottom, .leading, .rotate:
            return nil
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前除了单选 text 不显示 resize handle，其余单选/多选场景都直接产出四角 handle。
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
    selectionHandles = effectiveItem.kind == .text
        ? []
        : makeCornerEditHandles(for: screenQuad)
} else {
    let groupWorldBounds = groupSelectionWorldBounds(for: selectedItems)
    subject = .group(
        primaryItemID: resolvedPrimarySelectedItemID,
        memberItemIDs: selectedItems.map(\.id)
    )
    worldQuad = CanvasQuad(rect: groupWorldBounds)
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(
        CGPoint(x: groupWorldBounds.midX, y: groupWorldBounds.midY)
    )
    selectionHandles = makeCornerEditHandles(for: screenQuad)
}
```

### 1.2 修改后

- `CanvasSelectionHandleRole` 新增 `leading / trailing`，并显式暴露 `isWidthOnly`。
- `CanvasEditHandleRole.selectionHandleRole` 现在允许 `leading / trailing` 映射回 selection handle 角色。
- `CanvasRenderer` 新增：
  - `makeWidthOnlyEditHandles(...)`
  - `selectionEditHandles(forSingleSelectedItem:screenQuad:)`
  - `selectionEditHandles(forGroupSelectedItems:screenQuad:)`
- renderer 收口规则改为：
  - 单选 `text`：仍然无 resize handle
  - 单选 `markdown`：只出 `leading / trailing`
  - 多选且全是 `markdown`：只出 `leading / trailing`
  - 其他类型或混选：继续四角 handle

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasSelectionHandleRole / CanvasSelectionHandleRole.isWidthOnly / CanvasEditHandleRole.selectionHandleRole
// 功能说明: 修改后 selection handle 角色扩展到 leading / trailing，并允许交互层显式识别 width-only 语义。
enum CanvasSelectionHandleRole: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case leading
    case trailing
}

extension CanvasSelectionHandleRole {
    var isWidthOnly: Bool {
        switch self {
        case .leading, .trailing:
            return true
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return false
        }
    }
}

extension CanvasEditHandleRole {
    var selectionHandleRole: CanvasSelectionHandleRole? {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .top, .bottom, .rotate:
            return nil
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:) / makeWidthOnlyEditHandles(for:) / selectionEditHandles(forSingleSelectedItem:screenQuad:) / selectionEditHandles(forGroupSelectedItems:screenQuad:)
// 功能说明: 修改后 renderer 会按选中内容类型决定是输出四角 handle 还是 leading / trailing width-only handles。
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
    selectionHandles = selectionEditHandles(
        forSingleSelectedItem: effectiveItem,
        screenQuad: screenQuad
    )
} else {
    let groupWorldBounds = groupSelectionWorldBounds(for: selectedItems)
    subject = .group(
        primaryItemID: resolvedPrimarySelectedItemID,
        memberItemIDs: selectedItems.map(\.id)
    )
    worldQuad = CanvasQuad(rect: groupWorldBounds)
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(
        CGPoint(x: groupWorldBounds.midX, y: groupWorldBounds.midY)
    )
    selectionHandles = selectionEditHandles(
        forGroupSelectedItems: selectedItems,
        screenQuad: screenQuad
    )
}

private func makeWidthOnlyEditHandles(
    for screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    makeEditHandles(
        for: screenQuad,
        roles: [
            .leading,
            .trailing
        ]
    )
}

private func selectionEditHandles(
    forSingleSelectedItem item: CanvasBoardItem,
    screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    switch item.kind {
    case .text:
        return []
    case .markdown:
        return makeWidthOnlyEditHandles(for: screenQuad)
    case .image, .handDrawing:
        return makeCornerEditHandles(for: screenQuad)
    }
}

private func selectionEditHandles(
    forGroupSelectedItems items: [CanvasBoardItem],
    screenQuad: CanvasQuad
) -> [CanvasEditHandleGeometry] {
    guard items.isEmpty == false else {
        return []
    }
    if items.allSatisfy({ $0.kind == .markdown }) {
        return makeWidthOnlyEditHandles(for: screenQuad)
    }
    return makeCornerEditHandles(for: screenQuad)
}
```

## 修改二：iOS/macOS viewport 把 markdown width-only handle 画成左右边条

### 2.1 修改前

- `selectionHandlePath(...)` 不看 handle 角色，始终返回 `squareHandlePath(...)`。
- 因此即使后续想引入左右边 handle，视图层也只能画出方块点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: selectionHandlePath(centeredAt:rotationRadians:)
// 功能说明: 修改前所有 selection handle 都统一绘制成方块。
private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    squareHandlePath(
        centeredAt: center,
        size: selectionHandleSize,
        rotationRadians: rotationRadians
    )
}
```

### 2.2 修改后

- iOS / macOS 两端 viewport 都改成先按 `role` 分流。
- `leading / trailing` 改走 `edgeHandlePath(...)`，绘制为竖向圆角边条。
- 其余四角 handle 继续沿用原来的 `squareHandlePath(...)`，避免影响混选和其他 item 类型。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshSelectionChrome(from:) / selectionHandlePath(for:centeredAt:rotationRadians:) / edgeHandlePath(centeredAt:length:thickness:rotationRadians:)
// 功能说明: 修改后 leading / trailing selection handle 会画成边条，四角 handle 仍保留方块外观。
handleLayer.path = Self.selectionHandlePath(
    for: role,
    centeredAt: handle.screenCenter,
    rotationRadians: handle.screenRotationRadians
)

private static func selectionHandlePath(
    for role: CanvasSelectionHandleRole,
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    switch role {
    case .leading, .trailing:
        return edgeHandlePath(
            centeredAt: center,
            length: selectionEdgeHandleLength,
            thickness: selectionEdgeHandleThickness,
            rotationRadians: rotationRadians
        )
    case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
        break
    }
    return squareHandlePath(
        centeredAt: center,
        size: selectionHandleSize,
        rotationRadians: rotationRadians
    )
}

private static func edgeHandlePath(
    centeredAt center: CGPoint,
    length: CGFloat,
    thickness: CGFloat,
    rotationRadians: CGFloat
) -> CGPath {
    let localRect = CGRect(
        x: -thickness / 2,
        y: -length / 2,
        width: thickness,
        height: length
    )
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
    transform = transform.rotated(by: rotationRadians)
    let localPath = UIBezierPath(
        roundedRect: localRect,
        cornerRadius: thickness / 2
    )
    return localPath.cgPath.copy(using: &transform) ?? localPath.cgPath
}
```

## 修改三：拖拽预览、selection transform 与最终提交一起改成 width-only 语义

### 3.1 修改前

- `CanvasSelectionTransformState` 只有 `uniform / nonUniform` 两种缩放模式。
- markdown 在 selection transform 里虽然走 `nonUniform`，但本质还是“随拖拽直接拉伸容器几何”，不会在拖拽预览阶段按新宽度重测内容高度。
- `iOSViewController` / `macOSViewController` 的单选 resize 也统一按 `scale = max(widthScale, heightScale, minimumScale)` 算出新尺寸，语义上仍是二维缩放。
- `CanvasEditorSession` 的 finalize helper 也只处理四角 fixed-corner，尚未覆盖 `leading / trailing`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名: resizedItem(_:using:) / resizeScalingMode(for:) / resolvedScale(from:scalingMode:)
// 功能说明: 修改前 markdown 在 selection transform 里仍然按非均匀几何缩放处理，没有 width-only 模式，也不会按新宽度重测内容高度。
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
    case .image:
        return item.applyingGeometry(scaledItemGeometry) ?? item
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: makePointerResizeState(itemID:handleRole:) / makeResizedLocalFrame(using:draggedViewportLocation:)
// 功能说明: 修改前单选 resize 统一按二维缩放处理；minimumScale 和 scale 都同时依赖宽高两个轴。
let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
let minimumScale = max(
    minimumWorldDimension / initialLocalFrame.width,
    minimumWorldDimension / initialLocalFrame.height
)

let widthScale = abs(draggedLocalCorner.x - resizeState.fixedOppositeLocalCorner.x) / resizeState.initialLocalFrame.width
let heightScale = abs(draggedLocalCorner.y - resizeState.fixedOppositeLocalCorner.y) / resizeState.initialLocalFrame.height
let scale = max(widthScale, heightScale, resizeState.minimumScale)
guard scale.isFinite else {
    return nil
}

let resizedSize = CGSize(
    width: resizeState.initialLocalFrame.width * scale,
    height: resizeState.initialLocalFrame.height * scale
)
```

### 3.2 修改后

- `CanvasSelectionTransformState` 新增 `widthOnly` 缩放模式。
- 只要 `handleRole.isWidthOnly == true`，selection transform 就：
  - 返回 `widthOnly`
  - `resolvedScale` 固定 `height = 1`
  - `resizedMarkdownItem(...)` 直接按新宽度调用 `CanvasMarkdownLayoutMeasurer.measuredContentHeight(...)`
- iOS / macOS controller 的单选 resize 也一起收口：
  - `minimumScale` 对 width-only handle 只看宽度
  - `makeResizedLocalFrame(...)` 只改宽度，不再把高度一起按 scale 拉伸
  - `resizeSelectedItem(...)` 在拖拽预览阶段就重测 markdown height，再回算 center 和 local frame
- `CanvasEditorSession` 的 finalize helper 新增 `leading / trailing` fixed-edge 语义，保证最终提交和拖拽预览一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizedMarkdownItem(_:scaledCenter:proposedSize:scalingMode:) / resizeScalingMode(for:handleRole:) / resolvedScale(from:scalingMode:)
// 功能说明: 修改后只要 handleRole 是 width-only，markdown item 就按新宽度重测内容高度，不再沿用直接拉伸容器高度的预览方式。
private func resizedMarkdownItem(
    _ item: CanvasMarkdownItem,
    scaledCenter: CGPoint,
    proposedSize: CGSize,
    scalingMode: CanvasSelectionResizeScalingMode
) -> CanvasMarkdownItem {
    let resolvedSize: CGSize
    switch scalingMode {
    case .uniform, .nonUniform:
        resolvedSize = proposedSize
    case .widthOnly:
        resolvedSize = CGSize(
            width: max(proposedSize.width, 1),
            height: CanvasMarkdownLayoutMeasurer.measuredContentHeight(
                markdownSource: item.markdownSource,
                style: item.style,
                maxLayoutWidth: max(proposedSize.width, 1)
            )
        )
    }
    return CanvasMarkdownItem(
        id: item.id,
        markdownSource: item.markdownSource,
        style: item.style,
        center: scaledCenter,
        size: resolvedSize,
        zIndex: item.zIndex,
        rotationRadians: item.rotationRadians
    )
}

private func resizeScalingMode(
    for itemID: CanvasItemID,
    handleRole: CanvasSelectionHandleRole
) -> CanvasSelectionResizeScalingMode {
    if handleRole.isWidthOnly {
        return .widthOnly
    }
    switch sourceItemsByID[itemID]?.kind {
    case .some(.markdown):
        return .nonUniform
    case .some(.image), .some(.text), .some(.handDrawing), .none:
        return .uniform
    }
}

private func resolvedScale(
    from resizeDraft: CanvasSelectionResizeDraft,
    scalingMode: CanvasSelectionResizeScalingMode
) -> CGSize {
    switch scalingMode {
    case .uniform:
        return CGSize(
            width: resizeDraft.uniformScale,
            height: resizeDraft.uniformScale
        )
    case .nonUniform:
        return CGSize(
            width: resizeDraft.widthScale,
            height: resizeDraft.heightScale
        )
    case .widthOnly:
        return CGSize(
            width: resizeDraft.widthScale,
            height: 1
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: makePointerResizeState(itemID:handleRole:) / makeSelectionResizeState(handleRole:) / resizeSelectedItem(using:to:) / makeResizedLocalFrame(using:draggedViewportLocation:)
// 功能说明: 修改后单选 markdown 的 width-only 拖拽预览会只改宽度，并在预览阶段就按新宽度重测 markdown 高度。
let minimumWorldDimension = Self.minimumResizeViewportDimension / camera.zoomScale
let minimumScale: CGFloat
if handleRole.isWidthOnly {
    minimumScale = minimumWorldDimension / initialLocalFrame.width
} else {
    minimumScale = max(
        minimumWorldDimension / initialLocalFrame.width,
        minimumWorldDimension / initialLocalFrame.height
    )
}

let resizedLocalFrame: CGRect
if let markdownItem = currentItem.markdownItem, resizeState.handleRole.isWidthOnly {
    let measuredSize = editorSession.measuredMarkdownItemSize(
        for: markdownItem.markdownSource,
        style: markdownItem.style,
        layoutWidth: proposedLocalFrame.width
    )
    resizedLocalFrame = localFrame(
        for: resizeState.handleRole,
        withFixedOppositeCorner: resizeState.fixedOppositeLocalCorner,
        size: measuredSize
    )
} else {
    resizedLocalFrame = proposedLocalFrame
}

let resizedSize: CGSize
if resizeState.handleRole.isWidthOnly {
    let resolvedWidthScale = max(widthScale, resizeState.minimumScale)
    guard resolvedWidthScale.isFinite else {
        return nil
    }
    resizedSize = CGSize(
        width: resizeState.initialLocalFrame.width * resolvedWidthScale,
        height: resizeState.initialLocalFrame.height
    )
} else {
    let scale = max(widthScale, heightScale, resizeState.minimumScale)
    guard scale.isFinite else {
        return nil
    }
    resizedSize = CGSize(
        width: resizeState.initialLocalFrame.width * scale,
        height: resizeState.initialLocalFrame.height * scale
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: markdownFixedOppositeResizeLocalCorner(for:in:) / markdownResizeLocalFrame(for:withFixedOppositeCorner:size:)
// 功能说明: 修改后 finalize commit 也支持 leading / trailing fixed-edge，确保 width-only markdown 的最终提交语义与拖拽预览一致。
private func markdownFixedOppositeResizeLocalCorner(
    for handleRole: CanvasSelectionHandleRole,
    in localFrame: CGRect
) -> CGPoint {
    switch handleRole {
    case .topLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.maxY)
    case .topTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.maxY)
    case .bottomLeading:
        return CGPoint(x: localFrame.maxX, y: localFrame.minY)
    case .bottomTrailing:
        return CGPoint(x: localFrame.minX, y: localFrame.minY)
    case .leading:
        return CGPoint(x: localFrame.maxX, y: localFrame.midY)
    case .trailing:
        return CGPoint(x: localFrame.minX, y: localFrame.midY)
    }
}

private func markdownResizeLocalFrame(
    for handleRole: CanvasSelectionHandleRole,
    withFixedOppositeCorner oppositeCorner: CGPoint,
    size: CGSize
) -> CGRect {
    switch handleRole {
    case .topLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .topTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y - size.height,
            width: size.width,
            height: size.height
        )
    case .bottomLeading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .bottomTrailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y,
            width: size.width,
            height: size.height
        )
    case .leading:
        return CGRect(
            x: oppositeCorner.x - size.width,
            y: oppositeCorner.y - (size.height / 2),
            width: size.width,
            height: size.height
        )
    case .trailing:
        return CGRect(
            x: oppositeCorner.x,
            y: oppositeCorner.y - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
```

## 修改四：补充 width-only handle 与 fixed-edge 提交的回归测试

### 4.1 修改前

- 现有测试仍然默认 markdown resize handle 数量等于 `CanvasSelectionHandleRole.allCases.count` 的四角集合，或者直接用 `.bottomTrailing` 验证 markdown resize/finalize。
- 没有测试覆盖：
  - 单选 markdown 只出 `leading / trailing`
  - 全 markdown 多选只出 `leading / trailing`
  - width-only transform 会重测 markdown 高度
  - width-only finalize commit 会保持 fixed edge 不漂移

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift（修改前）
// 函数名: testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection()
// 功能说明: 修改前测试仍然把 markdown 的 selection handle 视为四角集合。
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

### 4.2 修改后

- `CanvasEditorSessionAlignmentOverlayTests`：
  - 单选 markdown 断言 handle 角色变成 `[.leading, .trailing]`
  - 全 markdown 多选断言 overlay 也只给 `[.leading, .trailing]`
  - 命中测试新增 `groupSelectionHandle(role: .leading)` 验证
- `CanvasSelectionTransformStateTests`：
  - 新增单选 markdown width-only transform 测试
  - 新增全 markdown 多选 width-only transform 测试
- `CanvasCommandPolicyParityTests`：
  - 新增 `.trailing` width-only finalize commit 测试，验证 fixed edge 与最终高度

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotKeepsResizeHandlesForSingleMarkdownSelection() / testMakeCanvasSnapshotUsesWidthOnlyHandlesForAllMarkdownMultiSelection()
// 功能说明: 修改后 overlay 测试不再把 markdown 视为四角 resize，而是明确断言 leading / trailing width-only handles。
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
    XCTAssertEqual(editOverlay.handles.map(\.role), [.leading, .trailing])
}

func testMakeCanvasSnapshotUsesWidthOnlyHandlesForAllMarkdownMultiSelection() throws {
    let firstItem = CanvasMarkdownItem(
        markdownSource: "## First",
        center: CGPoint(x: -60, y: 0),
        size: CGSize(width: 140, height: 84)
    )
    let secondItem = CanvasMarkdownItem(
        markdownSource: "## Second",
        center: CGPoint(x: 80, y: 40),
        size: CGSize(width: 180, height: 96)
    )
    let session = makeAlignmentOverlayTestSession(
        items: [.markdown(firstItem), .markdown(secondItem)],
        interactionState: CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )
    )

    let snapshot = session.makeCanvasSnapshot()
    let editOverlay = try XCTUnwrap(snapshot.editOverlay)

    XCTAssertEqual(editOverlay.handles.map(\.role), [.leading, .trailing])
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数名: testResizedMemberItemsUseWidthOnlyHandleForSingleMarkdownSelection() / testResizedMemberItemsUseWidthOnlyHandleForAllMarkdownSelection()
// 功能说明: 修改后 transform 测试直接验证 width-only handle 会按新宽度重测 markdown 高度，而不是简单拉伸旧高度。
func testResizedMemberItemsUseWidthOnlyHandleForSingleMarkdownSelection() throws {
    let markdownStyle = CanvasTextStyle(fontSize: 20)
    let markdownItem = CanvasMarkdownItem(
        markdownSource: "## Title\n\nA longer markdown paragraph that should reflow when width changes.",
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
            handleRole: .trailing,
            draggedWorldCorner: CGPoint(x: 160, y: 30),
            minimumScale: 0.1
        )
    )
    let resizedMarkdownItem = try XCTUnwrap(
        resizedItems.first?.markdownItem
    )
    let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: markdownItem.markdownSource,
        style: markdownStyle,
        maxLayoutWidth: 160
    )

    XCTAssertEqual(resizedMarkdownItem.center.x, 80, accuracy: 0.0001)
    XCTAssertEqual(resizedMarkdownItem.center.y, markdownItem.center.y, accuracy: 0.0001)
    XCTAssertEqual(resizedMarkdownItem.size.width, 160, accuracy: 0.0001)
    XCTAssertEqual(resizedMarkdownItem.size.height, expectedHeight, accuracy: 0.0001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testFinalizeMarkdownWidthOnlyResizeCommitRemeasuresHeightAndPreservesFixedEdge()
// 功能说明: 修改后 finalize parity 测试覆盖 trailing width-only 提交，确保固定边与最终内容高度都符合预期。
func testFinalizeMarkdownWidthOnlyResizeCommitRemeasuresHeightAndPreservesFixedEdge() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let source = """
    ## Markdown

    A wrapped paragraph that should only resize by width and remeasure height from content.

    - First
    - Second
    """
    let style = CanvasTextStyle(fontSize: 20)
    let originalItem = CanvasMarkdownItem(
        markdownSource: source,
        style: style,
        center: CGPoint(x: 40, y: 30),
        size: CGSize(width: 80, height: 60)
    )
    session.scene.append(originalItem)

    let provisionalItem = try XCTUnwrap(
        session.scene.resizeBoardItem(
            withID: originalItem.id,
            toCenter: CGPoint(x: 80, y: 30),
            size: CGSize(width: 160, height: 90)
        )?.markdownItem
    )
    let provisionalFixedEdgeAnchor = provisionalItem.worldPoint(
        fromLocal: CGPoint(
            x: provisionalItem.localFrame.minX,
            y: provisionalItem.localFrame.midY
        )
    )

    let committedItem = try XCTUnwrap(
        session.finalizeMarkdownResizeCommit(
            withID: originalItem.id,
            handleRole: .trailing,
            originalLayoutWidth: originalItem.size.width
        )
    )
    let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: source,
        style: style,
        maxLayoutWidth: provisionalItem.size.width
    )
    let committedFixedEdgeAnchor = committedItem.worldPoint(
        fromLocal: CGPoint(
            x: committedItem.localFrame.minX,
            y: committedItem.localFrame.midY
        )
    )

    XCTAssertEqual(committedItem.size.width, provisionalItem.size.width, accuracy: 0.0001)
    XCTAssertEqual(committedItem.size.height, expectedHeight, accuracy: 0.0001)
    XCTAssertEqual(committedItem.center.y, provisionalItem.center.y, accuracy: 0.0001)
    XCTAssertEqual(committedFixedEdgeAnchor.x, provisionalFixedEdgeAnchor.x, accuracy: 0.0001)
    XCTAssertEqual(committedFixedEdgeAnchor.y, provisionalFixedEdgeAnchor.y, accuracy: 0.0001)
}
```

## 验证

- 已执行 markdown width-only resize 相关 macOS 定向测试，结果通过。
- 已执行 iOS Simulator 构建，结果通过。
- 本次记录新增到 `commit_records/`，没有修改任何现有的 `.md` 文档。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild test -scheme MyCanvas_Ver_0 -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests
# 功能说明: 验证 markdown width-only handle、selection transform 与 finalize commit 的回归测试。
结果: 通过
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild build -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator'
# 功能说明: 验证 iOS 侧 viewport / controller 的 width-only 交互改动可以完整通过构建。
结果: 通过
```
