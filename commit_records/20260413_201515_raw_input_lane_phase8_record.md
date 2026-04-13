# 20260413_201515_raw_input_lane_phase8_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase8` 收口与测试补齐”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与测试结果整理，不包含原始 `git diff` 文本。

本次共涉及 `6` 个业务代码/测试文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift`

其中：

- 前 `4` 个文件是已跟踪文件修改
- 后 `2` 个文件是本次新增、当前仍未跟踪的测试文件

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch -- <6 个关键文件>` 显示当前位于 `feat/cross-platform-input-indicator`
- `git diff --stat -- <4 个已跟踪文件>` 统计为：`4 files changed, 155 insertions(+), 245 deletions(-)`
- `git status` 同时显示 `CanvasInputIndicatorFormatterTests.swift` 与 `CanvasInputIndicatorQueueTests.swift` 为新增未跟踪文件，因此它们不包含在上述 `git diff --stat` 的统计里
- 本记录文件是随后新增的说明材料，不属于上述 `6` 个业务代码/测试文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase7` 的 `secondary click / long press -> contextMenuRequest` 迁移细节复述
- `BoardVideoStorageTests.swift` 既有测试错误的修复
- 计划里手工回归矩阵的逐项实机执行

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_201515`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase8 写记录前的真实工作区状态。
git status --short --branch -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift"

# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
#  M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
#  M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
#  M MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
# ?? MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift
# ?? MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计这次 phase8 已跟踪关键文件的真实改动规模；未跟踪新文件不在此统计内。
git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"

# 实际输出:
#  .../Canvas/Input/CanvasRawInputIntent.swift        |  64 ++++++++++
#  .../Platform/iOS/iOSViewController.swift           | 123 ++++++------------
#  .../Platform/macOS/macOSViewController.swift       | 139 ++++++---------------
#  .../CanvasInputRoutingResolverTests.swift          |  74 +++--------
#  4 files changed, 155 insertions(+), 245 deletions(-)
```

## 本次 phase8 的真实目标

这一步不是再扩新的输入语义，而是把迁移期残留的重复入口和测试空白收口：

1. 把跨平台重复的 raw-input 构造 helper 从 controller 收到 shared 层。
2. 把 `iOS/macOS controller` 中重复的“route + log + record indicator”旁路收成单一入口。
3. 删除 phase4~7 期间残留的 `ContextMenuInput` 大段调试日志和 `observeIndicatorOnlyRawInput(...)` 这类迁移期 helper。
4. 补齐计划里点名的 `CanvasInputIndicatorFormatterTests` 和 `CanvasInputIndicatorQueueTests`。
5. 让 `CanvasInputRoutingResolverTests` 也直接复用 shared raw-input 命名，避免测试里维护第三套输入构造逻辑。

## 修改一：`CanvasRawInputIntent.swift` 上提 shared raw-input factory，消除 controller 内重复构造

### 修改前

shared 输入模型里只有 case 与 `debugName`，但 `Command + C / V / Z / Shift + Z`、`tap / longPress / scroll / pinch / zoom`、`primary / secondary click` 的构造 helper 分散在 `iOS/macOS controller` 里各写一份。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasRawInputIntent
// 功能说明: 修改前 shared 层只有原始输入枚举本体，没有跨平台复用的静态 factory。
enum CanvasRawInputIntent: Equatable, Sendable {
    case keyChord(CanvasKeyChord)
    case pointerClick(CanvasPointerButton)
    case gesture(
        CanvasRawInputGesture,
        source: CanvasRawInputSource
    )

    var source: CanvasRawInputSource {
        switch self {
        case .keyChord:
            return .keyboard
        case .pointerClick:
            return .pointer
        case .gesture(_, let source):
            return source
        }
    }

    var debugName: String {
        switch self {
        case .keyChord(let chord):
            return "keyChord.\(chord.debugName)"
        case .pointerClick(let button):
            return "pointerClick.\(button.debugName)"
        case .gesture(let gesture, let source):
            return "gesture.\(gesture.debugName).\(source.debugName)"
        }
    }
}
```

### 修改后

现在 shared 层直接提供统一命名的 `CanvasKeyChord` 和 `CanvasRawInputIntent` factory，controller 和测试都可以直接引用：

