# 20260519_162421_CST_markdown_block_phase5_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 5。
  - 把 markdown block 在 `board list` / `minimap` / `macOS` 端的可见性与最小可用编辑入口补齐。
  - 将 minimap / preview seed 中的 markdown 从 text 兼容分支提升成独立语义。
  - 将 `BoardThumbnailRenderer` 中的 markdown 缩略图从“普通文本占位”升级为真正的 markdown attributed 排版绘制。
  - 在 `macOSViewController` 接入 markdown 选中态 accessory、`Edit / +/-` 命令分发，以及最简 sheet 编辑器。
  - 新增阶段 5 定向测试，并收口实现过程中暴露出来的测试运行时稳定性问题。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift`
  - `MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示工作区里存在一个未纳入本记录的现存变更：`MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`。
  - 针对阶段 5 相关代码，`git status --short` 显示 `6` 个已跟踪修改文件，外加 `1` 个未跟踪新增目录 `MyCanvas_Ver_0/Platform/macOS/Markdown/`（其中包含本次新增的 `macOSCanvasMarkdownEditorViewController.swift`）与 `1` 个未跟踪新增测试文件 `MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift`。
  - 针对阶段 5 的已跟踪文件，`git diff --stat` 显示：`6 files changed, 319 insertions(+), 39 deletions(-)`。
  - 上述 `git diff --stat` 只统计已跟踪文件，不包含本次新增的 `MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift` 与 `MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift`。
- 本记录不包含：
  - 阶段 6 的完整回归测试与兼容性收口。
  - 任何 git 提交行为。

## 当前 changes 摘要

- `CanvasMiniMapNodeKind` 新增 `.markdown`，minimap 侧不再把 markdown 伪装成 `.text`。
- `CanvasMiniMapTextNodeProvider` 只处理 text；新增 `CanvasMiniMapMarkdownNodeProvider`，让 markdown 在 minimap 上独立建模，并跟随旋转预览几何。
- `CanvasMiniMapRenderer` 默认注册 markdown provider，`BoardGeometryPreviewBuilder` 生成 preview seed 时也把 markdown 标成 `.markdown`。
- `BoardThumbnailRenderer` 新增 `drawMarkdownItem(...)` 和 `drawAttributedText(...)`，markdown 缩略图改为通过 `CanvasMarkdownLayoutMeasurer` 真实排版后绘制，而不是把 `markdownSource` 当普通 text 塞给 `drawTextItem(...)`。
- `macOSViewController` 新增 `selectionAccessoryHostView`、selection accessory 状态同步、命令分发以及 markdown editor follow-up 处理。
- 新增 `macOSCanvasMarkdownEditorViewController`，提供基于 `NSScrollView + NSTextView` 的最简 markdown source 编辑器。
- 新增 `MarkdownPreviewParityTests`，覆盖 minimap kind、preview seed kind 和 board thumbnail 可见性，并通过 `@MainActor + Retainer` 消除测试释放期崩溃。

## 修改一：把 minimap / preview seed 中的 markdown 从 text 兼容分支升级成独立语义

### 1.1 `CanvasMiniMapSnapshot.swift`

#### 修改前

- `CanvasMiniMapNodeKind` 没有 `markdown` case。
- minimap 上即便出现 markdown block，也只能借用 `.text` 语义传递。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift（修改前）
// 函数名: CanvasMiniMapNodeKind
// 功能说明: 修改前 minimap node kind 没有 markdown，后续 provider 只能把 markdown 伪装成 text。
enum CanvasMiniMapNodeKind {
    case image
    case handDrawing
    case text
    case sticker
    case shape
}
```

#### 修改后

- `CanvasMiniMapNodeKind` 增加 `.markdown`，为 minimap、preview seed、board thumbnail trace 提供统一语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift
// 函数名: CanvasMiniMapNodeKind
// 功能说明: 修改后 minimap 节点拥有独立 markdown kind，后续 provider 与 preview seed 都可共享此语义。
enum CanvasMiniMapNodeKind {
    case image
    case handDrawing
    case text
    case markdown
    case sticker
    case shape
}
```

### 1.2 `CanvasMiniMapNodeProvider.swift`

#### 修改前

