# 20260316_191800_phase_bplus_stage3_history_commit_flow_record

## 记录范围

- 记录内容：
  1. 新增共享的文档级历史快照模型，明确把 `camera` 排除在历史记录之外。
  2. 新增共享历史控制器，支持 pending transaction、undo stack、redo stack 的基础能力。
  3. 让 iOS / macOS controller 把“点击选中 / 点击空白取消选中 / 导入图片 / move / resize”统一接入历史与“已提交变更才 autosave”的流程。
  4. 为后续平台 undo / redo 命令接线预留 `applyBoardHistorySnapshot(...)`。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 平台 undo / redo 菜单、快捷键或命令入口接线
  - inline crop / rotate overlay
  - 原始 gif diff

## 修改一：新增文档级历史快照模型，显式排除 camera

### 修改前

- 项目里没有独立的“仅文档状态”历史快照类型。
- `BoardRuntimeState` 可以承载完整运行态，但没有一层专门用于撤销/重做的文档快照桥接，也没有显式声明“历史不包含 camera”。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前项目里没有专门给撤销/重做使用的文档级快照模型，也没有把 camera 排除出历史的共享桥接层。
// before: file did not exist
```

### 修改后

- 新增 `BoardHistorySnapshot`，只保存 `items + boardState + interactionState`。
- 新增 `Equatable` 比较逻辑，确保历史提交可以基于“文档是否真的变化”来判断。
- 在同文件里补了 `BoardRuntimeState` 扩展，用于把运行态投影为历史快照，或用历史快照替换文档状态，但保留 `camera` 不变。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift
// 函数名/类型名: BoardHistorySnapshot / BoardRuntimeState.historySnapshot / BoardRuntimeState.replacingDocumentState(with:)
// 功能说明: 修改后新增共享文档快照模型，并通过 runtime state bridge 明确“历史只覆盖文档状态，不覆盖 camera”。
import CoreGraphics
import Foundation

struct BoardHistorySnapshot {
    var items: [CanvasImageItem]
    var boardState: CanvasBoardState?
    var interactionState: CanvasInteractionState
}

extension BoardHistorySnapshot: Equatable {
    static func == (lhs: BoardHistorySnapshot, rhs: BoardHistorySnapshot) -> Bool {
        itemsMatch(lhs.items, rhs.items) &&
        boardStatesMatch(lhs.boardState, rhs.boardState) &&
        lhs.interactionState.selectedItemID == rhs.interactionState.selectedItemID
    }

    private static func itemsMatch(
        _ lhsItems: [CanvasImageItem],
        _ rhsItems: [CanvasImageItem]
    ) -> Bool {
        guard lhsItems.count == rhsItems.count else {
            return false
        }

        return zip(lhsItems, rhsItems).allSatisfy { lhsItem, rhsItem in
            lhsItem.id == rhsItem.id &&
            lhsItem.center == rhsItem.center &&
            lhsItem.size == rhsItem.size &&
            lhsItem.zIndex == rhsItem.zIndex &&
            lhsItem.cropRectNormalized == rhsItem.cropRectNormalized &&
            lhsItem.rotationRadians == rhsItem.rotationRadians
        }
    }
}

extension BoardRuntimeState {
    var historySnapshot: BoardHistorySnapshot {
        BoardHistorySnapshot(
            items: items,
            boardState: boardState,
            interactionState: interactionState
        )
    }

    func replacingDocumentState(
        with snapshot: BoardHistorySnapshot,
        updatedAt: Date = Date()
    ) -> BoardRuntimeState {
        BoardRuntimeState(
            boardID: boardID,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            items: snapshot.items,
            boardState: snapshot.boardState,
            camera: camera,
            interactionState: snapshot.interactionState
        )
    }
}
```

## 修改二：新增共享历史控制器，承载 transaction / undo / redo 基础能力

### 修改前