- `.copyKeyboardShortcut / .pasteKeyboardShortcut / .undoKeyboardShortcut / .redoKeyboardShortcut`
- `.primaryPointerClick / .secondaryPointerClick`
- `.touchTapGesture / .touchLongPressGesture / .pointerScrollGesture / .touchPinchGesture / .pointerZoomGesture`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasKeyChord.copyKeyboardShortcut / CanvasRawInputIntent.copyKeyboardShortcut / CanvasRawInputIntent.pointerScrollGesture
// 功能说明: 修改后把跨平台重复的输入构造 helper 上提到 shared 层，controller 与测试统一复用同一套 raw-input 命名。
extension CanvasKeyChord {
    static var copyKeyboardShortcut: CanvasKeyChord {
        CanvasKeyChord(modifiers: [.command], key: .character("c"))
    }

    static var pasteKeyboardShortcut: CanvasKeyChord {
        CanvasKeyChord(modifiers: [.command], key: .character("v"))
    }

    static var undoKeyboardShortcut: CanvasKeyChord {
        CanvasKeyChord(modifiers: [.command], key: .character("z"))
    }

    static var redoKeyboardShortcut: CanvasKeyChord {
        CanvasKeyChord(modifiers: [.command, .shift], key: .character("z"))
    }
}

extension CanvasRawInputIntent {
    static var copyKeyboardShortcut: CanvasRawInputIntent {
        .keyChord(.copyKeyboardShortcut)
    }

    static var pasteKeyboardShortcut: CanvasRawInputIntent {
        .keyChord(.pasteKeyboardShortcut)
    }

    static var undoKeyboardShortcut: CanvasRawInputIntent {
        .keyChord(.undoKeyboardShortcut)
    }

    static var redoKeyboardShortcut: CanvasRawInputIntent {
        .keyChord(.redoKeyboardShortcut)
    }

    static var primaryPointerClick: CanvasRawInputIntent {
        .pointerClick(.primary)
    }

    static var secondaryPointerClick: CanvasRawInputIntent {
        .pointerClick(.secondary)
    }

    static var touchTapGesture: CanvasRawInputIntent {
        .gesture(.tap, source: .touch)
    }

    static var touchLongPressGesture: CanvasRawInputIntent {
        .gesture(.longPress, source: .touch)
    }

    static var pointerScrollGesture: CanvasRawInputIntent {
        .gesture(.scroll, source: .pointer)
    }

    static var touchPinchGesture: CanvasRawInputIntent {
        .gesture(.pinch, source: .touch)
    }

    static var pointerZoomGesture: CanvasRawInputIntent {
        .gesture(.zoom, source: .pointer)
    }
}
```

## 修改二：`iOSViewController.swift` 删除本地 raw-input helper 与 indicator-only 旁路，统一走 `resolveCapturedInputRouting(...)`

### 修改前

`iOS` controller 同时维护了三类迁移期残留：

1. 一组本地 `makeCopyKeyboardShortcutRawInput()` / `makePasteKeyboardShortcutRawInput()` 等 helper
2. 文本编辑 bridge 专用的 `observeIndicatorOnlyRawInput(...)`
3. `handleCapturedInput(...)` 里又单独写一遍 `route + log + record indicator`

这导致“同一条 captured input 先 route 再 log 再 record indicator”的逻辑在 controller 内有两份实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makeCopyKeyboardShortcutRawInput() / handleObservedTextEditorShortcut(_:) / observeIndicatorOnlyRawInput(...)
// 功能说明: 修改前 iOS controller 既保留本地 raw-input helper，又保留 indicator-only 旁路，route/log/record indicator 的逻辑存在重复实现。
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

### 修改后

`iOS` 现在：

- 全面改用 shared factory，例如 `.copyKeyboardShortcut`、`.touchTapGesture`、`.pointerScrollGesture`
- 文本编辑 bridge 不再走单独的 indicator-only helper，而是直接调用 `resolveCapturedInputRouting(...)`
- `handleCapturedInput(...)` 和文本编辑 bridge 都复用同一份 `resolveCapturedInputRouting(...) + recordCapturedInputIndicator(...)`
- phase7 临时留下的 `"[Canvas iOS][ContextMenuInput]"` 大段日志也被删掉

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleObservedTextEditorShortcut(_:) / handleCopyKeyCommand(_:) / resolveCapturedInputRouting(...) / recordCapturedInputIndicator(...)
// 功能说明: 修改后 iOS controller 不再维护本地 raw-input helper 与 indicator-only 旁路，所有 captured input 都复用同一条 route/log/record indicator 路径。
private func handleObservedTextEditorShortcut(
    _ shortcut: iOSCanvasTextEditorObservedShortcut
) {
    let rawInput: CanvasRawInputIntent
    let sourceDescription: String

    switch shortcut {
    case .copy:
        rawInput = .copyKeyboardShortcut
        sourceDescription =
            RawInputDeliverySource.textEditorCopyKeyCommand.debugName
    case .paste:
        rawInput = .pasteKeyboardShortcut
        sourceDescription =
            RawInputDeliverySource.textEditorPasteKeyCommand.debugName
    case .undo:
        rawInput = .undoKeyboardShortcut
        sourceDescription =
            RawInputDeliverySource.textEditorUndoKeyCommand.debugName
    case .redo:
        rawInput = .redoKeyboardShortcut
        sourceDescription =
            RawInputDeliverySource.textEditorRedoKeyCommand.debugName
    }

    _ = resolveCapturedInputRouting(
        rawInput,
        sourceDescription: sourceDescription
    )
}

@objc
private func handleCopyKeyCommand(_ sender: UIKeyCommand) {
    observeRawInput(
        .copyKeyboardShortcut,
        sourceDescription: RawInputDeliverySource.copyKeyCommand.debugName
    )
}

@discardableResult
private func resolveCapturedInputRouting(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String
) -> CanvasInputRoutingResult {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )
    recordCapturedInputIndicator(routingResult.indicatorEvent)
    return routingResult
}

private func recordCapturedInputIndicator(
    _ indicatorEvent: CanvasInputIndicatorEvent?
) {
    guard let indicatorEvent else {
        return
    }

    inputIndicatorHostView.record(event: indicatorEvent)
}
```

