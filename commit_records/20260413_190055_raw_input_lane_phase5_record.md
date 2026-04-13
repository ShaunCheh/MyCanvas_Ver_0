# 20260413_190055_raw_input_lane_phase5_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase5` iOS / iPadOS raw-input 接通”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 `2` 个业务代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 只包含上述 `2` 个已跟踪文件修改
- `git diff --stat -- <2 个关键文件>` 统计为：`2 files changed, 214 insertions(+), 2 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 `2` 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase4` 的 macOS raw-input 接线
- `phase6` 的文本编辑 responder bridge
- `Command + C` 的真实业务 copy 执行链路补齐

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_190055`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase5 写记录前的真实工作区状态。
## feat/cross-platform-input-indicator
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计这次 phase5 关键文件的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"

# 实际输出:
#  .../Platform/iOS/iOSViewController.swift           | 198 ++++++++++++++++++++-
#  .../CanvasInputRoutingResolverTests.swift          |  18 ++
#  2 files changed, 214 insertions(+), 2 deletions(-)
```

## 本次 phase5 的真实目标

这一步严格按计划接通 iOS / iPadOS raw input，而不是继续改 macOS：

1. 让 `iPhone / iPad + 蓝牙键盘` 的 `Command + C / V / Z / Shift + Command + Z` 进入统一输入总线。
2. 让 `Tap / Long Press / Scroll / Pinch` 至少进入 indicator lane。
3. `Tap` 不能粗暴挂在 `pointer down`，要避免把拖拽起手误记成 tap。
4. `Scroll / Pinch` 不能按每一帧都冒泡，否则胶囊栈会被连续手势刷爆。
5. 首版继续按 UIKit 当前能观测到的事实事件展示，不把 iPad pointer / Mirroring 的输入强行统一成 `Left Click`。

## 修改一：`iOSViewController.swift` 的 `keyCommands` 从只支持 Paste 扩成完整首批快捷键

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: keyCommands / makePasteKeyboardShortcutRawInput() / handlePasteKeyCommand(_:)
// 功能说明: 修改前 iOS 只注册了 Command + V；其它高价值快捷键还没有进入 raw-input lane。
override var keyCommands: [UIKeyCommand]? {
    let pasteCommand = UIKeyCommand(
        input: "v",
        modifierFlags: [.command],
        action: #selector(handlePasteKeyCommand(_:))
    )
    pasteCommand.discoverabilityTitle = "Paste Image"
    return [pasteCommand]
}

private func makePasteKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
    )
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        makePasteKeyboardShortcutRawInput(),
        sourceDescription: TransferEntryDeliverySource.iOSKeyCommand.debugName
    ) { routingResult in
        guard
            routingResult.interactionIntent
                == .transferEntry(.pasteKeyboardShortcut)
        else {
            return false
        }
        handlePasteRequest()
        return true
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: RawInputDeliverySource / keyCommands / makeCopyKeyboardShortcutRawInput() / makePasteKeyboardShortcutRawInput() / makeUndoKeyboardShortcutRawInput() / makeRedoKeyboardShortcutRawInput() / handleCopyKeyCommand(_:) / handlePasteKeyCommand(_:) / handleUndoKeyCommand(_:) / handleRedoKeyCommand(_:)
// 功能说明: 修改后 iOS 的首批硬件键盘快捷键都先进入 raw-input lane；其中 Copy 只做 indicator，Paste/Undo/Redo 继续下沉到既有业务执行路径。
private enum RawInputDeliverySource {
    case copyKeyCommand
    case pasteKeyCommand
    case undoKeyCommand
    case redoKeyCommand
    case tapGesture
    case longPressGesture
    case scrollGesture
    case pinchGesture

    var debugName: String {
        switch self {
        case .copyKeyCommand:
            return "iOSCopyKeyCommand"
        case .pasteKeyCommand:
            return "iOSPasteKeyCommand"
        case .undoKeyCommand:
            return "iOSUndoKeyCommand"
        case .redoKeyCommand:
            return "iOSRedoKeyCommand"
        case .tapGesture:
            return "iOSTapGesture"
        case .longPressGesture:
            return "iOSLongPressGesture"
        case .scrollGesture:
            return "iOSScrollGesture"
        case .pinchGesture:
            return "iOSPinchGesture"
        }
    }
}

override var keyCommands: [UIKeyCommand]? {
    let copyCommand = UIKeyCommand(
        input: "c",
        modifierFlags: [.command],
        action: #selector(handleCopyKeyCommand(_:))
    )
    copyCommand.discoverabilityTitle = "Copy"

    let pasteCommand = UIKeyCommand(
        input: "v",
        modifierFlags: [.command],
        action: #selector(handlePasteKeyCommand(_:))
    )
    pasteCommand.discoverabilityTitle = "Paste Image"

    let undoCommand = UIKeyCommand(
        input: "z",
        modifierFlags: [.command],
        action: #selector(handleUndoKeyCommand(_:))
    )
    undoCommand.discoverabilityTitle = "Undo"

    let redoCommand = UIKeyCommand(
        input: "z",
        modifierFlags: [.command, .shift],
        action: #selector(handleRedoKeyCommand(_:))
    )
    redoCommand.discoverabilityTitle = "Redo"

    return [
        copyCommand,
        pasteCommand,
        undoCommand,
        redoCommand
    ]
}

private func makeCopyKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("c")
        )
    )
}