- `CanvasMiniMapTextNodeProvider.makeNodes(context:)` 同时处理 text 和 markdown。
- 即便命中 markdown item，最终产出的 node `kind` 仍然是 `.text`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift（修改前）
// 函数名: CanvasMiniMapTextNodeProvider.makeNodes(context:)
// 功能说明: 修改前 text provider 兼管 markdown，导致 markdown 在 minimap 上无法声明独立 kind。
if let item = boardItem.textItem {
    itemWorldQuad = item.worldQuad
    itemID = item.id
    zIndex = item.zIndex
    isPreviewActive = context.inlineEditState?.mode == .text &&
        context.inlineEditState?.itemID == item.id
} else if let item = boardItem.markdownItem {
    itemWorldQuad = item.worldQuad
    itemID = item.id
    zIndex = item.zIndex
    isPreviewActive = false
} else {
    return nil
}

return CanvasMiniMapNode(
    id: itemID,
    kind: .text,
    worldQuad: itemWorldQuad,
    zIndex: zIndex,
    isPreviewActive: isPreviewActive
)
```

#### 修改后

- `CanvasMiniMapTextNodeProvider` 只保留 text。
- 新增 `CanvasMiniMapMarkdownNodeProvider`，markdown node 改为独立输出 `.markdown`，并跟随 `rotationPreviewState` 的几何结果。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapTextNodeProvider.makeNodes(context:) / CanvasMiniMapMarkdownNodeProvider.makeNodes(context:)
// 功能说明: 修改后 text 和 markdown 由不同 provider 负责，markdown 在 minimap 上拥有独立 kind 与旋转预览语义。
struct CanvasMiniMapTextNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
            guard let item = boardItem.textItem else {
                return nil
            }

            return CanvasMiniMapNode(
                id: item.id,
                kind: .text,
                worldQuad: item.worldQuad,
                zIndex: item.zIndex,
                isPreviewActive: context.inlineEditState?.mode == .text &&
                    context.inlineEditState?.itemID == item.id
            )
        }
    }
}

struct CanvasMiniMapMarkdownNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
            guard let item = boardItem.markdownItem else {
                return nil
            }

            let effectiveItem = effectiveMiniMapBoardItem(
                from: .markdown(item),
                rotationPreviewState: context.rotationPreviewState
            ).markdownItem ?? item

            return CanvasMiniMapNode(
                id: effectiveItem.id,
                kind: .markdown,
                worldQuad: effectiveItem.worldQuad,
                zIndex: effectiveItem.zIndex,
                isPreviewActive: context.rotationPreviewState?.geometry(
                    for: effectiveItem.id
                ) != nil
            )
        }
    }
}
```

### 1.3 `CanvasMiniMapRenderer.swift` 与 `BoardGeometryPreviewBuilder.swift`

#### 修改前