## 修改三：`macOSViewController.swift` 同步删除本地 raw-input helper、indicator-only 旁路和旧的 context-menu 调试日志

### 修改前

`macOS` controller 和 `iOS` 一样，也同时保留了：

1. `makeUndoKeyboardShortcutRawInput()` / `makeRedoKeyboardShortcutRawInput()` / `makePasteKeyboardShortcutRawInput()` / `makeSecondaryClickRawInput()`
2. `observeIndicatorOnlyRawInput(...)`
3. `handleCapturedInput(...)` 内部自己的 `route + log + record indicator`
4. `presentSecondaryClickContextMenu(at:)` 里 phase7 的大段 `ContextMenuInput` 调试输出

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: undo(_:) / handleCapturedInput(...) / observeIndicatorOnlyRawInput(...) / makeSecondaryClickRawInput()
// 功能说明: 修改前 macOS controller 也保留迁移期重复 helper 与 indicator-only 旁路，并且 secondary click 还有大段 context-menu 调试日志。
@objc
func undo(_ sender: Any?) {
    let rawInput = makeUndoKeyboardShortcutRawInput()
    if consumeObservedKeyboardShortcut(rawInput) {
        performCommand(.undo)
        return
    }
    // ... 其余逻辑省略 ...
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

private func makeSecondaryClickRawInput() -> CanvasRawInputIntent {
    .pointerClick(.secondary)
}
```

### 修改后

`macOS` 现在也全面改用 shared factory，并把文本编辑 responder bridge 和普通 captured input 都统一落到 `resolveCapturedInputRouting(...)` 上：

- `undo(_:) / redo(_:) / paste(_:)` 直接使用 `CanvasRawInputIntent.undoKeyboardShortcut` 等 shared 命名
- `handleCapturedInput(...)` 与文本编辑 `localKeyMonitor` 路径复用同一份 `resolveCapturedInputRouting(...)`
- `observeIndicatorOnlyRawInput(...)` 已删除
- `presentSecondaryClickContextMenu(at:)` 里的旧 `ContextMenuInput` 大段日志已删除

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: undo(_:) / resolveCapturedInputRouting(...) / handleObservedKeyboardShortcut(_:)
// 功能说明: 修改后 macOS controller 与 iOS 一样，统一使用 shared raw-input factory，并复用单一的 routing/log/indicator 入口。
@objc
func undo(_ sender: Any?) {
    let rawInput = CanvasRawInputIntent.undoKeyboardShortcut
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

@discardableResult
private func resolveCapturedInputRouting(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String
) -> CanvasInputRoutingResult {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )
    recordCapturedInputIndicator(routingResult.indicatorEvent)
    return routingResult
}

private func recordCapturedInputIndicator(
    _ indicatorEvent: CanvasInputIndicatorEvent?
) {
    guard let indicatorEvent else {
        return
    }

    inputIndicatorHostView.record(event: indicatorEvent)
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
        _ = resolveCapturedInputRouting(
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

    if shouldContinue,
       inputRoutingResolver.route(rawInput).interactionIntent != nil
    {
        rememberObservedKeyboardShortcut(rawInput)
    }

    return shouldContinue ? event : nil
}
```

## 修改四：`CanvasInputRoutingResolverTests.swift` 改为直接复用 shared raw-input 命名

### 修改前

shared routing 测试里仍然手写 `CanvasKeyChord(modifiers:key:)`、`.pointerClick(.primary)`、`.gesture(.tap, source: .touch)` 这类构造，和 controller 新收口出来的 shared factory 并不一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() / testPrimaryClickRoutesOnlyToLeftClickIndicator()
// 功能说明: 修改前 routing 测试仍手写 raw input 构造，测试侧维护的是第三套输入命名方式。
func testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() {
    let rawInput = CanvasRawInputIntent.keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
    )

    let result = resolver.route(rawInput)
    XCTAssertEqual(
        result.interactionIntent,
        .transferEntry(.pasteKeyboardShortcut)
    )
}