private func makePasteKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
    )
}

private func makeUndoKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("z")
        )
    )
}

private func makeRedoKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command, .shift],
            key: .character("z")
        )
    )
}

@objc
private func handleCopyKeyCommand(_ sender: UIKeyCommand) {
    observeRawInput(
        makeCopyKeyboardShortcutRawInput(),
        sourceDescription: RawInputDeliverySource.copyKeyCommand.debugName
    )
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        makePasteKeyboardShortcutRawInput(),
        sourceDescription: RawInputDeliverySource.pasteKeyCommand.debugName
    ) { routingResult in
        guard
            routingResult.interactionIntent
                == .transferEntry(.pasteKeyboardShortcut)
        else {
            return false
        }
        handlePasteRequest()
        return true
    }
}

@objc
private func handleUndoKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        makeUndoKeyboardShortcutRawInput(),
        sourceDescription: RawInputDeliverySource.undoKeyCommand.debugName
    ) { routingResult in
        guard routingResult.interactionIntent == .command(.undo) else {
            return false
        }

        performCommand(.undo)
        return true
    }
}

@objc
private func handleRedoKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        makeRedoKeyboardShortcutRawInput(),
        sourceDescription: RawInputDeliverySource.redoKeyCommand.debugName
    ) { routingResult in
        guard routingResult.interactionIntent == .command(.redo) else {
            return false
        }

        performCommand(.redo)
        return true
    }
}
```

### 修改意图

这一步把 iOS / iPadOS phase5 要求的首批快捷键完整接到了 raw-input ingress 上，并且继续遵守车道边界：

- `Command + C` 只有 indicator，不擅自补业务 copy 执行
- `Command + V / Z / Shift + Command + Z` 先做 routing，再决定是否继续下沉到既有执行路径

## 修改二：`iOSViewController.swift` 把 `Long Press / Scroll / Pinch` 接到 indicator lane

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupCanvasViewport()
// 功能说明: 修改前 iOS viewport 的长按、间接滚动、缩放只直连既有业务逻辑，还没有把这些事实事件送进 shared raw-input / indicator lane。
private func setupCanvasViewport() {
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onZoomGestureBegan = { [weak self] in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoomGestureBegan()
    }
    canvasViewportView.onZoomGestureEnded = { [weak self] in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoomGestureEnded()
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: ContinuousRawInputKind / setupCanvasViewport()
// 功能说明: 修改后 iOS viewport 的 Long Press / Scroll / Pinch 会先投递 raw-input；Scroll 做节流，Pinch 只在手势开始时记录一次，避免连续事件刷爆胶囊栈。
private enum ContinuousRawInputKind: Hashable {
    case scroll
}

private func setupCanvasViewport() {
    canvasViewportView.onLongPress = { [weak self] location in
        self?.observeRawInput(
            .gesture(.longPress, source: .touch),
            sourceDescription: RawInputDeliverySource.longPressGesture.debugName
        )
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.observeContinuousRawInput(
            .gesture(.scroll, source: .pointer),
            sourceDescription: RawInputDeliverySource.scrollGesture.debugName,
            kind: .scroll
        )
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onZoomGestureBegan = { [weak self] in
        self?.observePinchRawInputIfNeeded()
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoomGestureBegan()
    }
    canvasViewportView.onZoomGestureEnded = { [weak self] in
        self?.finishPinchRawInputObservation()
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoomGestureEnded()
    }
}
```

### 修改意图

这一步把 phase5 里最重要的手势事实接进了 indicator lane，同时没有改变既有画布交互执行路径：

- `Long Press` 继续走 context menu 业务逻辑
- `Scroll` 继续走 camera pan 逻辑
- `Pinch` 继续走 zoom 逻辑
- raw-input lane 只额外负责“观察并展示”

