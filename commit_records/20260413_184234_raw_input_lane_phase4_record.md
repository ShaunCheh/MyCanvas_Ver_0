# 20260413_184234_raw_input_lane_phase4_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase4` macOS raw-input 接通”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 `4` 个业务代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 只包含上述 `4` 个已跟踪文件修改
- `git diff --stat -- <4 个关键文件>` 统计为：`4 files changed, 389 insertions(+), 86 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 `4` 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase5` 的 iOS / iPadOS raw input 接通
- `Command + C` 的真实业务 copy 执行链路补齐

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_184234`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase4 写记录前的真实工作区状态。
## feat/cross-platform-input-indicator
 M MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
 M MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计这次 phase4 关键文件的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"

# 实际输出:
#  .../Canvas/Input/CanvasInputRoutingResolver.swift  |  33 +-
#  .../Platform/macOS/macOSAppDelegate.swift          |  31 +-
#  .../Platform/macOS/macOSViewController.swift       | 367 ++++++++++++++++++---
#  .../CanvasInputRoutingResolverTests.swift          |  44 +++
#  4 files changed, 389 insertions(+), 86 deletions(-)
```

## 本次 phase4 的真实目标

这一步严格按计划接通 macOS raw input，而不是继续做 iOS：

1. 让 macOS 的 `Command + C / V / Z / Shift + Command + Z` 都先进入 shared raw-input routing。
2. 让 `Left Click / Right Click / Scroll / Zoom` 从 `macOSCanvasViewportView` 的既有回调进入 indicator lane。
3. 保持 `Command + C` 只做 indicator，不擅自绑定不存在的业务 copy command。
4. 解决键盘观察与标准 action 并存时的双发风险。
5. 把 `undo / redo` 从 AppDelegate 直接代执行收回到 controller / responder 链路。

## 修改一：`CanvasInputRoutingResolver.swift` 从只识别 paste 扩成同时识别 undo / redo

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver.routeKeyChord(_:) / CanvasKeyChord.isPasteKeyboardShortcut
// 功能说明: 修改前 shared routing 只把 Command + V 降成 transferEntry.pasteKeyboardShortcut，其它键盘组合键最多只产出 indicator。
private func routeKeyChord(
    _ chord: CanvasKeyChord
) -> CanvasInputRoutingResult {
    let interactionIntent: CanvasInteractionIntent?
    if chord.isPasteKeyboardShortcut {
        interactionIntent = .transferEntry(.pasteKeyboardShortcut)
    } else {
        interactionIntent = nil
    }

    return CanvasInputRoutingResult(
        indicatorEvent: .keyChord(chord),
        interactionIntent: interactionIntent
    )
}

private extension CanvasKeyChord {
    var isPasteKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("v")
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver.routeKeyChord(_:) / CanvasKeyChord.routedInteractionIntent / isUndoKeyboardShortcut / isRedoKeyboardShortcut
// 功能说明: 修改后 shared routing 除了 paste，还会把 Command + Z / Shift + Command + Z 分别降成 .command(.undo) / .command(.redo)。
private func routeKeyChord(
    _ chord: CanvasKeyChord
) -> CanvasInputRoutingResult {
    return CanvasInputRoutingResult(
        indicatorEvent: .keyChord(chord),
        interactionIntent: chord.routedInteractionIntent
    )
}

private extension CanvasKeyChord {
    var routedInteractionIntent: CanvasInteractionIntent? {
        if isPasteKeyboardShortcut {
            return .transferEntry(.pasteKeyboardShortcut)
        }

        if isUndoKeyboardShortcut {
            return .command(.undo)
        }

        if isRedoKeyboardShortcut {
            return .command(.redo)
        }

        return nil
    }

    var isPasteKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("v")
    }