func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
    let result = resolver.route(.pointerClick(.primary))

    XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
    XCTAssertNil(result.interactionIntent)
}
```

### 修改后

测试现在直接引用 shared factory，和生产代码保持同一套 raw-input 命名：

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() / testPrimaryClickRoutesOnlyToLeftClickIndicator() / testTouchLongPressRoutesToLongPressIndicatorAndContextMenuRequest()
// 功能说明: 修改后 routing 测试直接复用 shared raw-input factory，避免测试侧再维护一套手写输入构造。
func testPasteKeyboardShortcutRoutesToIndicatorAndTransferEntryIntent() {
    let rawInput = CanvasRawInputIntent.pasteKeyboardShortcut

    let result = resolver.route(rawInput)

    XCTAssertEqual(
        result.indicatorEvent,
        .keyChord(CanvasKeyChord(modifiers: [.command], key: .character("v")))
    )
    XCTAssertEqual(
        result.interactionIntent,
        .transferEntry(.pasteKeyboardShortcut)
    )
}

func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
    let result = resolver.route(.primaryPointerClick)

    XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
    XCTAssertNil(result.interactionIntent)
}

func testTouchLongPressRoutesToLongPressIndicatorAndContextMenuRequest() {
    let result = resolver.route(.touchLongPressGesture)

    XCTAssertEqual(result.indicatorEvent, .action(.longPress))
    XCTAssertEqual(result.interactionIntent, .contextMenuRequest)
}
```

## 修改五：新增 `CanvasInputIndicatorFormatterTests.swift`，补齐 formatter 回归网

### 修改前

该文件在本次修改前不存在。

```bash
# 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift
# 函数名/符号名: (新文件)
# 功能说明: 修改前仓库中不存在该测试文件。
# 文件不存在
```

### 修改后

新增 formatter 测试后，当前至少覆盖了：

