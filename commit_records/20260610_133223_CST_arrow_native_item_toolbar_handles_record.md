# 20260610_133223_CST_arrow_native_item_toolbar_handles_record

## 记录范围

- 记录内容：
  - 在主工具条中新增“添加箭头”按钮，使用图标按钮而不是文字按钮。
  - 将箭头实现为正式的 `CanvasBoardItem`，而不是临时绘制态或图片占位。
  - 打通箭头的模型、命令、工具条、渲染、命中测试、拖拽、存储、小地图、缩略图与测试。
  - 单选箭头时，仅暴露首尾两个端点 handle；不再复用普通 block 的 8 个 resize handle 与 rotate handle。
- 涉及文件：
  - 模型与存储：
    - `MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
    - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
    - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - 命令、工具条与控制器入口：
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
    - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
    - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
    - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
    - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
    - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
    - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - 渲染、选中态、命中与拖拽：
    - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift`
    - `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift`
    - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasArrowLayer.swift`
    - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
    - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - 小地图、缩略图与测试：
    - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
    - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
    - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
    - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
    - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
    - `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
    - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
- 本记录不包含：
  - 任何提交操作。
  - 原始 `git diff` 全文粘贴。
  - 对现有 `.md` 文件的覆盖或删除。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统 date 命令生成本记录文件的时间戳前缀。
20260610_133223_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- . ':(exclude)*.md'
# 功能说明: 汇总生成本文件之前，当前 tracked changes 的体量与分布；不直接粘贴原始 diff。
 MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift   |  46 +++++++
 .../Canvas/Core/CanvasContextMenuContext.swift     |  10 +-
 .../Canvas/Core/CanvasContextResolver.swift        |   5 +
 .../Canvas/Core/CanvasEditOverlayHitTester.swift   |  62 ++++++++--
 .../Canvas/Core/CanvasMiniMapNodeProvider.swift    |  27 +++++
 .../Canvas/Core/CanvasMiniMapRenderer.swift        |   3 +-
 .../Canvas/Core/CanvasPointerPressContext.swift    |   3 +
 .../Canvas/Core/CanvasRenderSnapshot.swift         |  32 ++++-
 MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift    | 133 +++++++++++++++++++--
 MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift       |  16 ++-
 .../Canvas/Editing/BoardHistorySnapshot.swift      |   2 +
 MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift  |   7 ++
 .../Canvas/Editing/CanvasCommandCatalog.swift      |   8 ++
 .../Canvas/Editing/CanvasCommandExecutor.swift     |  10 ++
 .../Canvas/Editing/CanvasEditorSession.swift       |  32 +++++
 .../Editing/CanvasSelectionTransformState.swift    |   6 +-
 .../Input/CanvasClickSelectionResolver.swift       |   6 +
 MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift  |  51 +++++++-
 .../Canvas/Storage/BoardDocumentMapper.swift       |  28 +++++
 .../BoardList/BoardGeometryPreviewBuilder.swift    |  11 ++
 .../Shared/BoardList/BoardThumbnailRenderer.swift  |  65 +++++++++-
 .../CanvasContextMenuCommandResolver.swift         |   5 +-
 .../Shared/Toolbar/CanvasToolbarState.swift        |   1 +
 .../Shared/Toolbar/CanvasToolbarStateBuilder.swift |  18 ++-
 .../iOS/Canvas/iOSCanvasToolbarHostView.swift      |   2 +-
 .../iOS/Canvas/iOSCanvasViewportView.swift         | 109 +++++++++++++++--
 .../Platform/iOS/iOSViewController.swift           |  86 ++++++++++++-
 .../macOS/Canvas/macOSCanvasViewportView.swift     | 109 +++++++++++++++--
 .../Platform/macOS/macOSViewController.swift       |  88 +++++++++++++-
 .../CanvasCommandPolicyParityTests.swift           |  59 +++++++++
 .../CanvasEditorSessionAlignmentOverlayTests.swift |  32 ++++-
 .../CanvasToolbarStateBuilderTests.swift           |  23 +++-
 32 files changed, 1035 insertions(+), 60 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录本文件生成时的当前 changes；其中 3 个箭头核心文件为新增未跟踪文件。
 M MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextMenuContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasPointerPressContext.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
 M MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
 M MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
 M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
 M MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
 M MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
?? MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
?? MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift
?? MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasArrowLayer.swift
```

## 当前 changes 摘要

- 新增 3 个箭头核心文件：
  - `CanvasArrowItem.swift`
  - `CanvasArrowEndpointDragState.swift`
  - `CanvasArrowLayer.swift`
- 其余改动主要分成 5 个方向：
  - 把箭头纳入正式 item 类型系统与持久化协议。
  - 把 `addArrowItem` 打通到命令、工具条与控制器入口。
  - 为箭头建立独立 render payload、viewport layer 与选中态路径。
  - 在 hit-test / pointer state machine 中引入端点 handle 与拖拽几何求解。
  - 在 minimap / thumbnail / tests 中补上箭头链路与回归验证。

## 修改一：把箭头接入原生 item 模型与持久化主链

### 修改前

- `CanvasBoardItemKind` 与 `CanvasBoardItem` 里没有 `arrow`。
- 画布只承认 `image / text / markdown / handDrawing` 四类正式元素。
- `BoardDocument` / `BoardItemRecord` 也没有箭头记录类型，意味着箭头无法参与保存和加载。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前）
// 函数名: enum CanvasBoardItemKind / enum CanvasBoardItem
// 功能说明: 修改前画布类型系统里没有 arrow，箭头不可能成为正式的 BoardItem。
enum CanvasBoardItemKind: Equatable {
    case image
    case text
    case markdown
    case handDrawing
}

enum CanvasBoardItem {
    case image(CanvasImageItem)
    case text(CanvasTextItem)
    case markdown(CanvasMarkdownItem)
    case handDrawing(CanvasHandDrawingItem)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift（修改前）
// 函数名: enum BoardItemRecord / private enum ItemType
// 功能说明: 修改前持久化层没有 arrow record，文档格式无法编码或解码箭头元素。
enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case markdown(BoardMarkdownItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)
}

private enum ItemType: String, Codable {
    case image
    case text
    case markdown
    case handDrawing
}
```

### 修改后

- 新增 `CanvasArrowItem`，统一承载箭头的几何、命中和实心轮廓计算。
- `CanvasBoardItem` / `CanvasScene` / `BoardHistorySnapshot` 全部接入 `.arrow` 分支。
- `BoardDocument` 新增 `BoardArrowItemRecord`，并通过 `BoardDocumentMapper` 完成双向映射。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
// 函数名: CanvasArrowItem / endpointWorldPoint(for:) / canvasArrowPolygonPoints(in:)
// 功能说明: 新增原生箭头元素，负责端点坐标、旋转映射、命中测试和实心箭头路径生成。
enum CanvasArrowEndpointRole: CaseIterable {
    case start
    case end
}

struct CanvasArrowItem {
    let id: CanvasItemID
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat

    func contains(worldPoint: CGPoint) -> Bool {
        let localPoint = localPoint(fromWorld: worldPoint)
        return canvasArrowPath(in: localFrame).contains(localPoint)
    }

    func endpointWorldPoint(
        for role: CanvasArrowEndpointRole
    ) -> CGPoint {
        worldPoint(fromLocal: endpointLocalPoint(for: role))
    }
}

