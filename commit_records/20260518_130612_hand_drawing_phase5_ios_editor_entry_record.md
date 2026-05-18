# 20260518_130612_hand_drawing_phase5_ios_editor_entry_record

## 记录范围

- 记录内容：
  1. 为 handDrawing 补 `CanvasCommand`、`CanvasCommandExecutor` follow-up 与 `CanvasEditorSession` API。
  2. 新增 iOS 全屏手绘编辑器，使用 `PKCanvasView` 承载 Apple Pencil 绘制，并把提交结果回写主画布。
  3. 接入 toolbar / context menu 的 `新增手绘` 与 `编辑手绘` 入口，并显式收口 macOS 暂不支持编辑。
  4. 补阶段 5 的定点测试，并执行构建与 lint 验证。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_130612`
- 参考依据：
  - `git status --short`
  - `git diff --stat -- MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
  - `git diff -- MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
  - 当前新增文件内容：
    - `MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
    - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
    - `MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `M MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`
  - `M MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `?? MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
- `git diff --stat` 摘要：
  - 已跟踪文件修改：14 个
  - 统计结果：`642 insertions(+), 11 deletions(-)`
  - 主要改动集中在 `CanvasEditorSession.swift` 与 `iOSViewController.swift`
  - 新增未跟踪文件：3 个
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests -only-testing:MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests CODE_SIGNING_ALLOWED=NO`
    - 通过
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 6 的平台能力收口与更多回归验证
  - git commit / push

## 修改一：command lane 为 handDrawing 建立创建命令与 follow-up

### 修改前

- `CanvasCommandID` 与 `CanvasCommand` 没有 handDrawing 创建入口。
- `CanvasCommandExecutionResult` 只有 `refreshReason`，无法把“创建后立即打开编辑器”的 UI 意图正规从 command lane 传回 controller。
- `CanvasCommandExecutor` 只处理 text / import 等现有命令，没有 handDrawing 创建分支。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandID / CanvasCommand / CanvasCommandExecutionResult
// 功能说明: 修改前 command lane 没有 handDrawing 创建命令，执行结果也无法携带 UI follow-up。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case beginTextEdit
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    // 其余 case 省略
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    // 其余 case 省略
}

struct CanvasCommandExecutionResult {
    let refreshReason: String?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改前 executor 只认识 addTextItem 等已有命令，不会返回 handDrawing editor follow-up。
switch command {
case let .importMedia(request):
    return request.isEmpty == false
case .addTextItem:
    return session.canAddTextItem
case let .beginTextEdit(itemID):
    return session.canBeginTextEdit(withID: itemID)
// 其余分支省略
}

case .addTextItem:
    guard let addedTextItem = session.addTextItem() else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "add text item \(addedTextItem.id.uuidString)"
    )
```

### 修改后

- `CanvasCommandID` / `CanvasCommand` 新增 `addHandDrawingItem(paper:)`。
- 新增 `CanvasCommandFollowUp.presentHandDrawingEditor(itemID:)`。
- `CanvasCommandExecutionResult` 同时支持 `refreshReason` 与 `followUp`。
- `CanvasCommandExecutor` 在 handDrawing 新建成功后，直接回传“立即 present 编辑器”的后续 UI 意图。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名: CanvasCommandID / CanvasCommand / CanvasCommandFollowUp / CanvasCommandExecutionResult
// 功能说明: 修改后 command lane 可以创建 handDrawing，并把“立即打开编辑器”作为 follow-up 返回给 controller。
enum CanvasCommandID: String {
    case importMedia
    case addTextItem
    case addHandDrawingItem
    case beginTextEdit
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    // 其余 case 省略
}

enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case addHandDrawingItem(paper: CanvasHandDrawingPaperSpec)
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
    case decreaseTextFontSize
    case increaseTextFontSize
    case crop
    // 其余 case 省略
}

enum CanvasCommandFollowUp: Equatable {
    case presentHandDrawingEditor(itemID: CanvasItemID)
}

struct CanvasCommandExecutionResult {
    let refreshReason: String?
    let followUp: CanvasCommandFollowUp?

    init(
        refreshReason: String?,
        followUp: CanvasCommandFollowUp? = nil
    ) {
        self.refreshReason = refreshReason
        self.followUp = followUp
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: canExecute(_:) / execute(_:)
// 功能说明: 修改后 addHandDrawingItem 先走 session 创建文档变更，再返回 presentHandDrawingEditor follow-up。
switch command {
case let .importMedia(request):
    return request.isEmpty == false
case .addTextItem:
    return session.canAddTextItem
case .addHandDrawingItem:
    return session.canAddHandDrawingItem
case let .beginTextEdit(itemID):
    return session.canBeginTextEdit(withID: itemID)
// 其余分支省略
}

case let .addHandDrawingItem(paper):
    guard let addedHandDrawingItem = session.addHandDrawingItem(paper: paper) else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "add hand drawing item \(addedHandDrawingItem.id.uuidString)",
        followUp: .presentHandDrawingEditor(
            itemID: addedHandDrawingItem.id
        )
    )
```