- `modifier` 顺序是否按 `Command / Shift / Option / Control / Globe` 输出
- 命名键是否转成可读文本
- 字符键是否大写展示
- 动作文案是否按语义文本输出

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift
// 函数名/符号名: CanvasInputIndicatorFormatterTests
// 功能说明: 修改后新增 formatter 纯测试，锁住 keyChord 展示文本和 action 展示文本的输出格式。
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorFormatterTests: XCTestCase {
    private let formatter = CanvasInputIndicatorFormatter()

    func testKeyChordUsesCanonicalModifierOrderAndNamedKeyDisplayText() {
        let text = formatter.text(
            for: .keyChord(
                CanvasKeyChord(
                    modifiers: [.control, .command, .shift],
                    key: .named(.returnKey)
                )
            )
        )

        XCTAssertEqual(text, "Command + Shift + Control + Return")
    }

    func testKeyChordUppercasesCharacterDisplayText() {
        let text = formatter.text(for: .keyChord(.copyKeyboardShortcut))

        XCTAssertEqual(text, "Command + C")
    }

    func testActionUsesReadableSemanticDisplayName() {
        let text = formatter.text(for: .action(.rightClick))

        XCTAssertEqual(text, "Right Click")
    }
}
```

## 修改六：新增 `CanvasInputIndicatorQueueTests.swift`，补齐 queue 回归网

### 修改前

该文件在本次修改前不存在。

```bash
# 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift
# 函数名/符号名: (新文件)
# 功能说明: 修改前仓库中不存在该测试文件。
# 文件不存在
```

### 修改后

新增 queue 测试后，当前至少覆盖了：

- 新事件入队后只保留最新的可见项
- 生命周期结束时会 purge 过期项
- 旧项会按栈顺序降低 opacity
- 临近过期时会进入 fade-out

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift
// 函数名/符号名: CanvasInputIndicatorQueueTests
// 功能说明: 修改后新增 queue 纯测试，验证可见项裁剪、过期清理、栈透明度与生命周期渐隐行为。
import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorQueueTests: XCTestCase {
    func testEnqueueKeepsNewestVisibleItems() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 2,
                itemLifetime: 10,
                fadeOutDuration: 1,
                refreshInterval: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 1_000)

        _ = queue.enqueue(.action(.tap), now: start)
        _ = queue.enqueue(.action(.scroll), now: start.addingTimeInterval(0.1))
        let snapshot = queue.enqueue(
            .action(.rightClick),
            now: start.addingTimeInterval(0.2)
        )

        XCTAssertEqual(
            snapshot.items.map(\.event),
            [.action(.scroll), .action(.rightClick)]
        )
    }

    func testSnapshotPurgesExpiredEntries() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 3,
                itemLifetime: 1,
                fadeOutDuration: 0.2,
                refreshInterval: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 2_000)

        _ = queue.enqueue(.action(.tap), now: start)
        let snapshot = queue.snapshot(asOf: start.addingTimeInterval(1.1))

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertFalse(queue.hasEntries)
    }

    func testSnapshotAppliesFadeOutNearLifetimeEnd() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 1,
                itemLifetime: 4,
                fadeOutDuration: 1,
                refreshInterval: 0.1,
                newestOpacity: 1,
                stackOpacityStep: 0.2,
                minimumOpacity: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 4_000)

        _ = queue.enqueue(.action(.tap), now: start)
        let snapshot = queue.snapshot(asOf: start.addingTimeInterval(3.5))

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].opacity, CGFloat(0.5), accuracy: 0.0001)
    }
}
```

## 验证结果

`ReadLints` 检查以下文件，无新增诊断：

- `MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 复验 phase8 的 macOS Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase8-macos-r2"

# 实际结果: BUILD SUCCEEDED
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 复验 phase8 的 iOS Simulator Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase8-ios-r2"

# 实际结果: BUILD SUCCEEDED
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 定向验证 input 相关测试文件的 phase8 回归网；本次没有实际跑到测试执行阶段，因为 test target 仍被仓库既有错误阻断。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase8-tests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasInputIndicatorFormatterTests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasInputIndicatorQueueTests"

# 实际结果摘录:
# SwiftCompile normal arm64 Compiling CanvasInputIndicatorQueueTests.swift
# SwiftCompile normal arm64 Compiling CanvasInputRoutingResolverTests.swift
# SwiftCompile normal arm64 Compiling CanvasInputIndicatorEventTests.swift, CanvasInputIndicatorFormatterTests.swift
# /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift:28:22: error: cannot assign to property: 'updatedAt' is a get-only property
# ** TEST FAILED **
```

这次 targeted test 的真实结论是：

1. `CanvasInputIndicatorEventTests.swift`
2. `CanvasInputRoutingResolverTests.swift`
3. `CanvasInputIndicatorFormatterTests.swift`
4. `CanvasInputIndicatorQueueTests.swift`

这 `4` 个 input 相关测试文件都已成功编译进 `MyCanvas_Ver_0Tests` target。

阻断点仍是仓库里既有的 `BoardVideoStorageTests.swift` 编译错误，而不是本次 phase8 新增或修改的 input 代码本身。

## 本次保持的边界

1. `phase8` 主要做收口和测试补齐，没有再新增新的 raw-input 语义。
2. `CanvasInputRoutingResolver.swift` 的业务映射语义没有在这一步继续扩张，本次只清理 helper、命名和测试覆盖。
3. 文本编辑态 responder bridge 仍保持 `phase6` 的边界：文本编辑里的快捷键仍只镜像 indicator，不把文本编辑业务误下沉成 canvas command。
4. 本记录只覆盖自动可验证部分；计划里提到的手工回归矩阵没有在本轮逐项实机执行。
