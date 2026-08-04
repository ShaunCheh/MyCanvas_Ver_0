# 20260804_120951_handle_active_feedback_phase4_record

## 时间戳与记录范围

- 时间戳来源：在项目根目录执行系统命令 `date +"%Y%m%d_%H%M%S"`。
- 命令输出：`20260804_120951`。
- 对应任务：`Canvas Handle Active Feedback` 分阶段计划的阶段 4——统一接入 iOS/macOS pointer pressed、dragging、idle/cancel 生命周期。
- 参考依据：记录创建前的 `git status --short`、`git diff --stat`、相关文件当前内容及阶段 4 验证输出。
- 本次没有提交代码，也没有修改现有 `.md` 文件；本文件是按要求新增的阶段记录。

记录创建前，当前 changes 为：

- 修改 `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`。
- 修改 `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`。
- 修改 `MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift`。
- 新增 `MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleControllerAdapter.swift`。

## 修改目标与保持不变的边界

本阶段把阶段 1～3 已建立的 handle identity、共享交互状态机和 snapshot `visualState` 真正接到双端 pointer 生命周期上：

- pointer down 命中 handle 后，立即进入共享 `.pressed(identity)`。
- 越过现有 4pt 拖动阈值后，使用 pointer down 时保存的同一个 identity 进入 `.dragging(identity)`。
- pointer up、cancel、factory 失败、stale target 或 mutation 失败只要写回 `.idle`，都会经过唯一同步入口清理 active 状态。
- item body、selection translation、group frame body、crop translation、canvas pan，以及 iOS markdown scroll 都属于非 handle 状态。
- 只有 active identity 发生变化时才请求画布刷新；`.pressed` 到同 identity 的 `.dragging` 不增加无意义刷新。

以下既有业务没有修改：

- 4pt pointer drag activation threshold。
- resize、crop、rotate、arrow endpoint、group frame resize 的几何计算。
- history transaction 的开始、提交和取消位置。
- autosave reason 与 autosave update kind。
- pointer cancel 对现有几何草稿的提交或撤销语义。
- 文档格式、持久化模型和 history snapshot。

## 修改前：平台 pointer 状态没有驱动共享 handle 状态机

阶段 3 已经让 `CanvasEditorSession` 保存 `editHandleInteractionState`，并让 renderer 把它投影为 handle 的 `visualState`。但是双端 controller 的 `pointerDragState` 只是几何交互状态，没有同步入口：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | iOSViewController.pointerDragState（修改前）
private var pointerDragState: PointerDragState = .idle
```

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | macOSViewController.pointerDragState（修改前）
private var pointerDragState: PointerDragState = .idle
```

因此修改前存在以下断点：

- `CanvasPointerPressContext.targetHandleIdentity` 已经能够识别具体 handle，但 pointer down 不会发送 `.press(identity)`。
- 超过 4pt 阈值进入具体 resize/crop/rotate 状态时，不会发送 `.beginDragging`。
- 各种失败分支虽然统一写回 `.idle`，但不会清理 session 中潜在的 active handle。
- 双端 controller 若分别在每个 pointer 分支中手工补状态，容易漏掉早退和后续新增状态。

## 修改后 1：新增共享 controller adapter

新增纯 Swift adapter，将平台私有 `PointerDragState` 与共享 `CanvasEditHandleInteractionEvent` 隔离：

```swift
// MyCanvas_Ver_0/Canvas/Input/CanvasEditHandleControllerAdapter.swift | CanvasEditHandleControllerAdapter.event(for:)
enum CanvasEditHandlePointerLifecycleState: Hashable, Sendable {
    case pressed(CanvasEditHandleIdentity?)
    case draggingHandle
    case inactive
}

struct CanvasEditHandleControllerAdapter: Hashable, Sendable {
    private(set) var expectedDraggingIdentity: CanvasEditHandleIdentity?

    mutating func event(
        for pointerState: CanvasEditHandlePointerLifecycleState
    ) -> CanvasEditHandleInteractionEvent {
        switch pointerState {
        case let .pressed(identity):
            expectedDraggingIdentity = identity
            return .press(identity)

        case .draggingHandle:
            guard let expectedDraggingIdentity else {
                return .cancel
            }
            return .beginDragging(
                expectedIdentity: expectedDraggingIdentity
            )

        case .inactive:
            expectedDraggingIdentity = nil
            return .end
        }
    }
}
```

