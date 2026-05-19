# 20260519_150303_CST_markdown_block_phase2_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown_block_计划_ccecae26.plan.md` 的阶段 2。
  - 把 markdown block 从阶段 1 的 text-compatible 占位渲染，升级为真正的 markdown 测量与主画布渲染。
  - 新增共享 markdown 测量器与独立 markdown 渲染层，并接入 iOS / macOS 双端 viewport。
  - 把新建 markdown block 的默认尺寸契约从固定 `320x180` 改成“固定宽度排版 -> 计算高度”。
  - 新增定向测试，锁定测量、渲染层与默认创建尺寸的阶段 2 契约。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short` 显示本次阶段 2 涉及 `6` 个已跟踪修改文件、`4` 个新增文件，以及一个未处理的现存变更 `MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`。
  - 生成本记录前，`git diff --stat` 显示：`7 files changed, 113 insertions(+), 5 deletions(-)`。
  - 上述 `git diff --stat` 只统计已跟踪文件，不包含本次新增的 `CanvasMarkdownLayoutMeasurer.swift`、`CanvasMarkdownLayer.swift`、`CanvasMarkdownLayoutMeasurerTests.swift`、`CanvasMarkdownLayerTests.swift`。
- 本记录不包含：
  - 阶段 3 的 markdown resize 语义分叉与选中态悬浮工具条。
  - 阶段 4 的 iOS 最简 markdown 编辑器入口。
  - 阶段 5 的 board list / minimap / macOS 编辑 parity 收口。

## 当前 changes 摘要

- `CanvasRenderSnapshot` 新增 `CanvasMarkdownRenderPayload` 与 `CanvasRenderPayload.markdown`，主画布渲染链开始区分 text 和 markdown。
- `CanvasRenderer.makeMarkdownRenderItem(...)` 不再把 markdown source 塞进 `.text` payload，而是显式产出 `.markdown` payload。
- 新增 `CanvasMarkdownLayoutMeasurer`，在共享层完成基础子集 markdown 的解析、attributed 内容组装和“固定宽度 -> 反推高度”测量。
- 新增 `CanvasMarkdownLayer`，按容器宽度重排 markdown，并把 `zoomScale` 作为内容字号缩放输入。
- iOS / macOS viewport 均新增 `markdownLayers` 生命周期管理与 `.markdown` payload 刷新分支。
- `CanvasEditorSession.addMarkdownItem(...)` 的默认创建尺寸改成固定宽度 `320`、高度由 `CanvasMarkdownLayoutMeasurer.measuredContentHeight(...)` 计算。
- 新增测量器测试、渲染层测试，以及默认创建高度契约测试。

## 修改一：把 markdown 从 text 临时桥接升级成独立 render payload

### 1.1 `CanvasRenderSnapshot`

#### 修改前

- render snapshot 只有 `image` / `handDrawing` / `text` 三类 payload。
- markdown block 虽然已经有独立 runtime item，但在主画布渲染快照里仍然只能借道 `CanvasTextRenderPayload`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前）
// 类型名: CanvasTextRenderPayload / CanvasRenderPayload
// 功能说明: 修改前 render snapshot 没有 markdown 专用 payload，markdown 只能伪装成 text。
struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
}
```

#### 修改后

- 新增 `CanvasMarkdownRenderPayload`，显式携带 `markdownSource`、`style`、`zoomScale`。
- `CanvasRenderPayload` 新增 `.markdown`，后续 viewport 可以基于 payload 类型分配独立的 markdown layer。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 类型名: CanvasMarkdownRenderPayload / CanvasRenderPayload
// 功能说明: 修改后 render snapshot 为 markdown 建立独立 payload，避免继续复用 text 渲染语义。
struct CanvasTextRenderPayload {
    let text: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
    case markdown(CanvasMarkdownRenderPayload)
}
```

### 1.2 `CanvasRenderer.makeMarkdownRenderItem(...)`

#### 修改前

- `makeMarkdownRenderItem(...)` 虽然已经拿到了 `CanvasMarkdownItem`，但返回的仍然是 `.text(CanvasTextRenderPayload(...))`。
- 这意味着主画布侧还不能区分“普通 text block”和“markdown block”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改前 markdown render item 仍复用 text payload，后续 viewport 只能走 CanvasTextLayer。
return CanvasRenderItem(
    id: effectiveMarkdownItem.id,
    screenFrame: screenQuad.boundingRect.standardized,
    screenQuad: screenQuad,
    screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
    screenBoundsSize: CGSize(
        width: effectiveMarkdownItem.size.width * camera.zoomScale,
        height: effectiveMarkdownItem.size.height * camera.zoomScale
    ),
    rotationRadians: effectiveMarkdownItem.rotationRadians,
    zIndex: effectiveMarkdownItem.zIndex,
    payload: .text(
        CanvasTextRenderPayload(
            text: effectiveMarkdownItem.markdownSource,
            style: effectiveMarkdownItem.style,
            zoomScale: camera.zoomScale
        )
    )
)
```

