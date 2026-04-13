# 20260413_192701_raw_input_lane_phase7_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase7` business intent 继续收敛”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 `4` 个业务代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch -- <4 个关键文件>` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 只包含上述 `4` 个已跟踪文件修改
- `git diff --stat -- <4 个关键文件>` 统计为：`4 files changed, 111 insertions(+), 35 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 `4` 个业务代码文件本身

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase6` 的文本编辑 responder bridge
- pointer-heavy 的 selection / crop / drag 整体迁移
- 字符级输入可视化与 IME 组合态建模

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_192701`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取这次 raw input lane phase7 写记录前的真实工作区状态。
git status --short --branch -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"

# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
#  M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
#  M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
#  M MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计这次 phase7 关键文件的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift" \
  "MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift"

# 实际输出:
#  .../Canvas/Input/CanvasInputRoutingResolver.swift  | 47 +++++++++++++++++++---
#  .../Platform/iOS/iOSViewController.swift           | 47 +++++++++++++++-------
#  .../Platform/macOS/macOSViewController.swift       | 41 +++++++++++++------
#  .../CanvasInputRoutingResolverTests.swift          | 11 ++++-
#  4 files changed, 111 insertions(+), 35 deletions(-)
```

## 本次 phase7 的真实目标

这一步没有重复实现 `paste / undo / redo`，因为这些业务意图在前几个阶段已经通过 raw-input ingress 接通。`phase7` 真正新增的是：

1. 把 `secondary click / long press` 从“只显示 indicator + controller 自己单独做 context menu gate”的双入口，收口到 shared raw-input routing。
2. 让 `right click / long press` 在 shared 层明确降成 `.contextMenuRequest`，不再由 `iOS/macOS controller` 各自手写第二套业务判定。
3. 保留现有 context menu 展示逻辑，只把“是否允许触发 context menu”的决策入口统一到 raw-input lane。

## 修改一：`CanvasInputRoutingResolver.swift` 把 `secondary click / long press` 显式映射到 `.contextMenuRequest`

### 修改前

shared routing 之前只会给 `pointerClick` 和 `gesture` 产出 indicator event。`secondary click` 虽然能显示 `Right Click`，`long press` 虽然能显示 `Long Press`，但二者并不会在 shared 层生成 `CanvasInteractionIntent.contextMenuRequest`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver.route(_:) / CanvasPointerButton.indicatorAction / CanvasRawInputGesture.indicatorAction
// 功能说明: 修改前 pointerClick 和 gesture 只映射 indicator lane，不向 interaction lane 产出 contextMenuRequest。
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

private extension CanvasRawInputGesture {
    var indicatorAction: CanvasInputIndicatorAction {
        switch self {
        case .tap:
            return .tap
        case .longPress:
            return .longPress
        case .scroll:
            return .scroll
        case .pinch:
            return .pinch
        case .zoom:
            return .zoom
        }
    }
}
```

### 修改后

现在 shared routing 把 `pointerClick` 和 `gesture` 各自拆成独立 helper，并在扩展里显式声明：

- `pointerClick(.secondary) -> .contextMenuRequest`
- `gesture(.longPress, ...) -> .contextMenuRequest`

这意味着 `contextMenuRequest` 的入口开始真正复用 raw-input lane，而不是留在 controller 里各写一份。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: routePointerClick(_:) / routeGesture(_:) / CanvasPointerButton.routedInteractionIntent / CanvasRawInputGesture.routedInteractionIntent
// 功能说明: 修改后 secondary click 与 long press 会同时产出 indicatorEvent 和 contextMenuRequest，shared routing 开始负责这部分 business intent 归一。
struct CanvasInputRoutingResolver: Sendable {
    func route(_ rawInput: CanvasRawInputIntent) -> CanvasInputRoutingResult {
        switch rawInput {
        case .keyChord(let chord):
            return routeKeyChord(chord)
        case .pointerClick(let button):
            return routePointerClick(button)
        case .gesture(let gesture, _):
            return routeGesture(gesture)
        }
    }

    private func routePointerClick(
        _ button: CanvasPointerButton
    ) -> CanvasInputRoutingResult {
        CanvasInputRoutingResult(
            indicatorEvent: .action(button.indicatorAction),
            interactionIntent: button.routedInteractionIntent
        )
    }

    private func routeGesture(
        _ gesture: CanvasRawInputGesture
    ) -> CanvasInputRoutingResult {
        CanvasInputRoutingResult(
            indicatorEvent: .action(gesture.indicatorAction),
            interactionIntent: gesture.routedInteractionIntent
        )
    }
}

private extension CanvasPointerButton {
    var routedInteractionIntent: CanvasInteractionIntent? {
        switch self {
        case .primary:
            return nil
        case .secondary:
            return .contextMenuRequest
        }
    }
}

private extension CanvasRawInputGesture {
    var routedInteractionIntent: CanvasInteractionIntent? {
        switch self {
        case .longPress:
            return .contextMenuRequest
        case .tap,
             .scroll,
             .pinch,
             .zoom:
            return nil
        }
    }
}
```

