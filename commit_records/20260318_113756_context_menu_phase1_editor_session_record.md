# 20260318_113756_context_menu_phase1_editor_session_record

## 记录范围

- 记录内容：
  1. 新增共享编辑底座 `CanvasEditorSession`，集中承载 `scene`、`camera`、`boardState`、`interactionState`、`inlineEditState`、`rotationPreviewState`、`rotationInteractionState`、`lastRenderSnapshot`、history、save 等共享编辑运行时。
  2. 让 `iOS/macOS ViewController` 不再直接持有这批共享状态与服务，改为通过 `editorSession` 统一访问。
  3. 将共享的 canvas/minimap 渲染、历史提交、持久化保存、导入图片落盘前的会话写入逻辑收口到 session。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - `CanvasCommandCatalog` / `CanvasCommandExecutor`
  - `CanvasContextResolver`
  - `CanvasContextMenuState` / `CanvasContextMenuHostView`
  - `pointerDragState` 与命中测试状态机迁移
  - 原始 gif diff

## 修改一：新增共享编辑底座 `CanvasEditorSession`

### 修改前

- 项目里没有共享的编辑会话层。
- `iOS/macOS ViewController` 各自维护一套几乎相同的编辑运行时、渲染器、历史控制器与保存协调器。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前项目里没有共享编辑会话层，平台 controller 直接持有共享编辑状态与副作用服务。
// before: file did not exist
```

### 修改后

- 新增 `CanvasEditorSession`，把共享编辑运行时与共享副作用服务集中到 `Canvas/Editing`。
- session 提供：
  - canvas snapshot 生成
  - minimap snapshot 生成
  - board runtime 恢复与构造
  - history 提交 / undo / redo
  - autosave / save now
  - 导入图片后的文档写入

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: CanvasEditorSession / makeCanvasSnapshot() / makeMiniMapSnapshot()
// 功能说明: 修改后新增共享编辑会话，统一持有画布运行时，并集中产出 canvas/minimap snapshot。
import CoreGraphics
import Foundation

final class CanvasEditorSession {
    let scene = CanvasScene()
    var camera = CanvasCamera()
    var boardState: CanvasBoardState?
    var interactionState = CanvasInteractionState()
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?

    private(set) var lastRenderSnapshot: CanvasRenderSnapshot = .empty
    private(set) var activeBoardID: UUID?
    private(set) var activeBoardCreatedAt: Date?
    var activeBoardTitle = BoardDocument.defaultTitle

    private let renderer = CanvasRenderer()
    private let miniMapRenderer = CanvasMiniMapRenderer()
    private let saveCoordinator: BoardSaveCoordinator
    private let historyController = BoardHistoryController()

    func makeCanvasSnapshot() -> CanvasRenderSnapshot {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: interactionState,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState,
            rotationInteractionState: rotationInteractionState
        )
        lastRenderSnapshot = snapshot
        return snapshot
    }

    func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
        miniMapRenderer.makeSnapshot(
            context: CanvasMiniMapRenderContext(
                scene: scene,
                boardState: boardState,
                camera: camera,
                imageInlineEditState: inlineEditState,
                imageRotationPreviewState: rotationPreviewState
            )
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/类型名: restorePersistedBoardIfPossible() / saveBoardNow(...) / appendImportedImage(_:)
// 功能说明: 修改后 session 同时统一了文档恢复、持久化保存、导入图片后的文档写入与历史提交入口。
func restorePersistedBoardIfPossible() {
    do {
        let runtimeState = try BoardStore.loadOrCreateInitialBoard()
        applyBoardRuntimeState(runtimeState)
        resetHistory()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("\(boardStoreLogPrefix) Failed to restore board: \(error)")
    }
}

func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    guard let snapshot = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
        return
    }

    saveCoordinator.saveImmediately(
        snapshot: snapshot,
        reason: reason,
        completion: completion
    )
}

@discardableResult
func appendImportedImage(_ cgImage: CGImage) -> CanvasImageItem {
    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    _ = recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "append image",
        autosaveReason: "append image"
    )
    return item
}
```

## 修改二：iOS controller 不再直接持有共享编辑运行时

### 修改前