func canvasArrowPolygonPoints(in rect: CGRect) -> [CGPoint] {
    // 通过尾部厚度、箭头颈部和头部长宽比例，构造一个实心箭头多边形。
    // ... 省略若干比例计算 ...
    return [
        CGPoint(x: startX, y: centerY - tailHalfHeight),
        CGPoint(x: neckX, y: centerY - tailHalfHeight),
        CGPoint(x: neckX, y: standardizedRect.minY),
        CGPoint(x: endX, y: centerY),
        CGPoint(x: neckX, y: standardizedRect.maxY),
        CGPoint(x: neckX, y: centerY + tailHalfHeight),
        CGPoint(x: startX, y: centerY + tailHalfHeight)
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardArrowItemRecord / BoardItemRecord / encode(to:) / init(from:)
// 功能说明: 文档层新增 arrow 记录，并让 BoardDocument formatVersion 认识这种正式元素。
struct BoardArrowItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var rotationRadians: Double?
}

enum BoardItemRecord: Codable, Equatable {
    case image(BoardImageItemRecord)
    case text(BoardTextItemRecord)
    case markdown(BoardMarkdownItemRecord)
    case handDrawing(BoardHandDrawingItemRecord)
    case arrow(BoardArrowItemRecord)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeArrowItem(from:) / makeArrowRecord(from:)
// 功能说明: 文档 record 与运行时 arrow item 双向映射；外围 makeRuntimeState / makeItemRecord 已新增对 .arrow 的 switch 分支。
private static func makeArrowItem(
    from arrowRecord: BoardArrowItemRecord
) -> CanvasArrowItem {
    CanvasArrowItem(
        id: arrowRecord.id,
        center: arrowRecord.center.cgPoint,
        size: arrowRecord.size.cgSize,
        zIndex: CGFloat(arrowRecord.zIndex),
        rotationRadians: CGFloat(arrowRecord.rotationRadians ?? 0)
    )
}

private static func makeArrowRecord(
    from item: CanvasArrowItem
) -> BoardArrowItemRecord {
    BoardArrowItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

## 修改二：把 “Add Arrow” 接入命令链、工具条与控制器入口

### 修改前

- 命令层没有 `addArrowItem`，工具条状态构建器也没有 `.arrow` item。
- 控制器按钮字典里没有箭头按钮实例，因此平台层根本没有点击入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift（修改前）
// 函数名: enum CanvasCommandID / enum CanvasCommand
// 功能说明: 修改前命令层没有 addArrowItem，工具条和控制器无法分发“添加箭头”动作。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case addMarkdownItem
    case addHandDrawingItem
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case addMarkdownItem(markdownSource: String?)
    case addHandDrawingItem(paper: CanvasHandDrawingPaperSpec)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift（修改前）
// 函数名: mainToolbarState(session:saveState:placement:...)
// 功能说明: 修改前主工具条最多拼到 handDrawing，没有 arrowItemState。
itemStates.append(textItemState(session: session))
itemStates.append(markdownItemState(session: session))
if supportsHandDrawingEditing {
    itemStates.append(handDrawingItemState(session: session))
}
itemStates.append(importItemState(isEnabled: isImportEnabled))
```

### 修改后

- 命令层新增 `CanvasCommandID.addArrowItem` 与 `CanvasCommand.addArrowItem`。
- `CanvasEditorSession.addArrowItem()` 负责在相机中心创建默认向右的实心箭头，并记录历史。
- 工具条新增 `.arrow` 按钮，系统图标为 `arrowshape.right.fill`。
- macOS / iOS 控制器同步加上按钮实例、按钮映射、setup 和点击分发。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: addArrowItem()
// 功能说明: 插入默认箭头，并立即选中、扩展 board 边界、写入历史记录。
@discardableResult
func addArrowItem() -> CanvasArrowItem? {
    guard canAddArrowItem else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasArrowItem(
        center: camera.center,
        size: Self.defaultArrowSize,
        zIndex: nextBoardItemZIndex()
    )
    scene.append(item)
    _ = replaceSelection(
        with: [item.id],
        primarySelectedItemID: item.id
    )
    expandBoardIfNeeded(toInclude: item.worldBounds)
    let changeReason = "add arrow item"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return item
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(session:...) / arrowItemState(session:)
// 功能说明: 主工具条新增 arrow item，并用命令描述符统一驱动 enabled/active/icon。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    supportsHandDrawingEditing: Bool = false,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    // ... 省略历史、裁剪、多选、删除、保存等逻辑 ...
    itemStates.append(textItemState(session: session))
    itemStates.append(markdownItemState(session: session))
    if supportsHandDrawingEditing {
        itemStates.append(handDrawingItemState(session: session))
    }
    itemStates.append(arrowItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))
    // ... 省略返回 ...
}

func arrowItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
    let descriptor = commandCatalog.descriptor(
        for: .addArrowItem,
        session: session
    )
    return CanvasToolbarItemState(
        id: .arrow,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        isActive: descriptor.isActive,
        accessibilityLabel: "Add arrow",
        visualRole: .accent
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: toolbarButtonsByID / setupArrowButton() / handleArrowButtonClick()
// 功能说明: macOS 控制器新增箭头按钮实例、工具条映射与点击事件；iOS 控制器同步采用同构接法。
private let arrowButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .text: textButton,
        .markdown: markdownButton,
        .handDrawing: handDrawingButton,
        .arrow: arrowButton,
        .importMedia: importButton
    ]
}

private func setupArrowButton() {
    arrowButton.target = self
    arrowButton.action = #selector(handleArrowButtonClick)
    renderToolbar()
}
```

## 修改三：把箭头接入渲染合同，并改写单选 overlay 语义

### 修改前

- 渲染快照里没有 `arrow` payload。
- 选中 overlay 默认总是带 `rotateAffordance`，并围绕矩形 `quad` 生成普通 handle。
- 因为没有箭头专属轮廓与 path，选区轮廓与平移热区都只能按矩形包围盒处理。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前）
// 函数名: CanvasRenderPayload / CanvasEditHandleRole / CanvasEditSelectionOverlayPayload
// 功能说明: 修改前没有 arrow render payload，也没有 arrowStart / arrowEnd 两类 handle。
enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
    case markdown(CanvasMarkdownRenderPayload)
}

enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
    case rotate
}

struct CanvasEditSelectionOverlayPayload {
    let subject: CanvasEditSelectionOverlaySubject
    let rotateAffordance: CanvasEditRotateOverlayPayload
}
```

### 修改后

- 新增 `CanvasArrowRenderPayload` 与 `CanvasRenderPayload.arrow(...)`。
- 新增 `CanvasEditHandleRole.arrowStart / .arrowEnd`。
- `CanvasEditSelectionOverlayPayload.rotateAffordance` 改为可选，并新增 `outlineScreenPath / translationScreenPath`。
- `CanvasRenderer` 对单选箭头做特殊分支：使用箭头 path 作为轮廓和拖拽区域，只生成首尾两个 handle，不显示旋转手柄。
- viewport 层新增 `CanvasArrowLayer`，负责实际的实心箭头图层更新。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasRenderPayload / CanvasEditHandleRole / CanvasEditSelectionOverlayPayload
// 功能说明: 为箭头补齐 render payload、端点 handle 和可选 rotate affordance。
struct CanvasArrowRenderPayload {}

enum CanvasRenderPayload {
    case image(CanvasImageRenderPayload)
    case handDrawing(CanvasHandDrawingRenderPayload)
    case text(CanvasTextRenderPayload)
    case markdown(CanvasMarkdownRenderPayload)
    case arrow(CanvasArrowRenderPayload)
}

enum CanvasEditHandleRole: CaseIterable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading
    case rotate
    case arrowStart
    case arrowEnd
}

struct CanvasEditSelectionOverlayPayload {
    let subject: CanvasEditSelectionOverlaySubject
    let rotateAffordance: CanvasEditRotateOverlayPayload?
    let outlineScreenPath: CGPath?
    let translationScreenPath: CGPath?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(...) / makeArrowRenderItem(...) / makeArrowEndpointHandles(...)
// 功能说明: 单选箭头时，渲染层为其生成原生 render item、箭头轮廓 path 和两个端点 handle。
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
    selectionHandles = selectionEditHandles(
        forSingleSelectedItem: effectiveItem,
        screenQuad: screenQuad,
        camera: camera
    )
    if let arrowItem = effectiveItem.arrowItem {
        let arrowScreenPath = makeArrowScreenPath(
            for: arrowItem,
            camera: camera
        )
        selectionOutlineScreenPath = arrowScreenPath
        selectionTranslationScreenPath = arrowScreenPath
        rotateAffordance = nil
    } else {
        selectionOutlineScreenPath = nil
        selectionTranslationScreenPath = nil
        rotateAffordance = makeRotateAffordance(
            screenCenter: screenCenter,
            screenQuad: screenQuad
        )
    }
}

private func makeArrowEndpointHandles(
    for item: CanvasArrowItem,
    camera: CanvasCamera
) -> [CanvasEditHandleGeometry] {
    CanvasArrowEndpointRole.allCases.map { role in
        CanvasEditHandleGeometry(
            role: role == .start ? .arrowStart : .arrowEnd,
            screenCenter: camera.worldToViewport(
                item.endpointWorldPoint(for: role)
            ),
            screenRotationRadians: item.rotationRadians
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasArrowLayer.swift
// 函数名: update(with:contentsScale:)
// 功能说明: viewport 图层新增专用 CAShapeLayer，直接根据 render item 的中心、旋转和尺寸更新实心箭头。
final class CanvasArrowLayer: CAShapeLayer {
    func update(
        with item: CanvasRenderItem,
        contentsScale: CGFloat
    ) {
        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            path = canvasArrowPath(in: bounds)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if lastAppliedRotationRadians != item.rotationRadians {
            transform = CATransform3DMakeRotation(item.rotationRadians, 0, 0, 1)
            lastAppliedRotationRadians = item.rotationRadians
        }
    }
}
```

## 修改四：把箭头端点命中与拖拽纳入共享指针状态机

### 修改前

- 命中测试只认识普通 `selectionHandle / groupSelectionHandle / rotateHandle / cropHandle`。
- 控制器的主拖拽状态机只会把普通选中 handle 解释成 `resizingSelectedItem`。
- 没有“固定一端、拖动另一端并重算长度/朝向”的独立几何求解状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift（修改前）
// 函数名: enum CanvasEditOverlayHitTargetKind / resolveSelectionHitTarget(...)
// 功能说明: 修改前没有 arrowEndpointHandle，选中态命中只能落到普通 resize / rotate / crop 分支。
enum CanvasEditOverlayHitTargetKind {
    case rotateHandle
    case groupRotateHandle
    case selectionHandle(role: CanvasSelectionHandleRole)
    case groupSelectionHandle(role: CanvasSelectionHandleRole)
    case selectionTranslationArea
    case cropHandle(role: CanvasCropHandleRole)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: handlePrimaryPointerMove(to:from:)
// 功能说明: 修改前单选 handle 拖拽只有普通 resizingSelectedItem 路径，没有箭头端点专用状态。
case let .selectionHandle(handleRole):
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }

    guard let resizeState = makePointerResizeState(itemID: itemID, handleRole: handleRole) else {
        pointerDragState = .idle
        return
    }

    pointerDragState = .resizingSelectedItem(resizeState)
    resizeSelectedItem(using: resizeState, to: location)
```

### 修改后

- 命中测试新增 `arrowEndpointHandle(role:)`。
- `CanvasArrowEndpointDragState` 固化“固定端点 + 当前拖动端点 + 保留厚度 + 最小长度”这套几何合同。
- macOS / iOS 控制器都新增 `.adjustingArrowEndpoint(...)` 指针状态，并在 pointer move / up / cancel / history transaction 中接入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasEditOverlayHitTester.swift
// 函数名: resolveSelectionHitTarget(at:editOverlay:renderSnapshot:metrics:)
// 功能说明: 为箭头端点新增命中分支，并允许箭头 path 自身充当 selection translation area。
if let rotateAffordance = payload.rotateAffordance {
    // 只有非箭头单选或组选择才会走到 rotate hit 检测。
}

for handle in editOverlay.handles {
    if let role = handle.role.arrowEndpointRole {
        let hitRect = rect(
            centeredAt: handle.screenCenter,
            size: metrics.selectionHandleHitTargetSize
        )
        if hitRect.contains(viewportPoint) {
            return CanvasEditOverlayHitTarget(
                kind: .arrowEndpointHandle(role: role),
                itemID: editOverlay.itemID,
                anchorRect: hitRect
            )
        }
    }
}

if isWithinSelectionTranslationArea(
    viewportPoint,
    selectionScreenQuad: editOverlay.activeScreenQuad,
    selectionTranslationPath: payload.translationScreenPath,
    selectedMemberScreenQuads: selectedMemberScreenQuads,
    expectedMemberCount: payload.subject.memberItemIDs.count,
    outlineHitSlopWidth: metrics.selectionOutlineHitTargetWidth
) {
    return CanvasEditOverlayHitTarget(
        kind: .selectionTranslationArea,
        itemID: editOverlay.itemID,
        anchorRect: editOverlay.activeScreenQuad.boundingRect.standardized
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift
// 函数名: updatedGeometry(draggedWorldPoint:)
// 功能说明: 固定一端、拖动一端时，统一重算箭头中心、长度和旋转角，并限制最短长度。
struct CanvasArrowEndpointDragState {
    let itemID: CanvasItemID
    let draggedEndpointRole: CanvasArrowEndpointRole
    let fixedEndpointWorldPoint: CGPoint
    let preservedThickness: CGFloat
    let minimumLength: CGFloat
    let fallbackRotationRadians: CGFloat

    func updatedGeometry(
        draggedWorldPoint: CGPoint
    ) -> CanvasBoardItemGeometry {
        // 若长度过短，则沿既有方向或 fallbackRotationRadians 回退到最短长度。
        // 最终把新的中心、尺寸和旋转写回 CanvasBoardItemGeometry。
        return CanvasBoardItemGeometry(
            itemID: itemID,
            center: CGPoint(
                x: (startWorldPoint.x + endWorldPoint.x) / 2,
                y: (startWorldPoint.y + endWorldPoint.y) / 2
            ),
            size: CGSize(
                width: length,
                height: preservedThickness
            ),
            rotationRadians: atan2(direction.y, direction.x)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerMove(to:from:) / makePointerArrowEndpointState(itemID:endpointRole:) / adjustArrowEndpoint(using:to:)
// 功能说明: macOS 指针状态机把 arrowEndpointHandle 分支接入拖拽求解；iOS 控制器同步使用同样的状态模型。
case let .arrowEndpointHandle(endpointRole):
    guard let itemID = pressContext.targetItemID else {
        pointerDragState = .idle
        return
    }

    guard let endpointState = makePointerArrowEndpointState(
        itemID: itemID,
        endpointRole: endpointRole
    ) else {
        pointerDragState = .idle
        return
    }

    pointerDragState = .adjustingArrowEndpoint(endpointState)
    adjustArrowEndpoint(using: endpointState, to: location)

private func adjustArrowEndpoint(
    using endpointState: CanvasArrowEndpointDragState,
    to viewportLocation: CGPoint
) {
    let geometry = endpointState.updatedGeometry(
        draggedWorldPoint: camera.viewportToWorld(viewportLocation)
    )
    guard let updatedArrowItem = scene.applyBoardItemGeometries([geometry])?.first else {
        return
    }

    expandBoardIfNeeded(toInclude: updatedArrowItem.worldBounds)
    refreshCanvas()
}
```

## 修改五：同步补齐 minimap、thumbnail 与回归测试

### 修改前

- minimap provider 链里没有箭头。
- thumbnail 渲染器不认识 `BoardArrowItemRecord`。
- 相关测试也没有覆盖“新增箭头命令、工具条按钮、箭头单选 overlay”这三条主链。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift（修改前）
// 函数名: init(nodeProviders:)
// 功能说明: 修改前 minimap 只注册 image / handDrawing / text / markdown 四类 provider。
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
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift（修改前）
// 函数名: testMainToolbarStateIncludesMultiSelectItem()
// 功能说明: 修改前工具条测试基线里没有 .arrow，也没有箭头入口的断言。
XCTAssertEqual(
    state.items.map(\.id),
    [.undo, .redo, .crop, .multiSelect, .save, .text, .markdown, .importMedia]
)
```

### 修改后

- minimap renderer 注册 `CanvasMiniMapArrowNodeProvider()`。
- thumbnail renderer 新增 `drawArrowItem(...)`，直接按箭头 path 画出实心缩略图。
- 三组测试分别覆盖：
  - 命令/策略/默认几何
  - 工具条按钮存在性
  - 单选箭头仅显示首尾 handle 且不显示 rotate affordance

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: minimap provider 链新增箭头 provider，箭头可以进入 snapshot。
init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
    self.nodeProviders = nodeProviders ?? [
        CanvasMiniMapImageNodeProvider(),
        CanvasMiniMapHandDrawingNodeProvider(),
        CanvasMiniMapTextNodeProvider(),
        CanvasMiniMapMarkdownNodeProvider(),
        CanvasMiniMapArrowNodeProvider()
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapArrowNodeProvider.makeNodes(context:)
// 功能说明: 小地图节点从运行时 arrow item 派生，并沿用现有 shape kind 进入 minimap 渲染。
struct CanvasMiniMapArrowNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
            guard let item = boardItem.arrowItem else {
                return nil
            }

            let effectiveItem = effectiveMiniMapBoardItem(
                from: .arrow(item),
                rotationPreviewState: context.rotationPreviewState
            ).arrowItem ?? item

            return CanvasMiniMapNode(
                id: effectiveItem.id,
                kind: .shape,
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

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawArrowItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: thumbnail 阶段直接按箭头 path 填充，避免把箭头退化成矩形或占位节点。
private func drawArrowItem(
    _ itemRecord: BoardArrowItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext _: BoardThumbnailTraceContext,
    documentOrder _: Int?,
    renderOrder _: Int
) {
    let mappedCenter = geometry.worldToMiniMap(itemRecord.center.cgPoint)
    let rotationRadians = normalizedCanvasAngle(
        CGFloat(itemRecord.rotationRadians ?? 0)
    )
    let path = canvasArrowPath(
        in: CGRect(
            x: -mappedSize.width / 2,
            y: -mappedSize.height / 2,
            width: mappedSize.width,
            height: mappedSize.height
        )
    )

    context.saveGState()
    context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
    context.rotate(by: rotationRadians)
    context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift / MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift / MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testAddArrowCommandCreatesDefaultHorizontalArrow() / testMainToolbarStateIncludesArrowItem() / testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection()
// 功能说明: 回归测试补齐箭头命令、工具条和单选 overlay 的最小闭环。
func testAddArrowCommandCreatesDefaultHorizontalArrow() throws {
    let result = try XCTUnwrap(executor.execute(.addArrowItem))
    let itemID = try XCTUnwrap(session.singleSelectedItemID)
    let item = try XCTUnwrap(session.scene.arrowItem(withID: itemID))

    XCTAssertEqual(item.center, session.camera.center)
    XCTAssertEqual(item.size, CGSize(width: 220, height: 80))
    XCTAssertEqual(item.rotationRadians, 0, accuracy: 0.0001)
    XCTAssertEqual(result.refreshReason, "add arrow item \(item.id.uuidString)")
}

func testMainToolbarStateIncludesArrowItem() throws {
    let arrowItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .arrow })
    )
    XCTAssertEqual(arrowItem.systemImageName, "arrowshape.right.fill")
}

func testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection() throws {
    XCTAssertEqual(editOverlay.handles.map(\.role), [.arrowStart, .arrowEnd])
    XCTAssertNil(payload.rotateAffordance)
}
```

## 验证记录

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests
# 功能说明: 只执行本次箭头改动直接覆盖到的三组测试，确认命令、工具条和 overlay 行为闭环成立。
** TEST SUCCEEDED **

Test case 'CanvasCommandPolicyParityTests.testAddArrowCommandCreatesDefaultHorizontalArrow()' passed
Test case 'CanvasCommandPolicyParityTests.testAddArrowDescriptorAndExecutorMatchPolicyInEditingMode()' passed
Test case 'CanvasCommandPolicyParityTests.testAddArrowDescriptorAndExecutorMatchPolicyInReadingMode()' passed
Test case 'CanvasEditorSessionAlignmentOverlayTests.testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection()' passed
Test case 'CanvasToolbarStateBuilderTests.testMainToolbarStateIncludesArrowItem()' passed
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS'
# 功能说明: 记录本次全量测试的当前运行结果；以下失败名称按实际运行结果原样记录，不在本记录中额外归因。
Test case 'CanvasInputIndicatorQueueTests.testEnqueueKeepsNewestVisibleItems()' failed
Test case 'CanvasInputIndicatorQueueTests.testSnapshotAppliesFadeOutNearLifetimeEnd()' failed
Test case 'CanvasInputIndicatorQueueTests.testSnapshotPurgesExpiredEntries()' failed
Test case 'CanvasInputIndicatorQueueTests.testSnapshotUsesStackOpacityForOlderEntries()' failed
```

## 结论

- 本次改动已经把箭头从“工具条入口”一路接到“正式 item / 可持久化 / 可渲染 / 可选中 / 可拖拽端点 / 可进入 minimap 与 thumbnail / 有定向测试覆盖”。
- 本次文档没有粘贴原始 `git diff`，但所有“修改前 / 修改后”内容都以当前 `git diff`、`git status` 和当前工作区代码为依据整理。
- 本次文档只新增记录文件，不包含提交动作。
