# 20260413_191510_raw_input_lane_phase6_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase6` 文本编辑 responder bridge”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 `3` 个业务代码文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch -- <3 个关键文件>` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 只包含上述 `3` 个已跟踪文件修改
- `git diff --stat -- <3 个关键文件>` 统计为：`3 files changed, 188 insertions(+), 2 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 `3` 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase7` 的 business intent 迁移
- 文本编辑态的逐字符输入可视化
- IME 组合态建模

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_191510`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase6 写记录前的真实工作区状态。
git status --short --branch -- \
  "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
#  M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
#  M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计这次 phase6 关键文件的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

# 实际输出:
#  .../Canvas/iOSCanvasTextEditorOverlayView.swift    | 104 ++++++++++++++++++++-
#  .../Platform/iOS/iOSViewController.swift           |  62 ++++++++++++
#  .../Platform/macOS/macOSViewController.swift       |  24 +++++
#  3 files changed, 188 insertions(+), 2 deletions(-)
```

## 本次 phase6 的真实目标

这一步严格按计划补“文本编辑 responder 桥”，不是继续扩更多业务意图：

1. 当 `iOS` / `macOS` 进入文本编辑态、controller 不再是 `first responder` 时，`Command + C / V / Z / Shift + Command + Z` 仍然能显示输入胶囊。
2. 不能破坏现有文本编辑行为，文本本身的 `copy / paste / undo / redo` 仍要由对应文本视图继续处理。
3. 文本编辑态首版只镜像快捷键，不显示每个字符输入，不碰 IME 组合态。
4. `macOS` 优先复用现有 local monitor；`iOS` 在 `UITextView` 一侧补 forwarding。

## 修改一：`iOSCanvasTextEditorOverlayView.swift` 把普通 `UITextView` 升级为“可观察快捷键”的文本视图

### 修改前

`iOS` 文本编辑 overlay 里只有普通 `UITextView`，没有自己的快捷键观察能力。进入文本编辑态后，controller 不再是当前 responder，挂在 controller 上的 `keyCommands` 就不再是最稳的入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
// 函数名/符号名: iOSCanvasTextEditorOverlayView.textView
// 功能说明: 修改前 overlay 只持有普通 UITextView，不负责观察文本编辑态的硬件键盘快捷键。
let textView: UITextView = {
    let textView = UITextView()
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 17)
    textView.textColor = .label
    textView.tintColor = .systemBlue
    textView.autocorrectionType = .yes
    textView.autocapitalizationType = .sentences
    textView.spellCheckingType = .yes
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(
        top: 8,
        left: 4,
        bottom: 8,
        right: 4
    )
    textView.accessibilityLabel = "Text editor"
    return textView
}()
```

### 修改后

现在 overlay 把 `textView` 换成 `iOSCanvasInputObservingTextView`。这个子类只做一件事：在文本编辑态观察首批快捷键，并在保留文本自身 `copy / paste / undo / redo` 行为的同时，把“观察到的快捷键”回抛给 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift
// 函数名/符号名: iOSCanvasTextEditorObservedShortcut / iOSCanvasInputObservingTextView.keyCommands / handleObservedPasteKeyCommand(_:)
// 功能说明: 修改后 UITextView 自己观察 Command + C / V / Z / Shift + Command + Z，并在继续执行文本编辑动作的同时把快捷键信号抛给外部。
enum iOSCanvasTextEditorObservedShortcut {
    case copy
    case paste
    case undo
    case redo
}

let textView: iOSCanvasInputObservingTextView = {
    let textView = iOSCanvasInputObservingTextView()
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 17)
    textView.textColor = .label
    textView.tintColor = .systemBlue
    textView.accessibilityLabel = "Text editor"
    return textView
}()

var onObservedShortcut: ((iOSCanvasTextEditorObservedShortcut) -> Void)? {
    get { textView.onObservedShortcut }
    set { textView.onObservedShortcut = newValue }
}

final class iOSCanvasInputObservingTextView: UITextView {
    var onObservedShortcut: ((iOSCanvasTextEditorObservedShortcut) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let observedCommands = [
            makeObservedKeyCommand(
                input: "c",
                modifierFlags: [.command],
                action: #selector(handleObservedCopyKeyCommand(_:)),
                discoverabilityTitle: "Copy"
            ),
            makeObservedKeyCommand(
                input: "v",
                modifierFlags: [.command],
                action: #selector(handleObservedPasteKeyCommand(_:)),
                discoverabilityTitle: "Paste"
            ),
            makeObservedKeyCommand(
                input: "z",
                modifierFlags: [.command],
                action: #selector(handleObservedUndoKeyCommand(_:)),
                discoverabilityTitle: "Undo"
            ),
            makeObservedKeyCommand(
                input: "z",
                modifierFlags: [.command, .shift],
                action: #selector(handleObservedRedoKeyCommand(_:)),
                discoverabilityTitle: "Redo"
            )
        ]

        let observedSignatures = Set(observedCommands.map(CommandSignature.init))
        let inheritedCommands = (super.keyCommands ?? []).filter { command in
            observedSignatures.contains(CommandSignature(command)) == false
        }
        return observedCommands + inheritedCommands
    }

    @objc
    private func handleObservedPasteKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.paste)
        paste(sender)
    }

    @objc
    private func handleObservedUndoKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.undo)
        undoManager?.undo()
    }
}
```