## 修改二：共享编辑契约与 session 回写链补齐 handDrawing API

### 修改前

- 项目里还没有 `CanvasHandDrawingEditing.swift` 这类 handDrawing 编辑契约文件。
- `CanvasEditorSession` 只有 text / video / GIF 相关编辑接口，没有 handDrawing 的 `editorContext`、`commit`、`canEdit`、`add`。
- 新建 handDrawing 时也没有统一的“透明 preview + drawingData + transient payload”准备步骤。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: canAddTextItem / videoEditorContext(for:) / addTextItem(text:style:)
// 功能说明: 修改前 session 只有 text 与 video 相关编辑入口，没有 handDrawing 的独立新增、上下文与提交 API。
var canAddTextItem: Bool {
    inlineEditState == nil
}

func videoEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasVideoEditorContext {
    guard let activeBoardID else {
        throw CanvasVideoFrameServiceError.missingBoardIdentity
    }
    // 其余实现省略
}

@discardableResult
func addTextItem(
    text: String = "Text",
    style: CanvasTextStyle = .default
) -> CanvasTextItem? {
    guard canAddTextItem else {
        return nil
    }
    // 其余实现省略
}
```

### 修改后

- 新增 `CanvasHandDrawingEditing.swift`，统一收口：
  - `CanvasHandDrawingEditingError`
  - `CanvasHandDrawingEditorContext`
  - `CanvasHandDrawingEditSubmission`
  - `CanvasHandDrawingEditCommitResult`
  - `CanvasHandDrawingPreviewAssetFactory`
- `CanvasEditorSession` 新增：
  - `canAddHandDrawingItem`
  - `selectedHandDrawingItem`
  - `canEditSelectedHandDrawing`
  - `canEditHandDrawing(withID:)`
  - `handDrawingEditorContext(for:)`
  - `commitHandDrawingEdit(withID:submission:)`
  - `addHandDrawingItem(paper:)`
- 新建 handDrawing 时会立即创建透明 preview、注册 transient payload、更新选区并记录一条 board history。
- 提交编辑时会更新 `previewAsset`、`isEmpty`、`contentRevision`，并把 `drawingData + previewCGImage` 回写到 transient payload，后续交给保存链落盘。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditingError / CanvasHandDrawingEditorContext / CanvasHandDrawingEditSubmission / CanvasHandDrawingPreviewAssetFactory.makeTransparentPreview(for:)
// 功能说明: 修改后新增 handDrawing 编辑共享契约，iOS 编辑器与 session 之间不再直接传裸字段。
enum CanvasHandDrawingEditingError: LocalizedError {
    case invalidHandDrawingItem(itemID: CanvasItemID)
    case missingBoardIdentity
    case missingSourceDrawing(itemID: CanvasItemID)
    case failedToCreateBlankPreview(paperID: String)
}

struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let paper: CanvasHandDrawingPaperSpec
    let drawingData: Data
    let isEmpty: Bool
}

struct CanvasHandDrawingEditSubmission {
    let drawingData: Data
    let previewCGImage: CGImage
    let isEmpty: Bool
    let contentRevision: UUID
}

enum CanvasHandDrawingPreviewAssetFactory {
    static func makeTransparentPreview(
        for paper: CanvasHandDrawingPaperSpec
    ) throws -> CGImage {
        let width = max(Int(paper.size.width.rounded(.up)), 1)
        let height = max(Int(paper.size.height.rounded(.up)), 1)
        // 其余实现省略
        return image
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:) / addHandDrawingItem(paper:)
// 功能说明: 修改后 session 负责 handDrawing 的上下文组装、提交回写、transient 资产注册与单条历史记录。
func handDrawingEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasHandDrawingEditorContext {
    guard let item = scene.handDrawingItem(withID: itemID) else {
        throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
            itemID: itemID
        )
    }

    if let payload = transientHandDrawingAssetPayload(for: itemID) {
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            paper: item.paper,
            drawingData: payload.drawingData,
            isEmpty: item.isEmpty
        )
    }

    guard let activeBoardID else {
        throw CanvasHandDrawingEditingError.missingBoardIdentity
    }

    return CanvasHandDrawingEditorContext(
        itemID: itemID,
        paper: item.paper,
        drawingData: try BoardStore.loadHandDrawingSourceData(
            boardID: activeBoardID,
            itemID: itemID,
            userDefaults: userDefaults
        ),
        isEmpty: item.isEmpty
    )
}

@discardableResult
func commitHandDrawingEdit(
    withID itemID: CanvasItemID,
    submission: CanvasHandDrawingEditSubmission
) throws -> CanvasHandDrawingEditCommitResult? {
    guard var item = scene.handDrawingItem(withID: itemID) else {
        throw CanvasHandDrawingEditingError.invalidHandDrawingItem(
            itemID: itemID
        )
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    item.previewAsset = CanvasHandDrawingItem.persistedPreviewAsset(
        for: item.id,
        cgImage: submission.previewCGImage,
        logicalPixelSize: item.paper.size
    )
    item.isEmpty = submission.isEmpty
    item.contentRevision = submission.contentRevision
    scene.upsert(item)
    transientHandDrawingAssetPayloads[itemID] =
        BoardTransientHandDrawingAssetPayload(
            itemID: itemID,
            drawingData: submission.drawingData,
            previewCGImage: submission.previewCGImage
        )
    let changeReason = "commit hand drawing edit"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return CanvasHandDrawingEditCommitResult(
        item: item,
        refreshReason: changeReason
    )
}

@discardableResult
func addHandDrawingItem(
    paper: CanvasHandDrawingPaperSpec = .square
) -> CanvasHandDrawingItem? {
    guard canAddHandDrawingItem else {
        return nil
    }

    let beforeSnapshot = currentBoardHistorySnapshot()
    guard
        let previewImage = try? CanvasHandDrawingPreviewAssetFactory
            .makeTransparentPreview(for: paper)
    else {
        return nil
    }

    let itemID = CanvasItemID()
    let item = CanvasHandDrawingItem(
        id: itemID,
        paper: paper,
        previewAsset: CanvasHandDrawingItem.persistedPreviewAsset(
            for: itemID,
            cgImage: previewImage,
            logicalPixelSize: paper.size
        ),
        isEmpty: true,
        center: camera.center,
        size: normalizedDisplaySize(for: paper.size),
        zIndex: nextBoardItemZIndex()
    )
    scene.append(item)
    transientHandDrawingAssetPayloads[item.id] =
        BoardTransientHandDrawingAssetPayload(
            itemID: item.id,
            drawingData: Data(),
            previewCGImage: previewImage
        )
    _ = replaceSelection(with: [item.id], primarySelectedItemID: item.id)
    let changeReason = "add hand drawing item"
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: changeReason,
        autosaveReason: changeReason
    )
    return item
}
```