#### 修改后

- `makeMarkdownRenderItem(...)` 现在直接返回 `.markdown(CanvasMarkdownRenderPayload(...))`。
- 这一步把阶段 1 的兼容桥接拆开，为真正的 markdown layer 与重排语义提供类型入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后 markdown render item 产出独立 markdown payload，供双端 viewport 走专用渲染层。
return CanvasRenderItem(
    id: effectiveMarkdownItem.id,
    screenFrame: screenQuad.boundingRect.standardized,
    screenQuad: screenQuad,
    screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
    screenBoundsSize: CGSize(
        width: effectiveMarkdownItem.size.width * camera.zoomScale,
        height: effectiveMarkdownItem.size.height * camera.zoomScale
    ),
    rotationRadians: effectiveMarkdownItem.rotationRadians,
    zIndex: effectiveMarkdownItem.zIndex,
    payload: .markdown(
        CanvasMarkdownRenderPayload(
            markdownSource: effectiveMarkdownItem.markdownSource,
            style: effectiveMarkdownItem.style,
            zoomScale: camera.zoomScale
        )
    )
)
```

## 修改二：新增共享 markdown 测量器，并把默认创建尺寸改成“固定宽度 -> 反推高度”

### 2.1 `CanvasMarkdownLayoutMeasurer`

#### 修改前

- 工程内不存在共享 markdown 测量器。
- markdown block 还没有统一的基础子集解析、attributed 内容生成与固定宽度测量入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift（修改前）
// 类型名: CanvasMarkdownLayoutMeasurer
// 功能说明: 修改前工程内不存在共享 markdown 测量器，主画布也没有统一的 markdown 布局测量入口。
// 此文件不存在。
```

#### 修改后

- 新增 `CanvasMarkdownLayoutResult`，统一返回 `attributedText` 与 `contentSize`。
- 新增 `CanvasMarkdownLayoutMeasurer.layout(...)` 和 `measuredContentHeight(...)`，建立“固定最大宽度排版 -> 计算内容高度”的共享契约。
- 当前支持的基础子集落在共享解析/拼装层：标题、段落、无序列表、有序列表、引用、行内代码、代码块。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayoutMeasurer.swift
// 类型名: CanvasMarkdownLayoutResult / CanvasMarkdownLayoutMeasurer
// 功能说明: 修改后新增共享 markdown 测量器，负责基础子集解析、attributed 内容组装与固定宽度测量。
struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize

    var contentHeight: CGFloat {
        contentSize.height
    }
}

