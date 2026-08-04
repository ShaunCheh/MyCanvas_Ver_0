# 20260804_110323_handle_active_feedback_phase1_record

## 记录范围

本记录对应 `handle active feedback` 计划的阶段 1：建立共享 handle identity、pressed/dragging 状态机及纯单元测试。

本次记录参考了创建记录前的 `git status --short`、受版本控制文件的 `git diff`，并直接检查了三个新增文件的当前内容。下文不粘贴原始 diff，而是按实际源码整理修改前后情况。

阶段 1 只建立共享契约，尚未把 identity 或交互状态接入 renderer、hit tester、pointer context、`CanvasEditorSession`、iOS/macOS controller 和 viewport。因此，本阶段不会让画布 handle 实际变色，现有交互行为保持不变。

## 时间戳来源

文件名前缀通过系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 命令：生成“年月日_时分秒”格式的记录时间戳
date '+%Y%m%d_%H%M%S'
```

命令输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# date 命令的实际输出
20260804_110323
```

## 创建记录前的当前 changes

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# git status --short 的实际结果
 M MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
?? MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift
?? MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
?? MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift
```

本阶段的源码和测试变更共涉及五个文件；创建本记录后会额外出现当前 Markdown 文件。

## 修改一：handle role 具备稳定 identity 所需协议

### 修改前

selection、统一 edit、crop 和 arrow endpoint 的 role 只支持枚举遍历，不能直接作为共享 identity 的可哈希、可发送组成部分。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// CanvasSelectionHandleRole / CanvasEditHandleRole / CanvasCropHandleRole：修改前仅支持 CaseIterable
enum CanvasSelectionHandleRole: CaseIterable {
    // 方位 case 保持不变
}

enum CanvasEditHandleRole: CaseIterable {
    // 方位、rotate、arrow endpoint case 保持不变
}

enum CanvasCropHandleRole: CaseIterable {
    // 方位 case 保持不变
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
// CanvasArrowEndpointRole：修改前仅支持 CaseIterable
enum CanvasArrowEndpointRole: CaseIterable {
    case start
    case end
}
```

### 修改后

四类 role 补齐 `Hashable` 和 `Sendable`。枚举 case、几何语义及现有调用方式没有变化。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// CanvasSelectionHandleRole / CanvasEditHandleRole / CanvasCropHandleRole：支持参与共享 handle identity
enum CanvasSelectionHandleRole: CaseIterable, Hashable, Sendable {
    // 原有方位 case 保持不变
}

enum CanvasEditHandleRole: CaseIterable, Hashable, Sendable {
    // 原有方位、rotate、arrow endpoint case 保持不变
}

enum CanvasCropHandleRole: CaseIterable, Hashable, Sendable {
    // 原有方位 case 保持不变
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
// CanvasArrowEndpointRole：start/end 现在可安全组成 CanvasEditHandleKind
enum CanvasArrowEndpointRole: CaseIterable, Hashable, Sendable {
    case start
    case end
}
```

## 修改二：新增共享 handle identity

### 修改前

项目只有 `CanvasEditHandleGeometry.role` 等几何和方位信息，没有一个能够同时区分 owner、handle family 与具体 role 的稳定身份。尤其是 selection resize 与 crop resize 可以具有相同方位，多选成员数组也可能因顺序不同而表示同一选择。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// CanvasEditHandleGeometry：修改前只能携带 role 和易变的屏幕几何，不能单独稳定标识 handle
struct CanvasEditHandleGeometry {
    let role: CanvasEditHandleRole
    let screenCenter: CGPoint
    let screenRotationRadians: CGFloat
}
```

### 修改后

新增 `CanvasEditHandleIdentity.swift`，将 owner 与 kind 分离：

- owner 支持单个 item、多选集合和 canvas group。
- kind 覆盖 selection resize、crop resize、rotate、arrow endpoint 和 group frame resize。
- 多选 identity 使用 `Set<CanvasItemID>` 规范化成员，自动包含 primary item，成员顺序和重复项不会改变 identity。
- identity 只包含稳定业务身份，不包含屏幕坐标、frame 或 rotation 等易变几何。

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift
// CanvasEditHandleSelectionIdentity.init：把多选成员规范化为无序集合，并保证 primary 始终属于成员
struct CanvasEditHandleSelectionIdentity: Hashable, Sendable {
    let primaryItemID: CanvasItemID
    let memberItemIDs: Set<CanvasItemID>

