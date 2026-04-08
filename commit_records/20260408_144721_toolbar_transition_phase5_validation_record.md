# 20260408_144721_toolbar_transition_phase5_validation_record

## 记录范围

- 记录内容：`Phase 5` 的验证与微调收尾。
- 涉及业务代码文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 写入本记录前的代码状态依据：
  - `git status --short` 仅显示两份已修改文件：
    - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
    - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"` 显示本次改动只集中在双端控制器的 `remainingToolbarTransitionDuration(...)` 调用与实现。
- 本记录文件是随后新增的说明材料，不属于本次业务代码改动本身。
- 本记录不包含：
  - `Phase 0` 到 `Phase 4` 的基础结构、Host 接口、控制器接入与 layout reconcile
  - 任何新的共享字段或阶段语义改动
  - git commit / push

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 在写入本记录前确认当前工作区只包含 Phase 5 的双端控制器收尾改动，并据此抽取本次“修改前 / 修改后”的真实基线。
git status --short
git diff -- "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
```

## 修改一：修正第二段动画被错误算成 `0s` 的问题

### 修改前

- 双端控制器在 `runToolbarCollapsePhase()` 和 `runToolbarSlidePhase()` 里都会调用：
  - `remainingToolbarTransitionDuration(fullDuration:currentStage:)`
- 旧逻辑只看“当前 stage 的 progress”，不看“即将执行的目标 stage 是什么”。
- 这会导致一个真实问题：
  - 第一段 `collapsing(progress: 1)` 结束后，紧接着进入第二段 `exiting`
  - 因为旧函数只看 `currentStage == .collapsing(progress: 1)`，会把 `progress` 当成 `1`
  - 于是第二段剩余时长直接被算成 `0`
- `阅读 -> 编辑` 的 `entering -> expanding` 也有同样问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / remainingToolbarTransitionDuration(fullDuration:currentStage:)
// 功能说明: 修改前 iOS 侧只按 currentStage 继承 progress，第一段完成后切到第二段时，下一段会被误判为“剩余 0 时长”。
animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.collapseDuration,
        currentStage: runtime.stage
    ),
    completion: completion
)

animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.slideDuration,
        currentStage: runtime.stage
    ),
    completion: completion
)

private func remainingToolbarTransitionDuration(
    fullDuration: TimeInterval,
    currentStage: CanvasToolbarTransitionStage
) -> TimeInterval {
    let progress: CGFloat
    switch currentStage {
    case let .collapsing(currentProgress),
         let .exiting(currentProgress),
         let .entering(currentProgress),
         let .expanding(currentProgress):
        progress = clampedToolbarTransitionProgress(currentProgress)
    case .steadyVisible, .hidden:
        progress = 1
    }

    return max(fullDuration * TimeInterval(1 - progress), 0)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / remainingToolbarTransitionDuration(fullDuration:currentStage:)
// 功能说明: 修改前 macOS 侧与 iOS 一样，只按 currentStage 算剩余时长，第二段动画会在第一段完成后被错误压成 0 秒。
animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.collapseDuration,
        currentStage: runtime.stage
    ),
    completion: completion
)

animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.slideDuration,
        currentStage: runtime.stage
    ),
    completion: completion
)

private func remainingToolbarTransitionDuration(
    fullDuration: TimeInterval,
    currentStage: CanvasToolbarTransitionStage
) -> TimeInterval {
    let progress: CGFloat
    switch currentStage {
    case let .collapsing(currentProgress),
         let .exiting(currentProgress),
         let .entering(currentProgress),
         let .expanding(currentProgress):
        progress = clampedToolbarTransitionProgress(currentProgress)
    case .steadyVisible, .hidden:
        progress = 1
    }

    return max(fullDuration * TimeInterval(1 - progress), 0)
}
```

### 修改后

- 双端现在都把“当前 stage”和“目标 stage”一起传给 `remainingToolbarTransitionDuration(...)`。
- 只有在“当前 stage 类型”和“目标 stage 类型”一致时，才继承当前 progress：
  - `(.collapsing, .collapsing)`
  - `(.exiting, .exiting)`
  - `(.entering, .entering)`
  - `(.expanding, .expanding)`
- 其余情况一律从 `progress = 0` 开始，确保跨阶段切换时下一段拿到完整时长。
- 这样：
  - `collapsing -> exiting`
  - `entering -> expanding`
  不会再把第二段压成瞬间跳变。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / remainingToolbarTransitionDuration(fullDuration:currentStage:targetStage:)
// 功能说明: 修改后 iOS 侧只在“当前阶段类型和目标阶段类型相同”时继承 progress，跨阶段时恢复完整段时长。
animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.collapseDuration,
        currentStage: runtime.stage,
        targetStage: targetStage
    ),
    completion: completion
)

animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.slideDuration,
        currentStage: runtime.stage,
        targetStage: targetStage
    ),
    completion: completion
)

private func remainingToolbarTransitionDuration(
    fullDuration: TimeInterval,
    currentStage: CanvasToolbarTransitionStage,
    targetStage: CanvasToolbarTransitionStage
) -> TimeInterval {
    let progress: CGFloat
    switch (currentStage, targetStage) {
    case let (.collapsing(currentProgress), .collapsing),
         let (.exiting(currentProgress), .exiting),
         let (.entering(currentProgress), .entering),
         let (.expanding(currentProgress), .expanding):
        progress = clampedToolbarTransitionProgress(currentProgress)
    default:
        progress = 0
    }

    return max(fullDuration * TimeInterval(1 - progress), 0)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: runToolbarCollapsePhase() / runToolbarSlidePhase() / remainingToolbarTransitionDuration(fullDuration:currentStage:targetStage:)
// 功能说明: 修改后 macOS 侧与 iOS 对称，跨阶段切换时不会再错误继承上一段已经完成的 progress。
animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.collapseDuration,
        currentStage: runtime.stage,
        targetStage: targetStage
    ),
    completion: completion
)

animateToolbarTransition(
    to: targetStage,
    duration: remainingToolbarTransitionDuration(
        fullDuration: runtime.context.configuration.slideDuration,
        currentStage: runtime.stage,
        targetStage: targetStage
    ),
    completion: completion
)

private func remainingToolbarTransitionDuration(
    fullDuration: TimeInterval,
    currentStage: CanvasToolbarTransitionStage,
    targetStage: CanvasToolbarTransitionStage
) -> TimeInterval {
    let progress: CGFloat
    switch (currentStage, targetStage) {
    case let (.collapsing(currentProgress), .collapsing),
         let (.exiting(currentProgress), .exiting),
         let (.entering(currentProgress), .entering),
         let (.expanding(currentProgress), .expanding):
        progress = clampedToolbarTransitionProgress(currentProgress)
    default:
        progress = 0
    }

    return max(fullDuration * TimeInterval(1 - progress), 0)
}
```

## 修改二：保持 `Phase 5` 边界只做验证与收尾，不改共享配置结构

### 修改前

- `Phase 5` 计划允许调参的范围只有：
  - `collapseDuration`
  - `slideDuration`
  - `minimumContentScale`
- 但如果当前默认值没有被验证证明有问题，就不应该为了“看起来像在做 Phase 5”而随意改参数。

### 修改后

- 结合本次 `git diff` 可以确认：
  - 没有修改 `CanvasToolbarTransitionConfiguration`
  - 没有新增字段
  - 没有改阶段语义
- 本次收尾只修正了真实验证中暴露出的阶段切换时长继承 bug。
- 当前默认参数仍保持：
  - `collapseDuration = 0.18`
  - `slideDuration = 0.14`
  - `minimumContentScale = 0.78`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionState.swift
// 函数名/类型名: CanvasToolbarTransitionConfiguration.init(...)
// 功能说明: Phase 5 本次没有修改共享配置默认值，仍保持前面阶段确认过的默认参数。
struct CanvasToolbarTransitionConfiguration: Hashable, Sendable {
    var collapseDuration: TimeInterval
    var slideDuration: TimeInterval
    var minimumContentScale: CGFloat

    init(
        collapseDuration: TimeInterval = 0.18,
        slideDuration: TimeInterval = 0.14,
        minimumContentScale: CGFloat = 0.78
    ) {
        self.collapseDuration = max(collapseDuration, 0)
        self.slideDuration = max(slideDuration, 0)
        self.minimumContentScale = min(
            max(minimumContentScale, 0),
            1
        )
    }
}
```

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - 结果：无 linter 报错。
- 已执行双端构建校验，结果均通过。
- 已执行 macOS 测试套件，结果通过。

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 5 的 iOS 收尾改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase5-ios" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 对 Phase 5 的 macOS 收尾改动执行工程级构建校验。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase5-macos" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 对 Phase 5 的双端共享逻辑收尾改动执行 macOS 测试回归。
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-toolbar-phase5-tests" \
  CODE_SIGNING_ALLOWED=NO
```

```text
# 文件路径: xcodebuild test 输出摘要
# 函数名/类型名: 测试结果摘要
# 功能说明: 本次 macOS 测试套件执行成功。
** TEST SUCCEEDED **
```

- 本次没有附带模拟器或桌面运行时的肉眼动画验收记录。

## 当前结论

- 本次改动如实对应 `Phase 5` 的“验证后收尾”：
  - 先做了双端构建和测试回归
  - 再针对真实暴露的问题修正了第二段动画被错误算成 `0s` 的 bug
  - 没有更改共享 contract、字段命名或默认参数
- 当前业务代码改动仍只落在两份控制器文件：
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