- 项目里没有共享的历史控制器。
- controller 只能直接改 scene / interaction state / save coordinator，无法统一表达“一次点击一条历史”“一次拖拽一条历史”。

```text
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift
// 函数名/类型名: 文件原先不存在
// 功能说明: 修改前项目里没有共享历史控制器，controller 无法通过 shared 层统一维护 undo stack / redo stack / pending transaction。
// before: file did not exist
```

### 修改后

- 新增 `BoardHistoryController`，内部维护：
  - `undoStack`
  - `redoStack`
  - `pendingTransaction`
- 提供：
  - `beginTransaction(...)`
  - `cancelPendingTransaction()`
  - `commitPendingTransaction(...)`
  - `recordChange(...)`
  - `undo()`
  - `redo()`
- 这样 controller 只需要在合适的交互边界调用 shared API，不需要自己维护栈结构。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift
// 函数名/类型名: BoardHistoryController
// 功能说明: 修改后新增共享历史控制器，用 pending transaction 把一次点击/一次拖拽收束为一条历史记录，并维护 undo/redo 栈。
import Foundation

// History tracks document state only. Camera stays outside so undo/redo can
// restore board edits and selection without unexpectedly jumping the viewport.
final class BoardHistoryController {
    private struct BoardHistoryEntry {
        let beforeSnapshot: BoardHistorySnapshot
        let afterSnapshot: BoardHistorySnapshot
        let reason: String
    }

    private struct BoardHistoryTransaction {
        let initialSnapshot: BoardHistorySnapshot
        let reason: String
    }

    private var undoStack: [BoardHistoryEntry] = []
    private var redoStack: [BoardHistoryEntry] = []
    private var pendingTransaction: BoardHistoryTransaction?

    func beginTransaction(
        from snapshot: BoardHistorySnapshot,
        reason: String
    ) {
        guard pendingTransaction == nil else {
            return
        }

        pendingTransaction = BoardHistoryTransaction(
            initialSnapshot: snapshot,
            reason: reason
        )
    }

    func cancelPendingTransaction() {
        pendingTransaction = nil
    }

    @discardableResult
    func commitPendingTransaction(
        to snapshot: BoardHistorySnapshot
    ) -> Bool {
        guard let pendingTransaction else {
            return false
        }

        self.pendingTransaction = nil
        return recordChange(
            from: pendingTransaction.initialSnapshot,
            to: snapshot,
            reason: pendingTransaction.reason
        )
    }

    @discardableResult
    func recordChange(
        from beforeSnapshot: BoardHistorySnapshot,
        to afterSnapshot: BoardHistorySnapshot,
        reason: String
    ) -> Bool {
        guard beforeSnapshot != afterSnapshot else {
            return false
        }

        undoStack.append(
            BoardHistoryEntry(
                beforeSnapshot: beforeSnapshot,
                afterSnapshot: afterSnapshot,
                reason: reason
            )
        )
        redoStack.removeAll()
        return true
    }

    func undo() -> BoardHistorySnapshot? {
        guard let entry = undoStack.popLast() else {
            return nil
        }

        redoStack.append(entry)
        pendingTransaction = nil
        return entry.beforeSnapshot
    }