该 adapter 的关键行为：

- `.pressed(identity)` 保存命中时的稳定 identity，并产生 `.press(identity)`。
- `.draggingHandle` 不根据拖动中的几何或 selection 重新拼装 identity，而是使用 pointer down 时保存的 `expectedDraggingIdentity`。
- 如果没有对应的 pressed identity 却收到 `.draggingHandle`，产生 `.cancel`，不会错误激活其他 handle。
- `.inactive` 清空缓存并产生 `.end`。

## 修改后 2：iOS 使用 `pointerDragState` 唯一同步入口

iOS 的私有 pointer 状态被完整映射到共享生命周期。其中 markdown scroll 明确归类为非 handle：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | PointerDragState.editHandlePointerLifecycleState
var editHandlePointerLifecycleState:
    CanvasEditHandlePointerLifecycleState
{
    switch self {
    case let .pressed(_, pressContext, _):
        return .pressed(pressContext.targetHandleIdentity)

    case .croppingSelectedItem,
         .rotatingSelectedItem,
         .rotatingSelection,
         .resizingGroupFrame,
         .resizingSelectedItem,
         .adjustingArrowEndpoint,
         .resizingSelection:
        return .draggingHandle

    case .idle,
         .movingCropFrame,
         .draggingSelectedItem,
         .draggingSelection,
         .draggingGroupFrame,
         .scrollingMarkdownItem,
         .draggingCanvas:
        return .inactive
    }
}
```

`pointerDragState` 增加 property observer。原有代码中的所有状态赋值，包括 factory 失败后直接写 `.idle` 的分支，都自动经过同一个同步入口：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift | iOSViewController.pointerDragState / synchronizeEditHandleInteractionState(for:)
private var editHandleControllerAdapter =
    CanvasEditHandleControllerAdapter()
private var pointerDragState: PointerDragState = .idle {
    didSet {
        synchronizeEditHandleInteractionState(
            for: pointerDragState.editHandlePointerLifecycleState
        )
    }
}

private func synchronizeEditHandleInteractionState(
    for pointerState: CanvasEditHandlePointerLifecycleState
) {
    let event = editHandleControllerAdapter.event(for: pointerState)
    let transition = editorSession.editHandleInteractionState.apply(event)
    guard transition.didChangeVisualState else {
        return
    }

    requestCanvasRefresh(
        reason: "edit handle interaction visual state changed"
    )
}
```

iOS 仍沿用现有 `handlePrimaryPointerUp` 的 `defer { pointerDragState = .idle }`、`handlePrimaryPointerCancel()`、long press 抢占和 transition freeze 收尾路径。

## 修改后 3：macOS 使用相同的生命周期契约

macOS 与 iOS 使用同一个 adapter。macOS 没有 iOS 的 markdown touch scroll 状态，其余 handle / 非 handle 分类保持一致：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | PointerDragState.editHandlePointerLifecycleState
case .croppingSelectedItem,
     .rotatingSelectedItem,
     .rotatingSelection,
     .resizingGroupFrame,
     .resizingSelectedItem,
     .adjustingArrowEndpoint,
     .resizingSelection:
    return .draggingHandle

case .idle,
     .movingCropFrame,
     .draggingSelectedItem,
     .draggingSelection,
     .draggingGroupFrame,
     .draggingCanvas:
    return .inactive
```

macOS 同样通过 `pointerDragState.didSet` 统一发送事件，并且只在 active identity 变化时调用现有 refresh API：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift | macOSViewController.pointerDragState / synchronizeEditHandleInteractionState(for:)
private var editHandleControllerAdapter =
    CanvasEditHandleControllerAdapter()
private var pointerDragState: PointerDragState = .idle {
    didSet {
        synchronizeEditHandleInteractionState(
            for: pointerDragState.editHandlePointerLifecycleState
        )
    }
}

private func synchronizeEditHandleInteractionState(
    for pointerState: CanvasEditHandlePointerLifecycleState
) {
    let event = editHandleControllerAdapter.event(for: pointerState)
    let transition = editorSession.editHandleInteractionState.apply(event)
    guard transition.didChangeVisualState else {
        return
    }

    refreshCanvas(
        reason: "edit handle interaction visual state changed"
    )
}
```