    var isUndoKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("z")
    }

    var isRedoKeyboardShortcut: Bool {
        modifiers == [.command, .shift] && key.matchesCharacter("z")
    }
}
```

### 修改意图

这一步把 macOS phase4 所需的 `undo / redo` 快捷键语义先收敛进 shared 层，避免 controller 侧直接写死硬编码分流；同时保留 `Command + C` 为 indicator-only，遵守“只在已有业务语义存在时才降到 interaction lane”的边界。

## 修改二：`macOSAppDelegate.swift` 不再替 `undo / redo` 直接代执行

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名/符号名: macOSAppDelegate / handleUndoMenuItem(_:) / handleRedoMenuItem(_:) / validateMenuItem(_:) / makeEditMenuItem()
// 功能说明: 修改前 Undo / Redo 菜单由 AppDelegate 持有 target，并直接调用 currentCanvasViewController.performCommand(withID:)，绕开 controller 自身的 raw-input 与 interaction gate 收口。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var rootViewController: macOSAppRootViewController?

    @objc
    private func handleUndoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performCommand(withID: .undo)
    }

    @objc
    private func handleRedoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performCommand(withID: .redo)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(handleUndoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canPerformCommand(.undo) ?? false
        case #selector(handleRedoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canPerformCommand(.redo) ?? false
        default:
            return true
        }
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(handleUndoMenuItem(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = self

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(handleRedoMenuItem(_:)),
            keyEquivalent: "Z"
        )
        redoItem.target = self
        // ... 其余菜单项保持不变 ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
// 函数名/符号名: macOSAppDelegate / makeEditMenuItem()
// 功能说明: 修改后 AppDelegate 不再直接代执行 Undo / Redo，而是把菜单 action 交回 macOSViewController 的 responder/controller 链路。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    private func makeEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(macOSViewController.undo(_:)),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(macOSViewController.redo(_:)),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(macOSViewController.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = .command
        editMenu.addItem(pasteItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }
}
```

### 修改意图

这一步把 `undo / redo` 从 AppDelegate 的“越级代执行”收回到了 controller，避免业务执行链路和 raw-input / interaction gate 继续分叉；同时也让 text editor / canvas controller 能继续依赖 responder 机制分发。

## 修改三：`macOSViewController.swift` 新增 `undo / redo` action，并把菜单校验并入 controller

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: validateUserInterfaceItem(_:) / paste(_:)
// 功能说明: 修改前 controller 只校验 Paste 菜单，也没有 undo(_:) / redo(_:) 这两个菜单 action 收口点。
func validateUserInterfaceItem(
    _ item: any NSValidatedUserInterfaceItem
) -> Bool {
    switch item.action {
    case #selector(macOSViewController.paste(_:)):
        return canTransferContent(
            from: .general,
            entry: resolvedPasteTransferEntryIntent()
        )
    default:
        return true
    }
}

