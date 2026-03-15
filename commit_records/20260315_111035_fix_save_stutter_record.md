# 20260315_111035_fix_save_stutter_record

## 记录范围

- 记录内容：
  1. 把 `canvas` 的真正保存从主线程移动到共享的后台串行队列，减少 iOS/macOS 交互时的 UI 卡顿。
  2. 取消 `select item` 单独触发 autosave，避免“切换选中图片后 0.35 秒保存一次”打断拖动前几帧。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：原始 gif diff、额外的提交流程。

## 修改一：把真正的保存移到后台线程

### 问题背景

- `BoardStore.saveBoard(...)` 会同步执行 PNG 编码、目录协调写入和 `board.json` 写盘。
- 修改前，这条保存链路最终仍在主线程触发，因此只要 autosave 碰上拖动、缩放、平移等交互，就容易在 UI 上形成卡顿。
- 手动点击 `Save` 按钮时，也是在控制器里同步保存，只有保存结束后才更新按钮状态。

### 修改前

- iOS / macOS 控制器各自维护一套 `pendingAutosaveWorkItem`、`scheduleAutosave(...)`、`persistBoardNow(...)`。
- `scheduleAutosave(...)` 通过 `DispatchQueue.main.asyncAfter(...)` 在主线程延迟执行保存。
- 手动保存按钮点击后直接调用同步保存函数，保存时机与 UI 线程耦合较重。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: scheduleAutosave(reason:) / performAutosave(reason:) / persistBoardNow(reason:createBoardIfNeeded:)
// 功能说明: 修改前 iOS 直接在控制器里维护 autosave work item，并在主线程上继续走同步保存链路。
private var pendingAutosaveWorkItem: DispatchWorkItem?

private func scheduleAutosave(reason: String) {
    guard currentBoardRuntimeState() != nil else {
        return
    }

    pendingAutosaveWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.performAutosave(reason: reason)
    }
    pendingAutosaveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
}

private func performAutosave(reason: String) {
    do {
        _ = try persistBoardNow(reason: reason)
    } catch FolderBookmarkStoreError.missingBookmarkData {
        return
    } catch {
        return
    }
}