- `iOSViewController` 自己持有共享的 scene/camera/renderer/minimap/history/save/runtime state。
- 平台层和编辑器运行时是强耦合的。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController 成员区
// 功能说明: 修改前 iOS controller 直接持有共享编辑状态、渲染器、保存器和历史控制器，平台 UI 层与编辑器运行时没有边界。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let scene = CanvasScene()
private var camera = CanvasCamera()
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let canvasViewportView = iOSCanvasViewportView()
private var canvasContentView: UIView?
private var pendingRefreshReason: String?
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var inlineEditState: CanvasInlineEditState?
private var rotationPreviewState: CanvasRotationPreviewState?
private var rotationInteractionState: CanvasRotationInteractionState?
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
private var pointerDragState: PointerDragState = .idle
private var activeBoardID: UUID?
private var activeBoardTitle = BoardDocument.defaultTitle
private var activeBoardCreatedAt: Date?
private let saveCoordinator = BoardSaveCoordinator(
    queueLabel: "MyCanvas.BoardSave.iOS",
    logPrefix: "[BoardStore][iOS]"
)
private let historyController = BoardHistoryController()
```

### 修改后

- `iOSViewController` 只保留平台视图层、平台按钮与 `pointerDragState`。
- 共享状态改为统一通过 `editorSession` 代理访问。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.editorSession / iOSViewController.scene / iOSViewController.camera / iOSViewController.boardState
// 功能说明: 修改后 iOS controller 通过 editorSession 统一访问共享编辑状态，平台层只保留原生 UI 和平台状态机。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.iOS",
    logPrefix: "[BoardStore][iOS]"
)
private let canvasViewportView = iOSCanvasViewportView()
private var canvasContentView: UIView?
private var pendingRefreshReason: String?
private var pointerDragState: PointerDragState = .idle
private var saveButtonResetWorkItem: DispatchWorkItem?

private var scene: CanvasScene {
    editorSession.scene
}

private var camera: CanvasCamera {
    get { editorSession.camera }
    set { editorSession.camera = newValue }
}

private var boardState: CanvasBoardState? {
    get { editorSession.boardState }
    set { editorSession.boardState = newValue }
}

private var interactionState: CanvasInteractionState {
    get { editorSession.interactionState }
    set { editorSession.interactionState = newValue }
}

private var inlineEditState: CanvasInlineEditState? {
    get { editorSession.inlineEditState }
    set { editorSession.inlineEditState = newValue }
}

private var rotationPreviewState: CanvasRotationPreviewState? {
    get { editorSession.rotationPreviewState }
    set { editorSession.rotationPreviewState = newValue }
}

private var rotationInteractionState: CanvasRotationInteractionState? {
    get { editorSession.rotationInteractionState }
    set { editorSession.rotationInteractionState = newValue }
}

private var lastRenderSnapshot: CanvasRenderSnapshot {
    editorSession.lastRenderSnapshot
}
```

## 修改三：iOS controller 的共享刷新 / history / 保存 / 导入逻辑改为委托 session

### 修改前

- `performCanvasRefresh(reason:)` 和 `refreshMiniMap()` 直接在 controller 里组装 snapshot。
- `performUndoCommand()`、`performRedoCommand()`、`saveBoardNow(...)`、`appendImportedImage(_:)` 都直接依赖 controller 本地的共享状态与副作用服务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: performCanvasRefresh(reason:) / refreshMiniMap() / performUndoCommand() / saveBoardNow(...) / appendImportedImage(_:)
// 功能说明: 修改前这些共享编辑入口都直接写在 iOS controller 中，controller 同时承担平台 UI 和编辑器运行时职责。
private func performCanvasRefresh(reason: String) {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
    logCanvasState(reason: reason, snapshot: snapshot)
}

private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
    miniMapView.apply(snapshot)
}

private func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = historyController.undo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
    updateHistoryButtonsAppearance()
}

private func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    guard let snapshot = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
        return
    }

    saveCoordinator.saveImmediately(
        snapshot: snapshot,
        reason: reason,
        completion: completion
    )
}

private func appendImportedImage(_ cgImage: CGImage) {
    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    requestCanvasRefresh(
        reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
    )
    recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "append image",
        autosaveReason: "append image"
    )
}
```

### 修改后

- controller 仍保留平台 UI 反馈与日志，但共享编辑能力都改为委托 `editorSession`。
- 这样为后续阶段的 command layer 和 context resolver 继续抽离打下边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: performCanvasRefresh(reason:) / refreshMiniMap() / performUndoCommand() / saveBoardNow(...) / appendImportedImage(_:)
// 功能说明: 修改后 iOS controller 只负责平台级 UI 反馈、日志与视图应用，真正的共享编辑逻辑统一委托给 editorSession。
private func performCanvasRefresh(reason: String) {
    let snapshot = editorSession.makeCanvasSnapshot()
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
    logCanvasState(reason: reason, snapshot: snapshot)
}

private func refreshMiniMap() {
    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}

private func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = editorSession.undoHistorySnapshot()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
    updateHistoryButtonsAppearance()
}

private func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    editorSession.saveBoardNow(
        reason: reason,
        createBoardIfNeeded: createBoardIfNeeded,
        completion: completion
    )
}

private func appendImportedImage(_ cgImage: CGImage) {
    let item = editorSession.appendImportedImage(cgImage)
    requestCanvasRefresh(
        reason: "append image size=\(describe(size: item.size)) center=\(describe(point: item.center))"
    )
    updateHistoryButtonsAppearance()
}
```