@objc
func paste(_ sender: Any?) {
    switch resolvedPasteTransferEntryIntent() {
    case .pasteKeyboardShortcut:
        handleCapturedInput(
            makePasteKeyboardShortcutRawInput(),
            sourceDescription: TransferEntryDeliverySource.macOSPasteAction.debugName
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
    case .pasteMenu:
        // ... 其余逻辑保持不变 ...
        return
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: validateUserInterfaceItem(_:) / undo(_:) / redo(_:) / paste(_:)
// 功能说明: 修改后 controller 统一接住 Undo / Redo / Paste 菜单与快捷键；键盘路径优先走 raw-input routing，非键盘路径走 command/transfer interaction gate。
func validateUserInterfaceItem(
    _ item: any NSValidatedUserInterfaceItem
) -> Bool {
    switch item.action {
    case #selector(macOSViewController.undo(_:)):
        return canPerformCommand(.undo)
    case #selector(macOSViewController.redo(_:)):
        return canPerformCommand(.redo)
    case #selector(macOSViewController.paste(_:)):
        return canTransferContent(
            from: .general,
            entry: resolvedPasteTransferEntryIntent()
        )
    default:
        return true
    }
}

@objc
func undo(_ sender: Any?) {
    let rawInput = makeUndoKeyboardShortcutRawInput()
    if consumeObservedKeyboardShortcut(rawInput) {
        performCommand(.undo)
        return
    }

    if isCurrentKeyboardShortcut(rawInput) {
        _ = handleCapturedInput(
            rawInput,
            sourceDescription: RawInputDeliverySource.undoAction.debugName
        ) { routingResult in
            guard routingResult.interactionIntent == .command(.undo) else {
                return false
            }

            performCommand(.undo)
            return true
        }
        return
    }

    _ = handleCommandAttempt(
        .undo,
        sourceDescription: RawInputDeliverySource.undoAction.debugName
    ) {
        performCommand(.undo)
        return true
    }
}

@objc
func redo(_ sender: Any?) {
    let rawInput = makeRedoKeyboardShortcutRawInput()
    // ... 与 undo 同结构，降到 .command(.redo) 后再执行 ...
}

@objc
func paste(_ sender: Any?) {
    let rawInput = makePasteKeyboardShortcutRawInput()
    if consumeObservedKeyboardShortcut(rawInput) {
        handlePasteRequest()
        return
    }

    switch resolvedPasteTransferEntryIntent() {
    case .pasteKeyboardShortcut:
        handleCapturedInput(
            rawInput,
            sourceDescription: RawInputDeliverySource.pasteAction.debugName
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
    case .pasteMenu:
        // ... 其余逻辑保持不变 ...
        return
    }
}
```

### 修改意图

这一步把 `undo / redo / paste` 的菜单入口与键盘入口都收敛到 controller 内部：键盘先走 raw-input routing，菜单仍保持原有 command / transfer gate，从而统一验证、日志和 indicator 出口。

## 修改四：`macOSViewController.swift` 把 viewport 的 click / scroll / zoom 接进 raw-input lane

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupCanvasViewport()
// 功能说明: 修改前 viewport 回调只直连既有交互逻辑，Left Click / Right Click / Scroll / Zoom 并没有进入 shared raw-input / indicator lane。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handlePrimaryPointerDown(at: location)
    }

    canvasViewportView.onSecondaryClick = { [weak self] location in
        self?.handleSecondaryClick(at: location)
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
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupCanvasViewport()
// 功能说明: 修改后 viewport 的 primary click、secondary click、scroll、zoom 都会先投递 raw-input；Scroll / Zoom 额外做了节流，避免连续手势把胶囊栈刷爆。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.observeRawInput(
            .pointerClick(.primary),
            sourceDescription: RawInputDeliverySource.primaryClick.debugName
        )
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handlePrimaryPointerDown(at: location)
    }

    canvasViewportView.onSecondaryClick = { [weak self] location in
        self?.observeRawInput(
            .pointerClick(.secondary),
            sourceDescription: RawInputDeliverySource.secondaryClick.debugName
        )
        self?.handleSecondaryClick(at: location)
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
        self?.observeContinuousRawInput(
            .gesture(.zoom, source: .pointer),
            sourceDescription: RawInputDeliverySource.zoomGesture.debugName,
            kind: .zoom
        )
        guard self?.isTransitionInteractionFrozen == false else {
            return
        }
        self?.handleZoom(scaleDelta, around: anchor)
    }
}
```

### 修改意图

这一步把 macOS phase4 要求的桌面输入事实真正接入到了 shared 总线上，同时没有破坏既有画布交互执行路径：raw-input lane 负责观察与展示，原业务逻辑继续负责真正的 pointer / camera 更新。

## 修改五：`macOSViewController.swift` 用统一键盘观察器替换只补 Paste 的 supplemental monitor，并加入去重

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: shouldEnableSupplementalKeyboardCapture() / updateSupplementalKeyboardCaptureIfNeeded() / handleSupplementalKeyboardCapture(_:) / isPasteKeyboardShortcutEvent(_:)
// 功能说明: 修改前本地键盘 monitor 只在 readingMode 下补 Command + V，用于拦截被 block 的 pasteKeyboardShortcut；并不能统一观察 C / Z / Shift+Z，也没有键盘观察与 action 执行的去重机制。
private func shouldEnableSupplementalKeyboardCapture() -> Bool {
    guard
        view.window != nil,
        view.isHiddenOrHasHiddenAncestor == false
    else {
        return false
    }

    switch transferEntryDecision(for: .pasteKeyboardShortcut) {
    case .block(
        reason: .readingMode,
        feedback: .shakeWorkspaceModeButton
    ):
        return true
    case .allow,
         .block:
        return false
    }
}

private func updateSupplementalKeyboardCaptureIfNeeded() {
    guard shouldEnableSupplementalKeyboardCapture() else {
        removeSupplementalKeyboardCaptureIfNeeded()
        return
    }

    guard supplementalKeyboardCaptureMonitor == nil else {
        return
    }

    supplementalKeyboardCaptureMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown]
    ) { [weak self] event in
        self?.handleSupplementalKeyboardCapture(event) ?? event
    }
}

private func handleSupplementalKeyboardCapture(
    _ event: NSEvent
) -> NSEvent? {
    guard
        shouldEnableSupplementalKeyboardCapture(),
        let window = view.window,
        event.window === window,
        isPasteKeyboardShortcutEvent(event)
    else {
        return event
    }

    guard case .block = transferEntryDecision(for: .pasteKeyboardShortcut) else {
        return event
    }

    _ = handleCapturedInput(
        makePasteKeyboardShortcutRawInput(),
        sourceDescription: "macOSLocalKeyMonitor"
    ) { _ in
        false
    }
    return nil
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: observeRawInput(...) / observeContinuousRawInput(...) / handleCommandAttempt(...) / updateKeyboardShortcutObservationIfNeeded() / handleObservedKeyboardShortcut(_:) / observedKeyboardShortcutRawInput(from:) / rememberObservedKeyboardShortcut(_:) / consumeObservedKeyboardShortcut(_:)
// 功能说明: 修改后统一键盘观察器覆盖 Command + C / V / Z / Shift + Command + Z；观察到快捷键时先走 raw-input routing，再用短时 token 避免 action 阶段双发 indicator。
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

private func handleCommandAttempt(
    _ commandID: CanvasCommandID,
    sourceDescription: String,
    continueIfAllowed: () -> Bool
) -> Bool {
    handleInteractionAttempt(
        .command(commandID),
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed()
    }
}

private func updateKeyboardShortcutObservationIfNeeded() {
    guard shouldEnableKeyboardShortcutObservation() else {
        removeKeyboardShortcutObservationIfNeeded()
        return
    }

    guard keyboardShortcutObservationMonitor == nil else {
        return
    }

    keyboardShortcutObservationMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown]
    ) { [weak self] event in
        self?.handleObservedKeyboardShortcut(event) ?? event
    }
}

private func handleObservedKeyboardShortcut(
    _ event: NSEvent
) -> NSEvent? {
    guard
        shouldEnableKeyboardShortcutObservation(),
        let window = view.window,
        event.window === window,
        let rawInput = observedKeyboardShortcutRawInput(from: event)
    else {
        return event
    }

    let shouldContinue = handleCapturedInput(
        rawInput,
        sourceDescription: RawInputDeliverySource.localKeyMonitor.debugName
    ) { _ in
        true
    }

    if shouldContinue,
       inputRoutingResolver.route(rawInput).interactionIntent != nil
    {
        rememberObservedKeyboardShortcut(rawInput)
    }

    return shouldContinue ? event : nil
}

private func observedKeyboardShortcutRawInput(
    from event: NSEvent?
) -> CanvasRawInputIntent? {
    guard
        let event,
        event.type == .keyDown,
        event.isARepeat == false
    else {
        return nil
    }

    let relevantFlags = event.modifierFlags.intersection(
        [.command, .control, .option, .shift]
    )
    guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
        return nil
    }

    switch (relevantFlags, characters) {
    case ([.command], "c"):
        return makeCopyKeyboardShortcutRawInput()
    case ([.command], "v"):
        return makePasteKeyboardShortcutRawInput()
    case ([.command], "z"):
        return makeUndoKeyboardShortcutRawInput()
    case ([.command, .shift], "z"):
        return makeRedoKeyboardShortcutRawInput()
    default:
        return nil
    }
}