- `CanvasMiniMapRenderer` 的默认 provider 列表没有 markdown provider。
- `BoardGeometryPreviewBuilder` 在 document -> preview seed 过程中，仍把 markdown record 标成 `.text`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift（修改前）
// 函数名: init(nodeProviders:)
// 功能说明: 修改前 minimap renderer 默认 provider 列表里没有 markdown provider。
init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
    self.nodeProviders = nodeProviders ?? [
        CanvasMiniMapImageNodeProvider(),
        CanvasMiniMapHandDrawingNodeProvider(),
        CanvasMiniMapTextNodeProvider()
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift（修改前）
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改前 preview seed 中的 markdown node 仍然继承 text kind。
case let .markdown(markdownRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: markdownRecord.id,
        kind: .text,
        center: markdownRecord.center,
        size: markdownRecord.size,
        zIndex: markdownRecord.zIndex,
        rotationRadians: markdownRecord.rotationRadians
    )
```

#### 修改后

- minimap renderer 默认注册 `CanvasMiniMapMarkdownNodeProvider()`。
- preview seed 中的 markdown item 改为明确标记为 `.markdown`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: 修改后 minimap renderer 会默认注册 markdown provider，确保 snapshot 能直接产出 markdown nodes。
init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
    self.nodeProviders = nodeProviders ?? [
        CanvasMiniMapImageNodeProvider(),
        CanvasMiniMapHandDrawingNodeProvider(),
        CanvasMiniMapTextNodeProvider(),
        CanvasMiniMapMarkdownNodeProvider()
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改后 board preview seed 中的 markdown 节点会保留 markdown kind，而不是继续伪装成 text。
case let .markdown(markdownRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: markdownRecord.id,
        kind: .markdown,
        center: markdownRecord.center,
        size: markdownRecord.size,
        zIndex: markdownRecord.zIndex,
        rotationRadians: markdownRecord.rotationRadians
    )
```

## 修改二：让 board thumbnail 真实绘制 markdown，而不是把 source 直接当普通 text 塞进去

### 2.1 `BoardThumbnailRenderer.swift` 的分发入口

#### 修改前

- `BoardThumbnailRenderer` 在处理 `.markdown` 时，会临时构造 `BoardTextItemRecord`。
- markdown 缩略图因此只能走 `drawTextItem(...)`，丢失阶段 2 已有的 markdown attributed 布局能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:)
// 功能说明: 修改前 markdown 缩略图通过伪造 BoardTextItemRecord 走普通 text 绘制分支。
case let .markdown(markdownItemRecord):
    drawTextItem(
        BoardTextItemRecord(
            id: markdownItemRecord.id,
            center: markdownItemRecord.center,
            size: markdownItemRecord.size,
            zIndex: markdownItemRecord.zIndex,
            text: markdownItemRecord.markdownSource,
            style: markdownItemRecord.style,
            rotationRadians: markdownItemRecord.rotationRadians
        ),
        geometry: geometry,
        in: context,
        traceContext: traceContext,
        documentOrder: traceContext.documentOrderByID[
            markdownItemRecord.id
        ],
        renderOrder: renderOrder
    )
```

#### 修改后

- `.markdown` 分支改为直达 `drawMarkdownItem(...)`。
- 缩略图渲染层终于拿到了 markdown record 的原始语义，而不是依赖 text-compatible 桥接。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:)
// 功能说明: 修改后 markdown 缩略图改走独立 drawMarkdownItem(...)，不再伪造成 text record。
case let .markdown(markdownItemRecord):
    drawMarkdownItem(
        markdownItemRecord,
        geometry: geometry,
        in: context,
        traceContext: traceContext,
        documentOrder: traceContext.documentOrderByID[
            markdownItemRecord.id
        ],
        renderOrder: renderOrder
    )
```

### 2.2 新增 `drawMarkdownItem(...)` 与 `drawAttributedText(...)`

#### 修改前

- 渲染器中不存在 `drawMarkdownItem(...)`。
- `drawText(...)` 会在内部直接构造普通 `NSAttributedString` 并立刻绘制，无法复用 markdown 解析/排版结果。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift（修改前）
// 函数名: drawMarkdownItem(...)
// 功能说明: 修改前缩略图渲染器没有 markdown 专用绘制入口。
// 此函数在修改前不存在。
```

#### 修改后

- 新增 `drawMarkdownItem(...)`，使用 `CanvasMarkdownLayoutMeasurer.layout(...)` 按当前 thumbnail 宽度排版 markdown。
- 新增 `drawAttributedText(...)`，把 text / markdown 的底层 CoreText 绘制收敛到统一 helper。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawMarkdownItem(_:geometry:in:traceContext:documentOrder:renderOrder:) / drawAttributedText(_:in:context:)
// 功能说明: 修改后缩略图层会真实绘制 markdown attributed 内容，并让 text / markdown 共用底层 CoreText 绘制 helper。
private func drawMarkdownItem(
    _ itemRecord: BoardMarkdownItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext: BoardThumbnailTraceContext,
    documentOrder: Int?,
    renderOrder: Int
) {
    guard itemRecord.markdownSource.isEmpty == false else {
        return
    }

    let visibleSize = itemRecord.size.cgSize
    guard visibleSize.width > 0, visibleSize.height > 0 else {
        return
    }

    let mappedVisibleSize = CGSize(
        width: visibleSize.width * geometry.scale,
        height: visibleSize.height * geometry.scale
    )
    guard mappedVisibleSize.width > 0, mappedVisibleSize.height > 0 else {
        return
    }

    let mappedCenter = geometry.worldToMiniMap(itemRecord.center.cgPoint)
    let textRect = CGRect(
        x: -mappedVisibleSize.width / 2,
        y: -mappedVisibleSize.height / 2,
        width: mappedVisibleSize.width,
        height: mappedVisibleSize.height
    ).standardized
    let rotationRadians = normalizedCanvasAngle(
        CGFloat(itemRecord.rotationRadians ?? 0)
    )

    let layout = CanvasMarkdownLayoutMeasurer.layout(
        markdownSource: itemRecord.markdownSource,
        style: itemRecord.style.canvasTextStyle,
        maxLayoutWidth: mappedVisibleSize.width,
        scale: geometry.scale
    )

    context.saveGState()
    context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
    context.rotate(by: rotationRadians)
    context.clip(to: textRect)
    drawAttributedText(
        layout.attributedText,
        in: textRect,
        context: context
    )
    context.restoreGState()
}

private func drawAttributedText(
    _ attributedText: NSAttributedString,
    in rect: CGRect,
    context: CGContext
) {
    let availableSize = rect.size
    guard
        availableSize.width > 0,
        availableSize.height > 0,
        attributedText.length > 0
    else {
        return
    }

    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let textBounds = CGRect(origin: .zero, size: availableSize)
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.textMatrix = .identity
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        CGPath(rect: textBounds, transform: nil),
        nil
    )
    CTFrameDraw(frame, context)
    context.restoreGState()
}
```