## 修改四：macOS controller 同步改为持有 `editorSession`

### 修改前

- `macOSViewController` 和 iOS 一样，也直接持有 scene/camera/renderer/minimap/history/save/runtime state。
- 两端平台只是 UI 不同，但共享编辑运行时被复制维护了两份。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController 成员区
// 功能说明: 修改前 macOS controller 与 iOS controller 一样，直接持有共享编辑运行时和副作用服务。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let scene = CanvasScene()
private var camera = CanvasCamera()
private let renderer = CanvasRenderer()
private let miniMapRenderer = CanvasMiniMapRenderer()
private let canvasViewportView = macOSCanvasViewportView()
private var canvasContentView: NSView?
private var boardState: CanvasBoardState?
private var interactionState = CanvasInteractionState()
private var inlineEditState: CanvasInlineEditState?
private var rotationPreviewState: CanvasRotationPreviewState?
private var rotationInteractionState: CanvasRotationInteractionState?
private var lastRenderSnapshot: CanvasRenderSnapshot = .empty
private var pointerDragState: PointerDragState = .idle
private var activeBoardID: UUID?
private var activeBoardTitle = BoardDocument.defaultTitle
private var activeBoardCreatedAt: Date?
private let saveCoordinator = BoardSaveCoordinator(
    queueLabel: "MyCanvas.BoardSave.macOS",
    logPrefix: "[BoardStore][macOS]"
)
private let historyController = BoardHistoryController()
```

### 修改后

- `macOSViewController` 和 iOS 保持同样的结构：平台 UI 层 + session 代理。
- 这样后续 command layer 才能在两端真正共享，而不是继续在 controller 里复制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.editorSession / macOSViewController.scene / macOSViewController.camera / macOSViewController.boardState
// 功能说明: 修改后 macOS controller 与 iOS 一样，通过 editorSession 统一访问共享编辑状态，保留平台视图与平台交互胶水。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let editorSession = CanvasEditorSession(
    saveQueueLabel: "MyCanvas.BoardSave.macOS",
    logPrefix: "[BoardStore][macOS]"
)
private let canvasViewportView = macOSCanvasViewportView()
private var canvasContentView: NSView?
private var pointerDragState: PointerDragState = .idle
private var saveButtonResetWorkItem: DispatchWorkItem?

private var scene: CanvasScene {
    editorSession.scene
}

private var camera: CanvasCamera {
    get { editorSession.camera }
    set { editorSession.camera = newValue }
}

private var boardState: CanvasBoardState? {
    get { editorSession.boardState }
    set { editorSession.boardState = newValue }
}

private var interactionState: CanvasInteractionState {
    get { editorSession.interactionState }
    set { editorSession.interactionState = newValue }
}

private var inlineEditState: CanvasInlineEditState? {
    get { editorSession.inlineEditState }
    set { editorSession.inlineEditState = newValue }
}

private var rotationPreviewState: CanvasRotationPreviewState? {
    get { editorSession.rotationPreviewState }
    set { editorSession.rotationPreviewState = newValue }
}

private var rotationInteractionState: CanvasRotationInteractionState? {
    get { editorSession.rotationInteractionState }
    set { editorSession.rotationInteractionState = newValue }
}

private var lastRenderSnapshot: CanvasRenderSnapshot {
    editorSession.lastRenderSnapshot
}
```

## 修改五：macOS controller 的共享刷新 / history / 保存 / 导入逻辑同步委托 session

### 修改前

- `refreshCanvas()`、`refreshMiniMap()`、`performUndoCommand()`、`saveBoardNow(...)`、`appendImportedImage(_:)` 都直接依赖本地共享运行时。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: refreshCanvas() / refreshMiniMap() / performUndoCommand() / saveBoardNow(...) / appendImportedImage(_:)
// 功能说明: 修改前 macOS controller 直接负责共享编辑逻辑，和平台层逻辑混在一起。
private func refreshCanvas() {
    let snapshot = renderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    lastRenderSnapshot = snapshot
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
}

