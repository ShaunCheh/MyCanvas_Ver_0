# 20260413_175836_raw_input_lane_phase1_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase1` shared 骨架与纯测试补齐”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果、测试结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 6 个业务/测试文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 包含 `4` 个已跟踪 shared 源码文件修改与 `2` 个新测试文件新增：
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
  - `?? MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests.swift`
  - `?? MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`
- `git diff --stat -- <4 个已跟踪源码文件>` 统计为：`4 files changed, 271 insertions(+), 14 deletions(-)`
- `git diff --no-index --stat -- /dev/null <2 个新测试文件>` 分别统计为：
  - `CanvasInputIndicatorEventTests.swift`: `1 file changed, 35 insertions(+)`
  - `CanvasInputRoutingResolverTests.swift`: `1 file changed, 80 insertions(+)`
- 合并观察后，本次 `phase1` 当前业务/测试代码总量为：`6 files changed, 386 insertions(+), 14 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 6 个业务/测试文件本身。

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase2` 的 controller ingress 接线
- `phase3` 的胶囊 UI、queue、formatter、layout solver

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_175836`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 提取这次 raw input lane phase1 的真实变更范围与当前工作区状态。
git status --short --branch

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift"

git diff -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"
```

## 本次 phase1 的真实目标

这一步没有进入 `phase2` 的 controller 归一入口，也没有提前实现 `phase3` 的胶囊 UI，而是只把 `Raw Input Lane` 的 shared 纯模型、最小 routing resolver 和纯测试补齐：

1. 把 `CanvasRawInputIntent.swift` 从 phase0 占位文件扩成可测试的 raw-input shared 模型。
2. 把 `CanvasInputIndicatorEvent.swift` 从空壳扩成展示事件模型。
3. 把 `CanvasInputRoutingResult.swift` 从空壳扩成 shared routing 返回值。
4. 把 `CanvasInputRoutingResolver.swift` 从空壳扩成 phase1 最小 resolver。
5. 新增纯测试，验证 key chord 归一和 raw input -> indicator / interaction 的 shared 映射。

## 修改一：把 `CanvasRawInputIntent` 从占位扩成 shared raw-input 模型

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasRawInputSource / CanvasKeyChord / CanvasRawInputIntent
// 功能说明: 修改前这里只有 phase0 的占位契约，没有真正的 raw-input shared 模型、调试命名或归一行为。
import Foundation

// Phase 0 reserves the upstream raw-input lane for physical or system input
// facts captured on platform edges. Concrete cases arrive in later phases.
enum CanvasRawInputSource: Equatable, Sendable {}

// Shared key-chord naming stays upstream of command or transfer lowering.
struct CanvasKeyChord: Equatable, Sendable {}

// Raw input facts are not business intents and must not be added to
// CanvasInteractionIntent.
enum CanvasRawInputIntent: Equatable, Sendable {}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasRawInputSource / CanvasKeyModifier / CanvasNamedKey / CanvasKey / CanvasKeyChord / CanvasPointerButton / CanvasRawInputGesture / CanvasRawInputIntent
// 功能说明: 修改后补齐 raw-input lane 的最小 shared 模型，支持键盘组合键、指针点击、手势输入，以及 debugName 和字符归一能力。
import Foundation

// Shared raw-input sources describe logical capture origin, not platform-local
// delivery details such as responder chain or monitor type.
enum CanvasRawInputSource: String, Equatable, Sendable {
    case keyboard
    case pointer
    case touch

    var debugName: String {
        rawValue
    }
}

enum CanvasKeyModifier: String, CaseIterable, Sendable {
    case command
    case shift
    case option
    case control
    case globe

    fileprivate static let debugOrder: [CanvasKeyModifier] = [
        .command,
        .shift,
        .option,
        .control,
        .globe
    ]

    var debugName: String {
        rawValue
    }
}