这一步的关键点不是“把文本编辑 shortcut 真正接到 canvas 业务逻辑”，而是把当前真正持有 responder 的 `UITextView` 变成一个快捷键观察源。

## 修改二：`iOSViewController.swift` 接上文本编辑 bridge，并把编辑态快捷键限制为 indicator-only

### 修改前

`iOSViewController` 之前只是把 overlay 的 `textView.delegate` 接到 controller，自身没有从文本编辑 overlay 收到快捷键观察事件的通路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupTextEditorOverlay()
// 功能说明: 修改前 controller 只管理文本内容同步与 delegate，不接收文本编辑态快捷键信号。
private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    syncTextEditorPresentation()
}
```

### 修改后

controller 现在在 `setupTextEditorOverlay()` 里挂上 `onObservedShortcut`，再把编辑态观察到的快捷键翻译成既有 `CanvasRawInputIntent`。但这里不复用 `handleCapturedInput(...)`，而是单独走 `observeIndicatorOnlyRawInput(...)`，只记录 indicator，不把文本编辑里的 `paste / undo / redo` 误下沉成 canvas 的 business intent。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupTextEditorOverlay() / handleObservedTextEditorShortcut(_:) / observeIndicatorOnlyRawInput(...)
// 功能说明: 修改后 controller 接收文本编辑态快捷键桥接事件，把它们翻译为 raw input，并只记录 indicator lane。
private func setupTextEditorOverlay() {
    textEditorOverlayView.textView.delegate = self
    textEditorOverlayView.onObservedShortcut = { [weak self] shortcut in
        self?.handleObservedTextEditorShortcut(shortcut)
    }
    syncTextEditorPresentation()
}

private func handleObservedTextEditorShortcut(
    _ shortcut: iOSCanvasTextEditorObservedShortcut
) {
    let rawInput: CanvasRawInputIntent
    let sourceDescription: String

    switch shortcut {
    case .copy:
        rawInput = makeCopyKeyboardShortcutRawInput()
        sourceDescription =
            RawInputDeliverySource.textEditorCopyKeyCommand.debugName
    case .paste:
        rawInput = makePasteKeyboardShortcutRawInput()
        sourceDescription =
            RawInputDeliverySource.textEditorPasteKeyCommand.debugName
    case .undo:
        rawInput = makeUndoKeyboardShortcutRawInput()
        sourceDescription =
            RawInputDeliverySource.textEditorUndoKeyCommand.debugName
    case .redo:
        rawInput = makeRedoKeyboardShortcutRawInput()
        sourceDescription =
            RawInputDeliverySource.textEditorRedoKeyCommand.debugName
    }

    observeIndicatorOnlyRawInput(
        rawInput,
        sourceDescription: sourceDescription
    )
}

private func observeIndicatorOnlyRawInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String
) {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    if let indicatorEvent = routingResult.indicatorEvent {
        inputIndicatorHostView.record(event: indicatorEvent)
    }
}
```