## 修改三：`Tap` 改在 `pointer up` 的 `.pressed` 分支记录，避免把拖拽起手误记为 Tap

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handlePrimaryPointerUp(at:)
// 功能说明: 修改前 iOS 的 pointer-up 只做点击后业务处理，没有在这里补 tap 事实；如果简单把 tap 挂在 pointer-down，会把拖拽起手误判成 tap。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressContext):
        if isInlineEditModeActive {
            editorSession.cancelPendingHistoryTransaction()
            return
        }

        let clearedAlignmentInteractionState =
            clearAlignmentInteractionStateIfNeeded()
        let pressedItemID = pressContext.targetItemID
        let releasedContext = resolvePointerPressContext(at: location)
        let releasedItemID = releasedContext.targetItemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        // ... 后续 click 处理逻辑保持不变 ...
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem, .movingCropFrame:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handlePrimaryPointerUp(at:)
// 功能说明: 修改后只有在 pointer-up 仍然落在 .pressed 分支时才记录 Tap，从而把“真正点击”和“已经升级成拖拽的手势”分开。
private func handlePrimaryPointerUp(at location: CGPoint) {
    defer {
        pointerDragState = .idle
    }

    switch pointerDragState {
    case let .pressed(_, pressContext):
        observeRawInput(
            .gesture(.tap, source: .touch),
            sourceDescription: RawInputDeliverySource.tapGesture.debugName
        )
        if isInlineEditModeActive {
            editorSession.cancelPendingHistoryTransaction()
            return
        }

        let clearedAlignmentInteractionState =
            clearAlignmentInteractionStateIfNeeded()
        let pressedItemID = pressContext.targetItemID
        let releasedContext = resolvePointerPressContext(at: location)
        let releasedItemID = releasedContext.targetItemID
        let previousSelectedItemID = interactionState.selectedItemID
        var clickTarget = "blank"
        var clickResult = "selection_unchanged"
        // ... 后续 click 处理逻辑保持不变 ...
    case .rotatingSelectedItem:
        commitRotationDraftIfNeeded()
    case .croppingSelectedItem, .movingCropFrame:
        commitCropDraftIfNeeded()
    case .draggingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "move item")
    case .resizingSelectedItem:
        commitPendingPointerHistoryTransaction(autosaveReason: "resize item")
    case .draggingCanvas, .idle:
        break
    }
}
```

### 修改意图

这一步解决的是 phase5 的语义根因，而不是简单“有手指按下就算 tap”：

- `pointer down` 只是一次可能成为点击、也可能演变成拖拽/缩放的开始
- 只有 `pointer up` 时仍停留在 `.pressed`，才能说明这是一次真正的点击事实

## 修改四：新增 iOS raw-input 观察 helper，给 Scroll 和 Pinch 加上节流/单次记录

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleZoomGestureBegan() / handleZoomGestureEnded() / handleCapturedInput(...)
// 功能说明: 修改前 controller 还没有通用的 observeRawInput / observeContinuousRawInput helper；Pinch 也没有“当前手势只记一次”的状态位。
private var didMutateCameraDuringZoomGesture = false

private func handleZoomGestureBegan() {
    didMutateCameraDuringZoomGesture = false
}

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringZoomGesture else {
        return
    }

    scheduleAutosave(
        reason: "zoom canvas",
        updateKind: .viewStateOnly
    )
    didMutateCameraDuringZoomGesture = false
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    if let indicatorEvent = routingResult.indicatorEvent {
        inputIndicatorHostView.record(event: indicatorEvent)
    }

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: lastContinuousRawInputObservationByKind / hasObservedCurrentPinchRawInput / observePinchRawInputIfNeeded() / finishPinchRawInputObservation() / observeRawInput(...) / observeContinuousRawInput(...)
// 功能说明: 修改后 controller 具备通用的 iOS raw-input 观察 helper；Scroll 通过时间窗节流，Pinch 通过单次标记避免在手势变化帧里重复冒泡。
private var lastContinuousRawInputObservationByKind: [ContinuousRawInputKind: Date] = [:]
private var hasObservedCurrentPinchRawInput = false

private func handleZoomGestureBegan() {
    didMutateCameraDuringZoomGesture = false
}

private func handleZoomGestureEnded() {
    guard didMutateCameraDuringZoomGesture else {
        return
    }

    scheduleAutosave(
        reason: "zoom canvas",
        updateKind: .viewStateOnly
    )
    didMutateCameraDuringZoomGesture = false
}

private func observePinchRawInputIfNeeded() {
    guard hasObservedCurrentPinchRawInput == false else {
        return
    }

    hasObservedCurrentPinchRawInput = true
    observeRawInput(
        .gesture(.pinch, source: .touch),
        sourceDescription: RawInputDeliverySource.pinchGesture.debugName
    )
}

private func finishPinchRawInputObservation() {
    hasObservedCurrentPinchRawInput = false
}

private func observeRawInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String
) {
    _ = handleCapturedInput(
        rawInput,
        sourceDescription: sourceDescription
    ) { _ in
        true
    }
}

private func observeContinuousRawInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    kind: ContinuousRawInputKind,
    now: Date = Date()
) {
    if let lastObservedAt = lastContinuousRawInputObservationByKind[kind],
       now.timeIntervalSince(lastObservedAt)
            < Self.continuousRawInputObservationInterval
    {
        return
    }

    lastContinuousRawInputObservationByKind[kind] = now
    observeRawInput(
        rawInput,
        sourceDescription: sourceDescription
    )
}
```