enum CanvasNamedKey: String, Equatable, Sendable {
    case returnKey
    case escape
    case delete
    // ... 省略其它 named key，同一段新增逻辑保持不变 ...
}

enum CanvasKey: Equatable, Sendable {
    case character(String)
    case named(CanvasNamedKey)

    fileprivate var normalized: CanvasKey {
        switch self {
        case .character(let value):
            return .character(value.lowercased())
        case .named:
            return self
        }
    }

    var debugName: String {
        switch self {
        case .character(let value):
            return value.uppercased()
        case .named(let namedKey):
            return namedKey.debugName
        }
    }
}

struct CanvasKeyChord: Equatable, Sendable {
    let modifiers: Set<CanvasKeyModifier>
    let key: CanvasKey

    init(
        modifiers: Set<CanvasKeyModifier> = [],
        key: CanvasKey
    ) {
        self.modifiers = modifiers
        self.key = key.normalized
    }
}

enum CanvasRawInputIntent: Equatable, Sendable {
    case keyChord(CanvasKeyChord)
    case pointerClick(CanvasPointerButton)
    case gesture(
        CanvasRawInputGesture,
        source: CanvasRawInputSource
    )
}
```

### 修改意图

这一步把 phase0 的空占位推进成真正可测试的 raw-input shared 骨架，但仍然只停留在 shared 纯模型层，不接平台 `capture` 入口。

## 修改二：把 `CanvasInputIndicatorEvent` 从空结构扩成展示事件模型

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift
// 函数名/符号名: CanvasInputIndicatorEvent
// 功能说明: 修改前只有 phase0 的单个空结构，还没有 action 语义和调试命名。
import Foundation

// Phase 0 reserves the indicator lane for presentation-only events consumed by
// the future input indicator UI.
struct CanvasInputIndicatorEvent: Equatable, Sendable {}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift
// 函数名/符号名: CanvasInputIndicatorAction / CanvasInputIndicatorEvent
// 功能说明: 修改后把 indicator lane 扩成真正的展示事件模型，既支持 keyChord，也支持 leftClick、tap、scroll 等语义 action。
import Foundation

enum CanvasInputIndicatorAction: String, Equatable, Sendable {
    case leftClick
    case rightClick
    case tap
    case longPress
    case scroll
    case pinch
    case zoom
}

// Indicator events stay presentation-only even when they mirror a raw input
// fact that also lowers into a business interaction intent.
enum CanvasInputIndicatorEvent: Equatable, Sendable {
    case keyChord(CanvasKeyChord)
    case action(CanvasInputIndicatorAction)

    var debugName: String {
        switch self {
        case .keyChord(let chord):
            return "keyChord.\(chord.debugName)"
        case .action(let action):
            return "action.\(action.debugName)"
        }
    }
}
```

### 修改意图

这一步把“展示事件”与“业务意图”继续分开，为后续胶囊 UI 提供一个明确消费对象，而不是直接复用 `CanvasInteractionIntent` 或 `CanvasCommand`。

## 修改三：把 `CanvasInputRoutingResult` 从空结构扩成 shared routing 返回值

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift
// 函数名/符号名: CanvasInputRoutingResult
// 功能说明: 修改前只有 phase0 占位，没有 indicator 和 interaction 两条车道的显式返回值。
import Foundation

// Phase 0 reserves the shared handoff from raw input into indicator and
// interaction lanes. Concrete fields are intentionally deferred to phase 1.
struct CanvasInputRoutingResult: Equatable, Sendable {}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift
// 函数名/符号名: CanvasInputRoutingResult
// 功能说明: 修改后新增 indicatorEvent、interactionIntent、isEmpty 和 debugSummary，用于 shared routing 显式分流。
import Foundation

// Shared routing splits one raw input fact into an indicator event and an
// optional downstream interaction intent.
struct CanvasInputRoutingResult: Equatable, Sendable {
    let indicatorEvent: CanvasInputIndicatorEvent?
    let interactionIntent: CanvasInteractionIntent?