enum CanvasMarkdownLayoutMeasurer {
    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [String])
        case orderedList(items: [(number: Int, text: String)])
        case quote(text: String)
        case codeBlock(text: String)
    }

    static func layout(
        markdownSource: String,
        style: CanvasTextStyle,
        maxLayoutWidth: CGFloat,
        scale: CGFloat = 1
    ) -> CanvasMarkdownLayoutResult {
        let resolvedLayoutWidth = max(maxLayoutWidth, 1)
        let attributedText = makeAttributedText(
            markdownSource: markdownSource,
            style: style,
            scale: scale
        )
        let measuredRect = attributedText.boundingRect(
            with: CGSize(
                width: resolvedLayoutWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CanvasMarkdownLayoutResult(
            attributedText: attributedText,
            contentSize: CGSize(
                width: resolvedLayoutWidth,
                height: ceil(max(measuredRect.height, minimumContentHeight(
                    style: style,
                    scale: scale
                )))
            )
        )
    }

    static func measuredContentHeight(
        markdownSource: String,
        style: CanvasTextStyle,
        maxLayoutWidth: CGFloat,
        scale: CGFloat = 1
    ) -> CGFloat {
        layout(
            markdownSource: markdownSource,
            style: style,
            maxLayoutWidth: maxLayoutWidth,
            scale: scale
        ).contentHeight
    }

    private static func makeAttributedBlock(
        for block: Block,
        style: CanvasTextStyle,
        scale: CGFloat
    ) -> NSAttributedString {
        let baseFontSize = CanvasTextLayoutMeasurer.renderFontSize(
            for: style,
            scale: scale
        )
        switch block {
        case let .heading(level, text):
            let multiplier = headingFontSizeMultiplier(for: level)
            let fontSize = max(baseFontSize * multiplier, 1)
            let attributed = makeInlineAttributedText(
                from: text,
                style: style,
                fontSize: fontSize,
                traits: .plain.merging(isBold: true),
                defaultColor: platformColor(for: style.color)
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: fontSize,
                paragraphSpacing: fontSize * blockSpacingFactor
            )
            return attributed

        case let .unorderedList(items):
            return makeListBlock(
                items: items.enumerated().map { _, item in
                    (prefix: unorderedListPrefix, text: item)
                },
                style: style,
                fontSize: baseFontSize
            )

        case let .quote(text):
            let quoteText = text
                .components(separatedBy: "\n")
                .map { "\(quotePrefix)\($0)" }
                .joined(separator: "\n")
            let attributed = makeInlineAttributedText(
                from: quoteText,
                style: style,
                fontSize: baseFontSize,
                traits: .plain.merging(isItalic: true),
                defaultColor: platformColor(
                    for: style.color,
                    alphaMultiplier: 0.82
                )
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: baseFontSize,
                headIndent: baseFontSize * quoteHeadIndentFactor,
                paragraphSpacing: baseFontSize * blockSpacingFactor
            )
            return attributed

        // 其他 paragraph / orderedList / codeBlock case 省略。
        }
    }

    // 其他 markdown 解析、inline 样式和字体辅助函数省略。
}
```

### 2.2 `CanvasEditorSession.addMarkdownItem(...)`

#### 修改前

- 默认新建 markdown block 的尺寸是固定 `320x180`。
- 阶段 1 还没有把“固定宽度排版 -> 计算高度”的尺寸契约接入默认创建逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: addMarkdownItem(markdownSource:style:)
// 功能说明: 修改前 markdown block 直接使用固定容器尺寸 320x180，不根据内容测量高度。
private static let defaultMarkdownItemSize = CGSize(width: 320, height: 180)

func addMarkdownItem(
    markdownSource: String = CanvasEditorSession.defaultMarkdownSource,
    style: CanvasTextStyle = .default
) -> CanvasMarkdownItem? {
    let item = CanvasMarkdownItem(
        markdownSource: markdownSource,
        style: style,
        center: camera.center,
        size: Self.defaultMarkdownItemSize,
        zIndex: nextBoardItemZIndex()
    )
    // 其他历史与选中态逻辑省略。
    return item
}
```

#### 修改后

- 常量语义从固定 `size` 改成固定 `defaultMarkdownMaxLayoutWidth`。
- `addMarkdownItem(...)` 会先调用 `CanvasMarkdownLayoutMeasurer.measuredContentHeight(...)`，再用 `320 x measuredHeight` 作为默认容器尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: addMarkdownItem(markdownSource:style:)
// 功能说明: 修改后 markdown block 默认按固定宽度 320 排版，再反推初始高度。
private static let defaultMarkdownSource = """
## Markdown

Write here.
"""
private static let defaultMarkdownMaxLayoutWidth: CGFloat = 320

func addMarkdownItem(
    markdownSource: String = CanvasEditorSession.defaultMarkdownSource,
    style: CanvasTextStyle = .default
) -> CanvasMarkdownItem? {
    guard canAddMarkdownItem else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    let defaultMarkdownHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: markdownSource,
        style: style,
        maxLayoutWidth: Self.defaultMarkdownMaxLayoutWidth
    )
    let item = CanvasMarkdownItem(
        markdownSource: markdownSource,
        style: style,
        center: camera.center,
        size: CGSize(
            width: Self.defaultMarkdownMaxLayoutWidth,
            height: defaultMarkdownHeight
        ),
        zIndex: nextBoardItemZIndex()
    )
    // 其他历史与选中态逻辑省略。
    return item
}
```

## 修改三：新增独立 markdown 渲染层，并接入 iOS / macOS viewport

### 3.1 `CanvasMarkdownLayer`

#### 修改前

- 工程内不存在 markdown 专用 `CATextLayer` 子类。
- viewport 无法根据 markdown source、容器宽度和 `zoomScale` 单独决定何时重排 attributed 内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift（修改前）
// 类型名: CanvasMarkdownLayer
// 功能说明: 修改前工程内不存在 markdown 专用渲染层，主画布只能继续复用 CanvasTextLayer。
// 此文件不存在。
```