## 修改三：在 macOS controller 中接入 markdown accessory、命令分发与 follow-up

### 3.1 `handleCommandFollowUp(_:)` 与 `performSelectionAccessoryCommand(_:)`

#### 修改前

- `macOSViewController.handleCommandFollowUp(_:)` 对 `.presentMarkdownEditor` 仍然是 no-op。
- controller 中也没有 selection accessory 的 markdown 命令分发入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: handleCommandFollowUp(_:)
// 功能说明: 修改前 macOS controller 对 markdown editor follow-up 仍然保持 no-op。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case .presentHandDrawingEditor:
        return
    case .presentMarkdownEditor:
        return
    }
}
```

#### 修改后

- `.presentMarkdownEditor(itemID)` 改为真正调用 `presentMarkdownEditor(for:)`。
- 新增 `performSelectionAccessoryCommand(_:)`，把 accessory 上的 `Edit / +/-` 动作派回命令系统。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleCommandFollowUp(_:) / performSelectionAccessoryCommand(_:)
// 功能说明: 修改后 macOS controller 可以响应 markdown editor follow-up，并把 accessory 按钮动作派回命令层。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case .presentHandDrawingEditor:
        return
    case let .presentMarkdownEditor(itemID):
        presentMarkdownEditor(for: itemID)
    }
}

private func performSelectionAccessoryCommand(_ commandID: CanvasCommandID) {
    switch commandID {
    case .beginMarkdownEdit:
        guard let itemID = selectionAccessoryHostView.currentState?.itemID else {
            return
        }
        performCommand(.beginMarkdownEdit(itemID: itemID))
    case .decreaseMarkdownContentSize:
        performCommand(.decreaseMarkdownContentSize)
    case .increaseMarkdownContentSize:
        performCommand(.increaseMarkdownContentSize)
    default:
        return
    }
}
```

### 3.2 新增 selection accessory 状态同步与锚点解析

#### 修改前