    init(
        indicatorEvent: CanvasInputIndicatorEvent? = nil,
        interactionIntent: CanvasInteractionIntent? = nil
    ) {
        self.indicatorEvent = indicatorEvent
        self.interactionIntent = interactionIntent
    }

    var isEmpty: Bool {
        indicatorEvent == nil && interactionIntent == nil
    }

    var debugSummary: String {
        let indicatorDebugName = indicatorEvent?.debugName ?? "nil"
        let interactionDebugName = interactionIntent?.debugName ?? "nil"
        return "indicator=\(indicatorDebugName) interaction=\(interactionDebugName)"
    }
}
```

### 修改意图

这一步把 raw-input lane 到下游两条车道的 shared handoff 做成显式结构，方便后续 phase2 controller ingress 和 phase3 指示器 UI 都消费同一种结果。

## 修改四：实现 `CanvasInputRoutingResolver` 的 phase1 最小映射

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver
// 功能说明: 修改前只有 phase0 占位，raw input 还没有 shared routing 实现。
import Foundation

// Phase 0 reserves the shared boundary that will translate raw input facts
// into indicator events and optional interaction intents in later phases.
struct CanvasInputRoutingResolver: Sendable {}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver.route / routeKeyChord / CanvasKeyChord.isPasteKeyboardShortcut
// 功能说明: 修改后提供 phase1 的最小 shared 路由能力：Command+V 同时产出 indicator 和 transferEntry，其它首批事件先只产出 indicator。
import Foundation

// Shared routing normalizes raw input facts before platform code decides how to
// execute or present downstream behavior.
struct CanvasInputRoutingResolver: Sendable {
    func route(_ rawInput: CanvasRawInputIntent) -> CanvasInputRoutingResult {
        switch rawInput {
        case .keyChord(let chord):
            return routeKeyChord(chord)
        case .pointerClick(let button):
            return CanvasInputRoutingResult(
                indicatorEvent: .action(button.indicatorAction)
            )
        case .gesture(let gesture, _):
            return CanvasInputRoutingResult(
                indicatorEvent: .action(gesture.indicatorAction)
            )
        }
    }

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
}

private extension CanvasKeyChord {
    var isPasteKeyboardShortcut: Bool {
        modifiers == [.command] && key.matchesCharacter("v")
    }
}

private extension CanvasPointerButton {
    var indicatorAction: CanvasInputIndicatorAction {
        switch self {
        case .primary:
            return .leftClick
        case .secondary:
            return .rightClick
        }
    }
}
```

### 修改意图

这一步严格遵守 phase1 约束：只做 shared 最小 routing，不引入 controller，不把所有 raw input 都强行降成 `CanvasInteractionIntent`。其中 `Command + V` 作为首个示范路径，同时连接 indicator lane 和现有 interaction lane。