    func redo() -> BoardHistorySnapshot? {
        guard let entry = redoStack.popLast() else {
            return nil
        }

        undoStack.append(entry)
        pendingTransaction = nil
        return entry.afterSnapshot
    }
}
```

## 修改三：iOS controller 改为“按下记录起点，抬起/取消统一提交”

### 修改前

- `pointerDown` 只记录按下态，不建立历史事务。
- `pointerUp` 的 `draggingSelectedItem / resizingSelectedItem` 分支不会提交历史。
- `pointerCancel` 只会把状态设回 `.idle`。
- `appendImportedImage(...)` 会直接 `scheduleAutosave(...)`。
- `moveSelectedItem(...)` / `resizeSelectedItem(...)` 在拖拽过程中每次变化都直接 `scheduleAutosave(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改前 iOS pointer 生命周期里没有 shared history transaction，拖拽完成后也不会统一提交历史。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pointerPressTarget(at: location)
    )
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        // ... 省略未改动代码 ...
        break
    case .draggingSelectedItem, .resizingSelectedItem, .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    pointerDragState = .idle
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: appendImportedImage(_:) / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改前导入、move、resize 都会直接走 autosave，拖拽过程中的 preview 也会写盘。
private func appendImportedImage(_ cgImage: CGImage) {
    // ... 省略未改动代码 ...
    scheduleAutosave(reason: "append image")
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... 省略未改动代码 ...
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
    scheduleAutosave(reason: "move item")
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    // ... 省略未改动代码 ...
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedWorldFrame))")
    scheduleAutosave(reason: "resize item")
}
```

### 修改后

- `handlePrimaryPointerDown(at:)` 先解析 `pressTarget`，再调用 `beginPointerHistoryTransactionIfNeeded(...)`。
- `handlePrimaryPointerUp(at:)` 中：
  - 点击路径仍即时改选中态，但在 click 结束后清掉 pending transaction。
  - move / resize 路径会在抬起时调用 `commitPendingPointerHistoryTransaction(...)`。
- `handlePrimaryPointerCancel()` 对已进入 move / resize 的情况也会补交一次提交，避免 iOS 多指 / pinch 中断后丢历史。
- `appendImportedImage(...)` 不再直接写盘，而是先抓 `beforeSnapshot`，再通过 `recordImmediateHistoryChange(...)` 统一记录历史并触发 autosave。
- `moveSelectedItem(...)` / `resizeSelectedItem(...)` 只做预览刷新，不再在拖拽中重复 autosave。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改后 iOS controller 在按下时记录 pending history transaction，并在 pointerUp / pointerCancel 对 move / resize 做一次性提交。
private let historyController = BoardHistoryController()

private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    let pressTarget = pointerPressTarget(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pressTarget
    )
    beginPointerHistoryTransactionIfNeeded(for: pressTarget)
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        // ... 省略未改动代码 ...
        historyController.cancelPendingTransaction()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .pressed, .draggingCanvas, .idle:
        historyController.cancelPendingTransaction()
    }

    pointerDragState = .idle
}

// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: appendImportedImage(_:) / selectItem(withID:recordHistory:) / clearSelectionIfNeeded(recordHistory:) / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改后导入/点击选中/点击空白取消选中走统一历史入口；move/resize 只做预览刷新，autosave 延后到提交时再触发。
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

private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    requestCanvasRefresh(reason: "select item \(itemID.uuidString)")

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }
}

private func clearSelectionIfNeeded(recordHistory: Bool = false) {
    guard interactionState.selectedItemID != nil else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = nil
    requestCanvasRefresh(reason: "clear selection")

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear selection"
        )
    }
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... 省略未改动代码 ...
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    // ... 省略未改动代码 ...
    requestCanvasRefresh(reason: "resize selected item to \(describe(rect: resizedWorldFrame))")
}
```

- 同时补了 controller 侧的共享快照桥接与历史提交 helper，为后续平台 undo / redo 命令接线预留统一入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: restorePersistedBoardIfPossible() / currentBoardHistorySnapshot() / applyBoardHistorySnapshot(_:) / beginPointerHistoryTransactionIfNeeded(for:) / commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 功能说明: 修改后 iOS controller 通过 shared history snapshot 与 helper 方法统一管理恢复、提交和后续 undo/redo 的 apply 入口。
private func restorePersistedBoardIfPossible() {
    do {
        let runtimeState = try BoardStore.loadOrCreateInitialBoard()
        applyBoardRuntimeState(runtimeState)
        historyController.reset()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("[BoardStore][iOS] Failed to restore board: \(error)")
    }
}