## 修改三：iOS 新增全屏 PencilKit 编辑器，并把新增 / 再次编辑都接到同一回写链路

### 修改前

- `iOSViewController` 的 context menu UI action 只有 `editVideoDisplayFrame` 和 `importGIFFrames`。
- toolbar 初始化里没有 handDrawing button，也没有 `handleHandDrawingButtonTap()`。
- 项目中不存在 iOS 全屏 handDrawing editor controller，手绘块无法通过 `PKCanvasView` 进入专用编辑模式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: performContextMenuUIAction(_:context:) / viewDidLoad() / handleTextButtonTap()
// 功能说明: 修改前 iOS controller 只接了 video/GIF 的外部编辑器，没有 handDrawing 入口。
private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }
        presentVideoDisplayFrameEditor(for: itemID)
    case .importGIFFrames:
        guard let itemID = targetGIFItemID(for: context) else {
            return
        }
        presentGIFFrameImportEditor(for: itemID)
    }
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupCropButton()
    setupMultiSelectButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    // handDrawing button 不存在
}

@objc
private func handleTextButtonTap() {
    if isInlineTextModeActive {
        performCommand(.commitTextEdit)
    } else {
        performCommand(.addTextItem)
    }
}
```

### 修改后

- `iOSViewController` 增加 `handDrawingButton`、`supportsHandDrawingEditing`、`handleCommandFollowUp(_:)`、`presentHandDrawingEditor(for:)`、`handleHandDrawingButtonTap()`。
- 创建 handDrawing 后，controller 会从 `CanvasCommandExecutionResult.followUp` 收到 `presentHandDrawingEditor`，不再绕开 command lane。
- 单选中的 handDrawing 可以直接再次编辑；未选中时点击工具栏会先新建再立即进入编辑器。
- 新增 `iOSHandDrawingEditorViewController`，内部使用 `PKCanvasView` + `PKToolPicker`，并设置 `drawingPolicy = .pencilOnly`。
- 退出编辑器时，如果内容变化，则生成 `CanvasHandDrawingEditSubmission` 并提交到 session；如果没有变化，则直接 dismiss。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handleCommandFollowUp(_:) / performContextMenuUIAction(_:context:) / presentHandDrawingEditor(for:) / handleHandDrawingButtonTap()
// 功能说明: 修改后 iOS controller 统一从 follow-up、toolbar、context menu 三条入口拉起 handDrawing editor，并把提交结果回写 session。
private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case let .presentHandDrawingEditor(itemID):
        guard supportsHandDrawingEditing else {
            return
        }
        presentHandDrawingEditor(for: itemID)
    }
}

private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editHandDrawing:
        guard let itemID = targetHandDrawingItemID(for: context) else {
            return
        }
        presentHandDrawingEditor(for: itemID)
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }
        presentVideoDisplayFrameEditor(for: itemID)
    case .importGIFFrames:
        guard let itemID = targetGIFItemID(for: context) else {
            return
        }
        presentGIFFrameImportEditor(for: itemID)
    }
}

private func presentHandDrawingEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    cancelRotationInteractionIfNeeded(resetPointerDragState: true)

    let editorContext = try editorSession.handDrawingEditorContext(for: itemID)
    let editorViewController = try iOSHandDrawingEditorViewController(
        editorContext: editorContext
    ) { [weak self] submission in
        guard let self else { return }

        if let updateResult = try self.editorSession.commitHandDrawingEdit(
            withID: itemID,
            submission: submission
        ) {
            self.requestCanvasRefresh(reason: updateResult.refreshReason)
        }
    }
    present(editorViewController, animated: true)
}

@objc
private func handleHandDrawingButtonTap() {
    if let itemID = editorSession.singleSelectedItemID,
       editorSession.canEditHandDrawing(withID: itemID)
    {
        presentHandDrawingEditor(for: itemID)
        return
    }

    performCommand(.addHandDrawingItem(paper: .square))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: configureCanvasView() / finishEditingAndDismiss() / makePreviewCGImage(for:isEmpty:)
// 功能说明: 修改后新增 iOS 全屏 PencilKit 编辑器，进入时加载 PKDrawing，退出时回传 drawingData 与 previewCGImage。
final class iOSHandDrawingEditorViewController: UIViewController, PKCanvasViewDelegate {
    private let editorContext: CanvasHandDrawingEditorContext
    private let onCommitSubmission: (CanvasHandDrawingEditSubmission) throws -> Void
    private let initialDrawing: PKDrawing
    private let toolPicker = PKToolPicker()
    private let canvasView: PKCanvasView = {
        let view = PKCanvasView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = true
        view.bouncesZoom = true
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()

    private func configureCanvasView() {
        canvasView.delegate = self
        canvasView.drawing = initialDrawing
        canvasView.drawingPolicy = .pencilOnly
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 6)
        canvasView.contentSize = editorContext.paper.size
    }

    private func finishEditingAndDismiss() {
        let drawing = canvasView.drawing
        let isEmpty = drawing.strokes.isEmpty
        if shouldCommit(drawing: drawing, isEmpty: isEmpty) {
            let drawingData = drawing.dataRepresentation()
            let previewCGImage = try makePreviewCGImage(
                for: drawing,
                isEmpty: isEmpty
            )
            try onCommitSubmission(
                CanvasHandDrawingEditSubmission(
                    drawingData: drawingData,
                    previewCGImage: previewCGImage,
                    isEmpty: isEmpty,
                    contentRevision: UUID()
                )
            )
        }
        dismiss(animated: true)
    }

    private func makePreviewCGImage(
        for drawing: PKDrawing,
        isEmpty: Bool
    ) throws -> CGImage {
        if isEmpty {
            return try CanvasHandDrawingPreviewAssetFactory.makeTransparentPreview(
                for: editorContext.paper
            )
        }

        let paperBounds = CGRect(origin: .zero, size: editorContext.paper.size)
        let previewImage = drawing.image(from: paperBounds, scale: 1)
        if let cgImage = previewImage.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: editorContext.paper.size,
            format: format
        )
        let rasterizedImage = renderer.image { _ in
            previewImage.draw(at: .zero)
        }
        guard let cgImage = rasterizedImage.cgImage else {
            throw iOSHandDrawingEditorFlowError.failedToRenderPreview(
                itemID: editorContext.itemID
            )
        }
        return cgImage
    }
}
```