## 修改五：新增 `CanvasInputIndicatorEventTests`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests.swift
// 函数名/符号名: CanvasInputIndicatorEventTests
// 功能说明: 修改前仓库中不存在 indicator event 的纯测试文件。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests.swift
// 函数名/符号名: CanvasInputIndicatorEventTests
// 功能说明: 修改后新增纯测试，验证 keyChord 的 canonical modifier 顺序、字符大小写归一和 action.debugName。
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorEventTests: XCTestCase {
    func testKeyChordDebugNameUsesCanonicalModifierOrderAndUppercaseCharacter() {
        let event = CanvasInputIndicatorEvent.keyChord(
            CanvasKeyChord(
                modifiers: [.shift, .command],
                key: .character("z")
            )
        )

        XCTAssertEqual(event.debugName, "keyChord.command+shift+Z")
    }

    func testKeyChordNormalizesCharacterCaseForEquality() {
        let lowercased = CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
        let uppercased = CanvasKeyChord(
            modifiers: [.command],
            key: .character("V")
        )

        XCTAssertEqual(lowercased, uppercased)
    }
}
```

### 修改意图

这一步验证的是 phase1 shared 骨架的“命名与归一规则”，避免后续平台接线之前就出现同一快捷键大小写不一致、modifier 顺序不稳定之类的问题。

## 修改六：新增 `CanvasInputRoutingResolverTests`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: CanvasInputRoutingResolverTests
// 功能说明: 修改前仓库中不存在 raw input routing 的纯测试文件。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: CanvasInputRoutingResolverTests
// 功能说明: 修改后新增纯测试，验证 Command+V、Command+C、leftClick、tap、scroll 的 shared routing 结果。
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputRoutingResolverTests: XCTestCase {
    private let resolver = CanvasInputRoutingResolver()

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
        XCTAssertFalse(result.isEmpty)
    }

    func testCopyKeyboardShortcutRoutesOnlyToIndicatorEvent() {
        let rawInput = CanvasRawInputIntent.keyChord(
            CanvasKeyChord(
                modifiers: [.command],
                key: .character("c")
            )
        )

        let result = resolver.route(rawInput)

        XCTAssertNil(result.interactionIntent)
    }

    func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
        let result = resolver.route(.pointerClick(.primary))
        XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
    }
}
```

### 修改意图

这一步验证的是 phase1 最重要的 shared 约束：不是每个 raw input 都必须降成 `CanvasInteractionIntent`。`Command + V` 可以双路分流，而 `Command + C`、左键点击、`Tap`、`Scroll` 首先只进入 indicator lane。

## 本次明确没有做的事情

- 没有改 `iOSViewController` / `macOSViewController`
- 没有增加 `handleCapturedInput(...)`
- 没有接入 `chromeOverlayView`、胶囊 UI、queue、formatter、layout solver
- 没有给 `CanvasInputRoutingResolver` 增加平台特定分支
- 没有把 `right click / long press / undo / redo` 继续下沉进 `CanvasInteractionIntent`
- 没有改动现有 `CanvasInteractionPolicy` 的运行时行为

这和 `phase1` 计划是一致的：先把 shared raw-input 骨架与纯测试建立起来，再进入 phase2 的 controller ingress。

## 构建、测试与诊断验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase1 的 shared 源码改动不会破坏现有 app target 构建。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 运行本次 phase1 新增的两组定向测试，验证 shared raw-input routing 与 indicator event 行为。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:MyCanvas_Ver_0Tests/CanvasInputIndicatorEventTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests \
  test
```

验证结果：

- `ReadLints` 未发现这 6 个 phase1 文件的新增诊断
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build` 通过
- 定向测试命令已编译到 `CanvasInputIndicatorEventTests.swift` 与 `CanvasInputRoutingResolverTests.swift`，但整个 `MyCanvas_Ver_0Tests` target 仍被既有测试文件阻断，不是这次 phase1 新代码编译失败
- 实际阻断点来自：
  - `MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift`: `Cannot assign to property: 'updatedAt' is a get-only property`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`: `Extra argument 'updatedAt' in call`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`: `Missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call`

## 结论

这次 `phase1` 的真实落点是“把 phase0 的命名占位推进成可测试的 shared raw-input 骨架”：

1. `CanvasRawInputIntent` 已从空占位扩成键盘/点击/手势的 shared 输入模型。
2. `CanvasInputIndicatorEvent` 已从空结构扩成胶囊提示可消费的展示事件模型。
3. `CanvasInputRoutingResult` 与 `CanvasInputRoutingResolver` 已建立 shared 分流骨架。
4. `Command + V` 已成为首条示范性的双路映射：同时进入 indicator lane 和现有 interaction lane。
5. 纯测试已经补齐，但完整 test target 仍被仓库中既有测试文件阻断。

因此，后续进入 `phase2` 时，controller 只需要把平台 capture 归一投递到现有 resolver，不需要再临时定义 raw-input 模型和分流协议。