#### 修改后

- 新增 `CanvasMarkdownLayer`，缓存 `markdownSource/style/zoomScale/layoutWidth`。
- `update(...)` 中会在容器宽度、源文本、样式或缩放变化时重新调用 `CanvasMarkdownLayoutMeasurer.layout(...)`。
- `configureLayer()` 中启用 `masksToBounds = true`，从而让容器高度不足时按 block 边界裁切内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownLayer.swift
// 类型名: CanvasMarkdownLayer
// 功能说明: 修改后新增 markdown 专用渲染层，负责容器宽度驱动的重排与内容裁切。
final class CanvasMarkdownLayer: CATextLayer {
    let itemID: CanvasItemID
    private var lastAppliedMarkdownSource: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedZoomScale: CGFloat
    private var lastAppliedLayoutWidth: CGFloat

    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        if shouldRefreshAttributedText(
            markdownPayload: markdownPayload,
            layoutWidth: item.screenBoundsSize.width
        ) {
            let layout = CanvasMarkdownLayoutMeasurer.layout(
                markdownSource: markdownPayload.markdownSource,
                style: markdownPayload.style,
                maxLayoutWidth: item.screenBoundsSize.width,
                scale: markdownPayload.zoomScale
            )
            string = layout.attributedText
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedZoomScale = markdownPayload.zoomScale
            lastAppliedLayoutWidth = item.screenBoundsSize.width
        }
    }

    private func configureLayer() {
        alignmentMode = .left
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        isWrapped = true
        truncationMode = .none
        masksToBounds = true
    }
}
```

### 3.2 `iOSCanvasViewportView`

#### 修改前

- iOS viewport 只维护 `imageLayers`、`handDrawingLayers`、`textLayers` 三类 layer 池。
- `snapshot.items` 的刷新分支也只有 `.image` / `.handDrawing` / `.text` 三路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift（修改前）
// 函数名: refreshVisibleItemLayers() / textLayer(for:)
// 功能说明: 修改前 iOS viewport 没有 markdown layer 生命周期，markdown 仍然只能走 text layer。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

let incomingTextIDs = Set(
    snapshot.items.compactMap { item in
        if case .text = item.payload {
            return item.id
        }
        return nil
    }
)

for item in snapshot.items {
    switch item.payload {
    case let .image(imagePayload):
        // ...
    case let .handDrawing(handDrawingPayload):
        // ...
    case let .text(textPayload):
        let textLayer = textLayer(for: item.id)
        textLayer.update(
            with: item,
            textPayload: textPayload,
            contentsScale: contentsScale
        )
    }
}
```

#### 修改后

- 新增 `markdownLayers`。
- 在 layer 回收、payload 分发和 layer 工厂三处都补上 markdown 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshVisibleItemLayers() / markdownLayer(for:)
// 功能说明: 修改后 iOS viewport 已接入 markdown layer 的回收、分发与创建流程。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]
private var markdownLayers: [CanvasItemID: CanvasMarkdownLayer] = [:]

let incomingMarkdownIDs = Set(
    snapshot.items.compactMap { item in
        if case .markdown = item.payload {
            return item.id
        }
        return nil
    }
)