private func rememberObservedKeyboardShortcut(
    _ rawInput: CanvasRawInputIntent,
    now: Date = Date()
) {
    pruneObservedKeyboardShortcuts(asOf: now)
    observedKeyboardShortcuts.append(
        ObservedKeyboardShortcut(
            rawInput: rawInput,
            observedAt: now
        )
    )
}

private func consumeObservedKeyboardShortcut(
    _ rawInput: CanvasRawInputIntent,
    now: Date = Date()
) -> Bool {
    pruneObservedKeyboardShortcuts(asOf: now)
    guard let index = observedKeyboardShortcuts.firstIndex(where: {
        $0.rawInput == rawInput
    }) else {
        return false
    }

    observedKeyboardShortcuts.remove(at: index)
    return true
}
```

### 修改意图

这一步解决的是 phase4 的根因问题，而不是简单多绑几个回调：

- 不再把键盘观察限制在 “readingMode 下的 paste 补洞”
- 所有高价值快捷键统一经过一个观察口
- 观察阶段先负责 indicator / interaction routing
- action 阶段再通过短时 token 复用同一次键盘事实，避免 indicator 双发

## 修改六：`CanvasInputRoutingResolverTests.swift` 补齐 undo / redo 的 shared routing 测试

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: CanvasInputRoutingResolverTests
// 功能说明: 修改前测试只覆盖 paste、copy、leftClick、tap、scroll，还没有覆盖 undo / redo 快捷键降到 .command 的 shared routing。
func testCopyKeyboardShortcutRoutesOnlyToIndicatorEvent() {
    let rawInput = CanvasRawInputIntent.keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("c")
        )
    )

    let result = resolver.route(rawInput)

    XCTAssertEqual(
        result.indicatorEvent,
        .keyChord(
            CanvasKeyChord(
                modifiers: [.command],
                key: .character("c")
            )
        )
    )
    XCTAssertNil(result.interactionIntent)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testUndoKeyboardShortcutRoutesToIndicatorAndUndoCommandIntent() / testRedoKeyboardShortcutRoutesToIndicatorAndRedoCommandIntent()
// 功能说明: 修改后新增 undo / redo 的 shared routing 测试，保证 Command + Z / Shift + Command + Z 的业务意图归一不会回退。
func testUndoKeyboardShortcutRoutesToIndicatorAndUndoCommandIntent() {
    let rawInput = CanvasRawInputIntent.keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("z")
        )
    )

    let result = resolver.route(rawInput)

    XCTAssertEqual(
        result.indicatorEvent,
        .keyChord(
            CanvasKeyChord(
                modifiers: [.command],
                key: .character("z")
            )
        )
    )
    XCTAssertEqual(result.interactionIntent, .command(.undo))
}

func testRedoKeyboardShortcutRoutesToIndicatorAndRedoCommandIntent() {
    let rawInput = CanvasRawInputIntent.keyChord(
        CanvasKeyChord(
            modifiers: [.command, .shift],
            key: .character("z")
        )
    )

    let result = resolver.route(rawInput)

    XCTAssertEqual(
        result.indicatorEvent,
        .keyChord(
            CanvasKeyChord(
                modifiers: [.command, .shift],
                key: .character("z")
            )
        )
    )
    XCTAssertEqual(result.interactionIntent, .command(.redo))
}
```

