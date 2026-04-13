# 20260413_160606_interaction_intent_phase4_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase4` command gate 收敛”的实际 `git status`、`git diff --stat`、`git diff`、构建结果与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 5 个业务代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
- `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前的当前工作区状态依据：

- `git status --short --branch` 显示当前分支上存在 1 个与本次记录无关的既有变更：`M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`
- `git status --short --branch` 显示本次 `phase4` 当前 changes 包含 4 个已跟踪源码文件与 1 个新增测试文件
- `git diff --stat -- <4 个已跟踪业务代码文件>` 统计为：`4 files changed, 41 insertions(+), 13 deletions(-)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift"` 统计为：`1 file changed, 168 insertions(+)`
- 本记录文件是随后新增的说明材料，不属于上述 5 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/方案4输入意图收敛_b466a267.plan.md` 的任何编辑
- `phase5` 的 context menu / beginTextEdit 直达入口迁移

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +%Y%m%d_%H%M%S
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff --stat / git diff
# 功能说明: 提取本次 phase4 的当前工作区状态、统计信息与 5 个业务代码文件的真实改动范围。
git status --short --branch

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift" \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift" \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift"

git diff --unified=12 -- \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift"
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build / xcodebuild test
# 功能说明: 验证 phase4 command gate 收敛后的 app target 编译状态，并如实记录 targeted test 被既有测试错误阻断的情况。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  build

xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests \
  test
```

## 本次 phase4 的目标

这一步不是继续扩展 transfer entry 路径，而是把 command lane 的阅读模式判定真正收敛到 shared policy，让命令展示层和命令执行层都复用同一套语义：

1. 给 command lane 提供统一的 shared policy 入口，不再让各处自己手写 reading-mode 判断。
2. 让 `CanvasCommandCatalog.workspaceModeAdjustedDescriptor(...)` 复用 shared policy 结果。
3. 让 `CanvasCommandExecutor.canExecute(_:)` 也复用同一 policy 结果。
4. 让 transfer lane 下沉后的 `CanvasCommand.importMedia` 和其它 command 共用同一套 command gate。
5. 新增 command parity tests，锁定 `policy / descriptor / executor` 三者一致性。

## 修改一：为 command lane 补统一环境与 policy 入口

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment
// 功能说明: 修改前 shared environment 只提供通用字段，还没有专门给 command lane 复用的归一环境构造入口。
struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy.decision(for:environment:)
// 功能说明: 修改前 command 语义虽然已经能通过 .command(CanvasCommandID) 进入 policy，但外部没有统一 helper，Catalog 与 Executor 还未真正复用它。
struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        // ... 省略已有 transfer / command / contextMenu / beginTextEdit 判定 ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment.commandLane(workspaceMode:)
// 功能说明: 修改后新增 command lane 归一环境工厂，让 command 语义统一只消费 workspaceMode，不把 controller-local freeze 状态误带进 shared command gate。
struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool

    // Command lane does not own controller-local freeze state, so phase4 only
    // normalizes workspace mode here and keeps transition freeze upstream.
    static func commandLane(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: false
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy.commandDecision(for:workspaceMode:)
// 功能说明: 修改后新增 command lane 统一入口，把 CanvasCommandID 映射到现有 .command(...) intent，再交给同一个 shared policy 判定。
struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        // ... 省略已有判定 ...
    }

    func commandDecision(
        for commandID: CanvasCommandID,
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionDecision {
        decision(
            for: .command(commandID),
            environment: .commandLane(workspaceMode: workspaceMode)
        )
    }
}
```

### 修改意图

这一步把 `phase4` 需要的 command-lane shared 入口先正式固化下来，避免 `Catalog`、`Executor`、后续 context menu command surface 各自再拼一遍 `CanvasInteractionIntent.command(...)` 和环境对象。

## 修改二：`CanvasCommandCatalog` 改为复用 shared command policy

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/符号名: workspaceModeAdjustedDescriptor
// 功能说明: 修改前 descriptor 层自己手写 reading mode 判断，通过 CanvasCommandID.isAllowedInReadingMode 直接强制禁用命令描述。
private func workspaceModeAdjustedDescriptor(
    _ descriptor: CanvasCommandDescriptor,
    session: CanvasEditorSession
) -> CanvasCommandDescriptor {
    guard
        session.isReadingModeActive,
        descriptor.id.isAllowedInReadingMode == false
    else {
        return descriptor
    }

    return CanvasCommandDescriptor(
        id: descriptor.id,
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        isEnabled: false,
        isActive: false
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandCatalog.swift
// 函数名/符号名: interactionPolicy / workspaceModeAdjustedDescriptor
// 功能说明: 修改后 descriptor 层不再自己判断 reading mode，而是复用 CanvasInteractionPolicy.commandDecision(...) 的 allow/block 结论。
struct CanvasCommandCatalog {
    private let interactionPolicy = CanvasInteractionPolicy()

    private func workspaceModeAdjustedDescriptor(
        _ descriptor: CanvasCommandDescriptor,
        session: CanvasEditorSession
    ) -> CanvasCommandDescriptor {
        switch interactionPolicy.commandDecision(
        for: descriptor.id,
        workspaceMode: session.workspaceMode
        ) {
        case .allow:
            return descriptor
        case .block:
            return CanvasCommandDescriptor(
                id: descriptor.id,
                title: descriptor.title,
                systemImageName: descriptor.systemImageName,
                isEnabled: false,
                isActive: false
            )
        }
    }
}
```

