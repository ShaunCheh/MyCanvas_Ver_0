# 20260408_175850_alignment_guides_phase3_ios_controller_record

## 记录范围

- 记录内容：
  1. 将 `iOS` 拖拽移动入口切换到共享 `CanvasAlignmentGuideSolver`。
  2. 在 `iOSViewController` 中写入并清理 `alignmentInteractionState`，打通拖拽期的 transient overlay 闭环。
  3. 保持现有 pointer history transaction 边界不变，并补充构建与共享测试验证。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 当前 changes 依据：
  - `git status --short` 当前显示：
    - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `git diff --stat -- MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 当前显示：
    - `1 file changed, 70 insertions(+), 4 deletions(-)`
  - `git diff -- MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift` 显示：本次修改集中在 solver 接线、alignment transient state 写入/清理，以及 `moveSelectedItem(...)` 的移动语义切换。
- 验证依据：
  - `ReadLints`：`iOSViewController.swift` 无新增诊断问题。
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator"`
- 本记录不包含：
  - `Phase 4` 的 macOS 控制器接入
  - `Phase 5` 的 viewport 辅助线绘制
  - git commit / push

## 修改一：iOS 控制器新增共享 solver 与 alignment state 入口

### 修改前

- `iOSViewController` 只持有 `rotationInteractionState` 的 controller 侧代理属性，没有 `alignmentInteractionState`。
- 控制器内部也没有共享 `CanvasAlignmentGuideSolver` 实例，因此拖拽时无法在平台层调用共享求解器。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSViewController / rotationInteractionState
// 功能说明: 修改前 iOS 控制器只有 rotation transient state 的访问入口；alignment solver 和 alignmentInteractionState 都还没有接到 controller 层。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate {
    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()

    private var rotationInteractionState: CanvasRotationInteractionState? {
        get { editorSession.rotationInteractionState }
        set { editorSession.rotationInteractionState = newValue }
    }
}
```

### 修改后

- 新增 `private let alignmentGuideSolver = CanvasAlignmentGuideSolver()`。
- 新增 `alignmentInteractionState` 的 controller 侧代理属性，直接透传到 `editorSession.alignmentInteractionState`。
- 这样 `moveSelectedItem(...)` 可以在 iOS 控制器里先调用共享 solver，再把结果写回 `scene` 和 `editorSession`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: iOSViewController / alignmentInteractionState
// 功能说明: 修改后 iOS 控制器已经具备调用共享 alignment solver 和写入 alignment transient state 的基础入口，为拖拽链路改造提供共享层接点。
final class iOSViewController: UIViewController, PHPickerViewControllerDelegate, UIDropInteractionDelegate, UITextViewDelegate {
    private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
    private let alignmentGuideSolver = CanvasAlignmentGuideSolver()

    private var rotationInteractionState: CanvasRotationInteractionState? {
        get { editorSession.rotationInteractionState }
        set { editorSession.rotationInteractionState = newValue }
    }

    private var alignmentInteractionState: CanvasAlignmentInteractionState? {
        get { editorSession.alignmentInteractionState }
        set { editorSession.alignmentInteractionState = newValue }
    }
}
```

## 修改二：`moveSelectedItem(...)` 从“原始 delta 直接写 scene”切换为“共享 solver 求解后再提交”

### 修改前

- `moveSelectedItem(...)` 只做两件事：
  1. 通过 `viewportToWorld` 计算 `deltaInWorld`
  2. 直接调用 `scene.moveItem(withID:by:)`
