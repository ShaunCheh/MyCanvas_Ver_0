# 20260413_151030_interaction_intent_phase1_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase1` shared 骨架”的实际 `git status`、`git diff --no-index --stat`、运行结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 4 个新增代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift`
- `MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前的当前工作区状态依据：

- `git status --short --branch` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short --branch` 同时显示本次 `phase1` 新增的 4 个未跟踪文件
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift"` 统计为：`1 file changed, 16 insertions(+)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift"` 统计为：`1 file changed, 23 insertions(+)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift"` 统计为：`1 file changed, 43 insertions(+)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"` 统计为：`1 file changed, 80 insertions(+)`
- 本记录文件是随后新增的说明材料，不属于上述 4 个代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- `phase2` 及后续 runtime 入口接线

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +%Y%m%d_%H%M%S
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff --no-index --stat
# 功能说明: 提取本次 phase1 的当前工作区状态与四个新增文件的新增统计。
git status --short --branch

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift"
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / xcodebuild test
# 功能说明: 验证 phase1 新增 shared 骨架的构建状态，并记录测试受阻的实际原因。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests \
  test
```

## 本次 phase1 的目标

这一步不是接入 iOS / macOS 的 paste、import、drag-and-drop 运行时入口，而是先把 shared 层里 `Intent / Decision / Policy` 的骨架搭起来，并把最小测试闭环补齐：

1. 在 `Canvas/Input/` 下新增共享的输入意图模型。
2. 新增共享的环境、阻断原因、反馈提示与决策模型。
3. 固化 `CanvasInteractionPolicy.decision(for:environment:)` 这个统一判定入口。
4. 用纯单测锁定 `editing/reading` 与 `frozen/unfrozen` 语义，不改变当前产品行为。

## 修改一：新增 `CanvasInteractionIntent.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent / CanvasInteractionIntent
// 功能说明: 修改前仓库中不存在这个 shared intent 文件，phase1 的输入意图枚举尚未落到代码里。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent / CanvasInteractionIntent
// 功能说明: 修改后新增 shared 输入意图骨架，把 transfer entry、command、context menu 与 beginTextEdit 收敛到同一条上游语义车道。
import Foundation

// Shared interaction intents stay upstream of transfer/import lowering.
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}
```

### 修改意图

这一步先把“用户尝试做什么”独立建模出来，明确这些类型都位于 `CanvasTransferRequest` / `CanvasImportRequest` 之前，后续 `phase2` 再让平台入口统一产出这些 intent。

## 修改二：新增 `CanvasInteractionDecision.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment / CanvasInteractionBlockReason / CanvasInteractionFeedbackHint / CanvasInteractionDecision
// 功能说明: 修改前仓库中不存在这个 shared decision 文件，环境、阻断原因、反馈提示与 allow/block 结果尚未显式建模。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment / CanvasInteractionBlockReason / CanvasInteractionFeedbackHint / CanvasInteractionDecision
// 功能说明: 修改后新增 shared 决策模型，显式承载 workspaceMode、transitionFrozen、阻断原因与反馈提示。
import Foundation

struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool
}

enum CanvasInteractionBlockReason: Equatable, Sendable {
    case readingMode
    case transitionInteractionFrozen
}

enum CanvasInteractionFeedbackHint: Equatable, Sendable {
    case shakeWorkspaceModeButton
}

enum CanvasInteractionDecision: Equatable, Sendable {
    case allow
    case block(
        reason: CanvasInteractionBlockReason,
        feedback: CanvasInteractionFeedbackHint?
    )
}
```

### 修改意图

这一步把 policy 的输入环境和输出结果先定义清楚，避免后续平台 controller 直接散写 `if readingMode` / `if frozen` 分支，也为后面的 feedback bridge 预留统一结果结构。

## 修改三：新增 `CanvasInteractionPolicy.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy.decision(for:environment:)
// 功能说明: 修改前仓库中不存在这个 shared policy 文件，还没有统一的 allow/block 纯函数入口。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy.decision(for:environment:) / CanvasTransferEntryIntent.readingModeFeedbackHint
// 功能说明: 修改后新增最小 policy 闭环，优先处理 transition frozen，其次处理 reading mode，并只给键盘 paste 入口返回摇头反馈提示。
import Foundation

struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        if environment.isTransitionInteractionFrozen {
            return .block(reason: .transitionInteractionFrozen, feedback: nil)
        }

        guard environment.workspaceMode == .reading else {
            return .allow
        }

        switch intent {
        case .transferEntry(let entry):
            return .block(reason: .readingMode, feedback: entry.readingModeFeedbackHint)
        case .command(let commandID):
            guard commandID.isAllowedInReadingMode == false else {
                return .allow
            }

            return .block(reason: .readingMode, feedback: nil)
        case .contextMenuRequest,
             .beginTextEdit:
            return .block(reason: .readingMode, feedback: nil)
        }
    }
}