- `macOSViewController` 中不存在 `selectionAccessoryHostView` 的状态同步函数。
- context menu 刷新、overlay 布局刷新、canvas refresh 都不会更新 markdown accessory。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: syncSelectionAccessoryPresentation(layoutContext:)
// 功能说明: 修改前 macOS controller 中不存在 markdown selection accessory 的状态解析与布局同步入口。
// 此函数在修改前不存在。
```

#### 修改后

- 新增 `syncSelectionAccessoryPresentation(...)`、`resolvedMarkdownSelectionAccessoryState()`、`markdownSelectionAccessoryAnchorRect(for:)`。
- markdown accessory 只在编辑模式、未冻结、未弹出其它面板、且当前单选项为 markdown 时出现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: syncSelectionAccessoryPresentation(layoutContext:) / resolvedMarkdownSelectionAccessoryState() / markdownSelectionAccessoryAnchorRect(for:)
// 功能说明: 修改后 macOS controller 会按当前选区、chrome 状态与 edit overlay 实时解析 markdown accessory 的展示状态和锚点。
private func syncSelectionAccessoryPresentation(
    layoutContext: CanvasChromeLayoutContext? = nil
) {
    guard isViewLoaded else {
        return
    }

    guard let state = resolvedMarkdownSelectionAccessoryState() else {
        selectionAccessoryHostView.dismiss()
        return
    }

    let resolvedLayoutContext =
        layoutContext ?? contextMenuLayoutContextForCurrentChromeState()
    selectionAccessoryHostView.apply(
        state: state,
        layoutContext: resolvedLayoutContext
    )
}

private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    guard
        workspaceMode == .editing,
        isTransitionInteractionFrozen == false,
        contextMenuState == nil,
        presentedViewControllers?.isEmpty ?? true,
        presentationInlineEditState == nil,
        let itemID = editorSession.singleSelectedItemID,
        scene.markdownItem(withID: itemID) != nil,
        let anchorRect = markdownSelectionAccessoryAnchorRect(for: itemID)
    else {
        return nil
    }

    let editDescriptor = CanvasCommandDescriptor(
        id: .beginMarkdownEdit,
        title: "Edit Markdown",
        systemImageName: "pencil",
        isEnabled: editorSession.canBeginMarkdownEdit(withID: itemID),
        isActive: false
    )
    let decreaseDescriptor = commandDescriptor(
        for: .decreaseMarkdownContentSize
    )
    let increaseDescriptor = commandDescriptor(
        for: .increaseMarkdownContentSize
    )
    return SelectionAccessoryState.markdown(
        itemID: itemID,
        anchorRect: anchorRect,
        editDescriptor: editDescriptor,
        decreaseDescriptor: decreaseDescriptor,
        increaseDescriptor: increaseDescriptor
    )
}
```

### 3.3 `presentMarkdownEditor(for:)`

#### 修改前

- `macOSViewController` 中不存在 markdown editor 弹窗逻辑。
- 即使命令层已经有 `.presentMarkdownEditor(itemID:)` follow-up，macOS controller 也没有真正接通展示与提交。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改前 macOS controller 中不存在 markdown editor 的展示和提交逻辑。
// 此函数在修改前不存在。
```

#### 修改后

- 新增 `presentMarkdownEditor(for:)`。
- 展示前会取消旋转交互并隐藏 accessory，Done 时通过 `editorSession.commitMarkdownEdit(withID:markdownSource:)` 回写 source。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改后 macOS controller 可以弹出最简 markdown editor，并在提交成功后回写 source 与刷新画布。
private func presentMarkdownEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty ?? true else {
        return
    }

    guard let item = scene.markdownItem(withID: itemID) else {
        presentMarkdownEditorError(
            message: "Markdown item is no longer available."
        )
        return
    }

    cancelRotationInteractionIfNeeded(resetPointerDragState: true)
    selectionAccessoryHostView.dismiss()

    let editorViewController = macOSCanvasMarkdownEditorViewController(
        markdownSource: item.markdownSource
    ) { [weak self] markdownSource in
        guard let self else {
            return false
        }

        guard let commitResult = self.editorSession.commitMarkdownEdit(
            withID: itemID,
            markdownSource: markdownSource
        ) else {
            self.presentMarkdownEditorError(
                message: "Markdown item is no longer available."
            )
            return false
        }

        if commitResult.didChangeDocument {
            self.refreshCanvas(
                reason: "commit markdown edit \(itemID.uuidString)"
            )
        }
        return true
    }
    presentAsSheet(editorViewController)
}
```

## 修改四：新增 macOS 最简 markdown 编辑器文件

#### 修改前