- 修改前这条链路不会：
  - 调用共享 solver
  - 计算 `proposedCenter`
  - 生成/写入 `alignmentInteractionState`
  - 使用吸附后的中心点或位移

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: moveSelectedItem(withID:from:to:)
// 功能说明: 修改前拖拽移动链路只根据 pointer 位移计算 deltaInWorld，并直接写给 scene.moveItem；没有任何对齐候选搜索、吸附修正或 transient guide state 写入。
private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let deltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard deltaInWorld != .zero else {
        return
    }

    scene.moveItem(withID: itemID, by: deltaInWorld)
    if let movedItem = scene.boardItem(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldBounds)
    }
    requestCanvasRefresh(reason: "move selected item by \(describe(point: deltaInWorld))")
}
```

### 修改后

- `moveSelectedItem(...)` 现在的流程变为：
  1. 先取当前 `movingItem`
  2. 计算原始 `rawDeltaInWorld`
  3. 基于当前 item center 推出 `proposedCenter`
  4. 调用共享 `alignmentGuideSolver.solve(...)`
  5. 计算 `resolvedDeltaInWorld`
  6. 写入 `alignmentInteractionState`
  7. 再调用 `scene.moveItem(...)`
  8. 最后扩板并 refresh
- 这一步把 iOS 端拖拽几何从“平台自己直接写 scene”改成了“平台负责输入，几何求解交给共享 solver”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: moveSelectedItem(withID:from:to:)
// 功能说明: 修改后 iOS 拖拽链路会先把 raw delta 转成 proposedCenter，调用共享 alignment solver 得到吸附后的 resolvedCenter 和 transient interaction state，再提交移动并刷新画布。
private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    guard let movingItem = scene.boardItem(withID: itemID) else {
        clearAlignmentInteractionStateIfNeeded(
            refreshReason: "clear missing alignment interaction item"
        )
        return
    }

    let previousWorldLocation = camera.viewportToWorld(previousLocation)
    let currentWorldLocation = camera.viewportToWorld(location)
    let rawDeltaInWorld = CGPoint(
        x: currentWorldLocation.x - previousWorldLocation.x,
        y: currentWorldLocation.y - previousWorldLocation.y
    )
    guard rawDeltaInWorld != .zero else {
        return
    }

    let proposedCenter = CGPoint(
        x: movingItem.center.x + rawDeltaInWorld.x,
        y: movingItem.center.y + rawDeltaInWorld.y
    )
    let solveResult = alignmentGuideSolver.solve(
        CanvasAlignmentSolveRequest(
            movingItemID: itemID,
            proposedCenter: proposedCenter,
            scene: scene,
            boardState: boardState,
            camera: camera
        )
    )
    let resolvedDeltaInWorld = CGPoint(
        x: solveResult.resolvedCenter.x - movingItem.center.x,
        y: solveResult.resolvedCenter.y - movingItem.center.y
    )

    alignmentInteractionState = solveResult.interactionState
    scene.moveItem(withID: itemID, by: resolvedDeltaInWorld)
    if let movedItem = scene.boardItem(withID: itemID) {
        expandBoardIfNeeded(toInclude: movedItem.worldBounds)
    }
    requestCanvasRefresh(
        reason: "move selected item by \(describe(point: resolvedDeltaInWorld))"
    )
}
```

## 修改三：新增 alignment transient state 的统一清理 helper

### 修改前

- iOS 控制器里没有统一的 alignment state 清理函数。
- 一旦后续拖拽开始写入 `editorSession.alignmentInteractionState`，pointer 生命周期各分支就需要手动散落清理，容易漏掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: clearAlignmentInteractionStateIfNeeded(...)
// 功能说明: 修改前该函数不存在；alignment transient state 还没有统一清理入口。
```

### 修改后

- 新增 `clearAlignmentInteractionStateIfNeeded(refreshReason:)`。
- 它会：
  - 在 state 为空时直接返回 `false`
  - 在 state 非空时清空 `alignmentInteractionState`
  - 如有需要触发一次带原因的 `requestCanvasRefresh(...)`
- 这样 pointer up、pointer cancel 和异常兜底路径都可以复用一套清理逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: clearAlignmentInteractionStateIfNeeded(refreshReason:)
// 功能说明: 修改后 alignment transient state 的清理逻辑被统一收口，既能返回是否真的发生了清理，也能在需要时触发一次显式 refresh，避免辅助线残留。
@discardableResult
private func clearAlignmentInteractionStateIfNeeded(
    refreshReason: String? = nil
) -> Bool {
    guard alignmentInteractionState != nil else {
        return false
    }

    alignmentInteractionState = nil
    if let refreshReason {
        requestCanvasRefresh(reason: refreshReason)
    }
    return true
}
```

## 修改四：`pointer up` 与 `pointer cancel` 接入 alignment state 清理

### 修改前