for removedID in existingMarkdownIDs.subtracting(incomingMarkdownIDs) {
    markdownLayers[removedID]?.removeFromSuperlayer()
    markdownLayers[removedID] = nil
}

for item in snapshot.items {
    switch item.payload {
    case let .markdown(markdownPayload):
        let markdownLayer = markdownLayer(for: item.id)
        markdownLayer.update(
            with: item,
            markdownPayload: markdownPayload,
            contentsScale: contentsScale
        )
    // 其他 payload case 省略。
    }
}

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

### 3.3 `macOSCanvasViewportView`

#### 修改前

- macOS viewport 的 layer 池和 payload 刷新路径与 iOS 一样，也还没有 markdown 独立分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift（修改前）
// 函数名: refreshVisibleItemLayers() / textLayer(for:)
// 功能说明: 修改前 macOS viewport 也没有 markdown layer 生命周期，双端渲染语义尚未分叉。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]

for item in snapshot.items {
    switch item.payload {
    case let .text(textPayload):
        let textLayer = textLayer(for: item.id)
        textLayer.update(
            with: item,
            textPayload: textPayload,
            contentsScale: contentsScale
        )
    // 其他 payload case 省略。
    }
}
```

#### 修改后

- macOS 端同步新增 `markdownLayers`、`incomingMarkdownIDs` 和 `.markdown` 刷新分支。
- 双端 viewport 现在都能基于 `CanvasMarkdownRenderPayload` 驱动同一套 `CanvasMarkdownLayer`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshVisibleItemLayers() / markdownLayer(for:)
// 功能说明: 修改后 macOS viewport 与 iOS 对齐，开始维护 markdown layer 的完整生命周期。
private var imageLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var handDrawingLayers: [CanvasItemID: CanvasImageLayer] = [:]
private var textLayers: [CanvasItemID: CanvasTextLayer] = [:]
private var markdownLayers: [CanvasItemID: CanvasMarkdownLayer] = [:]

let incomingMarkdownIDs = Set(
    snapshot.items.compactMap { item in
        if case .markdown = item.payload {
            return item.id
        }
        return nil
    }
)

for removedID in existingMarkdownIDs.subtracting(incomingMarkdownIDs) {
    markdownLayers[removedID]?.removeFromSuperlayer()
    markdownLayers[removedID] = nil
}

for item in snapshot.items {
    switch item.payload {
    case let .markdown(markdownPayload):
        let markdownLayer = markdownLayer(for: item.id)
        markdownLayer.update(
            with: item,
            markdownPayload: markdownPayload,
            contentsScale: contentsScale
        )
    // 其他 payload case 省略。
    }
}

private func markdownLayer(for itemID: CanvasItemID) -> CanvasMarkdownLayer {
    if let markdownLayer = markdownLayers[itemID] {
        return markdownLayer
    }

    let markdownLayer = CanvasMarkdownLayer(itemID: itemID)
    itemsLayer.addSublayer(markdownLayer)
    markdownLayers[itemID] = markdownLayer
    return markdownLayer
}
```

## 修改四：补阶段 2 定向测试，锁定测量 / 渲染层 / 默认尺寸契约

### 4.1 `CanvasMarkdownLayoutMeasurerTests`

#### 修改前

- 工程内没有 markdown 测量器的专项测试。
- 阶段 2 的核心契约“宽度变窄高度变高”“基础子集能转换为可显示文本”“标题字号高于正文”都没有自动化覆盖。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift（修改前）
// 类型名: CanvasMarkdownLayoutMeasurerTests
// 功能说明: 修改前工程内不存在 markdown 测量器定向测试。
// 此文件不存在。
```

#### 修改后

- 新增 `CanvasMarkdownLayoutMeasurerTests`，覆盖：
  - 宽度变窄时高度增长。
  - 基础子集能被转换成主画布可显示的文本内容。
  - 标题字号高于正文。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests.swift
// 类型名: CanvasMarkdownLayoutMeasurerTests
// 功能说明: 修改后新增 markdown 测量器测试，锁定阶段 2 的基础布局与排版契约。
@MainActor
final class CanvasMarkdownLayoutMeasurerTests: XCTestCase {
    func testMeasuredContentHeightGrowsWhenWidthShrinks() {
        let wideHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: 320
        )
        let narrowHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: source,
            style: style,
            maxLayoutWidth: 160
        )

        XCTAssertGreaterThan(narrowHeight, wideHeight)
    }

    func testLayoutConvertsBasicBlocksIntoDisplayText() {
        XCTAssertTrue(layout.attributedText.string.contains("• item"))
        XCTAssertTrue(layout.attributedText.string.contains("▌ quote"))
        XCTAssertTrue(layout.attributedText.string.contains("code"))
    }

    func testHeadingUsesLargerFontThanBody() throws {
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
    }
}
```