private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedItems(),
        boardState: boardState,
        interactionState: interactionState
    )
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    requestCanvasRefresh(reason: "apply history snapshot")
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressTarget: PointerPressTarget
) {
    let reason: String
    switch pressTarget {
    case .handle:
        reason = "resize item"
    case .selectedBody:
        reason = "move item"
    case .unselectedItem, .blank:
        return
    }

    historyController.beginTransaction(
        from: currentBoardHistorySnapshot(),
        reason: reason
    )
}

private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return
    }

    scheduleAutosave(reason: autosaveReason)
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard historyController.recordChange(
        from: beforeSnapshot,
        to: currentBoardHistorySnapshot(),
        reason: reason
    ) else {
        return
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }
}
```

## 修改四：macOS controller 同步接入相同的历史与提交规则

### 修改前

- `handlePrimaryPointerDown(at:)` 只写入 `.pressed`，不记录历史事务起点。
- `handlePrimaryPointerUp(at:)` 的 `draggingSelectedItem / resizingSelectedItem` 分支不会提交历史。
- `appendImportedImage(...)` / `moveSelectedItem(...)` / `resizeSelectedItem(...)` 也会直接 autosave。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改前 macOS controller 与 iOS 一样，还没有“拖拽开始记录、拖拽结束提交”的 shared history 流程。
private func handlePrimaryPointerDown(at location: CGPoint) {
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pointerPressTarget(at: location)
    )
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        // ... 省略未改动代码 ...
        break
    case .draggingSelectedItem, .resizingSelectedItem, .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    pointerDragState = .idle
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: appendImportedImage(_:) / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改前导入、move、resize 也都直接触发 autosave，没有“只对已提交变更写盘”的收束层。
private func appendImportedImage(_ cgImage: CGImage) {
    // ... 省略未改动代码 ...
    scheduleAutosave(reason: "append image")
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... 省略未改动代码 ...
    refreshCanvas()
    scheduleAutosave(reason: "move item")
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    // ... 省略未改动代码 ...
    refreshCanvas()
    scheduleAutosave(reason: "resize item")
}
```

### 修改后

- macOS 侧同步新增 `historyController`，并与 iOS 保持同一套 shared helper 设计。
- `pointerDown / pointerUp / pointerCancel` 的 transaction 边界规则与 iOS 保持一致。
- `appendImportedImage(...)`、`selectItem(...)`、`clearSelectionIfNeeded(...)` 改为统一调用 `recordImmediateHistoryChange(...)`。
- `moveSelectedItem(...)` / `resizeSelectedItem(...)` 则只负责实时预览，autosave 延后到提交时触发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handlePrimaryPointerDown(at:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改后 macOS controller 与 iOS 保持同一套 transaction 规则，在 pointerUp / pointerCancel 对 move / resize 统一提交。
private let historyController = BoardHistoryController()

private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressTarget = pointerPressTarget(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressTarget: pressTarget
    )
    beginPointerHistoryTransactionIfNeeded(for: pressTarget)
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressTarget):
        // ... 省略未改动代码 ...
        historyController.cancelPendingTransaction()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .pressed, .draggingCanvas, .idle:
        historyController.cancelPendingTransaction()
    }

    pointerDragState = .idle
}

// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: appendImportedImage(_:) / selectItem(withID:recordHistory:) / clearSelectionIfNeeded(recordHistory:) / moveSelectedItem(withID:from:to:) / resizeSelectedItem(using:to:)
// 功能说明: 修改后 macOS 侧导入/点击选中/点击空白取消选中走统一历史入口，move/resize 只负责实时预览，autosave 在提交时再触发。
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

private func selectItem(
    withID itemID: CanvasImageItemID,
    recordHistory: Bool = false
) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = itemID
    refreshCanvas()

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "select item"
        )
    }
}