@discardableResult
private func persistBoardNow(
    reason: String,
    createBoardIfNeeded: Bool = false
) throws -> Bool {
    guard let runtimeState = currentBoardRuntimeState(createBoardIfNeeded: createBoardIfNeeded) else {
        return false
    }

    try BoardStore.saveBoard(runtimeState)
    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleSaveButtonClick()
// 功能说明: 修改前 macOS 手动保存按钮会直接调用同步保存函数，保存期间没有共享后台调度层。
@objc
private func handleSaveButtonClick() {
    pendingAutosaveWorkItem?.cancel()

    do {
        guard try persistBoardNow(reason: "manual save", createBoardIfNeeded: true) else {
            throw FolderBookmarkStoreError.missingBookmarkData
        }

        showSaveButtonFeedback(
            title: "Saved",
            systemImageName: "checkmark",
            tintColor: .systemGreen
        )
    } catch FolderBookmarkStoreError.missingBookmarkData {
        showSaveButtonFeedback(
            title: "No Folder",
            systemImageName: "exclamationmark.triangle",
            tintColor: .systemOrange
        )
        presentSaveError(
            message: "Select a folder from the board list before saving."
        )
    } catch {
        showSaveButtonFeedback(
            title: "Failed",
            systemImageName: "xmark",
            tintColor: .systemRed
        )
        presentSaveError(message: error.localizedDescription)
    }
}
```

### 修改后

- 新增共享 `BoardSaveCoordinator`，统一封装：
  - 主线程外的串行 `saveQueue`
  - autosave 防抖
  - 立即保存
  - 保存完成后回主线程做 UI 反馈
- iOS / macOS 控制器不再自己维护 `pendingAutosaveWorkItem`，而是只负责在主线程生成 `BoardRuntimeState` 快照，再把快照交给协调器。
- 手动保存按钮现在会先进入 `Saving` 状态，再异步等待后台保存完成，最后切回 `Saved / Failed / No Folder`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数名: scheduleAutosave(snapshot:reason:onFailure:) / saveImmediately(snapshot:reason:completion:)
// 功能说明: 修改后统一把真正的 BoardStore.saveBoard(...) 放进后台串行队列执行，控制器只需提交快照。
final class BoardSaveCoordinator {
    private let autosaveDelay: TimeInterval
    private let logPrefix: String
    private let saveQueue: DispatchQueue
    private var pendingAutosaveWorkItem: DispatchWorkItem?

    init(
        queueLabel: String,
        logPrefix: String,
        autosaveDelay: TimeInterval = 0.35
    ) {
        self.autosaveDelay = autosaveDelay
        self.logPrefix = logPrefix
        saveQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func scheduleAutosave(
        snapshot: BoardRuntimeState,
        reason: String,
        onFailure: ((Error) -> Void)? = nil
    ) {
        cancelPendingAutosave()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingAutosaveWorkItem = nil
            self.enqueueSave(snapshot: snapshot, reason: reason) { result in
                guard let onFailure else {
                    return
                }

                if case let .failure(error) = result {
                    onFailure(error)
                }
            }
        }

        pendingAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    func saveImmediately(
        snapshot: BoardRuntimeState,
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        cancelPendingAutosave()
        enqueueSave(
            snapshot: snapshot,
            reason: reason,
            completion: completion
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: scheduleAutosave(reason:) / saveBoardNow(reason:createBoardIfNeeded:completion:)
// 功能说明: 修改后 iOS 只在主线程生成 BoardRuntimeState 快照，再交给共享后台调度层。
private let saveCoordinator = BoardSaveCoordinator(
    queueLabel: "MyCanvas.BoardSave.iOS",
    logPrefix: "[BoardStore][iOS]"
)

private func scheduleAutosave(reason: String) {
    guard let snapshot = currentBoardRuntimeState() else {
        return
    }

    saveCoordinator.scheduleAutosave(
        snapshot: snapshot,
        reason: reason
    )
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: handleSaveButtonClick() / beginSaveButtonSaveState()
// 功能说明: 修改后 macOS 手动保存按钮会先进入 Saving 状态，再等待后台保存完成后回主线程更新按钮文案。
@objc
private func handleSaveButtonClick() {
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(
                title: "Saved",
                systemImageName: "checkmark",
                tintColor: .systemGreen
            )
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(
                    title: "No Folder",
                    systemImageName: "exclamationmark.triangle",
                    tintColor: .systemOrange
                )
            } else {
                self.showSaveButtonFeedback(
                    title: "Failed",
                    systemImageName: "xmark",
                    tintColor: .systemRed
                )
            }
        }
    }
}

private func beginSaveButtonSaveState() {
    saveButtonResetWorkItem?.cancel()
    saveButton.isEnabled = false
    applySaveButtonAppearance(
        title: "Saving",
        systemImageName: "square.and.arrow.down",
        tintColor: .controlAccentColor
    )
}
```

### 结果

- 真正的磁盘保存不再占用主线程，拖动、缩放、平移时的 UI 阻塞风险明显降低。
- iOS / macOS 的保存调度逻辑被统一抽到共享层，后续再调 autosave 策略时不需要同时维护两套实现。
- 手动 `Save` 按钮仍然保留原有成功/失败/未选目录反馈，但现在变成异步保存体验。

## 修改二：`select item` 不再触发 autosave

### 问题背景

- 这次卡顿的主要复现路径是：先选中 A，再点 B，然后立刻拖动 B。
- 原因不是选中高亮本身，而是“切换选中对象”会单独触发一次 autosave；这次 autosave 在 `0.35s` 后执行，很容易与拖动开始时机重叠。
- 如果拖动前仍然是原先已经选中的 A，则 `selectItem(withID:)` 会直接返回，不会触发这次额外保存，所以不会出现同样的卡顿峰值。

### 修改前

- `selectItem(withID:)` 在两端控制器里都会在更新 `selectedItemID` 后调用 `scheduleAutosave(reason: "select item")`。
- 这意味着“单纯切换选中态”也会走一遍完整的保存链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: selectItem(withID:)
// 功能说明: 修改前只要选中项发生变化，就会立刻安排一次 autosave。
private func selectItem(withID itemID: CanvasImageItemID) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    interactionState.selectedItemID = itemID
    requestCanvasRefresh(reason: "select item \(itemID.uuidString)")
    scheduleAutosave(reason: "select item")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: selectItem(withID:)
// 功能说明: 修改前 macOS 同样把“选中变化”视为 autosave 触发点之一。
private func selectItem(withID itemID: CanvasImageItemID) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    interactionState.selectedItemID = itemID
    refreshCanvas()
    scheduleAutosave(reason: "select item")
}
```

### 修改后

- `selectItem(withID:)` 现在只负责更新选中态和刷新画布，不再单独触发 autosave。
- 其他真正影响画板内容或视图状态的动作仍然会保存，例如：
  - `append image`
  - `move item`
  - `pan canvas`
  - `zoom canvas`
  - `configure board state`
- `selectedItemID` 仍然保留在文档模型中，只是不会因为一次孤立的点击选中而立刻保存；后续其他保存时机到来时，它仍会一起被写入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: selectItem(withID:)
// 功能说明: 修改后 iOS 切换选中对象只做 UI 更新，不再把“单独选中”作为 autosave 触发点。
private func selectItem(withID itemID: CanvasImageItemID) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    interactionState.selectedItemID = itemID
    requestCanvasRefresh(reason: "select item \(itemID.uuidString)")
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: selectItem(withID:)
// 功能说明: 修改后 macOS 与 iOS 保持一致，选中态变化不再直接触发 autosave。
private func selectItem(withID itemID: CanvasImageItemID) {
    guard interactionState.selectedItemID != itemID else {
        return
    }

    interactionState.selectedItemID = itemID
    refreshCanvas()
}
```

### 结果

- “先点 B，再马上拖 B” 这条路径不再插入一次额外 autosave，拖动前几帧更平滑。
- 交互上仍能立即看到选中高亮变化，因为 `requestCanvasRefresh(...)` / `refreshCanvas()` 保留不变。
- 保存行为更聚焦于真正改变画板数据或视图状态的动作，减少无意义的频繁落盘。