这里的语义变化是 phase6 的根因修复：文本编辑态的快捷键现在仍然进入 raw-input 命名体系，但只镜像到 indicator lane，不再借道 canvas 的 interaction gate。

## 修改三：`macOSViewController.swift` 在文本编辑 responder 生效时只观察 indicator，不再继续下沉 interaction lane

### 修改前

`macOS` 已经有 local monitor，但此前它不区分当前 `firstResponder` 是否已经切到 `textEditorOverlayView.textView`。因此，文本编辑态下观测到 `Command + V / Z` 时，仍会统一走 `handleCapturedInput(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleObservedKeyboardShortcut(_:)
// 功能说明: 修改前 local monitor 观察到快捷键后，不区分当前 responder 是否为文本编辑器，统一进入 handleCapturedInput。
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
```

### 修改后

现在 `macOS` 在 local monitor 里先判断 `window.firstResponder === textEditorOverlayView.textView`。如果已经进入文本编辑 responder，就只调用 `observeIndicatorOnlyRawInput(...)` 记录胶囊，然后直接把原始 `event` 还给 `NSTextView` 自己处理，不再进入 interaction gate，也不再写入快捷键去重 token。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: observeIndicatorOnlyRawInput(...) / handleObservedKeyboardShortcut(_:)
// 功能说明: 修改后当 first responder 已切到文本编辑器时，local monitor 只镜像 indicator，不再把文本编辑快捷键当成 canvas 业务意图。
private func observeIndicatorOnlyRawInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String
) {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    if let indicatorEvent = routingResult.indicatorEvent {
        inputIndicatorHostView.record(event: indicatorEvent)
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

    if window.firstResponder === textEditorOverlayView.textView {
        observeIndicatorOnlyRawInput(
            rawInput,
            sourceDescription: RawInputDeliverySource.localKeyMonitor.debugName
        )
        return event
    }

    let shouldContinue = handleCapturedInput(
        rawInput,
        sourceDescription: RawInputDeliverySource.localKeyMonitor.debugName
    ) { _ in
        true
    }

    return shouldContinue ? event : nil
}
```

这样 `macOS` 继续满足 phase6 计划里的“优先复用 monitor、尽量不侵入 `NSTextView`”边界，同时避免文本编辑态把 shortcut 误判成 canvas 层的业务动作。

## 验证结果

`ReadLints` 检查以下文件，无新增诊断：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase6 的 macOS Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase6-macos"

# 实际结果: BUILD SUCCEEDED
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase6 的 iOS Simulator Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase6-ios"

# 实际结果: BUILD SUCCEEDED
```

本次未额外新增自动化测试文件；原因是这一步主要修的是 responder bridge 和平台事件转发边界，没有新增 shared routing case，也没有引入新的纯模型分支。

## 本次保持的边界

1. 文本编辑态仍然只显示 `Command + C / V / Z / Shift + Command + Z`，不显示普通字符输入。
2. 没有接入 IME 组合态，也没有尝试做文本流级别的输入可视化。
3. `iOS` 文本编辑态的 `copy / paste / undo / redo` 继续由 `UITextView` / `undoManager` 自己执行，只把快捷键镜像到 indicator。
4. `macOS` 文本编辑态继续复用 local monitor，不侵入 `NSTextView` 子类。
5. `phase7` 里才会继续推进更多 interaction intent 的迁移，这次没有扩大范围。