### 修改意图

这一步把 phase5 的“手势去噪”和“展示节流”显式固化到了 controller：

- `Scroll` 用时间窗口节流
- `Pinch` 每个手势 session 只记一次 indicator
- 观察 helper 本身不改变业务执行，只负责把事实事件送进 raw-input lane

## 修改五：`CanvasInputRoutingResolverTests.swift` 补齐 iOS phase5 新增的手势展示语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testTouchTapRoutesOnlyToTapIndicator() / testPointerScrollRoutesOnlyToScrollIndicator()
// 功能说明: 修改前测试只覆盖了 Tap 和 Scroll，还没有覆盖 Long Press 与 Pinch 的 indicator 语义。
func testTouchTapRoutesOnlyToTapIndicator() {
    let result = resolver.route(
        .gesture(.tap, source: .touch)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.tap))
    XCTAssertNil(result.interactionIntent)
}

func testPointerScrollRoutesOnlyToScrollIndicator() {
    let result = resolver.route(
        .gesture(.scroll, source: .pointer)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.scroll))
    XCTAssertNil(result.interactionIntent)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testTouchLongPressRoutesOnlyToLongPressIndicator() / testTouchPinchRoutesOnlyToPinchIndicator()
// 功能说明: 修改后新增 Long Press 与 Pinch 的 routing 测试，保证 iOS phase5 新接入的手势事实能稳定映射到 indicator lane。
func testTouchLongPressRoutesOnlyToLongPressIndicator() {
    let result = resolver.route(
        .gesture(.longPress, source: .touch)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.longPress))
    XCTAssertNil(result.interactionIntent)
}

func testTouchPinchRoutesOnlyToPinchIndicator() {
    let result = resolver.route(
        .gesture(.pinch, source: .touch)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.pinch))
    XCTAssertNil(result.interactionIntent)
}
```

### 修改意图

这一步把 phase5 新补的 iOS 手势语义先锁在 shared routing 测试层，避免后续再把 `Long Press / Pinch` 误退回“没有展示事件”的状态。

## 验证结果

`ReadLints` 针对以下范围检查后没有新增诊断：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / test
# 功能说明: 验证 phase5 当前代码在 iOS 与 macOS 目标下都能通过编译，并尝试运行最贴近本次改动的 targeted test。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS" build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" test -only-testing:"MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests"
```

实际结果：

- `iOS build` 通过
- `macOS build` 通过
- `targeted test` 未能执行到 `CanvasInputRoutingResolverTests` 本身，因为 test target 仍被仓库里已有编译错误阻塞

```bash
# 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift / MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
# 函数名/符号名: xcodebuild test 失败摘要
# 功能说明: 记录 targeted test 未能运行的真实阻塞原因；这些错误来自仓库里既有测试文件，不是本次 phase5 新增代码直接引入的编译错误。
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:320:20: error: extra argument 'updatedAt' in call
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:316:22: error: missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift:28:22: error: cannot assign to property: 'updatedAt' is a get-only property
```

## 本次 phase5 的实际完成面

已经完成：

- iOS `Command + C / V / Z / Shift + Command + Z` 接入 raw-input lane
- `Command + C` 的 indicator-only 路径
- `Tap / Long Press / Scroll / Pinch` 接入 indicator lane
- `Tap` 按 `pointer up` 的 `.pressed` 分支判定
- `Scroll` 的基础节流
- `Pinch` 的单次记录
- `Long Press / Pinch` 的 shared routing 测试补齐

明确还没做：

- `phase6` 的文本编辑 responder bridge
- `Command + C` 的真实业务 copy 执行链路
- 在 test target 既有阻塞解除前，真正跑通 `CanvasInputRoutingResolverTests`