macOS 仍沿用现有 pointer-up defer、primary cancel、secondary-click context menu 抢占和 transition freeze 收尾路径。

## 生命周期变化结果

修改后的主要状态流如下：

1. pointer down 命中具体 handle：
   - `PointerDragState.pressed`。
   - adapter 保存 `targetHandleIdentity`。
   - session 接收 `.press(identity)`。
   - active identity 从 `nil` 变为该 identity，请求一次立即刷新。
2. pointer 位移达到现有 4pt 阈值：
   - 平台进入对应的 handle drag state。
   - adapter 使用保存的 identity 产生 `.beginDragging(expectedIdentity:)`。
   - session 从 `.pressed(identity)` 变为 `.dragging(identity)`。
   - active identity 没有变化，因此不额外刷新 handle 外观。
3. pointer up、cancel 或任意失败路径写回 `.idle`：
   - adapter 产生 `.end` 并清空缓存。
   - session 回到 `.inactive`。
   - active identity 变为 `nil`，请求刷新恢复 normal。
4. pointer down 命中 body、translation area 或 blank：
   - `targetHandleIdentity` 为 `nil`。
   - `.press(nil)` 保证陈旧 active 状态不会遗留。
5. 从 pressed 进入非 handle drag：
   - 映射为 `.inactive`。
   - group frame body 拖动不会被误认为 group frame resize handle。

## 测试补充

在现有共享状态机测试中新增 3 个 adapter 测试，覆盖 identity 保持、inactive 清理以及无来源 dragging 防护。

核心的 pressed-to-dragging 测试如下：

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift | testControllerAdapterKeepsPressedIdentityThroughDragActivation()
let pressEvent = adapter.event(for: .pressed(identity))
let pressTransition = state.apply(pressEvent)

XCTAssertEqual(adapter.expectedDraggingIdentity, identity)
XCTAssertTrue(pressTransition.didChangeVisualState)
XCTAssertEqual(state.phase, .pressed(identity))

let dragEvent = adapter.event(for: .draggingHandle)
let dragTransition = state.apply(dragEvent)

XCTAssertEqual(
    dragEvent,
    .beginDragging(expectedIdentity: identity)
)
XCTAssertFalse(dragTransition.didChangeVisualState)
XCTAssertEqual(state.phase, .dragging(identity))
```

无 pressed identity 的异常 dragging 会被取消：

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests.swift | testControllerAdapterNilPressAndOrphanDragCannotActivateHandle()
let orphanDragEvent = adapter.event(for: .draggingHandle)
let orphanDragTransition = state.apply(orphanDragEvent)

XCTAssertEqual(orphanDragEvent, .cancel)
XCTAssertNil(adapter.expectedDraggingIdentity)
XCTAssertTrue(orphanDragTransition.didChangeVisualState)
XCTAssertEqual(state.phase, .inactive)
```

## 验证命令与结果

相关测试、macOS build 和 iOS build 按顺序执行，避免并发访问 DerivedData：

```bash
# 项目根目录 /Users/shaun/cloudDev/MyCanvas_Ver_0 | 阶段 4 验证命令
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests

xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS'

xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'generic/platform=iOS'
```

验证结果：

- `CanvasEditHandleInteractionStateTests`：14 个测试通过，其中包含本阶段新增的 3 个 adapter 测试。
- `CanvasEditHandleIdentityPipelineTests`：9 个测试通过。
- 合计 23 个相关测试通过，`TEST SUCCEEDED`。
- macOS build：`BUILD SUCCEEDED`。
- iOS build：`BUILD SUCCEEDED`。
- 本阶段 4 个相关文件的 IDE lint：无错误。
- `git diff --check`：通过。
- 构建仍输出仓库中既有的 Swift 6 actor-isolation、测试部署版本和 AppIntents metadata warning；未出现由本阶段文件引入的新 warning 或 error。

## 当前可见效果边界

阶段 4 完成后，session 与 render snapshot 已能在 pointer pressed/dragging/idle 生命周期中正确产生 `.active` / `.normal` 语义。

当前双端 viewport 尚未根据 `CanvasEditHandleGeometry.visualState` 切换 layer 颜色，因此本阶段代码完成后，用户界面暂时不会显示实际变色。具体 normal/active 颜色与全部 handle layer 的应用属于计划阶段 5。