### 修改意图

这一步把 phase4 新增的 shared routing 语义先锁在纯测试层，防止未来再把 `undo / redo` 误退回 indicator-only。

## 验证结果

`ReadLints` 针对以下范围检查后没有新增诊断：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / test
# 功能说明: 验证 phase4 当前代码在双端构建下通过，并尝试运行最贴近本次改动的 targeted test。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS" build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" test -only-testing:"MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests"
```

实际结果：

- `macOS build` 通过
- `iOS build` 通过
- `targeted test` 未能执行到 `CanvasInputRoutingResolverTests` 本身，因为 test target 被仓库里已有编译错误阻塞

```bash
# 文件路径: MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift / MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
# 函数名/符号名: xcodebuild test 失败摘要
# 功能说明: 记录 targeted test 未能运行的真实阻塞原因；这些错误来自仓库里既有测试文件，不是本次 phase4 新增代码直接引入的编译错误。
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift:28:22: error: cannot assign to property: 'updatedAt' is a get-only property
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:320:20: error: extra argument 'updatedAt' in call
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift:316:22: error: missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
```

## 本次 phase4 的实际完成面

已经完成：

- shared routing 支持 `Command + Z / Shift + Command + Z`
- macOS `Undo / Redo / Paste` 菜单回到 controller / responder 路径
- macOS 键盘观察器统一覆盖 `Command + C / V / Z / Shift + Command + Z`
- keyboard observe 与 action execute 间的短时去重
- macOS `Left Click / Right Click / Scroll / Zoom` 接入 raw-input lane
- `Scroll / Zoom` 的基础节流
- `undo / redo` shared routing 测试补齐

明确还没做：

- `Command + C` 的真实业务 copy 执行链路
- `phase5` 的 iOS / iPadOS raw-input 接通
- 在 test target 既有阻塞解除之前，真正跑通 `CanvasInputRoutingResolverTests`