## 修改二：`iOSViewController.swift` 的 `long press` 入口从双通道收口为单一 raw-input ingress

### 修改前

`iOS` 侧之前有两条并行链路：

- `onLongPress` 先调用 `observeRawInput(.gesture(.longPress, ...))`，只做 indicator
- `handleLongPress(at:)` 再单独手写 `handleInteractionAttempt(.contextMenuRequest, ...)`

这意味着同一个 `long press` 事实被拆成了两套入口，business gate 并不来自 shared routing。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupCanvasViewport() / handleLongPress(at:)
// 功能说明: 修改前 iOS long press 先单独观察 raw input，再在 controller 内单独做 contextMenuRequest 的 interaction gate。
canvasViewportView.onLongPress = { [weak self] location in
    self?.observeRawInput(
        .gesture(.longPress, source: .touch),
        sourceDescription: RawInputDeliverySource.longPressGesture.debugName
    )
    self?.handleLongPress(at: location)
}

private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    guard handleInteractionAttempt(
        .contextMenuRequest,
        sourceDescription: "longPress",
        continueIfAllowed: { true }
    ) else {
        dismissContextMenu()
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    prepareForLongPressContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

### 修改后

`iOS` 现在把 `long press` 入口统一收口到 `handleCapturedInput(...)`。也就是说：

- 先构造 `makeLongPressRawInput()`
- shared routing 判断它是不是 `.contextMenuRequest`
- 只有 interaction intent 确认是 `.contextMenuRequest` 时，才继续执行 `presentLongPressContextMenu(at:)`

被 policy block 时仍会关闭现有 context menu，但这个 block 判断不再是另一套独立入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: setupCanvasViewport() / handleLongPress(at:) / presentLongPressContextMenu(at:) / makeLongPressRawInput()
// 功能说明: 修改后 iOS long press 统一通过 handleCapturedInput 进入 shared routing，再由 routingResult.interactionIntent 决定是否继续展示 context menu。
canvasViewportView.onLongPress = { [weak self] location in
    self?.handleLongPress(at: location)
}

private func handleLongPress(at location: CGPoint) {
    let didContinue = handleCapturedInput(
        makeLongPressRawInput(),
        sourceDescription: RawInputDeliverySource.longPressGesture.debugName
    ) { routingResult in
        guard routingResult.interactionIntent == .contextMenuRequest else {
            return false
        }

        return presentLongPressContextMenu(at: location)
    }

    if didContinue == false {
        dismissContextMenuIfContextMenuRequestBlocked()
    }
}

private func presentLongPressContextMenu(at location: CGPoint) -> Bool {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return true
    }

    if commitActiveTextEditIfNeeded() {
        return true
    }

    prepareForLongPressContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
    return true
}

private func makeLongPressRawInput() -> CanvasRawInputIntent {
    .gesture(.longPress, source: .touch)
}
```

## 修改三：`macOSViewController.swift` 的 `secondary click` 入口从双通道收口为单一 raw-input ingress

### 修改前

`macOS` 侧之前和 `iOS` 一样，也存在两条链路：

- `onSecondaryClick` 先调用 `observeRawInput(.pointerClick(.secondary), ...)`，只做 indicator
- `handleSecondaryClick(at:)` 再单独 `handleInteractionAttempt(.contextMenuRequest, ...)`

因此 `secondary click` 到 `contextMenuRequest` 的映射仍然写死在 controller 里，而不是 raw-input lane。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupCanvasViewport() / handleSecondaryClick(at:)
// 功能说明: 修改前 macOS secondary click 先单独记录 raw input，再用 controller 自己的 interaction gate 决定是否展示 context menu。
canvasViewportView.onSecondaryClick = { [weak self] location in
    self?.observeRawInput(
        .pointerClick(.secondary),
        sourceDescription: RawInputDeliverySource.secondaryClick.debugName
    )
    self?.handleSecondaryClick(at: location)
}

private func handleSecondaryClick(at location: CGPoint) {
    guard handleInteractionAttempt(
        .contextMenuRequest,
        sourceDescription: "secondaryClick",
        continueIfAllowed: { true }
    ) else {
        dismissContextMenu()
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    prepareForSecondaryClickContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}
```

### 修改后

`macOS` 现在也统一收口到 `handleCapturedInput(...)`。同一个 `secondary click` 事实只经过一次 raw-input routing，再由 shared routing 决定是否要下沉为 `.contextMenuRequest`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: setupCanvasViewport() / handleSecondaryClick(at:) / presentSecondaryClickContextMenu(at:) / makeSecondaryClickRawInput()
// 功能说明: 修改后 macOS secondary click 统一通过 handleCapturedInput 进入 raw-input lane，并以 routingResult.interactionIntent 作为 context menu gate。
canvasViewportView.onSecondaryClick = { [weak self] location in
    self?.handleSecondaryClick(at: location)
}