private func clearSelectionIfNeeded(recordHistory: Bool = false) {
    guard interactionState.selectedItemID != nil else {
        return
    }

    let beforeSnapshot = recordHistory ? currentBoardHistorySnapshot() : nil
    interactionState.selectedItemID = nil
    refreshCanvas()

    if let beforeSnapshot {
        recordImmediateHistoryChange(
            from: beforeSnapshot,
            reason: "clear selection"
        )
    }
}

private func moveSelectedItem(
    withID itemID: CanvasImageItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... 省略未改动代码 ...
    refreshCanvas()
}

private func resizeSelectedItem(
    using resizeState: PointerResizeState,
    to viewportLocation: CGPoint
) {
    // ... 省略未改动代码 ...
    refreshCanvas()
}
```

- 同样补了 macOS 侧的快照桥接与 helper，后续平台命令只需要在这里调用 `undo()` / `redo()` 结果并 `applyBoardHistorySnapshot(...)` 即可。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: restorePersistedBoardIfPossible() / currentBoardHistorySnapshot() / applyBoardHistorySnapshot(_:) / beginPointerHistoryTransactionIfNeeded(for:) / commitPendingPointerHistoryTransaction(autosaveReason:) / recordImmediateHistoryChange(from:reason:autosaveReason:)
// 功能说明: 修改后 macOS controller 通过 shared helper 统一管理历史快照的恢复、提交和未来的 apply 入口。
private func restorePersistedBoardIfPossible() {
    do {
        let runtimeState = try BoardStore.loadOrCreateInitialBoard()
        applyBoardRuntimeState(runtimeState)
        historyController.reset()
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        print("[BoardStore][macOS] Failed to restore board: \(error)")
    }
}

private func currentBoardHistorySnapshot() -> BoardHistorySnapshot {
    BoardHistorySnapshot(
        items: scene.orderedItems(),
        boardState: boardState,
        interactionState: interactionState
    )
}

private func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    if let runtimeState = currentBoardRuntimeState() {
        applyBoardRuntimeState(
            runtimeState.replacingDocumentState(with: snapshot)
        )
    } else {
        scene.setItems(snapshot.items)
        boardState = snapshot.boardState
        interactionState = snapshot.interactionState
    }

    refreshCanvas()
}

private func beginPointerHistoryTransactionIfNeeded(
    for pressTarget: PointerPressTarget
) {
    let reason: String
    switch pressTarget {
    case .handle:
        reason = "resize item"
    case .selectedBody:
        reason = "move item"
    case .unselectedItem, .blank:
        return
    }

    historyController.beginTransaction(
        from: currentBoardHistorySnapshot(),
        reason: reason
    )
}

private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    guard historyController.commitPendingTransaction(to: currentBoardHistorySnapshot()) else {
        return
    }

    scheduleAutosave(reason: autosaveReason)
}

private func recordImmediateHistoryChange(
    from beforeSnapshot: BoardHistorySnapshot,
    reason: String,
    autosaveReason: String? = nil
) {
    guard historyController.recordChange(
        from: beforeSnapshot,
        to: currentBoardHistorySnapshot(),
        reason: reason
    ) else {
        return
    }

    if let autosaveReason {
        scheduleAutosave(reason: autosaveReason)
    }
}
```

## 验证结果

- `ReadLints` 检查了以下文件，无新增 lint 问题：
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistorySnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/BoardHistoryController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 构建验证通过：
  - iOS Simulator `xcodebuild` 构建成功
  - macOS `xcodebuild` 构建成功

## 本阶段结果总结

- shared 层现在已经有了文档级 `history snapshot + history controller`。
- iOS / macOS 两端 controller 都已经统一到“点击即时提交、拖拽结束提交、拖拽预览不写盘”的阶段三规则。
- 后续阶段只需要继续把 crop / rotate 接进这套 transaction 规则，再把平台 undo / redo 命令入口接到 `BoardHistoryController.undo()` / `redo()` 与 `applyBoardHistorySnapshot(...)` 上即可。