private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
    miniMapView.apply(snapshot)
}

func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = historyController.undo()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
}

private func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    guard let snapshot = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        completion(.failure(FolderBookmarkStoreError.missingBookmarkData))
        return
    }

    saveCoordinator.saveImmediately(
        snapshot: snapshot,
        reason: reason,
        completion: completion
    )
}

private func appendImportedImage(_ cgImage: CGImage) {
    let beforeSnapshot = currentBoardHistorySnapshot()
    let item = CanvasImageItem(
        cgImage: cgImage,
        center: camera.center,
        size: normalizedDisplaySize(for: cgImage),
        zIndex: nextImageZIndex()
    )

    scene.append(item)
    expandBoardIfNeeded(toInclude: item.worldFrame)
    refreshCanvas()
    recordImmediateHistoryChange(
        from: beforeSnapshot,
        reason: "append image",
        autosaveReason: "append image"
    )
}
```

### 修改后

- macOS 侧与 iOS 侧使用相同的 session 委托模式。
- `macOSAppDelegate` 既有的 `performUndoCommand()` / `canUndoCommand` 接线仍然可用，只是内部实现改为走 session。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: refreshCanvas() / refreshMiniMap() / performUndoCommand() / saveBoardNow(...) / appendImportedImage(_:)
// 功能说明: 修改后 macOS controller 继续保留平台 UI 责任，但共享编辑逻辑统一委托给 editorSession。
private func refreshCanvas() {
    let snapshot = editorSession.makeCanvasSnapshot()
    canvasViewportView.apply(snapshot)
    refreshMiniMap()
}

private func refreshMiniMap() {
    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}

func performUndoCommand() {
    guard
        canUndoCommand,
        let snapshot = editorSession.undoHistorySnapshot()
    else {
        return
    }

    applyBoardHistorySnapshot(snapshot)
    scheduleAutosave(reason: "undo change")
}

private func saveBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    editorSession.saveBoardNow(
        reason: reason,
        createBoardIfNeeded: createBoardIfNeeded,
        completion: completion
    )
}

private func appendImportedImage(_ cgImage: CGImage) {
    _ = editorSession.appendImportedImage(cgImage)
    refreshCanvas()
}
```

## 本阶段收口后的边界

- 已迁入 `CanvasEditorSession`：
  - `scene`
  - `camera`
  - `boardState`
  - `interactionState`
  - `inlineEditState`
  - `rotationPreviewState`
  - `rotationInteractionState`
  - `lastRenderSnapshot`
  - `renderer`
  - `miniMapRenderer`
  - `BoardSaveCoordinator`
  - `BoardHistoryController`
  - `activeBoardID` / `activeBoardTitle` / `activeBoardCreatedAt`
- 仍保留在平台 controller：
  - `pointerDragState`
  - 原生视图树与布局
  - 按钮外观更新
  - 平台导入器 / 弹窗 / 错误提示
  - 现有 pointer hit test 与几何交互状态机

## 阶段 1 的实际收益

1. 两端平台不再各自维护一套共享编辑运行时。
2. 后续 `CanvasCommandCatalog` / `CanvasCommandExecutor` 有了统一的宿主。
3. 后续 `CanvasContextResolver` 可以直接依赖 session，而不必继续耦合两个平台 controller。
4. 当前 `macOSAppDelegate` 的 undo / redo 接线无需改动，仍可通过 controller 对外暴露的接口工作。
5. 这一步没有动平台视图层和指针状态机，因此风险被控制在共享状态与共享副作用边界内。

## 校验结果

- 已检查以下文件的 lint，未发现新增问题：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已执行项目级编译校验，并通过：

```bash
# 文件路径: MyCanvas_Ver_0
# 函数名/类型名: 命令行校验
# 功能说明: 使用完整 Xcode 的 developer dir 对 macOS / iOS 泛化目标进行编译校验，确认阶段 1 收口后工程可通过构建。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=macOS" \
  build CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS" \
  build CODE_SIGNING_ALLOWED=NO
```

## 结论

- 这次修改不是在 controller 上继续叠菜单前置逻辑，而是先完成了 `方案 C + 方案 D` 里最底层的共享编辑会话收口。
- 阶段 1 完成后，平台层已经退化成“平台 UI + 平台输入 + 平台状态机”，共享编辑底座已从两端 controller 中抽离出来。
- 下一阶段可以在此基础上继续做 `CanvasCommandCatalog + CanvasCommandExecutor`，把现有 crop / undo / redo / selection 等能力进一步从 controller 内部方法提升为共享命令能力。