## 修改四：toolbar / context menu 与平台能力判定接入 handDrawing

### 修改前

- `CanvasToolbarItemID` 没有 `handDrawing`。
- `CanvasToolbarStateBuilder` 没有 `supportsHandDrawingEditing`，也没有 `handDrawingItemState(session:)`。
- crop 按钮显示逻辑是 `selectedBoardItemKind != .text`，这会把 handDrawing 也误算进“可裁剪”。
- `CanvasContextMenuUIActionID` 没有 `editHandDrawing`，resolver 也没有 handDrawing 目标判定。
- `CanvasCommandCatalog` 没有 `addHandDrawingItem` descriptor。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名: CanvasToolbarItemID
// 功能说明: 修改前 toolbar item id 没有 handDrawing。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case save
    case text
    case importMedia
    case undo
    case redo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(session:saveState:placement:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:) / shouldShowCropItem(session:)
// 功能说明: 修改前 builder 不支持 handDrawing 入口，而且 crop 只排除了 text。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))
    return CanvasToolbarState(placement: placement, items: itemStates, showsBackground: showsBackground)
}

private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
    guard session.isInlineCropModeActive == false else {
        return true
    }

    return session.selectedBoardItemKind != .text
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名: CanvasContextMenuUIActionID
// 功能说明: 修改前 context menu UI action id 没有 editHandDrawing。
enum CanvasContextMenuUIActionID: String {
    case editVideoDisplayFrame
    case importGIFFrames
}
```

### 修改后

- `CanvasToolbarItemID` 新增 `.handDrawing`。
- `CanvasCommandCatalog` 新增 `addHandDrawingItem` descriptor，供 toolbar 使用。
- `CanvasToolbarStateBuilder.mainToolbarState(...)` 新增 `supportsHandDrawingEditing` 参数，并接入 `handDrawingItemState(session:)`。
- crop 判断收紧为 `selectedBoardItemKind == .image`，避免 handDrawing 误显示 image-only 操作。
- `CanvasContextMenuUIActionID` 新增 `.editHandDrawing`，resolver 增加 `supportsHandDrawingEditing` 参数与 `targetHandDrawingItemID(...)`。
- `iOSCanvasToolbarHostView` 把 `.handDrawing` 纳入 symbol configuration。
- `macOSViewController` 显式把 `supportsHandDrawingEditing` 固定为 `false`，即便共享链路已经识别 handDrawing，也不会在 macOS 上暴露编辑入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名: descriptor(for:session:context:)
// 功能说明: 修改后 catalog 能为 toolbar / context menu 提供 addHandDrawingItem 的 UI 描述。
case .addHandDrawingItem:
    descriptor = CanvasCommandDescriptor(
        id: .addHandDrawingItem,
        title: "Add Hand Drawing",
        systemImageName: "scribble",
        isEnabled: session.canAddHandDrawingItem,
        isActive: false
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名: mainToolbarState(session:saveState:placement:supportsHandDrawingEditing:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:) / handDrawingItemState(session:) / shouldShowCropItem(session:)
// 功能说明: 修改后 toolbar 能按平台能力暴露 handDrawing 入口，且单选 handDrawing 时切换为“编辑手绘”。
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
    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    if supportsHandDrawingEditing {
        itemStates.append(handDrawingItemState(session: session))
    }
    itemStates.append(importItemState(isEnabled: isImportEnabled))
    return CanvasToolbarState(placement: placement, items: itemStates, showsBackground: showsBackground)
}

func handDrawingItemState(
    session: CanvasEditorSession
) -> CanvasToolbarItemState {
    if session.canEditSelectedHandDrawing {
        return CanvasToolbarItemState(
            id: .handDrawing,
            systemImageName: "pencil.and.scribble",
            accessibilityLabel: "Edit hand drawing",
            visualRole: .accent
        )
    }

    let descriptor = commandCatalog.descriptor(
        for: .addHandDrawingItem,
        session: session
    )
    return CanvasToolbarItemState(
        id: .handDrawing,
        systemImageName: descriptor.systemImageName,
        isEnabled: descriptor.isEnabled,
        isActive: descriptor.isActive,
        accessibilityLabel: "Add hand drawing",
        visualRole: .accent
    )
}

private func shouldShowCropItem(session: CanvasEditorSession) -> Bool {
    guard session.isInlineCropModeActive == false else {
        return true
    }

    guard let selectedBoardItemKind = session.selectedBoardItemKind else {
        return true
    }

    return selectedBoardItemKind == .image
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名: CanvasContextMenuUIActionID
// 功能说明: 修改后 context menu UI action id 增加 editHandDrawing。
enum CanvasContextMenuUIActionID: String {
    case editHandDrawing
    case editVideoDisplayFrame
    case importGIFFrames
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: actionStates(for:session:environment:supportsHandDrawingEditing:) / uiActionDescriptor(for:context:session:supportsHandDrawingEditing:) / targetHandDrawingItemID(in:session:)
// 功能说明: 修改后 resolver 只在支持编辑的平台和单个 handDrawing 上注入 editHandDrawing。
func actionStates(
    for context: CanvasContextMenuContext,
    session: CanvasEditorSession,
    environment: CanvasInteractionEnvironment? = nil,
    supportsHandDrawingEditing: Bool = false
) -> [CanvasContextMenuActionState] {
    let candidateActionIDs = candidateActionIDs(
        for: context,
        session: session,
        supportsHandDrawingEditing: supportsHandDrawingEditing
    )
    // 其余实现省略
}

private func uiActionDescriptor(
    for uiActionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext,
    session: CanvasEditorSession,
    supportsHandDrawingEditing: Bool
) -> CanvasContextMenuActionDescriptor {
    switch uiActionID {
    case .editHandDrawing:
        return CanvasContextMenuActionDescriptor(
            title: "Edit Hand Drawing",
            systemImageName: "scribble",
            isEnabled: supportsHandDrawingEditing && targetHandDrawingItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    case .editVideoDisplayFrame:
        return CanvasContextMenuActionDescriptor(
            title: "Set Display Frame",
            systemImageName: "movieclapper",
            isEnabled: targetVideoItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    case .importGIFFrames:
        return CanvasContextMenuActionDescriptor(
            title: "Import GIF Frames",
            systemImageName: "square.grid.3x3",
            isEnabled: targetGIFItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    }
}

private func targetHandDrawingItemID(
    in context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> CanvasItemID? {
    guard let itemID = context.singleEffectiveItemID else {
        return nil
    }

    return session.canEditHandDrawing(withID: itemID)
        ? itemID
        : nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: symbolConfiguration(for:)
// 功能说明: 修改后 iOS toolbar host 会为 handDrawing 按钮复用和 crop/text 相同的符号配置。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .crop, .multiSelect, .text, .handDrawing:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: supportsHandDrawingEditing / handleCommandFollowUp(_:) / performContextMenuUIAction(_:context:)
// 功能说明: 修改后 macOS 明确保持“不支持 handDrawing 编辑”，共享 follow-up 和 context menu case 只做穷举收口。
private var supportsHandDrawingEditing: Bool {
    false
}

private func handleCommandFollowUp(_ followUp: CanvasCommandFollowUp) {
    switch followUp {
    case .presentHandDrawingEditor:
        return
    }
}

private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editHandDrawing:
        return
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }
        presentVideoDisplayFrameEditor(for: itemID)
    case .importGIFFrames:
        guard let itemID = targetGIFItemID(for: context) else {
            return
        }
        presentGIFFrameImportEditor(for: itemID)
    }
}
```