private extension CanvasTransferEntryIntent {
    var readingModeFeedbackHint: CanvasInteractionFeedbackHint? {
        switch self {
        case .pasteKeyboardShortcut:
            return .shakeWorkspaceModeButton
        case .pasteMenu,
             .importButton,
             .dragAndDrop:
            return nil
        }
    }
}
```

### 修改意图

这一步把 `phase1` 计划里要求的最小统一入口先冻结下来：

1. `transitionInteractionFrozen` 的阻断优先级高于 `readingMode`。
2. `readingMode` 下的 transfer intent 会统一走 `allow/block` 决策。
3. 键盘 `pasteKeyboardShortcut` 在 `readingMode` 下显式返回 `.shakeWorkspaceModeButton`，为后续 UI 反馈接线预留准确语义。
4. `command(CanvasCommandID)` 暂时复用现有 `CanvasCommandID.isAllowedInReadingMode` 元数据，不在 `phase1` 改 command runtime。

## 修改四：新增 `CanvasInteractionPolicyTests.swift`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: CanvasInteractionPolicyTests
// 功能说明: 修改前仓库中不存在这个测试文件，shared policy 的四象限语义还没有被测试固定下来。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests.swift
// 函数名/符号名: CanvasInteractionPolicyTests
// 功能说明: 修改后新增 phase1 纯单测，覆盖 pasteKeyboardShortcut 与 command 在 editing/reading、frozen/unfrozen 下的最小语义，并用 @MainActor 消除 actor 隔离告警。
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInteractionPolicyTests: XCTestCase {
    private let policy = CanvasInteractionPolicy()

    func testPasteKeyboardShortcutAllowsInEditingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
        )

        XCTAssertEqual(decision, .allow)
    }

    func testPasteKeyboardShortcutBlocksInReadingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .readingMode, feedback: .shakeWorkspaceModeButton)
        )
    }

    func testPasteKeyboardShortcutBlocksInEditingModeWhenFrozen() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: true)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .transitionInteractionFrozen, feedback: nil)
        )
    }

    func testPasteKeyboardShortcutPrioritizesFrozenBlockInReadingMode() {
        let decision = policy.decision(
            for: .transferEntry(.pasteKeyboardShortcut),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: true)
        )

        XCTAssertEqual(
            decision,
            .block(reason: .transitionInteractionFrozen, feedback: nil)
        )
    }

    func testCommandAllowsInEditingModeWhenNotFrozen() {
        let decision = policy.decision(
            for: .command(.undo),
            environment: makeEnvironment(workspaceMode: .editing, isFrozen: false)
        )

        XCTAssertEqual(decision, .allow)
    }

    func testCommandBlocksInReadingModeWhenMetadataDisallowsIt() {
        let decision = policy.decision(
            for: .command(.undo),
            environment: makeEnvironment(workspaceMode: .reading, isFrozen: false)
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
    }

    private func makeEnvironment(
        workspaceMode: CanvasWorkspaceMode,
        isFrozen: Bool
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: isFrozen
        )
    }
}
```

### 修改意图

这一步先把 `phase1` 所需的最小语义锁住，避免后续接 `phase2` 平台入口时再回头改 policy 规则：

- `editing + unfrozen` 时允许继续
- `reading + unfrozen` 时 paste keyboard shortcut 被阅读模式阻断，并返回按钮摇动反馈
- 任意 `frozen` 状态都优先返回 `transitionInteractionFrozen`
- command lane 先验证 `command(CanvasCommandID)` 这条语义通路已经能复用 shared policy

## 验证结果

本次记录对应的实际验证结果如下：

- `ReadLints` 对 4 个新增文件读取结果为：无 linter 报错
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build` 结果为：`BUILD SUCCEEDED`
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasInteractionPolicyTests test` 未能完成，不是因为本次 4 个新增文件编译失败，而是被仓库里既有测试文件 `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 的编译错误阻断

阻断到完整测试执行的既有错误为：

- `Extra argument 'updatedAt' in call`
- `Missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call`

## 与当前其他 changes 的边界说明

这次 `phase1` 记录只覆盖上面 4 个新增文件，不覆盖当前工作区里另一个已存在的 `.md` 计划文件变更：

- `M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`

该 `.md` 文件在本次记录写入过程中未被我删除、修改或回滚；这里只做如实说明，不把它混入本次 `phase1` 代码变更记录。