private func handleSecondaryClick(at location: CGPoint) {
    let didContinue = handleCapturedInput(
        makeSecondaryClickRawInput(),
        sourceDescription: RawInputDeliverySource.secondaryClick.debugName
    ) { routingResult in
        guard routingResult.interactionIntent == .contextMenuRequest else {
            return false
        }

        return presentSecondaryClickContextMenu(at: location)
    }

    if didContinue == false {
        dismissContextMenuIfContextMenuRequestBlocked()
    }
}

private func presentSecondaryClickContextMenu(at location: CGPoint) -> Bool {
    if commitActiveTextEditIfNeeded() {
        return true
    }

    prepareForSecondaryClickContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
    return true
}

private func makeSecondaryClickRawInput() -> CanvasRawInputIntent {
    .pointerClick(.secondary)
}
```

这里保留了原有 context menu 展示与 pointer 状态清理逻辑，只把“是否允许出现 context menu”的判定入口根因收口到 raw-input lane。

## 修改四：`CanvasInputRoutingResolverTests.swift` 补齐 contextMenuRequest 的 shared routing 断言

### 修改前

测试只覆盖了：

- `paste`
- `undo / redo`
- `leftClick`
- `tap / longPress / scroll / pinch`

但其中 `longPress` 仍然被断言为 indicator-only，`secondary click` 也没有测试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testPrimaryClickRoutesOnlyToLeftClickIndicator() / testTouchLongPressRoutesOnlyToLongPressIndicator()
// 功能说明: 修改前 shared routing 测试没有覆盖 secondary click 的 contextMenuRequest，也仍把 long press 视为 indicator-only。
func testPrimaryClickRoutesOnlyToLeftClickIndicator() {
    let result = resolver.route(.pointerClick(.primary))

    XCTAssertEqual(result.indicatorEvent, .action(.leftClick))
    XCTAssertNil(result.interactionIntent)
}

func testTouchLongPressRoutesOnlyToLongPressIndicator() {
    let result = resolver.route(
        .gesture(.longPress, source: .touch)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.longPress))
    XCTAssertNil(result.interactionIntent)
}
```

### 修改后

测试现在明确验证：

- `secondary click -> rightClick + contextMenuRequest`
- `longPress -> longPress + contextMenuRequest`

从 shared 层锁住 phase7 的行为，不依赖 controller 细节。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift
// 函数名/符号名: testSecondaryClickRoutesToRightClickIndicatorAndContextMenuRequest() / testTouchLongPressRoutesToLongPressIndicatorAndContextMenuRequest()
// 功能说明: 修改后测试明确约束 secondary click 与 long press 会向 interaction lane 产出 contextMenuRequest。
func testSecondaryClickRoutesToRightClickIndicatorAndContextMenuRequest() {
    let result = resolver.route(.pointerClick(.secondary))

    XCTAssertEqual(result.indicatorEvent, .action(.rightClick))
    XCTAssertEqual(result.interactionIntent, .contextMenuRequest)
}

func testTouchLongPressRoutesToLongPressIndicatorAndContextMenuRequest() {
    let result = resolver.route(
        .gesture(.longPress, source: .touch)
    )

    XCTAssertEqual(result.indicatorEvent, .action(.longPress))
    XCTAssertEqual(result.interactionIntent, .contextMenuRequest)
}
```

## 验证结果

`ReadLints` 检查以下文件，无新增诊断：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests.swift`

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase7 的 macOS Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase7-macos"

# 实际结果: BUILD SUCCEEDED
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 phase7 的 iOS Simulator Debug 构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase7-ios"

# 实际结果: BUILD SUCCEEDED
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 定向验证 CanvasInputRoutingResolverTests 的 phase7 shared routing 断言。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_Ver_0-phase7-tests" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasInputRoutingResolverTests"

# 实际结果摘录:
# /Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift:28:22: error: cannot assign to property: 'updatedAt' is a get-only property
# Testing cancelled because the build failed.
```

定向测试本次依然没有真正执行到测试运行阶段，但从构建日志可见：

- `CanvasInputRoutingResolverTests.swift` 已成功进入 `SwiftCompile`
- 阻断点仍是仓库里既有的 `BoardVideoStorageTests.swift`
- 这不是本次 phase7 新改动引入的错误

## 本次保持的边界

1. `phase7` 只迁移 `secondary click / long press -> contextMenuRequest`，没有把 selection / crop / drag 整体迁到 raw-input lane。
2. `paste / undo / redo` 继续沿用前几个阶段已经收口好的路径，这次没有重复改写。
3. 文本编辑态 responder bridge 仍按 `phase6` 的边界工作；文本编辑态快捷键依旧只镜像 indicator，不把文本编辑里的业务动作误下沉成 canvas command。
4. context menu 的展示、布局、action resolver 与 command 执行逻辑没有重写，这次只改输入入口的统一收敛方式。