## 修改五：阶段 5 测试补齐 handDrawing command / toolbar / context menu / session commit

### 修改前

- 阶段 5 相关测试尚不存在：
  - `CanvasCommandPolicyParityTests` 没有 handDrawing command parity 和 follow-up 断言。
  - `CanvasContextMenuActionResolverTests` 没有 handDrawing edit action 的注入条件验证。
  - `CanvasToolbarStateBuilderTests` 没有 handDrawing toolbar item 与 crop 隐藏验证。
  - 项目里没有 `CanvasHandDrawingEditingSessionTests.swift`。

### 修改后

- `CanvasCommandPolicyParityTests` 新增：
  - 编辑模式 / 阅读模式下的 `addHandDrawingItem` parity
  - add command 的 follow-up 与 transient payload 断言
- `CanvasContextMenuActionResolverTests` 新增：
  - 支持编辑的平台会注入 `editHandDrawing`
  - 不支持编辑的平台不会注入
- `CanvasToolbarStateBuilderTests` 新增：
  - handDrawing toolbar item 进入主工具栏
  - 单选 handDrawing 时按钮切换成 `Edit hand drawing`
  - handDrawing 选中时不再显示 crop
- 新增 `CanvasHandDrawingEditingSessionTests.swift`，验证提交编辑后：
  - `isEmpty`、`contentRevision` 更新
  - transient payload 写入
  - undo / redo 能正确回放 handDrawing commit

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddHandDrawingDescriptorAndExecutorMatchPolicyInEditingMode() / testAddHandDrawingDescriptorAndExecutorMatchPolicyInReadingMode() / testAddHandDrawingCommandProducesFollowUpAndTransientPayload()
// 功能说明: 修改后补齐 handDrawing command lane 的 policy parity 与 follow-up 断言。
func testAddHandDrawingDescriptorAndExecutorMatchPolicyInEditingMode() {
    let descriptor = commandCatalog.descriptor(
        for: .addHandDrawingItem,
        session: session
    )
    let decision = policy.commandDecision(
        for: .addHandDrawingItem,
        workspaceMode: session.workspaceMode
    )

    XCTAssertEqual(decision, .allow)
    XCTAssertTrue(descriptor.isEnabled)
    XCTAssertTrue(executor.canExecute(.addHandDrawingItem(paper: .square)))
}