    init<MemberIDs: Sequence>(
        primaryItemID: CanvasItemID,
        memberItemIDs: MemberIDs
    ) where MemberIDs.Element == CanvasItemID {
        self.primaryItemID = primaryItemID
        var normalizedMemberItemIDs = Set(memberItemIDs)
        normalizedMemberItemIDs.insert(primaryItemID)
        self.memberItemIDs = normalizedMemberItemIDs
    }
}
```

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift
// CanvasEditHandleOwner / CanvasEditHandleKind / CanvasEditHandleIdentity：组合 owner、family 与 role
enum CanvasEditHandleOwner: Hashable, Sendable {
    case item(CanvasItemID)
    case selection(CanvasEditHandleSelectionIdentity)
    case group(CanvasItemGroupID)
}

enum CanvasEditHandleKind: Hashable, Sendable {
    case selectionResize(CanvasSelectionHandleRole)
    case cropResize(CanvasCropHandleRole)
    case rotate
    case arrowEndpoint(CanvasArrowEndpointRole)
    case groupFrameResize(CanvasSelectionHandleRole)
}

struct CanvasEditHandleIdentity: Hashable, Sendable {
    let owner: CanvasEditHandleOwner
    let kind: CanvasEditHandleKind
}
```

本阶段没有修改 `CanvasEditHandleGeometry`；把 identity 写入 render geometry 属于计划阶段 2。

## 修改三：新增共享 pressed/dragging 状态机

### 修改前

项目没有独立的共享 handle 生命周期状态。平台 controller 的 pointer drag state 负责具体几何交互，但不能向共享 renderer 表达“当前哪一个 handle 正在按下或拖动”，也没有单独判断视觉是否需要刷新的返回值。

### 修改后

新增 `CanvasEditHandleInteractionState.swift`：

- phase：`inactive`、`pressed(identity)`、`dragging(identity)`。
- event：`press(identity?)`、`beginDragging(expectedIdentity:)`、`end`、`cancel`。
- visual state：只定义 `normal` 与 `active`；pressed 和 dragging 都映射为 active。
- 重复 press 同一 identity 保持幂等。
- 只有与 pressed identity 相同的 `beginDragging` 才能进入 dragging。
- `press(nil)`、`end` 和 `cancel` 清除活动 identity。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
// CanvasEditHandleInteractionPhase / CanvasEditHandleInteractionEvent：定义共享瞬态生命周期输入与状态
enum CanvasEditHandleInteractionPhase: Hashable, Sendable {
    case inactive
    case pressed(CanvasEditHandleIdentity)
    case dragging(CanvasEditHandleIdentity)
}

enum CanvasEditHandleInteractionEvent: Hashable, Sendable {
    case press(CanvasEditHandleIdentity?)
    case beginDragging(expectedIdentity: CanvasEditHandleIdentity)
    case end
    case cancel
}
```

状态迁移同时区分逻辑状态变化与视觉变化。`pressed(A) -> dragging(A)` 的 phase 发生变化，但 active identity 仍为 A，因此 `didChangeState == true`、`didChangeVisualState == false`，后续 controller 可以避免无意义的额外视觉刷新。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
// CanvasEditHandleInteractionTransition.didChangeVisualState：仅在 active identity 改变时要求刷新 handle 外观
struct CanvasEditHandleInteractionTransition: Hashable, Sendable {
    let previousPhase: CanvasEditHandleInteractionPhase
    let currentPhase: CanvasEditHandleInteractionPhase

    var didChangeState: Bool {
        previousPhase != currentPhase
    }

    var didChangeVisualState: Bool {
        previousPhase.activeIdentity != currentPhase.activeIdentity
    }
}
```

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
// CanvasEditHandleInteractionState.apply / nextPhase：执行幂等 press、identity 匹配和统一清理规则
@discardableResult
mutating func apply(
    _ event: CanvasEditHandleInteractionEvent
) -> CanvasEditHandleInteractionTransition {
    let previousPhase = phase
    phase = nextPhase(for: event)
    return CanvasEditHandleInteractionTransition(
        previousPhase: previousPhase,
        currentPhase: phase
    )
}

private func nextPhase(
    for event: CanvasEditHandleInteractionEvent
) -> CanvasEditHandleInteractionPhase {
    switch event {
    case let .press(identity):
        guard let identity else {
            return .inactive
        }
        guard activeIdentity != identity else {
            return phase
        }
        return .pressed(identity)

    case let .beginDragging(expectedIdentity):
        switch phase {
        case let .pressed(identity) where identity == expectedIdentity:
            return .dragging(identity)
        case let .dragging(identity) where identity == expectedIdentity:
            return phase
        case .inactive, .pressed, .dragging:
            return phase
        }

    case .end, .cancel:
        return .inactive
    }
}
```

`visualState(for:)` 使用完整 identity 精确匹配，因此同一时间只有当前活动 handle 返回 `.active`。

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
// CanvasEditHandleInteractionState.visualState(for:)：只激活完整 identity 相同的 handle
func visualState(
    for identity: CanvasEditHandleIdentity
) -> CanvasEditHandleVisualState {
    activeIdentity == identity ? .active : .normal
}
```

## 修改四：新增纯状态机单元测试

### 修改前

不存在 `CanvasEditHandleInteractionStateTests.swift`，共享 identity 和状态迁移规则没有独立测试。

### 修改后

新增 11 个测试，覆盖：

- 多选成员顺序、重复项与 primary 自动归一化。
- item、multi-selection、group 三种 owner。
- selection resize、crop resize、rotate、arrow endpoint、group frame resize 五类 kind。
- owner、kind、role 差异会产生不同 identity。
- press 立即 active，其他 handle 保持 normal。
- 重复 press 幂等。
- identity 匹配后才能进入 dragging。
- pressed 到 dragging 不产生额外 visual change。
- mismatch 不替换当前活动 handle。
- 切换活动 handle、`press(nil)`、`end`、`cancel` 的清理语义。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift
// testBeginDraggingRequiresPressedIdentityWithoutVisualRefresh：验证 phase 变化与视觉变化可以独立判断
func testBeginDraggingRequiresPressedIdentityWithoutVisualRefresh() {
    let identity = makeItemResizeIdentity()
    var state = CanvasEditHandleInteractionState()
    _ = state.apply(.press(identity))

    let transition = state.apply(
        .beginDragging(expectedIdentity: identity)
    )

    XCTAssertTrue(transition.didChangeState)
    XCTAssertFalse(transition.didChangeVisualState)
    XCTAssertEqual(state.phase, .dragging(identity))
    XCTAssertEqual(state.visualState(for: identity), .active)
}
```

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift
// testSelectionIdentityIgnoresMemberOrderingAndDuplicates：验证多选 identity 不受数组顺序和重复成员影响
func testSelectionIdentityIgnoresMemberOrderingAndDuplicates() {
    let primaryItemID = CanvasItemID()
    let secondaryItemID = CanvasItemID()

    let first = CanvasEditHandleSelectionIdentity(
        primaryItemID: primaryItemID,
        memberItemIDs: [primaryItemID, secondaryItemID]
    )
    let second = CanvasEditHandleSelectionIdentity(
        primaryItemID: primaryItemID,
        memberItemIDs: [secondaryItemID, primaryItemID, secondaryItemID]
    )

    XCTAssertEqual(first, second)
    XCTAssertEqual(Set([first, second]).count, 1)
}
```

## 自动验证

### macOS 指定测试

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：只运行 CanvasEditHandleInteractionStateTests
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests"
```

结果：`TEST SUCCEEDED`，`CanvasEditHandleInteractionStateTests` 中 11 个测试全部通过。

### iOS Simulator 构建

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 验证命令：确认新增共享类型可在 iOS Simulator 目标编译
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO
```

结果：`BUILD SUCCEEDED`。

### 静态检查

新增和修改文件的 IDE lint 检查没有错误，`git diff --check` 通过。

## 明确未修改的范围

- 未修改 renderer 的 handle geometry 生成逻辑。
- 未修改 edit overlay hit testing 和 pointer context。
- 未向 `CanvasEditorSession` 接入瞬态 handle 状态。
- 未修改 iOS/macOS pointer 生命周期。
- 未修改 iOS/macOS handle layer 的颜色或样式。
- 未修改 resize、crop、rotate、arrow、group frame 的几何计算。
- 未修改 history、autosave、storage 或文档格式。
- 未修改 `.cursor/plans/handle_active_feedback_fc72a0c4.plan.md`。

## 当前状态

创建本记录后，工作区包含阶段 1 的五个源码/测试变更，以及本记录文件。

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0（项目根目录）
# 创建记录文件后的预期 git status --short
 M MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
?? MyCanvas_Ver_0/Canvas/Core/CanvasEditHandleIdentity.swift
?? MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleInteractionState.swift
?? MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift
?? commit_records/20260804_110323_handle_active_feedback_phase1_record.md
```

本次没有提交代码。