### 修改意图

这一步把 command descriptor 的“展示语义”真正收敛进 shared policy，使 toolbar/context menu 这类命令展示面与运行时执行面说同一种 blocked language，而不是各判各的。

## 修改三：`CanvasCommandExecutor` 改为复用同一条 command policy

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/符号名: canExecute
// 功能说明: 修改前 executor 仍然直接读取 session.isReadingModeActive 与 command.isAllowedInReadingMode，和 shared policy 平行维护一套阅读模式逻辑。
func canExecute(_ command: CanvasCommand) -> Bool {
    guard session.isReadingModeActive == false || command.isAllowedInReadingMode else {
        return false
    }

    switch command {
    case let .importMedia(request):
        return request.isEmpty == false
    // ... 省略其它 command 的执行前条件 ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名/符号名: interactionPolicy / canExecute
// 功能说明: 修改后 executor 的第一层 gate 改为复用 CanvasInteractionPolicy.commandDecision(...)，然后才继续执行每个 command 自身的业务前置条件。
final class CanvasCommandExecutor {
    private let session: CanvasEditorSession
    private let interactionPolicy = CanvasInteractionPolicy()

    func canExecute(_ command: CanvasCommand) -> Bool {
        guard case .allow = interactionPolicy.commandDecision(
            for: command.id,
            workspaceMode: session.workspaceMode
        ) else {
            return false
        }

        switch command {
        case let .importMedia(request):
            return request.isEmpty == false
        case .addTextItem:
            return session.canAddTextItem
        // ... 省略其它 command 的具体业务条件 ...
        }
    }
}
```

### 修改意图

这一步把 command 的“真实执行路径”也收敛到 shared policy，确保 `CanvasCommand.importMedia(CanvasImportRequest)` 和其它 command 在进入 executor 前共用一套 reading-mode gate，而不是 transfer lane 一套、command lane 一套。

## 修改四：新增 command parity tests，锁定 `policy / descriptor / executor` 一致性

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名/符号名: CanvasCommandPolicyParityTests
// 功能说明: 修改前仓库中不存在这个测试文件，descriptor、executor 与 shared policy 之间的一致性还没有被专门锁住。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名/符号名: CanvasCommandPolicyParityTests
// 功能说明: 修改后新增 phase4 parity tests，覆盖 addText、commitTextEdit、importMedia 在 editing/reading 下的 policy、descriptor、executor 一致性。
import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasCommandPolicyParityTests: XCTestCase {
    private let policy = CanvasInteractionPolicy()
    private let commandCatalog = CanvasCommandCatalog()

    func testAddTextDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addTextItem))
    }

    func testAddTextDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addTextItem))
    }

    func testCommitTextDescriptorResetsActiveStateWhenPolicyBlocksInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        XCTAssertNotNil(session.addTextItem())
        session.workspaceMode = .reading

        let descriptor = commandCatalog.descriptor(
            for: .commitTextEdit,
            session: session
        )
        let decision = policy.commandDecision(
            for: .commitTextEdit,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.commitTextEdit))
    }

    func testImportMediaExecutorMatchesPolicyInReadingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let request = try makeCommandPolicyParityImportRequest()

        let decision = policy.commandDecision(
            for: .importMedia,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(executor.canExecute(.importMedia(request)))
    }
}
```

### 修改意图

这一步把 `phase4` 的核心承诺变成测试契约：

1. `policy` 说 allow 时，descriptor 与 executor 也必须允许。
2. `policy` 说 block 时，descriptor 必须 disabled，executor 也必须不可执行。
3. `commitTextEdit` 这种带 active state 的命令，在 reading mode 下必须同时清掉 `isEnabled` 和 `isActive`。
4. `importMedia` 作为 transfer lane 下沉后的 command，也必须走同一条 command policy。

## 验证结果

本次记录对应的实际验证结果如下：

- `ReadLints` 对 `CanvasInteractionDecision.swift`、`CanvasInteractionPolicy.swift`、`CanvasCommandCatalog.swift`、`CanvasCommandExecutor.swift`、`CanvasCommandPolicyParityTests.swift` 的读取结果为：无 linter 报错
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build` 结果为：`BUILD SUCCEEDED`
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests test` 未能跑完，不是因为本次新增的 parity tests 自身编译失败，而是被仓库里既有测试文件 `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift` 的编译错误阻断
- 从 test 输出可见，`CanvasCommandPolicyParityTests.swift` 已经进入 `SwiftCompile`，随后才被上述既有测试文件挡住

阻断到完整 test 执行的既有错误为：

- `Extra argument 'updatedAt' in call`
- `Missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call`

## 与当前其他 changes 的边界说明

这次 `phase4` 记录只覆盖上面 5 个业务代码文件，不覆盖当前工作区里另一个已存在的 `.md` 计划文件变更：

- `M .cursor/plans/方案4输入意图收敛_b466a267.plan.md`

该 `.md` 文件在本次记录写入过程中未被我删除、修改或回滚；这里只做如实说明，不把它混入本次 `phase4` 代码变更记录。