func testAddHandDrawingDescriptorAndExecutorMatchPolicyInReadingMode() {
    let descriptor = commandCatalog.descriptor(
        for: .addHandDrawingItem,
        session: session
    )
    let decision = policy.commandDecision(
        for: .addHandDrawingItem,
        workspaceMode: session.workspaceMode
    )

    XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    XCTAssertFalse(descriptor.isEnabled)
    XCTAssertFalse(executor.canExecute(.addHandDrawingItem(paper: .square)))
}

func testAddHandDrawingCommandProducesFollowUpAndTransientPayload() throws {
    let result = try XCTUnwrap(
        executor.execute(.addHandDrawingItem(paper: .square))
    )
    guard case let .presentHandDrawingEditor(itemID)? = result.followUp else {
        XCTFail("Expected addHandDrawingItem to request editor follow-up.")
        return
    }

    let addedItem = try XCTUnwrap(
        session.scene.handDrawingItem(withID: itemID)
    )
    XCTAssertTrue(addedItem.isEmpty)
    XCTAssertEqual(session.singleSelectedItemID, itemID)
    XCTAssertNotNil(session.transientHandDrawingAssetPayload(for: itemID))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 函数名: testSelectedHandDrawingIncludesEditActionWhenSupported() / testSelectedHandDrawingHidesEditActionWhenUnsupported()
// 功能说明: 修改后验证 context menu 只在支持 handDrawing 编辑的平台暴露 editHandDrawing。
func testSelectedHandDrawingIncludesEditActionWhenSupported() throws {
    let handDrawingItem = try makeContextMenuActionResolverTestHandDrawingItem()
    session.scene.append(handDrawingItem)

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: handDrawingItem.id,
            selectedItemID: handDrawingItem.id
        ),
        session: session,
        supportsHandDrawingEditing: true
    )

    XCTAssertTrue(actionStates.contains(where: isEditHandDrawingAction))
}