- 仓库中不存在 `MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift`。
- macOS 端没有最简 `Cancel / Done + NSTextView` 的 markdown source 编辑器。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift（修改前）
// 函数名: N/A
// 功能说明: 修改前此文件不存在，macOS 端没有最简 markdown source 编辑器。
// 此文件在修改前不存在。
```

#### 修改后

- 新增 `macOSCanvasMarkdownEditorViewController`。
- 控制器使用 `NSScrollView + NSTextView` 编辑原始 markdown source，提供 `Cancel / Done`，并通过闭包把提交动作交还给 `macOSViewController`。
- `NSTextView` 的 `maxSize` 与 `textContainer.containerSize` 明确使用 `CGFloat.greatestFiniteMagnitude`，消除实现过程中遇到的 Swift 类型推断歧义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift
// 函数名: viewDidLoad() / handleDoneButtonClick()
// 功能说明: 修改后新增最简 macOS markdown 编辑器，负责 source 输入、Done/Cancel 生命周期和 sheet 内首响应者切换。
final class macOSCanvasMarkdownEditorViewController: NSViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        return scrollView
    }()
    private let textView: NSTextView = {
        let textView = NSTextView()
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = CGSize(width: 12, height: 14)
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        return textView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 720, height: 540)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        configureButtons()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    @objc
    private func handleDoneButtonClick() {
        guard isCommitting == false else {
            return
        }

        isCommitting = true
        let didCommit = onCommitMarkdownSource(textView.string)
        isCommitting = false
        guard didCommit else {
            return
        }

        dismiss(self)
    }
}
```

## 修改五：新增阶段 5 定向测试，并把测试运行时稳定性问题一起收口

#### 修改前

- 仓库中没有专门覆盖“markdown minimap kind / preview seed kind / board thumbnail 可见性”的测试文件。
- 阶段 5 的回归点如果只靠手工验证，很难锁定“独立 kind”与“缩略图非空白”这两类契约。

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift（修改前）
// 函数名: N/A
// 功能说明: 修改前此文件不存在，阶段 5 没有独立的 markdown preview parity 测试。
// 此文件在修改前不存在。
```

#### 修改后

- 新增 `MarkdownPreviewParityTests`，覆盖：
  - minimap snapshot 中 markdown node 的独立 `.markdown` kind；
  - board preview seed 中 markdown node 的独立 `.markdown` kind；
  - markdown-only board 的 persisted thumbnail 非空白。
- 实现过程中，最初的 minimap 定向测试在 XCTest 释放期触发了 `abort()`；最终通过给测试类加 `@MainActor`，并引入 `MarkdownPreviewParityTestRetainer` 持有 `CanvasScene` / `BoardThumbnailRenderer`，把这个运行时问题一并收口。

```swift
// 文件路径: MyCanvas_Ver_0Tests/MarkdownPreviewParityTests.swift
// 函数名: MarkdownPreviewParityTests / MarkdownPreviewParityTestRetainer
// 功能说明: 修改后新增阶段 5 定向测试，并通过 @MainActor + Retainer 稳定默认 MainActor 隔离下的测试生命周期。
@MainActor
final class MarkdownPreviewParityTests: XCTestCase {
    func testCanvasMiniMapRendererUsesDedicatedMarkdownNodeKind() throws {
        let markdownItem = makeMarkdownPreviewTestItem(
            markdownSource: "## Title\n\nBody",
            center: CGPoint(x: 140, y: 90),
            size: CGSize(width: 220, height: 140),
            zIndex: 4
        )
        let textItem = CanvasTextItem(
            text: "Caption",
            center: CGPoint(x: 40, y: 30),
            size: CGSize(width: 100, height: 50),
            zIndex: 1
        )
        var scene = CanvasScene()
        scene.append(textItem)
        scene.append(markdownItem)
        MarkdownPreviewParityTestRetainer.scenes.append(scene)

        let snapshot = CanvasMiniMapRenderer().makeSnapshot(
            context: CanvasMiniMapRenderContext(
                scene: scene,
                camera: CanvasCamera(
                    center: .zero,
                    zoomScale: 1,
                    viewportSize: CGSize(width: 480, height: 320)
                )
            )
        )

        let markdownNode = try XCTUnwrap(
            snapshot.nodes.first(where: { $0.id == markdownItem.id })
        )
        XCTAssertEqual(markdownNode.kind, .markdown)
    }
}

private enum MarkdownPreviewParityTestRetainer {
    static var scenes: [CanvasScene] = []
    static var thumbnailRenderers: [BoardThumbnailRenderer] = []
}
```

## 验证结果

- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' test -only-testing:MyCanvas_Ver_0Tests/MarkdownPreviewParityTests`
  - 结果：通过。
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' build`
  - 结果：通过。
- `ReadLints`
  - 结果：本次修改涉及文件未引入新的 linter 错误。