### 4.2 `CanvasMarkdownLayerTests`

#### 修改前

- 工程内没有 markdown layer 的专项测试。
- `zoomScale` 是否真正体现在渲染字体尺寸上、layer 是否收到 markdown attributed 内容，都还没有测试约束。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前）
// 类型名: CanvasMarkdownLayerTests
// 功能说明: 修改前工程内不存在 markdown layer 定向测试。
// 此文件不存在。
```

#### 修改后

- 新增 `CanvasMarkdownLayerTests`，验证：
  - `CanvasMarkdownLayer.update(...)` 会写入 attributed markdown。
  - `zoomScale` 会把正文字号放大。
  - 标题字号仍高于正文。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 类型名: CanvasMarkdownLayerTests
// 功能说明: 修改后新增 markdown layer 测试，锁定 zoom 缩放、attributed 内容和容器尺寸应用。
@MainActor
final class CanvasMarkdownLayerTests: XCTestCase {
    func testUpdateBuildsAttributedMarkdownUsingZoomScaledFonts() throws {
        let layer = CanvasMarkdownLayer(itemID: itemID)
        let payload = CanvasMarkdownRenderPayload(
            markdownSource: """
            ## Title

            Body with `code`
            """,
            style: CanvasTextStyle(fontSize: 18),
            zoomScale: 1.5
        )

        layer.update(
            with: renderItem,
            markdownPayload: payload,
            contentsScale: 2
        )

        XCTAssertTrue(rendered.contains("Title"))
        XCTAssertTrue(rendered.contains("code"))
        XCTAssertEqual(layer.bounds.size, CGSize(width: 220, height: 120))
        XCTAssertGreaterThan(bodyFont.pointSize, payload.style.fontSize)
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
    }
}
```

### 4.3 `CanvasCommandPolicyParityTests`

#### 修改前

- `CanvasCommandPolicyParityTests` 只覆盖了阶段 1 的 markdown 命令准入与字号 `+/-` 历史行为。
- 还没有测试“默认新建 markdown block 是否按固定宽度测量高度”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift（修改前）
// 函数名: testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth()
// 功能说明: 修改前不存在默认创建尺寸契约测试，320 宽度与测量高度之间没有自动化约束。
// 此函数不存在。
```

#### 修改后

- 新增 `testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth()`。
- 该测试确保 `addMarkdownItem(...)` 产出的默认宽度固定为 `320`，高度严格等于 `CanvasMarkdownLayoutMeasurer.measuredContentHeight(...)` 的结果。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth()
// 功能说明: 修改后新增默认创建尺寸契约测试，锁定“固定宽度 320 -> 反推高度”的阶段 2 入口行为。
func testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let source = """
    ## Markdown

    A wrapped paragraph for measurement.
    """
    let style = CanvasTextStyle(fontSize: 20)

    let item = try XCTUnwrap(
        session.addMarkdownItem(
            markdownSource: source,
            style: style
        )
    )
    let expectedHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: source,
        style: style,
        maxLayoutWidth: 320
    )

    XCTAssertEqual(item.size.width, 320, accuracy: 0.0001)
    XCTAssertEqual(item.size.height, expectedHeight, accuracy: 0.0001)
}
```

## 验证结果

- `ReadLints` 检查本次修改文件，无新增 linter 问题。
- 已执行并通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayoutMeasurerTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests`
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'`
- 中途出现过一次 `CanvasMarkdownLayoutMeasurer.swift` 的局部变量名与 `quoteLine(from:)` 同名导致的编译错误，已在本次提交范围内修正，不再保留在当前 changes 中。