func testSelectedHandDrawingHidesEditActionWhenUnsupported() throws {
    let handDrawingItem = try makeContextMenuActionResolverTestHandDrawingItem()
    session.scene.append(handDrawingItem)

    let actionStates = CanvasContextMenuActionResolver().actionStates(
        for: makeContextMenuContext(
            targetKind: .selectedItemBody,
            targetItemID: handDrawingItem.id,
            selectedItemID: handDrawingItem.id
        ),
        session: session
    )

    XCTAssertFalse(actionStates.contains(where: isEditHandDrawingAction))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数名: testMainToolbarStateIncludesHandDrawingItemWhenSupported() / testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop()
// 功能说明: 修改后验证 handDrawing 按钮会进入工具栏，并在单选 handDrawing 时切换到“编辑手绘”语义。
func testMainToolbarStateIncludesHandDrawingItemWhenSupported() {
    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        supportsHandDrawingEditing: true,
        includesHistoryItems: true
    )

    XCTAssertEqual(
        state.items.map(\.id),
        [.undo, .redo, .crop, .multiSelect, .save, .text, .handDrawing, .importMedia]
    )
}

func testSelectedHandDrawingShowsEditToolbarItemAndHidesCrop() throws {
    let handDrawingItem = try makeToolbarStateBuilderTestHandDrawingItem()
    session.scene.append(handDrawingItem)
    session.interactionState = CanvasInteractionState(
        selectedItemID: handDrawingItem.id
    )

    let state = builder.mainToolbarState(
        session: session,
        saveState: .idle,
        placement: CanvasToolbarPlacement(preferredEdge: .trailing),
        supportsHandDrawingEditing: true
    )

    let handDrawingToolbarItem = try XCTUnwrap(
        state.items.first(where: { $0.id == .handDrawing })
    )
    XCTAssertEqual(handDrawingToolbarItem.accessibilityLabel, "Edit hand drawing")
    XCTAssertEqual(handDrawingToolbarItem.systemImageName, "pencil.and.scribble")
    XCTAssertFalse(state.items.contains(where: { $0.id == .crop }))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo()
// 功能说明: 修改后新增 session 级 handDrawing commit 测试，验证 preview / revision / undo / redo 一起生效。
func testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo() throws {
    let session = makeHandDrawingEditingTestSession()
    let item = try XCTUnwrap(session.addHandDrawingItem(paper: .square))
    let originalRevision = item.contentRevision
    session.resetHistory()

    let previewImage = try makeHandDrawingEditingTestImage(
        red: 0.2,
        green: 0.3,
        blue: 0.9
    )
    let updatedRevision = UUID()
    let result = try XCTUnwrap(
        session.commitHandDrawingEdit(
            withID: item.id,
            submission: CanvasHandDrawingEditSubmission(
                drawingData: Data("ink".utf8),
                previewCGImage: previewImage,
                isEmpty: false,
                contentRevision: updatedRevision
            )
        )
    )

    XCTAssertEqual(result.refreshReason, "commit hand drawing edit")
    let updatedItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
    XCTAssertFalse(updatedItem.isEmpty)
    XCTAssertEqual(updatedItem.contentRevision, updatedRevision)
    XCTAssertNotNil(session.transientHandDrawingAssetPayload(for: item.id))

    let undoSnapshot = try XCTUnwrap(session.undoHistorySnapshot())
    session.applyBoardHistorySnapshot(undoSnapshot)
    let undoneItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
    XCTAssertTrue(undoneItem.isEmpty)
    XCTAssertEqual(undoneItem.contentRevision, originalRevision)

    let redoSnapshot = try XCTUnwrap(session.redoHistorySnapshot())
    session.applyBoardHistorySnapshot(redoSnapshot)
    let redoneItem = try XCTUnwrap(session.scene.handDrawingItem(withID: item.id))
    XCTAssertFalse(redoneItem.isEmpty)
    XCTAssertEqual(redoneItem.contentRevision, updatedRevision)
}
```

## 结果小结

- 阶段 5 已把 handDrawing 的“新增 -> 立即进入 iOS 全屏编辑 -> 提交回写 -> 主画布刷新”主链打通。
- 新增与再次编辑都没有绕过 session / command lane，follow-up、asset payload、history、autosave 仍然走共享链路。
- macOS 当前只做能力收口，不暴露 handDrawing 编辑入口，符合“macOS 暂不做编辑”的阶段目标。