- `handlePrimaryPointerUp(at:)` 的 `.draggingSelectedItem` 分支只会提交 `move item` 事务。
- `handlePrimaryPointerCancel()` 的 `.draggingSelectedItem` 分支也只会提交事务。
- `.pressed` 点击收尾路径也不会清理 alignment state。
- 这意味着一旦开始在拖拽期显示 alignment overlay，松手或取消后会有残留风险。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改前 pointer up/cancel 的移动分支只处理 history 事务，不会清理 alignment transient state；pressed 收尾也没有兜底清理。
private func handlePrimaryPointerUp(at location: CGPoint) {
    switch pointerDragState {
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    default:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    default:
        editorSession.cancelPendingHistoryTransaction()
    }
}
```

### 修改后

- `.draggingSelectedItem` 的 `pointer up` / `pointer cancel` 分支在提交事务后都会调用 `clearAlignmentInteractionStateIfNeeded(...)`。
- `.pressed` 分支会先尝试清理 alignment state。
- 如果 `.pressed` 分支后续没有触发别的 refresh（例如只是空白点击收尾），就会补一次 `requestCanvasRefresh(reason: "clear alignment interaction on pointer up")`；如果选择变化或开始文本编辑已经导致 refresh，就不会重复刷一帧。
- 这一步专门处理“拖拽结束后辅助线残留”的问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改后 iOS pointer 生命周期会在拖拽结束和点击收尾路径统一清理 alignment transient state，并避免和已有选择/文本编辑 refresh 重复触发。
private func handlePrimaryPointerUp(at location: CGPoint) {
    switch pointerDragState {
    case let .pressed(_, pressContext):
        let clearedAlignmentInteractionState =
            clearAlignmentInteractionStateIfNeeded()
        var didTriggerPressedRefresh = false
        // ... 现有点击/选择逻辑继续执行 ...
        if clearedAlignmentInteractionState, didTriggerPressedRefresh == false {
            requestCanvasRefresh(
                reason: "clear alignment interaction on pointer up"
            )
        }
        editorSession.cancelPendingHistoryTransaction()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        clearAlignmentInteractionStateIfNeeded(
            refreshReason: "finish move alignment interaction"
        )
    default:
        break
    }
}

private func handlePrimaryPointerCancel() {
    switch pointerDragState {
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
        clearAlignmentInteractionStateIfNeeded(
            refreshReason: "cancel move alignment interaction"
        )
    default:
        editorSession.cancelPendingHistoryTransaction()
    }
}
```

## 修改五：历史事务边界保持不变，只增加 solver 与 transient overlay 状态

### 修改前

- 移动事务的开始和提交分别由：
  - `beginPointerHistoryTransactionIfNeeded(...)`
  - `commitPendingPointerHistoryTransaction(...)`
 负责。
- 原始拖拽链路没有吸附和辅助线，但事务边界是稳定的。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: beginPointerHistoryTransactionIfNeeded(for:) / commitPendingPointerHistoryTransaction(autosaveReason:)
// 功能说明: 修改前移动操作已经通过 pointer down / pointer up/cancel 的统一事务边界归并 history。
private func beginPointerHistoryTransactionIfNeeded(
    for pressContext: CanvasPointerPressContext
) {
    // ... selectedItemBody -> "move item" ...
}

private func commitPendingPointerHistoryTransaction(
    autosaveReason: String
) {
    // ... 统一提交 pending transaction ...
}
```

### 修改后

- 本次没有改动这两个事务函数本身。
- `Phase 3` 只是把“几何求解”和“alignment transient state”插到拖拽过程中，但仍然沿用原来的事务建模：
  - down 建事务
  - up/cancel 提交事务
  - alignment guide 与 snap 本身不单独记 history

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: moveSelectedItem(withID:from:to:) / handlePrimaryPointerUp(at:) / handlePrimaryPointerCancel()
// 功能说明: 修改后虽然拖拽改为共享 solver 求解，但 history 边界没有变化；alignment 只影响拖拽期表现和最终落点，不单独成为一条 history 记录。
private func moveSelectedItem(
    withID itemID: CanvasItemID,
    from previousLocation: CGPoint,
    to location: CGPoint
) {
    // ... solver 求解 + alignmentInteractionState 写入 + scene.moveItem ...
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    // ... draggingSelectedItem -> commitPendingPointerHistoryTransaction("move item") ...
}

private func handlePrimaryPointerCancel() {
    // ... draggingSelectedItem -> commitPendingPointerHistoryTransaction("move item") ...
}
```

## 本次修改后的实际状态

- 已经落下来的能力：
  - iOS 拖拽移动已经接入共享 `CanvasAlignmentGuideSolver`
  - 拖拽期会写入 `editorSession.alignmentInteractionState`
  - 松手、取消和点击收尾路径会清理 alignment transient state
  - 历史事务边界保持与改造前一致
- 还没有落下来的能力：
  - macOS 拖拽链路与 iOS 对齐
  - viewport 真实绘制 alignment overlay 线条

## 验证结果

- `ReadLints`：未发现 `iOSViewController.swift` 新增问题。
- 共享对齐相关测试已通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`
- iOS 构建已通过：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator"`
